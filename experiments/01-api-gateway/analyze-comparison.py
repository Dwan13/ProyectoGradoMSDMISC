#!/usr/bin/env python3
"""
Análisis Comparativo: Baseline vs NGINX Ingress - Control 1: API Gateway
Analiza y compara resultados de baseline (sin gateway) vs NGINX Ingress
"""

import json
import glob
import argparse
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
from collections import defaultdict
from scipy import stats

def load_k6_results(json_file):
    """Cargar resultados de k6 en formato JSONL"""
    metrics = []
    with open(json_file, 'r') as f:
        for line in f:
            try:
                data = json.loads(line.strip())
                if data.get('type') == 'Point':
                    metrics.append(data)
            except json.JSONDecodeError:
                continue
    return metrics

def extract_latency(metrics):
    """Extraer latencias HTTP de métricas k6"""
    latencies = []
    for m in metrics:
        if m.get('metric') == 'http_req_duration' and 'data' in m:
            value = m['data'].get('value')
            if value is not None:
                latencies.append(value)
    return latencies

def calculate_stats(values):
    """Calcular estadísticas descriptivas"""
    arr = np.array(values)
    return {
        'mean': np.mean(arr),
        'median': np.median(arr),
        'std': np.std(arr),
        'p50': np.percentile(arr, 50),
        'p95': np.percentile(arr, 95),
        'p99': np.percentile(arr, 99),
        'min': np.min(arr),
        'max': np.max(arr),
        'count': len(arr)
    }

def analyze_scenario_results(result_files, scenario_name):
    """Analizar resultados de un escenario agrupados por VUs"""
    results = defaultdict(list)
    
    for file in result_files:
        if 'vus10' in file:
            vus = 10
        elif 'vus25' in file:
            vus = 25
        elif 'vus50' in file:
            vus = 50
        else:
            continue
        
        metrics = load_k6_results(file)
        latencies = extract_latency(metrics)
        
        if latencies:
            results[vus].append({
                'file': file,
                'latencies': latencies,
                'stats': calculate_stats(latencies),
                'count': len(latencies)
            })
    
    # Calcular promedios por nivel de VUs
    summary = {}
    for vus in sorted(results.keys()):
        reps = results[vus]
        all_latencies = []
        for rep in reps:
            all_latencies.extend(rep['latencies'])
        
        stats_data = calculate_stats(all_latencies)
        summary[vus] = {
            'scenario': scenario_name,
            'repetitions': len(reps),
            'total_requests': len(all_latencies),
            'stats': stats_data
        }
    
    return results, summary

def compare_scenarios(baseline_summary, nginx_summary):
    """Comparar escenarios baseline vs NGINX"""
    print("\n" + "=" * 90)
    print("COMPARACIÓN BASELINE vs NGINX INGRESS")
    print("=" * 90)
    
    comparison_data = []
    
    for vus in sorted(baseline_summary.keys()):
        if vus not in nginx_summary:
            continue
        
        baseline_stats = baseline_summary[vus]['stats']
        nginx_stats = nginx_summary[vus]['stats']
        
        # Calcular overhead
        overhead_mean = ((nginx_stats['mean'] - baseline_stats['mean']) / baseline_stats['mean']) * 100
        overhead_p95 = ((nginx_stats['p95'] - baseline_stats['p95']) / baseline_stats['p95']) * 100
        overhead_p99 = ((nginx_stats['p99'] - baseline_stats['p99']) / baseline_stats['p99']) * 100
        
        print(f"\n{'=' * 90}")
        print(f"VUs: {vus}")
        print(f"{'=' * 90}")
        
        print(f"\nBaseline (Sin Gateway):")
        print(f"  Requests: {baseline_stats['count']:,}")
        print(f"  Avg Latency: {baseline_stats['mean']:.2f} ms")
        print(f"  P95: {baseline_stats['p95']:.2f} ms")
        print(f"  P99: {baseline_stats['p99']:.2f} ms")
        
        print(f"\nNGINX Ingress:")
        print(f"  Requests: {nginx_stats['count']:,}")
        print(f"  Avg Latency: {nginx_stats['mean']:.2f} ms")
        print(f"  P95: {nginx_stats['p95']:.2f} ms")
        print(f"  P99: {nginx_stats['p99']:.2f} ms")
        
        print(f"\nOverhead NGINX vs Baseline:")
        print(f"  Avg Latency: {overhead_mean:+.2f}%")
        print(f"  P95: {overhead_p95:+.2f}%")
        print(f"  P99: {overhead_p99:+.2f}%")
        
        comparison_data.append({
            'VUs': vus,
            'Baseline_Mean': baseline_stats['mean'],
            'NGINX_Mean': nginx_stats['mean'],
            'Overhead_Mean_%': overhead_mean,
            'Baseline_P95': baseline_stats['p95'],
            'NGINX_P95': nginx_stats['p95'],
            'Overhead_P95_%': overhead_p95,
            'Baseline_P99': baseline_stats['p99'],
            'NGINX_P99': nginx_stats['p99'],
            'Overhead_P99_%': overhead_p99,
        })
    
    return pd.DataFrame(comparison_data)

