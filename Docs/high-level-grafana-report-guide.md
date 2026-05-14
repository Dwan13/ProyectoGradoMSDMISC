# Grafana High-Level Report Guide (S1-S4)

## Objetivo
Montar un dashboard ejecutivo para explicar el trade-off seguridad vs calidad usando los 4 escenarios.

## Dataset base (generado)
- `Testing/results/anova/grafana_highlevel_long.csv`

Columnas:
- `scenario` (S1, S2, S3, S4)
- `vus` (1, 5, 10, 20)
- `metric` (`avg_ms`, `p95_ms`, `err_pct`, `rps`, `cpu_mcores`, `mem_mib`)
- `value`

## Paneles recomendados (alto nivel)
1. **Latency overview (avg_ms, p95_ms)**
   - Tipo: Time series o Line chart
   - Eje X: `vus`
   - Serie: `scenario`
   - Filtro `metric in [avg_ms,p95_ms]`

2. **Error vs Throughput trade-off**
   - Tipo: Scatter
   - X: `p95_ms`
   - Y: `err_pct`
   - Tamaño: `rps`
   - Color: `scenario`

3. **Resource cost at peak load**
   - Tipo: Bar chart
   - Filtro `vus=20`
   - Barras: `cpu_mcores`, `mem_mib` por `scenario`

4. **Scenario KPI cards**
   - Tipo: Stat
   - KPI recomendado:
     - `p95_ms` @ VU=20
     - `err_pct` @ VU=20
     - `rps` @ VU=20

5. **S2 vs S4 functional equivalence panel**
   - Tipo: Compare table
   - Filtrar escenarios S2 y S4
   - Mostrar 6 métricas por VU

## Estructura narrativa sugerida
1. Panel de resumen (S1-S4, 6 métricas).
2. Panel de trade-off (latencia/error/throughput).
3. Panel de costos de recursos.
4. Panel de comparabilidad funcional (S2 vs S4).
5. Panel de validación externa (S3 vs resto).

## Fuentes gráficas ya generadas (rápidas para reporte)
- `Testing/plots/high_level_report/all4_metrics_by_vus.png`
- `Testing/plots/high_level_report/tradeoff_error_vs_p95.png`
- `Testing/plots/high_level_report/resource_cost_vu20.png`

## Nota metodológica para dashboard
- S3 es benchmark avanzado nativo (validación externa).
- S4 es escenario funcionalmente equivalente a S2 (comparación 1:1).
- Para conclusiones causales principales del trade-off seguridad-calidad: priorizar S2 vs S4.
