#!/usr/bin/env python3
import argparse
import glob
import json
import os
from collections import defaultdict

import numpy as np
import pandas as pd
import matplotlib.pyplot as plt


def load_jsonl_points(path):
    points = []
    with open(path, 'r') as f:
        for line in f:
            try:
                row = json.loads(line)
            except json.JSONDecodeError:
                continue
            if row.get('type') == 'Point':
                points.append(row)
    return points


def extract_metric(points, metric_name):
    values = []
    for p in points:
        if p.get('metric') == metric_name:
            v = p.get('data', {}).get('value')
            if isinstance(v, (int, float)):
                values.append(float(v))
    return values


def summarize_latencies(latencies):
    arr = np.array(latencies)
    return {
        'count': int(arr.size),
        'avg_ms': float(np.mean(arr)),
        'p95_ms': float(np.percentile(arr, 95)),
        'p99_ms': float(np.percentile(arr, 99)),
    }


def scenario_from_name(file_name):
    base = os.path.basename(file_name)
    if base.startswith('baseline-'):
        return 'baseline'
    if base.startswith('istio-'):
        return 'istio'
    if base.startswith('linkerd-'):
        return 'linkerd'
    return 'unknown'


def vus_from_name(file_name):
    base = os.path.basename(file_name)
    for token in base.split('-'):
        if token.startswith('vus'):
            return int(token.replace('vus', ''))
    return -1


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--results-dir', required=True)
    parser.add_argument('--output-dir', required=True)
    args = parser.parse_args()

    os.makedirs(args.output_dir, exist_ok=True)

    files = sorted(glob.glob(os.path.join(args.results_dir, '**/*.json'), recursive=True))
    if not files:
        print('No se encontraron resultados JSON para analizar.')
        return 1

    rows = []
    for f in files:
        scenario = scenario_from_name(f)
        vus = vus_from_name(f)
        points = load_jsonl_points(f)
        lat = extract_metric(points, 'http_req_duration')
        if not lat:
            continue
        stats = summarize_latencies(lat)
        rows.append({
            'scenario': scenario,
            'vus': vus,
            'file': os.path.basename(f),
            **stats,
        })

    if not rows:
        print('No se pudieron extraer latencias de los JSON.')
        return 1

    df = pd.DataFrame(rows)
    csv_path = os.path.join(args.output_dir, 'mtls_summary.csv')
    df.to_csv(csv_path, index=False)

    grouped = df.groupby(['scenario', 'vus'], as_index=False).agg({
        'avg_ms': 'mean',
        'p95_ms': 'mean',
        'p99_ms': 'mean',
    })

    pivot = grouped.pivot(index='vus', columns='scenario', values='p95_ms')
    plt.figure(figsize=(8, 5))
    for col in pivot.columns:
        plt.plot(pivot.index, pivot[col], marker='o', label=col)
    plt.title('Control 2 - mTLS P95 por carga')
    plt.xlabel('VUs')
    plt.ylabel('P95 Latencia (ms)')
    plt.grid(alpha=0.3)
    plt.legend()
    chart_path = os.path.join(args.output_dir, 'mtls_p95_comparison.png')
    plt.savefig(chart_path, dpi=250, bbox_inches='tight')

    md_path = os.path.join(args.output_dir, 'mtls_report.md')
    with open(md_path, 'w') as f:
        f.write('# Reporte Control 2 - mTLS Service Mesh\n\n')
        f.write('## Resumen\n\n')
        try:
            f.write(grouped.to_markdown(index=False))
        except Exception:
            f.write(grouped.to_csv(index=False))
        f.write('\n\n## Archivos\n\n')
        f.write(f'- CSV: {csv_path}\n')
        f.write(f'- Grafico: {chart_path}\n')

    print(f'Reporte generado: {md_path}')
    print(f'Resumen CSV: {csv_path}')
    print(f'Grafico: {chart_path}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
