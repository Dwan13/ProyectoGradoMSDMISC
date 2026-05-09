#!/bin/bash
set -e

# Instala Helm si no está instalado
if ! command -v helm &> /dev/null; then
  echo "Helm no está instalado. Instalando..."
  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

# Crea el namespace monitoring si no existe
kubectl get namespace monitoring &> /dev/null || kubectl create namespace monitoring

# Agrega el repositorio de Prometheus Community
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Instala el Prometheus Operator stack
helm install prometheus prometheus-community/kube-prometheus-stack -n monitoring || helm upgrade prometheus prometheus-community/kube-prometheus-stack -n monitoring

# Aplica el PodMonitor de µBench
kubectl apply -f ./Monitoring/kubernetes-full-monitoring/mub-monitor.yaml -n monitoring

# Expone Prometheus y Grafana como NodePort
kubectl apply -f ./Monitoring/kubernetes-full-monitoring/prometheus-nodeport.yaml -n monitoring
kubectl apply -f ./Monitoring/kubernetes-full-monitoring/grafana-nodeport.yaml -n monitoring

echo "Prometheus y Grafana desplegados."
