#!/usr/bin/env python3
import csv
import glob
from statistics import mean
from pathlib import Path

base = Path('Testing/results/scaling_tests')

s1 = sorted(glob.glob(str(base / 'scaling-report_*.csv')))
s1 = [x for x in s1 if 'postgres-real' not in x and 'mubench-advanced' not in x]
s2 = sorted(glob.glob(str(base / 'scaling-report_postgres-real_*.csv')))
s3 = sorted(glob.glob(str(base / 'scaling-report_mubench-advanced_*.csv')))

if not (s1 and s2 and s3):
    raise SystemExit('Missing one or more scenario reports (s1/s2/s3).')

f1, f2, f3 = s1[-1], s2[-1], s3[-1]


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

rows1 = load_rows(f1)
rows2 = load_rows(f2)
rows3 = load_rows(f3)

agg = []
agg += aggregate_by_vus(rows1, 'scenario1-synthetic')
agg += aggregate_by_vus(rows2, 'scenario2-postgres-real')
agg += aggregate_by_vus(rows3, 'scenario3-mubench-advanced')

out_csv = base / f'three-scenarios-summary_{Path(f3).stem.split("_")[-1]}.csv'
with open(out_csv, 'w', newline='') as fh:
    w = csv.DictWriter(
        fh,
        fieldnames=['scenario', 'vus', 'avg_ms', 'p95_ms', 'err_pct', 'rps', 'cpu_mcores', 'mem_mib', 'samples']
    )
    w.writeheader()
    w.writerows(agg)

print(f'S1={f1}')
print(f'S2={f2}')
print(f'S3={f3}')
print(f'OUT={out_csv}')
for r in agg:
    print(r)
