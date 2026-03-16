# Control 1: API Gateway para Tráfico Norte-Sur

## 📋 Descripción

Este experimento evalúa el overhead de rendimiento introducido por API Gateways en el tráfico norte-sur (externo → cluster Kubernetes).

### Controles CCM Lite
- **AIS-08:** API Security
- **I&S-03:** Network Security  
- **IAM-13:** Strong Authentication

### Objetivos de Seguridad
✅ Protección de APIs expuestas  
✅ Autenticación y autorización centralizada  
✅ Rate limiting y validación de requests  
✅ Logging y monitoreo centralizado

---

## 🏗️ Arquitectura

### Escenario 1: Baseline (Sin Gateway)
```
Cliente → k6
   ↓
NodePort (30080)
   ↓
Service s0 (ClusterIP) → Pod s0 → s1 → sdb1
```

### Escenario 2: Kong Gateway
```
Cliente → k6
   ↓
Kong Gateway (NodePort 30080)
   ├── Rate Limiting Plugin (100 req/s)
   ├── Key Auth Plugin
   └── Request Transformer
       ↓
Service s0 (ClusterIP) → Pod s0 → s1 → sdb1
```

### Escenario 3: NGINX Ingress
```
Cliente → k6
   ↓
NGINX Ingress Controller (NodePort 30080)
   ├── Rate Limiting (100 req/s)
   └── Basic Auth
       ↓
Service s0 (ClusterIP) → Pod s0 → s1 → sdb1
```

---

## 🎯 Hipótesis

**H1:** Kong introducirá mayor latencia que NGINX (+10-15%) debido a arquitectura de plugins  
**H2:** Ambos gateways reducirán throughput máximo en 5-10% vs baseline  
**H3:** Kong consumirá 2-3x más memoria que NGINX por arquitectura Lua  
**H4:** Gateway mejorará resiliencia bajo ataque (rate limiting efectivo)

---

## 📊 Variables

### Variable Independiente
**Tipo de Gateway:**
- E1: Sin Gateway (acceso directo NodePort)
- E2: Kong Gateway
- E3: NGINX Ingress Controller

### Variables Dependientes
| Métrica | Unidad | Objetivo |
|---------|--------|----------|
| Latencia adicional | ms | Minimizar |
| Throughput máximo | req/s | Maximizar |
| CPU Gateway | % | Minimizar |
| Memoria Gateway | MiB | Minimizar |
| Tasa de bloqueo RL | % | Verificar efectividad |

---

## 🚀 Procedimiento de Ejecución

### Pre-requisitos
```bash
# Verificar que servicios base estén corriendo
microk8s kubectl get pods -n default | grep -E "s0|s1|sdb1"

# Debe mostrar 3 pods en estado Running 1/1
```

### Experimento 1: Baseline (Sin Gateway)

```bash
cd /home/dwan13/muBench/experiments/01-api-gateway/baseline

# 1. Desplegar servicio con NodePort
./deploy-baseline.sh

# 2. Esperar a que esté listo
microk8s kubectl wait --for=condition=ready pod -l app=s0 --timeout=60s

# 3. Ejecutar test k6 (3 cargas × 3 repeticiones)
for vus in 10 25 50; do
  for rep in 1 2 3; do
    k6 run \
      -e TARGET_URL=http://localhost:30080/process \
      -e VUS=$vus \
      -e DURATION=5m \
      --out json=results/baseline-vus${vus}-rep${rep}.json \
      ../tests/baseline.js
    
    echo "Cooldown 10 minutos..."
    sleep 600
  done
done

# 4. Capturar snapshot de Prometheus
curl -G 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=up{job="kubernetes-pods"}' \
  > results/prometheus-baseline.json
```

### Experimento 2: Kong Gateway

```bash
cd /home/dwan13/muBench/experiments/01-api-gateway/kong

# 1. Instalar Kong
./install-kong.sh

# 2. Configurar routes y plugins
./configure-kong.sh

# 3. Verificar Kong está corriendo
microk8s kubectl get pods -n kong

# 4. Ejecutar tests k6
for vus in 10 25 50; do
  for rep in 1 2 3; do
    k6 run \
      -e TARGET_URL=http://localhost:30080/s0 \
      -e API_KEY=test-key-12345 \
      -e VUS=$vus \
      -e DURATION=5m \
      --out json=results/kong-vus${vus}-rep${rep}.json \
      ../tests/test-kong.js
    
    sleep 600
  done
done

# 5. Capturar métricas de Kong
curl http://localhost:30080/metrics > results/kong-metrics.txt
```

### Experimento 3: NGINX Ingress

```bash
cd /home/dwan13/muBench/experiments/01-api-gateway/nginx

# 1. Instalar NGINX Ingress
./install-nginx.sh

# 2. Aplicar configuración de rate limiting
microk8s kubectl apply -f rate-limit-config.yaml

# 3. Verificar NGINX está corriendo
microk8s kubectl get pods -n ingress-nginx

# 4. Ejecutar tests k6
for vus in 10 25 50; do
  for rep in 1 2 3; do
    k6 run \
      -e TARGET_URL=http://localhost:30080/s0 \
      -e VUS=$vus \
      -e DURATION=5m \
      --out json=results/nginx-vus${vus}-rep${rep}.json \
      ../tests/test-nginx.js
    
    sleep 600
  done
done

# 5. Capturar métricas de NGINX
curl http://localhost:30080/metrics > results/nginx-metrics.txt
```

