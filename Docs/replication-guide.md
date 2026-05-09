# Guía de Replicación del Experimento muBench Scaling & Control Comparison

**Objetivo:** Reproducir exactamente el experimento 12-scenario × 4-VU del 9 de mayo de 2026 en cualquier máquina.

**Tiempo estimado:** 2-3 horas (primera vez), 1-1.5 horas (subsecuentes)

**Requiere:** Linux/macOS, Docker, Kubernetes, ~8GB RAM, ~10GB storage

---

## Parte 1: PREPARACIÓN DEL ENTORNO

### 1.1 Requisitos del Sistema

```bash
# Verificar SO
uname -a  # Linux o macOS

# Requisitos mínimos
CPU:      4 cores
RAM:      8GB disponible
Storage:  10GB libres
```

### 1.2 Instalación de Dependencias

#### **macOS (usando Homebrew)**
```bash
brew install docker kubectl k6 python3 git
brew install --cask docker  # Docker Desktop
```

#### **Ubuntu/Debian**
```bash
# Docker
curl -fsSL https://get.docker.com -o get-docker.sh && sudo sh get-docker.sh
sudo usermod -aG docker $USER
newgrp docker

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# k6
sudo apt-get update
sudo apt-get install -y golang-go
go install github.com/grafana/k6@latest
export PATH=$PATH:$(go env GOPATH)/bin

# Python3 & pip
sudo apt-get install -y python3 python3-pip
pip3 install requests pyyaml

# Git
sudo apt-get install -y git
```

#### **Verificar instalaciones**
```bash
docker --version          # Docker version 20.10+
kubectl version --client  # v1.24+
k6 version                # v0.43+
python3 --version         # 3.9+
git --version             # 2.30+
```

### 1.3 Clonar el Repositorio

```bash
cd ~/
git clone https://github.com/[usuario]/muBench.git
cd muBench
export MUBENCH_ROOT=$(pwd)
echo "MUBENCH_ROOT=$MUBENCH_ROOT" >> ~/.bashrc
source ~/.bashrc
```

### 1.4 Inicializar Kubernetes

#### **Opción A: Docker Desktop (Recomendado para macOS/Windows)**
```bash
# 1. Abrir Docker Desktop
# 2. Ir a Preferences → Kubernetes
# 3. Habilitar "Enable Kubernetes"
# 4. Esperar a que inicie (2-3 min)

# Verificar
kubectl get nodes
# Debería listar 1 nodo "docker-desktop"
```

#### **Opción B: Minikube (Linux/macOS)**
```bash
brew install minikube  # macOS
# O: https://minikube.sigs.k8s.io/docs/start/ (Linux)

minikube start --cpus=4 --memory=8192 --disk-size=20gb
eval $(minikube docker-env)  # Redirigir Docker a Minikube

# Verificar
kubectl get nodes
# Debería listar 1 nodo "minikube"
```

#### **Opción C: Kind (Kubernetes in Docker)**
```bash
brew install kind  # o instalar desde https://kind.sigs.k8s.io/

kind create cluster --name mubench --config - <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 30000
    hostPort: 30000  # Prometheus
  - containerPort: 30030
    hostPort: 30030  # Grafana
  - containerPort: 30080
    hostPort: 30080  # Services
EOF

kubectl config use-context kind-mubench
```

### 1.5 Crear Namespaces

```bash
# Namespace para microservicios
kubectl create namespace realistic-services

# Namespace para monitoreo
kubectl create namespace monitoring

# Verificar
kubectl get namespaces
```

---

## Parte 2: DESPLIEGUE DE SERVICIOS

### 2.1 Preparar Imágenes Docker

#### **Build local desde Dockerfile**
```bash
cd $MUBENCH_ROOT

# Construir imagen base (ServiceCell)
docker build -t mubench-servicecell:latest ./ServiceCell/

# Tag para Minikube/Kind (si usas)
# minikube image load mubench-servicecell:latest
# kind load docker-image mubench-servicecell:latest --name mubench
```

