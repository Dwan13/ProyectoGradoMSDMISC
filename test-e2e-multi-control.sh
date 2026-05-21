#!/bin/bash

set -e

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Multi-Control E2E Validation: Login + List Users + Create User + Verify in DB
# Tests: C1 (Kong, Istio, baseline), C2 (linkerd-mtls, istio-mtls), C3 (strict, basic),
#        C4 (moderate, strict), and all other variants across all control deployments
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $1"; }
log_control() { echo -e "${CYAN}[CONTROL]${NC} $1"; }

TIMESTAMP=$(date +%s%3N)
NEW_USERNAME="testuser_${TIMESTAMP}"

if command -v microk8s >/dev/null 2>&1; then
  KCTL="microk8s kubectl"
else
  KCTL="kubectl"
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Control Registry: Maps control names to ports and metadata
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

declare -A CONTROLS_CONFIG=(
  # C1: API Gateway (Kong, Istio, baseline) - mubench-real namespace
  ["C1-baseline"]="30084:30081"
  ["C1-kong"]="30184:30181"
  ["C1-istio"]="30184:30181"
  
  # C2: Service Mesh (baseline, linkerd-mtls, istio-mtls) - realistic namespace
  ["C2-baseline"]="30084:30081"
  ["C2-linkerd-mtls"]="30084:30081"
  ["C2-istio-mtls"]="30084:30081"
  
  # C3: Network Policy (baseline, basic, strict) - realistic namespace
  ["C3-baseline"]="30084:30081"
  ["C3-basic"]="30084:30081"
  ["C3-strict"]="30084:30081"
  
  # C4: Rate Limiting (baseline, moderate, strict) - realistic namespace
  ["C4-baseline"]="30084:30081"
  ["C4-moderate"]="30084:30081"
  ["C4-strict"]="30084:30081"
)

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Test results tracker
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

declare -A RESULTS_LOGIN
declare -A RESULTS_LIST
declare -A RESULTS_CREATE
declare -A RESULTS_VERIFY

TOTAL_TESTS=0
PASSED_TESTS=0

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Main Test Loop
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

log_info "Starting Multi-Control E2E Validation"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

for control_variant in "${!CONTROLS_CONFIG[@]}"; do
  log_control "Testing $control_variant"
  
  ports="${CONTROLS_CONFIG[$control_variant]}"
  auth_port="${ports%:*}"
  api_port="${ports#*:}"
  
  auth_url="http://localhost:${auth_port}"
  api_url="http://localhost:${api_port}"
  
  # --- Test 1: LOGIN ---
  echo -ne "  POST /login ... "
  response=$(curl -s -k \
    -X POST "${auth_url}/login" \
    -H "Content-Type: application/json" \
    -d '{"username": "demo", "password": "demo123"}' \
    -w "\n%{http_code}" 2>/dev/null || echo "ERROR\n000")
  
  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | head -n -1)
  
  if [[ "$http_code" == "200" ]]; then
    token=$(echo "$body" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)
    if [[ -n "$token" ]]; then
      log_success "HTTP $http_code"
      RESULTS_LOGIN[$control_variant]="PASS"
      ((++TOTAL_TESTS))
      ((++PASSED_TESTS))
    else
      log_error "No token (HTTP $http_code)"
      RESULTS_LOGIN[$control_variant]="FAIL"
      ((++TOTAL_TESTS))
      continue
    fi
  else
    log_error "HTTP $http_code"
    RESULTS_LOGIN[$control_variant]="FAIL"
    ((++TOTAL_TESTS))
    continue
  fi
  
  # --- Test 2: LIST USERS ---
  echo -ne "  GET /users ... "
  response=$(curl -s -k \
    -X GET "${api_url}/users?limit=10&offset=0" \
    -H "Authorization: Bearer $token" \
    -w "\n%{http_code}" 2>/dev/null || echo "ERROR\n000")
  
  http_code=$(echo "$response" | tail -1)
  
  if [[ "$http_code" == "200" ]]; then
    log_success "HTTP $http_code"
    RESULTS_LIST[$control_variant]="PASS"
    ((++TOTAL_TESTS))
    ((++PASSED_TESTS))
  else
    log_error "HTTP $http_code"
    RESULTS_LIST[$control_variant]="FAIL"
    ((++TOTAL_TESTS))
    continue
  fi
  
  # --- Test 3: CREATE USER ---
  echo -ne "  POST /users ... "
  response=$(curl -s -k \
    -X POST "${api_url}/users" \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    -d "{\"username\": \"${NEW_USERNAME}_${control_variant}\", \"email\": \"${NEW_USERNAME}_${control_variant}@example.com\"}" \
    -w "\n%{http_code}" 2>/dev/null || echo "ERROR\n000")
  
  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | head -n -1)
  
  if [[ "$http_code" == "201" || "$http_code" == "200" || "$http_code" == "409" ]]; then
    log_success "HTTP $http_code"
    RESULTS_CREATE[$control_variant]="PASS"
    ((++TOTAL_TESTS))
    ((++PASSED_TESTS))
  else
    log_error "HTTP $http_code"
    RESULTS_CREATE[$control_variant]="FAIL"
    ((++TOTAL_TESTS))
    continue
  fi
  
  echo ""
