#!/usr/bin/env bash
# ==============================================================================
# factorial-graceful-startup.sh
#
# Encendido específico para la campaña factorial (12 escenarios C1..C4).
# Sustituye al graceful-startup.sh tradicional (que apunta a s1-s4 obsoletos).
#
# Pasos:
#   1) Levanta MicroK8s y espera ready
#   2) Verifica addons requeridos
#   3) Restaura réplicas escaladas a 0 (si shutdown previo)
#   4) Ejecuta factorial-bootstrap.sh (estado baseline limpio)
#   5) Smoke test final
#
# Uso:
#   bash scripts/factorial-graceful-startup.sh
#   bash scripts/factorial-graceful-startup.sh --skip-smoke
#   bash scripts/factorial-graceful-startup.sh --yes      # sin prompts
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
STATE_FILE="${ROOT_DIR}/.mubench-state/factorial-session.env"
NS="realistic"

SKIP_SMOKE=false
ASSUME_YES=false

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log()  { echo -e "${BLUE}[startup]${NC} $*"; }
ok()   { echo -e "${GREEN}[ ok ]${NC} $*"; }
warn() { echo -e "${YELLOW}[warn]${NC} $*"; }
fail() { echo -e "${RED}[fail]${NC} $*"; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-smoke) SKIP_SMOKE=true; shift ;;
    --yes)        ASSUME_YES=true; shift ;;
    -h|--help)
      sed -n '2,20p' "$0"; exit 0 ;;
    *) warn "opción ignorada: $1"; shift ;;
  esac
done

echo ""
echo "============================================================"
echo "  GRACEFUL STARTUP — Factorial Campaign (12 escenarios)"
echo "============================================================"

# ─── 1) MicroK8s ──────────────────────────────────────────────────────────────
log "1) Levantando MicroK8s"
command -v microk8s >/dev/null || fail "MicroK8s no instalado"
microk8s start 2>/dev/null || true
if ! microk8s status --wait-ready --timeout=120 >/dev/null 2>&1; then
  fail "MicroK8s no quedó ready en 120s"
fi
ok "MicroK8s ready"

# ─── 2) Addons ────────────────────────────────────────────────────────────────
log "2) Verificando addons"
STATUS_OUT="$(microk8s status --format short 2>/dev/null)"
for a in dns hostpath-storage ingress metrics-server helm3 istio linkerd; do
  if echo "$STATUS_OUT" | grep -qE "^(core|community)/${a}: enabled"; then
    ok "addon $a"
  else
    warn "addon $a NO habilitado (algunos escenarios pueden fallar)"
  fi
done

# ─── 3) Restaurar réplicas (si shutdown previo escaló a 0) ───────────────────
log "3) Restaurando réplicas en namespace ${NS}"
if kubectl get ns "${NS}" >/dev/null 2>&1; then
  for d in $(kubectl -n "${NS}" get deploy -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
    REP=$(kubectl -n "${NS}" get deploy "$d" -o jsonpath='{.spec.replicas}' 2>/dev/null)
    if [[ "$REP" == "0" ]]; then
      kubectl -n "${NS}" scale deploy "$d" --replicas=1 >/dev/null
      ok "scaled up $d → 1"
    fi
  done
else
  warn "namespace ${NS} no existe (será creado por bootstrap)"
fi

# ─── 4) Bootstrap factorial (idempotente) ────────────────────────────────────
log "4) Ejecutando factorial-bootstrap.sh"
if [[ "$ASSUME_YES" == "false" ]]; then
  echo ""
  read -r -p "Aplicar bootstrap factorial sobre el cluster? [Enter=sí, n=no]: " ans
  [[ "$ans" =~ ^[Nn] ]] && { warn "saltando bootstrap"; exit 0; }
fi

BOOT_ARGS=()
[[ "$SKIP_SMOKE" == "true" ]] && BOOT_ARGS+=("--skip-smoke")
bash "${SCRIPT_DIR}/factorial-bootstrap.sh" "${BOOT_ARGS[@]}"

# ─── 5) Persistir estado ─────────────────────────────────────────────────────
mkdir -p "$(dirname "$STATE_FILE")"
cat > "$STATE_FILE" <<EOF
LAST_STARTUP_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)
LAST_MODE=factorial
NAMESPACE=${NS}
EOF
ok "estado persistido en $STATE_FILE"

echo ""
echo "============================================================"
echo "  ✓ STARTUP FACTORIAL COMPLETADO"
echo "============================================================"
echo ""
echo "Estado: cluster en BASELINE (12 escenarios listos)"
echo ""
echo "Siguientes pasos:"
echo "  • Aplicar un escenario:"
echo "      bash scripts/factorial-apply-scenario.sh C1 baseline"
echo ""
echo "  • Lanzar campaña completa (384 runs):"
echo "      python3 scripts/run-factorial-campaign.py \\"
echo "        --vus 1 5 10 20 --replicas 8 --duration 60"
echo ""
echo "  • Lanzar campaña reducida (sanidad ~50 min):"
echo "      python3 scripts/run-factorial-campaign.py \\"
echo "        --vus 1 5 --replicas 2 --duration 30"
echo ""
echo "  • Apagar al terminar:"
echo "      bash scripts/graceful-shutdown.sh --yes"
echo ""
