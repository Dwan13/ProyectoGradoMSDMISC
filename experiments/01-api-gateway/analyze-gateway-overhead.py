#!/usr/bin/env python3
"""
Análisis de Overhead de API Gateway
Compara Baseline vs Kong vs NGINX

Uso:
    python3 analyze-gateway-overhead.py \\
      --baseline baseline/results/*.json \\
      --kong kong/results/*.json \\
      --nginx nginx/results/*.json \\
      --output gateway-report.pdf
"""

import json
import glob
import sys
from pathlib import Path
import argparse
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
from scipy import stats

# Configuración de gráficos académicos
plt.rcParams.update({
    'figure.dpi': 300,
    'savefig.dpi': 300,
    'font.size': 12,
    'font.family': 'serif',
    'axes.labelsize': 14,
    'axes.titlesize': 16,
    'xtick.labelsize': 12,
    'ytick.labelsize': 12,
    'legend.fontsize': 12,
})

sns.set_style("whitegrid")
sns.set_palette("colorblind")


def load_k6_results(pattern):
    """Cargar resultados de k6 desde archivos JSON"""
    files = glob.glob(pattern)
    if not files:
        print(f"⚠️  No se encontraron archivos: {pattern}")
        return []
    
    results = []
    for f in files:
        try:
            with open(f, 'r') as file:
                # k6 JSON output es JSONL (una línea por métrica)
                for line in file:
                    if not line.strip():
                        continue
                    data = json.loads(line)
                    results.append(data)
        except Exception as e:
            print(f"Error leyendo {f}: {e}")
    
    return results


def extract_metrics(results):
    """Extraer métricas de resultados k6"""
    latencies = []
    throughputs = []
    errors = []
    
    for entry in results:
        if entry.get('type') == 'Point':
            metric = entry.get('metric')
            value = entry.get('data', {}).get('value', 0)
            
            if metric == 'http_req_duration':
                latencies.append(value)
            elif metric == 'http_reqs':
                throughputs.append(value)
            elif metric == 'http_req_failed':
                errors.append(value)
    
    return {
        'latency': latencies,
        'throughput': throughputs,
        'error_rate': errors
    }


def calculate_stats(data):
    """Calcular estadísticas descriptivas"""
    if not data:
        return {}
    
    return {
        'mean': np.mean(data),
        'median': np.median(data),
        'std': np.std(data),
        'p50': np.percentile(data, 50),
        'p95': np.percentile(data, 95),
        'p99': np.percentile(data, 99),
        'min': np.min(data),
        'max': np.max(data),
    }


def calculate_overhead(baseline, treatment):
    """Calcular overhead porcentual"""
    if baseline == 0:
        return 0
    return ((treatment - baseline) / baseline) * 100


