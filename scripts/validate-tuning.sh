#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="${ROOT_DIR}/Testing/results/auto_runs/tuning_validation"
CAMPAIGN_ID="TUNING_$(date +'%Y-%m-%d_%H%M%S')"

log() { echo "[$(date +'%H:%M:%S')] $*"; }
err() { echo "[$(date +'%H:%M:%S')] ERROR: $*" >&2; exit 1; }

# ========================================
# STEP 1: APPLY TUNING
# ========================================
log ""
log "========== STEP 1: APPLYING TUNING =========="
bash "${ROOT_DIR}/scripts/tune-problematic-controls.sh"

# ========================================
# STEP 2: WAIT FOR STABILIZATION
# ========================================
log ""
log "========== STEP 2: WAITING FOR STABILIZATION =========="
log "Waiting 30 seconds for services to settle..."
sleep 30
log "✓ Ready to benchmark"

# ========================================
# STEP 3: CREATE TUNING VALIDATION MATRIX
# ========================================
mkdir -p "${RESULTS_DIR}"

log ""
log "========== STEP 3: CREATING TUNING VALIDATION MATRIX =========="
log "Testing problematic variants at multiple VU levels..."

# Build minimal matrix focusing on the 3 problem variants
cat > "${RESULTS_DIR}/${CAMPAIGN_ID}_matrix.csv" << 'MATRIX'
Order,Control,Variant,VUs
1,C1,kong,1
2,C1,kong,5
3,C1,kong,10
4,C1,kong,20
5,C3,strict,1
6,C3,strict,5
7,C3,strict,10
8,C3,strict,20
9,C4,strict,1
10,C4,strict,5
11,C4,strict,10
12,C4,strict,20
MATRIX

log "Matrix created with 12 test cases (3 variants × 4 VU levels)"
log "Matrix location: ${RESULTS_DIR}/${CAMPAIGN_ID}_matrix.csv"

# ========================================
# STEP 4: RUN BENCHMARK MATRIX
# ========================================
log ""
log "========== STEP 4: RUNNING BENCHMARK MATRIX =========="

# Export k6 results format
export K6_OUTPUT_FORMAT="json"
export RESULTS_DIR

PASS_COUNT=0
TOTAL_COUNT=0

# Read and execute matrix
tail -n +2 "${RESULTS_DIR}/${CAMPAIGN_ID}_matrix.csv" | while IFS=, read -r order control variant vus; do
  TOTAL_COUNT=$((TOTAL_COUNT + 1))
  log ""
  log "[ORDER $order/$TOTAL_COUNT] Running ${control}/${variant} with ${vus} VUs..."
  
  NS="realistic"
  
  # Apply scenario (simplified: just set rate limiting based on variant)
  case "${variant}" in
    strict)
      microk8s kubectl set env deployment/api-service -n "${NS}" \
        RATE_LIMIT_ENABLED=true RATE_LIMIT_RPM=300 >/dev/null 2>&1 || true
      ;;
    moderate)
      microk8s kubectl set env deployment/api-service -n "${NS}" \
        RATE_LIMIT_ENABLED=true RATE_LIMIT_RPM=250 >/dev/null 2>&1 || true
      ;;
    baseline|kong|istio)
      microk8s kubectl set env deployment/api-service -n "${NS}" \
        RATE_LIMIT_ENABLED=false RATE_LIMIT_RPM=600 >/dev/null 2>&1 || true
      ;;
  esac
  
  # Run k6 benchmark
  RESULT_FILE="${RESULTS_DIR}/${CAMPAIGN_ID}_order${order}_${control}_${variant}_${vus}vus.json"
  
  /bin/python3 "${ROOT_DIR}/RealisticServices/run-k6-realistic.sh" \
    --script "${ROOT_DIR}/RealisticServices/k6/realistic-flow.js" \
    --vus "${vus}" \
    --output "${RESULT_FILE}" \
    2>&1 | tail -20 || log "⚠ Benchmark order $order returned status $?"
  
  log "✓ Order $order complete: ${RESULT_FILE}"
done

# ========================================
# STEP 5: ANALYZE RESULTS
# ========================================
log ""
log "========== STEP 5: ANALYZING RESULTS =========="

/bin/python3 - <<'ANALYZE_PY'
import json, glob, os, math, statistics
from collections import defaultdict

base = os.environ.get('RESULTS_DIR', '.')
files = glob.glob(base + '/*_order*_*.json')

