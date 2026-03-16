# Runbook Completo de Reproducibilidad (muBench + RealisticServices + Script Principal)

Este documento cubre todo el proceso desde cero, hasta validar que el script principal queda completamente actualizado y operativo con:

- flujo base muBench,
- flujo hibrido con micros realistas,
- perfiles `--hybrid`, `--hybrid-quick`, `--hybrid-stress`,
- benchmark opcional C1-C4 realista,
- resumen automatico k6 exportado y publicado en dashboard comparativo.

Guia extendida ultra detallada:

- `RealisticServices/GUIA_DEFINITIVA_DESDE_CERO.md`

## 1. Alcance y Resultado Esperado

Al finalizar este runbook debes poder ejecutar, desde un solo comando del script principal:

```bash
./scripts/deploy_microk8s.sh --start --hybrid-quick
```

y obtener:

1. muBench base desplegado.
2. RealisticServices desplegado (`auth/api/data/postgres`).
3. Pruebas k6 create/list sobre micros realistas.
4. Dashboards de Grafana publicados.
5. Resumen automatico en archivo `hybrid-k6-summary-*.txt`.
6. Panel "Resumen Hibrido k6 (Auto)" en dashboard comparativo.

## 2. Requisitos de Entorno

### 2.1 Hardware recomendado

- CPU: 6 vCPU o mas.
- RAM: 12-16 GB.
- Disco libre: 30 GB minimo.

### 2.2 Software requerido

- Linux o WSL2.
- Docker.
- MicroK8s.
- Python 3.8+.
- k6.
- curl.

### 2.3 Verificacion inicial

```bash
python3 --version
docker --version
microk8s version
microk8s kubectl version --client=true
microk8s status --wait-ready
k6 version
```

## 3. Preparacion desde Cero

### 3.1 Ubicar proyecto y permisos de ejecucion

```bash
cd /home/dwan13/muBench
chmod +x scripts/deploy_microk8s.sh
chmod +x RealisticServices/deploy-realistic.sh
chmod +x RealisticServices/run-k6-users-bulk.sh
chmod +x RealisticServices/run-controls-realistic.sh
chmod +x RealisticServices/controls/apply-control.sh
```

### 3.2 Confirmar que el script principal tiene opciones actualizadas

```bash
./scripts/deploy_microk8s.sh --help
```

Debes ver al menos:

- `--hybrid`
- `--hybrid-quick`
- `--hybrid-stress`
- `--hybrid-controls`

## 4. Arquitectura Operativa (Actualizada)

### 4.1 Capa base muBench

- Servicios simulados muBench.
- Observabilidad con Prometheus/Grafana.
- Consolidacion comparativa C1-C4 (CSV/MD/PNG).

### 4.2 Capa realista (hibrida)

- `auth-service` (`POST /login`).
- `api-service` (`GET /profile`, `GET /users`, `POST /users`).
- `data-service` (Postgres backend).
- `postgres` con datos semilla y datos creados por carga.

### 4.3 Carga realista integrada

- k6 crea usuarios masivamente y luego lista usuarios.
- Reintentos de port-forward con puertos alternos en helper.

## 5. Flujo Recomendado de Ejecucion

### 5.1 Sanity rapido (recomendado primero)

```bash
cd /home/dwan13/muBench
./scripts/deploy_microk8s.sh --start --hybrid-quick
```

### 5.2 Flujo hibrido normal

```bash
./scripts/deploy_microk8s.sh --start --hybrid
```

### 5.3 Flujo hibrido stress

```bash
./scripts/deploy_microk8s.sh --start --hybrid-stress
```

### 5.4 Hibrido + benchmark C1-C4 realista

```bash
./scripts/deploy_microk8s.sh --start --hybrid --hybrid-controls
```

## 6. Variables de Control Importantes

### 6.1 Variables generales

- `COMM_PROTOCOL` (`http|https`)
- `VUS`, `DURATION` (k6 base muBench)

### 6.2 Variables hibridas realistas

- `REALISTIC_CREATE_VUS`
- `REALISTIC_CREATE_DURATION`
- `REALISTIC_LIST_START`
- `REALISTIC_LIST_VUS`
- `REALISTIC_LIST_DURATION`
- `REALISTIC_LIST_LIMIT`

### 6.3 Variables de puertos port-forward (si hay colisiones)

- `REALISTIC_AUTH_PORT`
- `REALISTIC_API_PORT`
- `REALISTIC_AUTH_PORT_FALLBACK`
- `REALISTIC_API_PORT_FALLBACK`

Ejemplo:

```bash
REALISTIC_AUTH_PORT=19092 REALISTIC_API_PORT=19091 ./scripts/deploy_microk8s.sh --start --hybrid
```

## 7. Validaciones Funcionales Minimas

### 7.1 Estado de pods

```bash
microk8s kubectl get pods -n realistic
microk8s kubectl get svc -n realistic
```

### 7.2 Login y token

```bash
microk8s kubectl port-forward -n realistic svc/auth-service 18082:8080
```

En otra terminal:

