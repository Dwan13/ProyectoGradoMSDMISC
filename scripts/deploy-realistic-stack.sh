#!/usr/bin/env bash
set -euo pipefail

# 1. Generar y aplicar secreto TLS
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${SCRIPT_DIR}/.."


# Eliminar el manifiesto estático si existe para evitar conflicto
if [ -f "$ROOT_DIR/RealisticServices/k8s/ingress-tls-secret.yaml" ]; then
  echo "[INFO] Eliminando manifiesto estático de TLS para evitar conflicto con el secreto generado dinámicamente."
  rm -f "$ROOT_DIR/RealisticServices/k8s/ingress-tls-secret.yaml"
fi

# Generar y aplicar secreto TLS
bash "$SCRIPT_DIR/generate-tls-secret.sh"

# 2. Desplegar microservicios realistas y manifiestos
bash "$ROOT_DIR/RealisticServices/deploy-realistic.sh"

# 3. Desplegar Prometheus y Grafana (si no están desplegados)
if ! microk8s kubectl get svc -n monitoring grafana >/dev/null 2>&1; then
  echo "[INFO] Desplegando Prometheus y Grafana..."
  for f in "$ROOT_DIR/Monitoring/kubernetes-full-monitoring/"*.yaml; do
    # Solo aplicar archivos YAML que sean manifiestos válidos (evitar .json, .md, .yaml de valores, etc.)
    if grep -qE '^(apiVersion|kind):' "$f"; then
      microk8s kubectl apply -f "$f"
    else
      echo "[WARN] Omitiendo archivo no manifiesto: $f"
    fi
  done
else
  echo "[INFO] Prometheus y Grafana ya están desplegados."
fi

# 4. Esperar a que los pods estén listos
READY=0
for i in {1..30}; do
  NOT_READY=$(microk8s kubectl get pods -A | grep -E 'auth-service|api-service|data-service|postgres|grafana|prometheus' | grep -v 'Running' | grep -v 'Completed' | wc -l)
  if [ "$NOT_READY" -eq 0 ]; then
    READY=1
    break
  fi
  echo "[INFO] Esperando a que los pods estén listos... ($i/30)"
  sleep 10
done
if [ "$READY" -ne 1 ]; then
  echo "[ERROR] Algunos pods no están listos tras 5 minutos."
  microk8s kubectl get pods -A
  exit 1
fi

# 5. Mostrar estado de pods y servicios
echo "\n[INFO] Estado de los pods relevantes:"
microk8s kubectl get pods -A | grep -E 'auth-service|api-service|data-service|postgres|grafana|prometheus'

echo "\n[INFO] Servicios expuestos en el cluster:"
microk8s kubectl get svc -A | grep -E 'auth-service|api-service|data-service|postgres|grafana|prometheus'

# 6. Mostrar endpoints
GRAFANA_URL="http://127.0.0.1:30001"
PROM_URL="http://127.0.0.1:30000"
echo "[OK] Stack realista desplegado. Accede a Grafana: $GRAFANA_URL"
echo "[OK] Prometheus: $PROM_URL"
echo "[OK] Servicios expuestos por HTTPS en realistic.local"

# 7. Sugerencia para pruebas de carga
cat <<EOF

Para ejecutar pruebas de carga:
- Usa los scripts de k6 en RealisticServices/k6/ apuntando a https://realistic.local/api o /auth
- Asegúrate de tener '127.0.0.1 realistic.local' en /etc/hosts
- Las métricas estarán disponibles en Grafana
