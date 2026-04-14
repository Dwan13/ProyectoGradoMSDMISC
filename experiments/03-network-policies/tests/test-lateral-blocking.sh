#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_FILE="$ROOT_DIR/results/logs/lateral-blocking.log"

TMP_POD="netpol-test-client"
microk8s kubectl delete pod "$TMP_POD" -n default --ignore-not-found >/dev/null 2>&1 || true

microk8s kubectl run "$TMP_POD" -n default \
  --image=curlimages/curl:8.7.1 \
  --restart=Never \
  --command -- sleep 180 >/dev/null

microk8s kubectl wait --for=condition=Ready pod/"$TMP_POD" -n default --timeout=120s >/dev/null

set +e
OUT=$(microk8s kubectl exec -n default "$TMP_POD" -- curl -sS -m 5 -o /dev/null -w "%{http_code}" http://sdb1.default.svc.cluster.local:80/process 2>/dev/null)
RC=$?
set -e

{
  echo "timestamp=$(date +'%F %T')"
  echo "curl_exit_code=$RC"
  echo "http_code=${OUT:-none}"
  if [[ "$RC" -ne 0 ]] || [[ "$OUT" == "000" ]] || [[ "$OUT" == "403" ]] || [[ "$OUT" == "503" ]]; then
    echo "blocked=true"
  else
    echo "blocked=false"
  fi
} > "$LOG_FILE"

microk8s kubectl delete pod "$TMP_POD" -n default --ignore-not-found >/dev/null 2>&1 || true

echo "[netpol] Lateral blocking test registrado en $LOG_FILE"
