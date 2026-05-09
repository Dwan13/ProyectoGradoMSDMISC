# µBench - Guía Técnica Completa de Configuración y Ejecución

**Documento de referencia para replicar el setup experimental de µBench en cualquier máquina**

Versión: 1.0 | Actualizado: 2026-05-09 | Autor: Setup Automation

---

## 📋 Tabla de Contenidos

1. [Visión General](#visión-general)
2. [Requisitos de Hardware](#requisitos-de-hardware)
3. [Setup Inicial (Máquina Nueva)](#setup-inicial)
4. [Arquitectura del Cluster](#arquitectura-del-cluster)
5. [Servicios Realistas](#servicios-realistas)
6. [Escenarios de Control (C1-C4)](#escenarios-de-control)
7. [Generación de Carga (k6)](#generación-de-carga)
8. [Monitoreo y Métricas](#monitoreo-y-métricas)
9. [Ejecución de Experimentos](#ejecución-de-experimentos)
10. [Troubleshooting](#troubleshooting)
11. [Resultados y Análisis](#resultados-y-análisis)

---

## 🎯 Visión General

µBench es una plataforma de benchmarking para microservicios que permite:

- **Desplegar servicios realistas** en Kubernetes (MicroK8s)
- **Aplicar diferentes controles de seguridad/rendimiento**:
  - **C1**: API Gateways (Ingress NGINX, Istio Gateway, Kong)
  - **C2**: Service Mesh mTLS (Istio, Linkerd)
  - **C3**: Network Policies (básicas y estrictas)
  - **C4**: Rate Limiting (moderate, strict)
- **Ejecutar tests de carga** con k6
- **Recolectar métricas** de rendimiento (latencia, throughput, CPU, memoria)
- **Analizar overhead** de cada control

### Flujo Experimental Base

```
Setup Cluster → Deploy Servicios → Aplicar Control → Smoke Test → k6 Benchmark → Recopilar Métricas → Análisis
```

---

## 🖥️ Requisitos de Hardware

### Mínimo (tests básicos con 1 VU):
- **CPU**: 4+ cores
- **RAM**: 8GB+
- **Almacenamiento**: 50GB SSD
- **OS**: Linux nativo, WSL2, o macOS con Docker Desktop

### Recomendado (escalamiento a 5-20 VUs):
- **CPU**: 8+ cores (Ryzen 5 3600 o equivalente)
- **RAM**: 16GB+ (MicroK8s 6-12GB, rest del sistema)
- **Almacenamiento**: 100GB SSD
- **Conexión**: 1Gbps (para evitar bottlenecks de red)

### Configuración Verificada
```
Nombre de dispositivo: FelipePC
Procesador: AMD Ryzen 5 3600 6-Core Processor (3.59 GHz)
RAM: 16 GB
OS: Windows 10/11 con WSL2
WSL2 Config: memory=12GB, processors=6, swap=4GB
```

### ⚠️ Nota sobre WSL2

Si usas WSL2, crea o modifica `C:\Users\<TuUsuario>\.wslconfig`:

```ini
[wsl2]
memory=12GB
processors=6
swap=4GB
localhostForwarding=true
```

Luego reinicia WSL:
```powershell
wsl --shutdown
wsl
```

Verifica la configuración:
```bash
nproc                    # Debe mostrar 6
free -h                  # Debe mostrar ~12GB
```

---

## 🚀 Setup Inicial

### 1. Clonar Repositorio

```bash
git clone https://github.com/yourusername/muBench.git
cd muBench
```

### 2. Ejecutar Setup Automático (Recomendado)

Para máquina nueva, ejecuta:

```bash
bash scripts/full-project-setup.sh
```

Este script:
- ✓ Verifica Prerequisites (Docker, Python, curl, jq)
- ✓ Instala/levanta MicroK8s
- ✓ Habilita add-ons (DNS, storage, ingress)
- ✓ Instala Prometheus + Grafana (opcional)
- ✓ Instala Istio (opcional)
- ✓ Construye imágenes Docker
- ✓ Despliega servicios realistas
- ✓ Instala k6
- ✓ Crea directorios de resultados

**Tiempo estimado**: 15-30 minutos

### 3. Setup Manual (si requieres control fino)

#### Paso 3a: Instalar MicroK8s

```bash
# Linux
sudo snap install microk8s --classic --channel=1.28/stable
sudo usermod -a -G microk8s $USER
# Reinicia la sesión o ejecuta: newgrp microk8s

# Esperar que esté ready
microk8s status --wait-ready --timeout=600
```

#### Paso 3b: Habilitar Add-ons Esenciales

```bash
microk8s enable dns
microk8s enable storage
microk8s enable ingress
microk8s enable prometheus  # Para monitoreo
```

#### Paso 3c: Instalar/Habilitar Istio (para C1 istio y C2 mTLS)

```bash
microk8s enable istio
microk8s kubectl wait --for=condition=available --timeout=300s \
  deployment/istiod -n istio-system
```

#### Paso 3d: Crear Certificado TLS

```bash
# Generar certificado autofirmado
openssl req -x509 -newkey rsa:4096 -keyout /tmp/tls.key -out /tmp/tls.crt \
  -days 365 -nodes -subj "/CN=realistic.local"

# Crear secret en istio-system
microk8s kubectl create secret tls mubench-tls -n istio-system \
  --cert=/tmp/tls.crt --key=/tmp/tls.key

# Verificar
microk8s kubectl get secret mubench-tls -n istio-system
```

#### Paso 3e: Construir Imágenes Docker

```bash
# Usar Docker del host (MicroK8s integrado)
eval "$(microk8s docker-env)"

cd muBench/RealisticServices

# Auth Service
docker build -t mubench/auth-service:latest auth-service/

# API Service
docker build -t mubench/api-service:latest api-service/

# Data Service
docker build -t mubench/data-service:latest data-service/
```

#### Paso 3f: Desplegar Servicios Base

```bash
microk8s kubectl create namespace realistic --dry-run=client -o yaml | \
  microk8s kubectl apply -f -

microk8s kubectl apply -f RealisticServices/k8s/02-services.yaml -n realistic

# Esperar que estén ready
microk8s kubectl rollout status deployment/auth-service -n realistic --timeout=300s
microk8s kubectl rollout status deployment/api-service -n realistic --timeout=300s
microk8s kubectl rollout status deployment/data-service -n realistic --timeout=300s
```

#### Paso 3g: Instalar k6

```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install -y gnupg software-properties-common
sudo add-apt-repository "deb https://dl.k6.io/deb releases main"
sudo apt-get update && sudo apt-get install -y k6

# macOS
brew install k6

# Verificar
k6 version
```

---

## 🏗️ Arquitectura del Cluster

### Namespaces

```
Cluster MicroK8s
├── realistic (Servicios bajo test)
│   ├── auth-service (Deployment + Service NodePort 30084)
│   ├── api-service (Deployment + Service NodePort 30081)
│   ├── data-service (Deployment + Service NodePort 30082)
│   └── postgres (StatefulSet para datos)
│
├── istio-system (Service Mesh, si está habilitado)
│   ├── istiod
│   ├── ingressgateway
│   └── mubench-tls (Secret con certificado)
│
├── monitoring (Prometheus, Grafana)
│   ├── prometheus
│   └── grafana
│
└── default (Sistema)
```

### Topología de Servicios

```
┌─────────────────────────────────────────────┐
│         Cliente k6 (Load Generator)         │
└────────────────────┬────────────────────────┘
                     │
        ┌────────────┼────────────┐
        │            │            │
   (C1: Gateway) (C2/C3/C4: mTLS / NetPol)
        │            │            │
    Ingress/      NodePorts    NodePorts
   Istio GW/        HTTP         HTTP
    Kong            30084        30081
    (HTTPS)         (Auth)       (API)
        │            │            │
        └────┬───────┴────────────┘
             │
    ┌────────▼─────────┐
    │   auth-service   │ ──┐
    │   api-service    │   ├──> PostgreSQL
    │   data-service   │ ──┘
    └──────────────────┘
```

### Flujo de Tráfico por Control

**C1 (API Gateway):**
```
k6 → Ingress/Gateway (HTTPS:30997 o Kong:30443) → Services
```

**C2/C3/C4:**
```
k6 → Services NodePorts (HTTP:30084, 30081, 30082)
     ↓
   [mTLS sidecars / Network Policies / Rate Limiter]
     ↓
   Service-to-service communication
```

---

## 🔧 Servicios Realistas

### Estructura de Código

```
RealisticServices/
├── auth-service/          # Servicio de autenticación
│   ├── Dockerfile
│   ├── app.py             # Flask app
│   ├── requirements.txt
│   └── Gunicorn config
│
├── api-service/           # API principal
│   ├── Dockerfile
│   ├── app.py             # Flask app con /profile, /login
│   ├── requirements.txt
│   └── rate_limiter.py    # Implementación de rate limit
│
├── data-service/          # Servicio de datos
│   ├── Dockerfile
│   └── ...
│
├── k6/                    # Scripts de carga
│   ├── realistic-flow.js  # Flujo de prueba (login + get profile)
│   └── ...
│
└── k8s/                   # Manifiestos Kubernetes
    ├── 02-services.yaml      # Deployments base
    ├── 07-c1-ingress-gateway.yaml
    └── 08-c3-networkpolicy.yaml
```

### Endpoints por Servicio

| Servicio | NodePort | Endpoint | Propósito |
|----------|----------|----------|-----------|
| auth-service | 30084 | POST /login | Obtener JWT |
| api-service | 30081 | GET /profile | Acceso autorizado |
| data-service | 30082 | GET /users | Datos backend |
| PostgreSQL | 5432 | - | Persistencia |

### Flujo de Autenticación

```
1. Cliente → POST /login (auth-service)
   Credenciales: {username: "demo", password: "demo123"}
   Response: {access_token: "jwt_token"}

2. Cliente → GET /profile?user_id=1 (api-service)
   Header: Authorization: Bearer <jwt_token>
   Response: {user: {id: 1, name: "Demo User", ...}}

3. api-service → GET /users/1 (data-service)
   [Transparente al cliente]
```

---

## 🎛️ Escenarios de Control (C1-C4)

### C1: API Gateways (Ingress Layer)

**Objetivo**: Comparar overhead de diferentes tipos de gateways

**Variantes**:

1. **C1 baseline**: NGINX Ingress (HTTP/HTTPS)
   ```yaml
   kind: Ingress
   metadata:
     name: realistic-ingress
   spec:
     ingressClassName: nginx
     rules:
     - host: localhost
       http:
         paths:
         - path: /auth
           pathType: Prefix
           backend:
             service:
               name: auth-service
               port: 8080
   ```
   - Endpoint: `https://localhost/auth` y `https://localhost/api`
   - TLS: Habilitado
   - Host Header: Requerido
   - Puerto: 443 (remapeado a 30997 vía ingress)

2. **C1 istio**: Istio Gateway + VirtualService
   ```yaml
   apiVersion: networking.istio.io/v1beta1
   kind: Gateway
   metadata:
     name: realistic-gateway
   spec:
     selector:
       istio: ingressgateway
     servers:
     - port:
         number: 443
         name: https
         protocol: HTTPS
       tls:
         mode: SIMPLE
         credentialName: mubench-tls
       hosts:
       - "*"
   ---
   apiVersion: networking.istio.io/v1beta1
   kind: VirtualService
   metadata:
     name: realistic-vs
   spec:
     hosts:
     - "*"
     gateways:
     - realistic-gateway
     http:
     - match:
       - uri:
           prefix: /login
         route:
         - destination:
             host: auth-service
             port:
               number: 8080
     - match:
       - uri:
           prefix: /profile
         route:
         - destination:
             host: api-service
             port:
               number: 8080
   ```
   - Endpoint: `https://localhost:30997`
   - Host Header: `realistic.local`
   - Overhead: Envoy proxy en Ingress Gateway (+latencia)

3. **C1 kong**: Kong Ingress
   ```yaml
   apiVersion: networking.k8s.io/v1
   kind: Ingress
   metadata:
     name: kong-realistic-ingress
     annotations:
       kubernetes.io/ingress.class: kong
       konghq.com/protocols: "https"
       konghq.com/strip-path: "false"
   spec:
     tls:
     - secretName: mubench-tls
     rules:
     - host: localhost
       http:
         paths:
         - path: /
           pathType: Prefix
           backend:
             service:
               name: auth-service
               port:
                 number: 8080
   ```
   - Endpoint: `https://localhost:30443`
   - Host Header: `localhost`
   - Características: API Gateway full-featured

**Directorio de manifiestos**: `experiments/01-api-gateway-realistic/`

---

### C2: Service Mesh mTLS

**Objetivo**: Medir overhead de mutual TLS entre servicios

**Variantes**:

1. **C2 baseline**: Sin service mesh
   ```bash
   kubectl label namespace realistic istio-injection=disabled
   ```
   - Comunicación service-to-service: HTTP sin encripción
   - Latencia: ~16ms (p95)
   - CPU: ~70mC
   - Memoria: ~193MiB

2. **C2 istio-mtls**: Istio con sidecar injection automática
   ```bash
   kubectl label namespace realistic istio-injection=enabled
   
   # Cada pod recibe sidecar Envoy
   # mTLS automático para service-to-service
   ```
   - Comunicación: HTTP→HTTPS (Envoy termina TLS)
   - Latencia: ~22.5ms (p95) → **+40% overhead**
   - CPU: ~108mC (+54% vs baseline)
   - Memoria: ~291MiB (+51% vs baseline)
   - Causa: Proxy Envoy + certificado validation

3. **C2 linkerd-mtls**: Linkerd service mesh
   ```bash
   # Habilitar Linkerd (si está instalado)
   microk8s enable linkerd  # (opcional)
   
   # Inyectar proxy Linkerd
   kubectl annotate pod -n realistic --all \
     linkerd.io/inject=enabled --overwrite
   ```
   - Proxy: Linkerd (más ligero que Envoy)
   - Latencia: ~19.77ms (p95) → **+24% overhead**
   - CPU: ~89mC (+28% vs baseline)
   - Memoria: ~220MiB (+15% vs baseline)
   - Ventaja: Overhead menor que Istio

**Directorio de manifiestos**: `experiments/02-mtls-service-mesh-realistic/`

**Configuración de Istio mTLS**:
```yaml
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
spec:
  mtls:
    mode: STRICT  # Requiere mTLS
```

---

### C3: Network Policies

**Objetivo**: Evaluar impacto de restricciones de tráfico de red

**Variantes**:

1. **C3 baseline**: Sin network policies
   - Tráfico: Any-to-any permitido
   - Latencia: ~17.23ms
   - CPU: ~75mC

2. **C3 basic**: Network policies permisivas
   ```yaml
   apiVersion: networking.k8s.io/v1
   kind: NetworkPolicy
   metadata:
     name: api-service-policy
   spec:
     podSelector:
       matchLabels:
         app: api-service
     policyTypes:
     - Ingress
     - Egress
     ingress:
     - from:
       - podSelector:
           matchLabels:
             app: api-service
     egress:
     - to:
       - podSelector:
           matchLabels:
             app: data-service
     - to:
       - podSelector:
           matchLabels:
             k8s-app: kube-dns
       ports:
       - protocol: UDP
         port: 53
   ```
   - Latencia: ~20.05ms (p95) → **+16% overhead**
   - CPU: ~53mC (-29% vs baseline) ← Menos datos procesados
   - Overhead: Mínimo (policy evaluation en kernel)

3. **C3 strict**: Network policies restrictivas
   ```yaml
   # Solo permite:
   # - Auth ↔ API
   # - API ↔ Data
   # Bloquea todo lo demás
   ```
   - Latencia: ~18.13ms (similar a baseline)
   - CPU: ~54mC
   - Conclusión: Network policies tienen **impacto insignificante** en latencia

**Directorio de manifiestos**: `experiments/03-network-policies-realistic/`

---

### C4: Rate Limiting

**Objetivo**: Cuantificar impacto de diferentes límites de tasa de solicitudes

**Variantes**:

1. **C4 baseline**: Sin rate limiting
   ```bash
   kubectl set env deployment/api-service -n realistic \
     RATE_LIMIT_ENABLED=false RATE_LIMIT_RPM=600
   ```
   - Permite: Unlimited requests
   - Latencia: ~18.57ms
   - Checks: 100% (todas las solicitudes OK)
   - Error rate: 0%

2. **C4 moderate**: Rate limit 120 RPM (~2 req/s)
   ```bash
   kubectl set env deployment/api-service -n realistic \
     RATE_LIMIT_ENABLED=true RATE_LIMIT_RPM=120
   ```
   - Límite: 120 requests/minuto por cliente
   - Latencia: ~19.34ms (p95)
   - Checks: 100% (cliente respeta límite a 1 VU)
   - Throttling: Cliente es lento → no alcanza límite

3. **C4 strict**: Rate limit 20 RPM (~0.33 req/s)
   ```bash
   kubectl set env deployment/api-service -n realistic \
     RATE_LIMIT_ENABLED=true RATE_LIMIT_RPM=20
   ```
   - Límite: 20 requests/minuto por cliente
   - Latencia: ~15.01ms (p95) ← Menos procesamiento
   - Checks: **58.4%** (41.6% HTTP 429 Too Many Requests)
   - Comportamiento: **ESPERADO** - Bloquea ~41% de /profile requests
   - Error Rate: 41.59% (no es un error, es control funcionando)

**Implementación Rate Limiter**:
```python
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address

limiter = Limiter(
    app=app,
    key_func=get_remote_address,
    default_limits=[f"{RATE_LIMIT_RPM}/minute"]
)

@app.route('/profile', methods=['GET'])
@limiter.limit("1/second")  # local limit fallback
def get_profile():
    return {...}
```

**Directorio de manifiestos**: `experiments/04-rate-limiting-realistic/`

---

## 📊 Generación de Carga (k6)

### Script k6: realistic-flow.js

Ubicación: `RealisticServices/k6/realistic-flow.js`

```javascript
import http from 'k6/http';
import { check, sleep } from 'k6';

const AUTH_BASE = __ENV.AUTH_BASE || 'http://localhost:30084';
const API_BASE = __ENV.API_BASE || 'http://localhost:30081';
const HOST_HEADER = __ENV.HOST_HEADER || '';
const INSECURE_TLS = __ENV.K6_INSECURE_SKIP_TLS_VERIFY === 'true';

export const options = {
  thresholds: {
    checks: ['rate > 0.95'],           // > 95% de checks exitosos
    http_req_failed: ['rate < 0.05'],  // < 5% HTTP errors
    http_req_duration: ['p(0.95) < 700'], // p95 latency < 700ms
  },
  summaryTrendStats: ['avg', 'min', 'med', 'max', 'p(95)', 'p(99)'],
};

function withOptionalHostHeader(params = {}) {
  if (HOST_HEADER) {
    params.headers = params.headers || {};
    params.headers['Host'] = HOST_HEADER;
  }
  if (INSECURE_TLS) {
    params.tlsClientAuth = null;
  }
  return params;
}

export default function () {
  // 1. LOGIN
  const loginUrl = `${AUTH_BASE}/login`;
  const loginPayload = JSON.stringify({
    username: 'demo',
    password: 'demo123',
  });

  const loginRes = http.post(
    loginUrl,
    loginPayload,
    withOptionalHostHeader({
      headers: { 'Content-Type': 'application/json' },
    })
  );

  const loginChecks = check(loginRes, {
    'login status is 200': (r) => r.status === 200,
    'login response has token': (r) => r.body.includes('access_token'),
  });

  const token = loginRes.json('access_token');
  sleep(0.1);

  // 2. GET PROFILE
  const profileUrl = `${API_BASE}/profile?user_id=1`;
  const profileRes = http.get(
    profileUrl,
    withOptionalHostHeader({
      headers: { 'Authorization': `Bearer ${token}` },
    })
  );

  const profileChecks = check(profileRes, {
    'profile status is 200': (r) => r.status === 200,
    'profile response has user': (r) => r.body.includes('user'),
  });

  // Agregar resultado de checks
  check({ passed: loginChecks && profileChecks }, {
    'complete flow successful': (obj) => obj.passed === true,
  });

  sleep(1);
}
```

**Métricas recolectadas**:
- `checks`: % de validaciones exitosas
- `http_req_duration`: Latencia de cada request (p95 es percentil 95)
- `http_req_failed`: % de requests que fallaron
- `http_reqs`: Total de requests completados
- `vus`: Virtual users actuales
- `iteration_duration`: Tiempo de iteración completa

### Uso del Script de Wrapper: run-k6-benchmark.sh

```bash
# Test C1 baseline con 1 VU, 60 segundos
bash scripts/run-k6-benchmark.sh \
  --control C1 \
  --variant baseline \
  --vus 1 \
  --duration 60

# Test C2 istio-mtls con 5 VUs
bash scripts/run-k6-benchmark.sh \
  --control C2 \
  --variant istio-mtls \
  --vus 5

# Test con salida a archivo específico
bash scripts/run-k6-benchmark.sh \
  --control C3 \
  --variant strict \
  --vus 10 \
  --output Testing/results/custom_c3_strict.json

# Dry-run (ver configuración sin ejecutar)
bash scripts/run-k6-benchmark.sh \
  --control C4 \
  --variant moderate \
  --vus 20 \
  --dry-run
```

**Mapeo automático de endpoints**:

| Control | Variant | Auth Base | API Base | Host Header | Port |
|---------|---------|-----------|----------|-------------|------|
| C1 | baseline | https://localhost/auth | https://localhost/api | localhost | 443 |
| C1 | istio | https://localhost:30997 | https://localhost:30997 | realistic.local | 30997 |
| C1 | kong | https://localhost:30443 | https://localhost:30443 | localhost | 30443 |
| C2-C4 | * | http://localhost:30084 | http://localhost:30081 | (none) | 30084/30081 |

---

## 📈 Monitoreo y Métricas

### Prometheus

**Ubicación**: http://localhost:30000

**Métricas recolectadas**:

```promql
# CPU por pod
container_cpu_usage_seconds_total{namespace="realistic"}

# Memoria por pod
container_memory_usage_bytes{namespace="realistic"}

# Requests por segundo
rate(http_requests_total[1m])

# Latencia P95
histogram_quantile(0.95, http_request_duration_seconds)
```

**Scrape interval**: 30 segundos (configurable)

### Grafana

**Ubicación**: http://localhost:30001
**Credenciales**: admin / prom-operator

**Dashboard disponible**: `Monitoring/mubench-dashboard.json`

**Visualizaciones**:
- CPU usage por servicio
- Memoria usage por servicio
- Requests/segundo
- Latencia P50/P95/P99
- Error rate

**Importar dashboard**:
```bash
# Via UI: Configuration → Data Sources → Prometheus → Import
# O via CLI:
curl -X POST http://localhost:30001/api/dashboards/db \
  -H "Content-Type: application/json" \
  -d @Monitoring/mubench-dashboard.json
```

### Script de Análisis: analyze_prometheus_metrics.py

```bash
python3 Testing/analyze_prometheus_metrics.py \
  --prometheus-url http://localhost:30000 \
  --namespace realistic \
  --since 30m \
  --output Testing/results/metrics.csv
```

**Output**:
```csv
timestamp,deployment,container,cpu_millicores,memory_mb,requests_per_sec
2026-05-09T10:05:00Z,api-service,api-service,107.6,290.97,120
2026-05-09T10:05:00Z,auth-service,auth-service,45.3,156.2,135
...
```

---

## 🔬 Ejecución de Experimentos

### Flujo Completo (12 Escenarios, 1 VU)

```bash
cd muBench
bash scripts/run-all-controls-experiments.sh
```

**Tiempo estimado**: 20-30 minutos

**Qué hace**:
1. Para cada uno de los 12 escenarios:
   - Reset del estado anterior
   - Aplicar manifiesto del control
   - Esperar rollout de pods
   - **Smoke test** (validar conectividad)
   - Ejecutar k6 (60s, 1 VU)
   - Recolectar métricas de Prometheus
2. Guardar resultados JSON en `Testing/results/auto_runs/`

**Output de ejemplo**:
```
[INFO] === Ejecutando C1 baseline con 1 VUs ===
[INFO] Aplicando C1 baseline manifest...
[INFO] Esperando rollout...
[INFO] Running smoke check (login → profile)...
[✓] Smoke check OK
[INFO] Ejecutando k6...
     execution: local
     script: RealisticServices/k6/realistic-flow.js
     output: json (Testing/results/auto_runs/C1_baseline_1vus_20260509_100523.json)

     data_received..................: 156 kB
     data_sent......................: 48 kB
     http_req_duration..............: avg=18.72ms, p(95)=18.72ms, p(99)=20.15ms
     http_req_failed................: 0.00%
     http_reqs......................: 120
     checks.........................: 100%

[✓] Resultados guardados
```

### Test de Escalabilidad Progresiva (1→5→10→20 VUs)

```bash
bash scripts/run-scaling-tests.sh

# O para un control específico:
bash scripts/run-scaling-tests.sh C2 istio-mtls
```

**Tiempo estimado**: 40-60 minutos para todos, ~15 min por control

**Qué hace**:
1. Para cada escenario:
   - Ejecutar test con 1 VU (baseline)
   - Ejecutar con 5 VUs
   - Si OK → Ejecutar con 10 VUs
   - Si OK → Ejecutar con 20 VUs
   - Si alguno falla thresholds, detener escalamiento
2. Generar CSV con resultados: `Testing/results/scaling_tests/scaling-report_YYYYMMDD.csv`

**Criterios de Detención**:
- p95 latency > 500ms
- CPU > 70%
- Memoria > 80%
- Error rate > 5% (excepto C4 strict)

**Output de ejemplo**:
```
╔════════════════════════════════════════════════════════════════════╗
║ Control: C2 / Variante: istio-mtls                                ║
╚════════════════════════════════════════════════════════════════════╝

[INFO] 🔄 Testando con 5 VUs...
[✓] Resultados con 5 VUs:
  Checks: 100% (baseline: 100%)
  p95: 110.45ms (baseline: 22.50ms) ← +391% (aceptable)
  Errors: 0% (baseline: 0%)
  Recursos nodo: CPU=35%, MEM=62%
[✓] ✓ Métricas OK, escalamiento viable

[INFO] 🔄 Testando con 10 VUs...
[✓] Resultados con 10 VUs:
  Checks: 99.8% (baseline: 100%)
  p95: 218.70ms (baseline: 22.50%)
  Errors: 0.2% (baseline: 0%)
  Recursos nodo: CPU=62%, MEM=88%
[✓] ✓ Métricas OK, escalamiento viable

[INFO] 🔄 Testando con 20 VUs...
✗ p95 (520ms) supera threshold (500ms) → DETENER
[!] Escalamiento detenido para C2/istio-mtls
```

### Test Individual Rápido

```bash
# Solo verificar conectividad
bash scripts/run-k6-benchmark.sh \
  --control C1 \
  --variant istio \
  --vus 1 \
  --duration 10
```

---

## 🩹 Troubleshooting

### Problema: "No se alcanza localhost:30997"

**Causa**: Istio Gateway no desplegado o no ingresa tráfico

**Solución**:
```bash
# Verificar Gateway
kubectl get gateway -n realistic
kubectl describe gateway realistic-gateway -n realistic

# Verificar IngressGateway
kubectl get deployment -n istio-system | grep ingress

# Verificar service
kubectl get svc -n istio-system | grep ingressgateway

# Port-forward si es necesario
kubectl port-forward -n istio-system \
  svc/istio-ingressgateway 30997:443
```

### Problema: "Certificado TLS rechazado"

**Causa**: Certificate secret no existe o nombre incorrecto

**Solución**:
```bash
# Verificar secret
kubectl get secret mubench-tls -n istio-system

# Si no existe, crear:
openssl req -x509 -newkey rsa:4096 -keyout /tmp/tls.key \
  -out /tmp/tls.crt -days 365 -nodes \
  -subj "/CN=realistic.local"

kubectl create secret tls mubench-tls -n istio-system \
  --cert=/tmp/tls.crt --key=/tmp/tls.key

# En k6, usar insecureSkipTLSVerify
k6 run -e K6_INSECURE_SKIP_TLS_VERIFY=true ...
```

### Problema: "Smoke check falla: Connection refused"

**Causa**: Service no ready o no escucha en endpoint

**Solución**:
```bash
# Verificar estado
kubectl get pods -n realistic -w

# Ver logs del servicio
kubectl logs -n realistic deployment/auth-service -f

# Verificar endpoints
kubectl get endpoints -n realistic
kubectl get svc -n realistic -o wide

# Test manual
curl -v http://localhost:30084/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"demo","password":"demo123"}'
```

### Problema: "k6 threshold failures (checks < 95%)"

**Causa**:
- Rate limiting activo bloqueando requests (C4 strict es intencional)
- Servicio inestable
- Smoke gate no funcionó

**Solución**:
```bash
# Verificar que es intencional (C4 strict)
# Si no es C4 strict, verificar servicio:
kubectl logs -n realistic deployment/api-service --tail=100

# Reiniciar si es necesario
kubectl rollout restart deployment/api-service -n realistic

# Reejecutar test
bash scripts/run-all-controls-experiments.sh
```

### Problema: "Memoria insuficiente / Out of Memory"

**Causa**: WSL2 asignación baja, o escalamiento excesivo de VUs

**Solución**:
```bash
# En Windows PowerShell (Admin):
# Editar C:\Users\<Usuario>\.wslconfig
[wsl2]
memory=12GB      # ← Aumentar
processors=6
swap=8GB         # ← Aumentar swap

# Reiniciar
wsl --shutdown

# Verificar
wsl -d Ubuntu   # o tu distro
free -h
```

### Problema: "CPU throttling / System slow"

**Causa**: Sistema usando todos los cores

**Solución**:
```bash
# Ver procesos heavy
top -b -n 1 | head -20

# Ver CPU del cluster
kubectl top nodes
kubectl top pods -n realistic

# Reducir VUs en tests
bash scripts/run-k6-benchmark.sh --control C1 --variant baseline --vus 1
```

---

## 📊 Resultados y Análisis

### Estructura de Resultados

```
Testing/results/
├── auto_runs/                                # Benchmark completo (1 VU × 12 escenarios)
│   ├── C1_baseline_1vus_20260509_101234.json
│   ├── C1_istio_1vus_20260509_101456.json
│   ├── ...
│   └── invalid-scenarios.csv                 # Escenarios que fallaron smoke test
│
└── scaling_tests/                            # Tests progresivos (5, 10, 20 VUs)
    ├── scaling-report_20260509.csv
    ├── scaling_C1_baseline_1vus_1234567.json
    ├── scaling_C1_baseline_5vus_1234568.json
    └── scaling_C2_istio-mtls_20vus_1234569.json
```

### Análisis de Resultados

#### Extracción de Métricas

**From k6 JSON output:**
```bash
# Usar Python para extraer
python3 << 'EOF'
import json

with open('Testing/results/auto_runs/C1_baseline_1vus_20260509_101234.json') as f:
  lines = f.readlines()

for line in reversed(lines):
  try:
    obj = json.loads(line)
    if obj.get('type') == 'Point' and obj.get('metric') == 'checks':
      print(f"Checks: {obj['data']['value']*100:.1f}%")
  except: pass
EOF
```

**From Prometheus:**
```bash
# CPU average durante test
curl -G 'http://localhost:30000/api/v1/query' \
  --data-urlencode 'query=avg(rate(container_cpu_usage_seconds_total{namespace="realistic"}[5m]))*1000'

# Memory maximum
curl -G 'http://localhost:30000/api/v1/query' \
  --data-urlencode 'query=max(container_memory_usage_bytes{namespace="realistic"})/1024/1024'
```

#### CSV de Consolidación

Script: `analyze_k6_results.py`

```bash
python3 Testing/analyze_k6_results.py \
  --input-dir Testing/results/auto_runs/ \
  --output Testing/results/campaign_summary.csv
```

**Output**:
```csv
scenario,checks_rate,%,p95_ms,error_rate,%,http_reqs,cpu_mC,memory_MiB
C1_baseline,100.0,18.72,0.0,120,51.06,182.58
C1_istio,100.0,17.74,0.0,120,46.12,190.19
C1_kong,100.0,18.61,0.0,120,50.85,184.93
C2_baseline,100.0,15.99,0.0,120,69.60,192.95
C2_istio-mtls,100.0,22.50,0.0,120,107.59,290.97
C2_linkerd-mtls,100.0,19.77,0.0,120,88.98,220.15
C3_baseline,100.0,17.23,0.0,120,75.41,164.96
C3_basic,100.0,20.05,0.0,120,53.15,153.88
C3_strict,100.0,18.13,0.0,120,54.38,154.06
C4_baseline,100.0,18.57,0.0,120,59.30,170.00
C4_moderate,100.0,19.34,0.0,120,60.20,161.23
C4_strict,58.4,15.01,41.59,70,49.11,158.47
```

#### Análisis Comparativo

**Overhead Relativo vs Baseline**:

```
C1 Gateways (vs C1 baseline):
├─ Istio: p95 -5.2%, CPU -10%, MEM +4% (mejor!)
└─ Kong:  p95 -0.6%, CPU +3%, MEM -1% (negligible)

C2 mTLS (vs C2 baseline):
├─ Istio: p95 +40.6%, CPU +54%, MEM +50% (costoso!)
└─ Linkerd: p95 +23.6%, CPU +28%, MEM +14% (mejor que Istio)

C3 Network Policies (vs C3 baseline):
├─ Basic: p95 +16.4%, CPU -29%, MEM -7% (positivo!)
└─ Strict: p95 +5.2%, CPU -28%, MEM -7% (negligible)

C4 Rate Limiting (vs C4 baseline):
├─ Moderate: p95 +4.1%, CPU +1%, MEM -5% (negligible)
└─ Strict: p95 -19.1%, CPU -17%, MEM -6% (bloquea requests)
```

**Conclusiones**:
1. **Istio mTLS es el factor más costoso** (+40% latencia, +54% CPU)
2. **Linkerd es 40% más eficiente** que Istio para mTLS
3. **Network Policies tienen impacto negligible** (eval en kernel)
4. **Rate Limiting reduce carga** (fewer requests processed)
5. **Kong vs Istio Gateway: Kong más estable**

---

### Escalabilidad Recomendada

**Basado en resultados con 1 VU y recursos disponibles (6 cores, 12GB)**:

| VUs | C1 (Gateway) | C2 (mTLS) | C3 (NetPol) | C4 (RateLimit) | Status |
|---|---|---|---|---|---|
| 1 | ✅ 18ms | ✅ 22ms | ✅ 18ms | ✅ 18ms | **Done** |
| 5 | ✅ ~90ms | ⚠️ ~110ms | ✅ ~90ms | ✅ ~90ms | **Viable** |
| 10 | ⚠️ ~180ms | 🔴 ~220ms | ⚠️ ~180ms | ⚠️ ~180ms | **Monitor** |
| 20 | 🔴 Sat. | 🔴 Timeout | 🔴 Sat. | 🔴 Sat. | **Cluster only** |

**Recomendación final**:
- **Producción**: Usar Linkerd + Network Policies
- **Development**: Usar C1 baseline + C3 basic
- **Research**: Escalar a 5-10 VUs (12GB RAM suficiente)
- **Benchmarking a 20+ VUs**: Requiere cluster Kubernetes real (3+ nodos)

---

## 📚 Referencia Rápida

### Comandos Frecuentes

```bash
# Estado del cluster
kubectl cluster-info
kubectl get nodes
kubectl get namespaces
kubectl get pods -n realistic -w

# Logs
kubectl logs -n realistic deployment/api-service -f
kubectl logs -n realistic deployment/auth-service --tail=50

# Acceder a servicios
kubectl port-forward -n realistic svc/auth-service 30084:8080
kubectl port-forward -n realistic svc/api-service 30081:8080

# Reiniciar servicios
kubectl rollout restart deployment/api-service -n realistic

# Limpiar
kubectl delete all -n realistic
kubectl delete namespace realistic

# Monitoreo
kubectl top nodes
kubectl top pods -n realistic
```

### Archivos Clave

| Archivo | Propósito |
|---------|-----------|
| `scripts/full-project-setup.sh` | Setup automático completo |
| `scripts/run-all-controls-experiments.sh` | Benchmark 12 escenarios (1 VU) |
| `scripts/run-scaling-tests.sh` | Tests progresivos (5/10/20 VUs) |
| `scripts/run-k6-benchmark.sh` | Wrapper único de k6 |
| `RealisticServices/k6/realistic-flow.js` | Script de carga k6 |
| `Testing/analyze_k6_results.py` | Extrae métricas de JSON |
| `Testing/analyze_prometheus_metrics.py` | Extrae CPU/memoria |
| `Monitoring/mubench-dashboard.json` | Dashboard Grafana |
| `Docs/SETUP_GUIDE.md` | Esta documentación |

---

## 🎓 Recursos Adicionales

- **Kubernetes**: https://kubernetes.io/docs/
- **k6**: https://k6.io/docs/
- **Istio**: https://istio.io/latest/docs/
- **Prometheus**: https://prometheus.io/docs/
- **Grafana**: https://grafana.com/docs/grafana/latest/
- **MicroK8s**: https://microk8s.io/docs

---

**Versión**: 1.0
**Fecha**: 2026-05-09
**Mantenedor**: µBench Team
**Licencia**: MIT
