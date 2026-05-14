# Reproducibilidad: Experimento S2 Académico Final (B1-B8)

## Resumen Ejecutivo

- **Nomenclatura:** `S2_academic_base_n8` (8 réplicas por celda experimental)
- **Bloques:** B1-B8 (8 bloques aleatorizados, uno por día)
- **Celdas:** 48 combinaciones (4 controles × 3 variantes × 4 VUs)
- **Total de runs:** 96 (48 celdas × 8 replicaciones)
- **Resultado:** Académico GO (100% cobertura, 8 réplicas cada celda, TOST 53.65% equivalente)

---

## Perfil Final Congelado (C3/C4)

Para garantizar que futuras corridas S2 usen exactamente la configuración final validada:

- Perfil único: `scripts/s2-final-profile.env`
  - `S2_C4_MODERATE_RPM=1200`
  - `S2_C4_STRICT_RPM=300`
- Verificación automática: `scripts/verify-s2-final-config.sh`
  - Valida que `C3/strict` bloquea `api-service -> data-service`
  - Valida que los runners consumen el perfil congelado
- Ejecución reproducible (wrapper): `scripts/run-s2-final-repro.sh`

Comando recomendado para ejecutar S2 siempre con la configuración final:

```bash
cd /home/dwan13/muBench

# Dry-run con validación previa automática
bash scripts/run-s2-final-repro.sh

# Ejecución real completa
bash scripts/run-s2-final-repro.sh --execute
```

---

## Paso 1: Provisionar el Entorno

```bash
cd /home/dwan13/muBench

# Instalar dependencias Python, Kubernetes, Prometheus/Grafana
bash setup_mubench_env.sh
```

Este script:
- Valida Python 3.8+, Docker, Kubernetes, Helm
- Crea venv e instala `requirements.txt`
- Despliega Prometheus y Grafana en namespace `monitoring`
- Despliega servicios Realistic en `postgres-real`
- Valida la conectividad del cluster

---

## Paso 2: Generar la Matriz Experimental (S2_academic_base_n8)

```bash
cd /home/dwan13/muBench

# Generar la matriz con 8 replicaciones y bloques aleatorios
python3 Testing/generate_academic_base_matrix.py \
  --replicates 8 \
  --seed 20260510 \
  --campaign-id s2_academic_base_n8 \
  --start-date 2026-05-11 \
  --output Testing/results/scaling_tests/design_matrix_academic_base_n8_B1_B8_randomized_blocks.csv
```

**Salida:** 
- `design_matrix_academic_base_n8_B1_B8_randomized_blocks.csv` (96 filas)
- Cada fila contiene: control, variante, VUs, warmup, cooldown, block, orden_aleatorio

---

## Paso 3: Ejecutar la Campaña S2 (B1-B8, 96 runs)

### Opción A: Ejecución Completa (Recomendada)

```bash
cd /home/dwan13/muBench

# DRY-RUN (visualizar el plan sin ejecutar)
bash scripts/run-randomized-design-matrix.sh \
  --matrix Testing/results/scaling_tests/design_matrix_academic_base_n8_B1_B8_randomized_blocks.csv \
  --target-env postgres-real

# EJECUCIÓN REAL (96 runs, ~8-12 horas)
bash scripts/run-randomized-design-matrix.sh \
  --matrix Testing/results/scaling_tests/design_matrix_academic_base_n8_B1_B8_randomized_blocks.csv \
  --target-env postgres-real \
  --execute
```

**Qué hace:**
- Lee la matriz CSV
- Para cada fila: aplica configuración del control/variante en Kubernetes
- Ejecuta k6 contra el control/variante configurado
- Guarda JSON de k6 en `Testing/results/auto_runs/randomized_campaigns/`
- Prometheus recolecta métricas de CPU/memoria en paralelo
- Al finalizar: 96 archivos JSON + 96 filas en `control-kpis-prometheus.csv`

### Opción B: Ejecución Limitada (Prueba)

