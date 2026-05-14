#!/usr/bin/env python3
"""
Extract k6 NDJSON metrics by recalculating from individual points.
Aggregates checks, latencies, and error rates from distributed metric points.
"""

import json
import os
import glob
from pathlib import Path
import pandas as pd
import re
import numpy as np

RESULTS_DIR = "/home/dwan13/muBench/Testing/results/auto_runs/randomized_campaigns"
OUTPUT_DIR = "/home/dwan13/muBench/Testing/results/analysis"
os.makedirs(OUTPUT_DIR, exist_ok=True)

def extract_metrics_from_ndjson(filepath):
    """
    Recalculate metrics from k6 NDJSON by aggregating individual points.
    Returns dict with checks_rate, p95_ms, error_rate, total_reqs.
    """
    metrics = {
        'checks_succeeded': 0,
        'checks_failed': 0,
        'checks_rate': 0,
        'latencies': [],
        'p95_ms': 0,
        'error_count': 0,
        'total_reqs': 0,
        'login_ok': 0,
        'login_fail': 0,
        'profile_ok': 0,
        'profile_fail': 0,
    }
    
    try:
        with open(filepath, 'r') as f:
            lines = f.readlines()
        
        check_values = []  # Track each check pass/fail
        
        for line in lines:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
                
                if obj.get('type') != 'Point':
                    continue
                
                metric_name = obj.get('metric')
                data = obj.get('data', {})
                value = data.get('value', 0)
                tags = data.get('tags', {})
                
                # Collect check results
                if metric_name == 'checks':
                    check_name = tags.get('check', '')
                    if value > 0:
                        metrics['checks_succeeded'] += value
                        if 'login' in check_name:
                            metrics['login_ok'] += value
                        elif 'profile' in check_name:
                            metrics['profile_ok'] += value
                    else:
                        metrics['checks_failed'] += value
                        if 'login' in check_name:
                            metrics['login_fail'] -= value
                        elif 'profile' in check_name:
                            metrics['profile_fail'] -= value
                
                # Collect latencies for p95 calculation
                elif metric_name == 'http_req_duration':
                    metrics['latencies'].append(value)
                
                # Count requests
                elif metric_name == 'http_reqs':
                    metrics['total_reqs'] += 1
                
                # Count failures
                elif metric_name == 'http_req_failed':
                    if value > 0:
                        metrics['error_count'] += 1
                        
            except json.JSONDecodeError:
                continue
        
        # Calculate final metrics
        total_checks = metrics['checks_succeeded'] + abs(metrics['checks_failed'])
        if total_checks > 0:
            metrics['checks_rate'] = (metrics['checks_succeeded'] / total_checks) * 100
        
        if metrics['latencies']:
            metrics['p95_ms'] = np.percentile(metrics['latencies'], 95)
        
        if metrics['total_reqs'] > 0:
            metrics['error_rate'] = (metrics['error_count'] / metrics['total_reqs']) * 100
        
    except Exception as e:
        print(f"[ERROR] Failed to parse {filepath}: {e}")
    
    return metrics


def parse_filename(filename):
    """
    Parse k6 filename: s2_academic_base_n8_B4_2026-05-14_order1_C3_basic_5vus.json
    Returns dict with block, order, control, variant, vus.
    """
    basename = filename.replace('.json', '')
    
    # Try regex match
    pattern = r'n8_B(\d)_2026-05-14_order(\d+)_C(\d)_([^_]+)_(\d+)vus'
    match = re.search(pattern, basename)
    
    if match:
        return {
            'block': f"B{match.group(1)}",
            'order': int(match.group(2)),
            'control': f"C{match.group(3)}",
            'variant': match.group(4),
            'vus': int(match.group(5)),
        }
    
    return None


