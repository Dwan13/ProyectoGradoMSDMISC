# Control 4: Rate Limiting

Este control mide el impacto de rate limiting para proteger disponibilidad y backend.

## Criterio Tecnico

Este control NO requiere Istio/Linkerd como criterio principal.
Se implementa en el borde (ingress/gateway), donde se materializan AIS-08 e I&S-09 para trafico norte-sur.

- E1 Baseline: acceso directo por port-forward sin limite.
- E2 Rate Limiting: NGINX Ingress con limite por segundo y burst.

Istio/Linkerd pueden implementar politicas de trafico, pero eso corresponde mas a control de malla (Control 2). Aqui el objetivo es defensa perimetral y continuidad (BCR-03).

## Estrategia segura

- Corridas en background con logs.
- VUs: 10, 25, 50
- Duracion: 60s
- Cooldown: 20s
- Endpoint baseline: http://localhost:30200/process
- Endpoint RL: http://localhost:30080/rl-s0/process

## Flujo

- bash run-control4-safe.sh --scenario baseline
- bash run-control4-safe.sh --scenario ratelimit
- bash run-control4-autopilot-safe.sh
- bash monitor-control4.sh
- python3 analysis/analyze-rl-results.py --results-dir results --output-dir analysis/output-final
