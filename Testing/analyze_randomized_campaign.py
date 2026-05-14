#!/usr/bin/env python3
"""
Analyze randomized benchmark campaign results.
Generates comparison matrices, charts, and analysis by VUs/controls/scenarios.
Counts successful login/profile operations.
"""

import json
import os
import sys
from pathlib import Path
from collections import defaultdict
import pandas as pd
import matplotlib.pyplot as plt
import numpy as np

RESULTS_DIR = Path("/home/dwan13/muBench/Testing/results/auto_runs/randomized_campaigns")
OUTPUT_DIR = Path("/home/dwan13/muBench/Testing/results/analysis")
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

def load_json_results():
    """Load all JSON result files and extract metrics."""
    results = []
    
    if not RESULTS_DIR.exists():
        print(f"Results directory not found: {RESULTS_DIR}")
        return results
    
    for json_file in sorted(RESULTS_DIR.glob("*.json")):
        try:
            with open(json_file, 'r') as f:
                data = json.load(f)
                
            # Parse filename: s2_academic_base_n8_B{block}_order{N}_C{control}_{variant}_{vus}vus.json
            filename = json_file.stem
            parts = filename.split('_')
            
            # Extract components
            block = None
            order = None
            control = None
            variant = None
            vus = None
            
            for i, part in enumerate(parts):
                if part.startswith('B') and part[1].isdigit():
                    block = part
                elif part.startswith('order'):
                    order = int(parts[i+1]) if i+1 < len(parts) else None
                elif part.startswith('C') and part[1].isdigit():
                    control = part
                elif part.endswith('vus'):
                    vus = int(part[:-3])
                    
            # Extract from filename differently
            if not all([block, order, control, vus]):
                # Re-parse more carefully
                import re
                match = re.search(r'B(\d)_.*?order(\d+)_C(\d)_([^_]+)_(\d+)vus', filename)
                if match:
                    block = f"B{match.group(1)}"
                    order = int(match.group(2))
                    control = f"C{match.group(3)}"
                    variant = match.group(4)
                    vus = int(match.group(5))
            
            # Extract metrics from k6 output
            metrics = {
                'block': block,
                'order': order,
                'control': control,
                'variant': variant,
                'vus': vus,
                'file': str(json_file)
            }
            
            # Extract metrics from data
            if 'metrics' in data:
                m = data['metrics']
                if 'checks' in m:
                    checks = m['checks']
                    if 'value' in checks:
                        metrics['checks_rate'] = checks['value']
                    if 'passes' in checks and 'fails' in checks:
                        total = checks['passes'] + checks['fails']
                        if total > 0:
                            metrics['checks_rate'] = checks['passes'] / total * 100
                
                if 'http_req_duration' in m:
                    dur = m['http_req_duration']
                    if 'p(95)' in dur:
                        metrics['p95_ms'] = dur['p(95)']['value']
                
                if 'http_req_failed' in m:
                    failed = m['http_req_failed']
                    if 'value' in failed:
                        metrics['error_rate'] = failed['value'] * 100
                
                if 'http_reqs' in m:
                    reqs = m['http_reqs']
                    if 'count' in reqs:
                        metrics['total_reqs'] = reqs['count']
            
            # Try custom metrics if present
            if 'custom_metrics' in data:
                cm = data['custom_metrics']
                if 'checks_rate' in cm:
                    metrics['checks_rate'] = float(cm['checks_rate'])
                if 'p95_ms' in cm:
                    metrics['p95_ms'] = float(cm['p95_ms'])
                if 'error_rate' in cm:
                    metrics['error_rate'] = float(cm['error_rate'])
                if 'total_reqs' in cm:
                    metrics['total_reqs'] = int(cm['total_reqs'])
            
            results.append(metrics)
            
        except Exception as e:
            print(f"Error processing {json_file.name}: {e}", file=sys.stderr)
            continue
    
    return results

def parse_metrics_from_stdout(results_dir=RESULTS_DIR):
    """Parse metrics by reading terminal logs or extract from available JSONs."""
    # Alternative: grep terminal logs if they exist
    log_file = Path("/home/dwan13/.vscode-server/data/User/workspaceStorage/b41669e591f14398d2b8652a1bd04b0d/GitHub.copilot-chat/debug-logs/85c665b7-8001-41a4-b86c-f31f64b90c08")
    
    results = []
    import re
    
    # Try to find terminal output or read from existing JSONs
    return results

