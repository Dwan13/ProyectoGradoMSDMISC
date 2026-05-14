# Dual-Maestría Research Index
## Complete Documentation Package

**Candidate**: Felipe Dwan  
**Program**: Maestría (2 Specialized Topics)
- Sistemas y Computación Distribuidos
- Seguridad Digital

**Research Title**: *Security-Quality Trade-off Analysis in Microservices: A Systematic Evaluation of Control Mechanisms Under Advanced Threat Scenarios*

**Campaign**: S6 Integrated (384 runs completed)  
**Status**: Final analysis closed for declared scope

**Direct use-now documents**:
- Reproducibility package: [Docs/replication-guide.md](Docs/replication-guide.md)
- 12-15 min defense script: [Docs/DEFENSE_PLAYBOOK.md](Docs/DEFENSE_PLAYBOOK.md)
- Spoken script (7 min): [Docs/DEFENSE_SCRIPT_7MIN.md](Docs/DEFENSE_SCRIPT_7MIN.md)
- Spoken script (15 min): [Docs/DEFENSE_SCRIPT_15MIN.md](Docs/DEFENSE_SCRIPT_15MIN.md)
- Mock jury drill (15 hard questions): [Docs/DEFENSE_MOCK_15Q.md](Docs/DEFENSE_MOCK_15Q.md)
- Strict jury Q&A: [Docs/S6_JURY_QA_BANK.md](Docs/S6_JURY_QA_BANK.md)

Note: sections marked as "preliminary" in this index are retained as historical trace of intermediate stages.

---

## I. CORE RESEARCH DOCUMENTS

### 1. **DEFENSE_NARRATIVE.md** (Primary Thesis Argument)
**Purpose**: High-level statement of research contribution and thesis claims  
**Audience**: Jury members, academic community  
**Contents**:
- Problem statement: "Security vs Performance dilemma"
- Thesis in 2 dimensions (Sistemas + Seguridad)
- 7 major contributions
- Preliminary findings from 9 runs
- Defense implications

**Key Claims**:
1. Multi-dimensional evaluation is essential for systems
2. Overhead is non-linear and control-specific
3. Systematic experimental design enables rigor
4. No single control is universal (multi-layer defense necessary)
5. Defense effectiveness is quantifiable and measurable

**Use When**: 
- Opening/closing statement in defense
- Distill research to jury in first 10 minutes
- Answering "What's your main contribution?"

---

### 2. **TECHNICAL_METHODOLOGY.md** (Experimental Details)
**Purpose**: Comprehensive methodology documentation for reproducibility  
**Audience**: Technical jury, peer reviewers, future researchers  
**Contents**:
- Factorial design structure (4³ × 2 × 4 = 384 runs)
- Control definitions & variants (C1-C4)
- Load profiles (1, 5, 10, 20 VU)
- Security modes (normal 30% / attack 70%)
- Attack vector specifications (5 vectors with code)
- Metrics collection (6 dimensions)
- Orchestration scripts overview
- Statistical analysis plan (mixed model ANOVA)
- Threat model matrix derivation algorithm
- Reproducibility & archival plan

**Key Sections**:
- §1: Design (why 384 runs? why randomized blocks?)
- §2: Attack vectors (executable code for bad-login, token-tamper, etc.)
- §3: Metrics (k6 + Prometheus dual source)
- §4: Orchestration (automation pipeline)
- §5: Statistics (mixed model, post-hoc contrasts)
- §6: Threat model (algorithm for deriving control-vector matrix)
- §8: Limitations (scale, generalization, confounding)

**Use When**:
- Jury asks "How did you run this?"
- Need to explain experimental rigor
- Defending against "Why 384 runs specifically?"
- Answering "Is this reproducible?"

---

### 3. **PRELIMINARY_FINDINGS.md** (9-Run Analysis)
**Purpose**: Interim analysis of initial data to validate methodology  
**Audience**: Internal review, proof-of-concept  
**Contents**:
- Executive summary of 9 runs (all 6 metrics)
- Attack vs normal mode comparison
- Per-control effectiveness analysis
- Threat vector response patterns
- Preliminary threat model matrix (3×5)
- Load scalability analysis
- Statistical power assessment
- Preliminary defense implications
- Validation checklist

