#!/usr/bin/env bash
set -euo pipefail

################################################################################
# run-randomized-design-matrix.sh
#
# Pseudorunner para ejecutar matrices experimentales aleatorizadas y bloqueadas.
#
# Objetivo:
# - leer una matriz CSV con columnas de bloque y orden aleatorio
# - ejecutar fila por fila con warmup/cooldown consistentes
# - delegar el benchmark al wrapper existente run-k6-benchmark.sh
# - dejar puntos de extension claros para aplicar configuraciones nuevas
#
# Uso recomendado (dry-run por defecto):
#   bash scripts/run-randomized-design-matrix.sh \
#     --matrix Testing/results/scaling_tests/design_matrix_c4_limit_burst_randomized_blocks.csv
#
# Ejecucion real:
#   bash scripts/run-randomized-design-matrix.sh \
#     --matrix Testing/results/scaling_tests/design_matrix_c4_limit_burst_randomized_blocks.csv \
#     --execute --target-env postgres-real
################################################################################

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE_FILE="${ROOT_DIR}/scripts/s2-final-profile.env"
MATRIX=""
TARGET_ENV="${TARGET_ENV:-default}"
EXECUTE=false
LIMIT_ROWS=""
CONTINUE_ON_READINESS_FAIL=false
RESULTS_DIR="${ROOT_DIR}/Testing/results/auto_runs/randomized_campaigns"

if [[ -f "$PROFILE_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$PROFILE_FILE"
fi

S2_C4_MODERATE_RPM="${S2_C4_MODERATE_RPM:-1200}"
S2_C4_STRICT_RPM="${S2_C4_STRICT_RPM:-300}"

log() { echo "[run-randomized] $*"; }
fail() { echo "[run-randomized][error] $*" >&2; exit 1; }

kctl() {
  if command -v microk8s >/dev/null 2>&1; then
    microk8s kubectl "$@"
  else
    kubectl "$@"
  fi
}

apply_ingress_rate_limit() {
  local ns="$1"
  local limit_rps="$2"
  local burst_multiplier="$3"

  kctl apply -f "$ROOT_DIR/RealisticServices/k8s/07-c1-ingress-gateway-real.yaml" >/dev/null
  kctl annotate ingress realistic-gateway -n "$ns" \
    nginx.ingress.kubernetes.io/limit-rps="$limit_rps" \
    nginx.ingress.kubernetes.io/limit-burst-multiplier="$burst_multiplier" \
    --overwrite >/dev/null
}

clear_ingress_rate_limit() {
  local ns="$1"

  kctl apply -f "$ROOT_DIR/RealisticServices/k8s/07-c1-ingress-gateway-real.yaml" >/dev/null
  kctl annotate ingress realistic-gateway -n "$ns" \
    nginx.ingress.kubernetes.io/limit-rps- \
    nginx.ingress.kubernetes.io/limit-burst-multiplier- \
    >/dev/null 2>&1 || true
}

usage() {
  cat <<EOF
Usage: $(basename "$0") --matrix <csv> [--execute] [--target-env <env>] [--limit-rows <n>]

Options:
  --matrix <csv>       Randomized matrix CSV to run.
  --execute            Execute for real. Without this flag the script only prints the plan.
  --target-env <env>   Forwarded to run-k6-benchmark.sh.
  --limit-rows <n>     Execute only the first n rows after sorting.
  --continue-on-readiness-fail
                       Continue rows even when readiness gate is unstable.
                       Internally forwards --skip-precheck to run-k6-benchmark.sh.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --matrix) MATRIX="$2"; shift 2 ;;
    --execute) EXECUTE=true; shift ;;
    --target-env) TARGET_ENV="$2"; shift 2 ;;
    --limit-rows) LIMIT_ROWS="$2"; shift 2 ;;
    --continue-on-readiness-fail) CONTINUE_ON_READINESS_FAIL=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Unknown option: $1" ;;
  esac
done

[[ -n "$MATRIX" ]] || fail "--matrix is required"
[[ -f "$MATRIX" ]] || fail "Matrix not found: $MATRIX"
mkdir -p "$RESULTS_DIR"

