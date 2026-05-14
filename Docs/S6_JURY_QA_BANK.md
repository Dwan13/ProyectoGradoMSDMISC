# S6 Jury Q&A Bank (Dual-Master)

Purpose: high-pressure defense preparation from a strict evaluator perspective.

Use this as rapid rehearsal material.

## A. Methodology and Experimental Design

Q1. Why 384 runs?
A1. The design is 4 controls x 3 variants x 4 VU levels x 2 security modes x 4 randomized blocks, yielding 384 runs. This supports balanced coverage and inferential analysis with replication.

Q2. Why randomized blocks?
A2. To reduce temporal confounding from cluster drift, caching state, and background load. Blocking isolates day-level variance from treatment effects.

Q3. Why not a simpler benchmark with fewer factors?
A3. The thesis claim is about quality-security trade-offs under realistic operational choices. Removing factors would weaken external validity and hide interactions.

Q4. Why these VU levels (1,5,10,20)?
A4. They cover low to stressed but still operational ranges for this environment and include a level that can reveal non-linear overhead behavior.

Q5. What is your response to "n=4 replicates is still small"?
A5. It is a practical compromise between statistical power and infrastructure cost. The design remains stronger than one-shot benchmarks and produced highly significant model-level effects.

Q6. How do you ensure reproducibility?
A6. The matrix, runners, analyzer, and output artifacts are versioned and executable from repository scripts.

## B. Metrics and Instrumentation

Q7. Which are the core six metrics and why?
A7. avg_ms, p95_ms, err_pct, rps, cpu_mcores, mem_mib. Together they capture user-perceived responsiveness, reliability, throughput capacity, and resource cost.

Q8. Where do CPU and memory come from?
A8. From Prometheus query windows aligned with each run start/end timestamps, aggregated by service pods in the target namespace.

Q9. Are CPU and memory complete in final data?
A9. Yes. Final dataset has 384 rows, with 0 missing CPU and 0 missing memory values.

Q10. Why is p95 important if avg already exists?
A10. avg hides tail risk; p95 captures user-visible latency degradation in the worst regular slice.

Q11. Why use err_pct if attack traffic intentionally induces blocks?
A11. Because err_pct in attack mode reflects enforcement behavior; interpretation must separate security-denied responses from system instability.

Q12. Could throughput increases hide security failures?
A12. Yes, which is why throughput is never interpreted alone; it is cross-read with err_pct and control behavior under attack mode.

## C. Security Interpretation

Q13. Why can attack-mode latency be lower than normal-mode latency?
A13. Malicious requests are often rejected early (fast-fail), reducing service work and response time for those denied requests.

Q14. Is high attack-mode error always bad?
A14. No. In this context, a portion of attack-mode errors is expected and desirable if it corresponds to blocked malicious requests.

Q15. Which control appears strongest against credential/token abuse?
A15. C2 variants are strongest in this campaign for credential and token validation oriented attacks.

Q16. Which control appears strongest for source-based spoofing constraints?
A16. C3 strictness is the directly relevant family for segmentation and source-policy style mitigations.

Q17. Is there a silver-bullet control?
A17. No. The threat-control mapping is many-to-many. Defense-in-depth remains necessary.

Q18. Why keep C4 if it does not solve all vectors?
A18. C4 is complementary, reducing abuse pressure and brute-force intensity at the edge, improving resilience when combined with identity and segmentation controls.

Q19. What prevents overclaiming security completeness?
A19. Explicit non-claims in specification and residual risk documentation.

Q20. What is your strongest security caveat?
A20. The campaign is realistic but not exhaustive for distributed/adaptive adversaries at internet-scale botnet behavior.

## D. Systems and Performance Trade-offs

Q21. Which factors most strongly explain err_pct?
A21. Model fit is very high (R2 about 0.9235), indicating strong explanatory contribution from tested factors.

Q22. Which factors most strongly explain CPU overhead?
A22. Model fit for cpu_mcores is also high (R2 about 0.8678), indicating strong systematic effects by control, mode, and load.

Q23. Why not optimize for latency only?
A23. That would select insecure or fragile configurations. Engineering decisions require multi-objective trade-off consideration.

Q24. What is a practical deployment strategy from results?
A24. Baseline C1 plus C4 for broad protection, add C2 for sensitive paths, and C3 strictness for high-risk segments.

Q25. How should organizations choose among variants?
A25. Based on risk tier and resource budget, not a single universal winner.

Q26. What if committee asks for one best configuration?
A26. Answer with conditional optimum: best depends on objective weights across security efficacy, latency, and CPU budget.

Q27. Are trade-offs linear with load?
A27. Not universally. Some controls show stronger overhead growth as load rises.

