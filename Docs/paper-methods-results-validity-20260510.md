# Methods, Results, Threats to Validity, and Inference Criteria

## Methods

### Experimental Design

We evaluate four control families (C1-C4), each with three technology or policy variants, under four load stages (1, 5, 10, and 20 VUs). The original campaign produced one observation per treatment cell, and the improved analysis later combined two campaign days as blocked replicates.

The strengthened design is a full-factorial layout:

- Factors:
  - `control` with 4 levels
  - `variant_level` with 3 levels inside each control family
  - `vus` with 4 levels
- Blocking factor:
  - `day` to absorb day-level cluster drift

For future campaigns, randomized blocked execution matrices are available for:

- C4 rate-limiting surface analysis: [Testing/results/scaling_tests/design_matrix_c4_limit_burst_randomized_blocks.csv](Testing/results/scaling_tests/design_matrix_c4_limit_burst_randomized_blocks.csv)
- C2/C3 policy granularity and cost-benefit analysis: [Testing/results/scaling_tests/design_matrix_c2_c3_granularity_randomized_blocks.csv](Testing/results/scaling_tests/design_matrix_c2_c3_granularity_randomized_blocks.csv)

### Statistical Analysis

The primary continuous-metric model is:

$y \sim C(control) * C(variant\_level) * C(vus) + C(day)$

This model estimates:

- main effects of control, variant family, and load,
- all two-way interactions,
- the three-way interaction,
- day-block effect.

For proportions such as `err_pct`, the current implementation still reports ANOVA-style summaries for consistency with the rest of the campaign, but the recommended next step is a GLM binomial or beta-type model depending on the data-generation mechanism.

### Inference Criteria

A non-significant result is not interpreted as evidence of no effect by default. Instead, conclusions follow this hierarchy:

1. If $p < 0.05$ and the effect is practically meaningful, report a detected difference.
2. If $p \ge 0.05$ but statistical power is insufficient for the smallest effect size of interest (SESOI), report the result as inconclusive.
3. If $p \ge 0.05$ and a TOST/equivalence procedure shows the confidence interval is fully contained within the SESOI margin, report practical equivalence.

Default SESOI margins proposed for C1-C3 are:

- `avg_ms`: $\pm 1.0$ ms
- `p95_ms`: $\pm 3.0$ ms
- `rps`: $\pm 1.0$ req/s
- `cpu_mcores`: $\pm 100$ mCores
- `mem_mib`: $\pm 150$ MiB

The executable analysis template for equivalence testing is available in [Testing/analyze_tost_equivalence.py](Testing/analyze_tost_equivalence.py).

## Results

### Factorial ANOVA Summary

The blocked factorial ANOVA results are available in:

- [Testing/results/scaling_tests/anova_factorial_full_blocked_by_day_20260510.csv](Testing/results/scaling_tests/anova_factorial_full_blocked_by_day_20260510.csv)
- [Testing/results/scaling_tests/anova_factorial_matrix_20260510.csv](Testing/results/scaling_tests/anova_factorial_matrix_20260510.csv)
- [Docs/anova_factorial_full_20260510.md](Docs/anova_factorial_full_20260510.md)

Key findings are:

- `avg_ms` and `p95_ms` show strong main effects and meaningful interaction structure.
- `err_pct` is dominated by C4 rate-limiting behavior, which is expected by design rather than indicative of misconfiguration.
- `rps` is strongly driven by load and by interactions between control family and load.
- `cpu_mcores` shows statistically meaningful variation with load and some interactions.
- `mem_mib` shows weaker interaction structure, but a strong day effect is present.

### Interpretation of C1-C3

For C1-C3, the campaign now supports stronger analysis than the original one-run-per-cell design, but it still does not justify a blanket statement of “no effect” whenever a term is not significant. The current evidence supports this narrower claim:

- there is no robust evidence yet for practically relevant differences below the detectable threshold imposed by current replication and observed variance.

Estimated replication guidance based on observed within-cell variability is summarized in:

- [Docs/evidence-sufficiency-assessment-20260510.md](Docs/evidence-sufficiency-assessment-20260510.md)
- [Docs/inference-evidence-plan-factorial.md](Docs/inference-evidence-plan-factorial.md)

## Threats to Validity

### Internal Validity

- Cluster drift across campaign days may influence latency, memory, and throughput.
- Sequential execution can create ordering effects if blocking and randomization are not enforced.
- Policy propagation and service-mesh stabilization time may introduce transient artifacts if warmup is inconsistent.

Mitigation:

- blocked analysis by day,
- randomized execution matrices,
- fixed warmup and cooldown windows,
- explicit functional-validation layer separate from performance metrics.

### Construct Validity

- In C4, high error rate is not equivalent to experiment failure because 429 responses are expected under rate limiting.
- Comparing all controls using a single pass/fail threshold would confound policy intent with system failure.

Mitigation:

- separate performance layer (latency, throughput, CPU, memory) from functional-validation layer (e.g. expected 429, policy enforcement behavior).

### Conclusion Validity

- One observation per cell cannot support strong inferential claims.
- Even with two campaign days, power remains metric-dependent, especially for CPU and memory.

Mitigation:

- replicate 5-6 times per cell for latency-focused conclusions,
- use TOST/equivalence when the research claim is “no practically relevant difference”,
- report confidence intervals and effect sizes in addition to p-values.

### External Validity

- Results are currently tied to the `postgres-real` environment and its specific cluster characteristics.
- Generalization to other workloads, infrastructures, or traffic shapes remains limited.

Mitigation:

- repeat campaigns in at least one additional environment,
- vary workload shape and request mix,
- document image versions, manifests, and hashes for reproducibility.

## Inference Criteria for the Next Campaign

The next campaign should be considered academically stronger only if all of the following hold:

- randomized blocked execution is used,
- replication is at least 3 per cell for broad screening and 5-6 per cell for latency-focused inference,
- equivalence testing is applied for “no effect” claims,
- effect sizes and confidence intervals are reported,
- the C4 and C2/C3 extended matrices are used to estimate response surfaces and cost-benefit curves rather than isolated point comparisons.

## Operational Artifact

A pseudorunner that traverses randomized matrices is available in [scripts/run-randomized-design-matrix.sh](scripts/run-randomized-design-matrix.sh). It is conservative by design: it supports existing variants immediately and marks the custom sweep rows that still need manifest-dispatch integration.
