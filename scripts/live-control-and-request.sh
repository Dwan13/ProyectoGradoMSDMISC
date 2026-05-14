#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SCENARIO="${SCENARIO:-s2}"
CONTROL="${CONTROL:-none}"
VARIANT="${VARIANT:-baseline}"
ACTION="${ACTION:-create-and-list}"
LOGIN_USER="${LOGIN_USER:-demo}"
LOGIN_PASS="${LOGIN_PASS:-demo123}"
NEW_USER="${NEW_USER:-live_user_$(date +%s)}"
NEW_EMAIL="${NEW_EMAIL:-${NEW_USER}@example.com}"
LIMIT="${LIMIT:-50}"
GRAFANA_URL="${GRAFANA_URL:-http://127.0.0.1:30030}"
GRAFANA_ANNOTATE="${GRAFANA_ANNOTATE:-true}"
GRAFANA_USER="${GRAFANA_USER:-}"
GRAFANA_PASS="${GRAFANA_PASS:-}"

usage() {
  cat << 'EOF'
Usage:
  bash scripts/live-control-and-request.sh [options]

Options:
  --scenario <s1|s2|s3|s4>        Scenario to target (default: s2)
  --control <none|C1|C2|C3|C4>    Control family (default: none)
  --variant <name>                 Control variant (default: baseline)
  --action <login|create-user|list-users|create-and-list|ping-s3>
                                   Action to execute (default: create-and-list)
  --login-user <user>              Login username (default: demo)
  --login-pass <pass>              Login password (default: demo123)
  --new-user <username>            Username to create
  --new-email <email>              Email to create
  --limit <n>                      List users limit (default: 50)
  --grafana-url <url>              Grafana URL for annotations (default: http://127.0.0.1:30030)
  --no-annotate                    Disable Grafana annotation publishing

Examples:
  bash scripts/live-control-and-request.sh --scenario s2 --control C4 --variant strict --action create-and-list
  bash scripts/live-control-and-request.sh --scenario s2 --control none --action create-user --new-user u1 --new-email u1@example.com
  bash scripts/live-control-and-request.sh --scenario s4 --control none --action create-and-list
  bash scripts/live-control-and-request.sh --scenario s3 --action ping-s3
EOF
}

kctl() {
  if command -v microk8s >/dev/null 2>&1; then
    microk8s kubectl "$@"
  else
    kubectl "$@"
  fi
}

log() {
  echo "[$(date +'%H:%M:%S')] $*"
}

ensure_tls_secret() {
  local source_ns="$1"
  local secret_name="$2"
  local target_ns="$3"

  if kctl get secret "$secret_name" -n "$target_ns" >/dev/null 2>&1; then
    return 0
  fi

  kctl get secret "$secret_name" -n "$source_ns" -o json | python3 -c '
import json,sys
obj=json.load(sys.stdin)
obj["metadata"]={"name":obj["metadata"]["name"],"namespace":"'"$target_ns"'"}
print(json.dumps(obj))
' | kctl apply -f - >/dev/null
}

extract_token() {
  python3 -c 'import json,sys;print(json.loads(sys.stdin.read()).get("access_token",""))' 2>/dev/null || true
}

resolve_grafana_creds() {
  if [[ -n "$GRAFANA_USER" && -n "$GRAFANA_PASS" ]]; then
    return 0
  fi

  local user=""
  local pass=""
  user=$(kctl -n monitoring get secret prometheus-grafana -o jsonpath='{.data.admin-user}' 2>/dev/null | base64 -d || true)
  pass=$(kctl -n monitoring get secret prometheus-grafana -o jsonpath='{.data.admin-password}' 2>/dev/null | base64 -d || true)

  if [[ -n "$user" && -n "$pass" ]]; then
    GRAFANA_USER="$user"
    GRAFANA_PASS="$pass"
  fi
}

emit_grafana_annotation() {
  local phase="$1"
  local text="$2"
  if [[ "$GRAFANA_ANNOTATE" != "true" ]]; then
    return 0
  fi

  resolve_grafana_creds
  if [[ -z "$GRAFANA_USER" || -z "$GRAFANA_PASS" ]]; then
    log "Grafana annotation skipped: missing credentials"
    return 0
  fi

  if ! curl -sS --max-time 3 "$GRAFANA_URL/api/health" >/dev/null 2>&1; then
    log "Grafana annotation skipped: $GRAFANA_URL unreachable"
    return 0
  fi

  local epoch_ms
  epoch_ms=$(($(date +%s) * 1000))

  local payload
  payload=$(cat <<EOF
{
  "time": $epoch_ms,
  "tags": [
    "mubench-live",
    "scenario:$SCENARIO",
    "namespace:$NS",
    "control:$CONTROL",
    "variant:$VARIANT",
    "action:$ACTION",
    "phase:$phase"
  ],
  "text": "$text"
}
EOF
)

  curl -sS -u "$GRAFANA_USER:$GRAFANA_PASS" \
    -H 'Content-Type: application/json' \
    -X POST "$GRAFANA_URL/api/annotations" \
    -d "$payload" >/dev/null || true
}

set_endpoints() {
  case "$SCENARIO" in
    s1)
      NS="realistic"
      AUTH_BASE="http://127.0.0.1:30084"
      API_BASE="http://127.0.0.1:30081"
      ;;
    s2)
      NS="mubench-real"
      AUTH_BASE="http://127.0.0.1:30184"
      API_BASE="http://127.0.0.1:30181"
      ;;
    s3)
      NS="mubench-advanced"
      AUTH_BASE=""
      API_BASE=""
      S3_BASE="http://127.0.0.1:31213"
      ;;
    s4)
      NS="mubench-s4"
      AUTH_BASE="http://127.0.0.1:32184"
      API_BASE="http://127.0.0.1:32181"
      ;;
    *)
      echo "Unknown scenario: $SCENARIO"
      exit 1
      ;;
  esac
}