def generate_comparison_matrix(df):
    """Generate comparison matrices by control/variant/VUs."""
    
    if df.empty:
        print("No data available for analysis yet.")
        return
    
    # Create pivot tables for different metrics
    metrics_cols = ['checks_rate', 'p95_ms', 'error_rate', 'total_reqs']
    existing_metrics = [col for col in metrics_cols if col in df.columns]
    
    for metric in existing_metrics:
        try:
            # By control and VUs
            pivot_by_control_vus = pd.pivot_table(
                df, 
                values=metric, 
                index='control',
                columns=['variant', 'vus'],
                aggfunc='mean'
            )
            
            filename = OUTPUT_DIR / f"matrix_{metric}_by_control_vus.csv"
            pivot_by_control_vus.to_csv(filename)
            print(f"Saved: {filename}")
            
        except Exception as e:
            print(f"Error generating matrix for {metric}: {e}", file=sys.stderr)

def generate_charts(df):
    """Generate comparison charts."""
    
    if df.empty:
        print("No data available for charts yet.")
        return
    
    try:
        # Chart 1: Checks rate by control
        plt.figure(figsize=(12, 6))
        if 'checks_rate' in df.columns and 'control' in df.columns:
            df.groupby('control')['checks_rate'].mean().plot(kind='bar')
            plt.title('Average Checks Rate by Control')
            plt.ylabel('Checks Rate (%)')
            plt.xlabel('Control')
            plt.tight_layout()
            plt.savefig(OUTPUT_DIR / 'chart_checks_by_control.png', dpi=150)
            plt.close()
            print("Saved: chart_checks_by_control.png")
        
        # Chart 2: p95 latency by control
        plt.figure(figsize=(12, 6))
        if 'p95_ms' in df.columns and 'control' in df.columns:
            df.groupby('control')['p95_ms'].mean().plot(kind='bar')
            plt.title('Average p95 Latency by Control')
            plt.ylabel('Latency (ms)')
            plt.xlabel('Control')
            plt.tight_layout()
            plt.savefig(OUTPUT_DIR / 'chart_p95_by_control.png', dpi=150)
            plt.close()
            print("Saved: chart_p95_by_control.png")
        
        # Chart 3: Error rate by control
        plt.figure(figsize=(12, 6))
        if 'error_rate' in df.columns and 'control' in df.columns:
            df.groupby('control')['error_rate'].mean().plot(kind='bar')
            plt.title('Average Error Rate by Control')
            plt.ylabel('Error Rate (%)')
            plt.xlabel('Control')
            plt.tight_layout()
            plt.savefig(OUTPUT_DIR / 'chart_error_by_control.png', dpi=150)
            plt.close()
            print("Saved: chart_error_by_control.png")
        
        # Chart 4: Checks rate by VUs
        plt.figure(figsize=(12, 6))
        if 'checks_rate' in df.columns and 'vus' in df.columns:
            df.groupby('vus')['checks_rate'].mean().plot(kind='line', marker='o')
            plt.title('Average Checks Rate by VU Load')
            plt.ylabel('Checks Rate (%)')
            plt.xlabel('Virtual Users')
            plt.grid(True)
            plt.tight_layout()
            plt.savefig(OUTPUT_DIR / 'chart_checks_by_vus.png', dpi=150)
            plt.close()
            print("Saved: chart_checks_by_vus.png")
        
        # Chart 5: p95 latency by VUs
        plt.figure(figsize=(12, 6))
        if 'p95_ms' in df.columns and 'vus' in df.columns:
            df.groupby('vus')['p95_ms'].mean().plot(kind='line', marker='o')
            plt.title('Average p95 Latency by VU Load')
            plt.ylabel('Latency (ms)')
            plt.xlabel('Virtual Users')
            plt.grid(True)
            plt.tight_layout()
            plt.savefig(OUTPUT_DIR / 'chart_p95_by_vus.png', dpi=150)
            plt.close()
            print("Saved: chart_p95_by_vus.png")
            
    except Exception as e:
        print(f"Error generating charts: {e}", file=sys.stderr)

