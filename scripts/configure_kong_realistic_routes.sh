#!/usr/bin/env bash
set -euo pipefail

NS_KONG="${NS_KONG:-kong}"
KONG_CM="${KONG_CM:-kong-declarative-config}"
KONG_DEPLOY="${KONG_DEPLOY:-kong}"
TIMEOUT="${TIMEOUT:-240s}"

log() { echo "[$(date +'%H:%M:%S')] $*"; }

log "Aplicando configuracion declarativa de Kong para RealisticServices..."

microk8s kubectl -n "${NS_KONG}" apply -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: kong-declarative-config
  namespace: kong
data:
  kong.yml: |
    _format_version: "3.0"

    services:
    - name: s0-service
      url: http://s0.default.svc.cluster.local:80
      routes:
      - name: s0-route
        paths:
        - /
      plugins:
      - name: request-transformer
        config:
          add:
            headers:
            - X-Gateway:Kong

    - name: realistic-auth-service
      url: http://auth-service.realistic.svc.cluster.local:8080
      routes:
      - name: realistic-auth-route
        paths:
        - /auth
      plugins:
      - name: request-transformer
        config:
          add:
            headers:
            - X-Gateway:Kong
            - X-Route:auth

    - name: realistic-api-service
      url: http://api-service.realistic.svc.cluster.local:8080
      routes:
      - name: realistic-api-route
        paths:
        - /api
      plugins:
      - name: request-transformer
        config:
          add:
            headers:
            - X-Gateway:Kong
            - X-Route:api

    plugins:
    - name: prometheus
    - name: rate-limiting
      config:
        minute: 12000
        policy: local
EOF

log "Reiniciando deployment de Kong para cargar cambios..."
microk8s kubectl -n "${NS_KONG}" rollout restart "deployment/${KONG_DEPLOY}"
microk8s kubectl -n "${NS_KONG}" rollout status "deployment/${KONG_DEPLOY}" --timeout="${TIMEOUT}"

log "Verificando salud de rutas Realistic via Kong..."
AUTH_CODE="$(curl -s -o /tmp/kong-auth-health.out -w '%{http_code}' http://127.0.0.1:30082/auth/health || true)"
API_CODE="$(curl -s -o /tmp/kong-api-health.out -w '%{http_code}' http://127.0.0.1:30082/api/health || true)"

echo "AUTH_HEALTH_CODE=${AUTH_CODE}"
echo "API_HEALTH_CODE=${API_CODE}"

if [[ "${AUTH_CODE}" != "200" || "${API_CODE}" != "200" ]]; then
  log "[WARN] Kong responde pero alguna ruta realistic no quedo lista aun."
  log "Revisa: /tmp/kong-auth-health.out y /tmp/kong-api-health.out"
else
  log "Rutas Realistic sobre Kong listas."
fi
