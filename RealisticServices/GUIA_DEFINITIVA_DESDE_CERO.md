# Guia Definitiva Desde Cero (muBench + RealisticServices)

Esta guia esta pensada para ejecutar y entender todo el sistema desde cero, con foco en:

- pasos operativos exactos,
- razon tecnica de cada paso,
- verificacion de pods y servicios,
- interpretacion de resultados,
- recuperacion ante fallos.

Para una ruta de limpieza total de entorno (cluster + herramientas + validacion final), revisar tambien:

- `Docs/PROTOCOLO_CERO_ABSOLUTO.md`

El objetivo no es solo que funcione, sino que puedas explicar por que funciona.

## 0. Modelo mental del sistema (antes de tocar comandos)

### 0.1 Que despliegas realmente

Hay dos capas que se combinan en el flujo hibrido:

1. Capa muBench base:
- Servicios simulados para benchmark base.
- Pruebas k6 baseline e inter-service.
- Publicacion de dashboards y comparativos C1-C4.

2. Capa RealisticServices:
- `auth-service`: autentica y emite token para API.
- `api-service`: endpoint de negocio (`/profile`, `/users`, `POST /users`).
- `data-service`: acceso a datos y logica de persistencia.
- `postgres`: almacenamiento de usuarios y datos semilla.

### 0.2 Por que la separacion en capas importa

- Te permite comparar rendimiento entre simulacion base y microservicios realistas.
- Te permite aislar errores: si falla base, no culpas a realistic; si falla realistic, ya sabes que base estaba bien.
- Te permite evolucionar controles C1-C4 sin romper el pipeline principal.

### 0.3 Flujo de datos (simplificado)

1. k6 llama `auth-service` para login.
2. Recibe token.
3. Usa token para `api-service`.
4. `api-service` consulta/escribe via `data-service`.
5. `data-service` persiste en `postgres`.
6. Prometheus recoge metricas y Grafana las visualiza.

## 1. Requisitos y por que cada uno existe

### 1.1 Requisitos minimos

- Linux o WSL2
- Docker
- MicroK8s
- Python 3.8+
- k6
- curl

### 1.2 Razon tecnica de cada dependencia

- Docker: construye imagenes de `auth/api/data` para registry local.
- MicroK8s: cluster Kubernetes local que ejecuta pods y servicios.
- Python: utilidades y scripts del proyecto.
- k6: genera carga reproducible y comparable.
- curl: smoke tests rapidos de login y API.

### 1.3 Verificacion inicial obligatoria

```bash
python3 --version
docker --version
microk8s status --wait-ready
microk8s kubectl version --client=true
k6 version
curl --version
```

Si falla algo aqui, no avances. Todo lo demas depende de esta base.

## 2. Preparar entorno paralelo (practica sin tocar proyecto principal)

### 2.1 Ir a carpeta paralela

```bash
cd /home/dwan13/muBench_desde_cero
```

### 2.2 Crear copia limpia del proyecto

```bash
./bootstrap_workspace.sh
```

Que hace y por que:
- Copia el repo a `workspace/`.
- Excluye resultados y caches para iniciar casi desde cero.
- Evita contaminar el proyecto principal con pruebas de practica.

### 2.3 Permisos de scripts

```bash
chmod +x *.sh
chmod +x workspace/scripts/deploy_microk8s.sh
chmod +x workspace/RealisticServices/*.sh
```

Por que:
- En Linux, sin bit ejecutable el flujo falla por permiso denegado.

## 3. Ejecucion recomendada (primera corrida)

### 3.1 Ejecutar flujo rapido hibrido

```bash
./run_hybrid_quick.sh
```

Internamente ejecuta:

```bash
workspace/scripts/deploy_microk8s.sh --start --hybrid-quick
```

Por que empezar por quick:
- Menor duracion.
- Valida pipeline completo rapido.
- Menor probabilidad de ruido por saturacion de maquina.

### 3.2 Que esperar en logs (orden esperado)

1. muBench base inicializa y corre k6 baseline.
2. k6 inter-service termina con thresholds OK.
3. Despliegue realistic (`auth/api/data/postgres`).
4. k6 realista create/list termina con thresholds OK.
5. Se genera `hybrid-k6-summary-*.txt`.
6. Se publican dashboards.

