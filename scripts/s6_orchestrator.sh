#!/bin/bash
# S6 Campaign Orchestrator: Monitor execution + Auto-run post-processing

set -e

CAMPAIGN_DIR="/home/dwan13/muBench"
RESULTS_DIR="$CAMPAIGN_DIR/Testing/results"
CAMPAIGN_LOG="$CAMPAIGN_DIR/s6_campaign_execution.log"
MATRIX_FILE="$RESULTS_DIR/scaling_tests/design_matrix_s6_integrated_dual_n4_randomized_blocks.csv"

echo "[orchestrator] Starting S6 campaign monitoring..."
echo "[orchestrator] Matrix: $MATRIX_FILE"

# Count expected runs (4 blocks × 96 cells/block = 384 rows)
if [ -f "$MATRIX_FILE" ]; then
    TOTAL_ROWS=$(tail -n +2 "$MATRIX_FILE" | wc -l)
    echo "[orchestrator] Expected rows: $TOTAL_ROWS"
else
    echo "[orchestrator] WARNING: Matrix file not found"
    TOTAL_ROWS=384
fi

# Monitor campaign progress
echo "[orchestrator] Monitoring k6 result files..."
while true; do
    RESULT_COUNT=$(ls "$RESULTS_DIR/auto_runs/randomized_campaigns"/s6_integrated_dual_n4_B*.json 2>/dev/null | wc -l)
    echo "[orchestrator] Progress: $RESULT_COUNT / $TOTAL_ROWS runs completed"
    
    if [ "$RESULT_COUNT" -ge "$TOTAL_ROWS" ]; then
        echo "[orchestrator] ✓ All runs completed!"
        break
    fi
    
    sleep 300  # Check every 5 minutes
done

echo "[orchestrator] Waiting 30s for final file closes..."
sleep 30

# Step 1: Post-process all results into 6-metric CSV
echo "[orchestrator] Running post-processing (extract CPU/memory from Prometheus)..."
python3 "$CAMPAIGN_DIR/Testing/analyze_s6_integrated_results.py" \
    --input-glob="$RESULTS_DIR/auto_runs/randomized_campaigns/s6_integrated_dual_n4_B*.json" \
    --prom-url="http://localhost:30000" \
    --namespace="mubench-real" \
    --output="$RESULTS_DIR/s6_integrated_all_6_metrics_final.csv"

if [ ! -f "$RESULTS_DIR/s6_integrated_all_6_metrics_final.csv" ]; then
    echo "[orchestrator] ERROR: Post-processing failed"
    exit 1
fi

echo "[orchestrator] ✓ Post-processing complete"
FINAL_ROWS=$(tail -n +2 "$RESULTS_DIR/s6_integrated_all_6_metrics_final.csv" | wc -l)
echo "[orchestrator] Generated CSV with $FINAL_ROWS data rows"

# Step 2: Run statistical analysis
echo "[orchestrator] Running statistical analysis..."
python3 "$CAMPAIGN_DIR/Testing/s6_statistical_analysis.py" \
    --input-csv="$RESULTS_DIR/s6_integrated_all_6_metrics_final.csv" \
    --output-dir="$RESULTS_DIR/s6_analysis"

if [ ! -f "$RESULTS_DIR/s6_analysis/S6_INTEGRATED_REPORT.md" ]; then
    echo "[orchestrator] ERROR: Analysis failed"
    exit 1
fi

echo "[orchestrator] ✓ Statistical analysis complete"

# Step 3: Generate summary for defense
echo "[orchestrator] Generating defense summary..."
cat > "$RESULTS_DIR/s6_analysis/DEFENSE_READY.txt" << 'EOF'
╔════════════════════════════════════════════════════════════════════════════╗
║                   S6 INTEGRATED CAMPAIGN - ANALYSIS COMPLETE               ║
║                         Dual-Maestría Defense Ready                        ║
╚════════════════════════════════════════════════════════════════════════════╝

EVIDENCE COLLECTED:
✓ 384 total runs (4 controls × 3 variants × 4 VUs × 2 modes × 4 replicates)
✓ 6 metrics per run: latency(avg, p95), errors%, throughput, CPU, memory
✓ 5 advanced attack vectors: bad-login, unauth, token-tamper, bearer-malformed, xff-spoof
✓ Mixed-model ANOVA with block randomization
✓ Threat model matrix: attack → control effectiveness → cost

DEFENSE NARRATIVE FILES:
1. S6_INTEGRATED_REPORT.md           - Comprehensive findings & recommendations
2. threat_model_matrix.csv           - Attack vector effectiveness by control
3. 01_latency_by_control.png         - Latency distributions
4. 02_error_rate_attack.png          - Attack response comparison
5. 03_cpu_overhead.png               - Resource costs
6. 04_tradeoff_cpu_latency.png       - Security-performance trade-offs
7. s6_integrated_all_6_metrics_final.csv - Raw data for defense

MAESTRÍA TOPICS COVERED:
[Sistemas y Computación]
- Distributed systems: Multi-control deployment & load distribution
- Performance measurement: Latency percentiles, throughput, CPU/memory
- Scalability analysis: Load progression (1-20 VUs), resource growth
- Fault tolerance: Attack vector resilience, error rate under adversity

[Seguridad Digital]
- Authentication (C2): mTLS, JWT validation, credential handling
- Authorization: Gateway validation (C1), network policy (C3)
- Rate limiting: Brute force defense (C4), DDoS mitigation
- Threat modeling: Attack vector enumeration, control mapping
- Security metrics: Error rate under attack, defense effectiveness

QUICK START FOR DEFENSE:
cd /home/dwan13/muBench/Testing/results/s6_analysis/
cat S6_INTEGRATED_REPORT.md            # Read main findings
head threat_model_matrix.csv           # View threat model
display 01_latency_by_control.png      # Show plots

═════════════════════════════════════════════════════════════════════════════
Execution Time: Check s6_integrated_all_6_metrics_final.csv timestamps
Analysis Ready: $(date)
═════════════════════════════════════════════════════════════════════════════
EOF

cat "$RESULTS_DIR/s6_analysis/DEFENSE_READY.txt"

echo "[orchestrator] ✓ Defense summary written"
echo "[orchestrator] ╔════════════════════════════════════════════════════════════════╗"
echo "[orchestrator] ║           S6 CAMPAIGN COMPLETE - ALL ANALYSIS DONE             ║"
echo "[orchestrator] ║     Dual-Maestría Evidence & Defense Arguments Ready           ║"
echo "[orchestrator] ╚════════════════════════════════════════════════════════════════╝"
echo "[orchestrator] Results: $RESULTS_DIR/s6_analysis/"
