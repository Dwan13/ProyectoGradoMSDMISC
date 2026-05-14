#!/usr/bin/env python3
"""
Gráficas comparativas intracontrol para las 6 métricas clave.
Compara variantes dentro de cada control (C1, C2, C3, C4).
Salida: Testing/results/plots/ con PNG de alta calidad (300 DPI).
"""

import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
import glob
from pathlib import Path

# Configuración para documentos académicos
plt.rcParams.update({
    'figure.dpi': 300,
    'savefig.dpi': 300,
    'font.size': 11,
    'font.family': 'sans-serif',
    'axes.labelsize': 12,
    'axes.titlesize': 14,
    'xtick.labelsize': 10,
    'ytick.labelsize': 10,
    'legend.fontsize': 10,
})

sns.set_style("whitegrid")
sns.set_palette("Set2")

# Crear directorio de salida
output_dir = Path("Testing/results/plots")
output_dir.mkdir(parents=True, exist_ok=True)

# Cargar datos consolidados (B1-B8)
files = sorted(glob.glob('Testing/results/scaling_tests/scaling-report_postgres-real_*_B*.csv'))
df = pd.concat([pd.read_csv(f) for f in files], ignore_index=True)

print(f"[INFO] Datos consolidados: {len(df)} filas (384 = 48 celdas × 8 bloques)")
print(f"[INFO] Controles: {sorted(df['control'].unique())}")

# Definir las 6 métricas
METRICS = {
    'avg_ms': 'Latencia Promedio (ms)',
    'p95_ms': 'Latencia P95 (ms)',
    'err_pct': 'Tasa de Error (%)',
    'rps': 'Requests/seg',
    'cpu_mcores': 'CPU (millicores)',
    'mem_mib': 'Memoria (MiB)',
}

# Paleta de colores para variantes
VARIANT_COLORS = {
    'baseline': '#1f77b4',
    'istio': '#ff7f0e',
    'kong': '#2ca02c',
    'istio-mtls': '#ff7f0e',
    'linkerd-mtls': '#d62728',
    'basic': '#9467bd',
    'strict': '#e377c2',
    'moderate': '#7f7f7f',
}

# ============================================================
# 1. GRÁFICAS POR MÉTRICA (4x1: una por control)
# ============================================================

