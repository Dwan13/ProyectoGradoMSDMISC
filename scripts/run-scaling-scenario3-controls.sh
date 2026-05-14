#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="$ROOT_DIR/Testing/results/scaling_tests"
K6_SCRIPT="$ROOT_DIR/Testing/baseline.js"
CONTROLS_DIR="$ROOT_DIR/experiments/05-mubench-advanced/k8s-controls"
NS="${SCENARIO_NAMESPACE:-mubench-advanced}"
DURATION="${DURATION:-60s}"
BENCH_PROFILE="${BENCH_PROFILE:-native}"
DEFAULT_TARGET_URL="${TARGET_URL:-http://127.0.0.1:31213/s0}"
CONTROL_FILTER="${CONTROL_FILTER:-all}"
VARIANT_FILTER="${VARIANT_FILTER:-all}"

VUS_STAGES_CSV="${VUS_STAGES_CSV:-1,5,10,20}"
IFS=',' read -r -a VUS_STAGES <<< "$VUS_STAGES_CSV"
CONTROL_VARIANTS=(
  "C1_baseline"
  "C1_istio"
  "C1_kong"
  "C2_baseline"
  "C2_istio-mtls"
  "C2_linkerd-mtls"
  "C3_baseline"
  "C3_basic"
  "C3_strict"
  "C4_baseline"
  "C4_moderate"
  "C4_strict"
)

mkdir -p "$RESULTS_DIR"
REPORT="$RESULTS_DIR/scaling-report_mubench-advanced-controls_$(date +%Y%m%d_%H%M%S).csv"
echo "scenario,control,variant,vus,status,reason,avg_ms,p95_ms,err_pct,rps,cpu_mcores,mem_mib" > "$REPORT"

log() {
  echo "[INFO] $*"
}

kctl() {
  if command -v microk8s >/dev/null 2>&1; then
    microk8s kubectl "$@"
  else
    kubectl "$@"
  fi
}

duration_to_seconds() {
  local d="$1"
  if [[ "$d" =~ ^([0-9]+)s$ ]]; then
    echo "${BASH_REMATCH[1]}"
    return
  fi
  if [[ "$d" =~ ^([0-9]+)m$ ]]; then
    echo "$(( ${BASH_REMATCH[1]} * 60 ))"
    return
  fi
  if [[ "$d" =~ ^([0-9]+)h$ ]]; then
    echo "$(( ${BASH_REMATCH[1]} * 3600 ))"
    return
  fi
  echo "60"
}

parse_k6_jsonl() {
  local json_file="$1"
  local duration_secs="$2"
  python3 - << PY
import json
f = "$json_file"
duration_secs = float($duration_secs)
durations=[]
failed=0
total_failed_pts=0
reqs=0
with open(f) as fh:
  for line in fh:
    try:
      o=json.loads(line)
    except Exception:
      continue
    if o.get('type')!='Point':
      continue
    m=o.get('metric')
    v=o.get('data',{}).get('value',0)
    if m=='http_req_duration':
      durations.append(float(v))
    elif m=='http_req_failed':
      total_failed_pts += 1
      failed += int(v)
    elif m=='http_reqs':
      reqs += int(v)
durations.sort()
avg = sum(durations)/len(durations) if durations else 0
p95 = durations[min(int(len(durations)*0.95), len(durations)-1)] if durations else 0
err = (failed/total_failed_pts*100) if total_failed_pts else 0
rps = reqs/duration_secs if duration_secs > 0 else 0
print(f"{avg:.2f} {p95:.2f} {err:.2f} {rps:.2f}")
PY
}

node_resources() {
  kctl top nodes 2>/dev/null | tail -1 | awk '{
    cpu=$2; mem=$4;
    gsub(/m$/, "", cpu); gsub(/Mi$/, "", mem);
    print cpu " " mem
  }' || echo "0 0"
}

record_skipped() {
  local control="$1"
  local variant="$2"
  local reason="$3"
  for vus in "${VUS_STAGES[@]}"; do
    echo "mubench-advanced,$control,$variant,$vus,SKIPPED,$reason,0,0,0,0,0,0" >> "$REPORT"
  done
}