Si este orden se rompe, revisa seccion de troubleshooting.

## 4. Validacion de Kubernetes a nivel pods (detalle absoluto)

### 4.1 Confirmar namespace y pods realistas

```bash
microk8s kubectl get ns
microk8s kubectl get pods -n realistic -o wide
microk8s kubectl get svc -n realistic
```

Esperado minimo en `realistic`:
- `auth-service` Running
- `api-service` Running
- `data-service` Running
- `postgres` Running

### 4.2 Como interpretar estados de pod

- `Running`: contenedor listo para trafico.
- `Pending`: no hay recursos o scheduling incompleto.
- `CrashLoopBackOff`: app arranca y cae repetidamente (error de runtime).
- `ImagePullBackOff`: imagen no disponible en registry.

Comando de diagnostico rapido:

```bash
microk8s kubectl describe pod -n realistic <pod-name>
microk8s kubectl logs -n realistic <pod-name> --tail=200
```

### 4.3 Ready vs Running (clave para no confundirse)

Un pod puede aparecer `Running` pero no estar realmente listo para recibir trafico si `READY` no es `1/1`.

Regla practica:
- Aceptable: `1/1 Running`
- No aceptable: `0/1 Running`, `0/1 CrashLoopBackOff`, etc.

## 5. Validacion funcional de API (sin dashboard)

### 5.1 Login

Terminal A:

```bash
microk8s kubectl port-forward -n realistic svc/auth-service 18082:8080
```

Terminal B:

```bash
curl -s -X POST 'http://127.0.0.1:18082/login' \
  -H 'Content-Type: application/json' \
  -d '{"username":"demo","password":"demo123"}'
```

Por que:
- Demuestra que auth funciona antes de culpar a API o data-service.

### 5.2 Listar usuarios

Terminal A:

```bash
microk8s kubectl port-forward -n realistic svc/api-service 18081:8080
```

Terminal B (usar token real):

```bash
curl -s 'http://127.0.0.1:18081/users?limit=20&offset=0' \
  -H "Authorization: Bearer TOKEN"
```

Por que:
- Valida path completo auth -> api -> data -> postgres.

### 5.3 Crear usuario

```bash
curl -s -X POST 'http://127.0.0.1:18081/users' \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer TOKEN" \
  -d '{"username":"manual_user_1","email":"manual_user_1@example.com"}'
```

Por que:
- Valida escritura real en DB, no solo lectura.

## 6. Dashboard de Kubernetes (paso a paso exacto)

### 6.1 Acceso

URL:

- `https://localhost:10443`

Token recomendado (nuevo):

```bash
microk8s kubectl -n kube-system create token dashboard-admin
```

### 6.2 Donde mirar y que seleccionar

1. Abrir `Workloads`.
2. Entrar a `Pods`.
3. Cambiar namespace de `default` a `realistic` o `All namespaces`.
4. Limpiar filtros de texto.
5. Refrescar navegador (Ctrl+Shift+R).

### 6.3 Por que no ves pods a veces aunque existan

Causas mas comunes:
- Namespace equivocado (`default` en vez de `realistic`).
- Filtro de busqueda activo.
- Token sesion vieja.
- Port-forward del dashboard no activo.

Chequeo rapido de endpoint local:

```bash
curl -k -I https://localhost:10443/
```

## 7. Validacion de carga k6 y como leer resultados

### 7.1 Archivos que deben existir

```bash
ls -1t workspace/RealisticServices/results/k6-users-bulk-*.json | head
ls -1t workspace/RealisticServices/results/hybrid-k6-summary-*.txt | head
```

### 7.2 Metricas importantes del resumen

- `users_created_total`: volumen de escritura logrado.
- `users_listed_total`: volumen de lecturas logradas.
- `http_req_duration_p95_ms`: latencia p95 (referencia robusta).
- `http_req_failed_rate`: tasa de error HTTP.

Interpretacion rapida:
- p95 bajo + error bajo = sistema estable.
- p95 alto + error bajo = cuello de botella sin caida.
- p95 alto + error alto = degradacion real.

