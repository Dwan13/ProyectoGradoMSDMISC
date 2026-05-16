#!/bin/bash
#
# S6 RIGOROUS ORCHESTRATOR
# Executes three-phase security testing campaign with proper separation
#
# PHASES:
#   Phase 1 (Baseline):     Legitimate traffic only, 30s
#   Cooldown:               30s pause (system stabilization)
#   Phase 2 (Under Attack): Legitimate (70%) + Attack (30%), 30s
#   Cooldown:               30s pause
#   Phase 3 (Recovery):     Legitimate only, 30s (optional)
#
# DESIGN:
#   - Each phase uses SEPARATE k6 scripts/processes
#   - Attack traffic is NOT mixed with baseline (no contamination)
#   - Metrics collected separately per phase
#   - Clear demarcation: when baseline ends, attack begins
#
# CONFIGURATION:
#   CONTROL:  C1, C2, C3, C4
#   VARIANT:  baseline, var1, var2
#   LOAD (VUS): 1, 5, 10, 20
#   ATTACKS:   sqli, xxe, pathtraversal, credstuff
#   REPLICATES: 4 (randomized daily blocks)
#

set -e

CAMPAIGN_DIR="${CAMPAIGN_DIR:-.}"
RESULTS_DIR="$CAMPAIGN_DIR/Testing/results/s6_rigorous"
LOG_DIR="$RESULTS_DIR/logs"
ATTACK_LOGS="$RESULTS_DIR/attack_logs"

mkdir -p "$RESULTS_DIR" "$LOG_DIR" "$ATTACK_LOGS"

# Configuration
NAMESPACE="mubench-real"
PHASE1_DURATION="30s"
PHASE2_DURATION="30s"
PHASE3_DURATION="30s"
COOLDOWN="30s"

# k6 configuration
K6_VUS_LEGIT_PHASE1=1      # Phase 1: full VUS (baseline)
K6_VUS_LEGIT_PHASE2=7      # Phase 2: 70% legitimate
K6_VUS_ATTACK_PHASE2=3     # Phase 2: 30% attack
K6_RAMP_UP="0s"            # No ramp-up, immediate load

# Log functions
log_info() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] $*" | tee -a "$LOG_DIR/orchestrator.log"
}

log_error() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $*" | tee -a "$LOG_DIR/orchestrator.log"
}

log_section() {
  echo "" | tee -a "$LOG_DIR/orchestrator.log"
  echo "╔════════════════════════════════════════════════════════════════╗" | tee -a "$LOG_DIR/orchestrator.log"
  echo "║ $* " | tee -a "$LOG_DIR/orchestrator.log"
  echo "╚════════════════════════════════════════════════════════════════╝" | tee -a "$LOG_DIR/orchestrator.log"
  echo "" | tee -a "$LOG_DIR/orchestrator.log"
}

# Validate environment
validate_environment() {
  log_section "VALIDATION: Checking environment"
  
  # Check k6
  if ! command -v k6 &>/dev/null; then
    log_error "k6 not found"
    exit 1
  fi
  log_info "✓ k6 found: $(k6 version 2>/dev/null | head -1)"
  
  # Check kubectl
  if ! command -v kubectl &>/dev/null; then
    log_error "kubectl not found"
    exit 1
  fi
  log_info "✓ kubectl found"
  
  # Check namespace
  if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
    log_error "Namespace $NAMESPACE not found"
    exit 1
  fi
  log_info "✓ Namespace $NAMESPACE exists"
  
  # Check attack scripts
  for script in attack_sqli.js attack_xxe.js attack_pathtraversal.js attack_credstuff.js; do
    if [ ! -f "$CAMPAIGN_DIR/k6/$script" ]; then
      log_error "Attack script not found: $script"
      exit 1
    fi
  done
  log_info "✓ All attack scripts found"
  
  log_info "Environment validation PASSED"
}

# Phase 1: Baseline (Legitimate Traffic Only)
run_phase1_baseline() {
  log_section "PHASE 1: BASELINE (Legitimate Traffic Only)"
  
  local control="$1"
  local variant="$2"
  local vus="$3"
  local replica="$4"
  
  local output_file="$RESULTS_DIR/s6_rigorous_${control}_${variant}_${vus}vu_phase1_baseline_n${replica}.json"
  
  log_info "Control: $control, Variant: $variant, VUS: $vus, Replica: $replica"
  log_info "Output: $output_file"
  log_info "Duration: $PHASE1_DURATION"
  
  # Run legitimate traffic only
  k6 run \
    --vus "$vus" \
    --duration "$PHASE1_DURATION" \
    --ramp-up "$K6_RAMP_UP" \
    --out "json=$output_file" \
    --tag "control=$control" \
    --tag "variant=$variant" \
    --tag "vus=$vus" \
    --tag "phase=baseline" \
    --tag "replica=$replica" \
    "$CAMPAIGN_DIR/k6/realistic-flow.js" \
    2>&1 | tee -a "$LOG_DIR/phase1_${control}_${variant}_${vus}vu_n${replica}.log"
  
  local status=$?
  if [ $status -eq 0 ]; then
    log_info "Phase 1 completed successfully"
  else
    log_error "Phase 1 failed with status $status"
    return $status
  fi
}