has_istio_gateway() {
  kctl get svc istio-ingressgateway -n istio-system >/dev/null 2>&1
}

has_kong_proxy() {
  kctl get svc kong-proxy -n kong >/dev/null 2>&1
}

has_linkerd_injector() {
  kctl get mutatingwebhookconfiguration linkerd-proxy-injector-webhook-config >/dev/null 2>&1
}

cleanup_network_resources() {
  kctl delete ingress --all -n "$NS" --ignore-not-found >/dev/null 2>&1 || true
  kctl delete gateway.networking.istio.io --all -n "$NS" --ignore-not-found >/dev/null 2>&1 || true
  kctl delete virtualservice --all -n "$NS" --ignore-not-found >/dev/null 2>&1 || true
  kctl delete networkpolicy --all -n "$NS" --ignore-not-found >/dev/null 2>&1 || true
  kctl delete peerauthentication --all -n "$NS" --ignore-not-found >/dev/null 2>&1 || true
}

restart_s3_workloads() {
  local deps=(gw-nginx s0 s1 s2 s3 s4 s5 s6 s7 sdb1)
  for dep in "${deps[@]}"; do
    kctl rollout restart deployment/"$dep" -n "$NS" >/dev/null 2>&1 || true
  done
  for dep in "${deps[@]}"; do
    kctl rollout status deployment/"$dep" -n "$NS" --timeout=180s >/dev/null 2>&1 || true
  done
}

remove_linkerd_annotation() {
  local deps=(gw-nginx s0 s1 s2 s3 s4 s5 s6 s7 sdb1)
  for dep in "${deps[@]}"; do
    kctl patch deployment "$dep" -n "$NS" --type='json' \
      -p='[{"op":"remove","path":"/spec/template/metadata/annotations/linkerd.io~1inject"}]' >/dev/null 2>&1 || true
  done
}

add_linkerd_annotation() {
  local deps=(gw-nginx s0 s1 s2 s3 s4 s5 s6 s7 sdb1)
  for dep in "${deps[@]}"; do
    kctl patch deployment "$dep" -n "$NS" --type='merge' \
      -p '{"spec":{"template":{"metadata":{"annotations":{"linkerd.io/inject":"enabled"}}}}}' >/dev/null 2>&1 || true
  done
}

apply_c4_gateway_config() {
  local mode="$1"

  case "$mode" in
    baseline)
      cat << 'EOF' | kctl apply -f - >/dev/null
apiVersion: v1
kind: ConfigMap
metadata:
  name: gw-nginx
  namespace: mubench-advanced
data:
  nginx.conf: |
    user nginx;
    worker_processes  1;
    error_log  /etc/nginx/error.log;
    events {
      worker_connections  10240;
    }
    http {
        log_format  main
        '[GATEWAY] - '
        '$remote_addr - - '
        '[$time_local] '
        '"$request_method '
        '$request_uri" '
        '$status -'
        ' http:/$request_uri.mubench-advanced.svc.cluster.local';

        access_log  /etc/nginx/access.log main;
        access_log on;

        server {
                listen       80;
                server_name  _;
                location / {
                    proxy_read_timeout 5m;
                    proxy_connect_timeout 5m;
                    proxy_send_timeout 5m;
                    resolver kube-dns.kube-system.svc.cluster.local;
                    proxy_pass http:/$request_uri.mubench-advanced.svc.cluster.local/api/v1;
                    proxy_http_version 1.1;
                }
                location ~* /update$ {
                    resolver kube-dns.kube-system.svc.cluster.local;
                    rewrite ^(/.*)/update$ /update break;
                    proxy_pass http:/$1.mubench-advanced.svc.cluster.local;
                    proxy_http_version 1.1;
                }
        }
    }
EOF
      ;;
    moderate)
      cat << 'EOF' | kctl apply -f - >/dev/null
apiVersion: v1
kind: ConfigMap
metadata:
  name: gw-nginx
  namespace: mubench-advanced
