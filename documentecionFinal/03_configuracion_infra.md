# Configuración de Infraestructura

> **Fecha:** 2026-05-14  
> **Experimento:** S6 Integrated Dual-Mode  
> **Cluster:** MicroK8s single-node (Ubuntu 20.04, WSL2)

---

## 1. Kubernetes (MicroK8s)

### Cluster

| Parámetro | Valor |
|-----------|-------|
| Distribución | MicroK8s v1.28+ |
| Topología | Single-node (CPU: 8 cores, RAM: 16 GB) |
| Entorno host | Windows 11 + WSL2 Ubuntu 20.04 |
| Registry local | `localhost:32000` (MicroK8s built-in) |
| Add-ons activos | `dns`, `storage`, `registry`, `ingress`, `observability`, `istio`, `linkerd` |

### Namespaces relevantes

| Namespace | Propósito |
|-----------|-----------|
| `mubench-real` | Microservicios del experimento (producción simulada) |
| `realistic` | Namespace legacy (servicios v1) |
| `observability` | Prometheus + Grafana (kube-prom-stack) |
| `istio-system` | Istio control plane |
| `linkerd` | Linkerd control plane |

### Recursos desplegados en `mubench-real`

```
00-namespace.yaml        → Namespace + labels (kubernetes.io/metadata.name: mubench-real)
01-postgres.yaml         → PostgreSQL 14 StatefulSet, Secret (POSTGRES_DB/USER/PASSWORD)
02-postgres-real.yaml    → PostgreSQL v2 con PVC
02-services.yaml         → auth-service, data-service Deployments + Services (NodePort)
03-services-real.yaml    → api-service Deployment + Service
04-servicemonitor.yaml   → ServiceMonitor para Prometheus
05-prometheusrule.yaml   → Alertas PrometheusRule
06-experiment-comparison-rule.yaml → Recording rules para comparación
07-c1-*.yaml             → Ingress variants (NGINX, Istio Gateway, Kong)
08-c3-*.yaml             → NetworkPolicy variants (basic, moderate, strict)
09-access-nodeports.yaml → NodePort exposure para k6 externo
```

### Microservicios

| Servicio | Imagen | Puerto | Función |
|----------|--------|--------|---------|
| auth-service | `localhost:32000/mubench/auth-service:v1` | 8080 | Autenticación JWT (POST /login) |
| api-service | `localhost:32000/mubench/api-service:v1` | 8080 | API de perfil y usuarios (GET /profile, GET /users) |
| data-service | `localhost:32000/mubench/data-service:v1` | 8080 | Capa de datos PostgreSQL |
| postgres | `postgres:14` | 5432 | Base de datos relacional |

#### Readiness probes
Todos los servicios exponen `GET /health` en puerto 8080 con:
- `initialDelaySeconds: 5`
- `periodSeconds: 5`

#### Anotaciones Prometheus (scraping automático)
```yaml
annotations:
  prometheus.io/scrape: "true"
  prometheus.io/port:   "8080"
  prometheus.io/path:   "/metrics"
```

### TLS / Certificados
- Secret: `mubench-tls` (namespace `mubench-real`)
- Host: `real-postgres.local`
- Generado con: `openssl req -x509 -newkey rsa:4096 -keyout tls.key -out tls.crt -days 365 -nodes`
- k6 usa `K6_INSECURE_SKIP_TLS_VERIFY=true` para ignorar el certificado self-signed

---

## 2. k6 (Generador de Carga)

### Versión y instalación
```bash
# scripts/install_k6.sh
K6_VERSION=0.50.0
apt-key adv --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69
apt-get install k6=${K6_VERSION}
```

### Script principal
**Archivo:** `RealisticServices/k6/realistic-flow.js`

#### Variables de entorno configurables

| Variable | Default | Descripción |
|----------|---------|-------------|
| `AUTH_BASE` | `https://localhost/auth` | URL base del auth-service (incluye prefijo de ruta si hay ingress) |
| `API_BASE` | `https://localhost/api` | URL base del api-service |
| `K6_INSECURE_SKIP_TLS_VERIFY` | `true` | Ignorar cert self-signed |
| `HOST_HEADER` | `` | Host header override (ej: `real-postgres.local`) |
| `SECURITY_MODE` | `normal` | `normal` = solo tráfico legítimo; `attack` = legítimo + probes |
| `ATTACK_PROFILE` | `advanced` | `basic` = 2 vectores; `advanced` = 5 vectores (7 probes) |

#### Opciones k6 (`export const options`)
```javascript
thresholds: {
  http_req_failed: SECURITY_MODE === 'attack' ? ['rate<0.80'] : ['rate<0.05'],
  http_req_duration: ['p(95)<700'],
  checks: ['rate>0.95'],
}
```

#### Métricas custom declaradas
```javascript
const loginSuccessTotal      = new Counter('login_success_total');
const loginFailTotal         = new Counter('login_fail_total');
const profileSuccessTotal    = new Counter('profile_success_total');
const usersListSuccessTotal  = new Counter('users_list_success_total');
const jwtIssuedTotal         = new Counter('jwt_issued_total');
const jwtTraceEvents         = new Counter('jwt_trace_events');
const attackBlockedTotal     = new Counter('attack_blocked_total');
const attackVectorAttempts   = new Counter('attack_vector_attempts_total');
const attackVectorBlocked    = new Counter('attack_vector_blocked_total');
const profileDbLatencyMs     = new Trend('profile_db_latency_ms');
const usersDbLatencyMs       = new Trend('users_db_latency_ms');
```

### Perfil de campaña S6

**Archivo:** `scripts/s6-integrated-profile.env`

