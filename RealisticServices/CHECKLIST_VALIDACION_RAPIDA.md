# Checklist Imprimible de Validacion Rapida

## Preparacion
- [ ] Estoy en /home/dwan13/muBench
- [ ] docker --version responde OK
- [ ] microk8s status --wait-ready responde OK
- [ ] k6 version responde OK

## Script Principal Actualizado
- [ ] ./scripts/deploy_microk8s.sh --help muestra --hybrid
- [ ] ./scripts/deploy_microk8s.sh --help muestra --hybrid-quick
- [ ] ./scripts/deploy_microk8s.sh --help muestra --hybrid-stress
- [ ] ./scripts/deploy_microk8s.sh --help muestra --hybrid-controls

## Corrida Recomendada (sanity)
- [ ] Ejecute: ./scripts/deploy_microk8s.sh --start --hybrid-quick
- [ ] El proceso termino sin error fatal

## Evidencia de Carga Realista
- [ ] Existe RealisticServices/results/k6-users-bulk-*.json
- [ ] Existe RealisticServices/results/hybrid-k6-summary-*.txt
- [ ] El summary tiene users_created_total
- [ ] El summary tiene users_listed_total
- [ ] El summary tiene http_req_duration_p95_ms
- [ ] El summary tiene http_req_failed_rate

## Dashboards
- [ ] Abre Grafana: http://localhost:3000
- [ ] Dashboard realtime disponible
- [ ] Dashboard comparativo disponible
- [ ] Panel "Resumen Hibrido k6 (Auto)" visible

## Validacion Funcional API
- [ ] Login OK en auth-service
- [ ] GET /users OK con token
- [ ] POST /users OK con token

## Persistencia Basica
- [ ] SELECT COUNT(*) FROM app_users ejecuta OK
- [ ] El conteo aumenta despues de corridas de carga

## Consolidado Final
- [ ] Testing/results/all-controls-comparison.csv existe
- [ ] Testing/results/all-controls-p95.png existe
- [ ] Testing/results/all-controls-avg-vus.png existe
- [ ] ~/.mubench_credentials fue generado/actualizado