def plot_comparison(baseline_results, nginx_results, output_dir='plots'):
    """Generar gráficos comparativos"""
    import os
    os.makedirs(output_dir, exist_ok=True)
    
    sns.set_style("whitegrid")
    plt.rcParams['figure.figsize'] = (16, 6)
    plt.rcParams['font.size'] = 11
    
    # Preparar datos
    data_for_plot = []
    for vus in sorted(baseline_results.keys()):
        for rep in baseline_results[vus]:
            for lat in rep['latencies']:
                data_for_plot.append({
                    'VUs': f'{vus} VUs',
                    'Scenario': 'Baseline',
                    'Latency (ms)': lat
                })
    
    for vus in sorted(nginx_results.keys()):
        for rep in nginx_results[vus]:
            for lat in rep['latencies']:
                data_for_plot.append({
                    'VUs': f'{vus} VUs',
                    'Scenario': 'NGINX Ingress',
                    'Latency (ms)': lat
                })
    
    df = pd.DataFrame(data_for_plot)
    
    # Boxplot comparativo
    fig, axes = plt.subplots(1, 3, figsize=(18, 6))
    
    for idx, vus in enumerate([10, 25, 50]):
        df_vus = df[df['VUs'] == f'{vus} VUs']
        sns.boxplot(data=df_vus, x='Scenario', y='Latency (ms)', ax=axes[idx], palette='Set2')
        axes[idx].set_title(f'Latencia con {vus} VUs', fontsize=14, fontweight='bold')
        axes[idx].set_ylabel('Latencia (ms)', fontsize=12)
        axes[idx].set_xlabel('')
        axes[idx].grid(True, alpha=0.3)
        axes[idx].tick_params(axis='x', rotation=15)
    
    plt.tight_layout()
    output_file = f'{output_dir}/baseline_vs_nginx_boxplot.png'
    plt.savefig(output_file, dpi=300, bbox_inches='tight')
    print(f"\n✓ Gráfico boxplot guardado en: {output_file}")
    
    # Gráfico de overhead
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(16, 6))
    
    vus_list = [10, 25, 50]
    baseline_p95 = []
    nginx_p95 = []
    overhead_p95 = []
    
    for vus in vus_list:
        baseline_lats = []
        nginx_lats = []
        
        for rep in baseline_results[vus]:
            baseline_lats.extend(rep['latencies'])
        for rep in nginx_results[vus]:
            nginx_lats.extend(rep['latencies'])
        
        b_p95 = np.percentile(baseline_lats, 95)
        n_p95 = np.percentile(nginx_lats, 95)
        overhead = ((n_p95 - b_p95) / b_p95) * 100
        
        baseline_p95.append(b_p95)
        nginx_p95.append(n_p95)
        overhead_p95.append(overhead)
    
    # P95 absoluto
    x = np.arange(len(vus_list))
    width = 0.35
    
    bars1 = ax1.bar(x - width/2, baseline_p95, width, label='Baseline', color='#66c2a5')
    bars2 = ax1.bar(x + width/2, nginx_p95, width, label='NGINX Ingress', color='#fc8d62')
    
    ax1.set_title('P95 Latencia: Baseline vs NGINX Ingress', fontsize=14, fontweight='bold')
    ax1.set_ylabel('Latencia P95 (ms)', fontsize=12)
    ax1.set_xlabel('Usuarios Virtuales', fontsize=12)
    ax1.set_xticks(x)
    ax1.set_xticklabels([f'{v} VUs' for v in vus_list])
    ax1.legend(fontsize=11)
    ax1.grid(True, alpha=0.3, axis='y')
    
    # Agregar valores
    for bars in [bars1, bars2]:
        for bar in bars:
            height = bar.get_height()
            ax1.text(bar.get_x() + bar.get_width()/2., height,
                    f'{height:.1f}',
                    ha='center', va='bottom', fontsize=10)
    
    # Overhead porcentual
    colors = ['#2ca02c' if oh >= 0 else '#d62728' for oh in overhead_p95]
    bars = ax2.bar(vus_list, overhead_p95, color=colors, alpha=0.7)
    
    ax2.set_title('Overhead de NGINX Ingress vs Baseline (P95)', fontsize=14, fontweight='bold')
    ax2.set_ylabel('Overhead (%)', fontsize=12)
    ax2.set_xlabel('Usuarios Virtuales', fontsize=12)
    ax2.set_xticks(vus_list)
    ax2.set_xticklabels([f'{v} VUs' for v in vus_list])
    ax2.axhline(y=0, color='black', linestyle='-', linewidth=0.8)
    ax2.grid(True, alpha=0.3, axis='y')
    
    # Agregar valores
    for bar, value in zip(bars, overhead_p95):
        height = bar.get_height()
        ax2.text(bar.get_x() + bar.get_width()/2., height,
                f'{value:+.1f}%',
                ha='center', va='bottom' if value >= 0 else 'top',
                fontsize=11, fontweight='bold')
    
    plt.tight_layout()
    output_file = f'{output_dir}/nginx_overhead.png'
    plt.savefig(output_file, dpi=300, bbox_inches='tight')
    print(f"✓ Gráfico de overhead guardado en: {output_file}")