apply_row_configuration() {
  local control="$1"
  local variant="$2"
  local extra_json="$3"

  local rate_limit_rps burst_pct ns rate_limit_rpm
  rate_limit_rps="$(/bin/python3 - <<'PY' "$extra_json"
import json,sys
row=json.loads(sys.argv[1])
print(row.get('rate_limit_rps', ''))
PY
)"
  burst_pct="$(/bin/python3 - <<'PY' "$extra_json"
import json,sys
row=json.loads(sys.argv[1])
print(row.get('burst_pct', ''))
PY
)"

  if [[ "$TARGET_ENV" != "postgres-real" ]]; then
    case "$control/$variant" in
      C1/baseline|C1/istio|C1/kong|C2/baseline|C2/istio-mtls|C2/linkerd-mtls|C3/baseline|C3/basic|C3/moderate|C3/strict|C4/baseline|C4/moderate|C4/strict)
        log "apply existing configuration in non-postgres-real mode: $control/$variant"
        return 0
        ;;
      *)
        fail "Custom randomized variants currently support only TARGET_ENV=postgres-real"
        ;;
    esac
  fi

  ns="mubench-real"

  # Reset to a known S2 baseline before each row.
  kctl delete ingress --all -n "$ns" --ignore-not-found >/dev/null 2>&1 || true
  kctl delete gateway.networking.istio.io --all -n "$ns" --ignore-not-found >/dev/null 2>&1 || true
  kctl delete virtualservice --all -n "$ns" --ignore-not-found >/dev/null 2>&1 || true
  kctl delete networkpolicy --all -n "$ns" --ignore-not-found >/dev/null 2>&1 || true
  kctl set env deployment/api-service -n "$ns" RATE_LIMIT_ENABLED=false RATE_LIMIT_RPM=600 >/dev/null 2>&1 || true
  kctl label namespace "$ns" istio-injection=disabled --overwrite >/dev/null 2>&1 || true
  kctl apply -f "$ROOT_DIR/RealisticServices/k8s/03-services-real.yaml" >/dev/null 2>&1 || true

  case "$control/$variant" in
    C1/baseline)
      kctl apply -f "$ROOT_DIR/RealisticServices/k8s/07-c1-ingress-gateway-real.yaml" >/dev/null
      ;;
    C1/istio)
      kctl apply -f "$ROOT_DIR/RealisticServices/k8s/07-c1-istio-real.yaml" >/dev/null
      ;;
    C1/kong)
      kctl apply -f "$ROOT_DIR/RealisticServices/k8s/07-c1-kong-real.yaml" >/dev/null
      ;;
    C2/baseline)
      kctl apply -f "$ROOT_DIR/RealisticServices/k8s/03-services-real.yaml" >/dev/null
      ;;
    C2/istio-mtls)
      kctl apply -f "$ROOT_DIR/RealisticServices/k8s/02-services-istio-mtls-real.yaml" >/dev/null
      ;;
    C2/linkerd-mtls)
      kctl apply -f "$ROOT_DIR/RealisticServices/k8s/02-services-linkerd-mtls-real.yaml" >/dev/null
      ;;
    C3/baseline)
      log "C3 baseline: no network policy applied"
      ;;
    C3/basic)
      kctl apply -f "$ROOT_DIR/RealisticServices/k8s/08-c3-networkpolicy-real.yaml" >/dev/null
      ;;
    C3/moderate)
      kctl apply -f "$ROOT_DIR/RealisticServices/k8s/08-c3-networkpolicy-moderate-real.yaml" >/dev/null
      ;;
    C3/strict)
      kctl apply -f "$ROOT_DIR/RealisticServices/k8s/08-c3-networkpolicy-strict-real.yaml" >/dev/null
      ;;
    C3/strict-plus-egress|C3/strict-plus-egress-db)
      fail "Variant $control/$variant is declared in the design matrix, but no distinct manifest exists yet under RealisticServices/k8s/ for postgres-real"
      ;;
    C4/baseline)
      clear_ingress_rate_limit "$ns"
      log "Applied C4/baseline with no ingress rate limit"
      ;;
    C4/moderate)
      apply_ingress_rate_limit "$ns" "$(( (S2_C4_MODERATE_RPM + 59) / 60 ))" 2
      log "Applied C4/moderate at ingress with LIMIT_RPS=$(( (S2_C4_MODERATE_RPM + 59) / 60 )) (from RPM=$S2_C4_MODERATE_RPM)"
      ;;
    C4/strict)
      apply_ingress_rate_limit "$ns" "$(( (S2_C4_STRICT_RPM + 59) / 60 ))" 1
      log "Applied C4/strict at ingress with LIMIT_RPS=$(( (S2_C4_STRICT_RPM + 59) / 60 )) (from RPM=$S2_C4_STRICT_RPM)"
      ;;
    C4/rl*)
      if [[ -z "$rate_limit_rps" ]]; then
        fail "C4 sweep row missing rate_limit_rps: $extra_json"
      fi
      rate_limit_rpm="$(( rate_limit_rps * 60 ))"
      log "Applying C4 custom rate-only sweep at ingress: ${rate_limit_rps} req/s (RPM=${rate_limit_rpm})"
      apply_ingress_rate_limit "$ns" "$rate_limit_rps" 2
      ;;
    *)
      fail "Unsupported randomized row configuration: $control/$variant"
      ;;
  esac

  for dep in auth-service api-service data-service; do
    kctl rollout status deployment/"$dep" -n "$ns" --timeout=180s >/dev/null 2>&1 || true
  done
}

