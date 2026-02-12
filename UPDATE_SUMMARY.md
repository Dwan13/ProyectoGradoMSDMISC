# 🚀 MuBench - Actualizaciones para Comunicación Inter-Servicio

## 📝 Resumen de Implementación

Se han implementado exitosamente las siguientes funcionalidades en el proyecto MuBench **sin romper la arquitectura actual**:

### ✅ Funcionalidades Implementadas

1. **Comunicación Real HTTP/HTTPS entre Microservicios**
   - `service0` → llama HTTP a `service1`
   - `service1` → llama HTTP a `service-db`
   - Variable de entorno `COMM_PROTOCOL` para alternar http/https

2. **Endpoints REST Simples**
   - `/process` en service0
   - `/validate` en service1  
   - `/query` en service-db
   - `/metrics` en todos (Prometheus)
   - `/health` y `/ready` probes

3. **Métricas Prometheus Mejoradas**
   - `http_request_duration_seconds` (histograma de latencia)
   - `http_requests_total` (contador de requests)
   - Métricas originales de muBench preservadas

4. **Soporte TLS con Certificados Auto-Firmados**
   - Generación automática de certificados
   - Secrets de Kubernetes creados automáticamente
   - HTTPS opcional sin romper funcionalidad HTTP

5. **Manifests Kubernetes Actualizados**
   - Services con ClusterIP (comunicación interna)
   - Readiness y Liveness probes implementadas
   - Annotations de Prometheus para auto-discovery
   - Soporte volumenes TLS

6. **k6 Reemplaza JMeter**
   - Scripts JavaScript modernos y parametrizables
   - Salida JSON para análisis programático
   - Tests de baseline y comunicación inter-servicio

7. **Carpeta /experiments con Escenarios Reproducibles**
   - Guía completa HTTP sin cifrado
   - Guía completa HTTPS con medición de overhead TLS
   - Queries Prometheus documentadas

8. **Script Bash Extendido**
   - Parámetro `--protocol http|https`
   - Generación automática de certificados
   - Ejecución automática de tests k6
   - Flujo original preservado

---

## 📂 Archivos Creados/Modificados

### ✨ Archivos Nuevos

```
ServiceCell/
  └── CellController-enhanced.py          # Versión mejorada con endpoints HTTP/HTTPS

Testing/
  ├── baseline.js                         # Script k6 baseline
  ├── inter-service-test.js               # Script k6 inter-servicio
  └── analyze_k6_results.py               # Analizador de resultados

experiments/
  ├── README.md                           # Guía general de experimentos
  ├── scenario-http.md                    # Escenario HTTP detallado
  └── scenario-https.md                   # Escenario HTTPS con TLS

scripts/
  ├── install_k6.sh                       # Instalador de k6
  └── README.md                           # Documentación de scripts

CHANGES.md                                # Changelog detallado (este archivo)
```

### 🔧 Archivos Modificados

```
scripts/deploy_microk8s.sh                # Soporte HTTP/HTTPS, k6, TLS
Deployers/K8sDeployer/Templates/
  ├── DeploymentTemplate.yaml             # Probes, env vars, volumenes TLS
  └── ServiceTemplate.yaml                # ClusterIP, annotations Prometheus
```

---

## 🎯 Uso Rápido

### Opción 1: HTTP (Sin Cifrado)

```bash
cd ~/muBench

# Desplegar
./scripts/deploy_microk8s.sh --start --protocol http

# Acceder a Grafana
# URL: http://localhost:3000
# Ver credenciales en: ~/.mubench_credentials

# Ver resultados k6
ls -lh Testing/results/http-*.json
```

### Opción 2: HTTPS (Con TLS)

```bash
cd ~/muBench

# Desplegar con HTTPS
./scripts/deploy_microk8s.sh --start --protocol https

# Los certificados se generan automáticamente en:
# ~/muBench/tls-certs/

# Ver secrets creados
microk8s kubectl get secrets -n default | grep tls
```

### Comparar HTTP vs HTTPS (Medir Overhead)

```bash
cd ~/muBench

# 1. Ejecutar con HTTP
./scripts/deploy_microk8s.sh --start --protocol http
# Esperar a que complete...

# 2. Detener y ejecutar con HTTPS
./scripts/deploy_microk8s.sh --stop
./scripts/deploy_microk8s.sh --start --protocol https
# Esperar a que complete...

# 3. Analizar diferencias
cd Testing
python3 analyze_k6_results.py \
  results/http-baseline-*.json \
  results/https-baseline-*.json
```

