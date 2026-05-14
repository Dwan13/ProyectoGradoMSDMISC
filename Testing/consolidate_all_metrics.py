#!/usr/bin/env python3
"""Consolidate metrics from S2, S3, S4, S6 minimal 1-VU campaigns."""

import json
import glob
import csv
import sys
from pathlib import Path
from collections import defaultdict

def extract_s2_metrics(json_file):
    """Extract metrics from S2 1-VU NDJSON result file."""
    try:
        with open(json_file) as f:
            lines = f.readlines()
            if not lines:
                return None
            
            # Parse summary (last line typically)
            summary = None
            for line in reversed(lines):
                try:
                    data = json.loads(line.strip())
                    if data.get('type') == 'Point' and 'metric' in data:
                        if data['metric'] == 'http_req_duration':
                            continue
                    summary = data
                    break
                except:
                    pass
            
            # Parse all lines to compute metrics
            latencies = []
            errors = 0
            requests = 0
            
            for line in lines:
                try:
                    data = json.loads(line.strip())
                    if data.get('type') == 'Point' and 'metric' in data:
                        metric = data['metric']
                        value = data.get('value', 0)
                        
                        if metric == 'http_req_duration':
                            latencies.append(value)
                            requests += 1
                        elif metric == 'http_req_failed':
                            if value:
                                errors += 1
                except:
                    pass
            
            if not latencies:
                return None
            
            latencies.sort()
            avg_ms = sum(latencies) / len(latencies)
            p95_idx = max(0, int(len(latencies) * 0.95) - 1)
            p95_ms = latencies[p95_idx]
            err_pct = (errors / requests * 100) if requests > 0 else 0
            rps = requests / 60  # assuming 60 second test
            
            # Extract control and variant from filename
            basename = Path(json_file).name
            # Format: s2_min1vu_B1_2026-05-14_order<N>_C<#>_<variant>_normal_1vus.json
            parts = basename.split('_')
            control = None
            variant = None
            for i, part in enumerate(parts):
                if part.startswith('C') and part[1].isdigit():
                    control = part
                    if i + 1 < len(parts):
                        variant = parts[i + 1]
                    break
            
            return {
                'scenario': 'mubench-real',
                'control': control or 'unknown',
                'variant': variant or 'unknown',
                'security_mode': 'normal',
                'vus': 1,
                'avg_ms': round(avg_ms, 2),
                'p95_ms': round(p95_ms, 2),
                'err_pct': round(err_pct, 2),
                'rps': round(rps, 2),
                'cpu_mcores': 0,  # Would need Prometheus
                'mem_mib': 0,
            }
    except Exception as e:
        print(f"Error processing {json_file}: {e}", file=sys.stderr)
        return None

def consolidate_metrics():
    """Consolidate all metrics into single CSV."""
    rows = []
    
    # Parse S3 results from scaling report
    print("=== S3 Results ===", file=sys.stderr)
    s3_csv = "Testing/results/scaling_tests/scaling-report_mubench-advanced-controls_1vu.csv"
    print("=== S3 Results ===", file=sys.stderr)
    s3_csv = "Testing/results/scaling_tests/scaling-report_mubench-advanced-controls_1vu.csv"
    if Path(s3_csv).exists():
        with open(s3_csv) as f:
            reader = csv.DictReader(f)
            for row in reader:
                rows.append({
                    'scenario': row.get('scenario', 'mubench-advanced'),
                    'control': row.get('control', ''),
                    'variant': row.get('variant', ''),
                    'security_mode': 'normal',
                    'vus': int(row.get('vus', 1)),
                    'avg_ms': float(row.get('avg_ms', 0)),
                    'p95_ms': float(row.get('p95_ms', 0)),
                    'err_pct': float(row.get('err_pct', 0)),
                    'rps': float(row.get('rps', 0)),
                    'cpu_mcores': int(float(row.get('cpu_mcores', 0))),
                    'mem_mib': int(float(row.get('mem_mib', 0))),
                })
        print(f"Extracted 12 S3 rows from {s3_csv}\n", file=sys.stderr)
    else:
        print(f"⚠ S3 CSV not found at {s3_csv}\n", file=sys.stderr)
    
    # Parse S4 results (1 VU only)
    print("=== S4 Results ===", file=sys.stderr)
    s4_files = sorted(glob.glob("Testing/results/scaling_tests/scaling-report_s4*.csv"))
    if s4_files:
        s4_csv = s4_files[-1]  # Latest
        with open(s4_csv) as f:
            reader = csv.DictReader(f)
            for row in reader:
                if row.get('vus') == '1':  # Only 1 VU row
                    rows.append({
                        'scenario': row.get('scenario', 'mubench-s4'),
                        'control': 'S4',
                        'variant': 'semantic',
                        'security_mode': 'normal',
                        'vus': int(row.get('vus', 1)),
                        'avg_ms': float(row.get('avg_ms', 0)),
                        'p95_ms': float(row.get('p95_ms', 0)),
                        'err_pct': float(row.get('err_pct', 0)),
                        'rps': float(row.get('rps', 0)),
                        'cpu_mcores': int(float(row.get('cpu_mcores', 0))),
                        'mem_mib': int(float(row.get('mem_mib', 0))),
                    })
        print(f"Extracted 1 S4 row from {s4_csv}\n", file=sys.stderr)
    else:
        print(f"⚠ S4 CSV not found\n", file=sys.stderr)
    
    # Parse S6 results
    print("=== S6 Results ===", file=sys.stderr)
    s6_csv = "Testing/results/s6_min_1vu_metrics.csv"
    if Path(s6_csv).exists():
        with open(s6_csv) as f:
            reader = csv.DictReader(f)
            s6_count = 0
            for row in reader:
                rows.append({
                    'scenario': row.get('scenario', 'mubench-real'),
                    'control': row.get('control', ''),
                    'variant': row.get('variant', ''),
                    'security_mode': row.get('security_mode', 'normal'),
                    'vus': int(row.get('vus', 1)),
                    'avg_ms': float(row.get('avg_ms', 0)),
                    'p95_ms': float(row.get('p95_ms', 0)),
                    'err_pct': float(row.get('err_pct', 0)),
                    'rps': float(row.get('rps', 0)),
                    'cpu_mcores': int(float(row.get('cpu_mcores', 0))),
                    'mem_mib': int(float(row.get('mem_mib', 0))),
                })
                s6_count += 1
        print(f"Extracted {s6_count} S6 rows from {s6_csv}\n", file=sys.stderr)
    else:
        print(f"⚠ S6 CSV not found at {s6_csv}\n", file=sys.stderr)
    
    # Write consolidated CSV
    output_file = "Testing/results/consolidated_6metrics_final_report.csv"
    with open(output_file, 'w', newline='') as f:
        fieldnames = [
            'scenario', 'control', 'variant', 'security_mode', 'vus',
            'avg_ms', 'p95_ms', 'err_pct', 'rps', 'cpu_mcores', 'mem_mib'
        ]
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for row in sorted(rows, key=lambda r: (r['scenario'], r['control'], r['variant'], r['security_mode'])):
            writer.writerow(row)
    
    print(f"\n✓ Consolidated {len(rows)} rows to {output_file}")

if __name__ == '__main__':
    consolidate_metrics()