run_row() {
  local row_json="$1"
  local control variant vus warmup cooldown duration campaign_id block_day random_order output_name output_path security_mode k6_script
  control="$(/bin/python3 - <<'PY' "$row_json"
import json,sys
row=json.loads(sys.argv[1]); print(row.get('control',''))
PY
)"
  variant="$(/bin/python3 - <<'PY' "$row_json"
import json,sys
row=json.loads(sys.argv[1]); print(row.get('variant',''))
PY
)"
  vus="$(/bin/python3 - <<'PY' "$row_json"
import json,sys
row=json.loads(sys.argv[1]); print(row.get('vus','1'))
PY
)"
  warmup="$(/bin/python3 - <<'PY' "$row_json"
import json,sys
row=json.loads(sys.argv[1]); print(row.get('warmup_seconds','30'))
PY
)"
  cooldown="$(/bin/python3 - <<'PY' "$row_json"
import json,sys
row=json.loads(sys.argv[1]); print(row.get('cooldown_seconds','15'))
PY
)"
  duration="$(/bin/python3 - <<'PY' "$row_json"
import json,sys
row=json.loads(sys.argv[1]); print(row.get('duration_seconds','60'))
PY
)"
  campaign_id="$(/bin/python3 - <<'PY' "$row_json"
import json,sys
row=json.loads(sys.argv[1]); print(row.get('campaign_id','campaign'))
PY
)"
  block_day="$(/bin/python3 - <<'PY' "$row_json"
import json,sys
row=json.loads(sys.argv[1]); print(row.get('block_day','block'))
PY
)"
  random_order="$(/bin/python3 - <<'PY' "$row_json"
import json,sys
row=json.loads(sys.argv[1]); print(row.get('random_order','0'))
PY
)"

  security_mode="$(/bin/python3 - <<'PY' "$row_json"
import json,sys
row=json.loads(sys.argv[1]); print(row.get('security_mode','normal'))
PY
)"

  k6_script="$(/bin/python3 - <<'PY' "$row_json"
import json,sys
row=json.loads(sys.argv[1]); print(row.get('k6_script',''))
PY
)"

  output_name="${campaign_id}_${block_day}_order${random_order}_${control}_${variant}_${security_mode}_${vus}vus.json"
  output_path="${RESULTS_DIR}/${output_name}"

  # Resume support: skip rows that already have a complete NDJSON result,
  # but rerun rows with partial/corrupted outputs.
  if [[ -f "$output_path" ]]; then
    local is_complete
    is_complete="$(/bin/python3 - <<'PY' "$output_path" "$duration"
import json
import sys
from datetime import datetime
from pathlib import Path

path = Path(sys.argv[1])
expected = float(sys.argv[2])

if not path.exists() or path.stat().st_size == 0:
    print("0")
    raise SystemExit(0)

times = []
with path.open("r", encoding="utf-8", errors="ignore") as fh:
    for line in fh:
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except Exception:
            continue
        if obj.get("type") != "Point":
            continue
        t = obj.get("data", {}).get("time")
        if t:
            times.append(t)

if len(times) < 10:
    print("0")
    raise SystemExit(0)

