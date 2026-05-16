# S6 RIGOROUS FRAMEWORK - EXECUTION CHECKLIST
## Step-by-Step Guide to Defense-Ready Security Evaluation

**Status**: ✅ Framework Complete  
**Audience**: You, Your Committee, Jury  
**Timeline**: 4-5 weeks from now

---

## 📋 PRE-EXECUTION PHASE (This Week)

### Committee Briefing
- [ ] **Day 1-2**: Schedule committee meeting (30 min)
- [ ] **Day 1**: Send them:
  - `S6_RIGOROUS_COMPLETE_FRAMEWORK_SUMMARY.md` (10 min read)
  - `S6_THREAT_MODEL_RIGOROUS.md` (20 min read)
  - Ask: "Are these 6 attack vectors appropriate for our scope?"
- [ ] **Day 3**: Committee meeting
  - Present threat model (5 min)
  - Get approval: "Threat model is academically acceptable"
  - Show attack script examples (2 min)
  - Answer questions
  - **APPROVAL NEEDED**: Committee agrees to proceed

### Infrastructure Validation
- [ ] **Day 4**: Verify Kubernetes cluster
  ```bash
  kubectl get namespace mubench-real
  kubectl get pods -n mubench-real
  ```
  Expected: All pods running (auth-service, api-service, data-service, postgres)

- [ ] **Day 4**: Verify k6 installation
  ```bash
  k6 version
  ```
  Expected: v0.50.0 or later

- [ ] **Day 4**: Verify attack scripts exist and syntax is valid
  ```bash
  k6 run k6/attack_sqli.js --vus 1 --duration 10s
  # Should complete without syntax errors
  k6 run k6/attack_xxe.js --vus 1 --duration 10s
  k6 run k6/attack_pathtraversal.js --vus 1 --duration 10s
  k6 run k6/attack_credstuff.js --vus 1 --duration 60s
  ```
  Expected: All scripts run, log metrics (check console output)

- [ ] **Day 5**: Verify controls are deployed
  ```bash
  # Check Kong (C1)
  kubectl get ingress -n mubench-real  # Kong ingress controller
  
  # Check mTLS (C2)
  kubectl get peerauthentication -n mubench-real  # Istio mTLS policy
  
  # Check NetworkPolicy (C3)
  kubectl get networkpolicy -n mubench-real
  
  # Check rate limit (C4) - Kong config
  kubectl get kongplugin -n mubench-real  # Rate limit plugin
  ```
  Expected: All controls visible and active

- [ ] **Day 5**: Verify Prometheus
  ```bash
  curl http://prometheus:9090/api/v1/query?query=node_cpu_seconds_total
  ```
  Expected: Returns data (Prometheus scraping cluster metrics)

- [ ] **Day 5**: Prepare results directory
  ```bash
  mkdir -p Testing/results/s6_rigorous/{logs,attack_logs}
  chmod 777 Testing/results/s6_rigorous
  ```

- [ ] **Day 5**: Backup existing data
  ```bash
  tar czf backup_before_s6_rigorous_$(date +%Y%m%d).tar.gz \
    Testing/results/auto_runs/randomized_campaigns/*.json
  # Copy backup to external drive/cloud
  ```

### Documentation Review (Internal)
- [ ] Read all 4 strategic documents:
  - [ ] S6_RIGOROUS_COMPLETE_FRAMEWORK_SUMMARY.md (10 min)
  - [ ] S6_EXECUTIVE_GUIDE_FOR_DEFENSE.md (20 min)
  - [ ] S6_EXPERT_EVALUATION_RIGOROUS_ANALYSIS.md (60 min)
  - [ ] S6_THREAT_MODEL_RIGOROUS.md (30 min)
  - [ ] S6_RIGOROUS_WHY_THIS_WORKS.md (15 min)

- [ ] Understand the three-phase model:
  - [ ] Phase 1 (Baseline): Legitimate traffic only, 30s
  - [ ] Phase 2 (Under Attack): 70% legit + 30% attack, 30s
  - [ ] Phase 3 (Recovery): Legitimate only, 30s

- [ ] Understand the key metrics:
  - [ ] `attack_sent_count`: Total attacks injected
  - [ ] `attack_blocked_count`: Attacks with 401/403/429 status
  - [ ] `attack_leaked_count`: Attacks with 200 OK (FAILURES)
  - [ ] `mitigation_rate = (blocked / sent) * 100%` (KEY METRIC)

---

## 🚀 EXECUTION PHASE (Weeks 2-3)

### Week 2: Phase 1 - Baseline Campaign

**Goal**: Establish clean performance baseline WITHOUT attacks

