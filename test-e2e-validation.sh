#!/bin/bash

set -e

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# End-to-End Validation Test: Login + List Users + Create User + Verify in DB
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Utility function for colored output
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $1"; }

# Test configuration
TIMESTAMP=$(date +%s%3N)
NEW_USERNAME="testuser_${TIMESTAMP}"
NEW_EMAIL="${NEW_USERNAME}@example.com"

# Use NodePort for direct service access (bypasses ingress)
declare -A AUTH_URLS
AUTH_URLS[baseline]="http://localhost:30084"
AUTH_URLS[kong]="http://localhost:30184"
AUTH_URLS[istio]="http://localhost:30184"

declare -A API_URLS
API_URLS[baseline]="http://localhost:30081"
API_URLS[kong]="http://localhost:30181"
API_URLS[istio]="http://localhost:30181"

POSTGRES_HOST="localhost"
POSTGRES_PORT="5432"
POSTGRES_USER="mubench"
POSTGRES_PASSWORD="mubench"
POSTGRES_DB="mubench_real"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 1. Test Login (POST /login)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

log_info "Testing LOGIN endpoint across all controls..."
echo ""

for control in baseline kong istio; do
  auth_url="${AUTH_URLS[$control]}"
  api_url="${API_URLS[$control]}"
  
  echo -ne "${YELLOW}Testing $control (${auth_url}/login)...${NC} "
  
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
      log_success "LOGIN OK (HTTP $http_code) | Token: ${token:0:20}..."
      eval "TOKEN_${control}='$token'"
      eval "API_URL_${control}='$api_url'"
    else
      log_error "LOGIN FAILED: No token in response (HTTP $http_code)"
    fi
  else
    log_error "LOGIN FAILED (HTTP $http_code)"
    log_warn "Response: ${body:0:200}"
  fi
done

echo ""

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 2. Test List Users (GET /users)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

log_info "Testing LIST USERS endpoint across all controls..."
echo ""

for control in baseline kong istio; do
  api_url_var="API_URL_${control}"
  token_var="TOKEN_${control}"
  
  if [[ -z "${!token_var}" ]]; then
    log_warn "Skipping $control (no valid token)"
    continue
  fi
  
  api_url="${!api_url_var}"
  token="${!token_var}"
  
  echo -ne "${YELLOW}Testing $control (GET ${api_url}/users)...${NC} "
  
  response=$(curl -s -k \
    -X GET "${api_url}/users?limit=10&offset=0" \
    -H "Authorization: Bearer $token" \
    -w "\n%{http_code}" 2>/dev/null || echo "ERROR\n000")
  
  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | head -n -1)
  
  if [[ "$http_code" == "200" ]]; then
    user_count=$(echo "$body" | grep -o '"users"' | wc -l)
    log_success "LIST USERS OK (HTTP $http_code)"
    log_info "  Response preview: ${body:0:150}..."
  else
    log_error "LIST USERS FAILED (HTTP $http_code)"
    log_warn "  Response: ${body:0:200}"
  fi
done

echo ""

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 3. Test Create User (POST /users)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

log_info "Creating new user across all controls..."
echo ""

declare -A CREATED_USERS

for control in baseline kong istio; do
  api_url_var="API_URL_${control}"
  token_var="TOKEN_${control}"
  
  if [[ -z "${!token_var}" ]]; then
    log_warn "Skipping $control (no valid token)"
    continue
  fi
  
  api_url="${!api_url_var}"
  token="${!token_var}"
  
  echo -ne "${YELLOW}Creating user in $control...${NC} "
  
  response=$(curl -s -k \
    -X POST "${api_url}/users" \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    -d "{\"username\": \"${NEW_USERNAME}_${control}\", \"email\": \"${NEW_USERNAME}_${control}@example.com\", \"full_name\": \"Test User $control\"}" \
    -w "\n%{http_code}" 2>/dev/null || echo "ERROR\n000")
  
  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | head -n -1)
  
  if [[ "$http_code" == "201" || "$http_code" == "200" ]]; then
    user_id=$(echo "$body" | grep -o '"id":[0-9]*' | grep -o '[0-9]*' | head -1)
    log_success "USER CREATED OK (HTTP $http_code) | ID: $user_id"
    CREATED_USERS[$control]="${NEW_USERNAME}_${control}"
  elif [[ "$http_code" == "409" ]]; then
    log_warn "USER ALREADY EXISTS (HTTP $http_code) - using existing"
    CREATED_USERS[$control]="${NEW_USERNAME}_${control}"
  else
    log_error "CREATE USER FAILED (HTTP $http_code)"
    log_warn "  Response: ${body:0:200}"
  fi
done

echo ""

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 4. Verify in PostgreSQL
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

log_info "Verifying data in PostgreSQL..."
echo ""

# First, port-forward PostgreSQL if needed
log_info "Checking PostgreSQL connectivity..."

# Try to connect with a 5 second timeout
PGPASSWORD="$POSTGRES_PASSWORD" timeout 5 psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT 1;" > /dev/null 2>&1

if [[ $? -ne 0 ]]; then
  log_warn "Cannot connect to PostgreSQL directly. Trying via kubectl port-forward..."
  
  # Check if port-forward is already running
  if ! nc -z localhost 5432 > /dev/null 2>&1; then
    log_info "Starting port-forward: kubectl port-forward -n mubench-real svc/postgres 5432:5432 &"
    kubectl port-forward -n mubench-real svc/postgres 5432:5432 > /dev/null 2>&1 &
    sleep 3
  fi
fi

# Query for each created user with timeout
for control in baseline kong istio; do
  username="${CREATED_USERS[$control]}"
  
  if [[ -z "$username" ]]; then
    log_warn "Skipping DB verification for $control (no user created)"
    continue
  fi
  
  echo -ne "${YELLOW}Verifying user '$username' in PostgreSQL...${NC} "
  
  query="SELECT id, username, email, full_name, created_at FROM users WHERE username = '$username' LIMIT 1;"
  
  result=$(timeout 10 bash -c "PGPASSWORD='$POSTGRES_PASSWORD' psql -h '$POSTGRES_HOST' -p '$POSTGRES_PORT' -U '$POSTGRES_USER' -d '$POSTGRES_DB' -t -c \"$query\" 2>&1" || echo "TIMEOUT")
  
  if [[ -n "$result" && "$result" != "TIMEOUT" && "$result" != *"error"* && "$result" != *"ERROR"* ]]; then
    log_success "USER FOUND IN DATABASE"
    log_info "  Details: $result"
  else
    log_error "USER NOT FOUND OR CONNECTION TIMEOUT"
    log_warn "  Query result: $result"
  fi
done

echo ""

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 5. Summary Report
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

log_info "SUMMARY REPORT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Timestamp: $TIMESTAMP"
echo "Controls tested: baseline, kong, istio"
echo "Test scope:"
echo "  ✓ Login (POST /login)"
echo "  ✓ List Users (GET /users)"
echo "  ✓ Create User (POST /users)"
echo "  ✓ DB Verification (PostgreSQL)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
log_success "End-to-End validation test completed!"
