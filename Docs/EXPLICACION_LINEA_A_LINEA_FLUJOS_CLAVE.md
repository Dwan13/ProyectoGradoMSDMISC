# Explicacion Linea a Linea de Flujos Clave

Este documento baja al detalle en los archivos que mueven todo el flujo operativo actual.

## 1) scripts/deploy_microk8s.sh

Referencia base: scripts/deploy_microk8s.sh

### 1.1 Bloque de cabecera y modo estricto

- Lineas 1-13: metadata del script (proposito, alcance y protocolo soportado).
- Lineas 15-16: activa modo estricto de bash.
  - set -e: aborta si falla un comando critico.
  - set -u: error si se usa variable no definida.
  - set -o pipefail: errores en pipelines no se silencian.
- Linea 16: IFS controlado para evitar splitting inesperado.

Por que existe: evita ejecuciones parciales silenciosas y hace el flujo reproducible.

### 1.2 Variables globales y flags de ejecucion

- Lineas 18-44: define rutas base del proyecto, logs, resultados y banderas de modo.
- Bandera COMM_PROTOCOL: habilita comparativa http vs https.
- RUN_HYBRID_MODE / RUN_HYBRID_QUICK_MODE / RUN_HYBRID_STRESS_MODE:
  controlan si ademas del baseline se corre carga sobre micros realistas.
- RUN_REALISTIC_CONTROLS: agrega benchmark adicional C1-C4 realista.

Por que existe: concentrar configuracion en un solo lugar reduce drift de parametros.

### 1.3 Helpers de salida

- Lineas 46-53: funciones log/success/warn/error.

Por que existe: estandariza mensajes y acelera diagnostico visual en terminal.

### 1.4 generate_tls_certificates (lineas 59-97)

Que hace, linea por linea por bloques:

- 60-63: si protocolo no es https, sale sin hacer nada.
- 65-82: genera certificado por servicio (s0, s1, sdb1) con openssl.
- 84-95: crea secrets tls en Kubernetes solo si no existen.

Por que existe: habilitar comparativa tecnica entre trafico plano y cifrado.

### 1.5 wait_for_pods (lineas 99-107)

- Polling hasta encontrar pods core en Running.
- Si no llega a 100% en tiempo esperado, deja warning y continua.

Por que existe: reduce falsos negativos por condiciones transitorias de arranque.

### 1.6 enable_dashboard (lineas 109-145)

- Habilita dashboard y rbac de MicroK8s.
- Garantiza ServiceAccount dashboard-admin y ClusterRoleBinding cluster-admin.
- Abre port-forward local 10443:443.
- Emite token para login.

Por que existe: la visibilidad en UI es parte de validacion de reproducibilidad.

### 1.7 fix_nginx_dns (lineas 147-246)

- Reaplica config de gw-nginx con rutas demo y servicios simulados.
- Si no existe deployment, lo recrea con service NodePort.
- Fuerza rollout restart y espera estado Running.

Por que existe: el gateway es punto de entrada del baseline y suele romperse por drift de config.

### 1.8 check_k6 (lineas 248-288)

- Verifica binario k6.
- Si no existe, intenta instalacion automatica solo si ALLOW_SUDO_INSTALL=1 y hay sudo no interactivo.

Por que existe: evita que falle toda la corrida por falta de dependencia.

### 1.9 run_k6_tests (lineas 290-367)

- Crea carpeta de resultados y timestamp.
- Levanta port-forward a s0.
- Ejecuta baseline.js con variables de entorno controladas.
- Ejecuta inter-service-test.js.
- Cierra port-forward y muestra resumen de rutas de salida.

Por que existe: genera la linea base comparable antes de activar flujo realista.

### 1.10 create_grafana_dashboard (lineas 369-491)

- Obtiene password admin de secret de Grafana.
- Espera health del API.
- Publica dashboard JSON via API /api/dashboards/db.

Por que existe: observabilidad lista sin pasos manuales adicionales.

### 1.11 generate_all_controls_comparison (lineas 493-643)

- Lanza bloque Python embebido.
- Agrega resultados de C1-C4 desde JSON/CSV existentes.
- Calcula percentiles y promedios normalizados.
- Escribe CSV y Markdown consolidado.

Por que existe: entrega comparativo unico para analisis academico y operativo.

### 1.12 generate_all_controls_visuals (lineas 645-750)

- Genera graficas PNG (p95 y promedio) a partir del comparativo consolidado.

Por que existe: facilita lectura rapida para reporte y defensa experimental.

### 1.13 create_grafana_comparison_dashboard (lineas 752-879)

- Publica dashboard comparativo C1-C4.
- Inserta panel de resumen hibrido auto (si existe archivo de resumen).

Por que existe: evita abrir manualmente json/txt en cada corrida.

### 1.14 run_realistic_hybrid_flow (lineas 881-1027)

Bloque central de los cambios recientes:

