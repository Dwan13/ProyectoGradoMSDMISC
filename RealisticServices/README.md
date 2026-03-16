# RealisticServices (Auth + API + Postgres)

Este módulo inicia una base de microservicios más realista para muBench:

- `auth-service`: emite JWT en `POST /login`
- `api-service`: valida JWT y consulta `data-service`
- `data-service`: lee usuarios desde Postgres
- `postgres`: base de datos con datos semilla

## Flujo funcional

1. Cliente hace login en `auth-service`.
2. `auth-service` devuelve bearer token.
3. Cliente llama `api-service /profile` con token.
4. `api-service` valida token y consulta `data-service`.
5. `data-service` consulta Postgres y devuelve perfil.

## Requisitos

- MicroK8s activo
- Docker activo (para build/push al registry local de MicroK8s)

## Deploy rápido

```bash
cd RealisticServices
chmod +x deploy-realistic.sh k8s/03-smoke-test.sh
./deploy-realistic.sh
./k8s/03-smoke-test.sh
```

El deploy también:

- aplica `k8s/04-servicemonitor.yaml` para scrape de Prometheus,
- aplica `k8s/05-prometheusrule.yaml` con alertas base (error rate, P95 HTTP, P95 DB),
- publica dashboard nativo de Grafana con métricas en tiempo real.

Dashboard esperado:

- `http://localhost:3000/d/mubench-realistic-observability/mubench-realistic-services-realtime`

## Carga k6 realista

```bash
cd RealisticServices
chmod +x run-k6-realistic.sh
./run-k6-realistic.sh
```

Variables opcionales:

- `AUTH_BASE` (default `http://127.0.0.1:18082`)
- `API_BASE` (default `http://127.0.0.1:30081`)

## Carga k6: crear muchos usuarios y luego listar

Script dedicado para poblar usuarios de forma masiva (`POST /users`) y despues ejecutar listados (`GET /users`).

```bash
cd RealisticServices
chmod +x run-k6-users-bulk.sh
./run-k6-users-bulk.sh
```

Variables utiles:

- `CREATE_VUS` (default `15`)
- `CREATE_DURATION` (default `45s`)
- `LIST_START` (default `50s`)
- `LIST_VUS` (default `5`)
- `LIST_DURATION` (default `25s`)
- `LIST_LIMIT` (default `100`)

## Controles C1-C4 sobre micros realistas

Se incluyeron scripts para activar/desactivar controles sobre `auth/api/data`:

- `controls/apply-control.sh baseline|c1|c2|c3|c4`
- `run-controls-realistic.sh` (ejecuta benchmark comparativo de controles)

Mapeo de controles:

- `C1` API Gateway: Ingress NGINX (`k8s/07-c1-ingress-gateway.yaml`)
- `C2` mTLS mesh: activación condicional si Linkerd existe
- `C3` Network Policies: segmentación (`k8s/08-c3-networkpolicy.yaml`)
- `C4` Rate limiting: limiter en `api-service` via env vars

Ejemplo rápido:

```bash
cd RealisticServices
chmod +x controls/apply-control.sh run-controls-realistic.sh
./run-controls-realistic.sh
```

## Endpoints

- Auth (port-forward): `http://127.0.0.1:18082/login`
- API (NodePort): `http://127.0.0.1:30081/profile?user_id=1`

## Nota

El deployment de Postgres usa `emptyDir` (no persistente) para iteración rápida. Si quieres persistencia real, el siguiente paso es migrar a PVC/StorageClass.

## Runbook

Guia completa de replicacion paso a paso:

- `RUNBOOK_REPRODUCIBILIDAD.md`
- `RUNBOOK_ACADEMICO_METODO_EXPERIMENTAL.md`
- `CHECKLIST_VALIDACION_RAPIDA.md`
- `QUICKSTART_1PAGINA.md`

## Documento academico (IEEE/ACM)

Marco formal para argumentar C1-C4 como seguridad defensiva con trade-off seguridad-rendimiento:

- `SECURITY_DEFENSIVE_ARGUMENT_IEEE_ACM.md`

Version en espanol academico:

- `ARGUMENTO_SEGURIDAD_DEFENSIVA_ES.md`

Mapeo de controles C1-C4 con marcos de referencia:

- `MAPEO_C1_C4_CSA_CCM_NIST.md`