```bash
S6_CAMPAIGN_ID=s6_integrated_dual_n4
S6_REPLICATES=4
S6_SEED=20260513
S6_WARMUP_SECONDS=30
S6_COOLDOWN_SECONDS=15
S6_DURATION_SECONDS=60
S6_SECURITY_MODES=normal,attack
S6_K6_SCRIPT=RealisticServices/k6/realistic-flow.js
S2_C4_MODERATE_RPM=1200
S2_C4_STRICT_RPM=300
```

### Ejecución de campaña
```bash
# Verificación
bash scripts/verify-s6-integrated-config.sh

# Dry-run (no ejecuta, muestra plan)
bash scripts/run-s6-integrated-repro.sh

# Corrida real
bash scripts/run-s6-integrated-repro.sh --execute
```

### Formato de salida (NDJSON)
Cada corrida genera un archivo `.json` con una línea por evento de métrica:
```json
{"type":"Point","data":{"time":"2026-05-13T19:52:29.942Z","value":9.6394,"tags":{}},"metric":"http_req_duration"}
{"type":"Point","data":{"time":"...","value":56.4,"tags":{}},"metric":"http_reqs"}
```

**Ubicación:** `Testing/results/auto_runs/randomized_campaigns/`  
**Naming:** `{campaign_id}_{block}_{date}_order{n}_{control}_{variant}_{mode}_{vus}vus.json`

---

## 3. Prometheus

### Despliegue
- Stack: `kube-prometheus-stack` (Helm) desplegado en namespace `observability`
- Prometheus v2.47+, Grafana v10+

### Configuración de scraping

#### ServiceMonitor para microservicios
**Archivo:** `RealisticServices/k8s/04-servicemonitor.yaml`
```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: realistic-services
  namespace: monitoring
  labels: {release: prometheus}
spec:
  selector:
    matchExpressions:
      - {key: app, operator: In, values: ["auth-service","api-service","data-service"]}
  namespaceSelector:
    matchNames: [realistic]
  endpoints:
    - port: http
      path: /metrics
      interval: 10s
```

#### Scrape interval
- Servicios de aplicación: `10s`
- node-exporter / cAdvisor: `15s` (default kube-prom-stack)

### Métricas expuestas por los microservicios
```
mubench_http_requests_total{service, status, method}
mubench_http_request_duration_seconds_bucket{service, le}
mubench_db_query_duration_seconds_bucket{query_name, le}
```

### Alertas configuradas
**Archivo:** `RealisticServices/k8s/05-prometheusrule.yaml`

| Alerta | Condición | Severidad |
|--------|-----------|-----------|
| `RealisticHighErrorRate` | `error_rate > 5%` por 5 min | warning |
| `RealisticHighP95Latency` | `P95 > 400ms` por 5 min | warning |
| `RealisticSlowDbQueryP95` | `DB P95 > 200ms` por 5 min | warning |

### Queries PromQL para métricas de recursos
```promql
# CPU total del namespace mubench-real (millicores)
sum(rate(container_cpu_usage_seconds_total{namespace="mubench-real"}[1m])) * 1000

# Memoria RSS total (MiB)
sum(container_memory_rss{namespace="mubench-real"}) / 1024 / 1024

# Tasa de error HTTP
rate(mubench_http_requests_total{status=~"5.."}[5m]) /
clamp_min(rate(mubench_http_requests_total[5m]), 0.001)
```

---

## 4. Grafana

### Despliegue
- Incluido en `kube-prometheus-stack` (mismo namespace `observability`)
- Acceso: `http://localhost:3000` (port-forward) o NodePort asignado
- Credenciales default: `admin / prom-operator`

### Dashboard personalizado
**Archivo:** `Monitoring/mubench-dashboard.json`

#### Paneles incluidos
| Panel | Métrica visualizada | Tipo |
|-------|-------------------|------|
| Request Rate (rps) | `rate(http_reqs[1m])` | Time series |
| P95 Latency | `histogram_quantile(0.95, ...)` | Time series |
| Error Rate | `rate(http_req_failed[1m])` | Time series |
| CPU per Service | `rate(container_cpu_usage_seconds_total{...}[1m])` | Time series |
| Memory per Service | `container_memory_rss{...}` | Time series |
| DB Query P95 | `histogram_quantile(0.95, mubench_db_...)` | Time series |

#### Variables de template del dashboard
```
$namespace   → mubench-real | realistic
$service     → auth-service | api-service | data-service | All
$interval    → 1m | 5m | 10m
```

### Importar dashboard
```bash
# Via Grafana API (genera token primero)
curl -X POST http://admin:prom-operator@localhost:3000/api/dashboards/import \
  -H "Content-Type: application/json" \
  -d @Monitoring/mubench-dashboard.json

# Script automatizado
bash RealisticServices/publish-grafana-dashboard.sh
```

### Anotaciones de experimento
Durante la campaña S6, el script de orchestration inserta anotaciones en Grafana marcando inicio/fin de cada variante de control. Esto permite correlacionar visualmente el cambio de configuración con las métricas en tiempo real.

---

## 5. Pipeline de Análisis Post-Corrida

```
NDJSON files (385+)
       ↓
Testing/extract_clean_metrics.py
       → s6_integrated_clean_metrics.csv (384 rows, 6 métricas + derivadas)
       ↓
Testing/s6_statistical_analysis_rigorous.py
       → Testing/results/s6_analysis_rigorous/
           ├── S6_INTEGRATED_STATISTICAL_REPORT.md
           ├── threat_model_matrix.csv
           ├── threat_model_visualization.png
           └── diagnostic_plots_*.png (7 métricas × 4 plots)
```