- [ ] **Monday AM**: Start Phase 1 baseline
  ```bash
  cd /home/dwan13/muBench
  bash scripts/run_s6_rigorous_orchestrator.sh
  ```
  
  Script will:
  1. Validate environment
  2. Iterate: Control×Variant×VUS×Replica (4×3×4×4 = 192 cells)
  3. Run Phase 1 (baseline) for each
  4. Log results to: Testing/results/s6_rigorous/

- [ ] **Monday PM**: Monitor progress
  ```bash
  tail -f Testing/results/s6_rigorous/logs/orchestrator.log
  ls -l Testing/results/s6_rigorous/s6_rigorous_*.json | wc -l
  # Should see files accumulating
  ```
  Expected: 1-2 files per minute initially

- [ ] **Tuesday-Wednesday**: Let run (~8-10 hours total)
  - Expected runtime: ~8-10 hours for 192 Phase 1 runs
  - No action needed (process runs autonomously)
  - Check periodically: are files accumulating?

- [ ] **Wednesday PM**: Verify Phase 1 completion
  ```bash
  ls Testing/results/s6_rigorous/s6_rigorous_*_phase1_*.json | wc -l
  # Should be ~192 files
  ```

### Week 2-3: Phase 2 - Attack Campaigns

**Goal**: Measure control effectiveness under attack

- [ ] **Wednesday PM**: Start Phase 2a - SQLi Attack
  ```bash
  # Resume orchestrator (it continues from where Phase 1 ended)
  bash scripts/run_s6_rigorous_orchestrator.sh
  ```
  
  Will run:
  1. Phase 1 baseline (skip if already done)
  2. Phase 2 under_attack with SQLi vector
  3. Log to: Testing/results/s6_rigorous/attack_logs/sqli_*

- [ ] **Thursday-Friday**: Let run (~8-10 hours)
  Expected: 192 Phase 2a runs with SQLi metrics
  
- [ ] **Friday PM**: Verify Phase 2a completion
  ```bash
  ls Testing/results/s6_rigorous/s6_rigorous_*_phase2_*_sqli_*.json | wc -l
  # Should be ~192 files
  
  cat Testing/results/s6_rigorous/attack_logs/sqli_*/summary.txt
  # Should show: sqli_sent_total, sqli_blocked_total, etc.
  ```

- [ ] **Friday PM**: Start Phase 2b - CredStuff Attack
  ```bash
  bash scripts/run_s6_rigorous_orchestrator.sh
  ```
  
  Will run:
  1. Phase 2 under_attack with CredStuff vector
  
- [ ] **Weekend**: Let run (~8-10 hours)
  Expected: 192 Phase 2b runs

- [ ] **Monday AM**: Verify Phase 2b completion
  ```bash
  ls Testing/results/s6_rigorous/s6_rigorous_*_phase2_*_credstuff_*.json | wc -l
  # Should be ~192 files
  
  cat Testing/results/s6_rigorous/attack_logs/credstuff_*/summary.txt
  ```

### Optional: Phase 3 - Recovery
- [ ] **Monday PM** (optional): Run Phase 3 recovery
  ```bash
  bash scripts/run_s6_rigorous_orchestrator.sh
  ```
  Will verify system recovers to baseline after attacks

---

## 📊 ANALYSIS PHASE (Week 4)

### Data Aggregation

- [ ] **Monday**: Aggregate NDJSON files into CSV
  ```bash
  python3 Testing/analyze_s6_rigorous_results.py \
    --input-glob="Testing/results/s6_rigorous/s6_rigorous_*.json" \
    --output="Testing/results/s6_rigorous_all_metrics.csv"
  ```
  
  Expected output:
  ```
  control,variant,vus,attack_type,phase,replica,avg_ms,p95_ms,err_pct,rps,cpu_mcores,mem_mib,attack_sent,attack_blocked,attack_leaked,mitigation_rate
  C1,baseline,1,sqli,under_attack,1,5.2,12.1,0.0,19.2,250,180,100,98,2,98.0
  ...
  ```

- [ ] **Monday**: Extract Prometheus metrics (CPU, memory)
  ```bash
  python3 scripts/extract_prometheus_metrics.py \
    --prom-url="http://prometheus:9090" \
    --namespace="mubench-real" \
    --metric-file="Testing/results/s6_rigorous_all_metrics.csv" \
    --output="Testing/results/s6_rigorous_all_metrics_with_prometheus.csv"
  ```
  
  Adds: cpu_baseline, cpu_under_attack, mem_baseline, mem_under_attack

### Statistical Analysis

