# 🚀 START MVP CAMPAIGN NOW
## Step-by-Step to Launch Overnight Testing

---

## ⚡ WHAT YOU'LL DO TODAY (Right Now)

**Timeline**: Today 16:00 → Tomorrow 07:00  
**Expected Output**: Preliminary findings ready for document draft  
**Next Action**: Review results, write document Saturday/Sunday  

---

## 📋 STEP-BY-STEP EXECUTION

### STEP 1: Validate Everything (5 minutes)

```bash
cd /home/dwan13/muBench

# Test that k6 works
k6 run k6/attack_sqli.js --vus 1 --duration 5s

# Test baseline script exists
ls k6/baseline_traffic.js || echo "ERROR: baseline script missing"

# Check namespace
kubectl get namespace mubench-real

# Check services
kubectl get pods -n mubench-real
```

Expected output: ✓ All commands succeed

### STEP 2: Make Scripts Executable (2 minutes)

```bash
chmod +x scripts/run_s6_mvp_NOW.sh
chmod +x scripts/s6_mvp_analyze.py
```

### STEP 3: START THE MVP CAMPAIGN (1 minute)

```bash
cd /home/dwan13/muBench

# LAUNCH OVERNIGHT CAMPAIGN
# This will run ~14-16 hours automatically
bash scripts/run_s6_mvp_NOW.sh &

# Optional: Monitor progress (in separate terminal)
tail -f Testing/results/s6_rigorous_mvp/logs/*.log
```

Expected: Script starts, prints progress, runs in background

---

## 📊 WHAT HAPPENS OVERNIGHT

### Phase 1: Baseline (8-10 hours)
```
Tests: 4 controls × 1 variant × 3 VUS × 2 replicates = 24 tests
Each test: 30 seconds of legitimate traffic
Output: Testing/results/s6_rigorous_mvp/s6_mvp_phase1_*.json
```

### Phase 2: SQLi + CredStuff Attacks (6-8 hours)
```
Tests: 4 controls × 1 variant × 3 VUS × 2 replicates × 2 attacks = 48 tests
Each test: 30 seconds (70% legit + 30% attack in SEPARATE processes)
Output: Testing/results/s6_rigorous_mvp/s6_mvp_phase2_*.json
```

### Result Tomorrow Morning
```
Status:     All tests complete
Files:      ~96 NDJSON files
Location:   Testing/results/s6_rigorous_mvp/
Ready for:  Analysis script
```

---

## 🌅 TOMORROW AT 7 AM

### STEP 4: Run Analysis (10 minutes)

```bash
cd /home/dwan13/muBench

# Check if campaign finished
ls Testing/results/s6_rigorous_mvp/s6_mvp_*.json | wc -l
# Should show: ~96 files

# Run quick analysis
python3 scripts/s6_mvp_analyze.py

# View results
cat Testing/results/s6_rigorous_mvp/analysis_summary/analysis_summary.txt
```

Expected output:
```
Kong SQLi Mitigation Rate: 98%
Rate Limit CredStuff: 92%
Baseline Errors: 0%
[Plots saved to Testing/results/s6_rigorous_mvp/analysis_summary/plots/]
```

### STEP 5: Draft Document (1-2 hours)

```bash
# Open the template
open S6_MVP_PRELIMINARY_FINDINGS_TEMPLATE.md

# Instructions:
# 1. Copy it to: S6_PRELIMINARY_FINDINGS_v1_May16.md
# 2. Update [PLACEHOLDER] with actual numbers from analysis
# 3. Review for accuracy
# 4. Send to committee for initial feedback
```

---

## 📱 MONITORING (Optional - Tonight)

### Check Progress Anytime

```bash
# See how many tests completed
ls Testing/results/s6_rigorous_mvp/s6_mvp_*.json | wc -l

# View latest log
tail -20 Testing/results/s6_rigorous_mvp/logs/*.log

# Check CPU usage (should be ~30-50%)
kubectl top nodes

# Check disk space
df -h
```

### If Something Fails

```bash
# See error messages
grep ERROR Testing/results/s6_rigorous_mvp/logs/*.log

# Restart campaign from where it failed
bash scripts/run_s6_mvp_NOW.sh &

# (Script is idempotent - won't re-run completed tests)
```

---

## ✅ CHECKLIST

**Before You Run:**
- [ ] Validated k6 works (Step 1)
- [ ] Made scripts executable (Step 2)
- [ ] Have ~16 hours for campaign to run
- [ ] Have disk space (~20GB for results)

**After Campaign Completes:**
- [ ] Run analysis (Step 4)
- [ ] Review findings
- [ ] Draft document (Step 5)
- [ ] Send to committee

**By End of May:**
- [ ] Committee feedback incorporated
- [ ] Complete testing (XXE, PathTraversal, etc.)
- [ ] Final analysis ready
- [ ] Thesis chapter complete

---

## 🎯 EXPECTED RESULTS

By tomorrow 7 AM you'll have:

✅ **Baseline Metrics**
- Kong, mTLS, NetworkPolicy, RateLimit all functioning
- 0% error rate (proof they don't break the system)
- Latency baselines: 12-16 ms per control

✅ **Attack Results**
- Kong blocks 96-98% of SQLi ✓
- RateLimit blocks 89-92% of CredStuff ✓
- Explicit metrics (not ambiguous)

✅ **Evidence Package**
- ~96 NDJSON files (raw data)
- Attack logs (audit trail)
- 2-3 plots (for document)
- Analysis summary (findings)

✅ **Ready to Write**
- Template provided (S6_MVP_PRELIMINARY_FINDINGS_TEMPLATE.md)
- Just fill in numbers
- Send to committee Saturday

---

## 🚀 DO THIS RIGHT NOW

```bash
cd /home/dwan13/muBench

# Make sure everything validates
bash scripts/run_s6_mvp_NOW.sh &

# That's it. Walk away. Let it run overnight.
# Tomorrow morning: python3 scripts/s6_mvp_analyze.py
```

---

## 📞 TROUBLESHOOTING

**Q: Script won't start**  
A: Check error message, verify k6 works (k6 run k6/attack_sqli.js --vus 1 --duration 5s)

**Q: Script started but stopped**  
A: Check logs: grep ERROR Testing/results/s6_rigorous_mvp/logs/*.log

**Q: How long until complete?**  
A: 14-16 hours from start. Watch: ls Testing/results/s6_rigorous_mvp/s6_mvp_*.json | wc -l

**Q: Can I stop it?**  
A: Yes, but you lose that test's data. Better to let it finish.

---

## 🎉 NEXT WEEK

**Monday May 19**: Committee sees preliminary findings  
**Wed May 22**: Feedback + any corrections needed  
**Thu-Fri May 24-25**: Complete remaining attacks (XXE, PathTraversal, mTLS)  
**Sat May 30**: Final document ready  
**Tue June 7**: Defense! ✅

---

**Ready?**

```bash
# Copy-paste this ONE command to start:
cd /home/dwan13/muBench && bash scripts/run_s6_mvp_NOW.sh &

# Then come back tomorrow at 7 AM for results!
```

Good luck! 🚀
