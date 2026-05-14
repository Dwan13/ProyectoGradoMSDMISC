#!/usr/bin/env bash
set -euo pipefail

# Script maestro para automatizar el ciclo completo de pruebas de todos los controles (C1–C4)
# Aplica la configuración, ejecuta k6, recolecta métricas y guarda resultados por variante

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
K6_SCRIPT="${ROOT_DIR}/RealisticServices/k6/realistic-flow.js"
RESULTS_DIR="${ROOT_DIR}/Testing/results/auto_runs"
PROM_QUERY_SCRIPT="${ROOT_DIR}/Testing/analyze_k6_results.py"
PROM_CONSUMPTION_SCRIPT="${ROOT_DIR}/Testing/analyze_prometheus_metrics.py"
CREDENTIALS_SCRIPT="${ROOT_DIR}/scripts/get-demo-credentials.sh"
BASE_SERVICES_MANIFEST="${ROOT_DIR}/RealisticServices/k8s/02-services.yaml"
C1_NGINX_MANIFEST="${ROOT_DIR}/RealisticServices/k8s/07-c1-ingress-gateway.yaml"
C1_ISTIO_MANIFEST="${ROOT_DIR}/experiments/01-api-gateway-realistic/istio/01-services-istio.yaml"
C1_KONG_MANIFEST="${ROOT_DIR}/experiments/01-api-gateway-realistic/kong/01-services-kong.yaml"
C3_BASIC_MANIFEST="${ROOT_DIR}/RealisticServices/k8s/08-c3-networkpolicy.yaml"
C3_STRICT_MANIFEST="${ROOT_DIR}/RealisticServices/k8s/08-c3-networkpolicy-strict.yaml"
NS="realistic"
INVALID_RUNS_FILE="${RESULTS_DIR}/invalid-scenarios.csv"

mkdir -p "$RESULTS_DIR"
if [ ! -f "$INVALID_RUNS_FILE" ]; then
  echo "timestamp,control,variant,vus,auth_base,api_base,reason" > "$INVALID_RUNS_FILE"
fi


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

LOADS=(1)

AUTH_BASE_DEFAULT="https://localhost/auth"
API_BASE_DEFAULT="https://localhost/api"
K6_INSECURE_TLS_DEFAULT="true"

AUTH_BASE_NODEPORT_DEFAULT="http://localhost:30084"
API_BASE_NODEPORT_DEFAULT="http://localhost:30081"

C1_ISTIO_AUTH_BASE_DEFAULT="https://localhost:30997"
C1_ISTIO_API_BASE_DEFAULT="https://localhost:30997"
C1_KONG_AUTH_BASE_DEFAULT="https://localhost:30443"
C1_KONG_API_BASE_DEFAULT="https://localhost:30443"

reset_control_state() {
  # Limpia recursos de controles para evitar contaminación entre variantes.
  microk8s kubectl delete ingress realistic-gateway -n "$NS" --ignore-not-found
  microk8s kubectl delete ingress realistic-ingress -n "$NS" --ignore-not-found
  microk8s kubectl delete ingress kong-realistic-ingress -n "$NS" --ignore-not-found
  microk8s kubectl delete gateway.networking.istio.io realistic-gateway -n "$NS" --ignore-not-found
  microk8s kubectl delete virtualservice realistic-vs -n "$NS" --ignore-not-found
  microk8s kubectl delete gateway.networking.istio.io gateway -n default --ignore-not-found
  microk8s kubectl delete gateway.networking.istio.io istio-api-gateway -n istio-system --ignore-not-found
  microk8s kubectl delete virtualservice.networking.istio.io api -n mubench-realistic --ignore-not-found
  microk8s kubectl delete virtualservice.networking.istio.io api-virtualservice -n istio-system --ignore-not-found
  microk8s kubectl delete envoyfilter ratelimit-ingressgateway -n istio-system --ignore-not-found
  microk8s kubectl delete networkpolicy data-service-restrict postgres-restrict api-service-egress-restrict -n "$NS" --ignore-not-found

  microk8s kubectl label namespace "$NS" istio-injection=disabled --overwrite
}

