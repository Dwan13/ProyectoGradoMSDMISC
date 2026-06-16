# EVALUACIÓN DEL IMPACTO DE CONTROLES DE SEGURIDAD DEFENSIVA ALINEADOS A CSA CCM LITE V4 SOBRE LA EFICIENCIA DE  DESEMPEÑO Y LA FIABILIDAD EN ARQUITECTURAS DE MICROSERVICIOS DESPLEGADAS EN KUBERNETES

Trabajo de grado que evalua el impacto en rendimiento de cuatro controles de seguridad aplicados a una arquitectura de microservicios realista desplegada en Kubernetes.

> Las imagenes de los servicios y algunas convenciones de nombres usan el prefijo `mubench` por dependencia historica con la infraestructura base del proyecto.

---

## Descripcion

Este proyecto mide la latencia, throughput y tasa de errores de una aplicacion de microservicios bajo diferentes configuraciones de seguridad. Cada experimento aisla una variable de seguridad (tipo de API gateway, mTLS, politicas de red, rate limiting) y compara tres niveles: sin control (baseline), control moderado y control estricto.

La carga de trabajo es un flujo CRUD completo sobre `/products` con autenticacion JWT, generado por k6 y ejecutado desde un orquestador bash que automatiza el ciclo completo: despliegue, validacion, calentamiento, prueba de carga, recoleccion de metricas y consolidacion de resultados.

---

## Arquitectura de Servicios

```
Cliente (k6)
    │
    └─► Gateway / Ingress (variable por experimento)
              │
              ├─► api-service  :8080   ─► auth-service :8080 ─► PostgreSQL :5432
              │                        └─► data-service :8080 ─► PostgreSQL :5432
              └─► auth-service :8080
```

**Servicios (FastAPI / Python)**

| Servicio | Puerto | Funcion |
|---|---|---|
| `api-service` | 8080 | Orquesta las operaciones CRUD, valida JWT con auth-service |
| `auth-service` | 8080 | Emite y valida tokens JWT, gestiona usuarios en PostgreSQL |
| `data-service` | 8080 | CRUD sobre la tabla `products` en PostgreSQL |
| `postgres` | 5432 | Base de datos compartida (tablas: `app_users`, `app_products`) |

---

## Experimentos

Cada experimento tiene tres configuraciones desplegadas en namespaces independientes con su propio PostgreSQL y certificado TLS.

### C1 — API Gateway

Compara el impacto en rendimiento de tres mecanismos de ingress.

| Variante | Namespace | Puerto | Notas |
|---|---|---|---|
| `baseline` | `realistic-nginx` | 32167 | Nginx Ingress con reescritura de path |
| `kong` | `realistic-kong` | 30443 | Kong Ingress con soporte de plugins |
| `istio` | `realistic-istio` | 32012 | Istio Gateway + VirtualService, sidecar Envoy |

### C2 — mTLS (Service Mesh)

Mide el overhead del cifrado mutuo TLS entre servicios.

| Variante | Namespace | Puerto | Notas |
|---|---|---|---|
| `baseline` | `realistic-without-mtls` | 32167 | HTTP plano, sin sidecar |
| `istio-mtls` | `realistic-istio-mtls` | 32012 | PeerAuthentication STRICT, certificados SPIFFE |
| `linkerd-mtls` | `realistic-linkerd-mtls` | 32167 | mTLS automatico, proxy Linkerd (Rust) |

### C3 — Network Policies

Evalua el costo de la micro-segmentacion de red via CNI.

| Variante | Namespace | Puerto | Notas |
|---|---|---|---|
| `baseline` | `realistic-without-network-policies` | 32167 | Sin politicas, trafico libre |
| `basic` | `realistic-basic-network-policies` | 32167 | 4 politicas, deny-all + allow intra-namespace |
| `strict` | `realistic-strict-network-policies` | 32167 | 9 politicas, minimo privilegio por servicio |

### C4 — Rate Limiting

Mide el impacto del throttling por IP en el ingress Nginx.

