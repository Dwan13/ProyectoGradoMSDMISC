# Protocolo Cero Absoluto para muBench

## Objetivo

Ejecutar muBench desde un estado totalmente limpio y controlado, incluyendo:

1. Sistema base.
2. Herramientas de contenedores y cluster.
3. Librerias Python.
4. Limpieza de residuos locales.
5. Despliegue reproducible.
6. Validacion funcional y de observabilidad.

Este protocolo asume Linux Ubuntu 22.04+ (o equivalente Debian).

## 1. Stack tecnico consolidado

### 1.1 Tecnologias principales

- Kubernetes local: MicroK8s
- Contenedores: Docker + registry local de MicroK8s
- Orquestacion principal: scripts/deploy_microk8s.sh
- Pruebas de carga: k6
- Observabilidad: Prometheus + Grafana + Kubernetes Dashboard
- Backend realista: FastAPI + Postgres
- Lenguajes: Bash, Python, JavaScript (k6)

### 1.2 Librerias Python detectadas en el proyecto

Dependencias raiz (requirements.txt):

- kubernetes==18.20.0
- requests==2.26.0
- PyYAML==5.4.1
- python-igraph==0.9.6
- igraph==0.9.10
- websocket-client==1.2.1
- google-auth==2.1.0
- y complementarias del stack

Dependencias de RealisticServices:

- fastapi==0.115.0
- uvicorn==0.30.6
- PyJWT==2.9.0
- pydantic==2.9.2
- prometheus-client==0.21.0
- requests==2.32.3
- email-validator==2.2.0
- psycopg2-binary==2.9.9

## 2. Pre-requisitos de hardware

Minimo funcional:

- CPU: 6 vCPU
- RAM: 12 GB
- Disco libre: 30 GB

Recomendado:

- CPU: 8 vCPU+
- RAM: 16 GB
- Disco libre: 50 GB

## 3. Instalacion base del host

### 3.1 Paquetes de sistema

```bash
sudo apt update
sudo apt install -y \
  ca-certificates curl wget git jq unzip \
  python3 python3-pip python3-venv \
  docker.io snapd
```

### 3.2 Docker

```bash
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"
newgrp docker
```

Validar:

```bash
docker --version
```

Nota: si aparece warning por buildx faltante, el flujo puede funcionar con builder legacy. Si quieres eliminar ese warning:

```bash
sudo apt install -y docker-buildx-plugin || true
```

### 3.3 MicroK8s

```bash
sudo snap install microk8s --classic
sudo usermod -a -G microk8s "$USER"
newgrp microk8s
microk8s status --wait-ready
```

Habilitar addons necesarios:

```bash
microk8s enable dns storage ingress registry dashboard rbac
```

Alias opcional:

```bash
sudo snap alias microk8s.kubectl kubectl
kubectl version --client=true
```

### 3.4 k6

```bash
sudo gpg -k
sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg \
  --keyserver hkp://keyserver.ubuntu.com:80 \
  --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69

echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" | \
  sudo tee /etc/apt/sources.list.d/k6.list

sudo apt update
sudo apt install -y k6
k6 version
```

## 4. Cero absoluto real (limpieza completa)

Atencion: este bloque elimina estado local del cluster MicroK8s.

### 4.1 Matar residuos locales

```bash
pkill -f "kubectl.*port-forward" || true
pkill -f "microk8s kubectl.*port-forward" || true
```

### 4.2 Reset del cluster

```bash
microk8s reset
microk8s status --wait-ready
```

Rehabilitar addons despues del reset:

```bash
microk8s enable dns storage ingress registry dashboard rbac
```

### 4.3 Verificar estado limpio

```bash
microk8s kubectl get ns
microk8s kubectl get pods -A
```

Esperado: solo namespaces/pods base del sistema.

## 5. Obtener codigo desde cero

### Opcion A: clon limpio recomendado

```bash
mkdir -p "$HOME/labs"
cd "$HOME/labs"
git clone <URL_DEL_REPO_MUBENCH> mubench-clean
cd mubench-clean
```

### Opcion B: usar copia paralela local (ya creada)