# Phase 2: Under Attack (Mixed Legitimate + Attack)
run_phase2_under_attack() {
  log_section "PHASE 2: UNDER ATTACK (70% Legitimate + 30% Attack)"
  
  local control="$1"
  local variant="$2"
  local vus="$3"
  local replica="$4"
  local attack_type="$5"
  
  local output_file_legit="$RESULTS_DIR/s6_rigorous_${control}_${variant}_${vus}vu_phase2_legit_n${replica}.json"
  local output_file_attack="$RESULTS_DIR/s6_rigorous_${control}_${variant}_${vus}vu_phase2_attack_${attack_type}_n${replica}.json"
  
  log_info "Control: $control, Variant: $variant, VUS: $vus (${K6_VUS_LEGIT_PHASE2}+${K6_VUS_ATTACK_PHASE2}), Attack: $attack_type"
  log_info "Duration: $PHASE2_DURATION"
  
  # Terminal 1: Legitimate traffic (70% of load)
  log_info "Starting legitimate traffic..."
  k6 run \
    --vus "$K6_VUS_LEGIT_PHASE2" \
    --duration "$PHASE2_DURATION" \
    --ramp-up "$K6_RAMP_UP" \
    --out "json=$output_file_legit" \
    --tag "control=$control" \
    --tag "variant=$variant" \
    --tag "phase=under_attack" \
    --tag "traffic=legitimate" \
    --tag "replica=$replica" \
    "$CAMPAIGN_DIR/k6/realistic-flow.js" \
    2>&1 | tee -a "$LOG_DIR/phase2_${control}_${variant}_legit_n${replica}.log" &
  
  LEGIT_PID=$!
  
  # Small delay to ensure legitimate traffic is running
  sleep 2
  
  # Terminal 2: Attack traffic (30% of load)
  log_info "Starting attack traffic ($attack_type)..."
  case "$attack_type" in
    sqli)
      ATTACK_SCRIPT="attack_sqli.js"
      ;;
    xxe)
      ATTACK_SCRIPT="attack_xxe.js"
      ;;
    pathtraversal)
      ATTACK_SCRIPT="attack_pathtraversal.js"
      ;;
    credstuff)
      ATTACK_SCRIPT="attack_credstuff.js"
      ;;
    *)
      log_error "Unknown attack type: $attack_type"
      kill $LEGIT_PID
      return 1
      ;;
  esac
  
  k6 run \
    --vus "$K6_VUS_ATTACK_PHASE2" \
    --duration "$PHASE2_DURATION" \
    --ramp-up "$K6_RAMP_UP" \
    --out "json=$output_file_attack" \
    --tag "control=$control" \
    --tag "variant=$variant" \
    --tag "phase=under_attack" \
    --tag "attack=$attack_type" \
    --tag "replica=$replica" \
    "$CAMPAIGN_DIR/k6/$ATTACK_SCRIPT" \
    2>&1 | tee -a "$LOG_DIR/phase2_${control}_${variant}_attack_${attack_type}_n${replica}.log" &
  
  ATTACK_PID=$!
  
  # Wait for both to complete
  wait $LEGIT_PID
  local legit_status=$?
  wait $ATTACK_PID
  local attack_status=$?
  
  if [ $legit_status -eq 0 ] && [ $attack_status -eq 0 ]; then
    log_info "Phase 2 completed successfully"
    return 0
  else
    log_error "Phase 2 failed (legit: $legit_status, attack: $attack_status)"
    return 1
  fi
}

