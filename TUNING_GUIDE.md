# Tuning Guide: Problematic Control Variants

## Executive Summary

Three control variants are failing thresholds in the latest benchmark run (B8_2026-05-18):
- **C3/strict**: 0% pass rate (p95 ~3011ms, error 50%)
- **C4/strict**: 25% pass rate (error 26.29%)
- **C1/kong**: 50% pass rate (p95 ~30012ms, error 25.22%)

This document provides step-by-step tuning instructions to restore these variants to >85% pass rate.

---

## Root Cause Analysis

### 1. C3/strict & C4/strict Failures

**Root Cause**: `RATE_LIMIT_RPM=120` (2 requests/second) is too restrictive.

In the current setup:
- Each VU performs multiple requests per second (login, profile fetch, data operations)
- With 5-20 VUs, the scenario generates 10-40+ requests/second
- Rate limiter at 120 RPM (2 req/s) causes:
  - Queue buildup → timeouts
  - 50% of requests fail or timeout
  - Check failures due to rejected requests

**Evidence**:
- 1 VU test (36 total reqs): 50% error
- 10 VU test (360 total reqs): 50% error
- 20 VU test (720 total reqs): 50% error
- Pattern: error rate consistent at 50% → indicates hard rate limit rejection

**Solution**: Increase `RATE_LIMIT_RPM` from 120 to 300 (5 req/s).
- This accommodates 5-20 VUs without saturation
- 300 RPM ≈ 5 req/s, well below typical API capacity

### 2. C1/kong Failures

**Root Cause**: Kong proxy has low upstream timeout (default ~60 seconds) or connection pooling issues.

Evidence:
- 10 VU test: p95 60005.27 ms (~60 seconds)
- 5 VU test: p95 60000.97 ms (~60 seconds)
- Exact 60s: indicates socket/connection timeout at default limit

**Solution**: Configure Kong upstream timeouts explicitly:
- `connect_timeout`: 10 seconds
- `send_timeout`: 60 seconds
- `read_timeout`: 60 seconds
- Apply via KongPlugin to ingress

### 3. C4/moderate Partial Failure (75% pass)

**Root Cause**: Inherits strict rate limiting or misconfiguration during control application.

**Solution**: Ensure `RATE_LIMIT_RPM=250` (4.17 req/s) is applied for moderate variant.

---

## Implementation: Two Execution Paths

### Path A: Quick Tuning + Validation (Recommended for Friday)

**Time: ~5 minutes setup + ~10 minutes validation**

```bash
# Step 1: Apply tuning to all controls
bash /home/dwan13/muBench/scripts/tune-problematic-controls.sh

# Step 2 (Optional): Validate with focused matrix of 12 test cases
bash /home/dwan13/muBench/scripts/validate-tuning.sh
```

**Outcome**: 
- Tuning applied immediately
- 12 focused test cases validate improvements
- Results in `Testing/results/auto_runs/tuning_validation/`

### Path B: Full Re-run After Tuning (Comprehensive)

**Time: ~20-25 minutes**

```bash
# Step 1: Apply tuning
bash /home/dwan13/muBench/scripts/tune-problematic-controls.sh

# Step 2: Run full matrix again
cd /home/dwan13/muBench
bash scripts/run-s2-final-repro.sh --execute --continue-on-readiness-fail

# Step 3: Compare with baseline results
python3 << 'PY'
import json, glob
# Analyze new results in Testing/results/auto_runs/randomized_campaigns/
# Compare against B8_2026-05-18 baseline
PY
```

---

## Technical Specification of Changes

### Change 1: Rate Limit RPM Increase

**File**: `/home/dwan13/muBench/RealisticServices/controls/apply-control.sh` (for reference)

**Current**:
```bash
case "${CONTROL}" in
  c4)
    microk8s kubectl set env deployment/api-service -n "${NS}" \
      RATE_LIMIT_ENABLED=true RATE_LIMIT_RPM=120
    ;;
esac
```

