# Defense Mock: 15 Hard Jury Questions

Purpose: high-pressure rehearsal set aligned with final S6 evidence.

How to use:
- Read question aloud.
- Answer in 20-35 seconds.
- Compare with "jury-safe answer".
- Apply the correction line immediately.

## Q1. "Why should we trust your conclusions if assumptions are not perfect?"

Jury-safe answer:
"Because I do not claim perfect parametric certainty. I report strong directional evidence with high explanatory power, and I explicitly bound inference. Durbin-Watson is near 2, while Shapiro and Levene show deviations that I transparently disclose."

Quick correction if you overstate:
"Correction: strong directional evidence, not absolute parametric certainty."

## Q2. "Is this really dual-master work or two parallel reports?"

Jury-safe answer:
"It is integrated by design. Security controls are treated as causal factors inside a systems performance experiment, producing one decision surface over efficacy, latency, and CPU cost."

Quick correction:
"Not two tracks: one integrated experimental model."

## Q3. "Why 384 runs? Could this be overkill?"

Jury-safe answer:
"The 384 runs come from full factorial coverage with replication: 4 controls x 3 variants x 4 loads x 2 modes x 4 randomized blocks. That gives balanced inference and avoids one-shot benchmark bias."

Quick correction:
"It is not volume for volume's sake; it is coverage plus replication."

## Q4. "n=4 blocks is still limited."

Jury-safe answer:
"Yes, it is a practical compromise. I treat this as robust operational evidence within declared scope, not universal final truth. Replication improves reliability versus single-run studies, and limitations are explicit."

Quick correction:
"I acknowledge finite power and keep claims bounded."

## Q5. "Attack-mode errors are high. Did your system fail?"

Jury-safe answer:
"Not necessarily. In attack mode, a meaningful share of errors is intended denial behavior against malicious requests. I interpret err_pct jointly with vector type and control logic, not as pure instability."

Quick correction:
"High attack error can indicate enforcement, not collapse."

## Q6. "How can attack latency be lower than normal latency? Contradiction."

Jury-safe answer:
"It is consistent with fast-fail behavior. Early rejection often consumes fewer backend resources than full legitimate processing, so denied malicious traffic can return faster."

Quick correction:
"Lower attack latency is compatible with stronger blocking."

## Q7. "Give one best control."

Jury-safe answer:
"There is no universal best control. The optimum is conditional on threat profile and objective weights over security efficacy, latency budget, and CPU budget."

Quick correction:
"Best is conditional, not universal."

## Q8. "Why trust your threat model mapping?"

Jury-safe answer:
"Because vectors are executable and tied to protocol/API behavior, then tagged with STRIDE, CIA focus, attacker profile, impacted asset, and residual risk. The mapping is operationally testable, not only conceptual."

Quick correction:
"Executable vectors plus explicit metadata, not abstract labels only."

## Q9. "Prometheus data can be noisy."

Jury-safe answer:
"Agreed. I mitigate with per-run windows aligned to run timestamps and use consistency checks. Even with expected telemetry noise, the consolidated dataset is complete and shows coherent factor patterns."

Quick correction:
"I acknowledge noise and show mitigation + coherence."

## Q10. "Why OLS baseline instead of mixed models end-to-end?"

Jury-safe answer:
"OLS fixed-effects is the baseline inferential scaffold used in this run. I explicitly position robust/GLM/non-parametric sensitivity as the next hardening step. That is a scope extension, not a contradiction."

Quick correction:
"Baseline now, robustness extension next."

## Q11. "Your work does not prove full security."

Jury-safe answer:
"Correct. Scope is operational security under adversarial load, mainly availability and enforcement behavior. I do not claim full cryptographic assurance, internet-scale bypass closure, or forensic-depth coverage."

Quick correction:
"I confirm limitation before defending results."

## Q12. "Could throughput improvements hide security weaknesses?"

Jury-safe answer:
"Yes, if interpreted alone. I never use throughput in isolation; I cross-read rps with err_pct, p95, and vector-specific behavior to avoid false optimism."

Quick correction:
"No single metric drives conclusions."

## Q13. "What is your strongest numerical evidence?"

Jury-safe answer:
"Model explanatory strength on key outcomes: R2 err_pct 0.9235 and R2 cpu_mcores 0.8678, with complete matrix coverage and no missing CPU/memory in the consolidated S6 dataset."

Quick correction:
"Cite R2 plus data completeness together."

## Q14. "What should industry do Monday morning with this?"

Jury-safe answer:
"Apply risk-tier deployment: baseline C1+C4, add C2 on sensitive paths, enforce C3 strictness on high-risk segments. Decide using explicit weights across efficacy, latency, and CPU budget."

Quick correction:
"Actionable rule: tiered deployment by risk and budget."

## Q15. "In one sentence, what did your thesis prove?"

Jury-safe answer:
"That security architecture decisions in microservices can be made with reproducible, load-aware, vector-specific evidence on both defensive efficacy and operational cost."

Quick correction:
"Integrated, reproducible, scope-honest evidence."

---

## 30-Second Pressure Recovery Script

"Let me answer in scope. This thesis demonstrates operational security under adversarial load with reproducible evidence from 384 runs. My claims are directional and bounded by published diagnostics and explicit limitations. If helpful, I can separate what is proven now from what is planned as robustness extension."

## Self-Scoring Rubric (after each rehearsal answer)

Score each answer from 0 to 2:
- Scope honesty (0-2)
- Statistical discipline (0-2)
- Threat-model clarity (0-2)
- Operational actionability (0-2)
- Concision under 35s (0-2)

Target: 8/10 or higher on average.
