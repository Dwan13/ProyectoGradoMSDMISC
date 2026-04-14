#!/bin/bash
# =============================================================
# Ejecuta ambos flujos realistas de k6: negocio y autenticación/acceso
# =============================================================
# Uso:
#   bash run_realistic_combined.sh <control> <output_dir>
# Ejemplo:
#   bash run_realistic_combined.sh c1 ./results/c1-realistic-combined
# =============================================================

set -euo pipefail

CONTROL=${1:-c1}
OUT_DIR=${2:-./results/${CONTROL}-realistic-combined}
mkdir -p "$OUT_DIR"

# Variables de entorno para endpoints (ajusta si es necesario)
export AUTH_BASE="http://127.0.0.1:18082"
export API_BASE="http://127.0.0.1:30081"

# 1. Flujo de negocio: create/list users
k6 run --out json="$OUT_DIR/users-bulk-create-list.json" \
  ../RealisticServices/k6/users-bulk-create-list.js

# 2. Flujo de autenticación/acceso: login + profile
k6 run --out json="$OUT_DIR/realistic-flow.json" \
  ../RealisticServices/k6/realistic-flow.js

# Mensaje final
echo "\nFlujos ejecutados. Resultados en: $OUT_DIR"
echo "- users-bulk-create-list.json (negocio)"
echo "- realistic-flow.json (autenticación/acceso)"
