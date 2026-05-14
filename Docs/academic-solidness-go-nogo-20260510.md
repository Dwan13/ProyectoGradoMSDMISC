# Academic Solidness GO/NO-GO Protocol (S2 Base)

## Current status (2026-05-10)

Current evidence is NOT yet academically solid under strict criteria:
- Replicates per cell: 2 (target: 6)
- TOST inconclusive ratio: 60.8% (target: <=20%)
- GO/NO-GO verdict: NO_GO

### Protocol note (2026-05-11)

- The experiment remains in Scenario S2 (`postgres-real`).
- No new scenario (for example, `S5`) is introduced for this stabilization step.
- A methodological protocol update is applied as `S2.1`:
  - uniform readiness gate before each k6 row (login + profile must pass),
  - same design matrix, factors, variants, and VUs.
- For inference integrity, final claims should use runs collected under one protocol version consistently (preferably S2.1 end-to-end).

Evidence files:
- Testing/results/scaling_tests/academic_solidness_20260510/academic_solidness_report.md
- Testing/results/scaling_tests/academic_solidness_20260510/coverage_by_cell.csv
- Testing/results/scaling_tests/academic_solidness_20260510/tost_summary.csv

## Target criteria for "academically solid"

1. Design completeness
- Full base matrix covered: 48 cells (C1-C4 x 3 variants x 4 VUs).
- No missing cells.

2. Replication sufficiency
- Minimum replicates per cell: 6.
- Preferred for CPU/memory equivalence claims: >=8 when feasible.

3. Equivalence/inference quality
- TOST inconclusive ratio <= 20% for main claims.
- Report confidence intervals and effect sizes in addition to p-values.

4. Interpretability safeguards
- C4 moderate/strict high error behavior treated as expected functional effect.
- Separate performance interpretation from functional policy validation.

## Execution plan (operational)

### Step A: generate the n=6 randomized matrix

Command:

/bin/python3 Testing/generate_academic_base_matrix.py \
  --replicates 6 \
  --campaign-id s2_academic_base_n6 \
  --start-date 2026-05-11

Output:
- Testing/results/scaling_tests/design_matrix_academic_base_n6_randomized_blocks.csv

### Step B: execute by block/day (recommended)

Use one block per day for stability and blocking:
- B1_2026-05-11
- B2_2026-05-12
- B3_2026-05-13
- B4_2026-05-14
- B5_2026-05-15
- B6_2026-05-16

Recommended command pattern per day:

TARGET_ENV=postgres-real bash scripts/run-randomized-design-matrix.sh \
  --matrix Testing/results/scaling_tests/design_matrix_academic_base_n6_randomized_blocks.csv \
  --execute

Note:
- Keep the cluster in stable conditions during each block.
- Keep warmup/cooldown policy consistent across days.

### Step C: aggregate campaign CSVs

Collect all resulting S2 report CSVs for the campaign window. At minimum include all 6 replicate days in the analysis input list.

### Step D: run TOST/equivalence on all campaign files

Example pattern:

/bin/python3 Testing/analyze_tost_equivalence.py \
  --input Testing/results/scaling_tests/scaling-report_postgres-real_YYYYMMDD.csv \
  --input Testing/results/scaling_tests/scaling-report_postgres-real_YYYYMMDD.csv \
  --output-dir Testing/results/scaling_tests/tost_equivalence_academic_final

### Step E: run GO/NO-GO solidity assessment

Example:

/bin/python3 Testing/assess_academic_solidness.py \
  --input Testing/results/scaling_tests/scaling-report_postgres-real_YYYYMMDD.csv \
  --input Testing/results/scaling_tests/scaling-report_postgres-real_YYYYMMDD.csv \
  --min-replicates 6 \
  --tost-results Testing/results/scaling_tests/tost_equivalence_academic_final/tost_equivalence_results.csv \
  --output-dir Testing/results/scaling_tests/academic_solidness_final

## Decision rule

Declare "academically solid" only if all are true:
- verdict = GO
- missing_cells = 0
- low_replication_cells = 0
- TOST inconclusive ratio <= 20%

If any fail, keep verdict as NO_GO and explicitly report which blocker remains.