#### **O: Pull desde Docker Hub (si está disponible)**
```bash
docker pull mubench/servicecell:latest
docker tag mubench/servicecell:latest mubench-servicecell:latest
```

### 2.2 Desplegar Servicios Base

```bash
cd $MUBENCH_ROOT/RealisticServices/k8s

# Crear ConfigMaps para configuración
kubectl apply -f configmap-services.yaml -n realistic-services

# Desplegar 4 servicios
kubectl apply -f auth-service-deployment.yaml -n realistic-services
kubectl apply -f api-gateway-deployment.yaml -n realistic-services
kubectl apply -f data-service-deployment.yaml -n realistic-services
kubectl apply -f profile-service-deployment.yaml -n realistic-services

# Crear Services (LoadBalancer/NodePort)
kubectl apply -f services.yaml -n realistic-services

# Verificar rollout
kubectl rollout status deployment/auth-service -n realistic-services
kubectl rollout status deployment/api-gateway -n realistic-services
kubectl rollout status deployment/data-service -n realistic-services
kubectl rollout status deployment/profile-service -n realistic-services

# Verificar pods
kubectl get pods -n realistic-services
# Debería haber 8 pods (2 replicas × 4 servicios)
```

### 2.3 Validar Conectividad

```bash
# Port-forward para acceso local
kubectl port-forward svc/api-gateway 8080:80 -n realistic-services &

# Test simple
curl -X POST http://localhost:8080/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"testuser","password":"testpass"}'

# Debería retornar token o error controlado (no connection refused)
```

---

## Parte 3: INSTALACIÓN DE MONITOREO

### 3.1 Instalar Prometheus

```bash
cd $MUBENCH_ROOT

# Crear ConfigMap para prometheus.yml
kubectl create configmap prometheus-config \
  --from-file=Monitoring/prometheus.yml \
  -n monitoring

# Desplegar Prometheus
kubectl apply -f Monitoring/prometheus-deployment.yaml -n monitoring

# Esperar a que esté listo
kubectl rollout status deployment/prometheus -n monitoring

# Verificar
kubectl get pods -n monitoring
```

### 3.2 Instalar Grafana

```bash
# Crear PersistentVolume para Grafana (data)
kubectl apply -f Monitoring/grafana-pv.yaml

# Desplegar Grafana
kubectl apply -f Monitoring/grafana-deployment.yaml -n monitoring

# Esperar rollout
kubectl rollout status deployment/grafana -n monitoring

# Exponer en NodePort 30030
kubectl apply -f Monitoring/grafana-nodeport.yaml -n monitoring

# Verificar credenciales guardadas
kubectl get secret grafana-admin-secret -n monitoring -o jsonpath='{.data.password}' | base64 -d
```

### 3.3 Configurar ServiceMonitor (si usas Prometheus Operator)

```bash
# Si has instalado kube-prometheus-stack:
kubectl apply -f Add-on/Istio/servicemonitor-realistic.yaml -n realistic-services

# Si NO tienes operator, asegúrate que Prometheus scrape los servicios:
# Editar ConfigMap: kubectl edit configmap prometheus-config -n monitoring
# Agregar:
# - job_name: 'realistic-services'
#   kubernetes_sd_configs:
#   - role: pod
#     namespaces:
#       names:
#       - realistic-services
```

### 3.4 Acceder a Grafana

```bash
# Obtener IP/localhost y puerto
kubectl get service grafana -n monitoring

# URL: http://localhost:30030  (o IP:30030)
# Usuario: admin
# Contraseña: (obtenida del secret arriba, o default: admin)

# Si es primera vez: cambiar contraseña a:
# gjBgdk9aXrs2bCuZDnACjSry04I7my3ixPsqMoXi
```

---

## Parte 4: INSTALACIÓN DE CONTROLES (Control Framework)

### 4.1 Control C1: API Gateway

#### **C1-baseline: Sin control**
```bash
# No hace nada, solo servicios base
```

