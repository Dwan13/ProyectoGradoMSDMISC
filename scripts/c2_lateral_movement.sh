#!/usr/bin/env bash
# =============================================================================
# c2_lateral_movement.sh
#
# Test de eficacia de mTLS. Despliega un pod sin identidad mTLS (sin sidecar)
# y mide cuántos intentos hacia data-service (backend puro intra-cluster) son
# bloqueados. auth-service NO es target porque actúa como front-door público
# de autenticación (debe aceptar tráfico externo legítimo).
# Modela movimiento lateral post-compromiso (MITRE ATT&CK T1021/T1570,
# OWASP A07:2021).
#
# Uso:
#   bash scripts/c2_lateral_movement.sh <scenario_label> [attempts]
#
# Salida CSV:
#   scenario,target,attempts,blocked,passed,mitigation_rate
# =============================================================================
set -euo pipefail

LABEL="${1:-unknown}"
ATTEMPTS="${2:-100}"
NS="realistic"
ATTACKER_NAME="c2-attacker-$(date +%s)"
LOG_DIR="${LOG_DIR:-Testing/results/c2_lateral_movement}"
mkdir -p "${LOG_DIR}"

log() { echo "[c2-lateral] $*" >&2; }

kubectl -n "${NS}" delete pod -l role=c2-attacker --ignore-not-found --grace-period=0 --force >/dev/null 2>&1 || true

log "desplegando atacante sin sidecar (${ATTACKER_NAME}) en ns=${NS}"

cat <<EOF | kubectl apply -f - >/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: ${ATTACKER_NAME}
  namespace: ${NS}
  labels:
    role: c2-attacker
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
NCONT=$(kubectl -n "${NS}" get pod "${ATTACKER_NAME}" -o jsonpath='{.spec.containers[*].name}' | wc -w)
log "atacante listo (containers=${NCONT}, esperado 1 sin sidecar)"

# Target: GET /products en data-service.
# Justificación:
#  - En baseline (sin mTLS) retorna HTTP 200 con datos sensibles -> demuestra
#    exfiltración efectiva por movimiento lateral.
#  - En mTLS strict el sidecar/proxy rechaza la conexión del atacante sin
#    identidad antes de llegar a la app.
#  - No usamos /health porque Linkerd lo permite por la probe-default-route
#    (kubelet healthchecks), invalidando el test.
#  - No usamos /login porque retorna 401 desde la app (credenciales inválidas)
#    incluso en baseline, contaminando la métrica de mitigación.
# Criterio binario:
#   passed  = HTTP 200 (atacante exfiltró datos)
#   blocked = cualquier otra cosa (curl_exit!=0, 4xx, 5xx)
TARGETS=(
  "data-service|GET|http://data-service.${NS}.svc.cluster.local:8080/products"
)

OUT_CSV="${LOG_DIR}/${LABEL}_summary.csv"
echo "scenario,target,attempts,blocked,passed,mitigation_rate" > "${OUT_CSV}"

for entry in "${TARGETS[@]}"; do
  IFS='|' read -r TARGET METHOD URL <<<"${entry}"
  RAW="${LOG_DIR}/${LABEL}_${TARGET}_raw.csv"
  echo "i,http_code,curl_exit" > "${RAW}"
  log "atacando ${TARGET} (${METHOD} ${ATTEMPTS} intentos)..."

  blocked=0; passed=0
  for i in $(seq 1 "${ATTEMPTS}"); do
    set +e
    if [[ "${METHOD}" == "POST" ]]; then
      OUT=$(kubectl -n "${NS}" exec "${ATTACKER_NAME}" -- \
        curl -s -o /dev/null -m 3 -w "%{http_code}" \
        -X POST -H "Content-Type: application/json" -d '{"username":"x","password":"y"}' \
        "${URL}" 2>/dev/null)
    else
      OUT=$(kubectl -n "${NS}" exec "${ATTACKER_NAME}" -- \
        curl -s -o /dev/null -m 3 -w "%{http_code}" "${URL}" 2>/dev/null)
    fi
    EC=$?
    set -e
    OUT="${OUT:-000}"
    echo "${i},${OUT},${EC}" >> "${RAW}"
    # passed estricto: HTTP 200 = atacante recibió datos de la app
    # blocked: cualquier otra cosa (curl error, 4xx, 5xx, 000)
    if [[ "$OUT" == "200" ]]; then
      passed=$((passed + 1))
    else
      blocked=$((blocked + 1))
    fi
  done

  total=$((blocked + passed))
  rate=0
  [[ $total -gt 0 ]] && rate=$(awk "BEGIN{printf \"%.2f\", ${blocked}*100/${total}}")
  echo "${LABEL},${TARGET},${total},${blocked},${passed},${rate}" | tee -a "${OUT_CSV}"
done

kubectl -n "${NS}" delete pod "${ATTACKER_NAME}" --grace-period=0 --force >/dev/null 2>&1 || true
log "summary -> ${OUT_CSV}"
