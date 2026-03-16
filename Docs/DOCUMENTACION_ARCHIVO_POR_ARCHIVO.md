# Documentacion Archivo por Archivo de muBench

## Objetivo de este documento

Este documento explica que hace cada archivo importante del proyecto, por que existe y en que parte del flujo participa.

## Criterio de cobertura

1. Se documentan en detalle los archivos de codigo, automatizacion, manifiestos y configuracion que definen el comportamiento del sistema.
2. Se documentan por patron los archivos de resultados, logs, imagenes y salidas generadas automaticamente (porque son cientos y cambian en cada corrida).
3. Se separa explicitamente el contenido de terceros (por ejemplo, distribuciones completas de Istio) para no mezclar codigo propio con vendor.

## 1) Raiz del proyecto

- .dockerignore: evita incluir archivos innecesarios en builds Docker.
- .gitignore: evita versionar salidas temporales, binarios y caches.
- Dockerfile: imagen base para entorno de ejecucion principal del proyecto.
- Docker-README.md: instrucciones de uso del despliegue por Docker.
- LICENSE: licencia del proyecto.
- README.md: entrada principal del repositorio (arquitectura, uso, contexto).
- README_DISEÑO.md: documento de diseno general y decisiones de arquitectura.
- CHANGES.md: historial de cambios funcionales y tecnicos.
- BRIEF_SUMMARY.md: resumen ejecutivo del estado del proyecto.
- IMPLEMENTATION_GUIDE.md: guia de implementacion de alto nivel.
- INTEGRATION.md: pasos de integracion entre componentes.
- DISEÑO_EXPERIMENTAL.md: diseno de experimentos y criterios comparativos.
- GUIA_VISUALIZACION.md: guia de lectura de dashboards y resultados.
- UPDATE_SUMMARY.md: resumen de actualizaciones recientes.
- UPDATE_FIX.md: correcciones aplicadas en rondas recientes.
- requirements.txt: dependencias Python compartidas de utilidades principales.
- welcome.sh: script de bienvenida/preparacion rapida.

## 2) scripts

- scripts/deploy_microk8s.sh: orquestador principal end-to-end.
  - Levanta muBench base.
  - Ejecuta pruebas k6 base e inter-service.
  - Publica dashboards.
  - Integra flujo hibrido con RealisticServices.
  - Soporta perfiles hybrid, hybrid-quick, hybrid-stress y benchmark de controles.
- scripts/deploy_microk8s old.sh: version historica de referencia.
- scripts/deploy_microk8s copy.sh: variante historica de pruebas.
- scripts/install_k6.sh: instalacion de k6 para entorno local.
- scripts/quick_deploy_services.sh: despliegue rapido de servicios clave.
- scripts/README.md: notas de uso para scripts operativos.

## 3) RealisticServices (nucleo de micros realistas)

### 3.1 Servicios

- RealisticServices/auth-service/app.py: login y emision de token.
- RealisticServices/auth-service/requirements.txt: dependencias de auth.
- RealisticServices/auth-service/Dockerfile: build de auth-service.

- RealisticServices/api-service/app.py: endpoints de negocio (/profile, /users).
- RealisticServices/api-service/requirements.txt: dependencias de api.
- RealisticServices/api-service/Dockerfile: build de api-service.

- RealisticServices/data-service/app.py: acceso/persistencia de datos.
- RealisticServices/data-service/requirements.txt: dependencias de data.
- RealisticServices/data-service/Dockerfile: build de data-service.

### 3.2 Orquestacion y pruebas

- RealisticServices/deploy-realistic.sh: build+push de imagenes y apply de manifests.
- RealisticServices/run-k6-realistic.sh: carga realista base.
- RealisticServices/run-k6-users-bulk.sh: carga create/list de usuarios con retries de port-forward.
- RealisticServices/run-controls-realistic.sh: benchmark de controles C1-C4 en micros realistas.
- RealisticServices/controls/apply-control.sh: aplica baseline o control especifico (C1..C4).
- RealisticServices/publish-grafana-dashboard.sh: publica dashboards de observabilidad realista.
- RealisticServices/generate-experiment-comparison-rule.py: genera regla Prometheus para comparativo.
- RealisticServices/build_unified_docs_pdf.py: utilitario para generar documentacion consolidada.

### 3.3 k6

- RealisticServices/k6/realistic-flow.js: flujo realista clasico.
- RealisticServices/k6/users-bulk-create-list.js: escenario create/list concurrente con thresholds.

### 3.4 Kubernetes manifests

