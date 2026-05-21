#!/usr/bin/env bash
# =============================================================================
# c3_lateral_movement.sh
#
# Test de eficacia de NetworkPolicy (C3). Despliega un pod atacante SIN labels
# privilegiados y mide si las conexiones que la policy debe denegar son
# efectivamente bloqueadas a nivel CNI (Calico → iptables/eBPF en kernel).
#
# Modela:
#   - movimiento lateral: atacante intenta saltar api-service y llegar
#     directo a data-service o postgres (T1021/T1570, OWASP A05/A07).
#   - exfiltración: api-service intentando egress a Internet
#     (variante strict).
#   - dependencia externa legítima: api-service intentando consumir un endpoint
#     HTTP público simple. Esto cuantifica el costo operacional de strict.
#
# Probes:
#   P1: attacker → data-service:8080/products  (debe bloquearse en basic+strict)
#   P2: attacker → postgres:5432               (debe bloquearse en basic+strict)
#   P3: api-service → 1.1.1.1:443              (debe bloquearse SOLO en strict)
#   P4: api-service → example.com:80 (HTTP)    (debe bloquearse SOLO en strict)
#
# Criterio binario:
#   passed  = conexión exitosa (HTTP 200 / TCP open)
#   blocked = curl exit != 0 ó timeout ó código != 200
#
# Uso:
#   bash scripts/c3_lateral_movement.sh <scenario_label> [attempts]
#
# Salida CSV:
#   scenario,probe,target,attempts,blocked,passed,mitigation_rate
# =============================================================================
set -euo pipefail

LABEL="${1:-unknown}"
ATTEMPTS="${2:-10}"
NS="realistic"
ATTACKER_NAME="c3-attacker-$(date +%s)"
LOG_DIR="${LOG_DIR:-Testing/results/c3_lateral_movement}"
mkdir -p "${LOG_DIR}"

log() { echo "[c3-lateral] $*" >&2; }

kubectl -n "${NS}" delete pod -l role=c3-attacker --ignore-not-found --grace-period=0 --force >/dev/null 2>&1 || true

log "desplegando atacante (${ATTACKER_NAME}) en ns=${NS}"

cat <<EOF | kubectl apply -f - >/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: ${ATTACKER_NAME}
  namespace: ${NS}
  labels:
    role: c3-attacker
  annotations:
    sidecar.istio.io/inject: "false"
    linkerd.io/inject: disabled
spec:
  restartPolicy: Never
  containers:
    - name: attacker
      image: curlimages/curl:8.5.0
      command: ["sh", "-c", "sleep 600"]
EOF