#### **C1-istio: Service Mesh con Istio**
```bash
# Instalar Istio
curl -L https://istio.io/downloadIstio | sh -
cd istio-*
export PATH=$PWD/bin:$PATH

# Instalar Istio en cluster
istioctl install --set profile=demo -y

# Inyectar sidecars en namespace
kubectl label namespace realistic-services istio-injection=enabled

# Reiniciar pods para que Istio inyecte sidecars
kubectl rollout restart deployment -n realistic-services

# Esperar
kubectl rollout status deployment -n realistic-services

# Validar sidecars
kubectl get pods -n realistic-services -o jsonpath='{.items[*].spec.containers[*].name}'
# Debería mostrar "istio-proxy" en cada pod
```

#### **C1-kong: API Gateway Kong**
```bash
# Instalar Kong Helm chart
helm repo add kong https://charts.konghq.com
helm repo update
helm install kong kong/kong -n kong --create-namespace \
  --set ingressController.enabled=true

# Crear Ingress para Kong
kubectl apply -f $MUBENCH_ROOT/Add-on/Kong/ingress-kong.yaml -n realistic-services

# Verificar Kong está listo
kubectl get pods -n kong
```

### 4.2 Control C2: mTLS & Service Mesh

#### **C2-baseline: Sin mTLS**
```bash
# Servicios con comunicación cleartext (default)
```

#### **C2-istio-mtls: Istio con mTLS**
```bash
# (Istio ya instalado del C1)

# Aplicar PeerAuthentication para forzar mTLS
kubectl apply -f $MUBENCH_ROOT/Add-on/Istio/peerauthentication-mtls-strict.yaml -n realistic-services

# Verificar
kubectl get peerauthentication -n realistic-services
```

#### **C2-linkerd-mtls: Linkerd Service Mesh**
```bash
# Instalar Linkerd
curl --proto '=https' --tlsv1.2 -sSfL https://run.linkerd.io/install | sh
export PATH=$PATH:~/.linkerd2/bin

linkerd install | kubectl apply -f -
linkerd inject -n realistic-services - < $MUBENCH_ROOT/RealisticServices/k8s/services.yaml | kubectl apply -f -

# mTLS automático en Linkerd
linkerd viz install | kubectl apply -f -
```

### 4.3 Control C3: Network Policies

#### **C3-baseline: Sin políticas**
```bash
# Default allow all
```

#### **C3-basic: Políticas básicas**
```bash
kubectl apply -f $MUBENCH_ROOT/Add-on/Topology-affinity/network-policy-basic.yaml -n realistic-services

# Verificar
kubectl get networkpolicy -n realistic-services
```

#### **C3-strict: Políticas estrictas**
```bash
kubectl apply -f $MUBENCH_ROOT/Add-on/Topology-affinity/network-policy-strict.yaml -n realistic-services

# Verificar
kubectl get networkpolicy -n realistic-services
```

### 4.4 Control C4: Rate Limiting

#### **C4-baseline: Sin límite**
```bash
# Default no-limit
```

#### **C4-moderate: Límite moderado (20 req/s)**
```bash
kubectl apply -f $MUBENCH_ROOT/Add-on/Kong/rate-limit-moderate.yaml -n realistic-services
# O si usas Istio:
kubectl apply -f $MUBENCH_ROOT/Add-on/Istio/rate-limit-moderate.yaml -n realistic-services
```

#### **C4-strict: Límite estricto (10 req/s)**
```bash
kubectl apply -f $MUBENCH_ROOT/Add-on/Kong/rate-limit-strict.yaml -n realistic-services
# O si usas Istio:
kubectl apply -f $MUBENCH_ROOT/Add-on/Istio/rate-limit-strict.yaml -n realistic-services
```

---

## Parte 5: PREPARACIÓN DE SCRIPTS DE PRUEBA

### 5.1 Verificar k6 está instalado

```bash
k6 version
# v0.43.0 o superior

# Si no: instalar
go install github.com/grafana/k6@latest
export PATH=$PATH:$(go env GOPATH)/bin
```

### 5.2 Preparar Test Script