def main():
    parser = argparse.ArgumentParser(description='Analizar comparación Baseline vs NGINX Ingress')
    parser.add_argument('--baseline-dir', default='baseline/results',
                       help='Directorio con archivos JSON de baseline')
    parser.add_argument('--nginx-dir', default='nginx/results',
                       help='Directorio con archivos JSON de NGINX')
    parser.add_argument('--output', default='plots',
                       help='Directorio para guardar gráficos')
    
    args = parser.parse_args()
    
    # Cargar resultados
    baseline_files = glob.glob(f'{args.baseline_dir}/baseline-*.json')
    nginx_files = glob.glob(f'{args.nginx_dir}/nginx-*.json')
    
    if not baseline_files:
        print(f"✗ No se encontraron archivos baseline en {args.baseline_dir}")
        return 1
    
    if not nginx_files:
        print(f"✗ No se encontraron archivos NGINX en {args.nginx_dir}")
        return 1
    
    print(f"Archivos baseline: {len(baseline_files)}")
    print(f"Archivos NGINX: {len(nginx_files)}")
    
    # Analizar escenarios
    print("\n" + "=" * 90)
    print("ANALIZANDO BASELINE")
    print("=" * 90)
    baseline_results, baseline_summary = analyze_scenario_results(baseline_files, 'Baseline')
    
    print("\n" + "=" * 90)
    print("ANALIZANDO NGINX INGRESS")
    print("=" * 90)
    nginx_results, nginx_summary = analyze_scenario_results(nginx_files, 'NGINX')
    
    # Comparar
    comparison_df = compare_scenarios(baseline_summary, nginx_summary)
    
    # Guardar tabla de comparación
    output_csv = f'{args.output}/comparison_table.csv'
    comparison_df.to_csv(output_csv, index=False)
    print(f"\n✓ Tabla de comparación guardada en: {output_csv}")
    
    # Generar gráficos
    print("\n" + "=" * 90)
    print("GENERANDO GRÁFICOS COMPARATIVOS")
    print("=" * 90)
    plot_comparison(baseline_results, nginx_results, args.output)
    
    # Resumen final
    print("\n" + "=" * 90)
    print("RESUMEN EJECUTIVO")
    print("=" * 90)
    print(f"\nExperimentos completados:")
    print(f"  - Baseline: {len(baseline_files)} archivos")
    print(f"  - NGINX Ingress: {len(nginx_files)} archivos")
    print(f"\nOverhead promedio de NGINX Ingress (P95):")
    for _, row in comparison_df.iterrows():
        print(f"  - {int(row['VUs'])} VUs: {row['Overhead_P95_%']:+.2f}%")
    
    print(f"\nArchivos generados:")
    print(f"  - {output_csv}")
    print(f"  - {args.output}/baseline_vs_nginx_boxplot.png")
    print(f"  - {args.output}/nginx_overhead.png")
    
    return 0

if __name__ == '__main__':
    exit(main())
