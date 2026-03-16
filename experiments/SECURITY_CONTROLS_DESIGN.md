# Diseño Experimental: Controles de Seguridad CSA CCM Lite

## 📋 Resumen Ejecutivo

Este documento detalla el diseño experimental para evaluar el impacto en rendimiento de 4 controles de seguridad críticos según Cloud Controls Matrix (CSA CCM Lite) implementados en una arquitectura de microservicios basada en Kubernetes.

### Controles Evaluados
1. **API Gateway** (Norte-Sur) - Kong vs NGINX Gateway
2. **mTLS Service Mesh** (Este-Oeste) - Istio vs Linkerd
3. **Network Policies** (Segmentación)
4. **Rate Limiting** (Protección contra abuso)

---

## 🎯 Objetivo General

Cuantificar el overhead de rendimiento introducido por controles de seguridad en la nube, proporcionando evidencia empírica para decisiones arquitectónicas que balanceen seguridad y performance.

---

## 📊 Diseño Experimental Unificado

### Metodología
- **Tipo:** Diseño factorial con medidas repetidas
- **Variables controladas:** Hardware, Kubernetes, workload, carga de prueba
- **Repeticiones:** 3 por escenario
- **Duración por run:** 5 minutos
- **Cooldown entre runs:** 10 minutos

### Métricas Comunes (Todas las Pruebas)

| Métrica | Unidad | Fuente | Frecuencia |
|---------|--------|--------|------------|
| Latencia promedio | ms | k6 | Continua |
| Latencia P95 | ms | k6 | Continua |
| Latencia P99 | ms | k6 | Continua |
| Throughput | req/s | k6 | Continua |
| Tasa de errores | % | k6 | Continua |
| CPU por pod | % | Prometheus | 15s |
| Memoria por pod | MiB | Prometheus | 15s |
| Bytes red enviados | bytes/s | Prometheus | 15s |
| Bytes red recibidos | bytes/s | Prometheus | 15s |

### Niveles de Carga

| Nivel | VUs | Requests esperados/s | Duración |
|-------|-----|---------------------|----------|
| Baja | 10 | ~50-70 | 5 min |
| Media | 25 | ~120-150 | 5 min |
| Alta | 50 | ~200-300 | 5 min |

---

## 🔐 Control 1: API Gateway (Norte-Sur)

### Descripción
Evaluación del overhead introducido por API Gateways en el tráfico norte-sur (externo → cluster).

### Controles CCM Lite
- **AIS-08:** API Security
- **I&S-03:** Network Security
- **IAM-13:** Strong Authentication

### Objetivo de Seguridad
- Protección de APIs expuestas
- Autenticación y autorización centralizada
- Rate limiting y validación de requests

### Variable Independiente
**Tipo de Gateway:**
- E1: Sin Gateway (baseline - acceso directo vía NodePort)
- E2: Kong Gateway (con rate limit, auth plugin)
- E3: NGINX Ingress Controller (con rate limit básico)

### Variables Dependientes
1. Latencia adicional introducida (ms)
2. Throughput máximo (req/s)
3. CPU consumido por Gateway (%)
4. Memoria consumida por Gateway (MiB)

### Hipótesis
**H1:** Kong introducirá mayor latencia que NGINX debido a su arquitectura de plugins (+10-15%).  
**H2:** Ambos gateways reducirán throughput máximo en 5-10% vs baseline.  
**H3:** Kong consumirá 2-3x más memoria que NGINX por su arquitectura basada en Lua.

### Configuración

#### E1: Baseline (Sin Gateway)
```yaml
# Acceso directo via NodePort
Service:
  type: NodePort
  port: 30080
```

#### E2: Kong Gateway
```yaml
Kong:
  version: 3.4
  plugins:
    - rate-limiting (100 req/min)
    - key-auth
    - request-transformer
  replicas: 2
  resources:
    requests: {cpu: 500m, memory: 512Mi}
    limits: {cpu: 1000m, memory: 1Gi}
```

#### E3: NGINX Gateway
```yaml
NGINX:
  version: 1.9
  rate-limit: 100 req/s
  replicas: 2
  resources:
    requests: {cpu: 200m, memory: 256Mi}
    limits: {cpu: 500m, memory: 512Mi}
```

