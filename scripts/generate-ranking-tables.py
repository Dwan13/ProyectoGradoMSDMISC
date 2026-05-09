#!/usr/bin/env python3
"""
Generate comparative ranking tables by VU level.
Shows winner for each metric at each VU stage.
"""
import csv
import glob
from pathlib import Path

# Find latest report
reports = sorted(glob.glob('Testing/results/scaling_tests/scaling-report_*.csv'))
if not reports:
    print("ERROR: No scaling report found")
    exit(1)

report_file = reports[-1]
print(f"Reading: {report_file}\n")

# Parse CSV
rows = list(csv.DictReader(open(report_file)))

# Group by VU level
by_vus = {}
for row in rows:
    vus = int(row['vus'])
    if vus not in by_vus:
        by_vus[vus] = []
    by_vus[vus].append(row)

print("=" * 120)
print("COMPARATIVE RANKING BY VU LEVEL")
print("=" * 120)

# Process each VU level
for vus in sorted(by_vus.keys()):
    data = by_vus[vus]
    print(f"\n### VU = {vus} (60s duration)")
    print()
    
    # 1. Lowest Latency (p95_ms)
    print("**1. LOWEST LATENCY (p95_ms)** - Lower is better")
    sorted_p95 = sorted(data, key=lambda x: float(x['p95_ms']))
    for i, row in enumerate(sorted_p95[:5], 1):
        print(f"   {i}. {row['control']:2} / {row['variant']:15} → {float(row['p95_ms']):6.2f} ms")
    
    # 2. Highest Throughput (rps)
    print("\n**2. HIGHEST THROUGHPUT (rps)** - Higher is better")
    sorted_rps = sorted(data, key=lambda x: float(x['rps']), reverse=True)
    for i, row in enumerate(sorted_rps[:5], 1):
        print(f"   {i}. {row['control']:2} / {row['variant']:15} → {float(row['rps']):6.2f} req/s")
    
    # 3. Lowest Error Rate (err_pct)
    print("\n**3. LOWEST ERROR RATE (err_pct)** - Lower is better")
    sorted_err = sorted(data, key=lambda x: float(x['err_pct']))
    for i, row in enumerate(sorted_err[:5], 1):
        note = " ⚠ RATE LIMIT" if float(row['err_pct']) > 40 else ""
        print(f"   {i}. {row['control']:2} / {row['variant']:15} → {float(row['err_pct']):6.2f} %{note}")
    
    # 4. Lowest CPU Usage (cpu_mcores)
    print("\n**4. LOWEST CPU USAGE (cpu_mcores)** - Lower is better")
    sorted_cpu = sorted(data, key=lambda x: float(x['cpu_mcores']))
    for i, row in enumerate(sorted_cpu[:5], 1):
        print(f"   {i}. {row['control']:2} / {row['variant']:15} → {float(row['cpu_mcores']):6.1f} mCores")
    
    # 5. Lowest Memory Usage (mem_mib)
    print("\n**5. LOWEST MEMORY USAGE (mem_mib)** - Lower is better")
    sorted_mem = sorted(data, key=lambda x: float(x['mem_mib']))
    for i, row in enumerate(sorted_mem[:5], 1):
        print(f"   {i}. {row['control']:2} / {row['variant']:15} → {float(row['mem_mib']):6.1f} MiB")
    
    print("\n" + "-" * 120)

print("\n" + "=" * 120)
print("SUMMARY & INSIGHTS")
print("=" * 120)

# Find overall winners
all_rows = rows

# Best avg latency overall
best_p95 = min(all_rows, key=lambda x: float(x['p95_ms']))
print(f"\n🏆 BEST LATENCY (p95):")
print(f"   {best_p95['control']} / {best_p95['variant']} @ {best_p95['vus']} VU → {float(best_p95['p95_ms']):.2f} ms")

# Best throughput overall
best_rps = max(all_rows, key=lambda x: float(x['rps']))
print(f"\n🚀 BEST THROUGHPUT (rps):")
print(f"   {best_rps['control']} / {best_rps['variant']} @ {best_rps['vus']} VU → {float(best_rps['rps']):.2f} req/s")

# Most efficient (lowest CPU at max VU)
max_vus_data = [r for r in all_rows if int(r['vus']) == max(int(r['vus']) for r in all_rows)]
best_cpu = min(max_vus_data, key=lambda x: float(x['cpu_mcores']))
print(f"\n⚡ MOST EFFICIENT (CPU @ max VU):")
print(f"   {best_cpu['control']} / {best_cpu['variant']} @ {best_cpu['vus']} VU → {float(best_cpu['cpu_mcores']):.1f} mCores")

# Cleanest (no errors)
no_err = [r for r in all_rows if float(r['err_pct']) == 0.0]
if no_err:
    fastest_clean = min(no_err, key=lambda x: float(x['p95_ms']))
    print(f"\n✅ CLEANEST (zero errors, fastest):")
    print(f"   {fastest_clean['control']} / {fastest_clean['variant']} @ {fastest_clean['vus']} VU → {float(fastest_clean['p95_ms']):.2f} ms, {float(fastest_clean['rps']):.2f} req/s")

print("\n" + "=" * 120)
