#!/usr/bin/env python3
"""
Script para generar gráficos académicos de alta calidad
para insertar en documentos Word/PDF.

Uso:
    python3 generate_plots.py
    
Salida:
    Testing/plots/ con archivos PNG de 300 DPI
"""

import matplotlib.pyplot as plt
import seaborn as sns
import pandas as pd
import numpy as np
from pathlib import Path

# Configuración global para calidad académica
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
    'figure.titlesize': 18
})

# Estilo profesional
sns.set_style("whitegrid")
sns.set_palette("colorblind")

# Crear directorio de salida
output_dir = Path("plots")
output_dir.mkdir(parents=True, exist_ok=True)

# ============================================================
# GRÁFICO 1: Boxplot de Latencia P95
# ============================================================
def plot_latency_comparison():
    """Comparación de latencias HTTP vs HTTPS"""
    
    # Datos simulados (reemplazar con datos reales de k6)
    np.random.seed(42)
    http_latencies = np.random.normal(46, 3, 100)  # μ=46, σ=3
    https_latencies = np.random.normal(68, 5, 100)  # μ=68, σ=5
    
    data = pd.DataFrame({
        'Protocolo': ['HTTP']*100 + ['HTTPS']*100,
        'Latencia (ms)': np.concatenate([http_latencies, https_latencies])
    })
    
    fig, ax = plt.subplots(figsize=(8, 6))
    
    # Boxplot con colores personalizados
    box_plot = sns.boxplot(
        x='Protocolo', 
        y='Latencia (ms)', 
        data=data,
        palette={'HTTP': '#4CAF50', 'HTTPS': '#F44336'},
        ax=ax
    )
    
    # Agregar media como punto
    means = data.groupby('Protocolo')['Latencia (ms)'].mean()
    ax.plot([0, 1], means, 'D', color='black', markersize=8, 
            label='Media', zorder=10)
    
    # Título y etiquetas
    ax.set_title('Comparación de Latencia P95: HTTP vs HTTPS', 
                 fontweight='bold', pad=20)
    ax.set_ylabel('Latencia (ms)', fontweight='bold')
    ax.set_xlabel('Protocolo de Comunicación', fontweight='bold')
    
    # Agregar línea horizontal en P95
    p95_http = np.percentile(http_latencies, 95)
    p95_https = np.percentile(https_latencies, 95)
    ax.axhline(p95_http, color='green', linestyle='--', alpha=0.5, 
               label=f'P95 HTTP: {p95_http:.1f}ms')
    ax.axhline(p95_https, color='red', linestyle='--', alpha=0.5, 
               label=f'P95 HTTPS: {p95_https:.1f}ms')
    
    # Mostrar overhead en el gráfico
    overhead = ((p95_https - p95_http) / p95_http) * 100
    ax.text(0.5, max(https_latencies), 
            f'Overhead: +{overhead:.1f}%',
            ha='center', va='bottom', fontsize=13, 
            bbox=dict(boxstyle='round', facecolor='yellow', alpha=0.3),
            fontweight='bold')
    
    ax.legend(loc='upper right')
    ax.grid(True, alpha=0.3)
    
    plt.tight_layout()
    plt.savefig(output_dir / 'latency_comparison.png', 
                bbox_inches='tight', dpi=300)
    print(f"✅ Guardado: {output_dir / 'latency_comparison.png'}")
    plt.close()

