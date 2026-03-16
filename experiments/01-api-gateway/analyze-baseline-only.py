#!/usr/bin/env python3
"""
Análisis de Resultados Baseline - Control 1: API Gateway
Analiza únicamente los resultados baseline (sin gateway) para diferentes cargas
"""

import json
import glob
import argparse
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
from collections import defaultdict

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
                latencies.append(value)  # En milisegundos
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
        'max': np.max(arr)
    }

def analyze_baseline_results(result_files):
    """Analizar resultados baseline agrupados por VUs"""
    results = defaultdict(list)
    
    print("=" * 70)
    print("ANÁLISIS DE RESULTADOS BASELINE (Sin Gateway)")
    print("=" * 70)
    
    # Agrupar por nivel de carga (VUs)
    for file in result_files:
        if 'vus10' in file:
            vus = 10
        elif 'vus25' in file:
            vus = 25
        elif 'vus50' in file:
            vus = 50
        else:
            continue
        
        print(f"\nProcesando: {file}")
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
        
        stats = calculate_stats(all_latencies)
        summary[vus] = {
            'repetitions': len(reps),
            'total_requests': len(all_latencies),
            'stats': stats
        }
        
        print(f"\n{'=' * 70}")
        print(f"VUs: {vus} ({len(reps)} repeticiones)")
        print(f"{'=' * 70}")
        print(f"Total requests: {len(all_latencies):,}")
        print(f"Latencia promedio: {stats['mean']:.2f} ms")
        print(f"Latencia mediana (P50): {stats['median']:.2f} ms")
        print(f"P95: {stats['p95']:.2f} ms")
        print(f"P99: {stats['p99']:.2f} ms")
        print(f"Desv. estándar: {stats['std']:.2f} ms")
        print(f"Mín: {stats['min']:.2f} ms")
        print(f"Máx: {stats['max']:.2f} ms")
        
        print(f"\nPor repetición:")
        for i, rep in enumerate(reps, 1):
            print(f"  Rep {i}: {rep['count']:,} requests, "
                  f"P95={rep['stats']['p95']:.2f}ms, "
                  f"avg={rep['stats']['mean']:.2f}ms")
    
    return results, summary

def plot_baseline_comparison(results, output_dir='plots'):
    """Generar gráficos de comparación baseline"""
    import os
    os.makedirs(output_dir, exist_ok=True)
    
    # Configurar estilo
    sns.set_style("whitegrid")
    plt.rcParams['figure.figsize'] = (14, 6)
    plt.rcParams['font.size'] = 11
    
    # Preparar datos para boxplot
    data_for_plot = []
    for vus in sorted(results.keys()):
        for rep in results[vus]:
            for lat in rep['latencies']:
                data_for_plot.append({
                    'VUs': f'{vus} VUs',
                    'Latency (ms)': lat
                })
    
    df = pd.DataFrame(data_for_plot)
    
    # Boxplot comparativo
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(16, 6))
    
    # Boxplot de latencias
    sns.boxplot(data=df, x='VUs', y='Latency (ms)', ax=ax1, palette='Set2')
    ax1.set_title('Distribución de Latencias - Baseline (Sin Gateway)', fontsize=14, fontweight='bold')
    ax1.set_ylabel('Latencia (ms)', fontsize=12)
    ax1.set_xlabel('Carga (Usuarios Virtuales)', fontsize=12)
    ax1.grid(True, alpha=0.3)
    
    # Calcular P95 por VUs
    p95_data = []
    for vus in sorted(results.keys()):
        all_lats = []
        for rep in results[vus]:
            all_lats.extend(rep['latencies'])
        p95 = np.percentile(all_lats, 95)
        p95_data.append({'VUs': f'{vus} VUs', 'P95 (ms)': p95})
    
    p95_df = pd.DataFrame(p95_data)
    
    # Barplot P95
    bars = ax2.bar(p95_df['VUs'], p95_df['P95 (ms)'], color=['#66c2a5', '#fc8d62', '#8da0cb'])
    ax2.set_title('P95 de Latencia por Carga - Baseline', fontsize=14, fontweight='bold')
    ax2.set_ylabel('Latencia P95 (ms)', fontsize=12)
    ax2.set_xlabel('Carga (Usuarios Virtuales)', fontsize=12)
    ax2.grid(True, alpha=0.3, axis='y')
    
    # Añadir valores en las barras
    for bar in bars:
        height = bar.get_height()
        ax2.text(bar.get_x() + bar.get_width()/2., height,
                f'{height:.1f}ms',
                ha='center', va='bottom', fontsize=11, fontweight='bold')
    
    plt.tight_layout()
    output_file = f'{output_dir}/baseline_comparison.png'
    plt.savefig(output_file, dpi=300, bbox_inches='tight')
    print(f"\n✓ Gráfico guardado en: {output_file}")
    
    # Gráfico de tendencia
    fig, ax = plt.subplots(figsize=(10, 6))
    
    vus_list = sorted(results.keys())
    metrics_to_plot = ['mean', 'p50', 'p95', 'p99']
    colors = {'mean': '#1f77b4', 'p50': '#ff7f0e', 'p95': '#2ca02c', 'p99': '#d62728'}
    labels = {'mean': 'Promedio', 'p50': 'P50 (Mediana)', 'p95': 'P95', 'p99': 'P99'}
    
    for metric in metrics_to_plot:
        values = []
        for vus in vus_list:
            all_lats = []
            for rep in results[vus]:
                all_lats.extend(rep['latencies'])
            stats = calculate_stats(all_lats)
            values.append(stats[metric])
        
        ax.plot(vus_list, values, marker='o', linewidth=2, markersize=8,
               color=colors[metric], label=labels[metric])
    
    ax.set_title('Escalabilidad de Latencia - Baseline (Sin Gateway)', fontsize=14, fontweight='bold')
    ax.set_xlabel('Usuarios Virtuales Concurrentes', fontsize=12)
    ax.set_ylabel('Latencia (ms)', fontsize=12)
    ax.legend(loc='upper left', fontsize=11)
    ax.grid(True, alpha=0.3)
    ax.set_xticks(vus_list)
    
    output_file = f'{output_dir}/baseline_scalability.png'
    plt.savefig(output_file, dpi=300, bbox_inches='tight')
    print(f"✓ Gráfico de escalabilidad guardado en: {output_file}")

def main():
    parser = argparse.ArgumentParser(description='Analizar resultados baseline de experimento API Gateway')
    parser.add_argument('--results-dir', default='baseline/results',
                       help='Directorio con archivos JSON de k6')
    parser.add_argument('--output', default='plots',
                       help='Directorio para guardar gráficos')
    
    args = parser.parse_args()
    
    # Buscar archivos de resultados
    result_files = glob.glob(f'{args.results_dir}/baseline-*.json')
    
    if not result_files:
        print(f"✗ No se encontraron archivos de resultados en {args.results_dir}")
        return 1
    
    print(f"Encontrados {len(result_files)} archivos de resultados\n")
    
    # Analizar resultados
    results, summary = analyze_baseline_results(result_files)
    
    # Generar gráficos
    print(f"\n{'=' * 70}")
    print("GENERANDO GRÁFICOS")
    print(f"{'=' * 70}")
    plot_baseline_comparison(results, args.output)
    
    print(f"\n{'=' * 70}")
    print("ANÁLISIS COMPLETADO")
    print(f"{'=' * 70}")
    print(f"\nResultados procesados: {len(result_files)} archivos")
    print(f"Configuraciones analizadas: {len(summary)} niveles de carga")
    print(f"Gráficos generados en: {args.output}/")
    
    return 0

if __name__ == '__main__':
    exit(main())