def parse_iso(ts: str) -> datetime:
    fixed = ts.replace("Z", "+00:00")
    if "." in fixed:
        prefix, rest = fixed.split(".", 1)
        if "+" in rest:
            frac, tz = rest.split("+", 1)
            fixed = f"{prefix}.{frac[:6]}+{tz}"
        elif "-" in rest:
            frac, tz = rest.split("-", 1)
            fixed = f"{prefix}.{frac[:6]}-{tz}"
    return datetime.fromisoformat(fixed)

try:
    dur = (parse_iso(max(times)) - parse_iso(min(times))).total_seconds()
except Exception:
    print("0")
    raise SystemExit(0)

# Consider complete when we capture at least ~90% of requested window.
print("1" if dur >= (expected * 0.90) else "0")
PY
  )"

    if [[ "$is_complete" == "1" ]]; then
      log "skip existing complete result: ${output_path}"
      return 0
  fi

    log "found partial result, rerunning row and replacing file: ${output_path}"
    rm -f "$output_path"
    fi

  log "row block=${block_day} order=${random_order} control=${control} variant=${variant} security_mode=${security_mode} vus=${vus}"
  apply_row_configuration "$control" "$variant" "$row_json"

  if [[ "$EXECUTE" != true ]]; then
    log "dry-run warmup=${warmup}s benchmark=${control}/${variant} security_mode=${security_mode} vus=${vus} duration=${duration}s cooldown=${cooldown}s output=${output_path}"
    return 0
  fi

  if [[ "$warmup" =~ ^[0-9]+$ ]] && [[ "$warmup" -gt 0 ]]; then
    log "warmup ${warmup}s before benchmark ${control}/${variant}"
    sleep "$warmup"
  fi

  bench_cmd=(bash "$ROOT_DIR/scripts/run-k6-benchmark.sh" \
    --control "$control" \
    --variant "$variant" \
    --target-env "$TARGET_ENV" \
    --security-mode "$security_mode" \
    --vus "$vus" \
    --duration "$duration" \
    --output "$output_path")

  if [[ -n "$k6_script" ]]; then
    bench_cmd+=(--k6-script "$k6_script")
  fi

  if [[ "$CONTINUE_ON_READINESS_FAIL" == true ]]; then
    bench_cmd+=(--skip-precheck)
  elif [[ "$control" == "C3" && "$variant" == "strict" ]]; then
    log "C3/strict: skipping readiness gate because the strict policy intentionally blocks the profile probe"
    bench_cmd+=(--skip-precheck)
  fi

  # set -e would terminate immediately on non-zero; temporarily disable it
  # so we can handle threshold failures when continuity mode is enabled.
  set +e
  "${bench_cmd[@]}"
  local bench_rc=$?
  set -e
  if [[ "$bench_rc" -ne 0 ]]; then
    if [[ "$bench_rc" -eq 99 ]]; then
      log "benchmark returned code 99 (threshold failures); continuing campaign"
    elif [[ "$CONTINUE_ON_READINESS_FAIL" == true ]]; then
      log "benchmark returned code ${bench_rc}; continuing due to --continue-on-readiness-fail"
    else
      return "$bench_rc"
    fi
  fi

  if [[ "$cooldown" =~ ^[0-9]+$ ]] && [[ "$cooldown" -gt 0 ]]; then
    log "cooldown ${cooldown}s after benchmark ${control}/${variant}"
    sleep "$cooldown"
  fi
}

export MATRIX_PATH="$MATRIX"
export LIMIT_ROWS_VALUE="$LIMIT_ROWS"
mapfile -t ROWS < <(/bin/python3 - <<'PY'
import json
import os
import pandas as pd

path = os.environ['MATRIX_PATH']
limit = os.environ.get('LIMIT_ROWS_VALUE')
df = pd.read_csv(path)
order_cols = [c for c in ['block_day', 'random_order'] if c in df.columns]
if order_cols:
    df = df.sort_values(order_cols)
if limit:
    df = df.head(int(limit))
for _, row in df.iterrows():
    print(json.dumps(row.to_dict(), default=str))
PY
)

log "loaded ${#ROWS[@]} rows from $MATRIX"
for row in "${ROWS[@]}"; do
  run_row "$row"
done

log "completed matrix traversal"