apply_control_s2() {
  local control="$1"
  local variant="$2"
  local ns="mubench-real"

  log "Applying control state in $ns: $control/$variant"

  kctl delete ingress --all -n "$ns" --ignore-not-found >/dev/null 2>&1 || true
  kctl delete gateway.networking.istio.io --all -n "$ns" --ignore-not-found >/dev/null 2>&1 || true
  kctl delete virtualservice --all -n "$ns" --ignore-not-found >/dev/null 2>&1 || true
  kctl delete networkpolicy --all -n "$ns" --ignore-not-found >/dev/null 2>&1 || true

  kctl set env deployment/api-service -n "$ns" RATE_LIMIT_ENABLED=false RATE_LIMIT_RPM=600 >/dev/null 2>&1 || true
  kctl label namespace "$ns" istio-injection=disabled --overwrite >/dev/null 2>&1 || true
  kctl apply -f "$ROOT_DIR/RealisticServices/k8s/03-services-real.yaml" >/dev/null 2>&1 || true

  if [[ "$control" == "none" ]]; then
    log "Control disabled (baseline service state)"
  else
    case "$control" in
      C1)
        ensure_tls_secret realistic mubench-tls "$ns" || true
        ensure_tls_secret realistic realistic-tls "$ns" || true
        case "$variant" in
          baseline) kctl apply -f "$ROOT_DIR/RealisticServices/k8s/07-c1-ingress-gateway-real.yaml" >/dev/null ;;
          istio)    kctl apply -f "$ROOT_DIR/RealisticServices/k8s/07-c1-istio-real.yaml" >/dev/null ;;
          kong)     kctl apply -f "$ROOT_DIR/RealisticServices/k8s/07-c1-kong-real.yaml" >/dev/null ;;
          *) echo "Invalid C1 variant: $variant"; exit 1 ;;
        esac
        ;;
      C2)
        case "$variant" in
          baseline)    kctl apply -f "$ROOT_DIR/RealisticServices/k8s/03-services-real.yaml" >/dev/null ;;
          istio-mtls)  kctl apply -f "$ROOT_DIR/RealisticServices/k8s/02-services-istio-mtls-real.yaml" >/dev/null ;;
          linkerd-mtls)kctl apply -f "$ROOT_DIR/RealisticServices/k8s/02-services-linkerd-mtls-real.yaml" >/dev/null ;;
          *) echo "Invalid C2 variant: $variant"; exit 1 ;;
        esac
        ;;
      C3)
        case "$variant" in
          baseline) : ;;
          basic)  kctl apply -f "$ROOT_DIR/RealisticServices/k8s/08-c3-networkpolicy-real.yaml" >/dev/null ;;
          strict) kctl apply -f "$ROOT_DIR/RealisticServices/k8s/08-c3-networkpolicy-strict-real.yaml" >/dev/null ;;
          *) echo "Invalid C3 variant: $variant"; exit 1 ;;
        esac
        ;;
      C4)
        case "$variant" in
          baseline)
            kctl set env deployment/api-service -n "$ns" RATE_LIMIT_ENABLED=false RATE_LIMIT_RPM=600 >/dev/null
            ;;
          moderate)
            kctl set env deployment/api-service -n "$ns" RATE_LIMIT_ENABLED=true RATE_LIMIT_RPM=120 >/dev/null
            kctl rollout restart deployment/api-service -n "$ns" >/dev/null
            ;;
          strict)
            kctl set env deployment/api-service -n "$ns" RATE_LIMIT_ENABLED=true RATE_LIMIT_RPM=20 >/dev/null
            kctl rollout restart deployment/api-service -n "$ns" >/dev/null
            ;;
          *) echo "Invalid C4 variant: $variant"; exit 1 ;;
        esac
        ;;
      *)
        echo "Control not supported: $control"
        exit 1
        ;;
    esac
  fi

  for dep in auth-service api-service data-service; do
    kctl rollout status deployment/"$dep" -n "$ns" --timeout=180s >/dev/null 2>&1 || true
  done
}