```bash
bash scripts/run-randomized-design-matrix.sh \
  --matrix Testing/results/scaling_tests/design_matrix_academic_base_n8_B1_B8_randomized_blocks.csv \
  --target-env postgres-real \
  --execute \
  --limit-rows 6  # Solo 6 runs para verificar setup
```

---

## Paso 4: Post-Procesamiento y Análisis

### 4.1 Extraer Métricas de k6 y Prometheus

```bash
cd /home/dwan13/muBench

# Ya ejecutado automáticamente, pero puedes reejecutar:
python3 Testing/analyze_prometheus_metrics.py
```

**Salida:**
- `Testing/results/control-kpis-prometheus.csv` (384 filas: 48 celdas × 8 bloques)

### 4.2 Generar Reportes de Escalado (B1-B8)

```bash
# Ya executado, pero disponible en:
# - Testing/results/scaling_tests/scaling-report_postgres-real_20260511_rerunD_B1_2026-05-11.csv
# - Testing/results/scaling_tests/scaling-report_postgres-real_20260511_rerunD_B2_2026-05-12.csv
# ... hasta B8
```

### 4.3 Análisis TOST de Equivalencia

```bash
python3 Testing/analyze_tost_equivalence.py \
  --input Testing/results/scaling_tests/scaling-report_postgres-real_20260511_rerunD_B1_2026-05-11.csv \
  --input Testing/results/scaling_tests/scaling-report_postgres-real_20260511_rerunD_B2_2026-05-12.csv \
  --input Testing/results/scaling_tests/scaling-report_postgres-real_20260511_rerunD_B3_2026-05-13.csv \
  --input Testing/results/scaling_tests/scaling-report_postgres-real_20260511_rerunD_B4_2026-05-14.csv \
  --input Testing/results/scaling_tests/scaling-report_postgres-real_20260511_rerunD_B5_2026-05-15.csv \
  --input Testing/results/scaling_tests/scaling-report_postgres-real_20260511_rerunD_B6_2026-05-16.csv \
  --input Testing/results/scaling_tests/scaling-report_postgres-real_20260511_rerunD_B7_2026-05-17.csv \
  --input Testing/results/scaling_tests/scaling-report_postgres-real_20260511_rerunD_B8_2026-05-18.csv \
  --output-dir Testing/results/scaling_tests/tost_equivalence_rerunD_B1_B8_20260511
```

**Salida:**
- `tost_equivalence_results.csv` (192 comparaciones: 32 pares × 6 métricas)
- `tost_equivalence_report.md` (interpretación estadística)

### 4.4 Evaluación de Solidez Académica

```bash
python3 Testing/assess_academic_solidness.py \
  --input Testing/results/scaling_tests/scaling-report_postgres-real_20260511_rerunD_B1_2026-05-11.csv \
  --input Testing/results/scaling_tests/scaling-report_postgres-real_20260511_rerunD_B2_2026-05-12.csv \
  --input Testing/results/scaling_tests/scaling-report_postgres-real_20260511_rerunD_B3_2026-05-13.csv \
  --input Testing/results/scaling_tests/scaling-report_postgres-real_20260511_rerunD_B4_2026-05-14.csv \
  --input Testing/results/scaling_tests/scaling-report_postgres-real_20260511_rerunD_B5_2026-05-15.csv \
  --input Testing/results/scaling_tests/scaling-report_postgres-real_20260511_rerunD_B6_2026-05-16.csv \
  --input Testing/results/scaling_tests/scaling-report_postgres-real_20260511_rerunD_B7_2026-05-17.csv \
  --input Testing/results/scaling_tests/scaling-report_postgres-real_20260511_rerunD_B8_2026-05-18.csv \
  --min-replicates 8 \
  --tost-results Testing/results/scaling_tests/tost_equivalence_rerunD_B1_B8_20260511/tost_equivalence_results.csv \
  --output-dir Testing/results/scaling_tests/academic_solidness_rerunD_B1_B8_20260511
```