```bash
# Verificar que existe el script
ls -l $MUBENCH_ROOT/RealisticServices/k6/realistic-flow.js

# Si no existe, crear desde template:
cat > $MUBENCH_ROOT/RealisticServices/k6/realistic-flow.js << 'EOF'
import http from 'k6/http';
import { check, sleep } from 'k6';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:30080';

export const options = {
  vus: parseInt(__ENV.VU_COUNT || '1'),
  duration: '60s',
  thresholds: {
    'http_req_duration': ['p(95)<5000'],
    'http_req_failed': ['rate<0.1'],
  },
};

export default function() {
  // Step 1: Login
  let loginRes = http.post(`${BASE_URL}/auth/login`, JSON.stringify({
    username: 'testuser',
    password: 'testpass'
  }), {
    headers: { 'Content-Type': 'application/json' },
    tags: { name: 'LoginRequest' }
  });
  
  check(loginRes, {
    'Login status 200': (r) => r.status === 200,
  });

  let token = loginRes.json('token');

  // Step 2: Get Profile
  let profileRes = http.get(`${BASE_URL}/api/profile`, {
    headers: { 'Authorization': `Bearer ${token}` },
    tags: { name: 'ProfileRequest' }
  });

  check(profileRes, {
    'Profile status 200': (r) => r.status === 200,
  });

  sleep(0);  // No think time
}
EOF
```

### 5.3 Preparar Script de Escalado

```bash
# Verificar que existe
ls -l $MUBENCH_ROOT/scripts/run-scaling-tests.sh

# Si no existe o necesita actualizar:
cat > $MUBENCH_ROOT/scripts/run-scaling-tests.sh << 'SCRIPT_EOF'
#!/bin/bash
set -e

MUBENCH_ROOT="${MUBENCH_ROOT:-.}"
RESULTS_DIR="$MUBENCH_ROOT/Testing/results/scaling_tests"
mkdir -p "$RESULTS_DIR"

# Arrays de controles y variantes
declare -A CONTROLS=(
  [C1]="baseline istio kong"
  [C2]="baseline istio-mtls linkerd-mtls"
  [C3]="baseline basic strict"
  [C4]="baseline moderate strict"
)

VU_STAGES=(1 5 10 20)
REPORT_DATE=$(date +%Y%m%d)
REPORT="$RESULTS_DIR/scaling-report_$REPORT_DATE.csv"

echo "control,variant,vus,avg_ms,p95_ms,err_pct,rps,cpu_mcores,mem_mib" > "$REPORT"

for control in C1 C2 C3 C4; do
  for variant in ${CONTROLS[$control]}; do
    for vus in "${VU_STAGES[@]}"; do
      echo "Testing: $control / $variant @ $vus VUs"
      
      # Aplicar control (manifest sería control-specific)
      kubectl apply -f "$MUBENCH_ROOT/Add-on/${control/_/-}/${variant}.yaml" -n realistic-services 2>/dev/null || true
      kubectl wait --for=condition=ready pod -l app=${variant} -n realistic-services --timeout=60s 2>/dev/null || true
      sleep 5

      # Ejecutar test
      K6_OUT=$(k6 run \
        --vus "$vus" \
        --duration "60s" \
        --out json="$RESULTS_DIR/k6-${control}-${variant}-${vus}.json" \
        "$MUBENCH_ROOT/RealisticServices/k6/realistic-flow.js" 2>&1)

      # Parsear k6 output (simplificado)
      AVG_MS=$(echo "$K6_OUT" | grep "avg=" | sed 's/.*avg=\([0-9.]*\).*/\1/')
      P95_MS=$(echo "$K6_OUT" | grep "p(95)=" | sed 's/.*p(95)=\([0-9.]*\).*/\1/')
      ERR_PCT=$(echo "$K6_OUT" | grep -o '[0-9.]*% http_req_failed' | head -1 | tr -d '%')
      RPS=$(echo "$K6_OUT" | grep "reqs/sec" | sed 's/.*\([0-9.]*\) reqs.*/\1/')

      # Query Prometheus para CPU/Memory
      CPU_MCORES=$(kubectl exec -n monitoring deploy/prometheus -- \
        curl -s 'http://localhost:9090/api/v1/query?query=container_cpu_usage_seconds_total' | jq '.[0]' 2>/dev/null || echo "0")
      MEM_MIB=$(kubectl exec -n monitoring deploy/prometheus -- \
        curl -s 'http://localhost:9090/api/v1/query?query=container_memory_usage_bytes' | jq '.[0]' 2>/dev/null || echo "0")

      # Escribir fila al CSV
      echo "$control,$variant,$vus,$AVG_MS,$P95_MS,$ERR_PCT,$RPS,$CPU_MCORES,$MEM_MIB" >> "$REPORT"
      
      sleep 2
    done
  done
done

echo "Report saved to: $REPORT"
SCRIPT_EOF

chmod +x "$MUBENCH_ROOT/scripts/run-scaling-tests.sh"
```