apply_control_s1() {
  local control="$1"
  local variant="$2"
  local cmd="baseline"

  case "$control" in
    none) cmd="baseline" ;;
    C1) cmd="c1" ;;
    C2) cmd="c2" ;;
    C3) cmd="c3" ;;
    C4) cmd="c4" ;;
    *) echo "Control not supported in s1: $control"; exit 1 ;;
  esac

  if [[ "$variant" != "baseline" && "$control" != "none" ]]; then
    log "s1 supports control family only (no sub-variant). Ignoring variant=$variant"
  fi

  bash "$ROOT_DIR/RealisticServices/controls/apply-control.sh" "$cmd"
}

apply_controls_if_needed() {
  case "$SCENARIO" in
    s1)
      apply_control_s1 "$CONTROL" "$VARIANT"
      ;;
    s2)
      apply_control_s2 "$CONTROL" "$VARIANT"
      ;;
    s3)
      if [[ "$CONTROL" != "none" ]]; then
        echo "s3 control toggling is not exposed in this live helper. Use scripts/run-scaling-scenario3-controls.sh for matrix mode."
        exit 1
      fi
      ;;
    s4)
      if [[ "$CONTROL" != "none" ]]; then
        echo "s4 is semantic-equivalent baseline; control toggling is not implemented for this scenario."
        exit 1
      fi
      ;;
  esac
}

do_login() {
  local login_resp
  login_resp=$(curl -sS -X POST "${AUTH_BASE}/login" \
    -H 'Content-Type: application/json' \
    -d "{\"username\":\"${LOGIN_USER}\",\"password\":\"${LOGIN_PASS}\"}")

  TOKEN="$(echo "$login_resp" | extract_token)"
  if [[ -z "$TOKEN" ]]; then
    echo "Login failed: $login_resp"
    return 1
  fi

  log "Token acquired (len=${#TOKEN})"
  return 0
}