done

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# PostgreSQL Verification
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

echo ""
log_info "Verifying data persistence in PostgreSQL..."
echo ""

# Count how many test users were created
for control_variant in "${!CONTROLS_CONFIG[@]}"; do
  echo -ne "  Checking $control_variant ... "
  
  username="${NEW_USERNAME}_${control_variant}"

  # C1 usa postgres en mubench-real/mubench_real; el resto usa realistic/mubench
  if [[ "$control_variant" == C1-* ]]; then
    db_ns_primary="mubench-real"
    db_name_primary="mubench_real"
    db_ns_fallback="realistic"
    db_name_fallback="mubench"
  else
    db_ns_primary="realistic"
    db_name_primary="mubench"
    db_ns_fallback="mubench-real"
    db_name_fallback="mubench_real"
  fi

  result=$($KCTL exec -n "$db_ns_primary" deploy/postgres -- \
    psql -U mubench -d "$db_name_primary" -t -c \
    "SELECT id, username, email, created_at FROM app_users WHERE username = '$username' LIMIT 1;" 2>&1 || echo "")

  # Fallback defensivo para variantes con ruteo compartido entre namespaces.
  if [[ -z "$result" || "$result" == *"(0 rows)"* || "$result" == *"ERROR"* ]]; then
    result=$($KCTL exec -n "$db_ns_fallback" deploy/postgres -- \
      psql -U mubench -d "$db_name_fallback" -t -c \
      "SELECT id, username, email, created_at FROM app_users WHERE username = '$username' LIMIT 1;" 2>&1 || echo "")
  fi
  
  if [[ -n "$result" && "$result" != *"ERROR"* ]]; then
    log_success "Found in PostgreSQL"
    RESULTS_VERIFY[$control_variant]="PASS"
    ((++TOTAL_TESTS))
    ((++PASSED_TESTS))
  else
    log_warn "Not found in PostgreSQL"
    RESULTS_VERIFY[$control_variant]="FAIL"
    ((++TOTAL_TESTS))
  fi
done

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Summary Report
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "SUMMARY REPORT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Print table
printf "%-25s %-10s %-10s %-10s %-10s\n" "Control-Variant" "Login" "List" "Create" "Verify"
echo "─────────────────────────────────────────────────────────────────"

for control_variant in "${!CONTROLS_CONFIG[@]}"; do
  login="${RESULTS_LOGIN[$control_variant]:-SKIP}"
  list="${RESULTS_LIST[$control_variant]:-SKIP}"
  create="${RESULTS_CREATE[$control_variant]:-SKIP}"
  verify="${RESULTS_VERIFY[$control_variant]:-SKIP}"
  
  # Color results
  [[ "$login" == "PASS" ]] && login="${GREEN}PASS${NC}" || login="${RED}$login${NC}"
  [[ "$list" == "PASS" ]] && list="${GREEN}PASS${NC}" || list="${RED}$list${NC}"
  [[ "$create" == "PASS" ]] && create="${GREEN}PASS${NC}" || create="${RED}$create${NC}"
  [[ "$verify" == "PASS" ]] && verify="${GREEN}PASS${NC}" || verify="${RED}$verify${NC}"
  
  printf "%-25s %-10b %-10b %-10b %-10b\n" "$control_variant" "$login" "$list" "$create" "$verify"
done

echo "─────────────────────────────────────────────────────────────────"
echo ""
echo "Results: $PASSED_TESTS / $TOTAL_TESTS tests passed"

if [[ $PASSED_TESTS -eq $TOTAL_TESTS ]]; then
  log_success "All controls validated successfully!"
  log_success "Traceability maintained across all control combinations"
  exit 0
else
  log_warn "Some tests failed. Review above results."
  exit 1
fi