PHASE=""
for i in $(seq 1 30); do
  PHASE=$(kubectl -n "${NS}" get pod "${ATTACKER_NAME}" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
  READY=$(kubectl -n "${NS}" get pod "${ATTACKER_NAME}" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || echo "false")
  [[ "$PHASE" == "Running" && "$READY" == "true" ]] && break
  sleep 1
done
if [[ "$PHASE" != "Running" ]]; then
  log "ERROR: atacante no Ready (phase=${PHASE})"
  kubectl -n "${NS}" delete pod "${ATTACKER_NAME}" --grace-period=0 --force >/dev/null 2>&1 || true
  exit 1
fi
log "atacante Ready"

OUT_CSV="${LOG_DIR}/${LABEL}_summary.csv"
echo "scenario,probe,target,attempts,blocked,passed,mitigation_rate" > "${OUT_CSV}"

# -----------------------------------------------------------------------------
# Helper: ejecuta N intentos curl HTTP desde el atacante y resume.
# -----------------------------------------------------------------------------
probe_http() {
  local probe="$1"; local target="$2"; local url="$3"
  local raw="${LOG_DIR}/${LABEL}_${probe}_raw.csv"
  echo "i,http_code,curl_exit" > "${raw}"
  log "${probe} → ${target} (${ATTEMPTS} intentos, HTTP)"
  local blocked=0 passed=0
  for i in $(seq 1 "${ATTEMPTS}"); do
    set +e
    OUT=$(kubectl -n "${NS}" exec "${ATTACKER_NAME}" -- \
      curl -s -o /dev/null -m 3 -w "%{http_code}" "${url}" 2>/dev/null)
    EC=$?
    set -e
    OUT="${OUT:-000}"
    echo "${i},${OUT},${EC}" >> "${raw}"
    if [[ "${OUT}" == "200" ]]; then passed=$((passed+1)); else blocked=$((blocked+1)); fi
  done
  local total=$((blocked+passed)) rate=0
  [[ $total -gt 0 ]] && rate=$(awk "BEGIN{printf \"%.2f\", ${blocked}*100/${total}}")
  echo "${LABEL},${probe},${target},${total},${blocked},${passed},${rate}" | tee -a "${OUT_CSV}"
}

# -----------------------------------------------------------------------------
# Helper: TCP raw connect (postgres no habla HTTP).
# -----------------------------------------------------------------------------
probe_tcp() {
  local probe="$1"; local target="$2"; local host="$3"; local port="$4"
  local raw="${LOG_DIR}/${LABEL}_${probe}_raw.csv"
  echo "i,curl_exit" > "${raw}"
  log "${probe} → ${target} (${ATTEMPTS} intentos, TCP)"
  local blocked=0 passed=0
  for i in $(seq 1 "${ATTEMPTS}"); do
    set +e
    # nc -z (zero-I/O scan): exit 0 si TCP handshake ok, !=0 si bloqueado/timeout.
    # La imagen curlimages/curl trae busybox nc.
    kubectl -n "${NS}" exec "${ATTACKER_NAME}" -- \
      nc -z -w 3 "${host}" "${port}" >/dev/null 2>&1
    EC=$?
    set -e
    echo "${i},${EC}" >> "${raw}"
    if [[ ${EC} -eq 0 ]]; then passed=$((passed+1)); else blocked=$((blocked+1)); fi
  done
  local total=$((blocked+passed)) rate=0
  [[ $total -gt 0 ]] && rate=$(awk "BEGIN{printf \"%.2f\", ${blocked}*100/${total}}")
  echo "${LABEL},${probe},${target},${total},${blocked},${passed},${rate}" | tee -a "${OUT_CSV}"
}

# -----------------------------------------------------------------------------
# Helper: egress desde api-service hacia Internet (P3 strict-only).
# Usa kubectl exec sobre el pod api-service. Si no tiene curl, usa wget/nc.
# -----------------------------------------------------------------------------
probe_api_egress() {
  local probe="P3"; local target="api->internet"
  local raw="${LOG_DIR}/${LABEL}_${probe}_raw.csv"
  echo "i,exit_code" > "${raw}"
  local pod
  pod=$(kubectl -n "${NS}" get pod -l app=api-service -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
  if [[ -z "${pod}" ]]; then
    log "WARN: api-service pod no encontrado, saltando P3"
    echo "${LABEL},${probe},${target},0,0,0,NA" | tee -a "${OUT_CSV}"
    return
  fi
  log "${probe} → ${target} (api-service=${pod}, ${ATTEMPTS} intentos)"
  local blocked=0 passed=0
  for i in $(seq 1 "${ATTEMPTS}"); do
    set +e
    # Intenta conexión TCP a 1.1.1.1:443 vía bash /dev/tcp builtin.
    # api-service trae bash pero NO curl/wget/nc. Usamos bash explícito
    # (sh=dash no soporta /dev/tcp).
    kubectl -n "${NS}" exec "${pod}" -c api-service -- \
      bash -c 'timeout 3 bash -c "echo > /dev/tcp/1.1.1.1/443"' >/dev/null 2>&1
    EC=$?
    set -e
    echo "${i},${EC}" >> "${raw}"
    if [[ ${EC} -eq 0 ]]; then passed=$((passed+1)); else blocked=$((blocked+1)); fi
  done
  local total=$((blocked+passed)) rate=0
  [[ $total -gt 0 ]] && rate=$(awk "BEGIN{printf \"%.2f\", ${blocked}*100/${total}}")
  echo "${LABEL},${probe},${target},${total},${blocked},${passed},${rate}" | tee -a "${OUT_CSV}"
}

# -----------------------------------------------------------------------------
# Helper: dependencia externa legítima vía HTTP simple.
# Usa Python stdlib dentro de api-service para resolver DNS, abrir socket TCP y
# verificar que el peer remoto responda con una línea HTTP. Mide costo
# operacional: strict debería bloquear este flujo aunque no sea malicioso.
# -----------------------------------------------------------------------------
probe_api_external_http() {
  local probe="P4"; local target="api->example.com-http"
  local raw="${LOG_DIR}/${LABEL}_${probe}_raw.csv"
  echo "i,exit_code" > "${raw}"
  local pod
  pod=$(kubectl -n "${NS}" get pod -l app=api-service -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
  if [[ -z "${pod}" ]]; then
    log "WARN: api-service pod no encontrado, saltando P4"
    echo "${LABEL},${probe},${target},0,0,0,NA" | tee -a "${OUT_CSV}"
    return
  fi
  log "${probe} → ${target} (api-service=${pod}, ${ATTEMPTS} intentos)"
  local blocked=0 passed=0
  for i in $(seq 1 "${ATTEMPTS}"); do
    set +e
    kubectl -n "${NS}" exec -i "${pod}" -c api-service -- python3 - <<'PY' >/dev/null 2>&1
import socket, sys

host = "example.com"
port = 80
request = b"GET / HTTP/1.1\r\nHost: example.com\r\nConnection: close\r\n\r\n"

try:
    sock = socket.create_connection((host, port), timeout=3)
    sock.sendall(request)
    data = sock.recv(64)
    sock.close()
    if data.startswith(b"HTTP/"):
        sys.exit(0)
    sys.exit(2)
except Exception:
    sys.exit(1)
PY
    EC=$?
    set -e
    echo "${i},${EC}" >> "${raw}"
    if [[ ${EC} -eq 0 ]]; then passed=$((passed+1)); else blocked=$((blocked+1)); fi
  done
  local total=$((blocked+passed)) rate=0
  [[ $total -gt 0 ]] && rate=$(awk "BEGIN{printf \"%.2f\", ${blocked}*100/${total}}")
  echo "${LABEL},${probe},${target},${total},${blocked},${passed},${rate}" | tee -a "${OUT_CSV}"
}

# -----------------------------------------------------------------------------
# Ejecutar 4 probes
# -----------------------------------------------------------------------------
probe_http "P1" "data-service" "http://data-service.${NS}.svc.cluster.local:8080/products"
probe_tcp  "P2" "postgres"     "postgres.${NS}.svc.cluster.local" "5432"
probe_api_egress
probe_api_external_http

kubectl -n "${NS}" delete pod "${ATTACKER_NAME}" --grace-period=0 --force >/dev/null 2>&1 || true
log "summary -> ${OUT_CSV}"
