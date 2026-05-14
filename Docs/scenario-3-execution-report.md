# Escenario 3 - Ejecución y Resultados Iniciales

## Estado de despliegue
- Namespace: mubench-advanced
- Pipeline usado: ServiceGraphGenerator -> WorkModelGenerator -> K8sDeployer
- Script: scripts/setup-scenario3-mubench-advanced.sh
- Smoke test gateway: OK (HTTP 200 en /s0)

## Configuración aplicada
- DNS resolver corregido a kube-dns.kube-system.svc.cluster.local
- Topología avanzada: 8 servicios + 1 servicio de base (sdb1)
- Réplicas reducidas a 1 por servicio para estabilidad en el cluster local

## Benchmark de escalado del escenario 3
Script ejecutado: scripts/run-scaling-scenario3.sh
Reporte generado: Testing/results/scaling_tests/scaling-report_mubench-advanced_20260509.csv

Nota metodológica aplicada:
- Se corrigió el cálculo de RPS para usar la duración real del test (no valor fijo de 60s).
- El benchmark quedó parametrizable (`BENCH_PROFILE`, `TARGET_URLS`, `THINK_TIME`) manteniendo por defecto el comportamiento nativo del escenario 3.
- Estos cambios son de validez de medición, no de "simulación" de equivalencia funcional con escenarios 1/2.

Resultados:
- VU=1: avg=209.00ms, p95=263.30ms, err=0.00%, rps=3.23, cpu=2202m, mem=9594MiB
- VU=5: avg=773.26ms, p95=1073.44ms, err=0.58%, rps=5.73, cpu=3521m, mem=9768MiB
- VU=10: avg=1649.90ms, p95=2397.45ms, err=1.74%, rps=5.75, cpu=3338m, mem=9854MiB
- VU=20: avg=3705.92ms, p95=5521.59ms, err=12.38%, rps=5.38, cpu=3366m, mem=9931MiB

## Observaciones
- El escenario 3 tiene una carga interna más pesada por diseño (workmodel avanzado), por eso la latencia y consumo son significativamente más altos.
- Es útil para representar condiciones exigentes de cómputo interno, no para comparar latencia absoluta con escenario 1/2 sin normalización.

## Matriz completa C1-C4 sobre escenario 3 (equivalencia operativa)
- Script ejecutado: `scripts/run-scaling-scenario3-controls.sh`
- Resultado completo (48 filas = 12 variantes x 4 VUs):
	- `Testing/results/scaling_tests/scaling-report_mubench-advanced-controls_20260509_174026.csv`
- Resumen agregado por control/variante:
	- `Testing/results/scaling_tests/scaling-report_mubench-advanced-controls_20260509_174026_summary.csv`

Estado de ejecución:
- C1 baseline/istio/kong: ejecutables en este cluster.
- C2 baseline/istio-mtls/linkerd-mtls: ejecutables en este cluster.
- C3 baseline/basic/strict: ejecutables en este cluster.
- C4 baseline/moderate/strict: ejecutables en este cluster, implementado sobre gateway `gw-nginx`.

Justificación técnica relevante:
- En C2 istio-mtls se requirió excepción controlada para `gw-nginx` (PeerAuthentication PERMISSIVE) para permitir entrada HTTP externa de benchmark, manteniendo mTLS STRICT en el resto.
- En C4, al no existir `api-service` en escenario 3, se implementó rate limit equivalente en NGINX gateway (no por variable de entorno de aplicación como en escenarios 1/2).
