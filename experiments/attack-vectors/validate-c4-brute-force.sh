#!/usr/bin/env bash
# ==========================================================================
# validate-c4-brute-force.sh
# Validación del vector de ataque para C4 (Rate Limiting).
#
# FASE 1 – Smoke de ataque rápido (curl paralelo, ~30 seg):
#   Confirma que el control bloquea la ráfaga.
#   Distingue 503 rate-limit NGINX (control C4) vs 503 backend (fiabilidad).
#
# FASE 2 – Grid de VUS con las 6 métricas (comparable al experimento original):
#   VUS=1,5,10,20 × 3 variantes × REPLICAS réplicas
#   Usa c4-brute-force-k6.js (no sleep, credential stuffing continuo).
#   Métricas: avg_ms, p95_ms, err_pct, rps, cpu_total_m, mem_total_Mi
#   Salida: attack-results/c4_<TIMESTAMP>/results.csv
#
# VARIABLES DE ENTORNO:
#   VUS_LEVELS   Lista de VUS a probar          (por defecto: "1 5 10 20")
#   DURATION     Duración de cada run k6         (por defecto: 20s)
#   REPLICAS     Réplicas por variante×VUS        (por defecto: 3)
#   CLUSTER_PORT NodePort del Ingress NGINX       (por defecto: 32167)
#   SMOKE_REQS   Requests paralelos en Fase 1    (por defecto: 500)
#   SKIP_SMOKE   Si =1, omite la Fase 1          (por defecto: 0)
#   SKIP_GRID    Si =1, omite la Fase 2          (por defecto: 0)
#
# USO:
#   bash validate-c4-brute-force.sh
#   DURATION=60s REPLICAS=5 bash validate-c4-brute-force.sh
#   SKIP_SMOKE=1 bash validate-c4-brute-force.sh   # solo Fase 2
# ==========================================================================
set -euo pipefail

RED='\033[0;31m'; GRN='\033[0;32m'; YEL='\033[1;33m'
CYN='\033[0;36m'; BLD='\033[1m'; NC='\033[0m'

VUS_LEVELS="${VUS_LEVELS:-1 5 10 20}"
DURATION="${DURATION:-20s}"
REPLICAS="${REPLICAS:-8}"
CLUSTER_PORT="${CLUSTER_PORT:-32167}"
SMOKE_REQS="${SMOKE_REQS:-500}"
SKIP_SMOKE="${SKIP_SMOKE:-0}"
SKIP_GRID="${SKIP_GRID:-0}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ATTACK_K6="$SCRIPT_DIR/c4-brute-force-k6.js"

# --- Escenarios C4 ---
# formato: "namespace:target_suffix:label:limite"
C4_SCENARIOS=(
  "realistic-without-rate-limiting:without-rate-limiting:baseline:Sin límite"
  "realistic-moderate-rate-limiting:moderate-rate-limiting:moderate:1200 rpm"
  "realistic-strict-rate-limiting:strict-rate-limiting:strict:300 rpm"
)

RESOURCE_CSV=""  # se asigna en run_vus_grid

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
pass() { echo -e "  ${GRN}${BLD}✔ PROTEGIDO${NC}  – $*"; }
vuln() { echo -e "  ${RED}${BLD}✘ VULNERABLE${NC} – $*"; }