# ============================================================
# GRÁFICO 2: Throughput vs Carga
# ============================================================
def plot_throughput_vs_load():
    """Throughput en función de Virtual Users"""
    
    vus = [5, 10, 25, 50, 100]
    http_throughput = [38, 77, 185, 355, 450]  # Datos simulados
    https_throughput = [32, 65, 160, 305, 380]
    
    fig, ax = plt.subplots(figsize=(10, 6))
    
    # Líneas con marcadores
    ax.plot(vus, http_throughput, 'o-', linewidth=2.5, markersize=10,
            color='#4CAF50', label='HTTP', alpha=0.8)
    ax.plot(vus, https_throughput, 's-', linewidth=2.5, markersize=10,
            color='#F44336', label='HTTPS', alpha=0.8)
    
    # Área entre curvas (diferencia de rendimiento)
    ax.fill_between(vus, http_throughput, https_throughput, 
                     alpha=0.2, color='gray', 
                     label='Degradación por TLS')
    
    # Título y etiquetas
    ax.set_title('Throughput del Sistema: HTTP vs HTTPS', 
                 fontweight='bold', pad=20)
    ax.set_xlabel('Carga (Virtual Users)', fontweight='bold')
    ax.set_ylabel('Throughput (requests/segundo)', fontweight='bold')
    
    # Configuración ejes
    ax.set_xticks(vus)
    ax.grid(True, alpha=0.3, linestyle='--')
    
    # Anotaciones de valores
    for i, (vu, http, https) in enumerate(zip(vus, http_throughput, https_throughput)):
        ax.annotate(f'{http}', (vu, http), 
                    textcoords="offset points", xytext=(0,10), 
                    ha='center', fontsize=9, color='green')
        ax.annotate(f'{https}', (vu, https), 
                    textcoords="offset points", xytext=(0,-15), 
                    ha='center', fontsize=9, color='red')
    
    ax.legend(loc='upper left', framealpha=0.9)
    
    plt.tight_layout()
    plt.savefig(output_dir / 'throughput_vs_load.png', 
                bbox_inches='tight', dpi=300)
    print(f"✅ Guardado: {output_dir / 'throughput_vs_load.png'}")
    plt.close()

# ============================================================
# GRÁFICO 3: Overhead de Recursos (Barras)
# ============================================================
def plot_resource_overhead():
    """Overhead de CPU, Memoria, Red"""
    
    metrics = ['Latencia\nP95', 'Throughput', 'CPU\nUtilización', 
               'Red TX']
    http_values = [46, 450, 18, 2.1]
    https_values = [68, 380, 29, 2.3]
    
    # Calcular overhead porcentual
    overhead = [((h - ht) / ht) * 100 if ht != 0 else 0 
                for h, ht in zip(https_values, http_values)]
    
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(14, 6))
    
    # Subplot 1: Valores absolutos
    x = np.arange(len(metrics))
    width = 0.35
    
    bars1 = ax1.bar(x - width/2, http_values, width, 
                    label='HTTP', color='#4CAF50', alpha=0.8)
    bars2 = ax1.bar(x + width/2, https_values, width, 
                    label='HTTPS', color='#F44336', alpha=0.8)
    
    ax1.set_title('Métricas de Rendimiento: HTTP vs HTTPS', 
                  fontweight='bold', pad=15)
    ax1.set_ylabel('Valor (unidades mixtas)', fontweight='bold')
    ax1.set_xticks(x)
    ax1.set_xticklabels(metrics)
    ax1.legend()
    ax1.grid(True, alpha=0.3, axis='y')
    
    # Agregar valores encima de barras
    for bar in bars1 + bars2:
        height = bar.get_height()
        ax1.annotate(f'{height:.1f}',
                    xy=(bar.get_x() + bar.get_width() / 2, height),
                    xytext=(0, 3),
                    textcoords="offset points",
                    ha='center', va='bottom', fontsize=9)
    
    # Subplot 2: Overhead porcentual
    colors_overhead = ['#F44336' if o > 0 else '#4CAF50' for o in overhead]
    bars = ax2.barh(metrics, overhead, color=colors_overhead, alpha=0.7)
    
    ax2.set_title('Overhead de HTTPS respecto a HTTP', 
                  fontweight='bold', pad=15)
    ax2.set_xlabel('Overhead (%)', fontweight='bold')
    ax2.axvline(0, color='black', linewidth=0.8)
    ax2.grid(True, alpha=0.3, axis='x')
    
    # Valores en las barras
    for i, (bar, value) in enumerate(zip(bars, overhead)):
        ax2.text(value + 2, i, f'{value:+.1f}%', 
                va='center', fontweight='bold', fontsize=11)
    
    plt.tight_layout()
    plt.savefig(output_dir / 'resource_overhead.png', 
                bbox_inches='tight', dpi=300)
    print(f"✅ Guardado: {output_dir / 'resource_overhead.png'}")
    plt.close()