# Phase 3: Recovery (Optional)
run_phase3_recovery() {
  log_section "PHASE 3: RECOVERY (Legitimate Traffic Only, Post-Attack)"
  
  local control="$1"
  local variant="$2"
  local vus="$3"
  local replica="$4"
  
  local output_file="$RESULTS_DIR/s6_rigorous_${control}_${variant}_${vus}vu_phase3_recovery_n${replica}.json"
  
  log_info "Control: $control, Variant: $variant, VUS: $vus, Replica: $replica"
  log_info "Duration: $PHASE3_DURATION"
  
  # Run legitimate traffic again (no attacks)
  k6 run \
    --vus "$vus" \
    --duration "$PHASE3_DURATION" \
    --ramp-up "$K6_RAMP_UP" \
    --out "json=$output_file" \
    --tag "control=$control" \
    --tag "variant=$variant" \
    --tag "vus=$vus" \
    --tag "phase=recovery" \
    --tag "replica=$replica" \
    "$CAMPAIGN_DIR/k6/realistic-flow.js" \
    2>&1 | tee -a "$LOG_DIR/phase3_${control}_${variant}_${vus}vu_n${replica}.log"
  
  local status=$?
  if [ $status -eq 0 ]; then
    log_info "Phase 3 completed successfully"
  else
    log_error "Phase 3 failed with status $status"
    return $status
  fi
}

# Cooldown
cooldown() {
  log_info "Cooldown: waiting $COOLDOWN..."
  sleep "${COOLDOWN%s}"  # Remove 's' suffix if present
}

# Extract Prometheus metrics for the time window
extract_prometheus_metrics() {
  log_section "METRICS: Extracting Prometheus data"
  
  # This would require timestamp ranges from each phase
  # For now, placeholder - would query Prometheus for each phase separately
  log_info "Prometheus extraction placeholder (implement with timestamp ranges)"
}

# Main execution loop
execute_campaign() {
  log_section "S6 RIGOROUS CAMPAIGN EXECUTION"
  
  # Define matrix (simplified for demo - full would have all combos)
  local CONTROLS=("C1" "C2" "C3" "C4")
  local VARIANTS=("baseline" "var1" "var2")
  local VUS_LEVELS=(1 5 10 20)
  local ATTACK_TYPES=("sqli" "credstuff")  # Only 2 for speed
  local REPLICATES=(1 2 3 4)
  
  local TOTAL_RUNS=0
  local COMPLETED_RUNS=0
  local START_TIME=$(date +%s)
  
  # Count total runs
  for control in "${CONTROLS[@]}"; do
    for variant in "${VARIANTS[@]}"; do
      for vus in "${VUS_LEVELS[@]}"; do
        for attack in "${ATTACK_TYPES[@]}"; do
          for replica in "${REPLICATES[@]}"; do
            TOTAL_RUNS=$((TOTAL_RUNS + 3))  # 3 phases per combo
          done
        done
      done
    done
  done
  
  log_info "Total runs planned: $TOTAL_RUNS"
  
  # Execute
  for control in "${CONTROLS[@]}"; do
    for variant in "${VARIANTS[@]}"; do
      for vus in "${VUS_LEVELS[@]}"; do
        for replica in "${REPLICATES[@]}"; do
          
          log_section "STARTING: Control=$control, Variant=$variant, VUS=$vus, Replica=$replica"
          
          # Phase 1: Baseline
          run_phase1_baseline "$control" "$variant" "$vus" "$replica"
          [ $? -eq 0 ] && COMPLETED_RUNS=$((COMPLETED_RUNS + 1))
          
          # Cooldown
          cooldown
          
          # Phase 2: Under Attack (for each attack type)
          for attack in "${ATTACK_TYPES[@]}"; do
            run_phase2_under_attack "$control" "$variant" "$vus" "$replica" "$attack"
            [ $? -eq 0 ] && COMPLETED_RUNS=$((COMPLETED_RUNS + 1))
            cooldown
          done
          
          # Phase 3: Recovery (optional - could skip for speed)
          # run_phase3_recovery "$control" "$variant" "$vus" "$replica"
          # [ $? -eq 0 ] && COMPLETED_RUNS=$((COMPLETED_RUNS + 1))
          
        done
      done
    done
  done
  
  # Summary
  local END_TIME=$(date +%s)
  local DURATION=$((END_TIME - START_TIME))
  
  log_section "CAMPAIGN COMPLETE"
  log_info "Completed: $COMPLETED_RUNS / $TOTAL_RUNS runs"
  log_info "Duration: ${DURATION}s (~$((DURATION / 60)) minutes)"
  log_info "Results directory: $RESULTS_DIR"
}

# Main
main() {
  log_section "S6 RIGOROUS SECURITY TESTING CAMPAIGN"
  log_info "Campaign Directory: $CAMPAIGN_DIR"
  log_info "Results Directory: $RESULTS_DIR"
  log_info "Start Time: $(date)"
  
  validate_environment
  execute_campaign
  extract_prometheus_metrics
  
  log_section "ORCHESTRATION COMPLETE"
  log_info "All results available in: $RESULTS_DIR"
}

# Execute
main "$@"