- [ ] **Tuesday**: Run ANOVA analysis
  ```bash
  python3 Testing/s6_statistical_analysis_rigorous.py \
    --input="Testing/results/s6_rigorous_all_metrics_with_prometheus.csv" \
    --output-dir="Testing/results/s6_analysis"
  ```
  
  Generates:
  - ANOVA tables (one per metric)
  - Plots (latency by control, mitigation by attack, etc.)
  - threat_model_matrix.csv (attack × control effectiveness)

- [ ] **Tuesday**: Generate plots
  - Plot 1: Mitigation Rate by Control × Attack Type
    X-axis: Attack (SQLi, XXE, CredStuff, etc.)
    Y-axis: Mitigation Rate (%)
    Series: C1, C2, C3, C4
    Expected: Kong (C1) highest for injection attacks, Rate Limit (C4) highest for brute force
    
  - Plot 2: Latency Overhead by Control
    X-axis: Control
    Y-axis: Latency Overhead (ms)
    Expected: C3 (<2%), C4 (~1%), C1 (~12%), C2 (~30%)
    
  - Plot 3: ROI (Security Benefit per Latency Cost)
    X-axis: Control
    Y-axis: mitigation_rate / latency_overhead
    Expected: C4 highest, C2 lowest
    
  - Plot 4: CPU Cost by Control
    X-axis: Control
    Y-axis: CPU increase (millicores)
    Expected: C3 lowest, C2 highest

- [ ] **Wednesday**: Validate results make sense
  - [ ] Mitigation rates in 0-100% range? ✓
  - [ ] Latency overhead positive (controls add cost)? ✓
  - [ ] False positive rate < 0.5%? ✓
  - [ ] Any anomalies? Investigate
  
  If anomaly detected:
  ```bash
  # Re-check one cell manually
  cat Testing/results/s6_rigorous/logs/phase2_C1_baseline_sqli_1VU_n1.log
  # Look for errors or incomplete runs
  ```

### Finding Narrative

- [ ] **Thursday**: Write findings chapter for thesis
  - Threshold: Use findings from ANOVA + plots
  - Claim 1: "Control effectiveness is measurable and attack-specific"
    Evidence: Mitigation rates (Kong SQLi=98%, Rate Limit=89%, etc.)
  - Claim 2: "Security has a latency cost"
    Evidence: C1 adds 12%, C2 adds 30%, C3 adds 1%
  - Claim 3: "Optimal deployment depends on risk profile"
    Evidence: ROI analysis, deployment recommendations

---

## 🎤 DEFENSE PHASE (Week 5)

### Presentation Preparation

- [ ] **Monday**: Create slide deck (~10-15 minutes)
  1. Title slide (3 slides)
  2. Problem statement (1 slide): S2 has security gap
  3. Threat model (1 slide): 6 attack vectors mapped to OWASP
  4. Experimental design (1 slide): Three-phase model
  5. Key findings (3 slides):
     - Plot: Mitigation by control
     - Plot: Latency overhead
     - Plot: ROI
  6. Control recommendations (1 slide): Deployment order + rationale
  7. Limitations (1 slide): Scope boundaries, non-claims
  8. Conclusion (1 slide): S6 enables rigorous security evaluation
  9. Backup slides: Attack logs, raw data samples, scripts

- [ ] **Tuesday**: Practice presentation (10 min talk)
  - Do it once alone (record yourself)
  - Do it twice with advisor/colleague
  - Aim for 10-15 minute presentation + 10-15 min Q&A

- [ ] **Tuesday**: Prepare jury Q&A responses (memorize key points)
  From S6_EXPERT_EVALUATION_RIGOROUS_ANALYSIS.md Section 7:
  - [ ] Q1: "Why should we believe these results aren't faked?"
  - [ ] Q2: "Why only these 6 attacks?"
  - [ ] Q3: "What's the most important control?"
  - [ ] Q4: "Why is latency lower in attack mode?" (not an issue in rigorous S6)
  - [ ] Q5-10: Additional questions in jury bank

- [ ] **Wednesday**: Prepare artifacts for defense
  - [ ] USB drive with all NDJSON files (proof)
  - [ ] CSV with aggregated metrics
  - [ ] Attack logs (s6_attack_logs/sqli_requests.log, etc.)
  - [ ] Screenshots of scripts + GitHub commits
  - [ ] Live demo (optional): Run attack_sqli.js script if committee wants to see

### Defense Day

