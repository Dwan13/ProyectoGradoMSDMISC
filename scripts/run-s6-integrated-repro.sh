#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE_FILE="${ROOT_DIR}/scripts/s6-integrated-profile.env"
VERIFY_SCRIPT="${ROOT_DIR}/scripts/verify-s6-integrated-config.sh"
GEN_MATRIX="${ROOT_DIR}/Testing/generate_s6_integrated_matrix.py"
RUN_MATRIX="${ROOT_DIR}/scripts/run-randomized-design-matrix.sh"

EXECUTE=false
LIMIT_ROWS=""
TARGET_ENV=""
CONTINUE_ON_READINESS_FAIL=false

usage() {
  cat <<EOF
Usage: $(basename "$0") [--execute] [--limit-rows N] [--target-env ENV] [--continue-on-readiness-fail]

Default mode is dry-run.

Options:
  --execute                      Execute real benchmarks (default: dry-run)
  --limit-rows N                 Execute only first N rows after sorting
  --target-env ENV               Override target env from profile (default: postgres-real)
  --continue-on-readiness-fail   Forward continuity mode to runner
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --execute) EXECUTE=true; shift ;;
    --limit-rows) LIMIT_ROWS="$2"; shift 2 ;;
    --target-env) TARGET_ENV="$2"; shift 2 ;;
    --continue-on-readiness-fail) CONTINUE_ON_READINESS_FAIL=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "[run-s6][error] Unknown option: $1" >&2; exit 1 ;;
  esac
done

[[ -f "$PROFILE_FILE" ]] || { echo "[run-s6][error] Missing profile: $PROFILE_FILE" >&2; exit 1; }
# shellcheck disable=SC1090
source "$PROFILE_FILE"

bash "$VERIFY_SCRIPT"

if [[ -z "$TARGET_ENV" ]]; then
  TARGET_ENV="${S6_TARGET_ENV:-postgres-real}"
fi

MATRIX_PATH="${ROOT_DIR}/Testing/results/scaling_tests/design_matrix_${S6_CAMPAIGN_ID}_randomized_blocks.csv"

python3 "$GEN_MATRIX" \
  --replicates "${S6_REPLICATES}" \
  --seed "${S6_SEED}" \
  --campaign-id "${S6_CAMPAIGN_ID}" \
  --start-date "${S6_START_DATE}" \
  --warmup-seconds "${S6_WARMUP_SECONDS}" \
  --cooldown-seconds "${S6_COOLDOWN_SECONDS}" \
  --duration-seconds "${S6_DURATION_SECONDS}" \
  --security-modes "${S6_SECURITY_MODES}" \
  --k6-script "${S6_K6_SCRIPT}" \
  --output "$MATRIX_PATH"

CMD=(bash "$RUN_MATRIX" --matrix "$MATRIX_PATH" --target-env "$TARGET_ENV")
if [[ "$EXECUTE" == true ]]; then
  CMD+=(--execute)
fi
if [[ -n "$LIMIT_ROWS" ]]; then
  CMD+=(--limit-rows "$LIMIT_ROWS")
elif [[ -n "${S6_LIMIT_ROWS:-}" ]]; then
  CMD+=(--limit-rows "$S6_LIMIT_ROWS")
fi
if [[ "$CONTINUE_ON_READINESS_FAIL" == true ]]; then
  CMD+=(--continue-on-readiness-fail)
fi

echo "[run-s6] matrix: $MATRIX_PATH"
echo "[run-s6] mode: $([[ "$EXECUTE" == true ]] && echo execute || echo dry-run)"
echo "[run-s6] target_env: $TARGET_ENV"
echo "[run-s6] security_modes: ${S6_SECURITY_MODES}"
"${CMD[@]}"