### Procedimiento
```bash
# 1. Baseline
./experiments/01-api-gateway/run-baseline.sh

# 2. Kong
cd experiments/01-api-gateway/kong
./setup-kong.sh
k6 run tests/test-kong.js

# 3. NGINX
cd experiments/01-api-gateway/nginx
./setup-nginx.sh
k6 run tests/test-nginx.js

# 4. Análisis
python3 analyze-gateway-results.py
```

### Métricas Específicas
- **Gateway Latency:** Tiempo en gateway antes de backend
- **Plugin Overhead:** Latencia atribuible a plugins
- **Connection Pooling Efficiency:** Reuso de conexiones

---

## 🔒 Control 2: mTLS Service Mesh (Este-Oeste)

### Descripción
Evaluación del overhead de mutual TLS en comunicaciones internas entre microservicios.

### Controles CCM Lite
- **CEK-03:** Data Protection In-Transit
- **CEK-10:** Key Generation
- **CEK-12:** Key Rotation
- **IAM-13:** Strong Authentication
- **I&S-03:** Network Security

### Objetivo de Seguridad
- Cifrado de tráfico interno
- Autenticación mutua entre servicios
- Rotación automática de certificados

### Variable Independiente
**Tipo de Service Mesh:**
- E1: Sin Mesh (HTTP plano)
- E2: Istio con mTLS (strict mode)
- E3: Linkerd con mTLS automático

### Variables Dependientes
1. Latencia inter-servicio (ms)
2. CPU por sidecar proxy (%)
3. Memoria por sidecar (MiB)
4. Tasa de errores de certificados (%)

### Hipótesis
**H1:** mTLS aumentará latencia P95 en 20-30% vs HTTP plano.  
**H2:** Linkerd tendrá menor overhead que Istio (arquitectura más liviana en Rust vs C++).  
**H3:** CPU del sidecar será 2-4x el del contenedor de aplicación.

### Configuración

#### E1: Baseline (Sin Mesh)
```yaml
ServiceCell:
  protocol: http
  no_sidecar: true
```

#### E2: Istio
```yaml
Istio:
  version: 1.20
  mtls_mode: STRICT
  sidecar_resources:
    requests: {cpu: 100m, memory: 128Mi}
    limits: {cpu: 2000m, memory: 1Gi}
  certificate_ttl: 24h
  rotation: automatic
```

#### E3: Linkerd
```yaml
Linkerd:
  version: 2.14
  mtls: automatic
  proxy_resources:
    requests: {cpu: 10m, memory: 10Mi}
    limits: {cpu: 1000m, memory: 250Mi}
  certificate_ttl: 24h
```

### Procedimiento
```bash
# 1. Baseline HTTP
./experiments/02-mtls-service-mesh/run-baseline.sh

# 2. Istio mTLS
cd experiments/02-mtls-service-mesh/istio
./install-istio.sh
./enable-mtls.sh
k6 run tests/test-istio-mtls.js

# 3. Linkerd mTLS
cd experiments/02-mtls-service-mesh/linkerd
./install-linkerd.sh
k6 run tests/test-linkerd-mtls.js

# 4. Análisis
python3 analyze-mtls-results.py
```

### Métricas Específicas
- **Handshake Latency:** Tiempo de establecimiento TLS
- **Sidecar CPU/Mem:** Recursos del proxy
- **Certificate Rotation Events:** Frecuencia de rotación
- **mTLS Success Rate:** % de conexiones exitosas con mTLS

---

## 🛡️ Control 3: Network Policies (Segmentación)

### Descripción
Evaluación del impacto de políticas de red en segmentación interna.

### Controles CCM Lite
- **I&S-06:** Segmentation & Segregation
- **I&S-03:** Network Security
- **IAM-05:** Least Privilege

### Objetivo de Seguridad
- Restricción de comunicaciones laterales
- Principio de mínimo privilegio
- Reducción de superficie de ataque