do_create_user() {
  if [[ -z "${TOKEN:-}" ]]; then
    do_login
  fi

  local create_resp
  create_resp=$(curl -sS -X POST "${API_BASE}/users" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H 'Content-Type: application/json' \
    -d "{\"username\":\"${NEW_USER}\",\"email\":\"${NEW_EMAIL}\"}")

  log "Create response: $create_resp"
}

do_list_users() {
  if [[ -z "${TOKEN:-}" ]]; then
    do_login
  fi

  local list_resp
  list_resp=$(curl -sS -X GET "${API_BASE}/users?limit=${LIMIT}" \
    -H "Authorization: Bearer ${TOKEN}")

  log "List response (first 600 chars):"
  echo "$list_resp" | cut -c1-600
}

ping_s3() {
  local resp
  resp=$(curl -sS "${S3_BASE}/s0" || true)
  log "s3 response (first 300 chars):"
  echo "$resp" | cut -c1-300
}

print_grafana_watch_commands() {
  cat << EOF

Grafana real-time helpers:
1) Detect and port-forward Grafana service:
   kubectl get svc -A | grep -Ei 'grafana|prometheus-grafana'
   kubectl -n monitoring port-forward svc/prometheus-grafana 3000:80
   # Alternative common name:
   kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80

2) Open dashboard:
  ${GRAFANA_URL}

3) Live infra tail (while sending requests):
   watch -n 2 "kubectl top pods -n ${NS}"

4) Quick event stream in namespace:
   kubectl get events -n ${NS} --sort-by=.lastTimestamp -w

Tip: run this helper repeatedly with different control/variant and keep Grafana open.
This script writes Grafana annotations with tags scenario/control/variant/action.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scenario) SCENARIO="$2"; shift 2 ;;
    --control) CONTROL="$2"; shift 2 ;;
    --variant) VARIANT="$2"; shift 2 ;;
    --action) ACTION="$2"; shift 2 ;;
    --login-user) LOGIN_USER="$2"; shift 2 ;;
    --login-pass) LOGIN_PASS="$2"; shift 2 ;;
    --new-user) NEW_USER="$2"; shift 2 ;;
    --new-email) NEW_EMAIL="$2"; shift 2 ;;
    --limit) LIMIT="$2"; shift 2 ;;
    --grafana-url) GRAFANA_URL="$2"; shift 2 ;;
    --no-annotate) GRAFANA_ANNOTATE="false"; shift 1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1"; usage; exit 1 ;;
  esac
done

set_endpoints

log "Scenario=$SCENARIO Namespace=$NS Control=$CONTROL Variant=$VARIANT Action=$ACTION"
apply_controls_if_needed
emit_grafana_annotation "start" "Start $ACTION ($SCENARIO $CONTROL/$VARIANT)"

case "$ACTION" in
  login)
    if [[ "$SCENARIO" == "s3" ]]; then
      echo "s3 native does not expose auth/login in this form. Use --action ping-s3"
      exit 1
    fi
    do_login
    ;;
  create-user)
    if [[ "$SCENARIO" == "s3" ]]; then
      echo "s3 native is not functionally equivalent to user CRUD. create-user is not supported in s3 native."
      exit 1
    fi
    do_create_user
    ;;
  list-users)
    if [[ "$SCENARIO" == "s3" ]]; then
      echo "s3 native is not functionally equivalent to user CRUD. list-users is not supported in s3 native."
      exit 1
    fi
    do_list_users
    ;;
  create-and-list)
    if [[ "$SCENARIO" == "s3" ]]; then
      echo "s3 native is not functionally equivalent to user CRUD. Use s2 or s4 for create/list semantics."
      exit 1
    fi
    do_create_user
    do_list_users
    ;;
  ping-s3)
    if [[ "$SCENARIO" != "s3" ]]; then
      echo "ping-s3 action is only for s3"
      exit 1
    fi
    ping_s3
    ;;
  *)
    echo "Unknown action: $ACTION"
    usage
    exit 1
    ;;
esac

  emit_grafana_annotation "done" "Done $ACTION ($SCENARIO $CONTROL/$VARIANT)"

print_grafana_watch_commands
