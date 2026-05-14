# Comparación Consolidada - Escenarios 1, 2 y 3

## Fuentes usadas
- Escenario 1: Testing/results/scaling_tests/scaling-report_20260509.csv
- Escenario 2: Testing/results/scaling_tests/scaling-report_postgres-real_20260509.csv
- Escenario 3: Testing/results/scaling_tests/scaling-report_mubench-advanced_20260509.csv
- Escenario 4: Testing/results/scaling_tests/scaling-report_s4_20260509_191154.csv
- Consolidado: Testing/results/scaling_tests/four-scenarios-summary_latest.csv

## Metodología de consolidación
- Se agregaron métricas por nivel de VUs.
- Escenario 1 y 2: promedio sobre 12 combinaciones (4 controles x 3 variantes).
- Escenario 3: una corrida agregada por VU (malla avanzada, samples=1).

## Resumen comparativo por VU

### VU 1
- Escenario 1: avg=8.77ms, p95=16.96ms, err=3.47%, rps=3.77
- Escenario 2: avg=8.53ms, p95=16.48ms, err=3.47%, rps=3.88
- Escenario 3: avg=209.00ms, p95=263.30ms, err=0.00%, rps=3.23

### VU 5
- Escenario 1: avg=9.93ms, p95=20.26ms, err=7.34%, rps=19.30
- Escenario 2: avg=10.14ms, p95=20.34ms, err=7.34%, rps=19.26
- Escenario 3: avg=773.26ms, p95=1073.44ms, err=0.58%, rps=5.73

### VU 10
- Escenario 1: avg=10.76ms, p95=23.11ms, err=7.84%, rps=38.43
- Escenario 2: avg=10.32ms, p95=22.09ms, err=7.84%, rps=38.49
- Escenario 3: avg=1649.90ms, p95=2397.45ms, err=1.74%, rps=5.75

### VU 20
- Escenario 1: avg=12.37ms, p95=28.59ms, err=8.09%, rps=68.11
- Escenario 2: avg=11.74ms, p95=25.90ms, err=8.09%, rps=76.55
- Escenario 3: avg=3705.92ms, p95=5521.59ms, err=12.38%, rps=5.38

## Conclusión técnica
- Escenario 2 se mantiene muy cercano al escenario 1 en latencia agregada, con mayor uso de memoria y mejor throughput al máximo VU.
- Escenario 3 representa un perfil de carga avanzada y mucho más costoso en cómputo/latencia, útil para pruebas de estrés de arquitectura.
- Escenario 4 reproduce la semántica funcional create/read de usuarios con persistencia y es la base correcta para comparar 1:1 con S2.
- Para comparación académica estricta entre los 3, conviene normalizar por tipo de workload (porque escenario 3 no es equivalente en complejidad interna al 1/2).

## Nota de validez experimental
- La comparación 1 vs 2 es metodológicamente equivalente bajo la misma matriz de controles C1-C4 y 6 métricas.
- La comparación con escenario 3 es exploratoria: se replicaron VUs y métricas, pero no el mismo flujo funcional ni los controles C1-C4 implementados de la misma manera.
- La comparación con escenario 4 sí es la adecuada para equivalencia funcional 1:1 con S2.
- Ver evaluación técnica detallada: `Docs/scenario-3-equivalence-assessment.md` y `Docs/scenario-4-equivalence.md`.