def compare_scenarios(baseline_data, kong_data, nginx_data):
    """Comparar los 3 escenarios"""
    print("\n" + "="*60)
    print("  ANÁLISIS COMPARATIVO: API GATEWAY OVERHEAD")
    print("="*60)
    
    # Latencia
    print("\n📊 Latencia (ms)")
    print("-" * 60)
    
    baseline_lat = calculate_stats(baseline_data['latency'])
    kong_lat = calculate_stats(kong_data['latency'])
    nginx_lat = calculate_stats(nginx_data['latency'])
    
    print(f"{'Métrica':<15} {'Baseline':<12} {'Kong':<12} {'NGINX':<12}")
    print("-" * 60)
    print(f"{'Promedio':<15} {baseline_lat.get('mean', 0):>10.2f}  "
          f"{kong_lat.get('mean', 0):>10.2f}  {nginx_lat.get('mean', 0):>10.2f}")
    print(f"{'P95':<15} {baseline_lat.get('p95', 0):>10.2f}  "
          f"{kong_lat.get('p95', 0):>10.2f}  {nginx_lat.get('p95', 0):>10.2f}")
    print(f"{'P99':<15} {baseline_lat.get('p99', 0):>10.2f}  "
          f"{kong_lat.get('p99', 0):>10.2f}  {nginx_lat.get('p99', 0):>10.2f}")
    
    # Overhead
    print("\n📈 Overhead vs Baseline (%)")
    print("-" * 60)
    
    kong_overhead_p95 = calculate_overhead(
        baseline_lat.get('p95', 0), 
        kong_lat.get('p95', 0)
    )
    nginx_overhead_p95 = calculate_overhead(
        baseline_lat.get('p95', 0), 
        nginx_lat.get('p95', 0)
    )
    
    print(f"{'Kong P95':<20} {kong_overhead_p95:>+10.2f}%")
    print(f"{'NGINX P95':<20} {nginx_overhead_p95:>+10.2f}%")
    
    # Throughput
    print("\n🚀 Throughput (req/s)")
    print("-" * 60)
    
    baseline_thr = calculate_stats(baseline_data['throughput'])
    kong_thr = calculate_stats(kong_data['throughput'])
    nginx_thr = calculate_stats(nginx_data['throughput'])
    
    print(f"{'Baseline':<15} {baseline_thr.get('mean', 0):>10.2f}")
    print(f"{'Kong':<15} {kong_thr.get('mean', 0):>10.2f}  "
          f"({calculate_overhead(baseline_thr.get('mean', 1), kong_thr.get('mean', 0)):>+6.1f}%)")
    print(f"{'NGINX':<15} {nginx_thr.get('mean', 0):>10.2f}  "
          f"({calculate_overhead(baseline_thr.get('mean', 1), nginx_thr.get('mean', 0)):>+6.1f}%)")
    
    # Pruebas de hipótesis
    print("\n🔬 Pruebas Estadísticas (t-test)")
    print("-" * 60)
    
    # Kong vs Baseline
    if len(baseline_data['latency']) > 0 and len(kong_data['latency']) > 0:
        t_stat, p_value = stats.ttest_ind(
            baseline_data['latency'], 
            kong_data['latency']
        )
        print(f"Kong vs Baseline: t={t_stat:.3f}, p={p_value:.4f} ", end="")
        print("✅ Significativo" if p_value < 0.05 else "❌ No significativo")
    
    # NGINX vs Baseline
    if len(baseline_data['latency']) > 0 and len(nginx_data['latency']) > 0:
        t_stat, p_value = stats.ttest_ind(
            baseline_data['latency'], 
            nginx_data['latency']
        )
        print(f"NGINX vs Baseline: t={t_stat:.3f}, p={p_value:.4f} ", end="")
        print("✅ Significativo" if p_value < 0.05 else "❌ No significativo")
    
    # Kong vs NGINX
    if len(kong_data['latency']) > 0 and len(nginx_data['latency']) > 0:
        t_stat, p_value = stats.ttest_ind(
            kong_data['latency'], 
            nginx_data['latency']
        )
        print(f"Kong vs NGINX: t={t_stat:.3f}, p={p_value:.4f} ", end="")
        print("✅ Significativo" if p_value < 0.05 else "❌ No significativo")
    
    return {
        'baseline': {'latency': baseline_lat, 'throughput': baseline_thr},
        'kong': {'latency': kong_lat, 'throughput': kong_thr},
        'nginx': {'latency': nginx_lat, 'throughput': nginx_thr},
        'overhead': {
            'kong_p95': kong_overhead_p95,
            'nginx_p95': nginx_overhead_p95,
        }
    }


