#!/usr/bin/env bash
# ============================================================================
# run-crud-experiment.sh
#
# Orquestador del experimento CRUD completo (Create/Read/Update/Delete sobre
# /products) para los 3 escenarios C1 (gateways API):
#   - C1/baseline (nginx-ingress)   → realistic-nginx ns,  HTTPS NodePort 32167, host realistic.local
#   - C1/kong     (kong-ingress)    → realistic-kong  ns,  HTTPS NodePort 30443, host realistic.local
#   - C1/istio    (istio-gateway)   → realistic-istio ns,  HTTPS NodePort 32012, host realistic-istio.local
#
# Cada escenario tiene su propio namespace, Postgres y cert TLS:
#   experiments/01-api-gateway-realistic/{baseline,kong,istio}/
#
# Uso:
#   bash scripts/run-crud-experiment.sh --vus 20 --replicas 5 --duration 60s
#   bash scripts/run-crud-experiment.sh --scenario kong   # solo uno
# ============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
K6_SCRIPT="${ROOT_DIR}/RealisticServices/k6/realistic-crud-flow.js"

# --- Defaults ----------------------------------------------------------------
VUS=20
REPLICAS=5
DURATION="60s"
WARMUP="10"         # segundos de calentamiento previo a cada escenario (10s mínimo recomendado)
SCENARIO_FILTER=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --vus)       VUS="$2"; shift 2 ;;
    --replicas)  REPLICAS="$2"; shift 2 ;;
    --duration)  DURATION="$2"; shift 2 ;;
    --warmup)    WARMUP="${2%s}"; shift 2 ;;
    --scenario)  SCENARIO_FILTER="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

STAMP="$(date +%Y%m%d_%H%M%S)"
RUN_DIR="${ROOT_DIR}/Testing/results/auto_runs/crud_vus${VUS}_n${REPLICAS}_${STAMP}"
STATE_DIR="${RUN_DIR}/state"
SUMMARY_DIR="${RUN_DIR}/summaries"
LOG_DIR="${RUN_DIR}/logs"
mkdir -p "$STATE_DIR" "$SUMMARY_DIR" "$LOG_DIR"

INVALID_CSV="${RUN_DIR}/invalid-scenarios.csv"
echo "timestamp,control,variant,vus,replica,reason" > "$INVALID_CSV"
RESOURCE_CSV="${RUN_DIR}/resource_metrics.csv"
echo "control,variant,vus,replica,cpu_total_m,mem_total_Mi" > "$RESOURCE_CSV"

log()  { echo -e "\033[0;34m[crud]\033[0m $(date +%H:%M:%S) $*"; }
ok()   { echo -e "\033[0;32m[ ok ]\033[0m $*"; }
warn() { echo -e "\033[1;33m[warn]\033[0m $*"; }
err()  { echo -e "\033[0;31m[fail]\033[0m $*"; }

log "Run dir:  ${RUN_DIR}"
log "Config:   VUS=${VUS}  REPLICAS=${REPLICAS}  DURATION=${DURATION}  WARMUP=${WARMUP}s"
log "k6 script: ${K6_SCRIPT}"

# --- Manifiestos por escenario (aislados, cada uno con su ns + postgres + tls)
C1_DIR="${ROOT_DIR}/experiments/01-api-gateway-realistic"
C2_DIR="${ROOT_DIR}/experiments/02-mtls-service-mesh-realistic"
C3_DIR="${ROOT_DIR}/experiments/03-network-policies-realistic"
C4_DIR="${ROOT_DIR}/experiments/04-rate-limiting-realistic"

# --- Definición de escenarios -----------------------------------------------
# Formato: "control variant ns host port"
# El directorio de manifiestos se deriva de control (C1 -> C1_DIR, C2 -> C2_DIR).
SCENARIOS=(
  "C1 baseline   realistic-nginx        realistic.local              32167"
  "C1 kong       realistic-kong         realistic.local              30443"
  "C1 istio      realistic-istio        realistic-istio.local        32012"
  "C2 baseline   realistic-without-mtls realistic-without-mtls.local 32167"
  "C2 istio-mtls   realistic-istio-mtls   realistic-istio-mtls.local   32012"
  "C2 linkerd-mtls realistic-linkerd-mtls realistic-linkerd-mtls.local 32167"
  "C3 baseline   realistic-without-network-policies realistic-without-network-policies.local 32167"
  "C3 basic      realistic-basic-network-policies   realistic-basic-network-policies.local   32167"
  "C3 strict     realistic-strict-network-policies  realistic-strict-network-policies.local  32167"
  "C4 baseline   realistic-without-rate-limiting    realistic-without-rate-limiting.local    32167"
  "C4 moderate   realistic-moderate-rate-limiting   realistic-moderate-rate-limiting.local   32167"
  "C4 strict     realistic-strict-rate-limiting     realistic-strict-rate-limiting.local     32167"
)

