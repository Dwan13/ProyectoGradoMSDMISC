#!/usr/bin/env python3
"""
MuBench k6 Results Analyzer
Compara resultados HTTP vs HTTPS para calcular overhead de TLS
"""

import json
import sys
import os
from pathlib import Path
from typing import Dict, Any

def load_k6_results(filepath: str) -> Dict[str, Any]:
    """Load k6 JSON results file"""
    with open(filepath, 'r') as f:
        # k6 outputs NDJSON (newline-delimited JSON)
        # We need the final summary metric
        lines = f.readlines()
        for line in reversed(lines):
            try:
                data = json.loads(line)
                if data.get('type') == 'Point' and 'metric' in data:
                    continue
                if 'metrics' in data:
                    return data
            except json.JSONDecodeError:
                continue
    
    # If no summary found, try loading as regular JSON
    with open(filepath, 'r') as f:
        return json.load(f)

def extract_metrics(results: Dict[str, Any]) -> Dict[str, float]:
    """Extract key metrics from k6 results"""
    metrics = results.get('metrics', {})
    
    return {
        'avg_duration': metrics.get('http_req_duration', {}).get('avg', 0),
        'p95_duration': metrics.get('http_req_duration', {}).get('p(95)', 0),
        'p99_duration': metrics.get('http_req_duration', {}).get('p(99)', 0),
        'median_duration': metrics.get('http_req_duration', {}).get('med', 0),
        'total_requests': metrics.get('http_reqs', {}).get('count', 0),
        'failed_requests': metrics.get('http_req_failed', {}).get('rate', 0) * 100,
        'throughput': metrics.get('http_reqs', {}).get('rate', 0),
        'data_received': metrics.get('data_received', {}).get('count', 0),
        'data_sent': metrics.get('data_sent', {}).get('count', 0),
    }

def calculate_overhead(http_metrics: Dict[str, float], https_metrics: Dict[str, float]) -> Dict[str, Dict[str, float]]:
    """Calculate overhead percentages"""
    overhead = {}
    
    for key in http_metrics:
        if http_metrics[key] == 0:
            overhead[key] = {'absolute': 0, 'percentage': 0}
            continue
        
        absolute = https_metrics[key] - http_metrics[key]
        percentage = (absolute / http_metrics[key]) * 100
        
        overhead[key] = {
            'absolute': absolute,
            'percentage': percentage
        }
    
    return overhead

def print_comparison(http_metrics: Dict[str, float], https_metrics: Dict[str, float], overhead: Dict[str, Dict[str, float]]):
    """Print formatted comparison table"""
    
    print("\n" + "="*80)
    print(" MuBench TLS Overhead Analysis")
    print("="*80)
    
    print(f"\n{'Metric':<25} {'HTTP':<15} {'HTTPS':<15} {'Overhead':<15} {'%':<10}")
    print("-"*80)
    
    metrics_labels = {
        'avg_duration': 'Avg Latency (ms)',
        'p95_duration': 'P95 Latency (ms)',
        'p99_duration': 'P99 Latency (ms)',
        'median_duration': 'Median Latency (ms)',
        'throughput': 'Throughput (req/s)',
        'total_requests': 'Total Requests',
        'failed_requests': 'Failed Rate (%)',
        'data_received': 'Data RX (bytes)',
        'data_sent': 'Data TX (bytes)',
    }
    
    for key, label in metrics_labels.items():
        http_val = http_metrics[key]
        https_val = https_metrics[key]
        ovh_abs = overhead[key]['absolute']
        ovh_pct = overhead[key]['percentage']
        
        # Format based on metric type
        if 'duration' in key or 'latency' in key.lower():
            print(f"{label:<25} {http_val:>12.2f}  {https_val:>12.2f}  {ovh_abs:>12.2f}  {ovh_pct:>8.1f}%")
        elif 'throughput' in key:
            print(f"{label:<25} {http_val:>12.2f}  {https_val:>12.2f}  {ovh_abs:>12.2f}  {ovh_pct:>8.1f}%")
        elif 'rate' in key:
            print(f"{label:<25} {http_val:>12.2f}  {https_val:>12.2f}  {ovh_abs:>12.2f}  {ovh_pct:>8.1f}%")
        elif 'data' in key:
            print(f"{label:<25} {http_val:>12.0f}  {https_val:>12.0f}  {ovh_abs:>12.0f}  {ovh_pct:>8.1f}%")
        else:
            print(f"{label:<25} {http_val:>12.0f}  {https_val:>12.0f}  {ovh_abs:>12.0f}  {ovh_pct:>8.1f}%")
    
    print("-"*80)
    
    # Summary
    print("\n📊 TLS Overhead Summary:")
    print(f"  Average Latency Increase: {overhead['avg_duration']['percentage']:.1f}%")
    print(f"  P95 Latency Increase:     {overhead['p95_duration']['percentage']:.1f}%")
    print(f"  Throughput Decrease:      {overhead['throughput']['percentage']:.1f}%")
    print(f"  Data Overhead (TX):       {overhead['data_sent']['percentage']:.1f}%")
    print()

def main():
    if len(sys.argv) != 3:
        print("Usage: python3 analyze_k6_results.py <http-results.json> <https-results.json>")
        print("\nExample:")
        print("  python3 analyze_k6_results.py \\")
        print("    Testing/results/http-baseline-20260211_143022.json \\")
        print("    Testing/results/https-baseline-20260211_144022.json")
        sys.exit(1)
    
    http_file = sys.argv[1]
    https_file = sys.argv[2]
    
    # Validate files exist
    if not os.path.exists(http_file):
        print(f"Error: File not found: {http_file}")
        sys.exit(1)
    
    if not os.path.exists(https_file):
        print(f"Error: File not found: {https_file}")
        sys.exit(1)
    
    # Load results
    print(f"Loading HTTP results from: {http_file}")
    http_results = load_k6_results(http_file)
    http_metrics = extract_metrics(http_results)
    
    print(f"Loading HTTPS results from: {https_file}")
    https_results = load_k6_results(https_file)
    https_metrics = extract_metrics(https_results)
    
    # Calculate overhead
    overhead = calculate_overhead(http_metrics, https_metrics)
    
    # Print comparison
    print_comparison(http_metrics, https_metrics, overhead)
    
    # Recommendations
    print("💡 Recommendations:")
    if overhead['avg_duration']['percentage'] > 50:
        print("  ⚠️  TLS overhead is very high (>50%). Consider:")
        print("     - Using TLS 1.3 instead of 1.2")
        print("     - Enabling session resumption")
        print("     - Increasing CPU resources")
    elif overhead['avg_duration']['percentage'] > 30:
        print("  ⚡ TLS overhead is moderate (30-50%). This is expected.")
    else:
        print("  ✅ TLS overhead is acceptable (<30%).")
    
    print("\n" + "="*80 + "\n")

if __name__ == '__main__':
    main()