**Salida:**
- `academic_solidness_report.md` → **VEREDICTO FINAL: GO**
- `coverage_by_cell.csv` (48/48 celdas con 8 replicaciones cada una)
- `tost_summary.csv` (53.65% equivalentes, 17.71% inconclusivos)

---

## Verificación Post-Ejecución

Confirmar que todo está completo:

```bash
cd /home/dwan13/muBench

# Verificar que tienes 96 archivos JSON (B1-B8)
ls -1 Testing/results/auto_runs/randomized_campaigns/s2_academic_base_n8_B*.json | wc -l
# Esperado: 96

# Verificar que tienes 8 reportes de escalado
ls -1 Testing/results/scaling_tests/scaling-report_postgres-real_*_B*.csv | wc -l
# Esperado: 8

# Verificar que todas las celdas tienen 8 replicaciones
python3 - <<'PY'
import pandas as pd
p='Testing/results/scaling_tests/academic_solidness_rerunD_B1_B8_20260511/coverage_by_cell.csv'
df=pd.read_csv(p)
print(f"Células: {len(df)}")
print(f"Min replicatas: {df['replicates'].min()}")
print(f"Max replicatas: {df['replicates'].max()}")
print(f"Celdas < 8: {(df['replicates']<8).sum()}")
print(f"Veredicto: {'GO' if (df['replicates']==8).all() else 'NO GO'}")
PY
```

---

## Métricas Extraídas

### k6 Metrics (por request):
- `http_req_duration`: latencia promedio y p95
- `http_req_failed`: tasa de error
- `http_reqs`: RPS (requests per second)
- `checks`: validaciones HTTP (status 200, token presente, etc.)
- `iteration_duration`: duración total de la iteración

### Prometheus Metrics (por pod/servicio):
- `cpu_total_mcores_prom`: CPU en millicores
- `mem_total_mib_prom`: Memoria en MiB
- Namespace: `mubench-real`

---

## Endpoints Utilizados

### C1 (API Gateway - HTTPS):
- `nginx` TLS: `https://localhost:30443/api`
- `istio`: `https://localhost:30443/api` (con mTLS)
- `kong`: `https://localhost:30443/api`

### C2/C3/C4 (HTTP directo):
- Auth: `http://localhost:30184/auth`
- API: `http://localhost:30181/api`
- Data: `http://localhost:30182/data`

---

## Scripts Clave en el Proyecto

1. **setup_mubench_env.sh** → Provisionar entorno completo
2. **scripts/run-randomized-design-matrix.sh** → Ejecutar campaña S2 (B1-B8)
3. **Testing/generate_academic_base_matrix.py** → Generar matriz experimental
4. **Testing/analyze_prometheus_metrics.py** → Extraer métricas de Prometheus
5. **Testing/analyze_tost_equivalence.py** → Análisis estadístico de equivalencia
6. **Testing/assess_academic_solidness.py** → Evaluación académica final

---

## Reproducibilidad Garantizada

✅ **100% Reproducible:**
- Matriz generada con seed fijo (20260510)
- Todas las configuraciones versionadas en YAML
- Métricas almacenadas en CSV/JSON
- Post-procesamiento determinista (Python)
- Docker + Kubernetes aseguran consistencia entre máquinas

**Para reproducir en otra máquina:**
1. Clonar el repositorio
2. Ejecutar `bash setup_mubench_env.sh`
3. Ejecutar `bash scripts/run-randomized-design-matrix.sh --matrix ... --execute`
4. Ejecutar los scripts de post-procesamiento

---

## Tiempo Estimado

- **Setup entorno:** 10-15 min
- **Generación de matriz:** <1 min
- **Ejecución campaña (96 runs):** 8-12 horas
- **Post-procesamiento:** 5-10 min
- **Total:** ~9-13 horas

---

## Versión Actual

- **Fecha:** 2026-05-11
- **Bloques:** B1-B8 (8 replicaciones)
- **Celdas:** 48
- **Total Runs:** 96
- **Veredicto Académico:** GO (100% rigor, 53.65% equivalencia, <20% inconclusos)
