#!/usr/bin/env bash
set -euo pipefail

cat <<EOF | microk8s kubectl apply -f -
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: default
spec:
  mtls:
    mode: STRICT
EOF

echo "[istio] mTLS STRICT habilitado en namespace default"