| Variante | Namespace | Puerto | Notas |
|---|---|---|---|
| `baseline` | `realistic-without-rate-limiting` | 32167 | Sin limite de peticiones |
| `moderate` | `realistic-moderate-rate-limiting` | 32167 | 1200 rpm por IP (20 req/seg) |
| `strict` | `realistic-strict-rate-limiting` | 32167 | 300 rpm por IP (5 req/seg) |

---

## Estructura del Repositorio

```
ProyectoGradoMSDMISC/
├── experiments/                        # Manifiestos Kubernetes por experimento
│   ├── 01-api-gateway-realistic/
│   │   ├── baseline/                   # namespace/ + ingress nginx
│   │   ├── kong/                       # namespace/ + ingress kong
│   │   └── istio/                      # namespace/ + gateway + virtualservice
│   ├── 02-mtls-service-mesh-realistic/
│   ├── 03-network-policies-realistic/
│   ├── 04-rate-limiting-realistic/
│   └── attack-vectors/                 # Validación de vectores de ataque (post-defensa)
│       ├── validate-c3-lateral-movement.sh   # C3: kubectl exec → postgres pivot + cross-ns
│       ├── validate-c4-brute-force.sh        # C4: 500 curl paralelos → brute force
│       ├── c4-brute-force-k6.js              # C4: versión k6 con métricas detalladas
│       └── run-attack-validation.sh          # Wrapper: corre C3 + C4 en secuencia
│
├── RealisticServices/                  # Codigo fuente de los microservicios
│   ├── api-service/                    # FastAPI: orquestacion CRUD + JWT
│   ├── auth-service/                   # FastAPI: login + validacion JWT
│   ├── data-service/                   # FastAPI: CRUD /products sobre PostgreSQL
│   ├── k6/
│   │   └── realistic-crud-flow.js      # Script k6: flujo CRUD completo
│   └── (manifiestos K8s por escenario en experiments/0X-*-realistic/)
│
├── scripts/                            # Herramientas de orquestacion y analisis
│   ├── run-crud-experiment.sh          # ORQUESTADOR PRINCIPAL
│   ├── run-crud-full-grid.sh            # Loop factorial (VUS × controles × variantes)
│   ├── anova_overhead.py                # Análisis Kruskal-Wallis + ε²
│   ├── build_overhead_report.py         # Genera capítulo LaTeX + boxplots
│   ├── keep-portforwards.sh
│   └── monitoring-up.sh / monitoring-down.sh
│
├── Testing/                            # Resultados experimentales
│   └── results/auto_runs/              # Salida del orquestador (generada)
│       └── crud_vusN_nM_TIMESTAMP/
│           ├── results.csv             # Consolidado final
│           ├── resource_metrics.csv    # CPU/mem por replica
│           ├── invalid-scenarios.csv   # Escenarios que fallaron smoke check
│           ├── summaries/              # JSON k6 por replica
│           ├── logs/                   # stdout k6 por replica
│           └── state/                  # Dumps YAML del cluster
│
└── diagramas Experimentos/             # Diagramas PlantUML del proyecto
    ├── 00-orquestador/                 # Arquitectura del orquestador y k6
    ├── 01-api-gateway/
    ├── 02-mtls-service-mesh/
    ├── 03-network-policies/
    └── 04-rate-limiting/
```

---

## Requisitos

### Hardware mínimo

| Recurso | Mínimo | Recomendado |
|---|---|---|
| CPU | 4 vCPU | 8 vCPU |
| RAM | 8 GB | 16 GB |
| Disco | 30 GB libres | 60 GB libres (SSD) |

La campaña completa (12 escenarios × 4 niveles de VUS × 8 réplicas = 384 reps, ~20s c/u + setup) toma aproximadamente **6–10 horas** según el hardware. El experimento es CPU-bound durante la carga de k6 y disk-bound durante los rollouts.

### Sistema operativo

Validado en **Ubuntu 22.04 LTS** (también compatible con WSL2 + Ubuntu si se usa MicroK8s nativo de Linux).

### Software base

Las versiones listadas son las **probadas y validadas**. Versiones más recientes pueden funcionar pero NO garantizan reproducibilidad (cambios de CRDs en Istio/Linkerd, renombrado de Services en charts de Kong, etc.).