## 8. Grafana y observabilidad (que mirar primero)

### 8.1 URLs esperadas

- `http://localhost:3000/d/mubench-realistic-observability/mubench-realistic-services-realtime`
- `http://localhost:3000/d/mubench-controls-tech-comparison/mubench-controls-tech-comparison`

### 8.2 Panel clave agregado

En dashboard comparativo debe aparecer:
- `Resumen Hibrido k6 (Auto)`

Por que importa:
- Evita revisar JSON manualmente.
- Te deja un resumen trazable por corrida.

## 9. Postgres y persistencia (validacion de verdad)

Comprobar conteo de usuarios:

```bash
microk8s kubectl exec -n realistic deploy/postgres -- \
  psql -U mubench -d mubench -c "SELECT COUNT(*) FROM app_users;"
```

Por que:
- Confirma que la carga no solo respondio HTTP, sino que persistio datos.

## 10. Reset entre intentos (sin ensuciar resultados)

### 10.1 Reset normal (recomendado entre corridas)

```bash
cd /home/dwan13/muBench_desde_cero
./reset_total.sh
```

Que hace:
- Mata port-forwards locales.
- Ejecuta `--stop` en workspace paralelo.
- Muestra estado de pods realistic.

### 10.2 Reset hard (cuando quieres empezar limpio)

```bash
./reset_total.sh --hard
```

Adicionalmente:
- Borra resultados en `workspace/Testing/results` y `workspace/RealisticServices/results`.
- Reinicia deployments de realistic.

## 11. Troubleshooting detallado

### 11.1 `kubectl` no encontrado

En este entorno usa MicroK8s:

```bash
microk8s kubectl get pods -A
```

### 11.2 Port-forward ocupado

```bash
pkill -f "kubectl.*port-forward"
```

Luego vuelve a correr flujo o reset.

### 11.3 Pod en CrashLoopBackOff

```bash
microk8s kubectl describe pod -n realistic <pod-name>
microk8s kubectl logs -n realistic <pod-name> --tail=200
```

Busca:
- errores de variables de entorno,
- fallos de conexion a Postgres,
- fallos de import o dependencias.

### 11.4 Dashboard no muestra pods

- Verifica URL `https://localhost:10443`.
- Cambia namespace a `realistic`.
- Limpia filtros de tabla.
- Regenera token.
- Confirma por CLI que pods existen.

### 11.5 k6 no cumple thresholds

Acciones:
- bajar VUs (quick profile),
- cerrar procesos locales pesados,
- revisar saturation de CPU/RAM,
- repetir corrida para confirmar si fue ruido temporal.

## 12. Secuencia absoluta recomendada (checklist operativo)

1. Validar prerequisitos (Python, Docker, MicroK8s, k6).
2. Crear workspace paralelo con `bootstrap_workspace.sh`.
3. Ejecutar `run_hybrid_quick.sh`.
4. Confirmar pods `1/1 Running` en namespace `realistic`.
5. Validar login y lectura de usuarios por curl.
6. Entrar a Dashboard Kubernetes y seleccionar namespace correcto.
7. Verificar archivos `k6-users-bulk-*.json` y `hybrid-k6-summary-*.txt`.
8. Verificar dashboards de Grafana (realtime y comparativo).
9. Verificar persistencia en Postgres con `COUNT(*)`.
10. Ejecutar `reset_total.sh` entre intentos.
11. Escalar a `run_hybrid_stress.sh` cuando quick este estable.
12. Solo despues habilitar benchmark adicional C1-C4 realista.

## 13. Criterio final de exito reproducible

Puedes declarar exito completo si:

1. El flujo `--hybrid-quick` termina sin error fatal.
2. Los 4 pods realistas quedan `1/1 Running`.
3. El Dashboard muestra esos pods al seleccionar `realistic`.
4. k6 genera JSON y resumen hibrido.
5. Grafana muestra panel de resumen automatico.
6. Postgres refleja crecimiento de datos.

Cuando esos seis puntos se cumplen en corridas repetidas, tienes reproducibilidad tecnica real, no solo exito accidental.
