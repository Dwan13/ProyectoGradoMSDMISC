#!/bin/bash

################################################################################
# S6 RIGOROUS MVP ORCHESTRATOR - ACCELERATED FOR TOMORROW
# Timeline: Today 16:00 → Tomorrow 07:00 (15 hours max)
# Output: Initial findings for document draft
# Status: Production-ready
################################################################################

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

NAMESPACE="mubench-real"
RESULTS_DIR="Testing/results/s6_rigorous_mvp"
LOGS_DIR="${RESULTS_DIR}/logs"
ATTACK_LOGS_DIR="${RESULTS_DIR}/attack_logs"

# MVP Settings (FASTER than full campaign)
CONTROLS=("C1" "C2" "C3" "C4")
VARIANTS=("baseline")  # Only baseline to save time
VUS_CONFIGS=(1 5 10)   # Fewer VUS than full (4,10,20 full)
REPLICATES=2           # Half of full (4 full)
ATTACKS=("sqli" "credstuff")  # Only these 2 (skip XXE/PathTraversal)

# Timings
PHASE_1_DURATION=30      # seconds
PHASE_2_DURATION=30      # seconds
COOLDOWN=30              # seconds between phases
K6_LEGIT_VUS=7           # Legitimate traffic during Phase 2
K6_ATTACK_VUS=3          # Attack traffic during Phase 2

# ============================================================================
# SETUP
# ============================================================================

mkdir -p "${LOGS_DIR}" "${ATTACK_LOGS_DIR}"
chmod 777 "${RESULTS_DIR}" "${LOGS_DIR}" "${ATTACK_LOGS_DIR}"

LOGFILE="${LOGS_DIR}/orchestrator_mvp_$(date +%Y%m%d_%H%M%S).log"
exec 1> >(tee -a "${LOGFILE}")
exec 2>&1

echo "================================================================================"
echo "S6 MVP ORCHESTRATOR - STARTING $(date)"
echo "================================================================================"
echo "Namespace:     ${NAMESPACE}"
echo "Results Dir:   ${RESULTS_DIR}"
echo "Expected Runtime: 14-16 hours"
echo "Target Completion: Tomorrow ~07:00"
echo ""
echo "Configuration:"
echo "  Controls:    ${CONTROLS[@]}"
echo "  Variants:    ${VARIANTS[@]}"
echo "  VUS:         ${VUS_CONFIGS[@]}"
echo "  Replicates:  ${REPLICATES}"
echo "  Attacks:     ${ATTACKS[@]}"
echo "================================================================================"

# ============================================================================
# VALIDATION
# ============================================================================

echo ""
echo "[STEP 1/4] Validating Environment..."

# Check namespace
if ! kubectl get namespace "${NAMESPACE}" &>/dev/null; then
  echo "✗ ERROR: Namespace ${NAMESPACE} not found"
  exit 1
fi
echo "✓ Namespace ${NAMESPACE} exists"

# Check pods
PODS=$(kubectl get pods -n "${NAMESPACE}" -o custom-columns=NAME:.metadata.name | grep -E 'api-service|auth-service|data-service' | wc -l)
if [ "${PODS}" -lt 3 ]; then
  echo "✗ ERROR: Expected ≥3 services running, found ${PODS}"
  exit 1
fi
echo "✓ Found ${PODS} services running"

# Check k6
if ! command -v k6 &>/dev/null; then
  echo "✗ ERROR: k6 not found"
  exit 1
fi
K6_VERSION=$(k6 version | head -1 | awk '{print $2}')
echo "✓ k6 ${K6_VERSION} available"

# Check scripts exist
for script in attack_sqli.js attack_credstuff.js; do
  if [ ! -f "k6/${script}" ]; then
    echo "✗ ERROR: k6/${script} not found"
    exit 1
  fi
done
echo "✓ All attack scripts found"

# ============================================================================
# FUNCTIONS
# ============================================================================

run_phase_1_baseline() {
  local control=$1
  local variant=$2
  local vus=$3
  local replica=$4
  
  local phase_label="phase1"
  local test_name="${control}_${variant}_${vus}vus_r${replica}"
  local output_file="${RESULTS_DIR}/s6_mvp_${phase_label}_${test_name}.json"
  
  echo "  [Phase 1] ${control} ${variant} ${vus}VUS replica${replica}..."
  
  # Generate baseline traffic
  k6 run \
    -e CONTROL="${control}" \
    -e VARIANT="${variant}" \
    -e PHASE="baseline" \
    --vus "${vus}" \
    --duration "${PHASE_1_DURATION}s" \
    --no-thresholds \
    --out json="${output_file}" \
    k6/baseline_traffic.js 2>&1 | tail -3
}

