#!/usr/bin/env bash
# Script para obtener y mostrar credenciales de acceso para los entornos realistas
set -euo pipefail

API_URL="https://realistic.local/auth/login"
USERNAME="demo"
PASSWORD="demo123"

# Solicitar token de acceso

RESPONSE=$(curl -sk -X POST "$API_URL" -H 'Content-Type: application/json' -d '{"username":"'$USERNAME'","password":"'$PASSWORD'"}')
TOKEN=$(echo "$RESPONSE" | sed -n 's/.*"access_token"[ ]*:[ ]*"\([^"]*\)".*/\1/p')

if [ -z "$TOKEN" ]; then
  echo "[ERROR] No se pudo obtener el token de acceso. Respuesta: $RESPONSE"
  exit 1
fi

echo "[OK] Token de acceso para entorno realista:"
echo "$TOKEN"
echo
cat <<EOF

Puedes usar este token en los scripts de k6 o en peticiones manuales:
  -H "Authorization: Bearer $TOKEN"

Usuario demo:
  usuario: $USERNAME
  contraseña: $PASSWORD

EOF
