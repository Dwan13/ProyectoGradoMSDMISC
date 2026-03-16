# Control 3: Network Policies (Segmentacion)

Este control evalua el overhead de politicas de red y la efectividad del bloqueo lateral.

Escenarios:
- E1: Baseline sin NetworkPolicies
- E2: NetworkPolicies estrictas (allow-list)

## Estrategia segura (anti-congelamiento)

- Ejecucion en background con logs a archivo.
- Carga reducida: 5, 10, 20 VUs.
- Duracion corta: 60s por corrida.
- Cooldown: 20s.
- Endpoint estable via port-forward: http://localhost:30100/process

## Comandos principales

- Baseline: bash run-control3-safe.sh --scenario baseline
- Policies: bash run-control3-safe.sh --scenario policies
- Autopilot: bash run-control3-autopilot-safe.sh
- Monitor: bash monitor-control3.sh
- Analisis: python3 analysis/analyze-netpol-results.py --results-dir results --output-dir analysis/output-final