---

## 📊 Métricas Disponibles

### Nuevas Métricas Prometheus

```promql
# Latencia de requests HTTP por servicio
http_request_duration_seconds{service="s0",endpoint="/process"}

# Total de requests
rate(http_requests_total{service="s0"}[1m])

# Network bytes (K8s nativo)
rate(container_network_transmit_bytes_total{namespace="default"}[1m])
```

### Dashboard Grafana

Acceder a `http://localhost:3000` con credenciales de `~/.mubench_credentials`

Dashboard creado automáticamente: **"MuBench Microservices Performance"**

Paneles incluidos:
- HTTP Request Duration P95
- Throughput (req/s)
- Network TX/RX Bytes
- Error Rate

---

## 🔍 Arquitectura de Comunicación

```
┌─────────────┐
│   Cliente   │
│   (k6)      │
└──────┬──────┘
       │ HTTP
       ▼
┌─────────────────────┐
│  Gateway Nginx      │
│  NodePort: 31113    │
└──────┬──────────────┘
       │ HTTP
       ▼
┌─────────────────────┐     HTTP/HTTPS      ┌─────────────────────┐
│  Service0 (s0)      │ ─────────────────▶  │  Service1 (s1)      │
│  /process           │                     │  /validate          │
│  ClusterIP:80       │                     │  ClusterIP:80       │
└─────────────────────┘                     └──────┬──────────────┘
                                                   │ HTTP/HTTPS
                                                   ▼
                                            ┌─────────────────────┐
                                            │  ServiceDB (sdb1)   │
                                            │  /query             │
                                            │  ClusterIP:80       │
                                            └─────────────────────┘

Todos exponen:
  - /metrics (Prometheus)
  - /health (liveness)
  - /ready (readiness)
```

---

## 🧪 Experimentos Disponibles

Ver documentación completa en [`experiments/`](experiments/README.md)

### Experimento 1: HTTP Baseline
**Objetivo:** Medir latencia y throughput sin cifrado  
**Guía:** [experiments/scenario-http.md](experiments/scenario-http.md)

**Métricas clave:**
- Latencia P95 inter-servicio
- Throughput (req/s)
- Network bytes TX/RX

### Experimento 2: HTTPS con TLS
**Objetivo:** Medir overhead introducido por TLS  
**Guía:** [experiments/scenario-https.md](experiments/scenario-https.md)

**Métricas clave:**
- Overhead de latencia (%)
- Degradación de throughput (%)
- Incremento de CPU por cifrado
- Overhead de network bytes

---

## 🛠️ Requisitos

- MicroK8s instalado y corriendo
- kube-prom-stack desplegado (Prometheus + Grafana)
- k6 (se instala automáticamente)
- Python 3 (para análisis de resultados)

---

## 📚 Documentación Adicional

| Documento | Descripción |
|-----------|-------------|
| [CHANGES.md](CHANGES.md) | Changelog detallado de todos los cambios |
| [experiments/README.md](experiments/README.md) | Guía de experimentos |
| [experiments/scenario-http.md](experiments/scenario-http.md) | Escenario HTTP |
| [experiments/scenario-https.md](experiments/scenario-https.md) | Escenario HTTPS |
| [scripts/README.md](scripts/README.md) | Documentación de scripts |
| [Docs/Manual.md](Docs/Manual.md) | Manual original de muBench |

---

## 🔧 Troubleshooting

### Pods no arrancan

```bash
microk8s kubectl get pods -n default
microk8s kubectl describe pod <pod-name>
microk8s kubectl logs <pod-name>
```

### k6 no instalado

```bash
./scripts/install_k6.sh
```

### Métricas no en Prometheus

```bash
# Verificar annotations
microk8s kubectl get pod <pod-name> -o yaml | grep prometheus.io

# Test manual de /metrics
microk8s kubectl port-forward pod/<pod-name> 8080:8080
curl http://localhost:8080/metrics
```

### Certificados TLS inválidos

```bash
# Regenerar
rm -rf ~/muBench/tls-certs
microk8s kubectl delete secret s0-tls-secret s1-tls-secret sdb1-tls-secret
./scripts/deploy_microk8s.sh --start --protocol https
```