Q28. Why include memory if CPU already tracked?
A28. Some controls and traffic patterns shift memory footprint differently than CPU; both are needed for capacity planning.

## E. Statistical Validity

Q29. Why OLS and not full mixed-effects with random slopes?
A29. Current script uses OLS fixed effects as an operational baseline; full MixedLM is planned as a robustness extension. This is explicitly documented as an inferential limitation.

Q30. Does this invalidate conclusions?
A30. No, but it bounds claim strength. We retain strong directional evidence (high R2 and significant model effects), while avoiding overclaiming exact parametric certainty.

Q31. Are p-values enough?
A31. No. They are reported with effect interpretation and operational context; decision claims are not p-value only.

Q32. How do you address heteroscedasticity concerns?
A32. We ran formal diagnostics and observed homoscedasticity risk (Levene p-values < 0.05 for key metrics). We therefore frame conclusions as robust directional evidence and propose HC3-robust errors / GLM / non-parametric sensitivity checks as next step.

Q33. Did you check data completeness before modeling?
A33. Yes, full matrix completion and metric completeness were verified before final analysis.

Q34. Could outliers dominate conclusions?
A34. Outliers can influence means, so conclusions are triangulated with p95, grouped summaries, and control-level comparisons.

Q34b. Do ANOVA assumptions fully hold in your current dataset?
A34b. Not fully. Shapiro and Levene tests indicate deviations from strict normality/homoscedasticity, while Durbin-Watson remains near 2 (low autocorrelation risk). We explicitly report this and avoid overclaiming.

Q35. Why not use cross-validation?
A35. This is not a predictive ML task; it is causal-comparative experimental analysis with designed factors.

## F. Dual-Master Integration Defense

Q36. What makes this truly dual-master and not two separate projects?
A36. Security mechanisms are treated as causal factors inside system-performance evaluation, producing integrated trade-off evidence in one design.

Q37. What is the central integrated thesis sentence?
A37. Security effectiveness and system quality are jointly optimized only through measured control-specific, load-aware trade-off analysis.

Q38. If asked to separate contributions by discipline?
A38. Systems contribution: rigorous multi-factor performance methodology. Security contribution: executable threat-control efficacy mapping under operational load.

Q39. What is novel compared with standard benchmark papers?
A39. Unified matrix including both quality and attack-mode behaviors with full control-family coverage and actionable deployment guidance.

Q40. What is novel compared with pure security evaluations?
A40. Explicit quantification of operational cost and capacity impact per defensive family and variant.

## G. Hard Critique Simulation

Q41. "Your attack errors just show broken APIs."
A41. No. In this protocol, many attack requests are designed to be denied. Denial under malicious patterns is intended security behavior.

Q41b. "Entonces estás midiendo seguridad integral o solo disponibilidad operativa?"
A41b. Operational security under load. Specifically, availability/enforcement behavior under synthetic adversarial traffic. We do not claim full cryptographic or forensic assurance in this thesis scope.

Q42. "Your latency findings are contradictory."
A42. They are consistent with fast-fail logic. Lower attack-mode latency can coexist with stronger blocking and higher error percentages.

Q43. "This is over-engineered; industry will not run 384 experiments."
A43. The full matrix establishes scientific evidence. Production teams can later use reduced designs calibrated from these findings.

Q44. "You selected metrics that favor your argument."
A44. The six metrics are standard and include both favorable and unfavorable dimensions; they expose costs, not hide them.

Q45. "Prometheus scraping could be noisy."
A45. True in any live system; we reduced this risk with per-run windows and fallback margins, and still obtained coherent complete signals.

Q46. "No chaos/fault-injection means weak validity."
A46. Fault tolerance is a planned extension, but not required to validate the current quality-security trade-off claims.

Q47. "Where is real user traffic?"
A47. This is controlled synthetic traffic for causal inference; production telemetry is complementary future validation.

Q48. "Why should we trust your threat model?"
A48. Because vectors are executable and mapped to concrete protocol/API behaviors, and now each vector is also tagged with STRIDE category, CIA focus, attacker profile, impacted asset, and residual risk.

## H. Rapid Fire Numbers to Memorize

1. Total runs: 384.
2. Dataset rows: 384.
3. Missing CPU: 0.
4. Missing memory: 0.
5. R2 avg_ms: 0.5730.
6. R2 err_pct: 0.9235.
7. R2 cpu_mcores: 0.8678.
8. p-value err_pct model: 4.40e-196.
9. Attack mean err_pct: 73.33.
10. Normal mean err_pct: 11.12.

## I. Final Jury-Ready Closing Statement

The campaign is complete, reproducible, and analytically closed. Evidence is sufficient to defend integrated conclusions for both domains: security control efficacy and distributed-system quality trade-offs. Claims are strong within declared scope, and limitations are explicit and scientifically honest.