run_phase_2_attack() {
  local control=$1
  local variant=$2
  local vus=$3
  local replica=$4
  local attack_type=$5
  
  local phase_label="phase2_${attack_type}"
  local test_name="${control}_${variant}_${vus}vus_r${replica}"
  local output_file="${RESULTS_DIR}/s6_mvp_${phase_label}_${test_name}.json"
  
  echo "  [Phase 2] ${control} ${variant} ${vus}VUS ${attack_type} replica${replica}..."
  
  # Phase 2: Legitimate + Attack in SEPARATE k6 processes
  # Terminal 1: Legitimate
  (
    k6 run \
      -e CONTROL="${control}" \
      -e VARIANT="${variant}" \
      -e PHASE="under_attack" \
      --vus "${K6_LEGIT_VUS}" \
      --duration "${PHASE_2_DURATION}s" \
      --no-thresholds \
      --out json="${output_file}.legit" \
      k6/baseline_traffic.js
  ) &
  LEGIT_PID=$!
  
  # Terminal 2: Attack
  sleep 2  # Let legitimate requests start first
  (
    k6 run \
      -e CONTROL="${control}" \
      -e VARIANT="${variant}" \
      -e PHASE="under_attack" \
      -e ATTACK_TYPE="${attack_type}" \
      --vus "${K6_ATTACK_VUS}" \
      --duration "${PHASE_2_DURATION}s" \
      --no-thresholds \
      --out json="${output_file}.attack" \
      k6/attack_${attack_type}.js
  ) &
  ATTACK_PID=$!
  
  # Wait both to complete
  wait ${LEGIT_PID} ${ATTACK_PID}
  
  # Merge results
  python3 - <<EOF
import json

data_legit = []
data_attack = []

with open("${output_file}.legit", "r") as f:
  for line in f:
    try:
      data_legit.append(json.loads(line))
    except: pass

with open("${output_file}.attack", "r") as f:
  for line in f:
    try:
      data_attack.append(json.loads(line))
    except: pass

# Write merged + metadata
with open("${output_file}", "w") as f:
  for item in data_legit:
    item['_phase'] = 'phase2_legit'
    item['_attack'] = '${attack_type}'
    item['_control'] = '${control}'
    f.write(json.dumps(item) + "\n")
  for item in data_attack:
    item['_phase'] = 'phase2_attack'
    item['_attack'] = '${attack_type}'
    item['_control'] = '${control}'
    f.write(json.dumps(item) + "\n")

print(f"Merged: {len(data_legit)} legit + {len(data_attack)} attack = {len(data_legit)+len(data_attack)} total")
EOF
  
  rm -f "${output_file}.legit" "${output_file}.attack"
}

# ============================================================================
# PHASE 1: BASELINE (8-10 hours)
# ============================================================================

echo ""
echo "[STEP 2/4] PHASE 1: Baseline Campaign (Legitimate Traffic Only)"
echo "Expected Time: 8-10 hours"
echo ""

START_PHASE1=$(date +%s)
TOTAL_PHASE1=0

for control in "${CONTROLS[@]}"; do
  for variant in "${VARIANTS[@]}"; do
    for vus in "${VUS_CONFIGS[@]}"; do
      for replica in $(seq 1 ${REPLICATES}); do
        run_phase_1_baseline "${control}" "${variant}" "${vus}" "${replica}"
        TOTAL_PHASE1=$((TOTAL_PHASE1 + 1))
        
        # Cooldown between tests
        sleep ${COOLDOWN}
      done
    done
  done
done

END_PHASE1=$(date +%s)
DURATION_PHASE1=$(( (END_PHASE1 - START_PHASE1) / 60 ))
echo ""
echo "✓ PHASE 1 COMPLETE: ${TOTAL_PHASE1} tests in ${DURATION_PHASE1} minutes"

# ============================================================================
# PHASE 2: UNDER ATTACK (8-10 hours)
# ============================================================================

echo ""
echo "[STEP 3/4] PHASE 2: Attack Campaigns (Legitimate + Attack)"
echo "Expected Time: 8-10 hours total (2 attack types)"
echo ""

START_PHASE2=$(date +%s)
TOTAL_PHASE2=0

for attack in "${ATTACKS[@]}"; do
  echo "Attack Type: ${attack}"
  for control in "${CONTROLS[@]}"; do
    for variant in "${VARIANTS[@]}"; do
      for vus in "${VUS_CONFIGS[@]}"; do
        for replica in $(seq 1 ${REPLICATES}); do
          run_phase_2_attack "${control}" "${variant}" "${vus}" "${replica}" "${attack}"
          TOTAL_PHASE2=$((TOTAL_PHASE2 + 1))
          
          # Cooldown
          sleep ${COOLDOWN}
        done
      done
    done
  done
done

END_PHASE2=$(date +%s)
DURATION_PHASE2=$(( (END_PHASE2 - START_PHASE2) / 60 ))
echo ""
echo "✓ PHASE 2 COMPLETE: ${TOTAL_PHASE2} tests in ${DURATION_PHASE2} minutes"

# ============================================================================
# SUMMARY
# ============================================================================

echo ""
echo "[STEP 4/4] Campaign Summary"
echo "================================================================================"

TOTAL_TESTS=$((TOTAL_PHASE1 + TOTAL_PHASE2))
TOTAL_TIME=$(( (END_PHASE2 - START_PHASE1) / 60 ))

echo "Total Tests:     ${TOTAL_TESTS}"
echo "Total Duration:  ${TOTAL_TIME} minutes (~$(( TOTAL_TIME / 60 ))h $(( TOTAL_TIME % 60 ))m)"
echo "Results Dir:     ${RESULTS_DIR}"
echo ""

# Count files
NDJSON_FILES=$(find "${RESULTS_DIR}" -name "s6_mvp_*.json" | wc -l)
echo "✓ Generated ${NDJSON_FILES} NDJSON files"
echo "✓ Results ready for analysis at: ${RESULTS_DIR}/"
echo ""

echo "NEXT STEPS (Tomorrow morning):"
echo "1. Run: python3 scripts/s6_mvp_analyze.py"
echo "2. Check: ${RESULTS_DIR}/analysis_summary.txt"
echo "3. Review: ${RESULTS_DIR}/quick_plots/"
echo ""
echo "================================================================================"
echo "MVP Campaign Complete: $(date)"
echo "================================================================================"
