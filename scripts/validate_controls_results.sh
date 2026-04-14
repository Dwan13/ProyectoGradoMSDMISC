#!/usr/bin/env bash
set -euo pipefail

INPUT=""
OUTPUT=""
REPORT=""
INPLACE=0

usage() {
  cat <<EOF
Usage: $0 --input <csv> --output <clean_csv> --report <md> [--inplace]

Options:
  --input <path>    CSV consolidado original
  --output <path>   CSV limpio de salida
  --report <path>   Reporte markdown de validacion
  --inplace         Reemplazar el archivo de entrada con el limpio
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --input)
      INPUT="$2"
      shift 2
      ;;
    --output)
      OUTPUT="$2"
      shift 2
      ;;
    --report)
      REPORT="$2"
      shift 2
      ;;
    --inplace)
      INPLACE=1
      shift
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

if [[ -z "$INPUT" || -z "$OUTPUT" || -z "$REPORT" ]]; then
  usage
  exit 1
fi

if [[ ! -f "$INPUT" ]]; then
  echo "[ERROR] No existe archivo de entrada: $INPUT" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT")" "$(dirname "$REPORT")"

python3 - "$INPUT" "$OUTPUT" "$REPORT" <<'PY'
import csv
import sys
from collections import Counter

input_csv, output_csv, report_md = sys.argv[1:4]

valid = []
invalid = []
controls = Counter()

with open(input_csv, "r", newline="", encoding="utf-8") as f:
    reader = csv.DictReader(f)
    for row in reader:
        try:
            avg = float(row.get("avg_ms", "0") or 0)
            p95 = float(row.get("p95_ms", "0") or 0)
            vus = int(float(row.get("vus", "0") or 0))
            control = (row.get("control") or "unknown").strip()
        except Exception:
            invalid.append((row, "parse_error"))
            continue

        if avg <= 0 or p95 <= 0:
            invalid.append((row, "non_positive_metric"))
            continue
        if vus < 0:
            invalid.append((row, "invalid_vus"))
            continue

        controls[control] += 1
        valid.append(row)

with open(output_csv, "w", newline="", encoding="utf-8") as f:
    if valid:
        writer = csv.DictWriter(f, fieldnames=list(valid[0].keys()))
    else:
        writer = csv.DictWriter(f, fieldnames=["control", "scenario", "vus", "avg_ms", "p95_ms"])
    writer.writeheader()
    writer.writerows(valid)

required_controls = ["C1-api-gateway", "C2-mtls", "C3-netpol", "C4-ratelimit"]
missing_controls = [c for c in required_controls if controls[c] == 0]

with open(report_md, "w", encoding="utf-8") as f:
    f.write("# Validation Report - Consolidado C1-C4\n\n")
    f.write(f"- Input rows: {len(valid) + len(invalid)}\n")
    f.write(f"- Valid rows: {len(valid)}\n")
    f.write(f"- Invalid rows removed: {len(invalid)}\n")
    f.write(f"- Output CSV: {output_csv}\n\n")

    f.write("## Cobertura por control\n\n")
    for c in required_controls:
        f.write(f"- {c}: {controls[c]} filas\n")

    if missing_controls:
        f.write("\n## Advertencias\n\n")
        for c in missing_controls:
            f.write(f"- Sin datos para {c}.\n")

    if invalid:
        reasons = Counter(reason for _, reason in invalid)
        f.write("\n## Motivos de descarte\n\n")
        for reason, count in reasons.items():
            f.write(f"- {reason}: {count}\n")

print(len(valid))
print(len(invalid))
print("1" if missing_controls else "0")
PY

if [[ "$INPLACE" == "1" ]]; then
  cp "$OUTPUT" "$INPUT"
  echo "[INFO] Reemplazado CSV original con versión limpia"
fi

echo "[INFO] CSV limpio: $OUTPUT"
echo "[INFO] Reporte: $REPORT"
