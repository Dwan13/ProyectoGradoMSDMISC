#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Uso: ./scripts/generate_line_report.sh <archivo_relativo> [salida_md]" >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_REL="$1"
TARGET_FILE="${ROOT_DIR}/${TARGET_REL}"
OUT_FILE="${2:-${ROOT_DIR}/Docs/line-report-$(basename "$TARGET_REL").md}"

if [[ ! -f "$TARGET_FILE" ]]; then
  echo "[ERROR] Archivo no encontrado: $TARGET_FILE" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUT_FILE")"

{
  echo "# Line Report"
  echo
  echo "Archivo: ${TARGET_REL}"
  echo
  echo "Generado: $(date '+%Y-%m-%d %H:%M:%S')"
  echo
  echo "## Contenido numerado"
  echo
  echo '```text'
  nl -ba "$TARGET_FILE"
  echo '```'
} > "$OUT_FILE"

echo "[OK] Reporte generado en: $OUT_FILE"
