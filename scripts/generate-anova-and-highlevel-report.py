#!/usr/bin/env python3
import csv
import glob
from pathlib import Path

import matplotlib.pyplot as plt
import pandas as pd

BASE = Path('Testing/results/scaling_tests')
OUT_ANOVA = Path('Testing/results/anova')
OUT_PLOTS = Path('Testing/plots/high_level_report')
OUT_ANOVA.mkdir(parents=True, exist_ok=True)
OUT_PLOTS.mkdir(parents=True, exist_ok=True)


def load_csv(path):
    return pd.read_csv(path)


def latest(pattern):
    matches = sorted(glob.glob(str(BASE / pattern)))
    if not matches:
        return None
    return Path(matches[-1])


s1_file = BASE / 'scaling-report_20260509.csv'
s2_file = BASE / 'scaling-report_postgres-real_20260509.csv'
s3_file = BASE / 'scaling-report_mubench-advanced_20260509.csv'
s4_file = latest('scaling-report_s4_*.csv')

required = [s1_file, s2_file, s3_file, s4_file]
missing = [str(p) for p in required if p is None or not Path(p).exists()]
if missing:
    raise SystemExit(f'Missing required files: {missing}')

s1 = load_csv(s1_file)
s2 = load_csv(s2_file)
s3 = load_csv(s3_file)
s4 = load_csv(s4_file)

# Normalize columns where needed
for df in (s1, s2, s3):
    df['vus'] = df['vus'].astype(int)
for df in (s4,):
    df['vus'] = df['vus'].astype(int)

# 1) ANOVA matrix for full factorial where available (S1/S2)
s1_full = s1.copy()
s1_full['scenario'] = 'S1'
s2_full = s2.copy()
s2_full['scenario'] = 'S2'
full_factorial = pd.concat([s1_full, s2_full], ignore_index=True)
full_factorial = full_factorial[
    ['scenario', 'control', 'variant', 'vus', 'avg_ms', 'p95_ms', 'err_pct', 'rps', 'cpu_mcores', 'mem_mib']
]
full_factorial.to_csv(OUT_ANOVA / 'anova_matrix_s1_s2_fullfactor.csv', index=False)

# 2) Comparable semantic matrix (S2 vs S4) aggregated by vus
s2_sem = (
    s2.groupby('vus', as_index=False)
    .agg({
        'avg_ms': 'mean',
        'p95_ms': 'mean',
        'err_pct': 'mean',
        'rps': 'mean',
        'cpu_mcores': 'mean',
        'mem_mib': 'mean',
    })
)
s2_sem['scenario'] = 'S2'

s4_sem = s4[['vus', 'avg_ms', 'p95_ms', 'err_pct', 'rps', 'cpu_mcores', 'mem_mib']].copy()
s4_sem['scenario'] = 'S4'

anova_s2_s4 = pd.concat([s2_sem, s4_sem], ignore_index=True)
anova_s2_s4 = anova_s2_s4[['scenario', 'vus', 'avg_ms', 'p95_ms', 'err_pct', 'rps', 'cpu_mcores', 'mem_mib']]
anova_s2_s4.to_csv(OUT_ANOVA / 'anova_matrix_s2_s4_semantic.csv', index=False)

# 3) Remaining scenario matrix (S3 vs S4)
s3_r = s3[['vus', 'avg_ms', 'p95_ms', 'err_pct', 'rps', 'cpu_mcores', 'mem_mib']].copy()
s3_r['scenario'] = 'S3'
s4_r = s4[['vus', 'avg_ms', 'p95_ms', 'err_pct', 'rps', 'cpu_mcores', 'mem_mib']].copy()
s4_r['scenario'] = 'S4'
anova_s3_s4 = pd.concat([s3_r, s4_r], ignore_index=True)
anova_s3_s4 = anova_s3_s4[['scenario', 'vus', 'avg_ms', 'p95_ms', 'err_pct', 'rps', 'cpu_mcores', 'mem_mib']]
anova_s3_s4.to_csv(OUT_ANOVA / 'anova_matrix_s3_s4_remaining.csv', index=False)

# 4) Four-scenario high-level matrix
s1_agg = s1.groupby('vus', as_index=False).mean(numeric_only=True)
s1_agg['scenario'] = 'S1'
s2_agg = s2.groupby('vus', as_index=False).mean(numeric_only=True)
s2_agg['scenario'] = 'S2'
s3_agg = s3[['vus', 'avg_ms', 'p95_ms', 'err_pct', 'rps', 'cpu_mcores', 'mem_mib']].copy()
s3_agg['scenario'] = 'S3'
s4_agg = s4[['vus', 'avg_ms', 'p95_ms', 'err_pct', 'rps', 'cpu_mcores', 'mem_mib']].copy()
s4_agg['scenario'] = 'S4'

all4 = pd.concat([s1_agg, s2_agg, s3_agg, s4_agg], ignore_index=True)
all4 = all4[['scenario', 'vus', 'avg_ms', 'p95_ms', 'err_pct', 'rps', 'cpu_mcores', 'mem_mib']]
all4.to_csv(OUT_ANOVA / 'anova_matrix_all4_highlevel.csv', index=False)