# ---------- health check con credenciales CORRECTAS -----------------------
# Propósito: distinguir "el control bloquea" de "el servicio está caído".
# Si el stack no responde con demo/demo123, el error rate alto es fiabilidad,
# no efectividad del control. Devuelve 0 si OK, 1 si el servicio no responde.
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
    echo -e "  ${YEL}  ⚠ Verifica que el namespace esté desplegado antes de atacar.${NC}"
    echo -e "  ${YEL}  Comandos: microk8s kubectl get pods -n realistic-${label,,}-rate-limiting${NC}"
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
# FASE 1: SMOKE – RÁFAGA CURL (confirma que el control está activo)
# ==========================================================================
brute_force_smoke() {
  local host="$1" label="$2" limit_desc="$3"
  local tmpfile; tmpfile=$(mktemp)
  : > "$tmpfile"

  echo ""
  info "Variante: ${BLD}${label}${NC}  (límite: ${limit_desc})"
  info "Enviando ${SMOKE_REQS} requests paralelos a /auth/login..."

  for i in $(seq 1 "$SMOKE_REQS"); do
    {
      raw=$(curl -sk -w "\n%{http_code}" \
        --resolve "${host}:${CLUSTER_PORT}:127.0.0.1" \
        --max-time 5 \
        -H 'Content-Type: application/json' \
        -d '{"username":"admin","password":"wrongpassword_'${i}'"}' \
        "https://${host}:${CLUSTER_PORT}/auth/login" 2>/dev/null \
        || echo -e "\n000")
      code=$(echo "$raw" | tail -n1)
      body=$(echo "$raw" | head -n -1)
      case "$code" in
        200|401)
          echo "ok"          >> "$tmpfile" ;;
        503)
          if echo "$body" | grep -qi "nginx"; then
            echo "rl503"     >> "$tmpfile"   # rate-limit NGINX  → control C4
          else
            echo "be503"     >> "$tmpfile"   # backend failure   → fiabilidad
          fi ;;
        *)
          echo "other"       >> "$tmpfile" ;;
      esac
    } &
  done
  wait

  local ok_c rl_c be_c ot_c total
  ok_c=$(grep -c '^ok$'    "$tmpfile" 2>/dev/null || echo 0)
  rl_c=$(grep -c '^rl503$' "$tmpfile" 2>/dev/null || echo 0)
  be_c=$(grep -c '^be503$' "$tmpfile" 2>/dev/null || echo 0)
  ot_c=$(grep -c '^other$' "$tmpfile" 2>/dev/null || echo 0)
  total=$(wc -l < "$tmpfile" | tr -d ' ')
  rm -f "$tmpfile"

  local bpct=0
  [[ "$total" -gt 0 ]] && bpct=$(( (rl_c * 100) / total ))

  echo ""
  echo -e "  ┌────────────────────────────────────────────────────────┐"
  printf  "  │  Variante:                  %-26s │\n" "${label}"
  echo -e "  ├────────────────────────────────────────────────────────┤"
  printf  "  │  Total enviados:            %-26s │\n" "${total}"
  printf  "  │  Llegaron al backend 200/401: %-24s │\n" "${ok_c}"
  printf  "  │  Rate-limit NGINX  503 HTML:  %-24s │\n" "${rl_c}  ← control C4"
  printf  "  │  Fallo de backend  503 JSON:  %-24s │\n" "${be_c}  ← fiabilidad (≠ C4)"
  printf  "  │  Otros (000/4xx…):            %-24s │\n" "${ot_c}"
  echo -e "  ├────────────────────────────────────────────────────────┤"
  printf  "  │  Tasa de bloqueo (rate-limit): %-23s │\n" "${bpct}%"
  echo -e "  └────────────────────────────────────────────────────────┘"
  echo ""

  if [[ "$be_c" -gt 0 ]]; then
    echo -e "  ${YEL}⚠ $be_c respuestas 503 JSON del backend — revisar fiabilidad del stack.${NC}"
    echo ""
  fi
  if [[ "$rl_c" -eq 0 ]]; then
    vuln "0% bloqueados por rate-limit → brute force llega al backend sin restricción"
  elif [[ "$bpct" -ge 30 ]]; then
    pass "${bpct}% rechazados por NGINX rate-limit (503 HTML) — control C4 activo"
  else
    echo -e "  ${YEL}⚠ Solo ${bpct}% bloqueados — verificar configuración del rate-limit${NC}"
  fi
}

