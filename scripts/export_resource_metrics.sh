#!/usr/bin/env bash
set -euo pipefail

PROM_URL="${PROM_URL:-http://localhost:9090}"
NAMESPACE="realistic"
WINDOW="15m"
OUTPUT_DIR=""

usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  --namespace <ns>      Namespace a consultar (default: realistic)
  --window <dur>        Ventana de consulta (e.g. 10m, 30m, 1h; default: 15m)
  --output-dir <path>   Directorio de salida (default: Testing/results)
  --prom-url <url>      URL de Prometheus (default: http://localhost:9090)
EOF
}

parse_window_seconds() {
  local raw="$1"
  if [[ "$raw" =~ ^([0-9]+)([smh])$ ]]; then
    local num="${BASH_REMATCH[1]}"
    local unit="${BASH_REMATCH[2]}"
    case "$unit" in
      s) echo "$num" ;;
      m) echo $((num * 60)) ;;
      h) echo $((num * 3600)) ;;
      *) return 1 ;;
    esac
  else
    return 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --namespace)
      NAMESPACE="$2"
      shift 2
      ;;
    --window)
      WINDOW="$2"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --prom-url)
      PROM_URL="$2"
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "[ERROR] Opcion desconocida: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$OUTPUT_DIR" ]]; then
  OUTPUT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/Testing/results"
fi
mkdir -p "$OUTPUT_DIR"

WINDOW_SEC="$(parse_window_seconds "$WINDOW" || true)"
if [[ -z "$WINDOW_SEC" ]]; then
  echo "[ERROR] Ventana invalida: $WINDOW (usa formato 10m, 1h, 30s)" >&2
  exit 1
fi

END_TS="$(date +%s)"
START_TS=$((END_TS - WINDOW_SEC))
STAMP="$(date +%Y%m%d_%H%M%S)"

CPU_QUERY="sum by (pod) (rate(container_cpu_usage_seconds_total{namespace=\"${NAMESPACE}\",container!=\"\",pod!=\"\"}[1m]))"
MEM_QUERY="sum by (pod) (container_memory_working_set_bytes{namespace=\"${NAMESPACE}\",container!=\"\",pod!=\"\"})"

CPU_TMP="$(mktemp /tmp/mubench-cpu.XXXXXX.json)"
MEM_TMP="$(mktemp /tmp/mubench-mem.XXXXXX.json)"
trap 'rm -f "$CPU_TMP" "$MEM_TMP"' EXIT

curl -fsSG "${PROM_URL}/api/v1/query_range" \
  --data-urlencode "query=${CPU_QUERY}" \
  --data-urlencode "start=${START_TS}" \
  --data-urlencode "end=${END_TS}" \
  --data-urlencode "step=30" > "$CPU_TMP"

curl -fsSG "${PROM_URL}/api/v1/query_range" \
  --data-urlencode "query=${MEM_QUERY}" \
  --data-urlencode "start=${START_TS}" \
  --data-urlencode "end=${END_TS}" \
  --data-urlencode "step=30" > "$MEM_TMP"

OUT_CSV="${OUTPUT_DIR}/resource-metrics-${NAMESPACE}-${STAMP}.csv"
OUT_MD="${OUTPUT_DIR}/resource-metrics-${NAMESPACE}-${STAMP}.md"

python3 - "$CPU_TMP" "$MEM_TMP" "$OUT_CSV" "$OUT_MD" "$NAMESPACE" "$START_TS" "$END_TS" <<'PY'
import csv
import json
import sys
from statistics import mean

cpu_path, mem_path, out_csv, out_md, ns, start_ts, end_ts = sys.argv[1:8]

with open(cpu_path, "r", encoding="utf-8") as f:
    cpu = json.load(f)
with open(mem_path, "r", encoding="utf-8") as f:
    mem = json.load(f)

if cpu.get("status") != "success" or mem.get("status") != "success":
    raise SystemExit("Prometheus no devolvio status=success")

rows = {}

def add_values(payload, key):
    for series in payload.get("data", {}).get("result", []):
        pod = series.get("metric", {}).get("pod")
        if not pod:
            continue
        vals = []
        for point in series.get("values", []):
            if len(point) != 2:
                continue
            try:
                vals.append(float(point[1]))
            except Exception:
                continue
        if not vals:
            continue
        rec = rows.setdefault(pod, {})
        rec[key] = vals

add_values(cpu, "cpu")
add_values(mem, "mem")

if not rows:
    raise SystemExit("No se encontraron series CPU/memoria para el namespace indicado")

out_rows = []
for pod, data in sorted(rows.items()):
    cpu_vals = data.get("cpu", [])
    mem_vals = data.get("mem", [])
    out_rows.append({
        "namespace": ns,
        "pod": pod,
        "cpu_cores_avg": mean(cpu_vals) if cpu_vals else 0.0,
        "cpu_cores_max": max(cpu_vals) if cpu_vals else 0.0,
        "memory_bytes_avg": mean(mem_vals) if mem_vals else 0.0,
        "memory_bytes_max": max(mem_vals) if mem_vals else 0.0,
        "memory_mib_avg": (mean(mem_vals) / (1024 * 1024)) if mem_vals else 0.0,
        "memory_mib_max": (max(mem_vals) / (1024 * 1024)) if mem_vals else 0.0,
        "cpu_samples": len(cpu_vals),
        "mem_samples": len(mem_vals),
    })

with open(out_csv, "w", newline="", encoding="utf-8") as f:
    writer = csv.DictWriter(
        f,
        fieldnames=[
            "namespace", "pod", "cpu_cores_avg", "cpu_cores_max",
            "memory_bytes_avg", "memory_bytes_max", "memory_mib_avg", "memory_mib_max",
            "cpu_samples", "mem_samples",
        ],
    )
    writer.writeheader()
    writer.writerows(out_rows)

total_cpu_avg = sum(r["cpu_cores_avg"] for r in out_rows)
total_mem_mib_avg = sum(r["memory_mib_avg"] for r in out_rows)

with open(out_md, "w", encoding="utf-8") as f:
    f.write("# Resource Metrics Export\n\n")
    f.write(f"- Namespace: {ns}\n")
    f.write(f"- Window: {start_ts} -> {end_ts}\n")
    f.write(f"- Pods con datos: {len(out_rows)}\n")
    f.write(f"- CPU promedio total (cores): {total_cpu_avg:.4f}\n")
    f.write(f"- Memoria promedio total (MiB): {total_mem_mib_avg:.2f}\n\n")
    f.write("| Pod | CPU avg (cores) | CPU max (cores) | Mem avg (MiB) | Mem max (MiB) |\n")
    f.write("|---|---:|---:|---:|---:|\n")
    for r in out_rows:
        f.write(
            f"| {r['pod']} | {r['cpu_cores_avg']:.4f} | {r['cpu_cores_max']:.4f} | "
            f"{r['memory_mib_avg']:.2f} | {r['memory_mib_max']:.2f} |\n"
        )

print(out_csv)
print(out_md)
PY

echo "[INFO] Export CPU/memoria generado: ${OUT_CSV}"
echo "[INFO] Resumen markdown generado: ${OUT_MD}"