### Variable Independiente
**Nivel de Segmentación:**
- E1: Sin Network Policies (comunicación libre)
- E2: Con Network Policies (allow-list estricto)

### Variables Dependientes
1. Latencia de conexión inicial (ms)
2. CPU del cluster (%)
3. Tiempo de bloqueo de tráfico no permitido (ms)
4. Overhead de evaluación de políticas (ms)

### Hipótesis
**H1:** Network Policies tendrán impacto mínimo en latencia (<5%).  
**H2:** CPU del cluster aumentará <2% por evaluación de políticas.  
**H3:** Bloqueo de tráfico lateral será inmediato (<1ms).

### Configuración

#### E1: Baseline (Sin Policies)
```yaml
# Sin restricciones, todos los pods pueden comunicarse
NetworkPolicy: none
```

#### E2: Con Policies (Segmentación estricta)
```yaml
NetworkPolicies:
  - name: deny-all-default
    action: deny all ingress/egress
  
  - name: allow-s0-to-s1
    from: s0
    to: s1
    ports: [80]
  
  - name: allow-s1-to-sdb1
    from: s1
    to: sdb1
    ports: [80]
  
  - name: allow-prometheus-scrape
    from: prometheus
    to: all
    ports: [8080]
```

### Procedimiento
```bash
# 1. Baseline sin policies
./experiments/03-network-policies/run-baseline.sh

# 2. Con policies estrictas
cd experiments/03-network-policies
./apply-policies.sh
k6 run tests/test-with-policies.js

# 3. Test de bloqueo lateral
./test-lateral-blocking.sh

# 4. Análisis
python3 analyze-netpol-results.py
```

### Métricas Específicas
- **Policy Evaluation Time:** Tiempo de evaluar política
- **Blocked Connections:** # de conexiones bloqueadas
- **CNI Overhead:** CPU del plugin CNI (Calico/Cilium)

---

## 🚦 Control 4: Rate Limiting (Protección contra Abuso)

### Descripción
Evaluación de mecanismos de limitación de tasa para protección contra sobrecarga.

### Controles CCM Lite
- **AIS-08:** API Security
- **I&S-09:** Network Defense
- **BCR-03:** Business Continuity Strategy

### Objetivo de Seguridad
- Mitigación de ataques DoS
- Protección de recursos backend
- Garantía de disponibilidad

### Variable Independiente
**Nivel de Rate Limiting:**
- E1: Sin Rate Limiting
- E2: Con Rate Limiting (100 req/s por IP)

### Variables Dependientes
1. Throughput máximo estable (req/s)
2. Tasa de errores 429 (%)
3. Tiempo hasta degradación bajo carga (s)
4. Latencia bajo carga extrema (ms)

### Hipótesis
**H1:** Rate Limiting mejorará estabilidad bajo carga extrema (>200 VUs).  
**H2:** Throughput máximo se limitará a ~100 req/s con RL activo.  
**H3:** Errores 429 aparecerán cuando carga exceda límite en >10%.

### Configuración

#### E1: Baseline (Sin Rate Limiting)
```yaml
RateLimit: disabled
```

#### E2: Con Rate Limiting
```yaml
RateLimit:
  enabled: true
  requests_per_second: 100
  burst: 50
  scope: per_ip
  response_code: 429
  backend: redis  # Para distribuido
```

### Procedimiento
```bash
# 1. Baseline sin RL
./experiments/04-rate-limiting/run-baseline.sh

# 2. Con Rate Limiting
cd experiments/04-rate-limiting
./apply-rate-limit.sh
k6 run tests/test-with-rl.js --vus 150  # Exceder límite

# 3. Test de estabilidad extrema
k6 run tests/stress-test.js --vus 300 --duration 10m

# 4. Análisis
python3 analyze-rl-results.py
```

### Métricas Específicas
- **429 Rate:** % de requests limitados
- **Time to First 429:** Tiempo hasta primer request rechazado
- **Backend Protection:** % de reducción de carga en backend

---

## 📈 Análisis Estadístico Unificado

### Pruebas de Hipótesis

#### Test 1: Comparación de Latencias (Todos los Controles)
```
H0: μ_baseline = μ_control
H1: μ_baseline ≠ μ_control
Método: Paired t-test
α: 0.05
```

