import pandas as pd
import os

# Archivos de entrada
KPIS_CSV = os.path.join(os.path.dirname(__file__), 'results', 'control-kpis.csv')
COMPARISON_CSV = os.path.join(os.path.dirname(__file__), 'results', 'all-controls-comparison.csv')

# Métricas clave a mostrar
METRICS = [
    ('latency_p95_ms', 'Latencia p95 (ms)'),
    ('latency_p99_ms', 'Latencia p99 (ms)'),
    ('rps', 'RPS'),
    ('error_rate_pct', 'Error (%)'),
    ('cpu_cores', 'CPU (cores)'),
    ('memory_mb', 'Mem (MB)'),
]

def main():
    # Leer los KPIs
    kpis = pd.read_csv(KPIS_CSV)
    # Filtrar solo las métricas clave
    kpis = kpis[kpis['metric'].isin([m[0] for m in METRICS])]
    # Pivotear para tabla resumen
    summary = kpis.pivot_table(
        index=['control','scenario'],
        columns='metric',
        values='value',
        aggfunc='mean'
    ).reset_index()
    # Renombrar columnas
    summary = summary.rename(columns={m[0]: m[1] for m in METRICS})
    # Ordenar columnas
    cols = ['control','scenario'] + [m[1] for m in METRICS]
    summary = summary[cols]
    # Guardar CSV
    out_csv = os.path.join(os.path.dirname(__file__), 'results', 'control-summary.csv')
    summary.to_csv(out_csv, index=False)
    print(f"[OK] Tabla resumen generada: {out_csv}")
    print(summary.to_string(index=False))

if __name__ == '__main__':
    main()