print(f"\n{'='*60}")
print("TUNING VALIDATION RESULTS")
print(f"{'='*60}\n")

rows = []
for f in sorted(files):
    bn = os.path.basename(f)
    parts = bn.replace('.json', '').split('_')
    
    # Parse filename: TUNING_..._orderN_CONTROL_VARIANT_NVUs.json
    try:
        order = int([p for p in parts if p.startswith('order')][0].replace('order', ''))
        control = [p for p in parts if p in ['C1', 'C2', 'C3', 'C4']][0]
        variant = [p for p in parts if p in ['baseline', 'kong', 'strict', 'istio', 'moderate']][0]
        vus = int([p for p in parts if p.endswith('vus')][0].replace('vus', ''))
    except (IndexError, ValueError):
        continue
    
    checks = []; dur = []; failed = []
    reqs = 0
    
    try:
        with open(f, 'r', encoding='utf-8', errors='ignore') as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    o = json.loads(line)
                except Exception:
                    continue
                if o.get('type') != 'Point':
                    continue
                m = o.get('metric')
                v = o.get('data', {}).get('value')
                try:
                    fv = float(v)
                except Exception:
                    continue
                if m == 'checks':
                    checks.append(fv)
                elif m == 'http_req_duration':
                    dur.append(fv)
                elif m == 'http_req_failed':
                    failed.append(fv)
                elif m == 'http_reqs':
                    reqs += int(fv)
    except Exception as e:
        print(f"Error parsing {f}: {e}")
        continue
    
    s = sorted(dur) if dur else []
    p95 = s[max(0, math.ceil(0.95*len(s))-1)] if s else float('nan')
    checks_rate = (sum(checks)/len(checks)*100) if checks else float('nan')
    err_rate = (sum(failed)/len(failed)*100) if failed else float('nan')
    passed = (checks_rate >= 95 and p95 < 700 and err_rate <= 5)
    
    rows.append({
        'order': order, 'control': control, 'variant': variant, 'vus': vus,
        'checks': checks_rate, 'p95': p95, 'err': err_rate, 'reqs': reqs, 'passed': passed
    })

if not rows:
    print("No results found.")
else:
    # Summary
    total = len(rows)
    passed = sum(1 for r in rows if r['passed'])
    print(f"Total test cases: {total}")
    print(f"Passed: {passed}/{total} ({passed/total*100:.1f}%)")
    print(f"\n{'Order':<8} {'Control':<8} {'Variant':<12} {'VUs':<6} {'Pass':<6} {'Checks':<10} {'P95':<10} {'Error':<10}")
    print("-" * 90)
    
    for r in sorted(rows, key=lambda x: x['order']):
        status = "✓" if r['passed'] else "✗"
        print(f"{r['order']:<8} {r['control']:<8} {r['variant']:<12} {r['vus']:<6} {status:<6} {r['checks']:.1f}%{'':<3} {r['p95']:.1f}ms{'':<4} {r['err']:.1f}%")
    
    # Summary by variant
    print(f"\n{'='*60}")
    print("BY VARIANT")
    print(f"{'='*60}")
    by_var = defaultdict(list)
    for r in rows:
        by_var[r['variant']].append(r)
    
    for var in sorted(by_var.keys()):
        grp = by_var[var]
        pass_rate = sum(1 for g in grp if g['passed']) / len(grp) * 100
        print(f"{var:<12} Pass: {pass_rate:.1f}% (Checks: {statistics.mean(g['checks'] for g in grp):.2f}%, P95: {statistics.mean(g['p95'] for g in grp):.2f}ms, Error: {statistics.mean(g['err'] for g in grp):.2f}%)")

print(f"\n{'='*60}")
ANALYZE_PY

# ========================================
# STEP 6: SUMMARY & RECOMMENDATIONS
# ========================================
log ""
log "========== STEP 6: SUMMARY =========="
log ""
log "Tuning validation complete!"
log "Results directory: ${RESULTS_DIR}"
log ""
log "Next steps:"
log "  1. Review results in the analysis above"
log "  2. If pass rate improved: apply tuning to production matrix"
log "  3. If still failing: inspect detailed logs in ${RESULTS_DIR}"
log ""
log "To re-run full campaign with tuning applied:"
log "  cd ${ROOT_DIR} && bash scripts/run-s2-final-repro.sh --execute --continue-on-readiness-fail"
log ""