---

## 📈 Análisis de Resultados

### Generar Comparativa

```bash
cd /home/dwan13/muBench/experiments/01-api-gateway

# Analizar todos los resultados
python3 analyze-gateway-overhead.py \
  --baseline baseline/results/*.json \
  --kong kong/results/*.json \
  --nginx nginx/results/*.json \
  --output gateway-comparison-report.pdf
```

### Métricas Clave a Reportar

**Tabla 1: Latencia por Configuración**
| Gateway | Latencia Avg (ms) | P95 (ms) | P99 (ms) | Overhead vs Baseline |
|---------|-------------------|----------|----------|----------------------|
| Baseline | - | - | - | - |
| Kong | - | - | - | - |
| NGINX | - | - | - | - |

**Tabla 2: Recursos del Gateway**
| Gateway | CPU (%) | Memoria (MiB) | Pods | Throughput (rps) |
|---------|---------|---------------|------|------------------|
| Kong | - | - | 2 | - |
| NGINX | - | - | 2 | - |

**Tabla 3: Efectividad de Rate Limiting**
| Gateway | Límite Config | Requests/s Real | Tasa 429 (%) | Efectividad |
|---------|---------------|-----------------|--------------|-------------|
| Kong | 100 rps | - | - | - |
| NGINX | 100 rps | - | - | - |

---

## 🧪 Tests de Validación

### Test 1: Rate Limiting Funciona
```bash
# Generar carga mayor al límite
k6 run -e VUS=150 -e DURATION=1m \
  -e TARGET_URL=http://localhost:30080/s0 \
  tests/stress-test-rl.js

# Debe mostrar errores 429 cuando se excede 100 rps
```

### Test 2: Autenticación Bloquea sin API Key
```bash
# Kong: request sin API key debe fallar
curl -X POST http://localhost:30080/s0/process

# Esperado: 401 Unauthorized
```

### Test 3: Gateway Agrega Headers
```bash
# Verificar headers añadidos por gateway
curl -v -X POST http://localhost:30080/s0/process \
  -H "apikey: test-key-12345"

# Debe mostrar headers como X-Kong-* o X-Request-ID
```

---

## 🔧 Troubleshooting

### Kong no inicia
```bash
# Ver logs
microk8s kubectl logs -n kong -l app=kong

# Problema común: Base de datos no lista
# Solución: Esperar a que PostgreSQL esté ready
microk8s kubectl wait --for=condition=ready pod -l app=postgresql -n kong
```

### NGINX retorna 503
```bash
# Verificar que backend service existe
microk8s kubectl get svc s0 -n default

# Verificar endpoints
microk8s kubectl get endpoints s0 -n default

# Ver logs de NGINX
microk8s kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx
```

### Rate Limiting no funciona
```bash
# Kong: Verificar que plugin está activo
curl http://localhost:8001/plugins | jq '.data[] | select(.name=="rate-limiting")'

# NGINX: Verificar anotaciones en Ingress
microk8s kubectl get ingress s0-ingress -o yaml | grep rate
```

---

## 📁 Estructura de Archivos

```
01-api-gateway/
├── README.md (este archivo)
├── baseline/
│   ├── deploy-baseline.sh
│   ├── service-nodeport.yaml
│   └── results/
├── kong/
│   ├── install-kong.sh
│   ├── configure-kong.sh
│   ├── kong-values.yaml
│   ├── kong-route.yaml
│   ├── kong-plugins.yaml
│   └── results/
├── nginx/
│   ├── install-nginx.sh
│   ├── ingress-s0.yaml
│   ├── rate-limit-config.yaml
│   └── results/
├── tests/
│   ├── baseline.js
│   ├── test-kong.js
│   ├── test-nginx.js
│   └── stress-test-rl.js
└── analyze-gateway-overhead.py
```

---

## ✅ Checklist de Ejecución

### Antes de empezar
- [ ] Servicios s0, s1, sdb1 corriendo
- [ ] Prometheus scraping activo
- [ ] k6 instalado y verificado
- [ ] Helm instalado (para Kong)
- [ ] Espacio en disco suficiente (>5GB para logs)

### Durante experimento
- [ ] Monitorear logs de Gateway en tiempo real
- [ ] Verificar que pods no se reinicien
- [ ] Capturar snapshots de Prometheus cada 5 min
- [ ] Anotar cualquier anomalía (timeouts, OOM kills)

### Después de experimentar
- [ ] Exportar resultados k6 a JSON
- [ ] Capturar métricas finales de Prometheus/Grafana
- [ ] Hacer backup de configuraciones YAML
- [ ] Documentar cualquier ajuste realizado
- [ ] Limpiar recursos (opcional):
  ```bash
  ./cleanup-all.sh
  ```

---

## 📊 Resultados Esperados (Preliminares)

Basado en benchmarks de industria:

**Latencia P95:**
- Baseline: ~45ms
- Kong: ~65ms (+44%)
- NGINX: ~52ms (+16%)

**Throughput:**
- Baseline: ~450 rps
- Kong: ~400 rps (-11%)
- NGINX: ~420 rps (-7%)

**Recursos:**
- Kong: ~40% CPU, 800 MiB RAM
- NGINX: ~15% CPU, 200 MiB RAM

---

**Control:** API Gateway (Norte-Sur)  
**Fecha:** Marzo 2026  
**Estado:** Listo para ejecución  
**Tiempo estimado:** 8 horas (3 escenarios × 9 runs + setup)
