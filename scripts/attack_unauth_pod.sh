#!/bin/bash
#
# S6 RIGOROUS: Unauthorized Pod-to-Pod Access Test (mTLS Enforcement)
#
# Purpose: Test that mTLS prevents unauthenticated pod-to-pod connections
# Defended By: C2 (mTLS)
#
# Test Mechanism:
#   - Create a test pod without valid mTLS certificate
#   - Attempt TLS connection to api-service without client cert
#   - Measure: connection successful? TLS handshake succeeded?
#   - Expected: 100% of attempts rejected at TLS handshake
#
# Configuration:
#   TARGET_SERVICE: api-service.mubench-real.svc.cluster.local:5000
#   NAMESPACE: mubench-real
#   ATTEMPTS: 50 (with various timing, retry patterns)
#   DURATION: 60s
#

set -e

TARGET_SERVICE="${1:-api-service.mubench-real.svc.cluster.local:5000}"
NAMESPACE="${2:-mubench-real}"
ATTEMPTS="${3:-50}"
DURATION="${4:-60}"
LOG_DIR="./s6_attack_logs/unauth_pod"

mkdir -p "$LOG_DIR"

echo "[mtls-test] Starting unauthorized pod-to-pod access test"
echo "[mtls-test] Target: $TARGET_SERVICE"
echo "[mtls-test] Namespace: $NAMESPACE"
echo "[mtls-test] Attempts: $ATTEMPTS"
echo "[mtls-test] Duration: ${DURATION}s"

# Create a test pod (if not exists)
echo "[mtls-test] Creating test pod..."
kubectl run --image=nicolaka/netshoot mtls-attacker \
  --restart=Never \
  --rm \
  --namespace="$NAMESPACE" \
  -i --attach=false -- sleep 60 &

sleep 5  # Wait for pod to be ready

ATTACKER_POD=$(kubectl get pod -n "$NAMESPACE" -l run=mtls-attacker -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$ATTACKER_POD" ]; then
  echo "[mtls-test] ERROR: Test pod not found"
  exit 1
fi

echo "[mtls-test] Test pod: $ATTACKER_POD"

# Attempt TLS connections WITHOUT client certificate
echo "[mtls-test] Attempting $ATTEMPTS TLS connections WITHOUT client cert..."

BLOCKED_COUNT=0
LEAKED_COUNT=0
START_TIME=$(date +%s)

for i in $(seq 1 $ATTEMPTS); do
  ATTEMPT_START=$(date +%s%N | cut -b1-13)  # milliseconds
  
  # Attempt connection with openssl s_client (no -cert, no -key)
  RESPONSE=$(
    kubectl exec -n "$NAMESPACE" "$ATTACKER_POD" -- \
      timeout 5 openssl s_client -connect "$TARGET_SERVICE" \
      -showcerts 2>&1
  )
  
  ATTEMPT_END=$(date +%s%N | cut -b1-13)
  LATENCY=$((ATTEMPT_END - ATTEMPT_START))
  
  # Analyze response
  if echo "$RESPONSE" | grep -q "Verify return code:.*certificate required"; then
    # Expected: TLS handshake failed due to missing client cert
    BLOCKED_COUNT=$((BLOCKED_COUNT + 1))
    echo "$i,BLOCKED,ssl_cert_required,$LATENCY" >> "$LOG_DIR/unauth_pod_attempts.log"
  elif echo "$RESPONSE" | grep -q "connect:errno"; then
    # Connection refused or reset (also a block)
    BLOCKED_COUNT=$((BLOCKED_COUNT + 1))
    echo "$i,BLOCKED,connection_reset,$LATENCY" >> "$LOG_DIR/unauth_pod_attempts.log"
  elif echo "$RESPONSE" | grep -q "Verification OK"; then
    # LEAKED: TLS handshake succeeded (should not happen with mTLS)
    LEAKED_COUNT=$((LEAKED_COUNT + 1))
    echo "$i,LEAKED,handshake_succeeded,$LATENCY" >> "$LOG_DIR/unauth_pod_attempts.log"
  else
    # Unknown response
    BLOCKED_COUNT=$((BLOCKED_COUNT + 1))
    echo "$i,UNKNOWN,unknown_response,$LATENCY" >> "$LOG_DIR/unauth_pod_attempts.log"
  fi
  
  # Check if we've exceeded duration
  ELAPSED=$(($(date +%s) - START_TIME))
  if [ "$ELAPSED" -gt "$DURATION" ]; then
    echo "[mtls-test] Reached duration limit ($DURATION seconds)"
    break
  fi
  
  # Small delay between attempts
  sleep 0.2
done

# Cleanup
kubectl delete pod -n "$NAMESPACE" "$ATTACKER_POD" 2>/dev/null || true

# Calculate metrics
TOTAL_ATTEMPTS=$((BLOCKED_COUNT + LEAKED_COUNT))
if [ $TOTAL_ATTEMPTS -gt 0 ]; then
  MITIGATION_RATE=$((BLOCKED_COUNT * 100 / TOTAL_ATTEMPTS))
else
  MITIGATION_RATE=0
fi

# Write summary
cat > "$LOG_DIR/unauth_pod_summary.txt" << EOF
=== Unauthorized Pod-to-Pod Access Test ===
Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)
Target: $TARGET_SERVICE
Namespace: $NAMESPACE

RESULTS:
  Total Attempts: $TOTAL_ATTEMPTS
  Blocked (TLS rejected): $BLOCKED_COUNT
  Leaked (TLS succeeded): $LEAKED_COUNT
  Mitigation Rate: ${MITIGATION_RATE}%

INTERPRETATION:
  - Blocked > 95%: ✓ mTLS is enforcing certificate requirement
  - Blocked < 90%: ⚠ mTLS enforcement is weak (some handshakes succeeded)
  - Leaked > 0: ❌ CRITICAL - Unauthenticated pods can connect (mTLS failed)

STATUS: $([ "$MITIGATION_RATE" -ge 100 ] && echo "PASS" || echo "FAIL")
EOF

# Display summary
cat "$LOG_DIR/unauth_pod_summary.txt"

# Return exit code based on mitigation rate
if [ "$MITIGATION_RATE" -ge 100 ]; then
  echo "[mtls-test] ✓ mTLS test PASSED"
  exit 0
else
  echo "[mtls-test] ✗ mTLS test FAILED (mitigation rate: ${MITIGATION_RATE}%)"
  exit 1
fi