| Herramienta | Versión fijada | Instalación |
|---|---|---|
| MicroK8s | **1.28/stable** | `sudo snap install microk8s --classic --channel=1.28/stable` |
| CNI (auto con MicroK8s 1.28) | **Calico v3.26** | habilitado por defecto — **OBLIGATORIO** para C3 |
| k6 | **≥ 0.49** | `bash scripts/install_k6.sh` |
| Python | **3.10–3.12** | nativo en Ubuntu 22.04 |
| Docker | **24.x** | `sudo apt install docker.io` |
| Istio CLI (`istioctl`) | **1.20.0 exacto** | `curl -L https://istio.io/downloadIstio \| ISTIO_VERSION=1.20.0 sh -` |
| Linkerd CLI (`linkerd`) | **stable-2.14.10** | `curl --proto '=https' -sSfL https://run.linkerd.io/install \| LINKERD2_VERSION=stable-2.14.10 sh` |
| Kong Helm chart | **2.38.0 exacto** | `helm install kong kong/kong --version 2.38.0` |
| Helm | **≥ 3.13** | `sudo snap install helm --classic` |
| `jq` | cualquiera | `sudo apt install jq` |

> **CNI → NetworkPolicies.** MicroK8s 1.28 trae Calico por defecto, que es el único CNI listado en la matriz oficial de Kubernetes con enforcement completo de `NetworkPolicy`. Si reemplazas el CNI por flannel, **los escenarios de C3/strict pasarán los tests sin bloquear realmente** (falso negativo silencioso). `scripts/preflight-check.sh` lo verifica automáticamente.

---

## Garantía de reproducibilidad

La reproducibilidad de este experimento es **estadística, no determinística run-by-run**. Cumplir las condiciones mínimas del entorno NO es suficiente por sí solo: existen 8 fuentes documentadas de variabilidad que el pipeline mitiga, pero ninguna sola ejecución de una réplica está garantizada.

### Fuentes de variabilidad mitigadas automáticamente

| # | Riesgo | Mitigación automática | Verificable con |
|---|---|---|---|
| 1 | Readiness probes en timeout tras `kubectl apply` | `wait_rollout` estricto (240s + 120s pods Ready) | logs del orquestador |
| 2 | Sidecar mTLS no inyectado en pods preexistentes | `ensure_sidecars` reinicia deployments si falta `istio-proxy`/`linkerd-proxy` | `kubectl get pods -o yaml` |
| 3 | NetworkPolicies aceptadas pero no enforced (CNI flannel) | `preflight-check.sh` valida CNI = Calico/Cilium | `scripts/preflight-check.sh` |
| 4 | Imagen no publicada en registry local | preflight verifica `/v2/_catalog` + tag `v1` por servicio | preflight |
| 5 | Host virtual no resuelve | preflight verifica los 11 hosts en `/etc/hosts` | preflight (con `--fix`) |
| 6 | Rollback de versión de Istio/Linkerd/Kong | versiones fijadas exactas en la tabla anterior | `istioctl version`, `linkerd version` |
| 7 | Cachés/JIT/pool de conexiones fríos | `WARMUP=10s` por defecto antes de cada réplica | logs (`warmup done (N requests)`) |
| 8 | Recursos del host bajo presión | preflight verifica RAM ≥ 4 GB libres, load < nCPUs | preflight |

### Validaciones por control (en cada escenario, antes de medir)

El orquestador ejecuta `validate_control()` después del rollout y antes del smoke test. Si la validación falla, el escenario se omite y se anota en `invalid-scenarios.csv` con la razón exacta:

| Control | Invariante verificada | Acción si falla |
|---|---|---|
| **C1** | Ingress responde 200 a `/auth/login` (smoke) | omite escenario, reason=`smoke_failed` |
| **C2** (istio/linkerd-mtls) | Sidecar `istio-proxy`/`linkerd-proxy` presente en todos los pods del namespace + `PeerAuthentication mode=STRICT` (Istio) | reinicia deployments y reintenta; si persiste → `control_validation_failed` |
| **C3** (basic/strict) | `kubectl get netpol` devuelve ≥ 1 política activa en el namespace | omite escenario, reason=`control_validation_failed` |
| **C4** (moderate/strict) | Annotation `nginx.ingress.kubernetes.io/limit-rpm` presente en el Ingress | advertencia (no aborta, métrica de 429s lo verifica post-hoc) |

