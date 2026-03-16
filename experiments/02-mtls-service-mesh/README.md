# Control 2: mTLS Service Mesh (Istio vs Linkerd)

Este experimento mide el overhead de mTLS en trafico este-oeste entre microservicios, evitando congelamientos en entorno visual con una estrategia de ejecucion segura.

## Objetivo

Comparar:
- E1 Baseline HTTP sin mesh
- E2 Istio con mTLS strict
- E3 Linkerd con mTLS automatico

Metricas principales:
- Latencia avg, p95, p99
- Throughput
- Error rate
- Consumo de CPU/Memoria de sidecars (via Prometheus)

## Estrategia Anti-Congelamiento

1. Ejecutar siempre en background con logs a archivo.
2. Usar carga baja-media: 5, 10, 20 VUs.
3. Usar duracion corta: 60s por corrida.
4. Cooldown entre corridas: 20s.
5. Nunca ejecutar loops largos en terminal interactiva.

## Estructura

- baseline/run-baseline-safe.sh
- istio/install-istio-safe.sh
- istio/enable-mtls-strict.sh
- linkerd/install-linkerd-safe.sh
- tests/test-mtls-baseline.js
- tests/test-istio-mtls.js
- tests/test-linkerd-mtls.js
- analysis/analyze-mtls-results.py
- run-control2-safe.sh
- run-control2-autopilot-safe.sh
- monitor-control2.sh

## Requisitos

- MicroK8s activo
- Servicios s0, s1, sdb1 en Running
- k6 instalado
- Python3 con pandas y matplotlib

## Ejecucion Segura Recomendada

Desde la carpeta del control:

bash run-control2-safe.sh --scenario baseline
bash run-control2-safe.sh --scenario istio
bash run-control2-safe.sh --scenario linkerd
python3 analysis/analyze-mtls-results.py --results-dir results --output-dir analysis/output

Cada comando deja logs en results/logs para inspeccion posterior sin sobrecargar la sesion.

## Autopilot (secuencial y resiliente)

Este modo espera ejecuciones activas, reanuda escenarios faltantes y ejecuta analisis al final:

bash run-control2-autopilot-safe.sh

Monitoreo rapido:

bash monitor-control2.sh