#### Test 2: Comparación de Throughput
```
H0: MedianThroughput_baseline = MedianThroughput_control
H1: MedianThroughput_baseline ≠ MedianThroughput_control
Método: Mann-Whitney U test
α: 0.05
```

#### Test 3: ANOVA para múltiples configuraciones
```
Para Gateway (3 niveles) y Mesh (3 niveles):
H0: μ1 = μ2 = μ3
H1: Al menos un μ es diferente
Método: One-way ANOVA + Tukey HSD
α: 0.05
```

### Cálculo de Overhead

```python
# Overhead porcentual
overhead_pct = ((metric_control - metric_baseline) / metric_baseline) * 100

# Overhead absoluto
overhead_abs = metric_control - metric_baseline

# Eficiencia (inverso del overhead)
efficiency = 100 - overhead_pct
```

### Visualizaciones Requeridas

1. **Boxplots:** Latencia por configuración
2. **Barras:** Overhead de recursos (CPU, memoria)
3. **Series temporales:** Latencia bajo carga creciente
4. **Scatter plots:** Latencia vs Throughput (trade-offs)
5. **Heatmaps:** Correlación entre métricas
6. **Radar charts:** Comparación multidimensional de controles

---

## 🗓️ Cronograma de Ejecución

### Semana 1: Preparación
- Día 1-2: Setup de herramientas (Kong, Istio, Linkerd)
- Día 3-4: Validación de configuraciones
- Día 5: Piloto de cada control

### Semana 2: Experimentos - Gateway y mTLS
- Día 1: Control 1 - API Gateway (3 escenarios × 3 cargas × 3 reps = 27 runs)
- Día 2: Control 2 - mTLS Mesh (3 escenarios × 3 cargas × 3 reps = 27 runs)
- Día 3: Análisis preliminar

### Semana 3: Experimentos - NetPol y Rate Limiting
- Día 1: Control 3 - Network Policies (2 escenarios × 3 cargas × 3 reps = 18 runs)
- Día 2: Control 4 - Rate Limiting (2 escenarios × 3 cargas × 3 reps = 18 runs)
- Día 3: Análisis preliminar

### Semana 4: Análisis Final
- Día 1-2: Procesamiento de datos, estadística
- Día 3-4: Generación de gráficos, tablas
- Día 5: Redacción de informe

**Total:** 90 runs experimentales, ~30 horas de experimentos netos

---

## 📁 Estructura de Archivos

```
experiments/
├── SECURITY_CONTROLS_DESIGN.md (este archivo)
├── 01-api-gateway/
│   ├── README.md
│   ├── baseline/
│   │   └── deploy-baseline.sh
│   ├── kong/
│   │   ├── kong-values.yaml
│   │   ├── install-kong.sh
│   │   └── kong-config.yaml
│   ├── nginx/
│   │   ├── nginx-ingress.yaml
│   │   ├── install-nginx.sh
│   │   └── rate-limit-config.yaml
│   └── tests/
│       ├── baseline.js
│       ├── test-kong.js
│       └── test-nginx.js
│
├── 02-mtls-service-mesh/
│   ├── README.md
│   ├── baseline/
│   │   └── deploy-http-only.sh
│   ├── istio/
│   │   ├── istio-install.sh
│   │   ├── mtls-strict.yaml
│   │   └── sidecar-config.yaml
│   ├── linkerd/
│   │   ├── linkerd-install.sh
│   │   └── mtls-config.yaml
│   └── tests/
│       ├── baseline-http.js
│       ├── test-istio.js
│       └── test-linkerd.js
│
├── 03-network-policies/
│   ├── README.md
│   ├── baseline/
│   │   └── no-policies.sh
│   ├── policies/
│   │   ├── deny-all.yaml
│   │   ├── allow-s0-s1.yaml
│   │   ├── allow-s1-sdb1.yaml
│   │   └── allow-prometheus.yaml
│   ├── apply-policies.sh
│   ├── test-lateral-blocking.sh
│   └── tests/
│       ├── baseline.js
│       └── test-with-policies.js
│
├── 04-rate-limiting/
│   ├── README.md
│   ├── baseline/
│   │   └── no-rate-limit.sh
│   ├── rate-limit-config.yaml
│   ├── apply-rate-limit.sh
│   └── tests/
│       ├── baseline.js
│       ├── test-with-rl.js
│       └── stress-test.js
│
└── analysis/
    ├── analyze_all_controls.py
    ├── generate_comparison_plots.py
    ├── statistical_tests.py
    └── report_generator.py
```

