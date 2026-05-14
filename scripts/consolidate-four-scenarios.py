#!/usr/bin/env python3
import csv
from pathlib import Path
from statistics import mean

base = Path('Testing/results/scaling_tests')

files = {
    'scenario1-synthetic': sorted(base.glob('scaling-report_20260509.csv')),
    'scenario2-postgres-real': sorted(base.glob('scaling-report_postgres-real_*.csv')),
    'scenario3-mubench-advanced': sorted(base.glob('scaling-report_mubench-advanced_*.csv')),
    'scenario4-mubench-equivalent': sorted(base.glob('scaling-report_s4_*.csv')),
}

selected = {}
for name, paths in files.items():
    if not paths:
        continue
    selected[name] = paths[-1]

if len(selected) < 4:
    raise SystemExit(f"Missing one or more scenario reports: {', '.join(sorted(set(files)-set(selected)))}")


def load_rows(path):
    with open(path) as fh:
        return list(csv.DictReader(fh))


def aggregate_by_vus(rows, scenario_name):
    by = {}
    for r in rows:
        vus = int(r['vus'])
        by.setdefault(vus, []).append(r)

    out = []
    for vus in sorted(by):
        g = by[vus]
        out.append({
            'scenario': scenario_name,
            'vus': vus,
            'avg_ms': round(mean(float(x['avg_ms']) for x in g), 2),
            'p95_ms': round(mean(float(x['p95_ms']) for x in g), 2),
            'err_pct': round(mean(float(x['err_pct']) for x in g), 2),
            'rps': round(mean(float(x['rps']) for x in g), 2),
            'cpu_mcores': round(mean(float(x['cpu_mcores']) for x in g), 2),
            'mem_mib': round(mean(float(x['mem_mib']) for x in g), 2),
            'samples': len(g),
        })
    return out

agg = []
for name, path in selected.items():
    agg += aggregate_by_vus(load_rows(path), name)

out_csv = base / 'four-scenarios-summary_latest.csv'
with open(out_csv, 'w', newline='') as fh:
    w = csv.DictWriter(fh, fieldnames=['scenario', 'vus', 'avg_ms', 'p95_ms', 'err_pct', 'rps', 'cpu_mcores', 'mem_mib', 'samples'])
    w.writeheader()
    w.writerows(agg)

print(out_csv)
for name, path in selected.items():
    print(f'{name}={path}')