```bash
cd /home/dwan13/muBench_desde_cero
./bootstrap_workspace.sh
cd /home/dwan13/muBench_desde_cero/workspace
```

## 6. Entorno Python del proyecto

```bash
cd /ruta/a/mubench
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip setuptools wheel
pip install -r requirements.txt
```

Nota: los microservicios realistas instalan sus dependencias dentro de sus imagenes Docker en build time.

## 7. Precheck automatizado (recomendado)

Desde el repo:

```bash
./scripts/zero_absolute_precheck.sh
```

Debe confirmar versiones y disponibilidad de:

- python3, pip, docker, microk8s, k6, jq, curl

## 8. Despliegue cero absoluto

```bash
cd /ruta/a/mubench
chmod +x scripts/deploy_microk8s.sh
chmod +x RealisticServices/*.sh
./scripts/deploy_microk8s.sh --start --hybrid-quick
```

## 9. Validaciones obligatorias post-despliegue

### 9.1 Pods base y realistic

```bash
microk8s kubectl get pods -n default
microk8s kubectl get pods -n realistic
```

Esperado en realistic: auth-service, api-service, data-service, postgres en 1/1 Running.

### 9.2 Salud de endpoints realistas

```bash
microk8s kubectl port-forward -n realistic svc/auth-service 18082:8080
microk8s kubectl port-forward -n realistic svc/api-service 18081:8080
```

En otra terminal:

```bash
curl -s http://127.0.0.1:18082/health
curl -s http://127.0.0.1:18081/health
```

### 9.3 Dashboards

- Grafana: http://localhost:3000
- Prometheus: http://localhost:9090
- Kubernetes Dashboard: https://localhost:10443

Token dashboard:

```bash
microk8s kubectl -n kube-system create token dashboard-admin
```

En Dashboard, seleccionar namespace realistic o All namespaces para ver los micros nuevos.

### 9.4 Artefactos de evidencia

```bash
ls -1t Testing/results/http-baseline-*.json | head
ls -1t Testing/results/http-interservice-*.json | head
ls -1t RealisticServices/results/k6-users-bulk-*.json | head
ls -1t RealisticServices/results/hybrid-k6-summary-*.txt | head
```

## 10. Criterio de exito de cero absoluto

Se considera logrado si se cumplen los 7 puntos:

1. Precheck sin errores.
2. Cluster reset y addons reactivados correctamente.
3. Despliegue --hybrid-quick termina en exit code 0.
4. Pods realistic en 1/1 Running.
5. k6 genera JSON de baseline, interservice y users-bulk.
6. Se genera hybrid-k6-summary-*.txt.
7. Dashboard/Grafana accesibles y consistentes con CLI.

## 11. Problemas comunes y solucion rapida

### 11.1 kubectl no encontrado

Usar siempre:

```bash
microk8s kubectl <comando>
```

### 11.2 No se ven pods en Dashboard

- Confirmar URL https://localhost:10443
- Cambiar namespace a realistic
- Limpiar filtros de busqueda
- Regenerar token

### 11.3 Port-forward inestable

```bash
pkill -f "kubectl.*port-forward" || true
```

Reintentar flujo o usar helper de reset paralelo:

```bash
/home/dwan13/muBench_desde_cero/reset_total.sh
```

### 11.4 Warning de buildx

No bloquea despliegue si docker build legacy funciona. Instalar plugin solo para eliminar warning.

## 12. Secuencia minima recomendada (copiar y ejecutar)

```bash
# 1) limpieza cluster
pkill -f "kubectl.*port-forward" || true
microk8s reset
microk8s status --wait-ready
microk8s enable dns storage ingress registry dashboard rbac

# 2) proyecto limpio (elige A o B)
# A) git clone limpio
# B) /home/dwan13/muBench_desde_cero/bootstrap_workspace.sh

# 3) precheck + deploy
cd /ruta/a/mubench
./scripts/zero_absolute_precheck.sh
./scripts/deploy_microk8s.sh --start --hybrid-quick

# 4) validar
microk8s kubectl get pods -n realistic
ls -1t RealisticServices/results/hybrid-k6-summary-*.txt | head
```
