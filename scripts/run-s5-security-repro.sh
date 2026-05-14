#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE_FILE="${ROOT_DIR}/scripts/s5-security-profile.env"
VERIFY_SCRIPT="${ROOT_DIR}/scripts/verify-s5-security-config.sh"
GEN_MATRIX="${ROOT_DIR}/Testing/generate_s5_security_matrix.py"
RUN_MATRIX="${ROOT_DIR}/scripts/run-randomized-design-matrix.sh"

EXECUTE=false
LIMIT_ROWS=""
TARGET_ENV="postgres-real"

usage() {
  cat <<EOF
Usage: $(basename "$0") [--execute] [--limit-rows N] [--target-env postgres-real]

Default mode is dry-run.

Options:
  --execute            Execute real benchmarks (default: dry-run)
  --limit-rows N       Execute only first N rows after block/order sorting
  --target-env ENV     Forwarded to run-randomized-design-matrix.sh (default: postgres-real)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --execute) EXECUTE=true; shift ;;
    --limit-rows) LIMIT_ROWS="$2"; shift 2 ;;
    --target-env) TARGET_ENV="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "[run-s5][error] Unknown option: $1" >&2; exit 1 ;;
  esac
done

[[ -f "$PROFILE_FILE" ]] || { echo "[run-s5][error] Missing profile: $PROFILE_FILE" >&2; exit 1; }
# shellcheck disable=SC1090
source "$PROFILE_FILE"

bash "$VERIFY_SCRIPT"

MATRIX_PATH="${ROOT_DIR}/Testing/results/scaling_tests/design_matrix_${S5_CAMPAIGN_ID}_randomized_blocks.csv"

python3 "$GEN_MATRIX" \
  --replicates "${S5_REPLICATES}" \
  --seed "${S5_SEED}" \
  --campaign-id "${S5_CAMPAIGN_ID}" \
  --start-date "${S5_START_DATE}" \
  --warmup-seconds "${S5_WARMUP_SECONDS}" \
  --cooldown-seconds "${S5_COOLDOWN_SECONDS}" \
  --output "$MATRIX_PATH"

CMD=(bash "$RUN_MATRIX" --matrix "$MATRIX_PATH" --target-env "$TARGET_ENV")
if [[ "$EXECUTE" == true ]]; then
  CMD+=(--execute)
fi
if [[ -n "$LIMIT_ROWS" ]]; then
  CMD+=(--limit-rows "$LIMIT_ROWS")
elif [[ -n "${S5_LIMIT_ROWS:-}" ]]; then
  CMD+=(--limit-rows "$S5_LIMIT_ROWS")
fi

echo "[run-s5] matrix: $MATRIX_PATH"
echo "[run-s5] mode: $([[ "$EXECUTE" == true ]] && echo execute || echo dry-run)"
"${CMD[@]}"
