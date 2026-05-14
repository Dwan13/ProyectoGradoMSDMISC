# S6 Campaign Final Status Dashboard

Date: 2026-05-14

## Final Execution State

1. Campaign state: completed.
2. Matrix completion: 384/384.
3. Partial runs: 0.
4. Missing runs: 0.
5. Watchdog state: exited after completion.

## Final Data Package

1. Consolidated metrics CSV: [Testing/results/s6_integrated_all_6_metrics.csv](Testing/results/s6_integrated_all_6_metrics.csv)
2. Statistical report: [Testing/results/s6_analysis/S6_INTEGRATED_REPORT.md](Testing/results/s6_analysis/S6_INTEGRATED_REPORT.md)
3. Threat model matrix: [Testing/results/s6_analysis/threat_model_matrix.csv](Testing/results/s6_analysis/threat_model_matrix.csv)
4. Plot 1 latency by control: [Testing/results/s6_analysis/01_latency_by_control.png](Testing/results/s6_analysis/01_latency_by_control.png)
5. Plot 2 attack error by control: [Testing/results/s6_analysis/02_error_rate_attack.png](Testing/results/s6_analysis/02_error_rate_attack.png)
6. Plot 3 CPU overhead: [Testing/results/s6_analysis/03_cpu_overhead.png](Testing/results/s6_analysis/03_cpu_overhead.png)
7. Plot 4 CPU-latency trade-off: [Testing/results/s6_analysis/04_tradeoff_cpu_latency.png](Testing/results/s6_analysis/04_tradeoff_cpu_latency.png)

## Integrity Checks

1. Rows in consolidated CSV: 384.
2. Columns in consolidated CSV: 21.
3. Missing cpu_mcores: 0.
4. Missing mem_mib: 0.
5. Security modes present: normal, attack.
6. Controls present: C1, C2, C3, C4.
7. Load levels present: 1, 5, 10, 20.

## Inference Snapshot

1. avg_ms model: R2 = 0.5730, p = 1.4187e-59.
2. err_pct model: R2 = 0.9235, p = 4.4000e-196.
3. cpu_mcores model: R2 = 0.8678, p = 2.0524e-152.

## Defense Readiness Decision

Ready for dual-master defense within declared scope and non-claims.

Supporting evaluation documents:

1. [Docs/S6_FINAL_CLOSURE_EVALUATION.md](Docs/S6_FINAL_CLOSURE_EVALUATION.md)
2. [Docs/S6_JURY_QA_BANK.md](Docs/S6_JURY_QA_BANK.md)
3. [Docs/s6-security-technical-spec.md](Docs/s6-security-technical-spec.md)