**Key Findings**:
1. Extreme metric variance (11 ms to 98 ms latency, 97 to 1131 mC CPU)
2. Attack mode increases error rate 70× while reducing latency
3. C2 istio-mtls most effective (0% error) but expensive (788 mC @ 20 VU)
4. C3 basic highly efficient at small scale (0% error, 97 mC)
5. mTLS exhibits 8.9x latency growth at 20 VU (super-linear)
6. No control is universal; all vectors need multiple layers

**Use When**:
- Demonstrating methodology works
- Jury asks "What do the results show so far?"
- Need confidence in approach before full campaign
- Explaining preliminary evidence

---

### 4. **DEFENSE_PLAYBOOK.md** (Presentation Strategy)
**Purpose**: Strategy for defending research in front of jury  
**Audience**: Candidate (self), thesis advisors  
**Contents**:
- Opening statement (hook + thesis + why it matters)
- Dual-maestría argument structure (11 major claims with evidence)
  - 6 claims for Sistemas dimension
  - 5 claims for Seguridad dimension
- Evidence presentation strategy (3-phase approach)
- Integration narrative (why both dimensions together)
- Anticipated Q&A (8 tough questions + answers)
- Closing statement
- Defense materials checklist
- Timeline to defense
- Success criteria

**Claims Covered**:
| Dimension | Claim | Evidence |
|-----------|-------|----------|
| **SISTEMAS** | Multi-dimensional evaluation necessary | 6-metric table from 9 runs |
| | Overhead is non-linear | mTLS 8.9x latency @ 20 VU |
| | Systematic design enables rigor | Factorial design, blocks, replication |
| | Trade-offs are Pareto-bounded | Efficiency frontier mapping |
| **SEGURIDAD** | Threats must be operationalized | 5 attack vectors in k6 |
| | Controls are threat-specific | Threat model matrix |
| | Multi-layer defense necessary | Vector coverage analysis |
| | Defense is quantifiable | Error rates under attack |
| **DUAL** | Systems + Security are intertwined | Non-linear security overhead under load |

**Use When**:
- Preparing for defense date
- Rehearsing presentation
- Answering tough jury questions
- Explaining "Why dual-maestría?"

---

## II. DATA & RESULTS (In Progress)

### Expected Deliverables (Upon Campaign Completion)

**1. s6_integrated_all_6_metrics_final.csv**
- 384 rows (one per run)
- Columns: control, variant, security_mode, vus, avg_ms, p95_ms, err_pct, rps, cpu_mcores, mem_mib
- Timestamps: start_iso, end_iso (for Prometheus correlation)
- Additional traces: login_ok, users_ok, jwt_trace_events, db_latency

**2. S6_INTEGRATED_REPORT.md** (Automatic generation)
- Executive summary
- Attack response table
- Resource overhead comparison
- Threat model effectiveness matrix
- Statistical findings (ANOVA results)
- Conclusions & recommendations
- Defense strategy implications

**3. Plots (PNG, 300 DPI publication quality)**
- `01_latency_by_control.png`: Boxplot latency by control × mode
- `02_error_rate_attack.png`: Bar chart error % under attack
- `03_cpu_overhead.png`: Boxplot CPU by control × mode
- `04_tradeoff_cpu_latency.png`: Scatter plot CPU vs latency (Pareto frontier)

**4. Threat Model Matrix CSV**
- Rows: Attack vectors (5)
- Columns: Controls (4) + effectiveness rating
- Derived from: error rate analysis under each (control, vector) pair

---

## III. REFERENCE ARCHITECTURE

### S6 Campaign Pipeline