### Replicación estadística

La matriz por defecto usa **8 réplicas × 4 niveles VUS × 12 escenarios = 384 réplicas**. Esto absorbe outliers transitorios (1–2 réplicas anomalas no cambian el resultado del Kruskal-Wallis con α=0.05). Si una réplica individual falló, queda registrada en `invalid-scenarios.csv` y el análisis estadístico la excluye explícitamente.

### Procedimiento blindado

```bash
# 1. Verifica entorno (aborta si algo crucial falta)
bash scripts/preflight-check.sh --fix

# 2. Smoke run obligatorio: 1 escenario, 1 réplica, 10s — valida pipeline
bash scripts/run-crud-experiment.sh --scenario C1 --vus 1 --replicas 1 --duration 10s

# 3. Campaña completa (grid corre preflight de nuevo internamente)
nohup bash scripts/run-crud-full-grid.sh > /tmp/crud-full-grid.log 2>&1 &
```

Si cualquiera de los 3 pasos falla, NO continúes a los siguientes — el origen del fallo debe corregirse antes para preservar la validez interna de las mediciones.

---

## Replicación paso a paso

> Todos los comandos se ejecutan desde la raíz del repositorio. Asume usuario con `sudo` y que `microk8s` está agregado al grupo del usuario (`sudo usermod -a -G microk8s $USER && newgrp microk8s`).

### Paso 1 — Clonar el repositorio

```bash
git clone https://github.com/Dwan13/ProyectoGradoMSDMISC.git
cd ProyectoGradoMSDMISC
```

### Paso 2 — Provisionar MicroK8s

```bash
sudo snap install microk8s --classic --channel=1.28/stable
sudo usermod -a -G microk8s $USER
newgrp microk8s

# Habilitar addons necesarios
microk8s enable dns
microk8s enable ingress
microk8s enable metrics-server
microk8s enable registry            # registry local en localhost:32000
microk8s enable hostpath-storage    # PVCs para PostgreSQL
microk8s enable observability       # Prometheus + Grafana + kube-state-metrics

# Esperar a que todo esté Ready
microk8s status --wait-ready
```

### Paso 3 — Instalar service meshes e ingress alternativos

```bash
# Istio (necesario para C1/istio y C2/istio-mtls)
curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.20.0 sh -
cd istio-1.20.0 && sudo cp bin/istioctl /usr/local/bin/ && cd ..
istioctl install --set profile=demo -y

# Linkerd (necesario para C2/linkerd-mtls)
curl --proto '=https' --tlsv1.2 -sSfL https://run.linkerd.io/install | sh
export PATH=$HOME/.linkerd2/bin:$PATH
linkerd check --pre
linkerd install --crds | microk8s kubectl apply -f -
linkerd install | microk8s kubectl apply -f -
linkerd check

# Kong Ingress Controller (necesario para C1/kong)
microk8s helm3 repo add kong https://charts.konghq.com
microk8s helm3 repo update
microk8s helm3 install kong kong/kong -n kong --create-namespace \
  --set ingressController.installCRDs=false
```

### Paso 4 — Instalar k6 y dependencias Python

```bash
# k6 (cliente de carga)
bash scripts/install_k6.sh

# Python: solo se necesitan numpy, pandas, scipy, matplotlib para los reportes
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install numpy pandas scipy matplotlib
```

### Paso 5 — Construir y publicar imágenes en el registry local

Los 3 microservicios (`api-service`, `auth-service`, `data-service`) usan el mismo Dockerfile (FastAPI sobre Python 3.11-slim) y se sirven desde `localhost:32000/mubench/<servicio>:v1`.

```bash
for svc in api-service auth-service data-service; do
  docker build -t localhost:32000/mubench/${svc}:v1 RealisticServices/${svc}/
  docker push localhost:32000/mubench/${svc}:v1
done
```

Verifica:

```bash
curl -s http://localhost:32000/v2/_catalog
# Esperado: {"repositories":["mubench/api-service","mubench/auth-service","mubench/data-service"]}
```

### Paso 6 — Registrar los hosts virtuales en `/etc/hosts`

