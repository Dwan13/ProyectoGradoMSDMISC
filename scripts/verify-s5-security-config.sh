#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE_FILE="${ROOT_DIR}/scripts/s5-security-profile.env"
RUN_RANDOMIZED="${ROOT_DIR}/scripts/run-randomized-design-matrix.sh"
GEN_MATRIX="${ROOT_DIR}/Testing/generate_s5_security_matrix.py"

fail() {
  echo "[verify-s5][error] $*" >&2
  exit 1
}

[[ -f "$PROFILE_FILE" ]] || fail "Missing profile file: $PROFILE_FILE"
# shellcheck disable=SC1090
source "$PROFILE_FILE"

[[ -f "$GEN_MATRIX" ]] || fail "Missing matrix generator: $GEN_MATRIX"
[[ -f "$RUN_RANDOMIZED" ]] || fail "Missing runner: $RUN_RANDOMIZED"

[[ "${S5_REPLICATES:-}" =~ ^[0-9]+$ ]] || fail "S5_REPLICATES is not numeric"
(( S5_REPLICATES >= 2 )) || fail "S5_REPLICATES must be >= 2"

[[ "${S2_C4_MODERATE_RPM:-}" =~ ^[0-9]+$ ]] || fail "S2_C4_MODERATE_RPM is not numeric"
[[ "${S2_C4_STRICT_RPM:-}" =~ ^[0-9]+$ ]] || fail "S2_C4_STRICT_RPM is not numeric"
(( S2_C4_MODERATE_RPM > S2_C4_STRICT_RPM )) || fail "Expected S2_C4_MODERATE_RPM > S2_C4_STRICT_RPM"

# Check manifests required by S5 cells.
for manifest in \
  RealisticServices/k8s/07-c1-ingress-gateway-real.yaml \
  RealisticServices/k8s/07-c1-istio-real.yaml \
  RealisticServices/k8s/07-c1-kong-real.yaml \
  RealisticServices/k8s/02-services-istio-mtls-real.yaml \
  RealisticServices/k8s/02-services-linkerd-mtls-real.yaml \
  RealisticServices/k8s/08-c3-networkpolicy-real.yaml \
  RealisticServices/k8s/08-c3-networkpolicy-moderate-real.yaml \
  RealisticServices/k8s/08-c3-networkpolicy-strict-real.yaml
  do
  [[ -f "${ROOT_DIR}/${manifest}" ]] || fail "Missing manifest: ${manifest}"
done

# Ensure runner supports selected variants.
grep -q "C3/moderate" "$RUN_RANDOMIZED" || fail "Runner does not include C3/moderate"
grep -q "C4/moderate" "$RUN_RANDOMIZED" || fail "Runner does not include C4/moderate"
grep -q "C4/strict" "$RUN_RANDOMIZED" || fail "Runner does not include C4/strict"

echo "[verify-s5] OK"
echo "[verify-s5] campaign_id=${S5_CAMPAIGN_ID:-s5_security_focus_n3}"
echo "[verify-s5] replicates=${S5_REPLICATES}"
echo "[verify-s5] c4_moderate_rpm=${S2_C4_MODERATE_RPM}"
echo "[verify-s5] c4_strict_rpm=${S2_C4_STRICT_RPM}"
