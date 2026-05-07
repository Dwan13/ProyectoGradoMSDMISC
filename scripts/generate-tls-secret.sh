#!/usr/bin/env bash
# Script para generar un certificado autofirmado y crear el secreto TLS en Kubernetes
set -euo pipefail

NAMESPACE="realistic"
SECRET_NAME="realistic-tls"
CERT_FILE="tls.crt"
KEY_FILE="tls.key"

# Generar certificado autofirmado
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -subj "/CN=realistic.local/O=realistic" \
  -keyout "$KEY_FILE" -out "$CERT_FILE"

echo "Certificado y llave generados: $CERT_FILE, $KEY_FILE"

# Crear el namespace si no existe
kubectl get ns "$NAMESPACE" >/dev/null 2>&1 || kubectl create ns "$NAMESPACE"

# Crear el secreto TLS en Kubernetes
kubectl -n "$NAMESPACE" delete secret "$SECRET_NAME" >/dev/null 2>&1 || true
kubectl -n "$NAMESPACE" create secret tls "$SECRET_NAME" --cert="$CERT_FILE" --key="$KEY_FILE"

echo "Secreto TLS creado en el namespace $NAMESPACE."
