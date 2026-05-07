#!/usr/bin/env bash
set -euo pipefail

# Script maestro para automatizar el ciclo completo de pruebas de todos los controles (C1–C4)
# Aplica la configuración, ejecuta k6, recolecta métricas y guarda resultados por variante

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
K6_SCRIPT="${ROOT_DIR}/RealisticServices/k6/realistic-flow.js"
RESULTS_DIR="${ROOT_DIR}/Testing/results/auto_runs"
PROM_QUERY_SCRIPT="${ROOT_DIR}/Testing/analyze_k6_results.py"
CREDENTIALS_SCRIPT="${ROOT_DIR}/scripts/get-demo-credentials.sh"

mkdir -p "$RESULTS_DIR"


# Definición de controles y variantes
EXPERIMENTS=(
  "C1 baseline   ${ROOT_DIR}/experiments/01-api-gateway-realistic/baseline/"
  "C1 istio      ${ROOT_DIR}/experiments/01-api-gateway-realistic/istio/"
  "C1 kong       ${ROOT_DIR}/experiments/01-api-gateway-realistic/kong/"

  "C2 baseline   ${ROOT_DIR}/experiments/02-mtls-service-mesh-realistic/baseline/"
  "C2 istio-mtls ${ROOT_DIR}/experiments/02-mtls-service-mesh-realistic/istio-mtls/"
  "C2 linkerd-mtls ${ROOT_DIR}/experiments/02-mtls-service-mesh-realistic/linkerd-mtls/"

  "C3 baseline   ${ROOT_DIR}/experiments/03-network-policies-realistic/baseline/"
  "C3 basic      ${ROOT_DIR}/experiments/03-network-policies-realistic/basic/"
  "C3 strict     ${ROOT_DIR}/experiments/03-network-policies-realistic/strict/"

  "C4 baseline   ${ROOT_DIR}/experiments/04-rate-limiting-realistic/baseline/"
  "C4 moderate   ${ROOT_DIR}/experiments/04-rate-limiting-realistic/moderate/"
  "C4 strict     ${ROOT_DIR}/experiments/04-rate-limiting-realistic/strict/"
)

# Niveles de carga (VUs)
LOADS=(1 5 10 20)

# Obtener token demo
TOKEN=$(bash "$CREDENTIALS_SCRIPT" | head -n 1)
if [ -z "$TOKEN" ]; then
  echo "[ERROR] No se pudo obtener el token demo."
  exit 1
fi

done

for EXP in "${EXPERIMENTS[@]}"; do
  set -- $EXP
  CONTROL="$1"
  VARIANT="$2"
  MANIFEST_DIR="$3"

  for VUS in "${LOADS[@]}"; do
    STAMP=$(date +%Y%m%d_%H%M%S)
    OUT_JSON="$RESULTS_DIR/${CONTROL}_${VARIANT}_${VUS}vus_${STAMP}.json"
    OUT_METRICS="$RESULTS_DIR/${CONTROL}_${VARIANT}_${VUS}vus_${STAMP}_metrics.csv"

    echo "\n[INFO] === Ejecutando $CONTROL $VARIANT con $VUS VUs ==="
    # Aplicar manifiestos extra (si existen)
    if [ -d "$MANIFEST_DIR" ]; then
      for f in "$MANIFEST_DIR"/*.yaml; do
        if [ -f "$f" ]; then
          echo "[INFO] Aplicando $f"
          microk8s kubectl apply -f "$f"
        fi
      done
    fi

    # Esperar a que los pods estén listos
    sleep 10

    # Ejecutar prueba k6 con el número de VUs
    k6 run \
      -e AUTH_BASE="https://realistic.local/auth" \
      -e API_BASE="https://realistic.local/api" \
      -e TOKEN="$TOKEN" \
      --vus $VUS --duration 60s \
      --out json="$OUT_JSON" \
      "$K6_SCRIPT"

    echo "[INFO] k6 terminado para $CONTROL $VARIANT $VUS VUs: $OUT_JSON"

    # Recolectar métricas de Prometheus (CPU, Mem, etc.)
    if [ -f "$PROM_QUERY_SCRIPT" ]; then
      python3 "$PROM_QUERY_SCRIPT" --control "$CONTROL" --variant "$VARIANT" --vus "$VUS" --k6 "$OUT_JSON" --out "$OUT_METRICS"
      echo "[INFO] Métricas recolectadas: $OUT_METRICS"
    fi
  done
done

echo "\n[OK] Experimentos de todos los controles completados. Resultados en $RESULTS_DIR"