def generate_analysis_report(df):
    """Generate detailed analysis report."""
    
    report_lines = []
    report_lines.append("=" * 80)
    report_lines.append("RANDOMIZED BENCHMARK CAMPAIGN - ANALYSIS REPORT")
    report_lines.append("=" * 80)
    report_lines.append("")
    
    if df.empty:
        report_lines.append("No completed orders yet. Campaign still running.")
        report_lines.append("")
    else:
        report_lines.append(f"Total completed orders: {len(df)}")
        report_lines.append(f"Blocks: {', '.join(sorted(df['block'].unique()))}")
        report_lines.append(f"Controls: {', '.join(sorted(df['control'].unique()))}")
        report_lines.append(f"VU loads: {', '.join(map(str, sorted(df['vus'].unique())))}")
        report_lines.append("")
        
        # Summary statistics
        if 'checks_rate' in df.columns:
            report_lines.append("CHECKS RATE SUMMARY:")
            report_lines.append(f"  Mean: {df['checks_rate'].mean():.2f}%")
            report_lines.append(f"  Min:  {df['checks_rate'].min():.2f}%")
            report_lines.append(f"  Max:  {df['checks_rate'].max():.2f}%")
            report_lines.append("")
        
        if 'p95_ms' in df.columns:
            report_lines.append("P95 LATENCY SUMMARY (ms):")
            report_lines.append(f"  Mean: {df['p95_ms'].mean():.2f}ms")
            report_lines.append(f"  Min:  {df['p95_ms'].min():.2f}ms")
            report_lines.append(f"  Max:  {df['p95_ms'].max():.2f}ms")
            report_lines.append("")
        
        if 'error_rate' in df.columns:
            report_lines.append("ERROR RATE SUMMARY:")
            report_lines.append(f"  Mean: {df['error_rate'].mean():.2f}%")
            report_lines.append(f"  Min:  {df['error_rate'].min():.2f}%")
            report_lines.append(f"  Max:  {df['error_rate'].max():.2f}%")
            report_lines.append("")
        
        # Analysis by control
        if 'control' in df.columns and 'checks_rate' in df.columns:
            report_lines.append("PERFORMANCE BY CONTROL:")
            for control in sorted(df['control'].unique()):
                control_data = df[df['control'] == control]
                report_lines.append(f"  {control}:")
                report_lines.append(f"    Orders: {len(control_data)}")
                if 'checks_rate' in control_data.columns:
                    report_lines.append(f"    Avg Checks: {control_data['checks_rate'].mean():.2f}%")
                if 'p95_ms' in control_data.columns:
                    report_lines.append(f"    Avg p95: {control_data['p95_ms'].mean():.2f}ms")
                if 'error_rate' in control_data.columns:
                    report_lines.append(f"    Avg Error: {control_data['error_rate'].mean():.2f}%")
            report_lines.append("")
        
        # Analysis by VU load
        if 'vus' in df.columns:
            report_lines.append("PERFORMANCE BY VU LOAD:")
            for vus in sorted(df['vus'].unique()):
                vus_data = df[df['vus'] == vus]
                report_lines.append(f"  {vus} VUs:")
                report_lines.append(f"    Orders: {len(vus_data)}")
                if 'checks_rate' in vus_data.columns:
                    report_lines.append(f"    Avg Checks: {vus_data['checks_rate'].mean():.2f}%")
                if 'p95_ms' in vus_data.columns:
                    report_lines.append(f"    Avg p95: {vus_data['p95_ms'].mean():.2f}ms")
                if 'error_rate' in vus_data.columns:
                    report_lines.append(f"    Avg Error: {vus_data['error_rate'].mean():.2f}%")
            report_lines.append("")
        
        # Anomalies/Failed thresholds
        report_lines.append("ANOMALIES & FAILURES:")
        if 'checks_rate' in df.columns:
            failures = df[df['checks_rate'] < 95.0]
            if len(failures) > 0:
                report_lines.append(f"  {len(failures)} orders with Checks < 95%:")
                for _, row in failures.iterrows():
                    report_lines.append(f"    {row['block']} order {row['order']}: {row['control']} {row['variant']} {row['vus']}VU -> {row['checks_rate']:.1f}%")
            else:
                report_lines.append("  No threshold failures detected in completed orders.")
        report_lines.append("")
    
    report_text = "\n".join(report_lines)
    
    # Save report
    report_file = OUTPUT_DIR / "analysis_report.txt"
    with open(report_file, 'w') as f:
        f.write(report_text)
    
    print(report_text)
    print(f"\nReport saved to: {report_file}")

def main():
    print("Analyzing randomized benchmark campaign results...")
    print(f"Results directory: {RESULTS_DIR}")
    print(f"Output directory: {OUTPUT_DIR}")
    print("")
    
    # Load results
    results = load_json_results()
    
    if not results:
        print("No completed JSON results found yet. Campaign may still be initializing.")
        print("Waiting for first results to appear...")
        sys.exit(0)
    
    print(f"Loaded {len(results)} completed orders.")
    
    # Create DataFrame
    df = pd.DataFrame(results)
    print(f"\nDataFrame shape: {df.shape}")
    print(f"Columns: {list(df.columns)}")
    
    # Generate outputs
    print("\n" + "="*80)
    print("Generating analysis outputs...")
    print("="*80 + "\n")
    
    generate_comparison_matrix(df)
    print("")
    
    generate_charts(df)
    print("")
    
    generate_analysis_report(df)
    
    print("\n" + "="*80)
    print("Analysis complete. Outputs saved to:", OUTPUT_DIR)
    print("="*80)

if __name__ == "__main__":
    main()
