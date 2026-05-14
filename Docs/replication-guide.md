# S6 Reproducibility Package (Step-by-Step)

Purpose: reproduce the full S6 integrated campaign and its analysis on another machine with verifiable outputs.

Scope: this package reproduces operational security-under-load evidence (not cryptographic-depth assurance).

Target result: 384 completed runs, consolidated 6-metric dataset, threat model matrix, ANOVA report, and diagnostics plots.

---

## 1. Minimum Requirements

- OS: Linux (Ubuntu 22.04+ recommended)
- CPU: 8 vCPU minimum
- RAM: 16 GB minimum
- Storage: 30 GB free
- Tools:
  - Docker 24+
  - Kubernetes (microk8s, kind, or equivalent)
  - kubectl 1.27+
  - Python 3.10+
  - k6 0.47+

Quick check:

```bash
uname -a
python3 --version
kubectl version --client
k6 version
docker --version
```

---

## 2. Clone and Freeze the Workspace

```bash
cd ~
git clone <REPO_URL> muBench
cd muBench
git rev-parse HEAD
```

Record the commit hash in your lab notebook. This is mandatory for reproducibility claims.

---

## 3. Python Environment

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
pip install -r requirements.txt
```

Optional sanity:

```bash
python -m py_compile Testing/s6_statistical_analysis.py
```

---

## 4. Kubernetes and Monitoring Preconditions

Validate cluster access:

```bash
kubectl get nodes
kubectl get ns
```

Ensure Prometheus endpoint is reachable (default used by analysis scripts):

```bash
curl -sS http://localhost:30000/api/v1/status/buildinfo | head
```

If unavailable, port-forward Prometheus before analysis:

```bash
kubectl -n monitoring port-forward svc/prometheus-k8s 30000:9090
```

---

## 5. Verify S6 Configuration (Deterministic Inputs)

```bash
bash scripts/verify-s6-integrated-config.sh
```

Generate and inspect matrix:

```bash
python3 Testing/generate_s6_integrated_matrix.py \
  --replicates 4 \
  --seed 20260513 \
  --campaign-id s6_integrated_dual_n4 \
  --start-date 2026-05-20 \
  --security-modes normal,attack \
  --output Testing/results/scaling_tests/design_matrix_s6_integrated_dual_n4_randomized_blocks.csv

python3 - << 'PY'
import pandas as pd
p='Testing/results/scaling_tests/design_matrix_s6_integrated_dual_n4_randomized_blocks.csv'
df=pd.read_csv(p)
print('rows', len(df))
print('unique controls', sorted(df.control.unique()))
print('unique modes', sorted(df.security_mode.unique()))
print('unique vus', sorted(df.vus.unique()))
PY
```

Expected:
- rows = 384
- controls = C1,C2,C3,C4
- modes = normal,attack
- vus = 1,5,10,20

---

## 6. Execute S6 Campaign

Primary run command:

```bash
bash scripts/run-s6-integrated-repro.sh --execute --continue-on-readiness-fail
```

Recommended safety supervision (if long unattended run):

```bash
bash scripts/s6_watchdog.sh
```

Completion check:

```bash
python3 - << 'PY'
import csv,glob,os
m='Testing/results/scaling_tests/design_matrix_s6_integrated_dual_n4_randomized_blocks.csv'
with open(m) as f:
    total=sum(1 for _ in csv.DictReader(f))
files=glob.glob('Testing/results/auto_runs/randomized_campaigns/s6_integrated_dual_n4_*.json')
print('expected', total)
print('found', len(files))
PY
```

Expected: found = expected = 384.

---

## 7. Build Consolidated 6-Metric Dataset

```bash
python3 Testing/analyze_s6_integrated_results.py \
  --input-glob "Testing/results/auto_runs/randomized_campaigns/s6_*.json" \
  --prom-url "http://localhost:30000" \
  --namespace "mubench-real" \
  --output "Testing/results/s6_integrated_all_6_metrics.csv" \
  --matrix "Testing/results/scaling_tests/design_matrix_s6_integrated_dual_n4_randomized_blocks.csv"
