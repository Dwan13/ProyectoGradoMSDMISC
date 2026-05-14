# Comandos en Vivo para Ver Cambios en Grafana

Este flujo permite:
- Elegir escenario (`s1`, `s2`, `s3`, `s4`)
- Elegir control/variante (cuando aplique)
- Ejecutar operación (`login`, `create-user`, `list-users`, `create-and-list`)
- Observar impacto en tiempo real en Grafana

Script helper:
- `scripts/live-control-and-request.sh`

## 1) Preparar observación en tiempo real

```bash
# Detectar servicio de Grafana disponible
kubectl get svc -A | grep -Ei 'grafana|prometheus-grafana'

# Usa el que exista (uno de estos dos nombres típicos)
kubectl -n monitoring port-forward svc/prometheus-grafana 3000:80
# o
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80
```

Abrir:
- `http://127.0.0.1:3000`

En otra terminal (opcional, recursos live del namespace):
```bash
watch -n 2 "kubectl top pods -n mubench-real"
```

## 2) Escenario 2 (S2) con control seleccionable

### Sin control (baseline) + crear y listar usuario
```bash
bash scripts/live-control-and-request.sh \
  --scenario s2 \
  --control none \
  --action create-and-list \
  --new-user live_s2_base_001 \
  --new-email live_s2_base_001@example.com
```

### C1 istio + crear/listar
```bash
bash scripts/live-control-and-request.sh \
  --scenario s2 \
  --control C1 \
  --variant istio \
  --action create-and-list \
  --new-user live_s2_c1_istio_001 \
  --new-email live_s2_c1_istio_001@example.com
```

### C3 strict + crear/listar
```bash
bash scripts/live-control-and-request.sh \
  --scenario s2 \
  --control C3 \
  --variant strict \
  --action create-and-list \
  --new-user live_s2_c3_strict_001 \
  --new-email live_s2_c3_strict_001@example.com
```

### C4 strict (rate-limit agresivo) + crear/listar
```bash
bash scripts/live-control-and-request.sh \
  --scenario s2 \
  --control C4 \
  --variant strict \
  --action create-and-list \
  --new-user live_s2_c4_strict_001 \
  --new-email live_s2_c4_strict_001@example.com
```

## 3) Escenario 4 (S4) equivalente funcional

S4 en este helper se usa sin toggles de control (baseline equivalente):
```bash
bash scripts/live-control-and-request.sh \
  --scenario s4 \
  --control none \
  --action create-and-list \
  --new-user live_s4_001 \
  --new-email live_s4_001@example.com
```

## 4) Escenario 3 nativo (S3)

S3 nativo no es CRUD de usuarios; para observar en vivo:
```bash
bash scripts/live-control-and-request.sh \
  --scenario s3 \
  --control none \
  --action ping-s3
```

## 5) Pruebas rápidas separadas por acción

### Solo login (S2)
```bash
bash scripts/live-control-and-request.sh --scenario s2 --control none --action login
```

### Solo create-user (S2)
```bash
bash scripts/live-control-and-request.sh \
  --scenario s2 --control none --action create-user \
  --new-user live_only_create_001 \
  --new-email live_only_create_001@example.com
```

### Solo list-users (S2)
```bash
bash scripts/live-control-and-request.sh \
  --scenario s2 --control none --action list-users --limit 200
```

## 6) Qué variantes soporta S2 en el helper

- `C1`: `baseline`, `istio`, `kong`
- `C2`: `baseline`, `istio-mtls`, `linkerd-mtls`
- `C3`: `baseline`, `basic`, `strict`
- `C4`: `baseline`, `moderate`, `strict`

## Nota metodológica

- Para comparación funcional de crear/listar usuarios: usa S2 y S4.
- S3 nativo se mantiene como validación externa avanzada, no como equivalente semántico CRUD.

## 7) Comparativas baseline vs variantes por control y metrica

Generar todas las comparativas (S2 y S3):

```bash
python3 scripts/generate-control-comparison-report.py
```

Salidas principales:
- `Testing/results/control_comparison/control_comparison_long.csv`
- `Testing/results/control_comparison/control_variant_means.csv`
- `Testing/results/control_comparison/control_comparison_report.md`

Graficas por control (todas las metricas en un panel):
- `Testing/plots/control_comparison/S2_C1_variants_metrics.png`
- `Testing/plots/control_comparison/S2_C2_variants_metrics.png`
- `Testing/plots/control_comparison/S2_C3_variants_metrics.png`
- `Testing/plots/control_comparison/S2_C4_variants_metrics.png`
- `Testing/plots/control_comparison/S3_C1_variants_metrics.png`
- `Testing/plots/control_comparison/S3_C2_variants_metrics.png`
- `Testing/plots/control_comparison/S3_C3_variants_metrics.png`
- `Testing/plots/control_comparison/S3_C4_variants_metrics.png`

Ejemplo exacto pedido (baseline vs istio vs linkerd, C2):
- Revisa `S2_C2_variants_metrics.png` y `S3_C2_variants_metrics.png`.
- Para cruce S2 vs S3 por metrica en una variante concreta:
  - `Testing/plots/control_comparison/cross_C2_baseline_p95_ms.png`
  - `Testing/plots/control_comparison/cross_C2_istio-mtls_p95_ms.png`
  - `Testing/plots/control_comparison/cross_C2_linkerd-mtls_p95_ms.png`

Matriz completa de cruces S2 vs S3 por control/variante/metrica:
- Prefijo de archivos: `Testing/plots/control_comparison/cross_*.png`

### Filtros para Grafana (dataset largo)

Si conectas `control_comparison_long.csv` como datasource CSV/Infinity:
- Filtro 1: `control` (C1, C2, C3, C4)
- Filtro 2: `metric` (avg_ms, p95_ms, err_pct, rps, cpu_mcores, mem_mib)
- Filtro 3: `scenario` (S2, S3)
- Series: `variant`
- Eje X: `vus`
