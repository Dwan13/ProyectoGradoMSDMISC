#!/usr/bin/env bash
# ==========================================================================
# run-attack-validation.sh
# Orquestador: ejecuta la validación completa de vectores de ataque
# para C3 (Network Policies) y C4 (Rate Limiting).
#
# USO:
#   bash run-attack-validation.sh          # C3 + C4
#   bash run-attack-validation.sh --c3     # solo C3
#   bash run-attack-validation.sh --c4     # solo C4
#
# SALIDA:
#   Imprime resultados en terminal + guarda logs en attack-results/
# ==========================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/attack-results/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$LOG_DIR"

CYN='\033[0;36m'; BLD='\033[1m'; NC='\033[0m'

banner() {
  echo -e "\n${CYN}${BLD}▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓${NC}"
  echo -e "${CYN}${BLD}  $*${NC}"
  echo -e "${CYN}${BLD}▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓${NC}\n"
}

RUN_C3=true; RUN_C4=true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --c3) RUN_C3=true;  RUN_C4=false ;;
    --c4) RUN_C3=false; RUN_C4=true  ;;
    *) echo "Uso: $0 [--c3|--c4]" >&2; exit 1 ;;
  esac
  shift
done

banner "VALIDACIÓN DE VECTORES DE ATAQUE – CORRECCIONES JURADO"
echo "  Log dir: ${LOG_DIR}"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"

# ---------- C3 -----------------------------------------------------------
if $RUN_C3; then
  banner "C3 – NETWORK POLICIES: LATERAL MOVEMENT"
  bash "${SCRIPT_DIR}/validate-c3-lateral-movement.sh" 2>&1 | tee "${LOG_DIR}/c3-lateral-movement.log"
  echo ""
  echo "  Log guardado: ${LOG_DIR}/c3-lateral-movement.log"
fi

# ---------- C4 (bash version) -------------------------------------------
if $RUN_C4; then
  banner "C4 – RATE LIMITING: BRUTE FORCE (curl paralelo)"
  bash "${SCRIPT_DIR}/validate-c4-brute-force.sh" 2>&1 | tee "${LOG_DIR}/c4-brute-force.log"
  echo ""
  echo "  Log guardado: ${LOG_DIR}/c4-brute-force.log"

  # k6 version (opcional, requiere k6 instalado)
  if command -v k6 >/dev/null 2>&1; then
    banner "C4 – RATE LIMITING: BRUTE FORCE (k6)"
    for variant in "without-rate-limiting" "moderate-rate-limiting" "strict-rate-limiting"; do
      echo "  → Ejecutando k6 contra realistic-${variant}.local"
      k6 run \
        -e TARGET="${variant}" \
        -e PORT=32167 \
        -e VUS=5 \
        -e DURATION=20s \
        --summary-export "${LOG_DIR}/c4-k6-${variant}.json" \
        "${SCRIPT_DIR}/c4-brute-force-k6.js" \
        2>&1 | tee "${LOG_DIR}/c4-k6-${variant}.log"
    done
  else
    echo "  k6 no encontrado — omitiendo test k6 (ya se ejecutó la versión curl)"
  fi
fi

banner "VALIDACIÓN COMPLETADA"
echo "  Logs guardados en: ${LOG_DIR}"
ls -lh "$LOG_DIR"
