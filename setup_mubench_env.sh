#!/bin/bash
# muBench Automated Environment Setup Script
# Date: 2026-05-11
# Purpose: Provision a reproducible environment for muBench experiments (B1-B8, academic rigor)
# Usage: bash setup_mubench_env.sh

set -e

# 1. Check for required tools
REQUIRED_TOOLS=(docker docker-compose kubectl helm python3 pip3 git)
for tool in "${REQUIRED_TOOLS[@]}"; do
    if ! command -v $tool &> /dev/null; then
        echo "[ERROR] Required tool '$tool' is not installed. Please install it and rerun."
        exit 1
    fi
done

echo "[INFO] All required tools are installed."

# 2. Python environment setup (venv recommended)
if [ ! -d ".venv" ]; then
    echo "[INFO] Creating Python virtual environment (.venv)"
    python3 -m venv .venv
fi
source .venv/bin/activate

# 3. Upgrade pip and install Python dependencies
pip install --upgrade pip
pip install -r requirements.txt

# 4. Kubernetes cluster check
if ! kubectl cluster-info &> /dev/null; then
    echo "[ERROR] Kubernetes cluster not reachable. Please start your cluster (e.g., minikube, kind, or connect to your cloud cluster)."
    exit 2
fi

# 5. Deploy Prometheus and Grafana (if not present)
if ! kubectl get ns monitoring &> /dev/null; then
    echo "[INFO] Creating 'monitoring' namespace and deploying Prometheus/Grafana via Helm"
    kubectl create ns monitoring
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo update
    helm install prometheus prometheus-community/kube-prometheus-stack -n monitoring --set grafana.enabled=true
else
    echo "[INFO] Monitoring stack already present."
fi

# 6. Deploy muBench Realistic Services
cd RealisticServices
bash deploy-realistic.sh
cd ..

# 7. Validate environment
python3 scripts/validate_environment.sh || echo "[WARN] Validation script failed, please check logs."

echo "[SUCCESS] muBench environment setup complete."
echo "[INFO] Next steps:"
echo "- Run your benchmark campaigns as described in the README."
echo "- Use the provided post-processing scripts for analysis."