---

## ✅ Checklist de Validación

- [x] Comunicación s0 → s1 → sdb funciona
- [x] Endpoints /process, /validate, /query responden
- [x] Métricas en /metrics disponibles
- [x] Prometheus scraping automático funciona
- [x] Dashboard Grafana creado
- [x] k6 tests se ejecutan correctamente
- [x] Modo HTTP funciona
- [x] Modo HTTPS con TLS funciona
- [x] Certificados auto-firmados se generan
- [x] Probes readiness/liveness funcionan
- [x] Services usan ClusterIP
- [x] Script no rompe arquitectura original
- [x] Documentación completa creada

---

## 🎓 Explicación de Cambios por Archivo

### 1. ServiceCell/CellController-enhanced.py

**Cambios principales:**
- Añadidos endpoints `/process`, `/validate`, `/query`
- Implementadas métricas Prometheus `http_request_duration_seconds` y `http_requests_total`
- Soporte para variable `COMM_PROTOCOL` (http/https)
- Manejo de certificados TLS cuando HTTPS
- Probes `/health` y `/ready`
- Preservados endpoints originales de muBench

**Por qué:**
- Permite comunicación real entre servicios
- Métricas estándar para comparación con otras herramientas
- Flexibilidad HTTP/HTTPS sin recompilar

### 2. Deployers/K8sDeployer/Templates/DeploymentTemplate.yaml

**Cambios principales:**
- Añadido puerto 8443 para HTTPS
- Variable de entorno `COMM_PROTOCOL`
- Variable de entorno `NAMESPACE` (para DNS interno)
- Readiness probe en `/ready`
- Liveness probe en `/health`
- Placeholders para volumen TLS `{{TLS_VOLUME_MOUNT}}`

**Por qué:**
- Kubernetes necesita probes para health checks
- HTTPS requiere puerto dedicado
- Servicios necesitan conocer su namespace para DNS

### 3. Deployers/K8sDeployer/Templates/ServiceTemplate.yaml

**Cambios principales:**
- Tipo cambiado a `ClusterIP` (en vez de NodePort)
- Annotations Prometheus para auto-discovery
- Puerto 443 para HTTPS añadido

**Por qué:**
- ClusterIP es correcto para comunicación interna
- Annotations permiten que Prometheus encuentre pods automáticamente
- HTTPS necesita puerto 443 expuesto

### 4. Testing/baseline.js y inter-service-test.js

**Cambios principales:**
- Scripts k6 en JavaScript moderno
- Parametrizables vía environment variables
- Salida JSON para análisis programático
- Métricas personalizadas (error rate, duration)

**Por qué:**
- k6 es más moderno y mantenible que JMeter
- JSON permite análisis automático
- Parametrización facilita diferentes escenarios

### 5. scripts/deploy_microk8s.sh

**Cambios principales:**
- Función `generate_tls_certificates()` para HTTPS
- Función `check_k6()` y `run_k6_tests()` reemplaza JMeter
- Parámetro CLI `--protocol http|https`
- Dashboard Grafana mejorado
- Validación de protocolo

**Por qué:**
- Automatiza generación de certificados
- k6 es más fácil de automatizar que JMeter
- Protocolo configurable sin editar código
- UX mejorada con credenciales guardadas

---

## 🚀 Próximos Pasos (Opcional)

Mejoras futuras que podrían implementarse:

- [ ] Integración con Jaeger para distributed tracing completo
- [ ] mTLS (mutual TLS) para autenticación bidireccional
- [ ] Dashboard Grafana pre-configurado con import JSON
- [ ] CI/CD pipeline con tests automáticos
- [ ] Métricas TLS-específicas (handshake time, cipher suite)
- [ ] Comparación automática HTTP vs HTTPS con report HTML

---

## 📞 Soporte

Para problemas o preguntas:

1. Consultar [Troubleshooting](#-troubleshooting)
2. Revisar logs: `microk8s kubectl logs <pod-name>`
3. Ver documentación en `experiments/`
4. Verificar issues conocidos en [CHANGES.md](CHANGES.md)

---

**Última actualización:** 2026-02-11  
**Versión:** 2.0 (con comunicación inter-servicio HTTP/HTTPS)
