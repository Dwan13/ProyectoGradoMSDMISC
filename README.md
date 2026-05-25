# Experimentacion: Impacto de Controles de Seguridad en Microservicios

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
│   └── 04-rate-limiting-realistic/
│
├── RealisticServices/                  # Codigo fuente de los microservicios
│   ├── api-service/                    # FastAPI: orquestacion CRUD + JWT
│   ├── auth-service/                   # FastAPI: login + validacion JWT
│   ├── data-service/                   # FastAPI: CRUD /products sobre PostgreSQL
│   ├── k6/
│   │   ├── realistic-crud-flow.js      # Script k6: flujo CRUD completo (principal)
│   │   └── realistic-flow.js           # Script k6: flujo mixto de lectura
│   ├── k8s/                            # Manifiestos base reutilizables
│   ├── controls/
│   │   └── apply-control.sh
│   └── deploy-realistic.sh
│
├── scripts/                            # Herramientas de orquestacion y analisis
│   ├── run-crud-experiment.sh          # ORQUESTADOR PRINCIPAL
│   ├── run-crud-full-grid.sh            # Loop factorial (VUS × controles × variantes)
│   ├── anova_overhead.py                # Análisis Kruskal-Wallis + ε²
│   ├── build_overhead_report.py         # Genera capítulo LaTeX + boxplots
│   ├── keep-portforwards.sh
│   └── monitoring-up.sh / monitoring-down.sh
│
├── Testing/                            # Resultados y analisis estadistico
│   ├── results/auto_runs/              # Salida del orquestador (generada)
│   │   └── crud_vusN_nM_TIMESTAMP/
│   │       ├── results.csv             # Consolidado final
│   │       ├── resource_metrics.csv    # CPU/mem por replica
│   │       ├── invalid-scenarios.csv   # Escenarios que fallaron smoke check
│   │       ├── summaries/              # JSON k6 por replica
│   │       ├── logs/                   # stdout k6 por replica
│   │       └── state/                  # Dumps YAML del cluster
│   ├── consolidate_all_metrics.py
│   ├── s6_statistical_analysis.py
│   └── extract_clean_metrics.py
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

- Kubernetes (MicroK8s recomendado)
- Addons habilitados: `dns`, `ingress`, `metrics-server`, `registry`
- Istio instalado (para C1/istio y C2/istio-mtls)
- Linkerd instalado (para C2/linkerd-mtls)
- Kong Ingress Controller (para C1/kong)
- k6 >= 0.45
- Python 3 (consolidacion de resultados)
- Imagenes publicadas en registry local `localhost:32000/mubench/`

---

## Ejecucion

### Ejecutar la campana completa (12 escenarios)

```bash
bash scripts/run-crud-experiment.sh --vus 20 --replicas 5 --duration 60s
```

### Ejecutar un solo control

```bash
bash scripts/run-crud-experiment.sh --scenario C1
bash scripts/run-crud-experiment.sh --scenario kong
```

### Con calentamiento previo

```bash
bash scripts/run-crud-experiment.sh --vus 20 --replicas 5 --duration 60s --warmup 30
```

### Parametros disponibles

| Parametro | Por defecto | Descripcion |
|---|---|---|
| `--vus` | 20 | Virtual Users concurrentes en k6 |
| `--replicas` | 5 | Repeticiones por escenario (para significancia estadistica) |
| `--duration` | `60s` | Duracion de cada run k6 |
| `--warmup` | 0 | Segundos de trafico previo para estabilizar caches |
| `--scenario` | (todos) | Filtro por nombre parcial (ej: `kong`, `C2`, `istio-mtls`) |

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