data:
  nginx.conf: |
    user nginx;
    worker_processes  1;
    error_log  /etc/nginx/error.log;
    events {
      worker_connections  10240;
    }
    http {
        limit_req_zone $binary_remote_addr zone=s3rl:10m rate=30r/s;

        log_format  main
        '[GATEWAY] - '
        '$remote_addr - - '
        '[$time_local] '
        '"$request_method '
        '$request_uri" '
        '$status -'
        ' http:/$request_uri.mubench-advanced.svc.cluster.local';

        access_log  /etc/nginx/access.log main;
        access_log on;

        server {
                listen       80;
                server_name  _;
                location / {
                    limit_req zone=s3rl burst=40 nodelay;
                    proxy_read_timeout 5m;
                    proxy_connect_timeout 5m;
                    proxy_send_timeout 5m;
                    resolver kube-dns.kube-system.svc.cluster.local;
                    proxy_pass http:/$request_uri.mubench-advanced.svc.cluster.local/api/v1;
                    proxy_http_version 1.1;
                }
                location ~* /update$ {
                    resolver kube-dns.kube-system.svc.cluster.local;
                    rewrite ^(/.*)/update$ /update break;
                    proxy_pass http:/$1.mubench-advanced.svc.cluster.local;
                    proxy_http_version 1.1;
                }
        }
    }
EOF
      ;;
    strict)
      cat << 'EOF' | kctl apply -f - >/dev/null
apiVersion: v1
kind: ConfigMap
metadata:
  name: gw-nginx
  namespace: mubench-advanced
data:
  nginx.conf: |
    user nginx;
    worker_processes  1;
    error_log  /etc/nginx/error.log;
    events {
      worker_connections  10240;
    }
    http {
        limit_req_zone $binary_remote_addr zone=s3rl:10m rate=8r/s;

        log_format  main
        '[GATEWAY] - '
        '$remote_addr - - '
        '[$time_local] '
        '"$request_method '
        '$request_uri" '
        '$status -'
        ' http:/$request_uri.mubench-advanced.svc.cluster.local';

        access_log  /etc/nginx/access.log main;
        access_log on;

        server {
                listen       80;
                server_name  _;
                location / {
                    limit_req zone=s3rl burst=10 nodelay;
                    proxy_read_timeout 5m;
                    proxy_connect_timeout 5m;
                    proxy_send_timeout 5m;
                    resolver kube-dns.kube-system.svc.cluster.local;
                    proxy_pass http:/$request_uri.mubench-advanced.svc.cluster.local/api/v1;
                    proxy_http_version 1.1;
                }
                location ~* /update$ {
                    resolver kube-dns.kube-system.svc.cluster.local;
                    rewrite ^(/.*)/update$ /update break;
                    proxy_pass http:/$1.mubench-advanced.svc.cluster.local;
                    proxy_http_version 1.1;
                }
        }
    }
EOF
      ;;
  esac

  kctl rollout restart deployment/gw-nginx -n "$NS" >/dev/null 2>&1 || true
  kctl rollout status deployment/gw-nginx -n "$NS" --timeout=180s >/dev/null 2>&1 || true
}

resolve_target_url() {
  local control="$1"
  local variant="$2"

  if [[ "$control" == "C1" && "$variant" == "istio" ]]; then
    local np
    np="$(kctl get svc istio-ingressgateway -n istio-system -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}' 2>/dev/null || true)"
    if [[ -n "$np" ]]; then
      echo "http://127.0.0.1:${np}/s0"
      return
    fi
  fi

  if [[ "$control" == "C1" && "$variant" == "kong" ]]; then
    local np
    np="$(kctl get svc kong-proxy -n kong -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}' 2>/dev/null || true)"
    if [[ -n "$np" ]]; then
      echo "http://127.0.0.1:${np}/s0"
      return
    fi
  fi

  echo "$DEFAULT_TARGET_URL"
}

