# Escenario 2 - Configuración Completa (Postgres Real + Servicios Realistas)

## 1. Objetivo del escenario
Crear un entorno paralelo al experimento original para evaluar los mismos controles C1-C4 y las 6 métricas acordadas, pero usando una base de datos Postgres real (persistencia y operaciones reales), sin afectar el escenario original.

## 2. Aislamiento del entorno
- Namespace dedicado: `mubench-real`
- Escenario original intacto en su namespace original
- Servicios paralelos con NodePorts propios
- Manifiestos de controles duplicados/adaptados para `mubench-real`

## 3. Componentes desplegados

### 3.1 Base de datos Postgres
Archivo: `RealisticServices/k8s/02-postgres-real.yaml`

Incluye:
- `Namespace`: `mubench-real`
- `Secret`: `postgres-secret`
  - `POSTGRES_USER=mubench`
  - `POSTGRES_PASSWORD=mubench`
  - `POSTGRES_DB=mubench_real`
- `ConfigMap`: `postgres-init`
  - tabla `app_users`
  - índice `idx_app_users_created_at`
  - seed de 10,000 usuarios (`user_1 ... user_10000`)
- `Deployment`: `postgres` (imagen `postgres:15`)
- `Service`: `postgres` puerto 5432

### 3.2 Microservicios realistas (paralelos)
Archivo: `RealisticServices/k8s/03-services-real.yaml`

Servicios:
- `auth-service`
- `api-service`
- `data-service`

Conectividad DB:
- `data-service` usa `DB_HOST=postgres` y credenciales desde `postgres-secret`

NodePorts de escenario 2:
- `api-service`: `30181`
- `data-service`: `30182`
- `auth-service`: `30184`

## 4. Controles experimentales adaptados a `mubench-real`

### C1 API Gateway
- Baseline (NGINX ingress): `RealisticServices/k8s/07-c1-ingress-gateway-real.yaml`
- Istio: `RealisticServices/k8s/07-c1-istio-real.yaml`
- Kong: `RealisticServices/k8s/07-c1-kong-real.yaml`

Detalles importantes C1/Istio:
- Se añadió servidor HTTP en el Gateway para estabilidad local
- En benchmark se usa `port-forward` automático temporal para Istio

### C2 mTLS
- Istio mTLS real: `RealisticServices/k8s/02-services-istio-mtls-real.yaml`
- Linkerd mTLS real: `RealisticServices/k8s/02-services-linkerd-mtls-real.yaml`

### C3 Network Policies
- Basic: `RealisticServices/k8s/08-c3-networkpolicy-real.yaml`
- Strict: `RealisticServices/k8s/08-c3-networkpolicy-strict-real.yaml`

### C4 Rate Limiting
Se aplica por variables en `api-service` dentro de `mubench-real`:
- moderate: `RATE_LIMIT_ENABLED=true`, `RATE_LIMIT_RPM=120`
- strict: `RATE_LIMIT_ENABLED=true`, `RATE_LIMIT_RPM=20`

## 5. Scripts creados/ajustados para escenario 2

### 5.1 Setup y validación
- `scripts/setup-postgres-real-scenario.sh`
  - despliega Postgres real + servicios paralelos
- `scripts/validate-postgres-real-scenario.sh`
  - health checks
  - login JWT
  - lectura/escritura (`/users`)
  - conteo directo SQL en Postgres
  - carga corta k6

### 5.2 Runner de benchmark
- `scripts/run-k6-benchmark.sh`
  - nuevo flag `--target-env default|postgres-real`
  - endpoints específicos por control/variante en `postgres-real`
  - fix de parsing de métricas finales desde JSONL Points
  - soporte automático de port-forward para C1/istio en `postgres-real`

### 5.3 Campaña de escalado
- `scripts/run-scaling-tests.sh`
  - soporte `TARGET_ENV=postgres-real`
  - namespace dinámico (`SCENARIO_NAMESPACE`)
  - helper `kctl` (`microk8s kubectl` o `kubectl`)
  - clonación automática de secretos TLS al namespace objetivo cuando se requieren
  - apply/reset de manifiestos del escenario 2 para C1/C2/C3
  - reporte separado: `scaling-report_postgres-real_YYYYMMDD.csv`

## 6. Métricas evaluadas (6/6)
Columnas del reporte:
1. `avg_ms`
2. `p95_ms`
3. `err_pct`
4. `rps`
5. `cpu_mcores`
6. `mem_mib`

## 7. Validación de integridad ejecutada
Reporte validado:
- `Testing/results/scaling_tests/scaling-report_postgres-real_20260509.csv`

Chequeos finales:
- 48 filas válidas (12 pares control/variante x 4 VUs)
- Cobertura completa en VUs `{1,5,10,20}` para todos los pares
- Sin métricas faltantes ni no numéricas
- C1/istio corregido (sin 100% error)
- C4/strict conserva error alto esperado por diseño (rate limiting)

## 8. Comandos operativos principales

Despliegue escenario 2:
```bash
kubectl apply -f RealisticServices/k8s/02-postgres-real.yaml
kubectl apply -f RealisticServices/k8s/03-services-real.yaml
```

Setup automático:
```bash
bash scripts/setup-postgres-real-scenario.sh
```

Validación funcional completa:
```bash
bash scripts/validate-postgres-real-scenario.sh
```

Campaña completa 12x4 sobre escenario 2:
```bash
TARGET_ENV=postgres-real bash scripts/run-scaling-tests.sh
```

## 9. Estado de salida del escenario 2
- Escenario operativo y estable
- Comparable con escenario 1
- Listo para comparación formal previa a escenario 3