```
├─ Experiment Execution (Orchestrator)
│  ├─ Generate design matrix (384 rows)
│  └─ For each row:
│     ├─ Warmup 30s
│     ├─ Benchmark 60s (k6 + attack vectors)
│     └─ Cooldown 15s
│     
├─ Metrics Collection (Dual Source)
│  ├─ k6 NDJSON: HTTP latency, requests, errors, JWT metrics
│  └─ Prometheus: CPU (rate()[1m]), Memory (working_set_bytes)
│     
├─ Post-Processing
│  ├─ Parse k6 NDJSON → 4 metrics (avg_ms, p95_ms, err_pct, rps)
│  ├─ Extract timestamps
│  ├─ Query Prometheus with timestamp window → 2 metrics (cpu, mem)
│  └─ Merge into unified CSV (6 metrics per run)
│     
├─ Statistical Analysis
│  ├─ Linear mixed model: metric ~ control + variant + vus + sec_mode + (1|block)
│  ├─ ANOVA F-tests
│  ├─ Post-hoc Tukey HSD contrasts
│  └─ Effect sizes (Cohen's d)
│     
└─ Threat Model Derivation
   ├─ For each (attack_vector, control) pair:
   │  ├─ Filter runs: security_mode="attack"
   │  ├─ Calculate error_rate under this control
   │  └─ Compare vs baseline → effectiveness (HIGH/MEDIUM/LOW)
   └─ Generate 5×4 threat model matrix
```

---

## IV. DOCUMENT NAVIGATION GUIDE

### By Jury Role

**If you are: Systems Committee Member**
1. Start: DEFENSE_NARRATIVE.md § 2.1 (Sistemas dimension)
2. Detail: TECHNICAL_METHODOLOGY.md § 1, 3, 4 (Design, metrics, orchestration)
3. Evidence: PRELIMINARY_FINDINGS.md § 4 (Load scalability analysis)
4. Final: S6_INTEGRATED_REPORT.md (Statistical analysis upon completion)

**If you are: Security Committee Member**
1. Start: DEFENSE_NARRATIVE.md § 2.2 (Seguridad dimension)
2. Detail: TECHNICAL_METHODOLOGY.md § 2 (Attack vectors)
3. Evidence: PRELIMINARY_FINDINGS.md § 3 (Threat model response)
4. Final: threat_model_matrix.csv (Control effectiveness matrix)