### 5.4 Preparar Script de Análisis

```bash
cp $MUBENCH_ROOT/scripts/generate-ranking-tables.py $MUBENCH_ROOT/scripts/generate-ranking-tables.py.backup

# (Ya debería estar presente, pero hacer backup)
```

---

## Parte 6: EJECUCIÓN DEL EXPERIMENTO

### 6.1 Pre-flight Checks

```bash
# 1. Verificar Kubernetes está corriendo
kubectl get nodes
# Debería listar al menos 1 nodo

# 2. Verificar servicios están listos
kubectl get pods -n realistic-services
# Debería haber 8 pods en estado Running

# 3. Verificar Prometheus scrape
curl http://localhost:30000/api/v1/query?query=up
# Debería retornar JSON con métricas

# 4. Verificar Grafana
curl -u admin:gjBgdk9aXrs2bCuZDnACjSry04I7my3ixPsqMoXi http://localhost:30030/api/health
# Debería retornar {"status":"ok"}

# 5. Test de conectividad con un servicio
kubectl port-forward svc/api-gateway 8080:80 -n realistic-services &
curl -X POST http://localhost:8080/auth/login -H "Content-Type: application/json" -d '{"username":"test","password":"test"}'
kill %1
```

### 6.2 Ejecutar Experimento Completo

```bash
cd $MUBENCH_ROOT

# Opción A: Script automático (recomendado)
bash scripts/run-scaling-tests.sh

# Tiempo esperado: 1.5-2 horas (12 controles × 4 VUs × ~10 min setup/test)
```

### 6.3 Monitoreo en Vivo

En otra terminal, puedes monitorear:

```bash
# Ver logs en vivo
kubectl logs -f -n realistic-services -l app=api-gateway --tail=50

# Monitorear CPU/Memory
watch -n 1 'kubectl top pods -n realistic-services'

# Ver estado del experimento
tail -f Testing/results/scaling_tests/scaling-report_*.csv
```

---

## Parte 7: POST-EXPERIMENT ANALYSIS

### 7.1 Generar Rankings

```bash
cd $MUBENCH_ROOT

python3 scripts/generate-ranking-tables.py > Testing/results/scaling_tests/ranking-analysis.txt

# Generar resumen con deltas
python3 scripts/generate-scaling-summary.py
```

### 7.2 Publicar Dashboards a Grafana

```bash
bash RealisticServices/publish-grafana-dashboard.sh

# Debería imprimir URLs:
# Realtime: http://localhost:30030/d/mubench-realistic-observability/...
# Comparison: http://localhost:30030/d/mubench-controls-tech-comparison/...
```

### 7.3 Visualizar Resultados

```bash
# CSV con datos brutos
cat Testing/results/scaling_tests/scaling-report_20260509.csv | head -10

# Rankings formateados
cat Testing/results/scaling_tests/ranking-analysis.txt

# Grafana UI
open http://localhost:30030  # macOS
# o: firefox http://localhost:30030  # Linux
```

---

## Parte 8: LIMPIAR RECURSOS

### 8.1 Mantener Cluster Limpio (después de experimento)

```bash
# Resetear a baseline
kubectl delete networkpolicy --all -n realistic-services
kubectl delete peerauthentication --all -n realistic-services
kubectl rollout restart deployment -n realistic-services

# Esperar
kubectl rollout status deployment -n realistic-services
```