```bash
curl -s -X POST 'http://127.0.0.1:18082/login' \
  -H 'Content-Type: application/json' \
  -d '{"username":"demo","password":"demo123"}'
```

### 7.3 Listar usuarios

```bash
microk8s kubectl port-forward -n realistic svc/api-service 18081:8080
```

En otra terminal (reemplaza TOKEN):

```bash
curl -s 'http://127.0.0.1:18081/users?limit=20&offset=0' \
  -H "Authorization: Bearer TOKEN"
```

### 7.4 Crear usuario

```bash
curl -s -X POST 'http://127.0.0.1:18081/users' \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer TOKEN" \
  -d '{"username":"runbook_user_1","email":"runbook_user_1@example.com"}'
```

## 8. Validaciones de Carga k6 Realista

Despues de ejecutar flujo hibrido, verificar archivos:

```bash
ls -1t /home/dwan13/muBench/RealisticServices/results/k6-users-bulk-*.json | head
ls -1t /home/dwan13/muBench/RealisticServices/results/hybrid-k6-summary-*.txt | head
```

Esperado:

- existe al menos un `k6-users-bulk-*.json`,
- existe un `hybrid-k6-summary-*.txt` con:
  - `users_created_total`,
  - `users_listed_total`,
  - `http_req_duration_p95_ms`,
  - `http_req_failed_rate`.

## 9. Dashboards y Observabilidad

### 9.1 URLs esperadas

- Grafana realtime realista:
  - `http://localhost:3000/d/mubench-realistic-observability/mubench-realistic-services-realtime`
- Grafana comparativo:
  - `http://localhost:3000/d/mubench-controls-tech-comparison/mubench-controls-tech-comparison`
- Prometheus:
  - `http://localhost:9090`

### 9.2 Panel nuevo esperado en dashboard comparativo

Debe existir panel:

- `Resumen Hibrido k6 (Auto)`

con el texto del ultimo `hybrid-k6-summary-*.txt` generado en la corrida.

### 9.3 Kubernetes Dashboard: ver pods realistas

Para ver los micros nuevos en el Dashboard de Kubernetes:

1. Abre `https://localhost:10443`.
2. Inicia sesion con token de `dashboard-admin`.
3. Ve a `Workloads` -> `Pods`.
4. Cambia el selector de namespace de `default` a `realistic` o `All namespaces`.
5. Limpia cualquier filtro de texto en la tabla y refresca la vista.

Validacion por CLI (MicroK8s):

```bash
microk8s kubectl get pods -n realistic
```

Si los pods estan en `Running` por CLI pero no en UI, casi siempre es filtro de namespace o sesion vieja del Dashboard.

## 10. Verificacion de Persistencia de Datos en Postgres

```bash
microk8s kubectl exec -n realistic deploy/postgres -- \
  psql -U mubench -d mubench -c "SELECT COUNT(*) FROM app_users;"
```

Si ejecutaste cargas k6, el conteo debe crecer respecto a la semilla inicial.

## 11. Criterios de Exito Final

Se considera reproduccion completa cuando:

1. `./scripts/deploy_microk8s.sh --help` muestra opciones hibridas nuevas.
2. `--hybrid-quick` o `--hybrid-stress` finaliza sin error fatal.
3. Se genera `k6-users-bulk-*.json`.
4. Se genera `hybrid-k6-summary-*.txt`.
5. Dashboard comparativo se publica y contiene panel de resumen hibrido.
6. Credenciales se guardan en `~/.mubench_credentials`.

## 12. Troubleshooting

### 12.1 Port-forward del API realista falla

- El helper ya reintenta puertos alternos (`+100` por intento).
- Si persiste, liberar puertos ocupados:

```bash
pkill -f "port-forward"
```

### 12.2 k6 no encontrado

- Instalar k6 y validar:

```bash
k6 version
```

### 12.3 Error de email en `POST /users`

- Usar dominio valido, por ejemplo `example.com`.

### 12.4 Dashboard no muestra cambios

- Verificar que el Dashboard de Kubernetes este activo en `https://localhost:10443`.
- Confirmar que estas en namespace `realistic` o `All namespaces`.
- Confirmar que no hay filtro de texto activo en la tabla de pods.
- Obtener token nuevo y volver a iniciar sesion:

```bash
microk8s kubectl -n kube-system create token dashboard-admin
```

- Verificar por CLI en el mismo cluster de MicroK8s:

```bash
microk8s kubectl get pods -n realistic
```

## 13. Comandos Rapidos de Operacion

### 13.1 Arranque rapido hibrido

```bash
./scripts/deploy_microk8s.sh --start --hybrid-quick
```

### 13.2 Arranque stress

```bash
./scripts/deploy_microk8s.sh --start --hybrid-stress
```

### 13.3 Detener port-forwards

```bash
./scripts/deploy_microk8s.sh --stop
```

### 13.4 Limpieza manual (si aplica)

```bash
pkill -f "port-forward" || true
```

---

Con este runbook el proyecto queda reproducible desde cero hasta estado totalmente actualizado del script principal y validado con carga hibrida realista.