kctl() {
  if command -v microk8s >/dev/null 2>&1; then
    microk8s kubectl "$@"
  else
    kubectl "$@"
  fi
}

apply_scenario() {
  local ctrl="$1" var="$2"
  local base
  case "$ctrl" in
    C1) base="$C1_DIR" ;;
    C2) base="$C2_DIR" ;;
    C3) base="$C3_DIR" ;;
    C4) base="$C4_DIR" ;;
    *)  err "control desconocido: $ctrl"; return 1 ;;
  esac
  local dir="${base}/${var}"
  log "Aplicando manifiestos de ${dir}"
  if [[ -d "${dir}/namespace" ]]; then
    kctl apply -f "${dir}/namespace/" >/dev/null
  fi
  for f in "${dir}"/*.yaml; do
    [[ -f "$f" ]] && kctl apply -f "$f" >/dev/null
  done
}

wait_rollout() {
  local ns="$1"
  local failed=0
  for d in auth-service api-service data-service postgres; do
    if ! kctl -n "$ns" rollout status deploy/"$d" --timeout=240s >/dev/null 2>&1; then
      err "rollout $d en $ns NO completó en 240s"
      kctl -n "$ns" get pods -l app="$d" -o wide 2>/dev/null | sed 's/^/         /'
      failed=1
    fi
  done
  # Espera adicional: todas las pods Ready (no solo Available).
  # Usa split() porque awk POSIX no soporta backreferences en regex.
  local tries=24
  for ((i=1;i<=tries;i++)); do
    local not_ready
    not_ready=$(kctl -n "$ns" get pods --no-headers 2>/dev/null \
      | awk '{split($2,a,"/"); if (a[1]!=a[2] || $3!~/Running|Completed/) print}' \
      | wc -l)
    [[ "$not_ready" -eq 0 ]] && return $failed
    sleep 5
  done
  warn "$ns aún tiene pods no-Ready tras 120s extra"
  return $failed
}

# Garantiza que los sidecars (Envoy/Linkerd) estén inyectados en los pods.
# Tras `kubectl label namespace ... injection=enabled`, los pods existentes
# NO reciben sidecar; hay que reiniciarlos. Sin este paso, C2/*-mtls corre
# sin mTLS aunque las policies digan STRICT.
ensure_sidecars() {
  local ns="$1" var="$2"
  local expected_containers
  case "$var" in
    istio-mtls)   expected_containers="istio-proxy" ;;
    linkerd-mtls) expected_containers="linkerd-proxy" ;;
    *) return 0 ;;
  esac
  # Verifica si algún pod NO tiene el sidecar esperado
  local missing
  missing=$(kctl -n "$ns" get pods -o json 2>/dev/null \
    | python3 -c "
import json,sys
d=json.load(sys.stdin)
bad=[]
for p in d.get('items',[]):
    cs=[c['name'] for c in p['spec'].get('containers',[])]
    if '${expected_containers}' not in cs:
        bad.append(p['metadata']['name'])
print(' '.join(bad))
" 2>/dev/null || true)
  if [[ -n "$missing" ]]; then
    warn "sidecar ${expected_containers} faltante en: $missing → reiniciando deployments"
    kctl -n "$ns" rollout restart deploy >/dev/null 2>&1 || true
    wait_rollout "$ns"
    # Re-verifica
    missing=$(kctl -n "$ns" get pods -o json 2>/dev/null \
      | python3 -c "
import json,sys
d=json.load(sys.stdin)
bad=[]
for p in d.get('items',[]):
    cs=[c['name'] for c in p['spec'].get('containers',[])]
    if '${expected_containers}' not in cs:
        bad.append(p['metadata']['name'])
print(' '.join(bad))
" 2>/dev/null || true)
    if [[ -n "$missing" ]]; then
      err "sidecar ${expected_containers} sigue ausente en: $missing"
      return 1
    fi
  fi
  ok "sidecar ${expected_containers} presente en todos los pods de ${ns}"
  return 0
}

# Valida que el control realmente esté activo (no solo que los manifests se
# aplicaran). Cada control tiene una invariante observable distinta.
validate_control() {
  local ctrl="$1" var="$2" ns="$3" host="$4" port="$5"
  case "$ctrl" in
    C2)
      if [[ "$var" == "istio-mtls" || "$var" == "linkerd-mtls" ]]; then
        ensure_sidecars "$ns" "$var" || return 1
        # Verifica PeerAuthentication STRICT (Istio) o anotación inject (Linkerd)
        if [[ "$var" == "istio-mtls" ]]; then
          local mode
          mode=$(kctl -n "$ns" get peerauthentication -o jsonpath='{.items[*].spec.mtls.mode}' 2>/dev/null)
          [[ "$mode" == *STRICT* ]] && ok "PeerAuthentication STRICT activo en $ns" \
                                    || warn "PeerAuthentication no STRICT en $ns (mode='$mode')"
        fi
      fi
      ;;
    C3)
      # NetworkPolicies deben existir si la variante no es baseline
      if [[ "$var" != "baseline" ]]; then
        local n_pols
        n_pols=$(kctl -n "$ns" get netpol --no-headers 2>/dev/null | wc -l)
        if [[ "$n_pols" -lt 1 ]]; then
          err "C3/$var: NetworkPolicy esperada en $ns pero hay $n_pols"
          return 1
        fi
        ok "C3/$var: $n_pols NetworkPolicies activas"
      fi
      ;;
    C4)
      # Verifica que el ingress tenga la annotation de rate-limit
      if [[ "$var" != "baseline" ]]; then
        local has_limit
        has_limit=$(kctl -n "$ns" get ingress -o jsonpath='{.items[*].metadata.annotations.nginx\.ingress\.kubernetes\.io/limit-rpm}' 2>/dev/null)
        if [[ -z "$has_limit" ]]; then
          warn "C4/$var: ingress sin annotation limit-rpm (puede usar otra forma)"
        else
          ok "C4/$var: limit-rpm=$has_limit en ingress"
        fi
      fi
      ;;
  esac
  return 0
}

smoke_check() {
  local host="$1" port="$2"
  local tries=15
  for ((i=1;i<=tries;i++)); do
    local resp
    resp=$(curl -k -sS -m 6 \
      --resolve "${host}:${port}:127.0.0.1" \
      -X POST "https://${host}:${port}/auth/login" \
      -H 'Content-Type: application/json' \
      -d '{"username":"demo","password":"demo123"}' 2>/dev/null || true)
    if [[ "$resp" == *'"access_token"'* ]]; then
      return 0
    fi
    sleep 2
  done
  return 1
}

warmup_phase() {
  # Tráfico legitimo continuo durante $WARMUP segundos para estabilizar
  # caches (Postgres buffers, pools FastAPI, config reload de ingress, JIT).
  local host="$1" port="$2" secs="$3"
  [[ "$secs" -le 0 ]] && return 0
  log "warmup ${secs}s sobre ${host}:${port}"
  local token
  token=$(curl -k -sS -m 6 --resolve "${host}:${port}:127.0.0.1" \
    -X POST "https://${host}:${port}/auth/login" \
    -H 'Content-Type: application/json' \
    -d '{"username":"demo","password":"demo123"}' \
    | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))' 2>/dev/null || true)
  if [[ -z "$token" ]]; then
    warn "warmup sin token, omitido"
    return 0
  fi
  local end=$(( $(date +%s) + secs ))
  local n=0
  while [[ $(date +%s) -lt $end ]]; do
    curl -k -s -m 4 --resolve "${host}:${port}:127.0.0.1" \
      -H "Authorization: Bearer ${token}" \
      "https://${host}:${port}/api/products" >/dev/null 2>&1 || true
    n=$((n+1))
  done
  ok "warmup done (${n} requests)"
}

dump_state() {
  local var="$1" ns="$2" ctrl="${3:-C1}"
  local f="${STATE_DIR}/${ctrl}_${var}.yaml"
  {
    echo "# Estado efectivo del cluster tras aplicar ${ctrl}/${var} (ns=${ns})"
    echo "# Captura: $(date -Iseconds)"
    echo "---"
    kctl -n "$ns" get deploy,svc,ingress -o yaml 2>/dev/null || true
    echo "---"
    kctl -n "$ns" get gateway.networking.istio.io,virtualservice 2>/dev/null \
      | sed '/^No resources/d' || true
    echo "---"
    kctl -n "$ns" get pod -o wide 2>/dev/null || true
  } > "$f"
}

collect_resources() {
  local ns="$1" ctrl="$2" var="$3" rep="$4"
  local cpu_total=0 mem_total=0
  while read -r pod cpu mem _; do
    [[ -z "$pod" ]] && continue
    local cpu_val=${cpu%m}; local mem_val=${mem%Mi}
    [[ "$cpu_val" =~ ^[0-9]+$ ]] || cpu_val=0
    [[ "$mem_val" =~ ^[0-9]+$ ]] || mem_val=0
    cpu_total=$((cpu_total + cpu_val))
    mem_total=$((mem_total + mem_val))
  done < <(kctl top pods -n "$ns" --no-headers 2>/dev/null | awk '/api-service|auth-service|data-service|postgres/ {print $1, $2, $3}')
  echo "${ctrl},${var},${VUS},${rep},${cpu_total},${mem_total}" >> "$RESOURCE_CSV"
}

# --- Filtrado opcional ------------------------------------------------------
FILTERED=()
if [[ -n "$SCENARIO_FILTER" ]]; then
  IFS=',' read -ra FILTERS <<< "$SCENARIO_FILTER"
  for SC in "${SCENARIOS[@]}"; do
    for F in "${FILTERS[@]}"; do
      if [[ "$SC" == *"$F"* ]]; then FILTERED+=("$SC"); break; fi
    done
  done
else
  FILTERED=("${SCENARIOS[@]}")
fi

TOTAL=$(( ${#FILTERED[@]} * REPLICAS ))
COUNT=0

# ============================================================================
# Main loop
# ============================================================================
for SC in "${FILTERED[@]}"; do
  read -r CTRL VAR NS HOST PORT <<<"$SC"
  log "================ ${CTRL} / ${VAR}  (ns=${NS}, ${HOST}:${PORT}) ================"

  apply_scenario "$CTRL" "$VAR"
  if ! wait_rollout "$NS"; then
    err "rollout incompleto en $NS → escenario omitido (${REPLICAS} réplicas perdidas)"
    for ((r=1;r<=REPLICAS;r++)); do
      printf "%s,%s,%s,%s,%s,%s\n" "$(date -Iseconds)" "$CTRL" "$VAR" "$VUS" "$r" "rollout_failed" >> "$INVALID_CSV"
      COUNT=$((COUNT+1))
    done
    continue
  fi

  if ! validate_control "$CTRL" "$VAR" "$NS" "$HOST" "$PORT"; then
    err "validación de control falló para $CTRL/$VAR → escenario omitido"
    for ((r=1;r<=REPLICAS;r++)); do
      printf "%s,%s,%s,%s,%s,%s\n" "$(date -Iseconds)" "$CTRL" "$VAR" "$VUS" "$r" "control_validation_failed" >> "$INVALID_CSV"
      COUNT=$((COUNT+1))
    done
    continue
  fi

  if ! smoke_check "$HOST" "$PORT"; then
    err "smoke FAIL ${CTRL}/${VAR} → escenario omitido (${REPLICAS} réplicas perdidas)"
    for ((r=1;r<=REPLICAS;r++)); do
      printf "%s,%s,%s,%s,%s,%s\n" "$(date -Iseconds)" "$CTRL" "$VAR" "$VUS" "$r" "smoke_failed" >> "$INVALID_CSV"
      COUNT=$((COUNT+1))
    done
    continue
  fi
  ok "smoke OK (${HOST}:${PORT})"
  warmup_phase "$HOST" "$PORT" "$WARMUP"
  dump_state "$VAR" "$NS" "$CTRL"

  AUTH_BASE="https://${HOST}:${PORT}/auth"
  API_BASE="https://${HOST}:${PORT}/api"
  RESOLVE="${HOST}:127.0.0.1"

  for ((r=1;r<=REPLICAS;r++)); do
    COUNT=$((COUNT+1))
    SUM="${SUMMARY_DIR}/${CTRL}_${VAR}_rep${r}.json"
    LOG="${LOG_DIR}/${CTRL}_${VAR}_rep${r}.log"
    log "[${COUNT}/${TOTAL}] ${CTRL}/${VAR} replica=${r}"

    set +e
    k6 run \
      -e AUTH_BASE="$AUTH_BASE" \
      -e API_BASE="$API_BASE" \
      -e RESOLVE="$RESOLVE" \
      -e K6_INSECURE_SKIP_TLS_VERIFY=true \
      --vus "$VUS" --duration "$DURATION" \
      --summary-export "$SUM" \
      "$K6_SCRIPT" >"$LOG" 2>&1
    rc=$?
    set -e
    [[ $rc -ne 0 ]] && warn "k6 exit=$rc (ver $LOG)"

    collect_resources "$NS" "$CTRL" "$VAR" "$r"
  done
done

# --- Consolidar -------------------------------------------------------------
log "Consolidando resultados → ${RUN_DIR}/results.csv"

python3 - <<PY
import json, csv, os, glob, re
sum_dir = "${SUMMARY_DIR}"
out = "${RUN_DIR}/results.csv"
res_metrics = {}
res_file = "${RESOURCE_CSV}"
if os.path.exists(res_file):
    with open(res_file) as f:
        next(f, None)
        for line in f:
            parts = line.strip().split(",")
            if len(parts) == 6:
                ctrl, var, vus, rep, cpu, mem = parts
                res_metrics[(ctrl, var, vus, rep)] = (cpu, mem)

rows = []
for fp in sorted(glob.glob(os.path.join(sum_dir, "*.json"))):
    m = re.match(r"(C\d)_([\w-]+)_rep(\d+)\.json$", os.path.basename(fp))
    if not m: continue
    ctrl, var, rep = m.group(1), m.group(2), str(int(m.group(3)))
    try:
        d = json.load(open(fp))
    except Exception as e:
        print("skip", fp, e); continue
    M = d.get("metrics", {})
    def g(k, sub):
        try: return M[k][sub]
        except: return None
    def cnt(k):
        try: return M[k]["count"]
        except: return 0
    cpu, mem = res_metrics.get((ctrl, var, str(${VUS}), rep), ("", ""))
    rows.append({
        "control": ctrl, "variant": var, "vus": ${VUS}, "replica": int(rep),
        "avg_ms":  round(g("http_req_duration","avg") or 0, 3),
        "p95_ms":  round(g("http_req_duration","p(95)") or 0, 3),
        "err_pct": round((g("http_req_failed","rate") or 0) * 100, 3),
        "rps":     round(g("http_reqs","rate") or 0, 3),
        "checks_pct": round((g("checks","rate") or 0) * 100, 3),
        "create_ok":   cnt("crud_create_success_total"),
        "create_fail": cnt("crud_create_fail_total"),
        "read_ok":     cnt("crud_read_success_total"),
        "read_fail":   cnt("crud_read_fail_total"),
        "update_ok":   cnt("crud_update_success_total"),
        "update_fail": cnt("crud_update_fail_total"),
        "delete_ok":   cnt("crud_delete_success_total"),
        "delete_fail": cnt("crud_delete_fail_total"),
        "list_ok":     cnt("crud_list_success_total"),
        "create_p95_ms": round(g("crud_create_latency_ms","p(95)") or 0, 3),
        "read_p95_ms":   round(g("crud_read_latency_ms","p(95)") or 0, 3),
        "update_p95_ms": round(g("crud_update_latency_ms","p(95)") or 0, 3),
        "delete_p95_ms": round(g("crud_delete_latency_ms","p(95)") or 0, 3),
        "cpu_total_m":  cpu,
        "mem_total_Mi": mem,
    })

if rows:
    with open(out, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader(); w.writerows(rows)
    print(f"wrote {len(rows)} rows -> {out}")
else:
    print("no rows extracted")
PY

ok "Run completo. Resultados: ${RUN_DIR}"
echo "  results.csv          -> $(wc -l < "${RUN_DIR}/results.csv" 2>/dev/null || echo 0) lineas"
echo "  resource_metrics.csv -> CPU/mem por replica"
echo "  state/               -> dumps por escenario"
echo "  summaries/           -> k6 --summary-export por replica"
echo "  logs/                -> stdout de cada k6"