Cada escenario usa un host TLS distinto para evitar colisión de Ingress. Agrega de una vez:

```bash
sudo tee -a /etc/hosts <<'EOF'
127.0.0.1  realistic.local
127.0.0.1  realistic-istio.local
127.0.0.1  realistic-istio-mtls.local
127.0.0.1  realistic-without-mtls.local
127.0.0.1  realistic-linkerd-mtls.local
127.0.0.1  realistic-without-network-policies.local
127.0.0.1  realistic-basic-network-policies.local
127.0.0.1  realistic-strict-network-policies.local
127.0.0.1  realistic-without-rate-limiting.local
127.0.0.1  realistic-moderate-rate-limiting.local
127.0.0.1  realistic-strict-rate-limiting.local
EOF
```

> Si el cluster corre en otra máquina, reemplaza `127.0.0.1` por la IP del nodo.

### Paso 7 — Levantar el stack de observabilidad (opcional pero recomendado)

```bash
bash scripts/monitoring-up.sh
```

Esto escala Grafana, Prometheus y el K8s Dashboard a 1 réplica y abre port-forwards:

- Grafana → http://localhost:3000  (admin / `microk8s kubectl -n monitoring get secret prometheus-grafana -o jsonpath='{.data.admin-password}' | base64 -d`)
- Prometheus → http://localhost:9090
- Dashboard → https://localhost:10443  (token en `/tmp/dash-token.txt`)

Para mantener los port-forwards vivos durante runs largos:

```bash
nohup bash scripts/keep-portforwards.sh > /tmp/pf-keeper.log 2>&1 &
```

Apagar al terminar:

```bash
bash scripts/monitoring-down.sh
```

### Paso 8 — Preflight check (OBLIGATORIO antes de medir)

Valida que las 8 fuentes de variabilidad documentadas en "Garantía de reproducibilidad" estén controladas. **No saltes este paso**: sin preflight verde, los resultados no son comparables con los de la tesis.

```bash
bash scripts/preflight-check.sh          # solo valida
bash scripts/preflight-check.sh --fix    # corrige /etc/hosts automáticamente
```

Salida esperada: `✓ Entorno LISTO para ejecutar el experimento` y `Fallos críticos: 0`. Si reporta fallos, corrígelos antes de continuar; las advertencias son informativas (p.ej. Linkerd ausente solo importa si vas a correr C2/linkerd-mtls).

### Paso 9 — Smoke test (1 escenario, 1 réplica)

Antes de la campaña completa, valida que todo funciona con un solo escenario:

```bash
bash scripts/run-crud-experiment.sh \
  --scenario kong \
  --vus 5 \
  --replicas 1 \
  --duration 20s
```

Salida esperada: `[ ok ]` en cada paso (apply manifests → rollout → smoke → k6 → metrics). Resultados en `Testing/results/auto_runs/crud_vus5_n1_<TIMESTAMP>/`.

Si falla, revisa:
- `kubectl get pods -A | grep -v Running` (pods no listos)
- `Testing/results/auto_runs/.../invalid-scenarios.csv` (motivo del rechazo)
- `Testing/results/auto_runs/.../logs/*.log` (output crudo de k6)

### Paso 10 — Ejecutar la campaña completa (matriz factorial)

```bash
nohup bash scripts/run-crud-full-grid.sh > /tmp/crud-full-grid.log 2>&1 &
tail -f /tmp/crud-full-grid.log
```

**Matriz por defecto**: 4 controles × 3 variantes × 4 niveles VUS (1, 5, 10, 20) × 8 réplicas = **384 reps**, ~20s c/u.

Override de parámetros vía env vars:

```bash
REPLICAS=5 DURATION=30s VUS_LEVELS="1 5 10 20 50" \
  bash scripts/run-crud-full-grid.sh
```

Salida consolidada en `Testing/results/auto_runs/crud_grid_<TIMESTAMP>/`:

- `results_all.csv` — un row por réplica con latencias, throughput, checks
- `resource_metrics_all.csv` — CPU/mem por pod después de cada réplica
- `grid.log` — log maestro del grid

### Paso 11 — Generar análisis estadístico y reporte

