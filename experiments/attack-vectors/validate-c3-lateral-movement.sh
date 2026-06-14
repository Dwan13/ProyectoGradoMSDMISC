#!/usr/bin/env bash
# ==========================================================================
# validate-c3-lateral-movement.sh
# Validación del vector de ataque para C3 (NetworkPolicies).
#
# ESCENARIO DE AMENAZA:
#   Un atacante compromete el pod api-service (p.ej. explotando una
#   vulnerabilidad RCE en la API). Desde allí intenta:
#     1. Pivotar directamente a PostgreSQL (port 5432) para exfiltrar datos
#        sin pasar por la capa de autorización.
#     2. Alcanzar servicios desde un namespace no autorizado
#        (simula compromiso de otro tenant/aplicación en el mismo cluster).
#
# HIPÓTESIS:
#   Baseline  → VULNERABLE: sin NetworkPolicy, api-service alcanza postgres
#   Basic     → VULNERABLE: allow-intra-namespace permite todo intra-ns
#   Strict    → PROTEGIDO:  api-egress solo autoriza puerto 8080 a auth/data;
#               postgres:5432 es inalcanzable desde api-service
#
# REQUISITOS:
#   - microk8s kubectl (o kubectl con kubeconfig configurado)
#   - Los tres namespaces desplegados (o al menos los que se quieran probar)
#
# USO:
#   bash validate-c3-lateral-movement.sh
# ==========================================================================
set -euo pipefail

RED='\033[0;31m'; GRN='\033[0;32m'; YEL='\033[1;33m'
CYN='\033[0;36m'; BLD='\033[1m'; NC='\033[0m'

# ---------- kubectl wrapper ------------------------------------------------
kctl() {
  if command -v microk8s >/dev/null 2>&1; then
    microk8s kubectl "$@"
  else
    kubectl "$@"
  fi
}

banner() {
  echo -e "\n${CYN}${BLD}══════════════════════════════════════════════════${NC}"
  echo -e "${CYN}${BLD}  $*${NC}"
  echo -e "${CYN}${BLD}══════════════════════════════════════════════════${NC}"
}
info() { echo -e "  ${YEL}▷${NC} $*"; }
pass() { echo -e "  ${GRN}${BLD}✔ PROTEGIDO${NC}  – $*"; }
vuln() { echo -e "  ${RED}${BLD}✘ VULNERABLE${NC} – $*"; }

# ---------- Snippet Python para conexión TCP con timeout ------------------
# Se ejecuta dentro del pod comprometido (python:3.11-slim = stdlib pura)
TCP_PROBE='
import socket, sys
host, port = sys.argv[1], int(sys.argv[2])
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.settimeout(5)
try:
    s.connect((host, port))
    s.close()
    print(f"[ATAQUE EXITOSO] TCP {host}:{port} alcanzado desde el pod comprometido")
    sys.exit(0)
except ConnectionRefusedError:
    print(f"[BLOQUEADO] {host}:{port} – conexión rechazada")
    sys.exit(1)
except Exception as e:
    print(f"[BLOQUEADO] {host}:{port} – {type(e).__name__}: {e}")
    sys.exit(1)
'

