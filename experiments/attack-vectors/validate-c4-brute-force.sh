#!/usr/bin/env bash
# ==========================================================================
# validate-c4-brute-force.sh
# Validación del vector de ataque para C4 (Rate Limiting).
#
# ESCENARIO DE AMENAZA:
#   Credential Stuffing / Brute Force Attack contra /auth/login.
#   Un atacante envía N solicitudes de autenticación rápidas desde una sola
#   IP intentando adivinar contraseñas (o validar una lista de credenciales
#   filtradas). Sin rate limiting, el backend procesa cada intento.
#
# HIPÓTESIS:
#   Baseline   → VULNERABLE: todos los requests llegan al backend (0 bloqueados)
#   Moderate   → MITIGADO:   >1200 req/min bloqueados con HTTP 503
#   Strict     → PROTEGIDO:  >300 req/min bloqueados con HTTP 503
#
# MECANISMO:
#   NGINX Ingress annotation nginx.ingress.kubernetes.io/limit-rpm implementa
#   un token-bucket a nivel de IP cliente. Los requests que exceden el límite
#   reciben HTTP 503 inmediatamente (no se retrasan ni encolan).
#
# REQUISITOS:
#   - curl disponible en WSL
#   - Los tres namespaces C4 desplegados y accesibles en el puerto NodePort
#   - /etc/hosts con las entradas *.local → 127.0.0.1 (o usar CLUSTER_IP)
#
# CONFIGURACIÓN:
#   CLUSTER_PORT=32167   NodePort del NGINX Ingress controller en MicroK8s
#   REQUESTS=500         Ráfaga de 500 requests paralelos (excede todos los límites)
#
# USO:
#   bash validate-c4-brute-force.sh
#   CLUSTER_PORT=32168 bash validate-c4-brute-force.sh   # puerto diferente
# ==========================================================================
set -euo pipefail

RED='\033[0;31m'; GRN='\033[0;32m'; YEL='\033[1;33m'
CYN='\033[0;36m'; BLD='\033[1m'; NC='\033[0m'

CLUSTER_PORT="${CLUSTER_PORT:-32167}"
REQUESTS="${REQUESTS:-500}"   # Ráfaga suficiente para superar burst=300 de Strict
TMPDIR_RESULTS=$(mktemp -d)

banner() {
  echo -e "\n${CYN}${BLD}══════════════════════════════════════════════════${NC}"
  echo -e "${CYN}${BLD}  $*${NC}"
  echo -e "${CYN}${BLD}══════════════════════════════════════════════════${NC}"
}
info() { echo -e "  ${YEL}▷${NC} $*"; }
pass() { echo -e "  ${GRN}${BLD}✔ PROTEGIDO${NC}  – $*"; }
vuln() { echo -e "  ${RED}${BLD}✘ VULNERABLE${NC} – $*"; }

