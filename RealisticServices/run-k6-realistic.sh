#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="${ROOT_DIR}/results"
mkdir -p "${RESULTS_DIR}"

AUTH_BASE="${AUTH_BASE:-http://127.0.0.1:30084}"
API_BASE="${API_BASE:-http://127.0.0.1:30081}"
STAMP="$(date +%Y%m%d_%H%M%S)"
OUT_JSON="${RESULTS_DIR}/k6-realistic-${STAMP}.json"

echo "[INFO] AUTH_BASE=${AUTH_BASE}"
echo "[INFO] API_BASE=${API_BASE}"
echo "[INFO] Output=${OUT_JSON}"

k6 run \
  -e AUTH_BASE="${AUTH_BASE}" \
  -e API_BASE="${API_BASE}" \
  --out json="${OUT_JSON}" \
  "${ROOT_DIR}/k6/realistic-flow.js"

echo "[INFO] k6 finished: ${OUT_JSON}"