apply_control_variant() {
  local control="$1"
  local variant="$2"
  local manifest_dir="$3"

  microk8s kubectl apply -f "$BASE_SERVICES_MANIFEST"
  microk8s kubectl set env deployment/api-service -n "$NS" RATE_LIMIT_ENABLED=false RATE_LIMIT_RPM=600

  case "$control" in
    C1)
      case "$variant" in
        baseline)
          microk8s kubectl apply -f "$C1_NGINX_MANIFEST"
          ;;
        istio)
          microk8s kubectl apply -f "$C1_ISTIO_MANIFEST"
          ;;
        kong)
          microk8s kubectl apply -f "$C1_KONG_MANIFEST"
          ;;
      esac
      ;;
    C2)
      if [ -d "$manifest_dir" ]; then
        for f in "$manifest_dir"/*.yaml; do
          if [ -f "$f" ]; then
            echo "[INFO] Aplicando $f"
            microk8s kubectl apply -f "$f"
          fi
        done
      fi
      ;;
    C3)
      case "$variant" in
        baseline)
          ;;
        basic)
          microk8s kubectl apply -f "$C3_BASIC_MANIFEST"
          ;;
        strict)
          microk8s kubectl apply -f "$C3_STRICT_MANIFEST"
          ;;
      esac
      ;;
    C4)
      case "$variant" in
        baseline)
          microk8s kubectl set env deployment/api-service -n "$NS" RATE_LIMIT_ENABLED=false RATE_LIMIT_RPM=600
          microk8s kubectl rollout restart deployment/api-service -n "$NS"
          ;;
        moderate)
          microk8s kubectl set env deployment/api-service -n "$NS" RATE_LIMIT_ENABLED=true RATE_LIMIT_RPM=1200
          microk8s kubectl rollout restart deployment/api-service -n "$NS"
          ;;
        strict)
          microk8s kubectl set env deployment/api-service -n "$NS" RATE_LIMIT_ENABLED=true RATE_LIMIT_RPM=300
          microk8s kubectl rollout restart deployment/api-service -n "$NS"
          ;;
      esac
      ;;
  esac
}

run_smoke_check() {
  local auth_base="$1"
  local api_base="$2"
  local host_header="${3:-}"
  local tries=12
  local sleep_secs=2

  for ((i=1; i<=tries; i++)); do
    local login_resp
    if [ -n "$host_header" ]; then
      login_resp=$(curl -k -sS -X POST "${auth_base}/login" -H "Host: ${host_header}" -H 'Content-Type: application/json' -d '{"username":"demo","password":"demo123"}' || true)
    else
      login_resp=$(curl -k -sS -X POST "${auth_base}/login" -H 'Content-Type: application/json' -d '{"username":"demo","password":"demo123"}' || true)
    fi

    local token
    token=$(echo "$login_resp" | sed -n 's/.*"access_token"[ ]*:[ ]*"\([^"]*\)".*/\1/p')

    if [ -n "$token" ]; then
      local profile_resp
      if [ -n "$host_header" ]; then
        profile_resp=$(curl -k -sS -H "Host: ${host_header}" -H "Authorization: Bearer ${token}" "${api_base}/profile?user_id=1" || true)
      else
        profile_resp=$(curl -k -sS -H "Authorization: Bearer ${token}" "${api_base}/profile?user_id=1" || true)
      fi
      if echo "$profile_resp" | grep -q '"user"'; then
        return 0
      fi
    fi

    sleep "$sleep_secs"
  done

  return 1
}

# El flujo k6 obtiene token en cada iteracion; este valor solo se mantiene por compatibilidad.
TOKEN=$(bash "$CREDENTIALS_SCRIPT" 2>/dev/null | grep -Eo '^[A-Za-z0-9\._-]+' | head -n 1 || true)
if [ -z "$TOKEN" ]; then
  echo "[WARN] No se pudo obtener token demo previo; k6 hara login en runtime."
  TOKEN="unused"