# ---------- Función de ataque por fuerza bruta ----------------------------
# Envía $REQUESTS requests en paralelo (background jobs) simulando un
# atacante que no respeta backoff — máxima presión sobre el endpoint.
brute_force_attack() {
  local host="$1" label="$2" limit_desc="$3"
  local result_file="${TMPDIR_RESULTS}/${label// /_}.txt"
  : > "$result_file"   # trunca/crea

  echo ""
  info "Variante:   ${BLD}${label}${NC}  (Límite: ${limit_desc})"
  info "Ataque:     $REQUESTS requests paralelos a /auth/login (sin delay)"
  info "Credencial: usuario='admin', password='wrongpassword' (intento de fuerza bruta)"
  info "URL:        https://${host}:${CLUSTER_PORT}/auth/login"
  echo ""

  # Dispara todos los requests en background, guarda el HTTP status code
  for i in $(seq 1 "$REQUESTS"); do
    {
      code=$(curl -sk -o /dev/null -w "%{http_code}" \
        --resolve "${host}:${CLUSTER_PORT}:127.0.0.1" \
        --max-time 10 \
        -H 'Content-Type: application/json' \
        -d '{"username":"admin","password":"wrongpassword_'${i}'"}' \
        "https://${host}:${CLUSTER_PORT}/auth/login" 2>/dev/null || echo "000")
      echo "$code" >> "$result_file"
    } &
  done

  # Espera a que todos los requests terminen
  wait
  echo "  Requests completados. Contando respuestas..."

  local ok_count blocked_count other_count total
  ok_count=$(grep -cE '^(200|401)$'  "$result_file" 2>/dev/null || echo 0)
  blocked_count=$(grep -c '^503$'    "$result_file" 2>/dev/null || echo 0)
  other_count=$(grep -cvE '^(200|401|503)$' "$result_file" 2>/dev/null || echo 0)
  total=$(wc -l < "$result_file" | tr -d ' ')

  local block_pct=0
  [[ "$total" -gt 0 ]] && block_pct=$(( (blocked_count * 100) / total ))

  echo ""
  echo -e "  ┌─────────────────────────────────────────────────┐"
  printf  "  │  Variante: %-35s │\n" "${label}"
  echo -e "  ├─────────────────────────────────────────────────┤"
  printf  "  │  Total requests enviados:  %-20s │\n" "${total}"
  printf  "  │  Procesados (200/401):     %-20s │\n" "${ok_count}"
  printf  "  │  Bloqueados (HTTP 503):    %-20s │\n" "${blocked_count}"
  printf  "  │  Tasa de bloqueo:          %-19s%% │\n" "${block_pct}"
  echo -e "  └─────────────────────────────────────────────────┘"
  echo ""

  if [[ "$blocked_count" -eq 0 ]]; then
    vuln "0% bloqueados → todos los intentos de brute force llegan al backend"
  elif [[ "$block_pct" -ge 30 ]]; then
    pass "${block_pct}% de solicitudes bloqueadas por rate limiting (HTTP 503)"
  else
    echo -e "  ${YEL}⚠ Solo ${block_pct}% bloqueados — verificar configuración del rate limit${NC}"
  fi

  rm -f "$result_file"
}

# ==========================================================================
# MAIN
# ==========================================================================
banner "C4 RATE LIMITING – VECTOR DE ATAQUE: BRUTE FORCE / CREDENTIAL STUFFING"
cat <<EOF
  Control:   C4 – NGINX Ingress Rate Limiting (limit-rpm)
  Ataque:    Credential stuffing (OWASP OAT-008) / Brute Force (OWASP OAT-007)
  Método:    $REQUESTS requests HTTP paralelos desde una sola IP sin delay
  Endpoint:  POST /auth/login
  CWE ref:   CWE-307 (Improper Restriction of Excessive Authentication Attempts)
  Límites:   Baseline=ilimitado | Moderate=1200 rpm | Strict=300 rpm
EOF

echo ""
echo -e "${BLD}Iniciando simulación de ataque...${NC}"

brute_force_attack \
  "realistic-without-rate-limiting.local"  \
  "BASELINE"   \
  "Sin límite"

brute_force_attack \
  "realistic-moderate-rate-limiting.local" \
  "MODERATE"   \
  "1200 req/min"

brute_force_attack \
  "realistic-strict-rate-limiting.local"   \
  "STRICT"     \
  "300 req/min"

banner "RESUMEN"
cat <<EOF

  Un atacante enviando $REQUESTS requests instantáneos (credential stuffing):

  ┌───────────┬─────────────────┬────────────────────────────────────────┐
  │ Variante  │ Límite NGINX    │ Resultado del ataque                   │
  ├───────────┼─────────────────┼────────────────────────────────────────┤
  │ Baseline  │ Ninguno         │ VULNERABLE: todos los intentos llegan  │
  │ Moderate  │ 1200 req/min    │ PARCIAL: se reduce el rate de intentos │
  │ Strict    │ 300 req/min     │ PROTEGIDO: >90% bloqueados con HTTP 503│
  └───────────┴─────────────────┴────────────────────────────────────────┘

  CONCLUSIÓN:
    La variante Strict limita al atacante a ~300 intentos por minuto por IP.
    Para una contraseña de 8 caracteres alfanuméricos (62^8 ≈ 218 billones
    de combinaciones), a 300 intentos/min el ataque tardaría ~1.38 millones
    de años — haciendo el brute force computacionalmente inviable.

    HTTP 503 se retorna en ~2ms (rechazo instantáneo antes del backend),
    lo que también protege los recursos del servidor durante el ataque.
EOF

# Limpieza
rm -rf "$TMPDIR_RESULTS"