---

## ✅ Checklist Pre-Experimento

### Infraestructura
- [ ] MicroK8s corriendo y estable
- [ ] Prometheus + Grafana funcionales
- [ ] k6 instalado (v0.45+)
- [ ] Helm instalado (para Kong, Istio)
- [ ] Suficiente espacio en disco (>20GB para logs/resultados)

### Servicios Base
- [ ] Imagen Docker v3-enhanced construida
- [ ] Servicios s0, s1, sdb1 desplegados
- [ ] Endpoints /process, /validate, /query funcionando
- [ ] ConfigMap workmodel configurado

### Herramientas de Monitoreo
- [ ] Prometheus scraping de pods
- [ ] Grafana dashboards importados
- [ ] Node exporter activo (para métricas de red)

### Scripts de Automatización
- [ ] Scripts de deploy validados
- [ ] Scripts de cleanup probados
- [ ] Tests k6 ejecutados exitosamente (baseline)

---

## 🎯 Criterios de Éxito

Un experimento se considera exitoso si:

1. ✅ Tasa de errores < 1% (excepto tests de rate limiting)
2. ✅ Coeficiente de variación < 20% entre repeticiones
3. ✅ Datos completos para todas las métricas
4. ✅ Pods estables durante toda la prueba (sin crashes)
5. ✅ Snapshots de Prometheus capturados correctamente

---

## 📊 Resultados Esperados

### Control 1: API Gateway
| Configuración | Latencia P95 | Throughput | CPU Gateway | Memoria Gateway |
|---------------|--------------|------------|-------------|-----------------|
| Baseline | 46ms | 450 rps | - | - |
| Kong | ~65ms (+41%) | ~400 rps (-11%) | 40% | 800 MiB |
| NGINX | ~55ms (+20%) | ~420 rps (-7%) | 15% | 200 MiB |

### Control 2: mTLS Service Mesh
| Configuración | Latencia P95 | CPU Sidecar | Memoria Sidecar | Error Rate |
|---------------|--------------|-------------|-----------------|------------|
| HTTP Plano | 46ms | - | - | 0% |
| Istio mTLS | ~60ms (+30%) | 25% | 128 MiB | <0.1% |
| Linkerd mTLS | ~55ms (+20%) | 8% | 40 MiB | <0.1% |

### Control 3: Network Policies
| Configuración | Latencia P95 | Overhead | Bloqueos Exitosos |
|---------------|--------------|----------|-------------------|
| Sin Policies | 46ms | - | N/A |
| Con Policies | ~48ms (+4%) | <3% CPU cluster | 100% |

### Control 4: Rate Limiting
| Configuración | Throughput Max | Tasa 429 | Estabilidad |
|---------------|----------------|----------|-------------|
| Sin RL | Variable (degrada) | 0% | Baja bajo carga |
| Con RL | 100 rps (estable) | 33% @ 150 VUs | Alta |

---

## 📚 Referencias

### Normativas de Seguridad
- CSA Cloud Controls Matrix (CCM) v4.0
- NIST SP 800-204B: Attribute-based Access Control for Microservices
- OWASP API Security Top 10

### Herramientas
- Kong Gateway: https://docs.konghq.com/
- Istio Documentation: https://istio.io/latest/docs/
- Linkerd Documentation: https://linkerd.io/2/overview/
- Kubernetes Network Policies: https://kubernetes.io/docs/concepts/services-networking/network-policies/

---

**Documento:** Diseño Experimental de Controles de Seguridad  
**Fecha:** Marzo 2026  
**Versión:** 1.0  
**Estado:** Listo para implementación