for metric_key, metric_label in METRICS.items():
    fig, axes = plt.subplots(2, 2, figsize=(14, 10))
    fig.suptitle(f'Comparativa Intracontrol: {metric_label}', 
                 fontsize=16, fontweight='bold', y=0.995)
    
    controls = sorted(df['control'].unique())
    
    for idx, control in enumerate(controls):
        ax = axes[idx // 2, idx % 2]
        
        # Filtrar datos del control
        ctrl_data = df[df['control'] == control].copy()
        
        # Boxplot por variante y VUs
        sns.boxplot(
            data=ctrl_data, 
            x='variant', 
            y=metric_key,
            hue='vus',
            ax=ax,
            palette='Set2'
        )
        
        ax.set_title(f'{control}', fontweight='bold', fontsize=12)
        ax.set_xlabel('Variante', fontweight='bold')
        ax.set_ylabel(metric_label, fontweight='bold')
        ax.grid(True, alpha=0.3, axis='y')
        ax.legend(title='VUs', loc='best', fontsize=9)
    
    plt.tight_layout()
    plt.savefig(output_dir / f'01_metric_{metric_key}.png', 
                bbox_inches='tight', dpi=300)
    print(f"✓ Guardado: 01_metric_{metric_key}.png")
    plt.close()

# ============================================================
# 2. GRÁFICA INDIVIDUAL POR MÉTRICA (resumen agregado)
# ============================================================

for metric_key, metric_label in METRICS.items():
    fig, ax = plt.subplots(figsize=(12, 6))
    
    # Agregar por control/variante (promedio de todos los VUs y bloques)
    summary = df.groupby(['control', 'variant'])[metric_key].agg(['mean', 'std']).reset_index()
    
    # Graficar con barras y líneas de error
    x_pos = 0
    x_labels = []
    x_ticks = []
    colors = []
    
    for control in sorted(df['control'].unique()):
        ctrl_summary = summary[summary['control'] == control]
        
        for idx, row in ctrl_summary.iterrows():
            variant = row['variant']
            mean = row['mean']
            std = row['std']
            
            ax.bar(x_pos, mean, yerr=std, 
                   color=VARIANT_COLORS.get(variant, '#808080'),
                   capsize=5, alpha=0.7, edgecolor='black', linewidth=1.5)
            
            x_labels.append(f"{control}\n{variant}")
            x_ticks.append(x_pos)
            x_pos += 1
        
        x_pos += 0.5  # Espacio entre controles
    
    ax.set_xticks(x_ticks)
    ax.set_xticklabels(x_labels, fontsize=9)
    ax.set_ylabel(metric_label, fontweight='bold', fontsize=12)
    ax.set_title(f'{metric_label} - Comparativa Intracontrol (Promedio ± Std)', 
                 fontweight='bold', fontsize=13)
    ax.grid(True, alpha=0.3, axis='y')
    
    plt.tight_layout()
    plt.savefig(output_dir / f'02_summary_{metric_key}.png', 
                bbox_inches='tight', dpi=300)
    print(f"✓ Guardado: 02_summary_{metric_key}.png")
    plt.close()

# ============================================================
# 3. HEATMAP: CONTROL × VARIANTE (valores promedio)
# ============================================================

for metric_key, metric_label in METRICS.items():
    # Crear matriz pivot: filas=variante, columnas=control, valores=métrica
    pivot = df.groupby(['control', 'variant'])[metric_key].mean().unstack(fill_value=0)
    
    fig, ax = plt.subplots(figsize=(8, 6))
    
    sns.heatmap(pivot.T, annot=True, fmt='.2f', cmap='RdYlGn_r', 
                cbar_kws={'label': metric_label}, ax=ax, linewidths=0.5)
    
    ax.set_title(f'Heatmap: {metric_label} por Control y Variante', 
                 fontweight='bold', fontsize=13)
    ax.set_xlabel('Variante', fontweight='bold')
    ax.set_ylabel('Control', fontweight='bold')
    
    plt.tight_layout()
    plt.savefig(output_dir / f'03_heatmap_{metric_key}.png', 
                bbox_inches='tight', dpi=300)
    print(f"✓ Guardado: 03_heatmap_{metric_key}.png")
    plt.close()

# ============================================================
# 4. LÍNEAS: Escalado por VUs (una línea por variante)
# ============================================================

for metric_key, metric_label in METRICS.items():
    fig, axes = plt.subplots(2, 2, figsize=(14, 10))
    fig.suptitle(f'Escalado por VUs: {metric_label}', 
                 fontsize=16, fontweight='bold')
    
    for idx, control in enumerate(sorted(df['control'].unique())):
        ax = axes[idx // 2, idx % 2]
        
        ctrl_data = df[df['control'] == control].copy()
        
        # Agrupar por VUs y variante, tomar promedio
        scaled = ctrl_data.groupby(['vus', 'variant'])[metric_key].mean().reset_index()
        
        # Graficar línea por variante
        for variant in sorted(scaled['variant'].unique()):
            var_data = scaled[scaled['variant'] == variant]
            ax.plot(var_data['vus'], var_data[metric_key], 
                   marker='o', linewidth=2, label=variant,
                   color=VARIANT_COLORS.get(variant, '#808080'))
        
        ax.set_title(f'{control}', fontweight='bold', fontsize=12)
        ax.set_xlabel('VUs', fontweight='bold')
        ax.set_ylabel(metric_label, fontweight='bold')
        ax.set_xticks([1, 5, 10, 20])
        ax.grid(True, alpha=0.3)
        ax.legend(loc='best', fontsize=9)
    
    plt.tight_layout()
    plt.savefig(output_dir / f'04_scaling_{metric_key}.png', 
                bbox_inches='tight', dpi=300)
    print(f"✓ Guardado: 04_scaling_{metric_key}.png")
    plt.close()

# ============================================================
# 5. RESUMEN ESTADÍSTICO POR CONTROL (tabla visual)
# ============================================================

for control in sorted(df['control'].unique()):
    fig, ax = plt.subplots(figsize=(12, 6))
    ax.axis('tight')
    ax.axis('off')
    
    ctrl_data = df[df['control'] == control].copy()
    summary = ctrl_data.groupby('variant')[list(METRICS.keys())].agg(['mean', 'std'])
    
    # Crear tabla
    table_data = []
    table_data.append(['Variante'] + [f"{k}\n(mean)" for k in METRICS.keys()])
    
    for variant in sorted(ctrl_data['variant'].unique()):
        row = [variant]
        for metric_key in METRICS.keys():
            var_data = ctrl_data[ctrl_data['variant'] == variant][metric_key]
            mean = var_data.mean()
            std = var_data.std()
            row.append(f"{mean:.2f}\n±{std:.2f}")
        table_data.append(row)
    
    table = ax.table(cellText=table_data, loc='center', cellLoc='center')
    table.auto_set_font_size(False)
    table.set_fontsize(10)
    table.scale(1, 2)
    
    # Colorear encabezado
    for i in range(len(METRICS) + 1):
        table[(0, i)].set_facecolor('#4CAF50')
        table[(0, i)].set_text_props(weight='bold', color='white')
    
    ax.set_title(f'Estadísticas por Variante: {control}', 
                 fontweight='bold', fontsize=14, pad=20)
    
    plt.tight_layout()
    plt.savefig(output_dir / f'05_stats_table_{control}.png', 
                bbox_inches='tight', dpi=300)
    print(f"✓ Guardado: 05_stats_table_{control}.png")
    plt.close()

print(f"\n[SUCCESS] Todas las gráficas generadas en: {output_dir.absolute()}")
print(f"[INFO] Total de archivos PNG: {len(list(output_dir.glob('*.png')))}")