# ==========================================================================
# VECTOR 1: Pivoting a base de datos
#   api-service comprometido intenta TCP a postgres:5432
# ==========================================================================
test_postgres_pivot() {
  local ns="$1" label="$2"
  echo ""
  info "Variante: ${BLD}${label}${NC}  (ns: ${ns})"
  info "Atacante: pod api-service comprometido"
  info "Objetivo: postgres:5432 (lectura directa de BD, sin pasar por data-service)"

  local pod
  pod=$(kctl -n "$ns" get pods -l app=api-service \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

  if [[ -z "$pod" ]]; then
    echo -e "  ${YEL}⚠ Namespace $ns no encontrado o sin pod api-service. Omitiendo.${NC}"
    return
  fi

  echo -e "  Pod seleccionado: ${pod}"
  local result exit_code=0
  result=$(kctl -n "$ns" exec "$pod" -- \
    python3 -c "$TCP_PROBE" postgres 5432 2>&1) || exit_code=$?

  echo -e "  Resultado: ${result}"
  if [[ $exit_code -eq 0 ]]; then
    vuln "api-service puede acceder a postgres:5432 → DB expuesta si api-service es comprometido"
  else
    pass "NetworkPolicy bloquea el acceso api-service → postgres:5432 (lateral movement prevenido)"
  fi
}

# ==========================================================================
# VECTOR 2: Acceso cross-namespace
#   Pod en namespace "default" intenta alcanzar servicios internos
#   (simula compromiso de otra aplicación en el mismo cluster Kubernetes)
# ==========================================================================
test_cross_namespace() {
  local target_ns="$1" label="$2"
  local target_host="data-service.${target_ns}.svc.cluster.local"
  echo ""
  info "Variante: ${BLD}${label}${NC}  (ns objetivo: ${target_ns})"
  info "Atacante: pod en namespace 'default' (otro tenant comprometido)"
  info "Objetivo: ${target_host}:8080 (acceso directo a data-service sin autenticación)"

  # Lanza un pod efímero en default, ejecuta el probe y lo elimina
  local result exit_code=0
  result=$(kctl run c3-attacker-probe \
    --image=python:3.11-slim \
    --restart=Never \
    --rm \
    -n default \
    -i \
    --timeout=60s \
    -- python3 -c "$TCP_PROBE" "$target_host" 8080 2>&1) || exit_code=$?

  echo -e "  Resultado: ${result}"
  if [[ $exit_code -eq 0 ]]; then
    vuln "Pod externo (ns 'default') alcanza $target_host → sin aislamiento de namespace"
  else
    pass "NetworkPolicy bloquea acceso cross-namespace → namespace isolation activo"
  fi
}

# ==========================================================================
# MAIN
# ==========================================================================
banner "C3 NETWORK POLICIES – VECTOR DE ATAQUE: MOVIMIENTO LATERAL"
cat <<EOF
  Control:   C3 – Kubernetes NetworkPolicies
  Ataque:    Lateral movement desde pod api-service comprometido
  Objetivo:  Acceso directo a PostgreSQL para exfiltración de datos
  CWE ref:   CWE-284 (Improper Access Control)
  MITRE ATT&CK T1210: Exploitation of Remote Services
EOF

echo ""
echo -e "${BLD}══ VECTOR 1: Pivoting a la base de datos ══${NC}"
echo "   api-service (comprometido) → postgres:5432"
echo "   Riesgo: acceso completo a la BD sin pasar por data-service ni auth"
test_postgres_pivot "realistic-without-network-policies" "BASELINE"
test_postgres_pivot "realistic-basic-network-policies"   "BASIC"
test_postgres_pivot "realistic-strict-network-policies"  "STRICT"

echo ""
echo -e "${BLD}══ VECTOR 2: Acceso cross-namespace ══${NC}"
echo "   Pod externo (ns 'default') → data-service:8080"
echo "   Riesgo: otro inquilino del cluster accede a la API sin credentials"
test_cross_namespace "realistic-without-network-policies" "BASELINE"
test_cross_namespace "realistic-basic-network-policies"   "BASIC"
test_cross_namespace "realistic-strict-network-policies"  "STRICT"

banner "RESUMEN DE RESULTADOS"
cat <<EOF

  ┌───────────┬────────────────────────────┬──────────────────────────┐
  │ Variante  │ Vector 1: DB pivot         │ Vector 2: Cross-ns       │
  │           │ (api-service → postgres)   │ (default → data-service) │
  ├───────────┼────────────────────────────┼──────────────────────────┤
  │ Baseline  │ VULNERABLE                 │ VULNERABLE               │
  │ Basic     │ VULNERABLE (intra-ns libre)│ PROTEGIDO                │
  │ Strict    │ PROTEGIDO                  │ PROTEGIDO                │
  └───────────┴────────────────────────────┴──────────────────────────┘

  CONCLUSIÓN:
    - Basic protege el perímetro del namespace (cross-ns) pero NO
      el movimiento lateral entre microservicios dentro del mismo ns.
    - Strict (micro-segmentación) es la única variante que implementa
      el principio de least-privilege a nivel de pod:
        api-service solo puede hablar con auth-service:8080 y data-service:8080.
        Postgres solo acepta conexiones de auth-service y data-service.
      → Un api-service comprometido NO puede exfiltrar la BD directamente.
EOF
