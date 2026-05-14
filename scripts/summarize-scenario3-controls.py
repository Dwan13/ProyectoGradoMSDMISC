#!/usr/bin/env python3
import csv
import sys
from collections import defaultdict
from pathlib import Path

if len(sys.argv) < 2:
    print("Usage: summarize-scenario3-controls.py <controls_csv>")
    sys.exit(1)

inp = Path(sys.argv[1])
if not inp.exists():
    print(f"Input not found: {inp}")
    sys.exit(1)

rows = []
with inp.open() as f:
    reader = csv.DictReader(f)
    for r in reader:
        if r.get("status") != "OK":
            continue
        rows.append(r)

by_cv = defaultdict(list)
for r in rows:
    by_cv[(r["control"], r["variant"])].append(r)

out = inp.with_name(inp.stem + "_summary.csv")
with out.open("w", newline="") as f:
    writer = csv.writer(f)
    writer.writerow([
        "control",
        "variant",
        "samples",
        "avg_ms_mean",
        "p95_ms_mean",
        "err_pct_mean",
        "rps_mean",
        "cpu_mcores_mean",
        "mem_mib_mean",
    ])

    for (control, variant), rs in sorted(by_cv.items()):
        n = len(rs)
        def mean(k):
            vals = [float(x[k]) for x in rs]
            return sum(vals) / len(vals) if vals else 0.0

        writer.writerow([
            control,
            variant,
            n,
            f"{mean('avg_ms'):.2f}",
            f"{mean('p95_ms'):.2f}",
            f"{mean('err_pct'):.2f}",
            f"{mean('rps'):.2f}",
            f"{mean('cpu_mcores'):.2f}",
            f"{mean('mem_mib'):.2f}",
        ])

print(out)