- RealisticServices/k8s/00-namespace.yaml: namespace realistic.
- RealisticServices/k8s/01-postgres.yaml: despliegue y servicio de Postgres.
- RealisticServices/k8s/02-services.yaml: despliegues/servicios de auth, api, data.
- RealisticServices/k8s/03-smoke-test.sh: validacion funcional de despliegue.
- RealisticServices/k8s/04-servicemonitor.yaml: scraping Prometheus Operator.
- RealisticServices/k8s/05-prometheusrule.yaml: alertas/reglas base.
- RealisticServices/k8s/06-experiment-comparison-rule.yaml: regla comparativa (generada).
- RealisticServices/k8s/07-c1-ingress-gateway.yaml: control C1 (gateway/ingress).
- RealisticServices/k8s/08-c3-networkpolicy.yaml: control C3 (network policy).

### 3.5 Documentacion academica y operativa

- RealisticServices/README.md: uso del modulo realista.
- RealisticServices/RUNBOOK_REPRODUCIBILIDAD.md: runbook operativo principal.
- RealisticServices/GUIA_DEFINITIVA_DESDE_CERO.md: guia ultra detallada (paso a paso + por que).
- RealisticServices/RUNBOOK_ACADEMICO_METODO_EXPERIMENTAL.md: enfoque de metodo experimental.
- RealisticServices/CHECKLIST_VALIDACION_RAPIDA.md: checklist rapido de validacion.
- RealisticServices/QUICKSTART_1PAGINA.md: arranque de 1 pagina.
- RealisticServices/ARGUMENTO_SEGURIDAD_DEFENSIVA_ES.md: argumentacion en espanol.
- RealisticServices/SECURITY_DEFENSIVE_ARGUMENT_IEEE_ACM.md: argumentacion estilo IEEE/ACM.
- RealisticServices/MAPEO_C1_C4_CSA_CCM_NIST.md: mapeo de controles a marcos de seguridad.

### 3.6 Resultados (generados)