# ==========================================================================
# FASE 2: GRID VUS – 6 MÉTRICAS (comparable al experimento original)
# ==========================================================================
run_vus_grid() {
  if [[ ! -f "$ATTACK_K6" ]]; then
    echo -e "${YEL}⚠ No se encontró $ATTACK_K6 — Fase 2 omitida.${NC}"
    return
  fi
  if ! command -v k6 >/dev/null 2>&1; then
    echo -e "${YEL}⚠ k6 no encontrado — Fase 2 omitida. Instala k6 y reintenta.${NC}"
    return
  fi

  local RUN_DIR="$SCRIPT_DIR/attack-results/c4_$(date +%Y%m%d_%H%M%S)"
  local SUM_DIR="$RUN_DIR/summaries"
  RESOURCE_CSV="$RUN_DIR/resource_metrics.csv"
  mkdir -p "$SUM_DIR"
  echo "control,variant,vus,replica,cpu_total_m,mem_total_Mi" > "$RESOURCE_CSV"

  local total_runs=0 current=0
  for VUS in $VUS_LEVELS; do
    total_runs=$((total_runs + ${#C4_SCENARIOS[@]} * REPLICAS))
  done

  echo ""
  info "Pre-flight: verificando servicios antes del grid k6..."
  for SC in "${C4_SCENARIOS[@]}"; do
    IFS=: read -r NS TARGET VAR LIMIT_DESC <<< "$SC"
    health_check "realistic-${TARGET}.local" "$VAR" || true
  done
  echo ""
  info "Grid: VUS=[${VUS_LEVELS}] × ${#C4_SCENARIOS[@]} variantes × ${REPLICAS} réplicas = ${total_runs} runs"
  info "Duración por run: ${DURATION}  |  Script k6: $(basename "$ATTACK_K6")"
  info "Resultados: ${RUN_DIR}"

  for VUS in $VUS_LEVELS; do
    for SC in "${C4_SCENARIOS[@]}"; do
      IFS=: read -r NS TARGET VAR LIMIT_DESC <<< "$SC"

      for ((r=1; r<=REPLICAS; r++)); do
        current=$((current+1))
        local SUM="$SUM_DIR/C4_${VAR}_vus${VUS}_rep${r}.json"
        printf "  [%3d/%d] C4/%-8s  VUS=%-2d  rep=%d  ..." \
               "$current" "$total_runs" "$VAR" "$VUS" "$r"

        set +e
        k6 run \
          -e TARGET="$TARGET" \
          -e PORT="$CLUSTER_PORT" \
          -e VUS="$VUS" \
          -e DURATION="$DURATION" \
          --summary-export "$SUM" \
          --no-color --quiet \
          "$ATTACK_K6" 2>/dev/null
        local rc=$?
        set -e

        collect_resources "$NS" "C4" "$VAR" "$VUS" "$r"
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
    m = re.match(r"(C4)_([\w-]+)_vus(\d+)_rep(\d+)\.json$", os.path.basename(fp))
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
        "control":        ctrl,
        "variant":        var,
        "vus":            int(vus),
        "replica":        int(rep),
        "avg_ms":         round(g("http_req_duration", "avg")    or 0, 3),
        "p95_ms":         round(g("http_req_duration", "p(95)")  or 0, 3),
        "err_pct":        round((g("http_req_failed",  "rate") or 0) * 100, 3),
        "rps":            round(g("http_reqs",          "rate")   or 0, 3),
        "ratelimit_503":  cnt("ratelimit_503"),   # control C4
        "backend_503":    cnt("backend_503"),      # fiabilidad
        "reached_backend":cnt("attack_reached_backend"),
        "cpu_total_m":    cpu,
        "mem_total_Mi":   mem,
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
      f"{'err%':>7} {'rps':>7} {'rl503':>7} {'cpu_m':>7} {'mem_Mi':>7}")
print("  " + "-"*74)
for (var, vus), rs in sorted(groups.items(), key=lambda x: (["baseline","moderate","strict"].index(x[0][0]) if x[0][0] in ["baseline","moderate","strict"] else 99, x[0][1])):
    def mean(k):
        vals = [r[k] for r in rs if isinstance(r.get(k), (int, float))]
        return round(sum(vals)/len(vals), 2) if vals else "-"
    def sumv(k):
        vals = [r[k] for r in rs if isinstance(r.get(k), (int, float))]
        return int(sum(vals)) if vals else "-"
    print(f"  {var:<10} {vus:>4} {mean('avg_ms'):>8} {mean('p95_ms'):>8} "
          f"{mean('err_pct'):>7} {mean('rps'):>7} {sumv('ratelimit_503'):>7} "
          f"{mean('cpu_total_m'):>7} {mean('mem_total_Mi'):>7}")
PY

  echo ""
  echo -e "  ${GRN}${BLD}Fase 2 completada.${NC}"
  echo -e "  results.csv → ${RUN_DIR}/results.csv"
}

# ==========================================================================
# MAIN
# ==========================================================================
banner "C4 RATE LIMITING – VECTOR DE ATAQUE: BRUTE FORCE / CREDENTIAL STUFFING"
cat <<EOF
  Control:   C4 – NGINX Ingress Rate Limiting (limit-rpm)
  Ataque:    Credential stuffing (OWASP OAT-008) / Brute Force (OWASP OAT-007)
  CWE-307 (Improper Restriction of Excessive Authentication Attempts)
  VUS grid:  ${VUS_LEVELS}  |  Duración: ${DURATION}  |  Réplicas: ${REPLICAS}
  Smoke:     ${SMOKE_REQS} requests paralelos (Fase 1)
EOF

# ── FASE 1 ────────────────────────────────────────────────────────────────
if [[ "$SKIP_SMOKE" == "1" ]]; then
  echo -e "\n${YEL}SKIP_SMOKE=1 — Fase 1 omitida.${NC}"
else
  banner "FASE 1 – SMOKE DE ATAQUE (ráfaga curl)"
  echo "  Propósito: confirmar rápidamente que el control bloquea la ráfaga."
  echo ""

  echo ""
  info "Pre-flight: verificando que los servicios responden con credenciales legítimas..."
  all_healthy=true
  for SC in "${C4_SCENARIOS[@]}"; do
    IFS=: read -r NS TARGET VAR LIMIT_DESC <<< "$SC"
    HOST="realistic-${TARGET}.local"
    health_check "$HOST" "$VAR" || all_healthy=false
  done
  if [[ "$all_healthy" == false ]]; then
    echo -e "\n  ${YEL}⚠ Uno o más servicios no respondieron al health-check.${NC}"
    echo -e "  ${YEL}  El test continúa, pero un error rate alto puede ser un problema${NC}"
    echo -e "  ${YEL}  de fiabilidad del stack, NO del control de rate-limiting.${NC}\n"
  fi
  echo ""

  for SC in "${C4_SCENARIOS[@]}"; do
    IFS=: read -r NS TARGET VAR LIMIT_DESC <<< "$SC"
    HOST="realistic-${TARGET}.local"
    brute_force_smoke "$HOST" "${VAR^^}" "$LIMIT_DESC"
  done

  cat <<'EOF'
  NOTA: 503 HTML (firma "nginx") = rate-limit activo = control C4.
        503 JSON                 = fallo del backend  = métrica de fiabilidad.
        Ambos tipos se reportan por separado en la tabla anterior.
EOF
fi

# ── FASE 2 ────────────────────────────────────────────────────────────────
if [[ "$SKIP_GRID" == "1" ]]; then
  echo -e "\n${YEL}SKIP_GRID=1 — Fase 2 omitida.${NC}"
else
  banner "FASE 2 – GRID VUS: 6 MÉTRICAS (comparable al experimento C4 original)"
  echo "  Ejecuta el ataque de credential stuffing continuo (sin sleep) en"
  echo "  VUS=[${VUS_LEVELS}] para contrastar con los datos del experimento original."
  echo "  Columnas extra: ratelimit_503 (bloqueos del control C4)."
  run_vus_grid
fi