apply_control_state() {
  local control="$1"
  local variant="$2"

  cleanup_network_resources

  # Baseline default for C2/C4 before applying specific variant.
  kctl label namespace "$NS" istio-injection=disabled --overwrite >/dev/null 2>&1 || true
  remove_linkerd_annotation

  case "$control" in
    C1)
      case "$variant" in
        baseline) kctl apply -f "$CONTROLS_DIR/11-c1-ingress-nginx-s3.yaml" >/dev/null ;;
        istio)    kctl apply -f "$CONTROLS_DIR/11-c1-istio-s3.yaml" >/dev/null ;;
        kong)     kctl apply -f "$CONTROLS_DIR/11-c1-kong-s3.yaml" >/dev/null ;;
      esac
      ;;
    C2)
      case "$variant" in
        baseline)
          kctl delete peerauthentication --all -n "$NS" --ignore-not-found >/dev/null 2>&1 || true
          ;;
        istio-mtls)
          kctl label namespace "$NS" istio-injection=enabled --overwrite >/dev/null
          kctl apply -f "$CONTROLS_DIR/12-c2-istio-mtls-s3.yaml" >/dev/null
          ;;
        linkerd-mtls)
          add_linkerd_annotation
          ;;
      esac
      ;;
    C3)
      case "$variant" in
        baseline) : ;;
        basic)  kctl apply -f "$CONTROLS_DIR/13-c3-basic-s3.yaml" >/dev/null ;;
        strict) kctl apply -f "$CONTROLS_DIR/13-c3-strict-s3.yaml" >/dev/null ;;
      esac
      ;;
    C4)
      apply_c4_gateway_config "$variant"
      ;;
  esac

  restart_s3_workloads
  sleep 2
}

is_variant_supported() {
  local control="$1"
  local variant="$2"

  if [[ "$control" == "C1" && "$variant" == "istio" ]]; then
    has_istio_gateway || return 1
  fi
  if [[ "$control" == "C1" && "$variant" == "kong" ]]; then
    has_kong_proxy || return 1
  fi
  if [[ "$control" == "C2" && "$variant" == "istio-mtls" ]]; then
    has_istio_gateway || return 1
  fi
  if [[ "$control" == "C2" && "$variant" == "linkerd-mtls" ]]; then
    has_linkerd_injector || return 1
  fi

  return 0
}

duration_secs="$(duration_to_seconds "$DURATION")"

log "Running S3 control matrix in namespace: $NS"
log "Report: $REPORT"

for cv in "${CONTROL_VARIANTS[@]}"; do
  IFS='_' read -r control variant <<< "$cv"

  if [[ "$CONTROL_FILTER" != "all" && "$CONTROL_FILTER" != "$control" ]]; then
    continue
  fi
  if [[ "$VARIANT_FILTER" != "all" && "$VARIANT_FILTER" != "$variant" ]]; then
    continue
  fi

  log "=== $control / $variant ==="

  if ! is_variant_supported "$control" "$variant"; then
    record_skipped "$control" "$variant" "control-plane-component-not-available"
    log "Skipped $control/$variant (component not available)"
    continue
  fi

  apply_control_state "$control" "$variant"
  target_url="$(resolve_target_url "$control" "$variant")"
  log "Target URL: $target_url"

  for vus in "${VUS_STAGES[@]}"; do
    out="$RESULTS_DIR/scaling_s3_${control}_${variant}_${vus}vus_$(date +%s).json"

    k6 run \
      -e TARGET_URL="$target_url" \
      -e VUS="$vus" \
      -e DURATION="$DURATION" \
      -e BENCH_PROFILE="$BENCH_PROFILE" \
      --out json="$out" \
      "$K6_SCRIPT" >/tmp/s3_controls_${control}_${variant}_${vus}.log 2>&1 || true

    read -r avg p95 err rps < <(parse_k6_jsonl "$out" "$duration_secs")
    read -r cpu mem < <(node_resources)
    cpu="${cpu:-0}"; mem="${mem:-0}"

    echo "mubench-advanced,$control,$variant,$vus,OK,,${avg},${p95},${err},${rps},${cpu},${mem}" >> "$REPORT"
    log "VU=$vus avg=${avg} p95=${p95} err=${err}% rps=${rps}"
  done
done

log "Completed."
cat "$REPORT"