# ============================================================
# GRÁFICO 4: Serie Temporal de Latencia
# ============================================================
def plot_latency_timeseries():
    """Serie temporal de latencia durante experimento"""
    
    # Simular 300 segundos de datos
    time = np.arange(0, 300, 1)
    
    # Latencia HTTP con variación realista
    http_latency = 46 + np.random.normal(0, 3, len(time)) + \
                   np.sin(time / 30) * 5  # Oscilación periódica
    
    # Latencia HTTPS con más variación
    https_latency = 68 + np.random.normal(0, 5, len(time)) + \
                    np.sin(time / 30) * 7
    
    fig, ax = plt.subplots(figsize=(12, 6))
    
    # Líneas de latencia
    ax.plot(time, http_latency, label='HTTP', 
            color='#4CAF50', alpha=0.7, linewidth=1.5)
    ax.plot(time, https_latency, label='HTTPS', 
            color='#F44336', alpha=0.7, linewidth=1.5)
    
    # Líneas de referencia (promedios)
    ax.axhline(np.mean(http_latency), color='green', 
               linestyle='--', alpha=0.5, 
               label=f'HTTP avg: {np.mean(http_latency):.1f}ms')
    ax.axhline(np.mean(https_latency), color='red', 
               linestyle='--', alpha=0.5, 
               label=f'HTTPS avg: {np.mean(https_latency):.1f}ms')
    
    # Sombreado de desviación estándar
    ax.fill_between(time, 
                     http_latency - 3, http_latency + 3,
                     alpha=0.2, color='green')
    ax.fill_between(time, 
                     https_latency - 5, https_latency + 5,
                     alpha=0.2, color='red')
    
    ax.set_title('Latencia en el Tiempo (Experimento de 5 minutos)', 
                 fontweight='bold', pad=20)
    ax.set_xlabel('Tiempo (segundos)', fontweight='bold')
    ax.set_ylabel('Latencia (ms)', fontweight='bold')
    ax.legend(loc='upper right')
    ax.grid(True, alpha=0.3)
    
    plt.tight_layout()
    plt.savefig(output_dir / 'latency_timeseries.png', 
                bbox_inches='tight', dpi=300)
    print(f"✅ Guardado: {output_dir / 'latency_timeseries.png'}")
    plt.close()

# ============================================================
# GRÁFICO 5: Heatmap de Correlaciones
# ============================================================
def plot_correlation_heatmap():
    """Heatmap de correlaciones entre métricas"""
    
    # Datos simulados de correlación
    np.random.seed(42)
    n = 100
    
    data = pd.DataFrame({
        'Latencia': np.random.normal(50, 10, n),
        'CPU': np.random.normal(25, 5, n),
        'Memoria': np.random.normal(200, 30, n),
        'Red TX': np.random.normal(2.5, 0.5, n),
        'Throughput': np.random.normal(400, 50, n)
    })
    
    # Añadir correlaciones artificiales
    data['CPU'] = data['Latencia'] * 0.5 + np.random.normal(0, 3, n)
    data['Throughput'] = 600 - data['Latencia'] * 2 + np.random.normal(0, 20, n)
    
    # Calcular matriz de correlación
    corr = data.corr()
    
    fig, ax = plt.subplots(figsize=(10, 8))
    
    # Heatmap con anotaciones
    sns.heatmap(corr, annot=True, fmt='.2f', 
                cmap='RdYlGn_r', center=0,
                square=True, linewidths=1, 
                cbar_kws={"shrink": 0.8},
                ax=ax)
    
    ax.set_title('Matriz de Correlación de Métricas de Rendimiento', 
                 fontweight='bold', pad=20, fontsize=16)
    
    plt.tight_layout()
    plt.savefig(output_dir / 'correlation_heatmap.png', 
                bbox_inches='tight', dpi=300)
    print(f"✅ Guardado: {output_dir / 'correlation_heatmap.png'}")
    plt.close()

# ============================================================
# EJECUTAR TODOS LOS GRÁFICOS
# ============================================================
if __name__ == "__main__":
    print("🎨 Generando gráficos académicos...")
    print("=" * 60)
    
    plot_latency_comparison()
    plot_throughput_vs_load()
    plot_resource_overhead()
    plot_latency_timeseries()
    plot_correlation_heatmap()
    
    print("=" * 60)
    print(f"✅ Todos los gráficos guardados en: {output_dir}")
    print(f"\n📌 Próximos pasos:")
    print(f"   1. Abrir {output_dir}")
    print(f"   2. Insertar imágenes en Word: Insert → Pictures")
    print(f"   3. Ajustar tamaño manteniendo aspect ratio")
    print(f"   4. Agregar referencias cruzadas en el texto")