fi

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

    reset_control_state
    apply_control_variant "$CONTROL" "$VARIANT" "$MANIFEST_DIR"

    if [[ "$CONTROL" == "C1" && "$VARIANT" == "istio" ]]; then
      export AUTH_BASE="$C1_ISTIO_AUTH_BASE_DEFAULT"
      export API_BASE="$C1_ISTIO_API_BASE_DEFAULT"
      export HOST_HEADER="realistic.local"
    elif [[ "$CONTROL" == "C1" && "$VARIANT" == "kong" ]]; then
      export AUTH_BASE="$C1_KONG_AUTH_BASE_DEFAULT"
      export API_BASE="$C1_KONG_API_BASE_DEFAULT"
      export HOST_HEADER="localhost"
    elif [[ "$CONTROL" == "C1" ]]; then
      export AUTH_BASE="$AUTH_BASE_DEFAULT"
      export API_BASE="$API_BASE_DEFAULT"
      export HOST_HEADER=""
    else
      export AUTH_BASE="$AUTH_BASE_NODEPORT_DEFAULT"
      export API_BASE="$API_BASE_NODEPORT_DEFAULT"
      export HOST_HEADER=""
    fi
    export K6_INSECURE_SKIP_TLS_VERIFY="${K6_INSECURE_SKIP_TLS_VERIFY:-$K6_INSECURE_TLS_DEFAULT}"

    # Esperar a que los despliegues objetivo estén listos para reducir sesgo por cold start/rollout.
    for dep in auth-service data-service api-service; do
      microk8s kubectl rollout status deployment/"$dep" -n "$NS" --timeout=180s
    done

    # Gate funcional: solo correr benchmark si login/profile funcionan en el endpoint de este escenario.
    if ! run_smoke_check "$AUTH_BASE" "$API_BASE" "$HOST_HEADER"; then
      echo "[ERROR] Smoke check fallido para $CONTROL $VARIANT (AUTH_BASE=$AUTH_BASE API_BASE=$API_BASE). Escenario marcado invalido y omitido."
      printf "%s,%s,%s,%s,%s,%s,%s\n" "$(date -Iseconds)" "$CONTROL" "$VARIANT" "$VUS" "$AUTH_BASE" "$API_BASE" "smoke_check_failed" >> "$INVALID_RUNS_FILE"
      continue
    fi
    echo "[INFO] Smoke check OK para $CONTROL $VARIANT (AUTH_BASE=$AUTH_BASE API_BASE=$API_BASE)"

    # Ejecutar prueba k6 con el número de VUs
    set +e
    k6 run \
      -e AUTH_BASE="$AUTH_BASE" \
      -e API_BASE="$API_BASE" \
      -e K6_INSECURE_SKIP_TLS_VERIFY="$K6_INSECURE_SKIP_TLS_VERIFY" \
      -e HOST_HEADER="$HOST_HEADER" \
      -e TOKEN="$TOKEN" \
      --vus $VUS --duration 60s \
      --out json="$OUT_JSON" \
      "$K6_SCRIPT"
    K6_EXIT=$?
    set -e

    if [ "$K6_EXIT" -ne 0 ]; then
      echo "[WARN] k6 termino con codigo $K6_EXIT para $CONTROL $VARIANT $VUS VUs. Continuando con siguientes escenarios."
    fi

    echo "[INFO] k6 terminado para $CONTROL $VARIANT $VUS VUs: $OUT_JSON"

    # Recolectar métricas de Prometheus (CPU, Mem, etc.)
    # if [ -f "$PROM_QUERY_SCRIPT" ]; then
    #   python3 "$PROM_QUERY_SCRIPT" --control "$CONTROL" --variant "$VARIANT" --vus "$VUS" --k6 "$OUT_JSON" --out "$OUT_METRICS"
    #   echo "[INFO] Métricas recolectadas: $OUT_METRICS"
    # fi
  done
done

echo "\n[OK] Experimentos de todos los controles completados. Resultados en $RESULTS_DIR"

if [ -f "$PROM_CONSUMPTION_SCRIPT" ]; then
  echo "[INFO] Generando resumen de consumo CPU/Memoria desde Prometheus..."
  python3 "$PROM_CONSUMPTION_SCRIPT"
fi