- [ ] **Thursday or Friday**: Defense presentation
  - [ ] Test all slides work on venue computer
  - [ ] Have backup on USB + cloud
  - [ ] Bring printed copies of key plots
  - [ ] Bring attack logs (physical or digital)
  
  **Presentation Structure**:
  1. Opening: "S2 showed performance costs of security, but didn't prove security works."
  2. Threat model: "We test 6 OWASP attack vectors."
  3. Design: "Three phases: baseline, under attack, recovery."
  4. Findings: "Kong blocks 98% of SQLi, mTLS blocks 100% of unauth pod access."
  5. Recommendations: "Deploy in order: C4→C3→C1→C2 based on ROI."
  6. Limitations: "Representative scope, not exhaustive security evaluation."
  
  **Q&A Strategy**:
  - Listen carefully to question
  - Refer to jury bank (S6_EXPERT_EVALUATION_RIGOROUS_ANALYSIS.md Section 7)
  - Show evidence: attack logs, metrics, scripts
  - Admit if you don't know: "That's a good point, let me check the data..."
  - Stay honest: Don't overclaim security

- [ ] **Friday PM**: Await results ✅

---

## 📋 FINAL VERIFICATION CHECKLIST (Before Defense)

### Data Integrity
- [ ] All NDJSON files preserved (not deleted)
- [ ] CSV with all metrics generated
- [ ] Prometheus data extracted (CPU, memory)
- [ ] No missing data points (< 5% allowed)
- [ ] Attack logs preserved (s6_attack_logs/)

### Statistical Validity
- [ ] ANOVA results computed (F-stats, p-values)
- [ ] Effect sizes reported (η²)
- [ ] Assumptions checked (normality, homogeneity)
- [ ] Confidence intervals on mitigation rates
- [ ] Outliers identified and explained

### Presentation Quality
- [ ] Slide deck complete (10-15 min)
- [ ] Plots labeled and legend clear
- [ ] Findings grounded in data (not speculation)
- [ ] Limitations acknowledged
- [ ] Recommendations justified (ROI-based)

### Reproducibility Package
- [ ] Attack payloads documented (OWASP source links)
- [ ] k6 scripts version-controlled
- [ ] Orchestrator script commented
- [ ] Results reproducible (±5% variability tolerated)
- [ ] GitHub repo has full audit trail

---

## 🎯 SUCCESS CRITERIA (Thesis Defense)

### Jury Will Look For:
- [ ] **Rigor**: Design is scientifically sound ✓ (three-phase, explicit hypotheses)
- [ ] **Evidence**: Metrics support claims ✓ (mitigation rates, latency overhead)
- [ ] **Honesty**: Limitations acknowledged ✓ (explicit non-claims)
- [ ] **Reproducibility**: Anyone could verify ✓ (OWASP payloads, version control)
- [ ] **Operationality**: Results are actionable ✓ (deployment recommendations)

### Expected Jury Questions (You're Prepared):
- [ ] "Why should we trust this data?" → Jury Q&A Bank, Section 7.1
- [ ] "Why these 6 attacks?" → Jury Q&A Bank, Section 7.2
- [ ] "What's the most important control?" → Jury Q&A Bank, Section 7.3
- [ ] "Can you reproduce this?" → Show GitHub + attack logs
- [ ] "What weren't you testing?" → Show explicit non-claims

---

## 📞 EMERGENCY CONTACTS

### If Something Goes Wrong

**Problem**: k6 script fails  
**Solution**: Run individually to debug
```bash
k6 run k6/attack_sqli.js --vus 1 --duration 5s -v  # Verbose output
```

**Problem**: Prometheus metrics not available  
**Solution**: Check Prometheus is scraping
```bash
curl http://prometheus:9090/api/v1/query?query=up
# Should return: {"status":"success","data":{...}}
```

**Problem**: Attack logs not being written  
**Solution**: Check directory permissions
```bash
ls -ld Testing/results/s6_rigorous/attack_logs/
# Should be: drwxrwxrwx (777 permissions)
```

**Problem**: Data looks suspicious (anomalies)  
**Solution**: Go back to raw logs
```bash
cat Testing/results/s6_rigorous/logs/*.log | grep ERROR
# Look for messages about what went wrong
```

---

## ✅ COMPLETION CHECKLIST

**After Defense Concludes**:
- [ ] Jury accepted thesis ✅
- [ ] Both theses defended successfully ✅
- [ ] Celebrate! 🎉

---

**PRINT THIS CHECKLIST.** Use it as your daily guide for 4-5 weeks.

Each item is a **checkpoint**. Don't skip any.

**Status**: Ready to execute  
**Start Date**: Week 1 (now)  
**End Date**: Week 5 (defense)  
**Expected Outcome**: ✅ Both theses defended with rigorous S6 evidence