def plot_comparison(baseline_data, kong_data, nginx_data, output_dir):
    """Generar gráficos comparativos"""
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    
    print(f"\n📊 Generando gráficos en {output_dir}")
    
    # Gráfico 1: Boxplot de latencia
    fig, ax = plt.subplots(figsize=(10, 6))
    
    data = pd.DataFrame({
        'Gateway': ['Baseline']*len(baseline_data['latency']) + 
                   ['Kong']*len(kong_data['latency']) + 
                   ['NGINX']*len(nginx_data['latency']),
        'Latencia (ms)': baseline_data['latency'] + 
                         kong_data['latency'] + 
                         nginx_data['latency']
    })
    
    sns.boxplot(x='Gateway', y='Latencia (ms)', data=data, 
                palette={'Baseline': '#4CAF50', 'Kong': '#F44336', 'NGINX': '#2196F3'},
                ax=ax)
    
    ax.set_title('Comparación de Latencia: Baseline vs Gateways', 
                 fontweight='bold', pad=20)
    ax.set_ylabel('Latencia (ms)', fontweight='bold')
    ax.set_xlabel('Configuración', fontweight='bold')
    ax.grid(True, alpha=0.3)
    
    plt.tight_layout()
    plt.savefig(output_dir / 'latency_comparison.png', dpi=300, bbox_inches='tight')
    print(f"  ✓ latency_comparison.png")
    plt.close()
    
    # Gráfico 2: Barras de overhead
    fig, ax = plt.subplots(figsize=(8, 6))
    
    baseline_stats = calculate_stats(baseline_data['latency'])
    kong_stats = calculate_stats(kong_data['latency'])
    nginx_stats = calculate_stats(nginx_data['latency'])
    
    gateways = ['Baseline', 'Kong', 'NGINX']
    p95_values = [
        baseline_stats.get('p95', 0),
        kong_stats.get('p95', 0),
        nginx_stats.get('p95', 0)
    ]
    
    colors = ['#4CAF50', '#F44336', '#2196F3']
    bars = ax.bar(gateways, p95_values, color=colors, alpha=0.7)
    
    # Agregar valores encima de barras
    for bar in bars:
        height = bar.get_height()
        ax.annotate(f'{height:.1f}ms',
                   xy=(bar.get_x() + bar.get_width() / 2, height),
                   xytext=(0, 3),
                   textcoords="offset points",
                   ha='center', va='bottom', fontsize=11, fontweight='bold')
    
    ax.set_title('Latencia P95 por Gateway', fontweight='bold', pad=20)
    ax.set_ylabel('Latencia P95 (ms)', fontweight='bold')
    ax.set_xlabel('Gateway', fontweight='bold')
    ax.grid(True, alpha=0.3, axis='y')
    
    plt.tight_layout()
    plt.savefig(output_dir / 'p95_comparison.png', dpi=300, bbox_inches='tight')
    print(f"  ✓ p95_comparison.png")
    plt.close()


def main():
    parser = argparse.ArgumentParser(description='Analyze API Gateway overhead')
    parser.add_argument('--baseline', required=True, help='Baseline results pattern')
    parser.add_argument('--kong', required=True, help='Kong results pattern')
    parser.add_argument('--nginx', required=True, help='NGINX results pattern')
    parser.add_argument('--output', default='plots', help='Output directory')
    
    args = parser.parse_args()
    
    print("🔍 Cargando resultados...")
    
    baseline_results = load_k6_results(args.baseline)
    kong_results = load_k6_results(args.kong)
    nginx_results = load_k6_results(args.nginx)
    
    print(f"  Baseline: {len(baseline_results)} entries")
    print(f"  Kong: {len(kong_results)} entries")
    print(f"  NGINX: {len(nginx_results)} entries")
    
    baseline_metrics = extract_metrics(baseline_results)
    kong_metrics = extract_metrics(kong_results)
    nginx_metrics = extract_metrics(nginx_results)
    
    # Análisis comparativo
    stats_summary = compare_scenarios(baseline_metrics, kong_metrics, nginx_metrics)
    
    # Generar gráficos
    plot_comparison(baseline_metrics, kong_metrics, nginx_metrics, args.output)
    
    print("\n✅ Análisis completado")
    print("="*60)


if __name__ == '__main__':
    main()