- RealisticServices/results/k6-users-bulk-*.json: salida cruda de k6 bulk.
- RealisticServices/results/hybrid-k6-summary-*.txt: resumen automatico de corrida hibrida.
- RealisticServices/results/controls/*.json: resultados por control aplicado.

## 4) Add-on

- Add-on/HPA/create-hpa.py: generacion automatica de HPA.
- Add-on/HPA/hpa-template.yaml: plantilla HPA.
- Add-on/HPA/README.md: uso del modulo HPA.

- Add-on/Istio/create-destination-rule.py: helper para destination rules.
- Add-on/Istio/destination-rule-template.yaml: plantilla destination rule.
- Add-on/Istio/istio-gateway.yaml: gateway Istio para escenario.
- Add-on/Istio/istio-s0-virtual-service.yaml: virtual service para s0.
- Add-on/Istio/mubench-istio-grafana.json: dashboard Istio.
- Add-on/Istio/README.md: uso de add-on Istio.

- Add-on/Topology-affinity/create-affinity-yamls.py: afinidad/topologia de pods.
- Add-on/Topology-affinity/README.md: explicacion de afinidad topologica.

## 5) Autopilots

- Autopilots/K8sAutopilot/K8sAutopilot.py: piloto automatico de experimentos.
- Autopilots/K8sAutopilot/README.md: instrucciones del autopilot.
- Autopilots/K8sAutopilot/SimulationWorkspace/*: artefactos de simulacion generados.

## 6) Benchmarks

- Benchmarks/Runner/Runner.py: coordinador de ejecucion de benchmarks.
- Benchmarks/Runner/TimingError.py: utilitario de errores de temporizacion.
- Benchmarks/TrafficGenerator/TrafficGenerator.py: motor de generacion de trafico.
- Benchmarks/TrafficGenerator/RunTrafficGen.py: launcher del generador.

## 7) Configs

- Configs/K8sAutopilotConf.json: configuracion de autopilot Kubernetes.
- Configs/K8sParameters.json: parametros de cluster/despliegue.
- Configs/RunnerParameters.json: parametros del benchmark runner.
- Configs/ServiceGraphParameters.json: parametros del generador de grafos.
- Configs/TrafficParameters.json: parametros de trafico.
- Configs/WorkModelParameters.json: parametros del modelo de carga.

## 8) CustomFunctions

- CustomFunctions/Loader.py: carga dinamica de funciones custom.
- CustomFunctions/Colosseum.py: funciones personalizadas para escenarios.
- CustomFunctions/README.md: contrato de funciones custom.

## 9) Deployers

- Deployers/K8sDeployer/K8sYamlBuilder.py: construccion de YAMLs de despliegue.
- Deployers/K8sDeployer/K8sYamlDeployer.py: despliegue de YAMLs a cluster.
- Deployers/K8sDeployer/RunK8sDeployer.py: ejecutor principal del deploayer.
- Deployers/K8sDeployer/Templates/*.yaml: plantillas base de objetos Kubernetes.

## 10) ServiceCell

- ServiceCell/CellController-mp.py: controlador principal multiproceso de celdas.
- ServiceCell/CellController-enhanced.py: variante extendida del controlador.
- ServiceCell/InternalServiceExecutor.py: ejecucion de llamadas internas.
- ServiceCell/ExternalServiceExecutor.py: ejecucion de llamadas externas.
- ServiceCell/mub.proto: contrato gRPC.
- ServiceCell/mub_pb2.py y mub_pb2_grpc.py: codigo generado de protobuf.
- ServiceCell/Dockerfile y Dockerfile-mp-*.debug: imagenes de ejecucion y debug.
- ServiceCell/start-mp*.sh: scripts de arranque en modos distintos.
- ServiceCell/gunicorn.conf.py: configuracion de Gunicorn.
- ServiceCell/builder.sh: build helper.
- ServiceCell/requirements.txt: dependencias de ServiceCell.
- ServiceCell/README.md: documentacion especifica del componente.

## 11) ServiceGraphGenerator

- ServiceGraphGenerator/ServiceGraphGenerator.py: genera grafo de servicios.
- ServiceGraphGenerator/RunServiceGraphGen.py: launcher del generador.

## 12) WorkModelGenerator

- WorkModelGenerator/WorkModelGenerator.py: genera modelo de trabajo.
- WorkModelGenerator/RunWorkModelGen.py: launcher de generacion.
- WorkModelGenerator/SimulationWorkspace/*.yaml|*.json|*.png: salidas generadas de simulacion.

## 13) Testing

- Testing/baseline.js: prueba baseline k6.
- Testing/inter-service-test.js: prueba de interaccion entre servicios.
- Testing/analyze_k6_results.py: analisis de resultados k6.
- Testing/generate_plots.py: generacion de graficas comparativas.
- Testing/mubench_baseline.jmx: escenario legado JMeter.
- Testing/results/*: resultados historicos de ejecuciones (json/jtl/csv/md/png).
- Testing/plots/*: visualizaciones generadas de analisis.

## 14) Monitoring

- Monitoring/mubench-dashboard.json: dashboard principal de muBench.
- Monitoring/mubench-servicemonitor.yaml: ServiceMonitor principal.
- Monitoring/kubernetes-full-monitoring/*.yaml|*.sh|*.json|*.png:
  - instalacion y configuracion de stack de observabilidad,
  - dashboards y capturas de referencia,
  - manifests de Prometheus, Grafana, Jaeger, Kiali e Ingress.

## 15) Docs

- Docs/Manual.md: manual funcional del proyecto.
- Docs/reproducibility.md: notas de reproducibilidad generales.
- Docs/*.drawio: diagramas editables.
- Docs/*.png|*.pdf: material visual, capturas y poster.

## 16) experiments (diseno experimental)

### 16.1 Estructura comun por control

Cada control sigue un patron:

- README.md: metodologia y alcance del experimento.
- run-controlX-safe.sh: pipeline seguro del control.
- monitor-controlX.sh: seguimiento de ejecucion.
- baseline/*: baseline del control.
- tests/*: scripts k6 o validaciones.
- analysis/*: scripts de analisis y salidas agregadas.
- results/*: salidas por repeticion + logs.

### 16.2 Controles presentes

- experiments/01-api-gateway: comparacion baseline vs NGINX/Kong.
- experiments/02-mtls-service-mesh: comparacion baseline vs mTLS mesh (Istio/Linkerd).
- experiments/03-network-policies: impacto de politicas de red.
- experiments/04-rate-limiting: impacto de rate limiting.

### 16.3 Archivos de terceros y vendor en experiments

- experiments/02-mtls-service-mesh/istio-1.22.3/*:
  - distribucion completa de Istio (vendor externo),
  - no es codigo de autoria del proyecto,
  - se conserva para reproducibilidad del control C2.

## 17) Archivos generados y caches

Se consideran artefactos generados (no logica fuente):

- __pycache__/*.pyc
- results/*.json, *.jtl, *.log, *.csv, *.png, *.md (salidas de corrida)
- plots/*.png
- SimulationWorkspace/* generado

Estos archivos se documentan por patron porque su contenido depende de cada ejecucion.

## 18) Relacion con tus ultimos cambios

Cambios recientes principales quedaron concentrados en:

- scripts/deploy_microk8s.sh
- RealisticServices/run-k6-users-bulk.sh
- RealisticServices/k6/users-bulk-create-list.js
- RealisticServices/RUNBOOK_REPRODUCIBILIDAD.md
- RealisticServices/GUIA_DEFINITIVA_DESDE_CERO.md
- carpeta paralela /home/dwan13/muBench_desde_cero con bootstrap/run/reset

Para explicacion linea por linea de estos archivos clave, ver:

- Docs/EXPLICACION_LINEA_A_LINEA_FLUJOS_CLAVE.md
