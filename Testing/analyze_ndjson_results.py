#!/usr/bin/env python3
"""
Analyze randomized benchmark campaign results from NDJSON k6 output.
Extracts summary metrics and generates comparison matrices.
"""

import json
import os
import glob
from pathlib import Path
import pandas as pd
import re

RESULTS_DIR = "/home/dwan13/muBench/Testing/results/auto_runs/randomized_campaigns"
OUTPUT_DIR = "/home/dwan13/muBench/Testing/results/analysis"
os.makedirs(OUTPUT_DIR, exist_ok=True)

def extract_metrics_from_ndjson(filepath):
    """
    Extract final summary metrics from k6 NDJSON output.
    Returns dict with checks_rate, p95_ms, error_rate, total_reqs.
    """
    metrics = {
        'checks_rate': 0,
        'p95_ms': 0,
        'error_rate': 0,
        'total_reqs': 0,
        'login_ok': 0,
        'profile_ok': 0,
    }
    
    try:
        with open(filepath, 'r') as f:
            lines = f.readlines()
        
        # Parse each NDJSON line
        metric_points = {}
        
        for line in lines:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
                metric_name = obj.get('metric')
                
                # Collect all Point data for each metric (latest value at end of file)
                if obj.get('type') == 'Point' and metric_name:
                    metric_points[metric_name] = obj.get('data', {}).get('value', 0)
                    
                    # Extract check details
                    tags = obj.get('data', {}).get('tags', {})
                    if metric_name == 'checks' and tags.get('check') == 'login status 200':
                        metrics['login_ok'] += 1
                    elif metric_name == 'checks' and tags.get('check') == 'profile status 200':
                        metrics['profile_ok'] += 1
                        
            except json.JSONDecodeError:
                continue
        
        # Use the last point values as summary
        if 'http_reqs' in metric_points:
            metrics['total_reqs'] = int(metric_points['http_reqs'])
        
        if 'http_req_failed' in metric_points:
            # k6 stores rate as decimal (0.05 = 5%)
            metrics['error_rate'] = metric_points['http_req_failed'] * 100
        
        # For checks, count successful vs failed
        if 'checks' in metric_points:
            # This will need to scan through file for check counts
            pass
        
        # Try to extract p95 from last line which usually has summary
        if lines:
            last_obj = None
            for line in reversed(lines):
                if line.strip():
                    try:
                        last_obj = json.loads(line.strip())
                        break
                    except:
                        pass
            
            if last_obj and 'data' in last_obj and 'value' in last_obj['data']:
                if last_obj.get('metric') == 'http_req_duration':
                    metrics['p95_ms'] = last_obj['data']['value']
        
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
        metrics = extract_metrics_from_ndjson(filepath)
        
        # Combine
        result = {
            **parsed,
            **metrics,
        }
        results.append(result)
        print(f"[✓] {filename}: Checks={result.get('checks_rate', 0):.1f}%, p95={result.get('p95_ms', 0):.2f}ms, Error={result.get('error_rate', 0):.2f}%")
    
    return pd.DataFrame(results) if results else pd.DataFrame()


def generate_summary_matrix(df):
    """Generate summary matrix: Control/Variant vs VUs."""
    if df.empty:
        print("[WARNING] No data to generate matrix")
        return
    
    print("\n" + "="*80)
    print("SUMMARY MATRIX: Checks Rate (%) by Control/Variant/VUs")
    print("="*80)
    
    # Pivot: Control/Variant rows, VUs columns
    for (control, variant), group in df.groupby(['control', 'variant']):
        print(f"\n{control}/{variant}:")
        for vu in sorted(group['vus'].unique()):
            sub = group[group['vus'] == vu]
            avg_checks = sub['checks_rate'].mean()
            avg_p95 = sub['p95_ms'].mean()
            avg_error = sub['error_rate'].mean()
            print(f"  {vu}VU: Checks={avg_checks:.1f}%, p95={avg_p95:.2f}ms, Error={avg_error:.2f}%")


def main():
    print("\n" + "="*80)
    print("RANDOMIZED CAMPAIGN ANALYSIS - NDJSON Parser")
    print("="*80)
    
    df = load_current_campaign_results()
    
    if df.empty:
        print("[ERROR] No valid results loaded")
        sys.exit(1)
    
    print(f"\n[INFO] Loaded {len(df)} completed orders")
    
    # Generate summary matrix
    generate_summary_matrix(df)
    
    # Save CSV
    csv_file = os.path.join(OUTPUT_DIR, "campaign_summary_B4_2026-05-14.csv")
    df.to_csv(csv_file, index=False)
    print(f"\n[✓] Summary saved to: {csv_file}")
    
    # Save detailed report
    report_file = os.path.join(OUTPUT_DIR, "campaign_report_B4_2026-05-14.txt")
    with open(report_file, 'w') as f:
        f.write("RANDOMIZED CAMPAIGN RESULTS REPORT\n")
        f.write("="*80 + "\n")
        f.write(f"Campaign Block: B4_2026-05-14\n")
        f.write(f"Total Orders Completed: {len(df)}\n\n")
        f.write(df.to_string())
    
    print(f"[✓] Detailed report saved to: {report_file}")


if __name__ == "__main__":
    import sys
    main()
