#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CFG_DIR="$ROOT_DIR/experiments/05-mubench-advanced/Configs"
OUT_DIR="$ROOT_DIR/experiments/05-mubench-advanced/SimulationWorkspace"
NS="mubench-advanced"

SG_CFG="$CFG_DIR/ServiceGraphParameters.advanced.json"
WM_CFG="$CFG_DIR/WorkModelParameters.advanced.json"
K8S_CFG="$CFG_DIR/K8sParameters.advanced.json"

mkdir -p "$OUT_DIR"

echo "[0/5] Limpieza previa (namespace y yamls anteriores)"
kubectl delete ns "$NS" --ignore-not-found=true >/dev/null 2>&1 || true
for _ in $(seq 1 60); do
	if ! kubectl get ns "$NS" >/dev/null 2>&1; then
		break
	fi
	sleep 1
done
rm -rf "$OUT_DIR/yamls"

echo "[1/5] Generando ServiceGraph avanzado"
python3 "$ROOT_DIR/ServiceGraphGenerator/RunServiceGraphGen.py" -c "$SG_CFG"

echo "[2/5] Generando WorkModel avanzado"
python3 "$ROOT_DIR/WorkModelGenerator/RunWorkModelGen.py" -c "$WM_CFG"

echo "[3/5] Verificando kube namespace"
kubectl get ns "$NS" >/dev/null 2>&1 || kubectl create ns "$NS"

echo "[4/5] Desplegando app avanzada con K8sDeployer"
python3 "$ROOT_DIR/Deployers/K8sDeployer/RunK8sDeployer.py" -c "$K8S_CFG"

echo "[5/5] Estado rápido"
kubectl get pods -n "$NS" -o wide
kubectl get svc -n "$NS"

echo "Escenario 3 inicializado en namespace: $NS"