```

Integrity check:

```bash
python3 - << 'PY'
import pandas as pd
p='Testing/results/s6_integrated_all_6_metrics.csv'
df=pd.read_csv(p)
print('rows', len(df))
print('cols', len(df.columns))
print('missing_cpu', df['cpu_mcores'].isna().sum())
print('missing_mem', df['mem_mib'].isna().sum())
print('controls', sorted(df['control'].unique()))
print('modes', sorted(df['security_mode'].unique()))
print('vus', sorted(df['vus'].unique()))
PY
```

Expected:
- rows = 384
- missing_cpu = 0
- missing_mem = 0

---

## 8. Run Statistical Analysis and Threat Model

```bash
python3 Testing/s6_statistical_analysis.py \
  --input-csv Testing/results/s6_integrated_all_6_metrics.csv \
  --output-dir Testing/results/s6_analysis
```

Expected generated artifacts:
- Testing/results/s6_analysis/S6_INTEGRATED_REPORT.md
- Testing/results/s6_analysis/threat_model_matrix.csv
- Testing/results/s6_analysis/01_latency_by_control.png
- Testing/results/s6_analysis/02_error_rate_attack.png
- Testing/results/s6_analysis/03_cpu_overhead.png
- Testing/results/s6_analysis/04_tradeoff_cpu_latency.png
- assumption_qq_*.png, assumption_residuals_fitted_*.png, assumption_scale_location_*.png

---

## 9. Final Reproducibility Acceptance Checklist

Pass criteria:

1. Matrix size is exactly 384 rows.
2. Raw campaign outputs contain 384 completed result files.
3. Consolidated CSV has 384 rows and all 6 core metrics.
4. CPU and memory missing values are zero.
5. Threat model matrix is generated with 20 rows (5 vectors x 4 controls).
6. ANOVA report and assumptions diagnostics are produced.

Quick assert:

```bash
python3 - << 'PY'
import pandas as pd
ok=True
m='Testing/results/scaling_tests/design_matrix_s6_integrated_dual_n4_randomized_blocks.csv'
r='Testing/results/s6_integrated_all_6_metrics.csv'
t='Testing/results/s6_analysis/threat_model_matrix.csv'
rm=pd.read_csv(m)
rr=pd.read_csv(r)
rt=pd.read_csv(t)
checks=[
    ('matrix_384', len(rm)==384),
    ('results_384', len(rr)==384),
    ('missing_cpu_0', rr['cpu_mcores'].isna().sum()==0),
    ('missing_mem_0', rr['mem_mib'].isna().sum()==0),
    ('threat_rows_20', len(rt)==20),
]
for name,val in checks:
    print(name, 'OK' if val else 'FAIL')
    ok=ok and val
print('OVERALL', 'OK' if ok else 'FAIL')
PY
```

---

## 10. Known Limitations to Declare in Reproduction Report

- This protocol reproduces operational resilience under synthetic adversarial load.
- It does not certify cryptographic-depth properties (cipher hardening, key lifecycle audit).
- External validity remains bounded to the tested cluster profile unless repeated in additional environments.

---

## 11. Suggested Evidence Bundle for External Reviewer

Include these files in your reproducibility package:

- Testing/results/scaling_tests/design_matrix_s6_integrated_dual_n4_randomized_blocks.csv
- Testing/results/s6_integrated_all_6_metrics.csv
- Testing/results/s6_analysis/S6_INTEGRATED_REPORT.md
- Testing/results/s6_analysis/threat_model_matrix.csv
- Testing/results/s6_analysis/*.png
- Docs/DEFENSE_NARRATIVE.md
- Docs/S6_JURY_QA_BANK.md

Optional checksum manifest:

```bash
sha256sum Testing/results/s6_integrated_all_6_metrics.csv > Testing/results/s6_analysis/checksums.sha256
sha256sum Testing/results/s6_analysis/* >> Testing/results/s6_analysis/checksums.sha256
```

This allows third-party verification that analysis artifacts match exactly.