```bash
# Análisis Kruskal-Wallis + tamaño de efecto (ε²)
python3 scripts/anova_overhead.py \
  Testing/results/auto_runs/crud_grid_<TIMESTAMP>/results_all.csv

# Reporte LaTeX con boxplots PNG/PDF
python3 scripts/build_overhead_report.py \
  --input Testing/results/auto_runs/crud_grid_<TIMESTAMP>/results_all.csv \
  --output Testing/results/auto_runs/crud_grid_<TIMESTAMP>/report/
```

### Ejecución dirigida (subconjuntos)

```bash
# Un control completo
bash scripts/run-crud-experiment.sh --scenario C2

# Una variante específica
bash scripts/run-crud-experiment.sh --scenario istio-mtls

# Con warmup (recomendado para mediciones definitivas)
bash scripts/run-crud-experiment.sh --vus 20 --replicas 5 --duration 60s --warmup 30
```

### Parámetros del orquestador

| Parámetro | Por defecto | Descripción |
|---|---|---|
| `--vus` | 20 | Virtual Users concurrentes en k6 |
| `--replicas` | 5 | Repeticiones por escenario (para significancia estadística) |
| `--duration` | `60s` | Duración de cada run k6 |
| `--warmup` | 0 | Segundos de tráfico previo para estabilizar caches |
| `--scenario` | (todos) | Filtro por nombre parcial (ej: `kong`, `C2`, `istio-mtls`) |

---

## Validación de Vectores de Ataque

Esta sección documenta la validación funcional de C3 y C4 mediante ataques controlados en el entorno de laboratorio. Su propósito es demostrar que cada control **bloquea efectivamente las amenazas que afirma mitigar**, complementando las métricas de rendimiento con evidencia de efectividad de seguridad.

Los scripts viven en `experiments/attack-vectors/` y están diseñados para ejecutarse sobre los mismos namespaces del experimento principal, sin necesidad de infraestructura adicional.

### Prerrequisitos

- Los namespaces objetivo ya están desplegados (`kubectl get pods -A | grep realistic`)
- `curl` disponible en el sistema (WSL o Linux nativo)
- `k6` instalado (solo para la variante k6 de C4)
- Los hosts `*.local` resuelven a `127.0.0.1` (Paso 6 completado)

### Ejecución rápida

```bash
# Ambos controles en secuencia (C3 + C4)
bash experiments/attack-vectors/run-attack-validation.sh

# Solo C3
bash experiments/attack-vectors/run-attack-validation.sh --c3

# Solo C4
bash experiments/attack-vectors/run-attack-validation.sh --c4
```

Los resultados se guardan en `experiments/attack-vectors/attack-results/<TIMESTAMP>/`.

---

### C3 — Network Policies: Movimiento Lateral

**Script:** `experiments/attack-vectors/validate-c3-lateral-movement.sh`

**Amenaza modelada:** Un atacante compromete el pod `api-service` mediante explotación remota (RCE) y desde allí intenta pivotar hacia otros recursos no autorizados del cluster (MITRE ATT&CK T1210, CWE-284).

#### Vector 1 — Pivoting a la base de datos

Desde el pod `api-service` comprometido, el atacante intenta una conexión TCP directa a `postgres:5432` para exfiltrar datos sin pasar por `data-service`.

```bash
# El script ejecuta internamente algo equivalente a:
kubectl -n <namespace> exec <api-service-pod> -- python3 -c "
import socket, sys
s = socket.socket(); s.settimeout(5)
s.connect(('postgres', 5432))   # si conecta: ataque exitoso
"
```

| Variante | Resultado esperado | Razón |
|---|---|---|
| **Baseline** | `CONNECT_OK` — VULNERABLE | Sin NetworkPolicy; tráfico libre |
| **Basic** | `CONNECT_OK` — VULNERABLE | `allow-intra-namespace` permite todo el tráfico intra-ns |
| **Strict** | `CONNECT_FAIL` (timeout) — PROTEGIDO | `api-egress` solo permite puerto 8080 a `auth-service` y `data-service`; `postgres:5432` es inalcanzable |