### 8.2 Desmontar Todo (Cleanup completo)

```bash
# Eliminar namespace de servicios
kubectl delete namespace realistic-services

# Eliminar namespace de monitoreo
kubectl delete namespace monitoring

# Desinstalar Istio/Kong/Linkerd si fue instalado
# (depende de cómo fue instalado)

# Si usas Minikube/Kind
minikube delete  # o: kind delete cluster --name mubench
```

---

## Parte 9: TROUBLESHOOTING

### Problema: Pods no inician

```bash
# Verificar eventos
kubectl describe pod <pod-name> -n realistic-services

# Ver logs
kubectl logs <pod-name> -n realistic-services

# Solución más común: reiniciar deployment
kubectl rollout restart deployment/<service> -n realistic-services
```

### Problema: Prometheus no scrape métricas

```bash
# Verificar ConfigMap está correcto
kubectl get configmap prometheus-config -n monitoring -o yaml

# Editar si necesario
kubectl edit configmap prometheus-config -n monitoring

# Reiniciar Prometheus
kubectl rollout restart deployment/prometheus -n monitoring
```

### Problema: k6 no conecta a servicios

```bash
# Verificar DNS
kubectl run -it --rm debug --image=alpine -- nslookup api-gateway.realistic-services

# Port-forward para debug
kubectl port-forward svc/api-gateway 8080:80 -n realistic-services &
curl http://localhost:8080/health
kill %1

# Verificar firewall/network policies
kubectl get networkpolicy -n realistic-services
```

### Problema: Diferencias en resultados respecto a original

**Causas comunes:**
- Different hardware (CPU speed affects latency) → Normalizar por hardware
- Different Kubernetes version → Use same K8s version
- Different network latency → Run in same DC/cluster
- System load during test → Stop background processes
- Clock skew → Check NTP sync

**Validación:**
```bash
# Comparar CPU specs
kubectl describe node | grep -A 5 "Allocatable"

# Comparar métricas RPS scaling
grep "^[^,]*,[^,]*,[0-9]*," Testing/results/scaling_tests/scaling-report_*.csv | \
  awk -F, '{print $3, $7}' | sort | uniq -c
# RPS debe escalar linealmente (1:5:10:20)
```

---

## Parte 10: GUÍA RÁPIDA DE UNA LÍNEA

```bash
# Para hacerlo en una máquina con Docker/K8s ya instalado:
git clone https://github.com/[usuario]/muBench.git && \
cd muBench && \
kubectl create namespace realistic-services monitoring && \
kubectl apply -f RealisticServices/k8s/ -n realistic-services && \
kubectl apply -f Monitoring/ -n monitoring && \
kubectl apply -f Add-on/Istio/peerauthentication-mtls-strict.yaml -n realistic-services && \
bash scripts/run-scaling-tests.sh && \
python3 scripts/generate-ranking-tables.py
```

---

## Apéndice A: Variantes de Configuración

### Hardware Recomendado

| Scenario | CPU | RAM | Storage | Duration |
|----------|-----|-----|---------|----------|
| **Laptop (local)** | 4 cores | 8GB | 10GB SSD | 2-3 horas |
| **Desktop (dev)** | 8+ cores | 16GB | 50GB SSD | 1-1.5 horas |
| **Cloud VM** | 8 cores | 16GB | 50GB | 1 hora |
| **Production-like** | 16+ cores | 32GB | 200GB | 30 min |

### Variantes de K8s

| Platform | Pros | Cons | Commands |
|----------|------|------|----------|
| **Docker Desktop** | Easy setup, integrated | Resource heavy | Auto-start, no config |
| **Minikube** | Local, free | Slower | `minikube start` |
| **Kind** | Fast, containerized | Need Docker | `kind create cluster` |
| **EKS/GKE/AKS** | Production-like | Cost, complexity | Provider CLI |

---

**Documento actualizado:** May 9, 2026  
**Compatibilidad:** macOS 11+, Ubuntu 20.04+, Debian 11+, RHEL 8+  
**Mantener actualizado:** Revisar cuando Kubernetes versión bumps ocurran
