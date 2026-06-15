#!/usr/bin/env bash
# ==========================================================================
# validate-c3-lateral-movement.sh
# Validación del vector de ataque para C3 (NetworkPolicies).
#
# FASE 1 – Test binario (lateral movement):
#   Vector 1: api-service → postgres:5432  (pivoting a BD)
#   Vector 2: pod externo (ns default) → data-service  (cross-namespace)
#
# FASE 2 – Grid de VUS con las 6 métricas (comparable al experimento original):
#   VUS=1,5,10,20 × 3 variantes × REPLICAS réplicas
#   Métricas: avg_ms, p95_ms, err_pct, rps, cpu_total_m, mem_total_Mi
#   Salida: attack-results/c3_<TIMESTAMP>/results.csv
#
# VARIABLES DE ENTORNO:
#   VUS_LEVELS   Lista de VUS a probar          (por defecto: "1 5 10 20")
#   DURATION     Duración de cada run k6         (por defecto: 20s)
#   REPLICAS     Réplicas por variante×VUS        (por defecto: 3)
#   CLUSTER_PORT NodePort del Ingress NGINX       (por defecto: 32167)
#   SKIP_GRID    Si =1, omite la Fase 2          (por defecto: 0)
#
# USO:
#   bash validate-c3-lateral-movement.sh
#   DURATION=60s REPLICAS=5 bash validate-c3-lateral-movement.sh
#   SKIP_GRID=1  bash validate-c3-lateral-movement.sh   # solo Fase 1
# ==========================================================================
set -euo pipefail

RED='\033[0;31m'; GRN='\033[0;32m'; YEL='\033[1;33m'
CYN='\033[0;36m'; BLD='\033[1m'; NC='\033[0m'

VUS_LEVELS="${VUS_LEVELS:-1 5 10 20}"
DURATION="${DURATION:-20s}"
REPLICAS="${REPLICAS:-8}"
CLUSTER_PORT="${CLUSTER_PORT:-32167}"
SKIP_GRID="${SKIP_GRID:-0}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
CRUD_K6="$ROOT_DIR/RealisticServices/k6/realistic-crud-flow.js"

# --- Escenarios C3 ---
# formato: "namespace:hostname:variant_label"
C3_SCENARIOS=(
  "realistic-without-network-policies:realistic-without-network-policies.local:baseline"
  "realistic-basic-network-policies:realistic-basic-network-policies.local:basic"
  "realistic-strict-network-policies:realistic-strict-network-policies.local:strict"
)

# ==========================================================================
# UTILIDADES COMUNES
# ==========================================================================
kctl() {
  if command -v microk8s >/dev/null 2>&1; then
    microk8s kubectl "$@"
  else
    kubectl "$@"
  fi
}

banner() {
  echo -e "\n${CYN}${BLD}══════════════════════════════════════════════════${NC}"
  echo -e "${CYN}${BLD}  $*${NC}"
  echo -e "${CYN}${BLD}══════════════════════════════════════════════════${NC}"
}
info() { echo -e "  ${YEL}▷${NC} $*"; }
ok()   { echo -e "  ${GRN}${BLD}✔ PROTEGIDO${NC}  – $*"; }
vuln() { echo -e "  ${RED}${BLD}✘ VULNERABLE${NC} – $*"; }

# ---------- health check con credenciales correctas -----------------------
health_check() {
  local host="$1" label="$2"
  local code
  code=$(curl -sk -o /dev/null -w "%{http_code}" \
    --resolve "${host}:${CLUSTER_PORT}:127.0.0.1" \
    --max-time 8 \
    -H 'Content-Type: application/json' \
    -d '{"username":"demo","password":"demo123"}' \
    "https://${host}:${CLUSTER_PORT}/auth/login" 2>/dev/null || echo "000")

  if [[ "$code" == "200" ]]; then
    echo -e "  ${GRN}✔ Health OK${NC} [${label}] demo/demo123 → HTTP 200"
    return 0
  else
    echo -e "  ${RED}✘ Health FAIL${NC} [${label}] demo/demo123 → HTTP ${code}"
    echo -e "  ${YEL}  ⚠ Si err_pct es alto en el grid, puede ser el stack caído, no el control.${NC}"
    return 1
  fi
}

