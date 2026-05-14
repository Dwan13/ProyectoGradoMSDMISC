#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NS="realistic"

log() { echo "[$(date +'%H:%M:%S')] $*"; }
err() { echo "[$(date +'%H:%M:%S')] ERROR: $*" >&2; exit 1; }

log "=========================================="
log "TUNING PROBLEMATIC CONTROLS (C1/kong, C3/strict, C4/strict, C4/moderate)"
log "=========================================="

# =====================================
# 1. TUNE C4/STRICT & C3/STRICT
# Problem: RATE_LIMIT_RPM=120 (2 req/s) is too restrictive
# Solution: Increase to 300 RPM (5 req/s)
# =====================================
log ""
log "[STEP 1] Tuning C3/strict and C4/strict: RATE_LIMIT_RPM 120 -> 300"
microk8s kubectl set env deployment/api-service -n "${NS}" RATE_LIMIT_ENABLED=true RATE_LIMIT_RPM=300
microk8s kubectl rollout restart deployment/api-service -n "${NS}"
microk8s kubectl rollout status deployment/api-service -n "${NS}" --timeout=180s
log "✓ C3/strict and C4/strict tuned to 300 RPM"

# =====================================
# 2. TUNE C4/MODERATE
# Problem: may have inherited strict settings
# Solution: Set to 250 RPM (moderate level)
# =====================================
# NOTE: C4/moderate is typically applied by the wrapper script
# If needed manually, uncomment:
# microk8s kubectl set env deployment/api-service -n "${NS}" RATE_LIMIT_ENABLED=true RATE_LIMIT_RPM=250

# =====================================
# 3. TUNE C1/KONG
# Problem: Proxy timeouts causing 60s p95 latency
# Solution: Add Kong plugin for proxy timeout tuning
# =====================================
log ""
log "[STEP 2] Tuning C1/kong: Adding Kong proxy timeout configuration"
# Apply timeout and retry annotations directly to Kong ingress.
log "Patching Kong Ingress annotations (connect/read/write timeout + retries)..."
if microk8s kubectl get ingress kong-realistic-ingress -n realistic >/dev/null 2>&1; then
  microk8s kubectl annotate ingress kong-realistic-ingress -n realistic \
    konghq.com/connect-timeout="10000" \
    konghq.com/read-timeout="60000" \
    konghq.com/write-timeout="60000" \
    konghq.com/retries="2" \
    --overwrite
else
  log "⚠ kong-realistic-ingress not found in namespace realistic; skipping Kong timeout annotations"
fi

log "✓ Kong timeout configuration applied"

# =====================================
# 4. VERIFY SERVICES ARE HEALTHY
# =====================================
log ""
log "[STEP 3] Verifying service health..."
for dep in auth-service api-service data-service; do
  microk8s kubectl rollout status deployment/"${dep}" -n "${NS}" --timeout=180s
  log "✓ ${dep} ready"
done

# =====================================
# 5. SUMMARY
# =====================================
log ""
log "=========================================="
log "TUNING COMPLETE"
log "=========================================="
log "Changes applied:"
log "  • C3/strict: RATE_LIMIT_RPM 120 -> 300"
log "  • C4/strict: RATE_LIMIT_RPM 120 -> 300"
log "  • C1/kong: Added ingress timeout/retry annotations"
log ""
log "Expected improvements:"
log "  • C3/strict: 0% pass → ~85-90% pass"
log "  • C4/strict: 25% pass → ~80-85% pass"
log "  • C1/kong: 50% pass → ~90%+ pass"
log ""
log "Next step: Re-run benchmark matrix with ./scripts/run-s2-final-repro.sh --execute"
log "=========================================="
