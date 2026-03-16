# Runbook Academico: Metodo Experimental y Reproducibilidad

## 1. Objetivo del Protocolo
Este documento define el procedimiento experimental para reproducir muBench con microservicios realistas, validar operacion funcional, ejecutar cargas controladas con k6 y recolectar evidencia de rendimiento-seguridad de manera trazable.

## 2. Pregunta Experimental
Bajo un esquema hibrido (muBench base + RealisticServices), cual es el comportamiento de latencia, error rate y capacidad de alta/listado de usuarios al ejecutar cargas de tipo quick, normal y stress, y como se refleja en el dashboard comparativo.

## 3. Entorno y Requisitos
- SO: Linux o WSL2
- Docker y MicroK8s operativos
- Python 3.8+
- k6 instalado
- Repositorio en: /home/dwan13/muBench

Comandos de verificacion:

```bash
python3 --version
docker --version
microk8s version
microk8s kubectl version --client=true
microk8s status --wait-ready
k6 version
```

## 4. Variables de Control
### 4.1 Variables de carga base
- COMM_PROTOCOL
- VUS
- DURATION

### 4.2 Variables de carga realista
- REALISTIC_CREATE_VUS
- REALISTIC_CREATE_DURATION
- REALISTIC_LIST_START
- REALISTIC_LIST_VUS
- REALISTIC_LIST_DURATION
- REALISTIC_LIST_LIMIT

### 4.3 Variables de puerto local
- REALISTIC_AUTH_PORT
- REALISTIC_API_PORT
- REALISTIC_AUTH_PORT_FALLBACK
- REALISTIC_API_PORT_FALLBACK

## 5. Protocolo de Ejecucion
### 5.1 Inicializacion

```bash
cd /home/dwan13/muBench
chmod +x scripts/deploy_microk8s.sh
chmod +x RealisticServices/deploy-realistic.sh
chmod +x RealisticServices/run-k6-users-bulk.sh
chmod +x RealisticServices/run-controls-realistic.sh
chmod +x RealisticServices/controls/apply-control.sh
```

### 5.2 Corridas recomendadas
1. Sanity check:

```bash
./scripts/deploy_microk8s.sh --start --hybrid-quick
```

2. Corrida normal:

```bash
./scripts/deploy_microk8s.sh --start --hybrid
```

3. Corrida stress:

```bash
./scripts/deploy_microk8s.sh --start --hybrid-stress
```

4. Corrida con controles realistas:

```bash
./scripts/deploy_microk8s.sh --start --hybrid --hybrid-controls
```

## 6. Evidencia Minima Requerida
- JSON de carga realista: RealisticServices/results/k6-users-bulk-*.json
- Resumen automatico: RealisticServices/results/hybrid-k6-summary-*.txt
- Consolidado C1-C4: Testing/results/all-controls-comparison.csv
- Evidencia visual: Testing/results/all-controls-p95.png y Testing/results/all-controls-avg-vus.png
- Credenciales/runtime snapshot: ~/.mubench_credentials

## 7. Criterios de Exito
Se considera corrida valida si se cumplen simultaneamente:
1. El script principal finaliza sin error fatal.
2. Se genera al menos un archivo k6-users-bulk-*.json.
3. Se genera al menos un hybrid-k6-summary-*.txt.
4. El dashboard comparativo se publica y contiene panel "Resumen Hibrido k6 (Auto)".
5. Las APIs de login y usuarios responden correctamente bajo token valido.

## 8. Amenazas a la Validez
- Colision de puertos locales por procesos previos de port-forward.
- Variacion de recursos host (CPU/RAM) durante la corrida.
- Dependencia de estado previo en base de datos (numero de usuarios acumulados).
- Interferencias por trabajos concurrentes en MicroK8s.

Mitigaciones:
- Ejecutar limpieza de port-forward previo: pkill -f "port-forward".
- Reportar hardware utilizado y parametros exactos por corrida.
- Usar mismo perfil de carga para comparaciones entre replicas.

## 9. Recomendacion de Reporte
Para tesis o articulo, reportar por corrida:
- perfil (quick, normal, stress),
- users_created_total,
- users_listed_total,
- http_req_duration_p95_ms,
- http_req_failed_rate,
- timestamp y nombre de archivo de evidencia.