- Ejecuta deploy-realistic.sh.
- Activa perfil hybrid-quick o hybrid-stress ajustando CREATE_VUS/LIST_VUS y duraciones.
- Ejecuta run-k6-users-bulk.sh.
- Si falla primer intento, reintenta con puertos alternos.
- Toma ultimo k6-users-bulk-*.json y extrae resumen a hybrid-k6-summary-*.txt.
- Si RUN_REALISTIC_CONTROLS=1, dispara benchmark de controles realistas.

Por que existe: unificar baseline + realistic en una sola corrida reproducible.

### 1.15 start_services (lineas 1029-1115)

- Orquesta todo en secuencia:
  - pods,
  - gateway,
  - port-forwards,
  - dashboard,
  - k6 baseline,
  - dashboards,
  - flujo hibrido,
  - comparativos,
  - export de credenciales.

Por que existe: entrypoint unico para no depender de ejecucion manual fragmentada.

### 1.16 stop_services (lineas 1117-1125)

- mata port-forwards locales de forma segura.

Por que existe: limpiar estado entre intentos.

### 1.17 usage + parser CLI (lineas 1127-fin)

- define help del script y parsea flags:
  - --start
  - --stop
  - --hybrid
  - --hybrid-quick
  - --hybrid-stress
  - --hybrid-controls

Por que existe: interfaz estable para automatizar corridas.

## 2) RealisticServices/run-k6-users-bulk.sh

Referencia: RealisticServices/run-k6-users-bulk.sh

### Bloques y razon

- Lineas 1-14: modo estricto + variables base + defaults de puertos.
- Lineas 16-20: nombre de salida k6 con timestamp.
- Lineas 21-24: cleanup con trap para no dejar port-forwards colgados.
- Lineas 26-52: funcion start_port_forward con reintentos y puertos alternos (+100 por intento).
- Lineas 54-57: aplica baseline de controles (opcional) antes de medir.
- Lineas 59-69: levanta pf de auth y api con manejo de error.
- Lineas 71-81: health checks obligatorios de auth y api.
- Lineas 83-95: ejecuta k6 users-bulk-create-list.js parametrizado por entorno.

Por que existe: robustecer la parte mas fragil del flujo (port-forward local).

## 3) RealisticServices/k6/users-bulk-create-list.js

Referencia: RealisticServices/k6/users-bulk-create-list.js

### Bloques y razon

- Lineas 1-4: imports de http, checks, sleep, metricas custom.
- Lineas 6-17: parametros por entorno y metricas custom (counters/trends).
- Lineas 19-41: opciones k6 con dos escenarios concurrentes:
  - create_users
  - list_users
- Lineas 43-58: setup de login y token compartido.
- Lineas 60-87: createUsers() crea usuarios unicos y contabiliza exitos.
- Lineas 89-111: listUsers() pagina usuarios y acumula conteos listados.

Por que existe: medir simultaneamente escritura y lectura en condiciones cercanas a uso real.

## 4) RealisticServices/deploy-realistic.sh

Referencia: RealisticServices/deploy-realistic.sh

### Bloques y razon

- Lineas 1-10: setup base y funcion log.
- Lineas 11-21: build_push(name,dir): build y push al registry local de MicroK8s.
- Lineas 23-29: habilita registry y construye auth/data/api.
- Lineas 31-38: aplica manifests de namespace, postgres, servicios y observabilidad.
- Lineas 39-43: genera y aplica regla comparativa de experimentos.
- Lineas 45-53: restart de deployments para tomar imagenes nuevas.
- Lineas 55-59: port-forward de auth para smoke local.
- Lineas 61-64: publica dashboards.

Por que existe: garantizar despliegue idempotente de la capa realista.

## 5) /home/dwan13/muBench_desde_cero/reset_total.sh

Referencia: /home/dwan13/muBench_desde_cero/reset_total.sh

### Bloques y razon

- Lineas 1-7: modo estricto y variables de contexto del workspace paralelo.
- Lineas 8-27: ayuda integrada (modo normal y hard).
- Lineas 29-43: parser de argumentos con validacion.
- Lineas 45-56: prechecks de existencia de workspace y deploy script.
- Lineas 58-65: mata port-forwards y ejecuta --stop.
- Lineas 67-72: imprime estado de pods realistic si microk8s esta disponible.
- Lineas 74-93: modo --hard limpia resultados y reinicia deployments.
- Lineas 94-101: salida de estado final y siguiente accion sugerida.

Por que existe: permitir iteraciones limpias sin romper ni contaminar el proyecto principal.

## 6) Archivos donde NO tiene sentido documentar linea a linea manual

Para mantener exactitud y evitar ruido, estos se documentan por patron:

- Archivos de salida de pruebas (results/*.json, *.jtl, *.log, *.csv, *.png, *.md).
- Archivos de cache (__pycache__/*.pyc).
- Distribuciones vendor de terceros (ejemplo: experiments/02-mtls-service-mesh/istio-1.22.3/*).

Razon:

- Son artefactos generados automaticamente.
- Cambian en cada corrida.
- No contienen logica de autoria directa del proyecto.
