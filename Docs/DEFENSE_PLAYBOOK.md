# S6 Defense Playbook (12-15 Minutes)

Purpose: ready-to-deliver oral script for a strict dual-master jury (Sistemas y Computacion + Seguridad Digital).

Evidence baseline used in this script:
- 384/384 completed runs
- consolidated dataset with 6 core metrics (no missing CPU/memory)
- threat model matrix with STRIDE/CIA mapping
- ANOVA and diagnostics published in S6 analysis outputs

---

## 0) Time Map

- 0:00-1:00 Opening and thesis
- 1:00-3:00 Problem framing and contributions
- 3:00-5:30 Methodology rigor
- 5:30-8:30 Results (performance + security)
- 8:30-10:30 Statistical validity and interpretation boundaries
- 10:30-12:00 Practical recommendations
- 12:00-13:30 Limitations and future work
- 13:30-15:00 Closing and transition to Q&A

---

## 1) Opening Script (0:00-1:00)

"In microservices, teams are forced into a false trade-off: either secure the platform and lose performance, or keep performance and accept security risk. This thesis tests that assumption with controlled evidence.

I executed a full integrated campaign with 384 runs and six core metrics, combining system quality and security behavior under adversarial load. The core result is not that one control wins globally, but that each control is effective against specific threats at specific operational costs."

Thesis sentence:
"Security and system quality are jointly optimized only through measured, vector-specific, load-aware trade-off analysis."

---

## 2) Problem and Contributions (1:00-3:00)

Say:

1. "From Sistemas, the problem is rigorous multi-factor performance under realistic load."
2. "From Seguridad, the problem is mapping concrete threats to effective controls with measurable residual risk."
3. "From dual integration, the problem is deciding controls with both efficacy and operational cost in view."

Contribution bullets:

1. Full factorial integrated design (4 controls x 3 variants x 4 VUs x 2 modes x 4 blocks = 384).
2. Unified 6-metric evidence per run: avg_ms, p95_ms, err_pct, rps, cpu_mcores, mem_mib.
3. Formalized threat matrix with STRIDE/CIA, attacker profile, impacted asset, and residual risk.
4. Explicit scope discipline: operational security under load, not cryptographic-depth certification.

---

## 3) Methodology Script (3:00-5:30)

Show matrix design and say:

"I used randomized blocks to reduce temporal confounding and kept the same load levels and control families across all conditions."

Security mode definition:

- normal mode: legitimate flow
- attack mode: synthetic adversarial vectors embedded into workload

Core rigor points:

1. Balanced matrix coverage across controls, variants, load and mode.
2. Timestamp-based Prometheus merge for CPU/memory.
3. Reproducible orchestration from versioned scripts and matrix.

Key line for strict jury:
"This is not a one-shot benchmark. It is designed experimentation with replication and auditable artifacts."

---

## 4) Results Script (5:30-8:30)

Use these numbers directly:

- R2 avg_ms = 0.5730
- R2 err_pct = 0.9235
- R2 cpu_mcores = 0.8678

Say:

"The model explains error behavior strongly and captures CPU overhead patterns with high fit."

Operational overhead summary:

- C1 CPU overhead +12.1% (normal vs attack)
- C2 CPU overhead +12.3%
- C3 CPU overhead +10.2%
- C4 CPU overhead +9.0%

Threat-control interpretation:

- Credential/token abuse: C2 strongest
- Source spoofing constraints: C3 strongest
- Malformed bearer/header guard: C1 and C2 stronger
- Volumetric pressure moderation: C4 complementary, not universal

Line to avoid overclaiming:
"No control is a silver bullet; evidence supports defense-in-depth with vector-specific assignment."

---

## 5) Statistical Validity Script (8:30-10:30)

Say this clearly:

"I validated assumptions with Q-Q, residuals-vs-fitted, scale-location, Shapiro, Levene, and Durbin-Watson."

Then state the honest finding:

- Durbin-Watson near 2 indicates low autocorrelation risk.
- Shapiro and Levene indicate deviations from strict normality/homoscedasticity in key metrics.

Interpretation discipline:

"Therefore, I present conclusions as strong directional evidence with high explanatory power, not as perfect parametric certainty. This limitation is explicit in the report and defense claims."

If challenged on OLS:

"OLS is baseline inferential scaffolding for this execution environment; robust/GLM sensitivity is a next statistical hardening step, not a contradiction of observed directional effects."

---

## 6) Practical Recommendation Script (10:30-12:00)

Say:

"Decision should be risk-tier based, not single-winner based."

Recommended deployment logic:

1. Baseline protection: C1 + C4
2. Sensitive paths: add C2
3. High-risk segments: enforce C3 strictness where spoofing and lateral movement risk is high

Decision rule sentence:
"Choose by objective weights over security efficacy, latency budget and CPU budget."

---

## 7) Limitations and Future Work (12:00-13:30)

Deliver verbatim:

"This thesis demonstrates operational security under adversarial load. It does not claim full cryptographic assurance, full bypass resistance at internet-scale botnet behavior, or forensic-depth incident response coverage."

Future work bullets:

1. Cryptographic-depth audit (cipher suites, key lifecycle, secrets hardening)
2. Internet-scale bypass validation (distributed rotation/proxy chaining)
3. Multi-cluster external validation
4. Robust inferential extensions (HC3/GLM/non-parametric sensitivity)

---

## 8) Closing Script (13:30-15:00)

"The main contribution is methodological and operational: we can make security architecture decisions with measured trade-offs instead of intuition.

For Sistemas, this provides rigorous multi-factor evidence under adversarial conditions. For Seguridad, this provides explicit threat-control-residual-risk mapping with operational cost visibility.

The work is complete for its declared scope, reproducible from repository artifacts, and honest about what remains outside scope."

Transition line:
"I am ready for detailed questions on threat model formalization, statistical assumptions, and reproducibility pipeline."

---

## 9) Strict Jury Q&A Triggers (Quick Response Cards)

Q: "What security property is actually demonstrated?"
A: "Availability and enforcement behavior under adversarial load; not full cryptographic-depth assurance."

Q: "Do ANOVA assumptions fully hold?"
A: "Not strictly for all metrics; diagnostics are published. I therefore report directional conclusions with explicit inferential boundaries."

Q: "Why trust this threat model?"
A: "Vectors are executable and linked to STRIDE/CIA, attacker profile, impacted asset, and residual risk."

Q: "Should we accept one best control?"
A: "No. Best is conditional on objective weights and threat profile."

---

## 10) Slide Order (Minimal, High-Impact)

1. Problem + thesis
2. Integrated design (384 matrix)
3. Metrics and instrumentation
4. Result summary (R2 + overhead)
5. Threat model matrix (STRIDE/CIA)
6. Assumptions diagnostics and interpretation boundary
7. Recommendation by risk tier
8. Limitations and future work
9. Closing statement

Use appendix for deep dives:
- full ANOVA table
- diagnostics plots
- reproducibility checklist
- full Q&A bank
