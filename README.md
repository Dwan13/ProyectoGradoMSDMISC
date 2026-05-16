# muBench (Entrega enfocada en S2, S3, S4 y S6)

Este repositorio esta preparado para ejecutar y validar solo los escenarios:
- S2: Postgres real con controles C1-C4
- S3: muBench advanced (control matrix)
- S4: semantic equivalent
- S6: campana integrada final (quality + security)

Todo el flujo documental se centraliza en este README.

## 1. Requisitos

Requisitos minimos en Linux:
- kubectl
- MicroK8s (o cluster Kubernetes compatible)
- Docker
- Python 3.10+
- pip
- k6

Verificacion rapida:
```bash
kubectl version --client
microk8s status || true
python3 --version
k6 version
```

## 2. Preparacion del entorno

Desde raiz del repo:
```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

Si necesitas validacion base del host:
```bash
bash scripts/validate_environment.sh
```

## 3. Levantar escenarios

### S2 (postgres real)
```bash
bash scripts/setup-postgres-real-scenario.sh
```

### S3 (mubench advanced)
```bash
bash scripts/setup-scenario3-mubench-advanced.sh
```

### S4 (semantic equivalent)
```bash
bash scripts/setup-scenario4-semantic-equivalent.sh
```

## 4. Ejecutar pruebas

### S2 final reproducible
Dry run:
```bash
bash scripts/run-s2-final-repro.sh
```

Ejecucion real:
```bash
bash scripts/run-s2-final-repro.sh --execute
```

### S3 scaling por controles
```bash
bash scripts/run-scaling-scenario3-controls.sh
```

### S4 scaling semantic equivalent
```bash
bash scripts/run-scaling-scenario4-semantic-equivalent.sh
```

### S6 integrado (campana final)
Dry run:
```bash
bash scripts/run-s6-integrated-repro.sh
```

Ejecucion real:
```bash
bash scripts/run-s6-integrated-repro.sh --execute --continue-on-readiness-fail
```

## 5. Analisis de resultados S6

Consolidar metricas desde resultados NDJSON:
```bash
python3 Testing/analyze_s6_integrated_results.py
```

Analisis estadistico final y reporte:
```bash
python3 Testing/s6_statistical_analysis.py
```

Salida esperada principal:
- CSV consolidado en `Testing/results/scaling_tests/`
- Reporte y graficas en `Testing/results/s6_analysis/`

## 6. Comandos utiles de validacion

Compilacion rapida del analizador:
```bash
python3 -m py_compile Testing/s6_statistical_analysis.py
```

Estado de pods:
```bash
kubectl get pods -A
```

Recursos:
```bash
kubectl top nodes
kubectl top pods -A
```

## 7. Flujo recomendado de entrega (S2/S3/S4/S6)

1. Preparar entorno y validar prerequisitos.
2. Levantar escenario objetivo.
3. Ejecutar pruebas del escenario.
4. Para S6, correr consolidacion y analisis estadistico.
5. Verificar artefactos generados en `Testing/results/`.

## 8. Notas de alcance

- Esta entrega excluye intencionalmente S1 y addons no necesarios para S2/S3/S4/S6.
- La operacion diaria de apagado/arranque puede apoyarse en:
  - `scripts/graceful-shutdown.sh`
  - `scripts/graceful-startup.sh`
