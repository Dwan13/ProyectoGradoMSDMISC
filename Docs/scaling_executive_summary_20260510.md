# Resumen Ejecutivo de Escalabilidad (postgres-real)

Fecha: 2026-05-10

## Alcance
- Comparativa entre corridas del 2026-05-10 vs 2026-05-09.
- Cobertura: 48 combinaciones (control, variante, VUs).
- Métricas: avg_ms, p95_ms, err_pct, rps, cpu_mcores, mem_mib.

## Resultado Global (Hoy - Ayer)
- Delta promedio avg_ms: -0.577 ms
- Delta promedio p95_ms: -1.071 ms
- Delta promedio err_pct: 0.000 pp
- Delta promedio rps: 0.101

## Hallazgos Clave
- Mayor mejora en p95: C1/istio/20 VUs con delta -10.78 ms.
- Mayor mejora en avg_ms: C1/istio/20 VUs con delta -2.62 ms.
- Mayor mejora en rps: C2/istio-mtls/20 VUs con delta +0.93.
- Mayor incremento de error: C4/moderate/5 VUs con delta 0.02 pp.

## ANOVA por Experimentación (factor: variante)
- Se detectaron diferencias significativas en:
  - C4 / avg_ms: F=19.0874, p=0.000579
  - C4 / p95_ms: F=10.4516, p=0.004502
  - C4 / err_pct: F=13.7950, p=0.001815

## Interpretación Técnica
- C4 muestra diferencias estadísticamente significativas entre variantes en latencia y error, consistente con el diseño de políticas de rate limiting (moderate/strict).
- En C1-C3 no se observa evidencia de cambio significativo entre variantes para latencia y throughput en esta comparación diaria.
- Los cambios globales favorecen menor latencia y throughput ligeramente superior sin degradación global del error.

## Archivos de Soporte
- Testing/results/scaling_tests/comparison_postgres-real_20260510_vs_20260509.csv
- Testing/results/scaling_tests/comparison_summary_by_variant_20260510_vs_20260509.csv
- Testing/results/scaling_tests/anova_matrix_by_control_20260510.csv
- Docs/scaling_comparative_anova_20260510.tex