# 5) Grafana-friendly long format
long_rows = []
for _, row in all4.iterrows():
    for metric in ['avg_ms', 'p95_ms', 'err_pct', 'rps', 'cpu_mcores', 'mem_mib']:
        long_rows.append({
            'scenario': row['scenario'],
            'vus': int(row['vus']),
            'metric': metric,
            'value': float(row[metric]),
        })
long_df = pd.DataFrame(long_rows)
long_df.to_csv(OUT_ANOVA / 'grafana_highlevel_long.csv', index=False)

# 6) High-level plots
plt.rcParams.update({
    'figure.dpi': 160,
    'savefig.dpi': 180,
    'font.size': 10,
})

metrics = ['avg_ms', 'p95_ms', 'err_pct', 'rps', 'cpu_mcores', 'mem_mib']
fig, axes = plt.subplots(2, 3, figsize=(16, 8))
for idx, metric in enumerate(metrics):
    ax = axes[idx // 3][idx % 3]
    for scenario in ['S1', 'S2', 'S3', 'S4']:
        d = all4[all4['scenario'] == scenario].sort_values('vus')
        ax.plot(d['vus'], d[metric], marker='o', label=scenario)
    ax.set_title(metric)
    ax.set_xlabel('VUs')
    ax.grid(alpha=0.3)
axes[0][0].legend(loc='best')
fig.suptitle('High-Level Comparison by Scenario (6 metrics)')
fig.tight_layout()
fig.savefig(OUT_PLOTS / 'all4_metrics_by_vus.png')
plt.close(fig)

fig, ax = plt.subplots(figsize=(8, 6))
for scenario in ['S1', 'S2', 'S3', 'S4']:
    d = all4[all4['scenario'] == scenario]
    ax.scatter(d['p95_ms'], d['err_pct'], s=d['rps'] * 2, alpha=0.75, label=scenario)
for _, r in all4.iterrows():
    ax.annotate(f"{r['scenario']}-VU{int(r['vus'])}", (r['p95_ms'], r['err_pct']), fontsize=8, alpha=0.7)
ax.set_title('Trade-off Map: Error% vs P95 (size ~ RPS)')
ax.set_xlabel('p95_ms')
ax.set_ylabel('err_pct')
ax.grid(alpha=0.3)
ax.legend(loc='best')
fig.tight_layout()
fig.savefig(OUT_PLOTS / 'tradeoff_error_vs_p95.png')
plt.close(fig)

fig, ax = plt.subplots(figsize=(9, 6))
latest_vu = all4[all4['vus'] == 20].copy()
x = range(len(latest_vu))
ax.bar([i - 0.18 for i in x], latest_vu['cpu_mcores'], width=0.36, label='cpu_mcores')
ax.bar([i + 0.18 for i in x], latest_vu['mem_mib'], width=0.36, label='mem_mib')
ax.set_xticks(list(x))
ax.set_xticklabels(latest_vu['scenario'])
ax.set_title('Resource Cost at VU=20')
ax.grid(axis='y', alpha=0.3)
ax.legend()
fig.tight_layout()
fig.savefig(OUT_PLOTS / 'resource_cost_vu20.png')
plt.close(fig)

# 7) Markdown report
report = OUT_ANOVA / 'anova_and_highlevel_report.md'
with report.open('w', encoding='utf-8') as f:
    f.write('# ANOVA Matrices and High-Level Comparative Report\n\n')
    f.write('## Sources\n')
    f.write(f'- S1: {s1_file}\n')
    f.write(f'- S2: {s2_file}\n')
    f.write(f'- S3: {s3_file}\n')
    f.write(f'- S4: {s4_file}\n\n')
    f.write('## Generated ANOVA Matrices\n')
    f.write('- anova_matrix_s1_s2_fullfactor.csv\n')
    f.write('- anova_matrix_s2_s4_semantic.csv\n')
    f.write('- anova_matrix_s3_s4_remaining.csv\n')
    f.write('- anova_matrix_all4_highlevel.csv\n\n')
    f.write('## Grafana-friendly data\n')
    f.write('- grafana_highlevel_long.csv\n\n')
    f.write('## High-level plots\n')
    f.write('- all4_metrics_by_vus.png\n')
    f.write('- tradeoff_error_vs_p95.png\n')
    f.write('- resource_cost_vu20.png\n\n')
    f.write('## Notes\n')
    f.write('- S1/S2 full-factor matrix is suitable for factorial ANOVA design tables.\n')
    f.write('- S3/S4 and S2/S4 matrices are scenario-level comparisons; inferential power is limited without replications.\n')

print('Generated:')
print(OUT_ANOVA / 'anova_matrix_s1_s2_fullfactor.csv')
print(OUT_ANOVA / 'anova_matrix_s2_s4_semantic.csv')
print(OUT_ANOVA / 'anova_matrix_s3_s4_remaining.csv')
print(OUT_ANOVA / 'anova_matrix_all4_highlevel.csv')
print(OUT_ANOVA / 'grafana_highlevel_long.csv')
print(OUT_ANOVA / 'anova_and_highlevel_report.md')
print(OUT_PLOTS / 'all4_metrics_by_vus.png')
print(OUT_PLOTS / 'tradeoff_error_vs_p95.png')
print(OUT_PLOTS / 'resource_cost_vu20.png')
