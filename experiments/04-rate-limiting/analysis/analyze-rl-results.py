#!/usr/bin/env python3
import argparse
import glob
import json
import os

import numpy as np
import pandas as pd
import matplotlib.pyplot as plt


def load_points(path):
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


def extract(points, metric):
    out = []
    for p in points:
        if p.get('metric') == metric:
            v = p.get('data', {}).get('value')
            if isinstance(v, (int, float)):
                out.append(float(v))
    return out


def scenario_from_file(path):
    b = os.path.basename(path)
    if b.startswith('baseline-'):
        return 'baseline'
    if b.startswith('ratelimit-'):
        return 'ratelimit'
    return 'unknown'


def vus_from_file(path):
    b = os.path.basename(path)
    for token in b.split('-'):
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
    rows = []
    for f in files:
        scenario = scenario_from_file(f)
        if scenario == 'unknown':
            continue
        vus = vus_from_file(f)
        points = load_points(f)
        lat = extract(points, 'http_req_duration')
        fails = extract(points, 'http_req_failed')
        if not lat:
            continue
        arr = np.array(lat)
        fail_rate = float(np.mean(fails)) if fails else 0.0
        rows.append({
            'scenario': scenario,
            'vus': vus,
            'file': os.path.basename(f),
            'avg_ms': float(np.mean(arr)),
            'p95_ms': float(np.percentile(arr, 95)),
            'p99_ms': float(np.percentile(arr, 99)),
            'fail_rate': fail_rate,
        })

    if not rows:
        print('No hay datos para analizar')
        return 1

    df = pd.DataFrame(rows)
    csv_path = os.path.join(args.output_dir, 'ratelimit_summary.csv')
    df.to_csv(csv_path, index=False)

    grouped = df.groupby(['scenario', 'vus'], as_index=False).agg({
        'avg_ms': 'mean',
        'p95_ms': 'mean',
        'p99_ms': 'mean',
        'fail_rate': 'mean',
    })

    pivot = grouped.pivot(index='vus', columns='scenario', values='p95_ms')
    plt.figure(figsize=(8, 5))
    for col in pivot.columns:
        plt.plot(pivot.index, pivot[col], marker='o', label=col)
    plt.title('Control 4 - Rate Limiting P95 por carga')
    plt.xlabel('VUs')
    plt.ylabel('P95 Latencia (ms)')
    plt.grid(alpha=0.3)
    plt.legend()
    chart_path = os.path.join(args.output_dir, 'ratelimit_p95_comparison.png')
    plt.savefig(chart_path, dpi=250, bbox_inches='tight')

    report_path = os.path.join(args.output_dir, 'ratelimit_report.md')
    with open(report_path, 'w') as f:
        f.write('# Reporte Control 4 - Rate Limiting\n\n')
        f.write('## Resumen\n\n')
        try:
            f.write(grouped.to_markdown(index=False))
        except Exception:
            f.write(grouped.to_csv(index=False))
        f.write('\n\n## Archivos\n\n')
        f.write(f'- CSV: {csv_path}\n')
        f.write(f'- Grafico: {chart_path}\n')

    print(f'Reporte generado: {report_path}')
    print(f'Resumen CSV: {csv_path}')
    print(f'Grafico: {chart_path}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
