#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE_FILE="${ROOT_DIR}/scripts/s6-integrated-profile.env"
RUN_RANDOMIZED="${ROOT_DIR}/scripts/run-randomized-design-matrix.sh"
RUN_K6="${ROOT_DIR}/scripts/run-k6-benchmark.sh"
GEN_MATRIX="${ROOT_DIR}/Testing/generate_s6_integrated_matrix.py"
K6_FLOW="${ROOT_DIR}/RealisticServices/k6/realistic-flow.js"

fail() {
  echo "[verify-s6][error] $*" >&2
  exit 1
}

[[ -f "$PROFILE_FILE" ]] || fail "Missing profile file: $PROFILE_FILE"
# shellcheck disable=SC1090
source "$PROFILE_FILE"

[[ -f "$GEN_MATRIX" ]] || fail "Missing matrix generator: $GEN_MATRIX"
[[ -f "$RUN_RANDOMIZED" ]] || fail "Missing randomized runner: $RUN_RANDOMIZED"
[[ -f "$RUN_K6" ]] || fail "Missing benchmark runner: $RUN_K6"
[[ -f "$K6_FLOW" ]] || fail "Missing k6 flow script: $K6_FLOW"

[[ "${S6_REPLICATES:-}" =~ ^[0-9]+$ ]] || fail "S6_REPLICATES is not numeric"
(( S6_REPLICATES >= 3 )) || fail "S6_REPLICATES must be >= 3"

[[ "${S6_DURATION_SECONDS:-}" =~ ^[0-9]+$ ]] || fail "S6_DURATION_SECONDS is not numeric"
(( S6_DURATION_SECONDS >= 60 )) || fail "S6_DURATION_SECONDS must be >= 60"

[[ "${S2_C4_MODERATE_RPM:-}" =~ ^[0-9]+$ ]] || fail "S2_C4_MODERATE_RPM is not numeric"
[[ "${S2_C4_STRICT_RPM:-}" =~ ^[0-9]+$ ]] || fail "S2_C4_STRICT_RPM is not numeric"
(( S2_C4_MODERATE_RPM > S2_C4_STRICT_RPM )) || fail "Expected S2_C4_MODERATE_RPM > S2_C4_STRICT_RPM"

for token in "--security-mode" "--k6-script"; do
  grep -q -- "$token" "$RUN_K6" || fail "run-k6-benchmark.sh missing $token"
done

grep -q "security_mode" "$RUN_RANDOMIZED" || fail "run-randomized-design-matrix.sh missing security_mode support"

echo "[verify-s6] OK"
echo "[verify-s6] campaign_id=${S6_CAMPAIGN_ID:-s6_integrated_dual_n4}"
echo "[verify-s6] replicates=${S6_REPLICATES}"
echo "[verify-s6] duration_seconds=${S6_DURATION_SECONDS}"
echo "[verify-s6] security_modes=${S6_SECURITY_MODES}"
echo "[verify-s6] c4_moderate_rpm=${S2_C4_MODERATE_RPM}"
echo "[verify-s6] c4_strict_rpm=${S2_C4_STRICT_RPM}"
