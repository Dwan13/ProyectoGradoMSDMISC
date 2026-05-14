#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE_FILE="${ROOT_DIR}/scripts/s2-final-profile.env"
STRICT_MANIFEST="${ROOT_DIR}/RealisticServices/k8s/08-c3-networkpolicy-strict-real.yaml"
RUN_RANDOMIZED="${ROOT_DIR}/scripts/run-randomized-design-matrix.sh"
RUN_SCALING="${ROOT_DIR}/scripts/run-scaling-tests.sh"

fail() {
  echo "[verify-s2][error] $*" >&2
  exit 1
}

[[ -f "$PROFILE_FILE" ]] || fail "Missing profile file: $PROFILE_FILE"
# shellcheck disable=SC1090
source "$PROFILE_FILE"

[[ "${S2_C4_MODERATE_RPM:-}" =~ ^[0-9]+$ ]] || fail "S2_C4_MODERATE_RPM is not numeric"
[[ "${S2_C4_STRICT_RPM:-}" =~ ^[0-9]+$ ]] || fail "S2_C4_STRICT_RPM is not numeric"

if (( S2_C4_MODERATE_RPM <= S2_C4_STRICT_RPM )); then
  fail "Expected moderate RPM > strict RPM, got $S2_C4_MODERATE_RPM <= $S2_C4_STRICT_RPM"
fi

[[ -f "$STRICT_MANIFEST" ]] || fail "Missing strict manifest: $STRICT_MANIFEST"
grep -q "name: api-service-egress-restrict" "$STRICT_MANIFEST" || fail "C3 strict manifest missing api-service-egress-restrict policy"

# Strict policy should not allow api-service egress to data-service.
if awk '
  $0 ~ /name: api-service-egress-restrict/ {in_block=1}
  in_block && $0 ~ /^---/ {in_block=0}
  in_block {print}
' "$STRICT_MANIFEST" | grep -q "app: data-service"; then
  fail "C3 strict manifest still allows api-service -> data-service"
fi

# Ensure runners consume profile variables instead of hardcoding.
grep -q "S2_C4_MODERATE_RPM" "$RUN_RANDOMIZED" || fail "run-randomized-design-matrix.sh does not consume profile variable"
grep -q "S2_C4_STRICT_RPM" "$RUN_RANDOMIZED" || fail "run-randomized-design-matrix.sh does not consume profile variable"
grep -q "S2_C4_MODERATE_RPM" "$RUN_SCALING" || fail "run-scaling-tests.sh does not consume profile variable"
grep -q "S2_C4_STRICT_RPM" "$RUN_SCALING" || fail "run-scaling-tests.sh does not consume profile variable"

echo "[verify-s2] OK"
echo "[verify-s2] C4 moderate RPM=$S2_C4_MODERATE_RPM"
echo "[verify-s2] C4 strict RPM=$S2_C4_STRICT_RPM"
echo "[verify-s2] C3 strict policy blocks api-service -> data-service"
