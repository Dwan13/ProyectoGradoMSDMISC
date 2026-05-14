#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE_FILE="${ROOT_DIR}/scripts/s2-final-profile.env"
VERIFY_SCRIPT="${ROOT_DIR}/scripts/verify-s2-final-config.sh"
RUN_SCRIPT="${ROOT_DIR}/scripts/run-randomized-design-matrix.sh"
MATRIX="${ROOT_DIR}/Testing/results/scaling_tests/design_matrix_academic_base_n8_B1_B8_randomized_blocks.csv"
MATRIX_GENERATOR="${ROOT_DIR}/Testing/generate_academic_base_matrix.py"
EXECUTE=false
LIMIT_ROWS=""
CONTINUE_ON_READINESS_FAIL=false

usage() {
  cat <<EOF
Usage: $(basename "$0") [--execute] [--limit-rows N] [--matrix PATH]

Options:
  --execute        Run full execution. Without this flag, performs dry-run only.
  --limit-rows N   Run only first N rows from matrix (for smoke checks).
  --matrix PATH    Override design matrix path.
  --continue-on-readiness-fail
                   Continue rows even when readiness gate is unstable.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --execute) EXECUTE=true; shift ;;
    --limit-rows) LIMIT_ROWS="$2"; shift 2 ;;
    --matrix) MATRIX="$2"; shift 2 ;;
    --continue-on-readiness-fail) CONTINUE_ON_READINESS_FAIL=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

[[ -f "$PROFILE_FILE" ]] || { echo "Missing profile file: $PROFILE_FILE" >&2; exit 1; }

if [[ ! -f "$MATRIX" ]]; then
  echo "[run-s2-final] Matrix not found, generating reproducible matrix at: $MATRIX"
  /bin/python3 "$MATRIX_GENERATOR" \
    --replicates 8 \
    --seed 20260510 \
    --campaign-id s2_academic_base_n8 \
    --start-date 2026-05-11 \
    --output "$MATRIX"
fi

# shellcheck disable=SC1090
source "$PROFILE_FILE"

bash "$VERIFY_SCRIPT"

CMD=(bash "$RUN_SCRIPT" --matrix "$MATRIX" --target-env postgres-real)
if [[ "$EXECUTE" == true ]]; then
  CMD+=(--execute)
fi
if [[ -n "$LIMIT_ROWS" ]]; then
  CMD+=(--limit-rows "$LIMIT_ROWS")
fi
if [[ "$CONTINUE_ON_READINESS_FAIL" == true ]]; then
  CMD+=(--continue-on-readiness-fail)
fi

echo "[run-s2-final] Using profile: $PROFILE_FILE"
echo "[run-s2-final] C4 moderate RPM=$S2_C4_MODERATE_RPM"
echo "[run-s2-final] C4 strict RPM=$S2_C4_STRICT_RPM"
echo "[run-s2-final] Matrix: $MATRIX"
echo "[run-s2-final] Continue on readiness fail: $CONTINUE_ON_READINESS_FAIL"
"${CMD[@]}"