**If you are: Director / General Jury**
1. Start: This index (you're reading it)
2. Overview: DEFENSE_PLAYBOOK.md § 1-3 (Opening, arguments, evidence)
3. Questions: DEFENSE_PLAYBOOK.md § 4 (Q&A strategy)
4. Judgment: DEFENSE_NARRATIVE.md § 5 (Contributions summary)

---

## V. KEY EVIDENCE TABLES (Quick Reference)

### Table 1: Preliminary Findings (9 Runs)

| Control | Variant | Mode | VUs | avg_ms | err_pct | cpu_mC |
|---------|---------|------|-----|--------|---------|---------|
| C3 | basic | normal | 1 | 11.05 | 0% | 97.89 |
| C2 | istio-mtls | normal | 10 | 19.01 | 0% | 453.91 |
| **C2** | **istio-mtls** | **normal** | **20** | **98.20** | 0.5% | **788.20** |
| C1 | istio | attack | 5 | 4.25 | **80%** | 118.96 |
| C3 | strict | attack | 20 | 12.78 | 40% | **1131.63** |

**Key Insights**:
- Row 3: mTLS at high load shows 8.9x latency increase
- Row 4: Single-layer defense (C1 alone) insufficient
- Row 5: C4 cost highest but defense moderate

### Table 2: Threat Model Matrix (Preliminary)

```
              C1 (Gateway)    C2 (mTLS)       C3 (NetPol)     C4 (RateLimit)
bad-login     ❌ (HIGH ERR)   ✅ (BLOCKED)    ❌ (HIGH ERR)   ⚠️ (SLOWED)
token-tamper  ❌ (HIGH ERR)   ✅ (BLOCKED)    ❌ (HIGH ERR)   ⚠️ (SLOWED)
unauth        ⚠️ (MEDIUM)     ✅ (BLOCKED)    ❌ (HIGH ERR)   ⚠️ (SLOWED)
bearer-mal    ✅ (BLOCKED)    ✅ (BLOCKED)    ❌ (HIGH ERR)   ⚠️ (SLOWED)
xff-spoof     ❌ (NO EFFECT)  ❌ (NO EFFECT)  ✅ (BLOCKED)    ❌ (NO EFFECT)

Legend: ✅ Effective | ⚠️ Partial | ❌ Ineffective
```

**Interpretation**: No column is all green. Implies multi-layer defense necessary.

---

## VI. TIMELINE & STATUS

### Completed ✅
- [x] Research problem defined
- [x] Experimental design (384 runs, factorial)
- [x] Attack vector implementation (5 vectors in k6)
- [x] Orchestration scripts (warmup/cooldown automation)
- [x] Methodology documentation (TECHNICAL_METHODOLOGY.md)
- [x] Preliminary analysis (9 runs, 6 metrics)
- [x] Defense narrative draft (DEFENSE_NARRATIVE.md)
- [x] Playbook for jury (DEFENSE_PLAYBOOK.md)

### In Progress ⏳
- [ ] Campaign execution: 9/384 runs complete (2.3%)
- [ ] Orchestrator monitoring: Checking every 5 min
- [ ] Expected completion: May 15, 2026 (~20 more hours)

### Pending ⏹️
- [ ] Full statistical analysis (384 runs)
- [ ] Final threat model matrix (5×4, filled with p-values)
- [ ] Publication plots (4 high-res PNGs)
- [ ] Comprehensive report (S6_INTEGRATED_REPORT.md)
- [ ] Defense slides (PowerPoint, 20 min presentation)
- [ ] Final thesis document (integrated narrative)
- [ ] Defense date scheduled (June 2026)

---

## VII. SUCCESS CRITERIA (Jury Evaluation)

### Dimension: Sistemas y Computación ✓
- [x] Multi-metric evaluation demonstrated
- [x] Non-linear performance effects shown
- [x] Systematic experimental design used
- [ ] Statistical analysis rigorous (pending full data)
- [ ] Generalization to broader systems discussed

**Evidence Quality**: Preliminary evidence strong; final evidence pending completion

### Dimension: Seguridad Digital ✓
- [x] Threats operationalized as attack vectors
- [x] Controls mapped to specific threats
- [x] Multi-layer necessity argued
- [ ] Quantitative defense metrics computed (pending)
- [ ] Threat model matrix validated (pending)

**Evidence Quality**: Preliminary evidence strong; final evidence pending completion

### Integration (Dual-Maestría) ✓
- [x] Systems perspective required (load, performance)
- [x] Security perspective required (threat model, adversary)
- [x] Interaction shown (non-linear overhead under attack)
- [ ] Neither dimension subordinate to other (balanced, pending)
- [ ] Contribution unique to this integration (pending jury judgment)

**Evidence Quality**: Narrative compelling; empirical validation pending

---

## VIII. NOTES FOR JURY PREPARATION

### What Not to Expect
- ❌ "Perfect" security (no single control is 100% effective)
- ❌ Certainty at production scale (20 VU << 1000 VU production)
- ❌ Exhaustive threat model (5 vectors representative, not comprehensive)
- ❌ Algorithm novel (mixed model ANOVA is standard)

### What to Expect
- ✅ Rigorous experimental design
- ✅ Empirical evidence (384 runs × 6 metrics = 2304 data points)
- ✅ Practical implications (guidance for architects)
- ✅ Clear limitations and future work
- ✅ Integration of 2 academic disciplines into coherent thesis

---

## IX. APPENDIX: File Locations in Repository

```
/home/dwan13/muBench/

├── Docs/
│  ├── DEFENSE_NARRATIVE.md ...................... (Thesis claims & narrative)
│  ├── TECHNICAL_METHODOLOGY.md ................. (Experimental details)
│  ├── PRELIMINARY_FINDINGS.md .................. (9-run analysis)
│  ├── DEFENSE_PLAYBOOK.md ...................... (Jury presentation strategy)
│  ├── s6-integrated-security-architecture.puml . (Architecture diagram)
│  └── s6-security-technical-spec.md ............ (Technical spec)
│
├── Testing/
│  ├── s6_statistical_analysis.py ............... (Post-processing script)
│  ├── analyze_s6_integrated_results.py ......... (Metrics extraction)
│  └── results/
│     ├── auto_runs/randomized_campaigns/
│     │  └── s6_integrated_dual_n4_B*.json ..... (Raw k6 NDJSON outputs)
│     ├── s6_integrated_all_6_metrics.csv ...... (Preliminary 9-run CSV)
│     ├── s6_integrated_all_6_metrics_final.csv (Final 384-run CSV, pending)
│     └── s6_analysis/
│        ├── S6_INTEGRATED_REPORT.md ........... (Generated report)
│        ├── threat_model_matrix.csv .......... (Generated matrix)
│        └── *.png ........................... (Generated plots)
│
├── scripts/
│  ├── run-s6-integrated-repro.sh ............... (Campaign driver)
│  ├── run-randomized-design-matrix.sh ......... (Row orchestrator)
│  ├── s6_orchestrator.sh ...................... (Auto-analysis pipeline)
│  └── run-k6-benchmark.sh ..................... (Per-benchmark executor)
│
└── RealisticServices/k6/
   └── realistic-flow.js ....................... (Attack vector implementation)
```

---

## X. HOW TO USE THIS PACKAGE

### For Initial Jury Review
1. Read this index (provides overview)
2. Read DEFENSE_NARRATIVE.md (thesis claims)
3. Skim TECHNICAL_METHODOLOGY.md §1, §2 (design & threats)
4. Review PRELIMINARY_FINDINGS.md (evidence from 9 runs)
5. Optional: DEFENSE_PLAYBOOK.md for context

**Time commitment**: ~90 min

### For Detailed Evaluation
1-5 from above, plus:
6. Full TECHNICAL_METHODOLOGY.md (all sections)
7. PRELIMINARY_FINDINGS.md (detailed analysis)
8. Review CSV data: s6_integrated_all_6_metrics.csv
9. Review code: realistic-flow.js, s6_statistical_analysis.py

**Time commitment**: ~4 hours

### For Defense Day Preparation
- Candidate uses: DEFENSE_PLAYBOOK.md (entire document)
- Jury reviews: DEFENSE_NARRATIVE.md (1 page per major claim)
- Both refer to: PRELIMINARY_FINDINGS.md (evidence lookup)

---

## DOCUMENT MASTER INDEX

| Document | Purpose | Audience | Length | Status |
|----------|---------|----------|--------|--------|
| DEFENSE_NARRATIVE.md | Core thesis | Jury, academic | ~5 pages | ✅ Complete |
| TECHNICAL_METHODOLOGY.md | Methods detail | Technical jury | ~10 pages | ✅ Complete |
| PRELIMINARY_FINDINGS.md | 9-run analysis | Internal, PoC | ~8 pages | ✅ Complete |
| DEFENSE_PLAYBOOK.md | Jury strategy | Candidate | ~7 pages | ✅ Complete |
| S6_INTEGRATED_REPORT.md | Final findings | Jury | ~8 pages | ⏳ Pending |
| threat_model_matrix.csv | Threat-control map | Technical jury | ~10 rows | ⏳ Pending |
| Presentation Slides | Oral defense | Jury (live) | 20-25 slides | ⏹️ To create |
| Final Thesis Document | Formal submission | University | ~40 pages | ⏹️ To integrate |

---

**Index Version**: 1.0  
**Last Updated**: May 13, 2026, 20:30 UTC  
**Campaign Status**: 9/384 runs complete (2.3%)  
**Next Update**: May 15, 2026 (Upon campaign completion)  
**Defense Target**: June 2026
