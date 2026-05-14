# Resumen Ejecutivo: muBench Academic Benchmark (B1-B8)

## Arquitectura General
- **Generador de tráfico:** k6 (VUs: 1, 5, 10, 20)
- **API Gateway:** nginx TLS, istio, kong (C1); HTTP directo (C2/C3/C4)
- **Servicios:** API, Auth, Data, Postgres DB
- **Monitoreo:** Prometheus (métricas CPU/memoria), Grafana
- **Orquestación:** Kubernetes

## Esquema de Base de Datos
- API Service, Auth Service y Data Service interactúan con Postgres DB
- Consultas de autenticación, datos y operaciones API

## Flujo de Datos
1. k6 genera tráfico hacia el API Gateway o directo al API Service
2. El gateway enruta a Auth y API Service
3. API Service consulta Data Service y Postgres
4. Prometheus recolecta métricas de todos los servicios
5. Scripts post-procesan y fusionan datos de k6 y Prometheus
6. Análisis estadístico (TOST, ANOVA, solidness)

## Diseño Experimental
- **Matriz:** 48 celdas (control, variante, VUs)
- **Bloques:** B1-B8, 8 réplicas por celda
- **Comparativas:** intra-control por tecnología y esquema
- **Hipótesis:** Equivalencia de desempeño y robustez entre tecnologías
- **Endpoints:**
  - C1: nginx TLS, istio, kong (HTTPS)
  - C2/C3/C4: HTTP directo

## Métricas y Proveedores
- **k6:** latencia (p95), tasa de error, checks
- **Prometheus:** CPU, memoria (por pod/servicio)

## Reproducibilidad: Paso a Paso
1. Clona el repositorio y entra al directorio muBench
2. Ejecuta `bash setup_mubench_env.sh` para provisionar el entorno
3. Corre los experimentos según el README
4. Ejecuta los scripts de post-procesamiento para análisis y reportes

## Diagrama de Arquitectura, Esquema y Flujo
- Ver archivos en Docs/: architecture.puml, db_schema.puml, data_flow.puml, experimental_design.puml

---

**Resultado:**
- 100% de celdas cubiertas (48/48), 8 réplicas cada una
- Métricas completas de k6 y Prometheus
- Validación académica: "GO" (cumple rigor y valor académico)
- Listo para análisis ANOVA y comparativas robustas