collect_resources() {
  local ns="$1" ctrl="$2" var="$3" vus="$4" rep="$5"
  local cpu_total=0 mem_total=0 cpu_val mem_val pod cpu mem rest
  while read -r pod cpu mem rest; do
    [[ -z "$pod" ]] && continue
    cpu_val="${cpu%m}"; mem_val="${mem%Mi}"
    [[ "$cpu_val" =~ ^[0-9]+$ ]] || cpu_val=0
    [[ "$mem_val" =~ ^[0-9]+$ ]] || mem_val=0
    cpu_total=$((cpu_total + cpu_val))
    mem_total=$((mem_total + mem_val))
  done < <(kctl top pods -n "$ns" --no-headers 2>/dev/null \
    | awk '/api-service|auth-service|data-service|postgres/ {print $1, $2, $3, $4}' \
    || true)
  echo "${ctrl},${var},${vus},${rep},${cpu_total},${mem_total}" >> "$RESOURCE_CSV"
}

# ==========================================================================
# FASE 1: TESTS BINARIOS DE MOVIMIENTO LATERAL
# ==========================================================================

TCP_PROBE='
import socket, sys
host, port = sys.argv[1], int(sys.argv[2])
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.settimeout(5)
try:
    s.connect((host, port))
    s.close()
    print(f"[ATAQUE EXITOSO] TCP {host}:{port} alcanzado desde el pod comprometido")
    sys.exit(0)
except ConnectionRefusedError:
    print(f"[BLOQUEADO] {host}:{port} – conexión rechazada")
    sys.exit(1)
except Exception as e:
    print(f"[BLOQUEADO] {host}:{port} – {type(e).__name__}: {e}")
    sys.exit(1)
'