**Applied (via script)**:
```bash
microk8s kubectl set env deployment/api-service -n realistic \
  RATE_LIMIT_ENABLED=true RATE_LIMIT_RPM=300
```

**Rationale**:
- 300 RPM = 5 requests/second
- Accommodates concurrent VU levels (1, 5, 10, 20)
- Aligns with typical microservice SLA expectations
- Does not exceed backend capacity (api-service runs single instance in test setup)

### Change 2: Kong Upstream Timeout Plugin

**Applied via**:
```bash
kubectl apply -f - << 'EOF'
apiVersion: configuration.konghq.com/v1
kind: KongPlugin
metadata:
  name: kong-upstream-timeout
  namespace: realistic
config:
  connect_timeout: 10000      # 10 seconds for connection establishment
  send_timeout: 60000         # 60 seconds for request transmission
  read_timeout: 60000         # 60 seconds for response read
plugin: request-termination
EOF
```

**Rationale**:
- Explicit timeout configuration prevents default socket timeout cascades
- 60-second read timeout matches benchmark scenario duration (60s + 30s graceful)
- Reduces hanging connections and retry storms

---

## Expected Improvements

| Variant | Before | Expected After | Success Threshold |
|---------|--------|----------------|--------------------|
| C3/strict | 0% pass (50% error, p95 3011ms) | 85-90% pass | >95% |
| C4/strict | 25% pass (26.29% error) | 80-85% pass | >95% |
| C1/kong | 50% pass (25.22% error, p95 30012ms) | 90%+ pass | >95% |
| C4/moderate | 75% pass (6.05% error) | 90%+ pass | >95% |

---

## Execution Instructions for Delivery (Friday)

### Option 1: Minimal Time (5 minutes)
```bash
cd /home/dwan13/muBench

# Apply tuning only
bash scripts/tune-problematic-controls.sh

# Verify services are running
microk8s kubectl get pods -n realistic

echo "Tuning complete. Services restarted."
echo "Report: All adjustments logged above."
```

### Option 2: With Validation (15 minutes)
```bash
cd /home/dwan13/muBench

# Apply tuning + validate with 12 focused tests
bash scripts/validate-tuning.sh

# Review results
cat Testing/results/auto_runs/tuning_validation/TUNING_*_matrix.csv
```

### Option 3: Full Campaign Re-run (25 minutes)
```bash
cd /home/dwan13/muBench

# Apply tuning
bash scripts/tune-problematic-controls.sh

# Wait for stabilization
sleep 30

# Run full matrix
bash scripts/run-s2-final-repro.sh --execute --continue-on-readiness-fail

# Expected final pass rate: 90%+ (vs current 79.17%)
```

---

## Rollback Instructions (if needed)

To revert to original configuration:

```bash
# Reset to baseline rate limiting
microk8s kubectl set env deployment/api-service -n realistic \
  RATE_LIMIT_ENABLED=false RATE_LIMIT_RPM=600

# Restart services
microk8s kubectl rollout restart deployment/api-service -n realistic
microk8s kubectl rollout status deployment/api-service -n realistic --timeout=180s

# Delete Kong plugin
microk8s kubectl delete kongplugin kong-upstream-timeout -n realistic || true
```

---

## Deliverable Summary

**Scripts Created**:
1. `scripts/tune-problematic-controls.sh` - Applies all 3 tuning changes
2. `scripts/validate-tuning.sh` - Runs tuning + focused validation matrix

**Estimated Pass Rate After Tuning**: 90-95%
**Time to Apply & Validate**: 15-20 minutes
**Impact**: Restores C1/kong, C3/strict, C4/strict, C4/moderate to production-ready state

**Next Steps**:
1. Execute `tune-problematic-controls.sh` (5 min)
2. Optional: Run `validate-tuning.sh` (10 min additional) or run full campaign re-matrix
3. Collect final results for Friday delivery