def load_current_campaign_results():
    """Load all B4_2026-05-14 results (current campaign block)."""
    pattern = os.path.join(RESULTS_DIR, 's2_academic_base_n8_B4_2026-05-14*.json')
    files = sorted(glob.glob(pattern))
    
    print(f"[INFO] Found {len(files)} result files for B4_2026-05-14")
    
    results = []
    
    for filepath in files:
        filename = os.path.basename(filepath)
        
        # Parse filename
        parsed = parse_filename(filename)
        if not parsed:
            print(f"[SKIP] Could not parse: {filename}")
            continue
        
        # Extract metrics
        raw_metrics = extract_metrics_from_ndjson(filepath)
        
        # Combine
        result = {
            **parsed,
            'checks_rate': raw_metrics['checks_rate'],
            'p95_ms': raw_metrics['p95_ms'],
            'error_rate': raw_metrics['error_rate'],
            'total_reqs': raw_metrics['total_reqs'],
            'login_ok': raw_metrics['login_ok'],
            'profile_ok': raw_metrics['profile_ok'],
        }
        results.append(result)
        print(f"[✓] {filename}: Checks={result['checks_rate']:.1f}%, p95={result['p95_ms']:.2f}ms, Error={result['error_rate']:.2f}%, Reqs={raw_metrics['total_reqs']}")
    
    return pd.DataFrame(results) if results else pd.DataFrame()


def generate_summary_matrix(df):
    """Generate summary matrix: Control/Variant vs VUs."""
    if df.empty:
        print("[WARNING] No data to generate matrix")
        return
    
    print("\n" + "="*100)
    print("SUMMARY MATRIX: Checks Rate (%), p95ms, Error Rate (%) by Control/Variant/VUs")
    print("="*100)
    
    # Pivot: Control/Variant rows, VUs columns
    for (control, variant), group in df.groupby(['control', 'variant']):
        print(f"\n{control}/{variant}:")
        for vu in sorted(group['vus'].unique()):
            sub = group[group['vus'] == vu]
            avg_checks = sub['checks_rate'].mean()
            avg_p95 = sub['p95_ms'].mean()
            avg_error = sub['error_rate'].mean()
            counts = len(sub)
            print(f"  {vu:2d}VU ({counts} runs): Checks={avg_checks:6.1f}%, p95={avg_p95:7.2f}ms, Error={avg_error:6.2f}%")


def generate_control_comparison(df):
    """Generate comparison by control type."""
    if df.empty:
        return
    
    print("\n" + "="*100)
    print("CONTROL COMPARISON: Aggregated metrics by Control")
    print("="*100 + "\n")
    
    for control in sorted(df['control'].unique()):
        group = df[df['control'] == control]
        avg_checks = group['checks_rate'].mean()
        avg_p95 = group['p95_ms'].mean()
        avg_error = group['error_rate'].mean()
        
        print(f"{control}:")
        print(f"  Avg Checks:  {avg_checks:6.1f}%")
        print(f"  Avg p95:     {avg_p95:7.2f}ms")
        print(f"  Avg Error:   {avg_error:6.2f}%")
        print(f"  Total login_ok: {group['login_ok'].sum()}")
        print(f"  Total profile_ok: {group['profile_ok'].sum()}")
        print()


def main():
    print("\n" + "="*100)
    print("RANDOMIZED CAMPAIGN ANALYSIS - k6 NDJSON Aggregation")
    print("="*100)
    
    df = load_current_campaign_results()
    
    if df.empty:
        print("[ERROR] No valid results loaded")
        return
    
    print(f"\n[INFO] Successfully loaded {len(df)} completed orders")
    
    # Generate summaries
    generate_summary_matrix(df)
    generate_control_comparison(df)
    
    # Save CSV
    csv_file = os.path.join(OUTPUT_DIR, "campaign_summary_B4_2026-05-14.csv")
    df.to_csv(csv_file, index=False)
    print(f"\n[✓] Summary saved to: {csv_file}")
    
    # Print top anomalies
    print("\n" + "="*100)
    print("ANOMALIES: Tests with Check Rate < 95% or Error Rate > 5%")
    print("="*100)
    anomalies = df[(df['checks_rate'] < 95) | (df['error_rate'] > 5)]
    if not anomalies.empty:
        for idx, row in anomalies.iterrows():
            print(f"{row['control']}/{row['variant']} {row['vus']:2d}VU: Checks={row['checks_rate']:6.1f}%, Error={row['error_rate']:6.2f}%")
    else:
        print("[✓] No significant anomalies detected!")
    
    print("\n")


if __name__ == "__main__":
    main()