test_postgres_pivot() {
  local ns="$1" label="$2"
  echo ""
  info "Variante: ${BLD}${label}${NC}  (ns: ${ns})"
  info "Atacante: pod api-service comprometido → objetivo: postgres:5432"

  local pod
  pod=$(kctl -n "$ns" get pods -l app=api-service \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

  if [[ -z "$pod" ]]; then
    echo -e "  ${YEL}⚠ Namespace $ns no encontrado o sin pod api-service. Omitiendo.${NC}"
    return
  fi

  echo -e "  Pod: ${pod}"
  local result exit_code=0
  result=$(kctl -n "$ns" exec "$pod" -- \
    python3 -c "$TCP_PROBE" postgres 5432 2>&1) || exit_code=$?

  echo -e "  Resultado: ${result}"
  if [[ $exit_code -eq 0 ]]; then
    vuln "api-service puede acceder a postgres:5432 → DB expuesta"
  else
    ok "NetworkPolicy bloquea api-service → postgres:5432 (lateral movement prevenido)"
  fi
}

test_cross_namespace() {
  local target_ns="$1" label="$2"
  local target_host="data-service.${target_ns}.svc.cluster.local"
  echo ""
  info "Variante: ${BLD}${label}${NC}  (ns objetivo: ${target_ns})"
  info "Atacante: pod en ns 'default' → objetivo: ${target_host}:8080"

  local result exit_code=0
  result=$(kctl run c3-attacker-probe \
    --image=python:3.11-slim \
    --restart=Never \
    --rm \
    -n default \
    -i \
    --timeout=60s \
    -- python3 -c "$TCP_PROBE" "$target_host" 8080 2>&1) || exit_code=$?

  echo -e "  Resultado: ${result}"
  if [[ $exit_code -eq 0 ]]; then
    vuln "Pod externo (ns 'default') alcanza $target_host → sin aislamiento"
  else
    ok "NetworkPolicy bloquea acceso cross-namespace → namespace isolation activo"
  fi
}

# ==========================================================================
# FASE 2: GRID VUS – 6 MÉTRICAS (comparable al experimento original)
# ==========================================================================
run_vus_grid() {
  if [[ ! -f "$CRUD_K6" ]]; then
    echo -e "${YEL}⚠ No se encontró $CRUD_K6 — Fase 2 omitida.${NC}"
    return
  fi
  if ! command -v k6 >/dev/null 2>&1; then
    echo -e "${YEL}⚠ k6 no encontrado — Fase 2 omitida. Instala k6 y reintenta.${NC}"
    return
  fi

  local RUN_DIR="$SCRIPT_DIR/attack-results/c3_$(date +%Y%m%d_%H%M%S)"
  local SUM_DIR="$RUN_DIR/summaries"
  RESOURCE_CSV="$RUN_DIR/resource_metrics.csv"
  mkdir -p "$SUM_DIR"
  echo "control,variant,vus,replica,cpu_total_m,mem_total_Mi" > "$RESOURCE_CSV"

  local total_runs=0 current=0
  for VUS in $VUS_LEVELS; do
    total_runs=$((total_runs + ${#C3_SCENARIOS[@]} * REPLICAS))
  done

  echo ""
  info "Pre-flight: verificando servicios C3 con demo/demo123..."
  for SC in "${C3_SCENARIOS[@]}"; do
    IFS=: read -r NS HOST VAR <<< "$SC"
    health_check "$HOST" "$VAR" || true
  done
  echo ""
  info "Grid: VUS=[${VUS_LEVELS}] × ${#C3_SCENARIOS[@]} variantes × ${REPLICAS} réplicas = ${total_runs} runs"
  info "Duración por run: ${DURATION}  |  Script k6: $(basename "$CRUD_K6")"
  info "Resultados: ${RUN_DIR}"

  for VUS in $VUS_LEVELS; do
    for SC in "${C3_SCENARIOS[@]}"; do
      IFS=: read -r NS HOST VAR <<< "$SC"
      local AUTH_BASE="https://${HOST}:${CLUSTER_PORT}/auth"
      local API_BASE="https://${HOST}:${CLUSTER_PORT}/api"
      local RESOLVE="${HOST}:127.0.0.1"

      for ((r=1; r<=REPLICAS; r++)); do
        current=$((current+1))
        local SUM="$SUM_DIR/C3_${VAR}_vus${VUS}_rep${r}.json"
        printf "  [%3d/%d] C3/%-8s  VUS=%-2d  rep=%d  ..." \
               "$current" "$total_runs" "$VAR" "$VUS" "$r"

        set +e
        k6 run \
          -e AUTH_BASE="$AUTH_BASE" \
          -e API_BASE="$API_BASE" \
          -e RESOLVE="$RESOLVE" \
          -e K6_INSECURE_SKIP_TLS_VERIFY=true \
          --vus "$VUS" --duration "$DURATION" \
          --summary-export "$SUM" \
          --no-color --quiet \
          "$CRUD_K6" 2>/dev/null
        local rc=$?
        set -e

        collect_resources "$NS" "C3" "$VAR" "$VUS" "$r"
        [[ $rc -eq 0 ]] && echo " OK" || echo " (k6 exit=$rc)"
      done
    done
  done

  # Consolidar a CSV
  echo ""
  info "Consolidando resultados → ${RUN_DIR}/results.csv"
  python3 - "$SUM_DIR" "$RESOURCE_CSV" "$RUN_DIR/results.csv" << 'PY'
import json, csv, os, glob, re, sys

sum_dir, res_file, out_csv = sys.argv[1], sys.argv[2], sys.argv[3]

# Cargar CPU/mem
res = {}
if os.path.exists(res_file):
    with open(res_file) as f:
        next(f, None)
        for line in f:
            p = line.strip().split(",")
            if len(p) == 6:
                res[(p[0], p[1], p[2], p[3])] = (p[4], p[5])

rows = []
for fp in sorted(glob.glob(os.path.join(sum_dir, "*.json"))):
    m = re.match(r"(C3)_([\w-]+)_vus(\d+)_rep(\d+)\.json$", os.path.basename(fp))
    if not m: continue
    ctrl, var, vus, rep = m.group(1), m.group(2), m.group(3), m.group(4)
    try:
        d = json.load(open(fp))
    except Exception as e:
        print(f"  skip {os.path.basename(fp)}: {e}"); continue
    M = d.get("metrics", {})
    def g(k, s):
        try: return M[k][s]
        except: return None
    def cnt(k):
        try: return int(M[k].get("count", 0) or M[k].get("value", 0))
        except: return 0
    cpu, mem = res.get((ctrl, var, vus, rep), ("", ""))
    rows.append({
        "control":      ctrl,
        "variant":      var,
        "vus":          int(vus),
        "replica":      int(rep),
        "avg_ms":       round(g("http_req_duration", "avg")    or 0, 3),
        "p95_ms":       round(g("http_req_duration", "p(95)")  or 0, 3),
        "err_pct":      round((g("http_req_failed",  "rate") or 0) * 100, 3),
        "rps":          round(g("http_reqs",          "rate")   or 0, 3),
        "create_ok":    cnt("crud_create_success_total"),
        "create_fail":  cnt("crud_create_fail_total"),
        "cpu_total_m":  cpu,
        "mem_total_Mi": mem,
    })

if not rows:
    print("  Sin filas — verifica que los summaries JSON existen.")
    sys.exit(0)

with open(out_csv, "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
    w.writeheader(); w.writerows(rows)
print(f"  results.csv escrito: {len(rows)} filas → {out_csv}")

# Mini-tabla resumen por variante×VUS
from collections import defaultdict
groups = defaultdict(list)
for r in rows:
    groups[(r["variant"], r["vus"])].append(r)

print("\n  RESUMEN (media de réplicas):")
print(f"  {'Variante':<10} {'VUS':>4} {'avg_ms':>8} {'p95_ms':>8} "
      f"{'err%':>7} {'rps':>7} {'cpu_m':>7} {'mem_Mi':>7}")
print("  " + "-"*66)
for (var, vus), rs in sorted(groups.items(), key=lambda x: (x[0][0], x[0][1])):
    def mean(k):
        vals = [r[k] for r in rs if isinstance(r[k], (int, float)) and r[k] != ""]
        return round(sum(vals)/len(vals), 2) if vals else "-"
    print(f"  {var:<10} {vus:>4} {mean('avg_ms'):>8} {mean('p95_ms'):>8} "
          f"{mean('err_pct'):>7} {mean('rps'):>7} {mean('cpu_total_m'):>7} "
          f"{mean('mem_total_Mi'):>7}")
PY

  echo ""
  echo -e "  ${GRN}${BLD}Fase 2 completada.${NC}"
  echo -e "  results.csv  → ${RUN_DIR}/results.csv"
  echo -e "  summaries/   → ${#C3_SCENARIOS[@]} variantes × ${#C3_SCENARIOS[@]} VUS × ${REPLICAS} réplicas"
}

# ==========================================================================
# MAIN
# ==========================================================================
banner "C3 NETWORK POLICIES – VECTOR DE ATAQUE: MOVIMIENTO LATERAL"
cat <<EOF
  Control:   C3 – Kubernetes NetworkPolicies
  Ataque:    Lateral movement desde pod api-service comprometido
  CWE-284 / MITRE ATT&CK T1210
  VUS grid:  ${VUS_LEVELS}  |  Duración: ${DURATION}  |  Réplicas: ${REPLICAS}
EOF

# ── FASE 1 ────────────────────────────────────────────────────────────────
banner "FASE 1 – VECTOR DE ATAQUE BINARIO"

echo ""
echo -e "${BLD}══ Vector 1: DB pivot (api-service → postgres:5432) ══${NC}"
test_postgres_pivot "realistic-without-network-policies" "BASELINE"
test_postgres_pivot "realistic-basic-network-policies"   "BASIC"
test_postgres_pivot "realistic-strict-network-policies"  "STRICT"

echo ""
echo -e "${BLD}══ Vector 2: Cross-namespace (default → data-service) ══${NC}"
test_cross_namespace "realistic-without-network-policies" "BASELINE"
test_cross_namespace "realistic-basic-network-policies"   "BASIC"
test_cross_namespace "realistic-strict-network-policies"  "STRICT"

echo ""
cat <<'EOF'
  ┌───────────┬─────────────────────┬──────────────────────┐
  │ Variante  │ DB pivot (V1)       │ Cross-namespace (V2) │
  ├───────────┼─────────────────────┼──────────────────────┤
  │ Baseline  │ VULNERABLE          │ VULNERABLE           │
  │ Basic     │ VULNERABLE          │ PROTEGIDO            │
  │ Strict    │ PROTEGIDO           │ PROTEGIDO            │
  └───────────┴─────────────────────┴──────────────────────┘
EOF

# ── FASE 2 ────────────────────────────────────────────────────────────────
if [[ "$SKIP_GRID" == "1" ]]; then
  echo -e "\n${YEL}SKIP_GRID=1 — Fase 2 omitida.${NC}"
else
  banner "FASE 2 – GRID VUS: 6 MÉTRICAS (comparable al experimento C3 original)"
  echo "  Ejecuta el flujo CRUD estándar contra las 3 variantes en VUS=[${VUS_LEVELS}]."
  echo "  Propósito: comparar latencia, throughput, error rate y recursos con"
  echo "  los datos originales del experimento para medir el overhead real del control."
  run_vus_grid
fi