> El timeout (5s) en Strict es comportamiento correcto: Kubernetes NetworkPolicy hace **DROP** de paquetes (no REJECT), lo que produce timeout a nivel TCP en lugar de `connection refused`. Esto confirma que el bloqueo ocurre en el kernel (eBPF/netfilter vía CNI Calico), no en la aplicación.

#### Vector 2 — Acceso cross-namespace

Desde un pod en el namespace `default` (simula el compromiso de otra aplicación en el mismo cluster), el atacante intenta alcanzar `data-service` del namespace objetivo.

| Variante | Resultado esperado | Razón |
|---|---|---|
| **Baseline** | `CONNECT_OK` — VULNERABLE | Sin NetworkPolicy; cualquier pod del cluster accede |
| **Basic** | `CONNECT_FAIL` — PROTEGIDO | `default-deny-all` bloquea todo ingress externo al namespace |
| **Strict** | `CONNECT_FAIL` — PROTEGIDO | Ídem; además solo `api-service` puede hablar con `data-service` |

#### Ejecución manual (por variante)

```bash
bash experiments/attack-vectors/validate-c3-lateral-movement.sh
```

Salida esperada (fragmento de Strict):

```
  ▷ Test: api-service → postgres:5432  [STRICT]
  Resultado: [BLOQUEADO] postgres:5432 – timed out
  ✔ PROTEGIDO – NetworkPolicy bloquea el acceso api-service → postgres:5432
```

---

### C4 — Rate Limiting: Fuerza Bruta / Credential Stuffing

**Scripts:**
- `experiments/attack-vectors/validate-c4-brute-force.sh` — versión curl (500 requests paralelos)
- `experiments/attack-vectors/c4-brute-force-k6.js` — versión k6 (más detalle de métricas)

**Amenaza modelada:** Un atacante automatizado envía solicitudes de autenticación masivas contra `POST /auth/login` desde una sola IP, intentando adivinar credenciales (OWASP OAT-007 Credential Cracking / OAT-008 Credential Stuffing, CWE-307).

#### Ejecución con curl (recomendada para demo rápida)

```bash
# Configurable: número de requests y puerto
REQUESTS=500 CLUSTER_PORT=32167 bash experiments/attack-vectors/validate-c4-brute-force.sh
```

El script dispara 500 `curl` en background simultáneamente (sin delay) y clasifica cada respuesta:

| Código HTTP | Clasificación | Significado |
|---|---|---|
| `200` / `401` | Procesados | El intento llegó al backend |
| `503` + body HTML (`nginx`) | `ratelimit_503` | **Control C4 activo** — NGINX rechazó antes del backend |
| `503` + body JSON | `backend_503` | Fallo de fiabilidad — **no confundir con bloqueo del control** |

Resultados esperados con 500 requests:

| Variante | Procesados | Rate-limit 503 | Tasa de bloqueo |
|---|---|---|---|
| **Baseline** | ~500 | 0 | 0% — VULNERABLE |
| **Moderate** | variable | variable | parcial (límite 1200 rpm) |
| **Strict** | ~300 (burst) | >200 | >40% — PROTEGIDO |

#### Ejecución con k6 (recomendada para métricas de tesis)

```bash
# Baseline (sin rate limiting)
k6 run -e TARGET=without-rate-limiting -e PORT=32167 -e VUS=5 -e DURATION=20s \
  experiments/attack-vectors/c4-brute-force-k6.js

# Strict (300 rpm)
k6 run -e TARGET=strict-rate-limiting  -e PORT=32167 -e VUS=5 -e DURATION=20s \
  experiments/attack-vectors/c4-brute-force-k6.js
```

El resumen k6 separa explícitamente `ratelimit_503` (control C4) de `backend_503` (fiabilidad):

```
 Total requests:                      3000
 Llegaron al backend     (200/401):    280
 Bloqueados por NGINX RL (503 HTML):  2715   ← control C4
 Fallos de backend       (503 JSON):     5   ← fiabilidad (≠ C4)
 Tasa de bloqueo (control C4):       90.5%
```

#### Distinción 503 rate-limit vs 503 backend

La distinción es necesaria para no atribuir fallos de fiabilidad como efectividad del control:

| Característica | 503 Rate-limit (NGINX) | 503 Backend failure |
|---|---|---|
| **Origen** | NGINX rechaza antes de llegar al pod | El pod/servicio devuelve error |
| **Body** | HTML: `<center>nginx</center>` | JSON: `{"detail":"..."}` |
| **Content-Type** | `text/html` | `application/json` |
| **Latencia típica** | 1–3 ms | 10–50 ms |
| **Métrica asociada** | Efectividad de seguridad (C4) | Fiabilidad (ISO/IEC 25010) |

El script lo verifica con `grep -qi "nginx"` sobre el body de cada respuesta 503.

---

## Troubleshooting

| Síntoma | Diagnóstico | Solución |
|---|---|---|
| `image pull backoff` | El nodo no resuelve `localhost:32000` | Verifica `microk8s enable registry` y que las imágenes estén publicadas (`curl localhost:32000/v2/_catalog`) |
| Pods Istio sin sidecar | Falta label en el namespace | El orquestador inyecta `istio-injection=enabled` automáticamente; si falla manual: `kubectl label ns <ns> istio-injection=enabled --overwrite` |
| `connection refused` en k6 | El Ingress aún no está listo | El orquestador hace smoke test antes de cada run; revisa `kubectl get pods -n ingress` |
| Rollouts con timeout | Recursos insuficientes | Aumenta RAM del host o reduce `VUS_LEVELS` a `"1 5"` |
| Hosts `*.local` no resuelven | Falta entrada en `/etc/hosts` | Repite el Paso 6 |
| Linkerd no inyecta proxy | mTLS habilitado pero sin annotation | Verifica `kubectl get ns realistic-linkerd-mtls -o yaml \| grep linkerd.io/inject` |
| Grafana sin métricas | `metrics-server` o `kube-state-metrics` caídos | `microk8s status` y `kubectl get pods -n observability` |

---

## Flujo k6 — realistic-crud-flow.js

Cada VU ejecuta por iteracion:

1. `POST /auth/login` → obtiene JWT token
2. `GET /api/products?limit=20&offset=0` → lista productos
3. `POST /api/products` → crea producto (nombre unico por VU + iteracion)
4. `GET /api/products/:id` → lee el producto creado
5. `PUT /api/products/:id` → actualiza precio y descripcion
6. `GET /api/products/:id` → lee estado post-actualizacion
7. `DELETE /api/products/:id` → elimina el producto
8. `sleep(0.3s)` → pacing

**Total: 7 requests por iteracion.**

### Thresholds

| Metrica | Umbral |
|---|---|
| `http_req_failed` | rate < 5% |
| `http_req_duration` | p95 < 700 ms |
| `checks` | rate > 95% |
| `crud_*_success_total` | count > 0 (cada operacion) |

---

## Metricas Recolectadas

El consolidador Python genera `results.csv` con las siguientes columnas por replica:

| Columna | Descripcion |
|---|---|
| `control`, `variant` | Identificador del escenario (ej: C1, kong) |
| `vus`, `replica` | Parametros del run |
| `avg_ms`, `p95_ms` | Latencia global promedio y percentil 95 |
| `err_pct` | Porcentaje de errores HTTP |
| `rps` | Throughput (requests por segundo) |
| `checks_pct` | Porcentaje de checks k6 pasados |
| `create/read/update/delete_ok` | Conteo de operaciones exitosas por tipo |
| `create/read/update/delete_p95_ms` | Latencia p95 por operacion CRUD |
| `cpu_total_m` | CPU total de los 4 pods en milicores (post-run) |
| `mem_total_Mi` | Memoria total de los 4 pods en MiB (post-run) |

---

## Diagramas

Los diagramas PlantUML del proyecto estan en `diagramas Experimentos/`. Cada experimento tiene:

- `arquitectura.puml` — vista comparativa de las tres configuraciones
- `flujo.puml` — diagrama de actividad del flujo de peticiones
- `clases.puml` — recursos Kubernetes como clases con relaciones
- `paquetes.puml` — namespaces y dependencias entre componentes
- `casos-de-uso.puml` — actores e interacciones
- `secuencia.puml` — traza de mensajes entre componentes

Para renderizarlos: extension PlantUML en VS Code o [plantuml.com/plantuml](http://www.plantuml.com/plantuml/).
