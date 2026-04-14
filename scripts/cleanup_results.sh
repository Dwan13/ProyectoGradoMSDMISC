#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="${ROOT_DIR}/Testing/results"

# Defaults (override with env vars or flags):
# KEEP_RUNS=1 DRY_RUN=0 DELETE_RAW_IN_KEPT=1 ./scripts/cleanup_results.sh
KEEP_RUNS="${KEEP_RUNS:-1}"
DRY_RUN="${DRY_RUN:-0}"
DELETE_RAW_IN_KEPT="${DELETE_RAW_IN_KEPT:-1}"
TOTAL_CLEAN="${TOTAL_CLEAN:-0}"

usage() {
  cat <<'EOF'
Usage: cleanup_results.sh [--keep-runs N] [--dry-run] [--keep-raw] [--total-clean]

Options:
  --keep-runs N   Keep latest N run directories per prefix (default: 1)
  --dry-run       Print what would be deleted without deleting
  --keep-raw      Do not delete raw JSON files in kept directories
  --total-clean   Keep only the latest entry in Testing/results and delete all others

This script targets heavy experiment outputs under Testing/results and:
1) keeps only latest N directories per run prefix,
2) optionally deletes raw/fault-raw JSON from kept directories,
3) removes temporary run logs in /tmp.

When --total-clean is used, it overrides prefix logic and keeps only the newest
file/directory entry in Testing/results.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --keep-runs)
      KEEP_RUNS="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --keep-raw)
      DELETE_RAW_IN_KEPT=0
      shift
      ;;
    --total-clean)
      TOTAL_CLEAN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ ! -d "${RESULTS_DIR}" ]]; then
  echo "[INFO] No results directory: ${RESULTS_DIR}"
  exit 0
fi

log() { echo "[cleanup] $*"; }

run_or_echo() {
  if [[ "${DRY_RUN}" == "1" ]]; then
    echo "[dry-run] $*"
  else
    eval "$@"
  fi
}

size_before="$(du -sh "${RESULTS_DIR}" 2>/dev/null | awk '{print $1}')"
log "Size before: ${size_before}"

if [[ "${TOTAL_CLEAN}" == "1" ]]; then
  mapfile -t entries < <(find "${RESULTS_DIR}" -maxdepth 1 -mindepth 1 -printf '%T@ %p\n' | sort -nr | awk '{print $2}')
  total_entries="${#entries[@]}"

  if (( total_entries > 1 )); then
    keep_entry="${entries[0]}"
    log "Total clean: keeping latest entry: $(basename "${keep_entry}")"
    for ((i=1; i<total_entries; i++)); do
      run_or_echo "rm -rf '${entries[$i]}'"
    done
  fi

  run_or_echo "rm -f /tmp/c1*-realistic-run*.log /tmp/c2*-realistic-run*.log /tmp/c3*-realistic-run*.log /tmp/c4*-realistic-run*.log /tmp/c*r-*.log /tmp/c*r-prom-pf.log"

  size_after="$(du -sh "${RESULTS_DIR}" 2>/dev/null | awk '{print $1}')"
  log "Size after: ${size_after}"
  log "Done. total_clean=1, dry_run=${DRY_RUN}"
  exit 0
fi

# Prefixes observed in this repo.
prefixes=(
  "c1-realistic-"
  "c1-only-"
  "c2-realistic-"
  "c2-mesh-realistic-"
  "c3-realistic-"
  "c4-realistic-"
  "c2-mesh-consolidated-"
)

for prefix in "${prefixes[@]}"; do
  mapfile -t dirs < <(find "${RESULTS_DIR}" -maxdepth 1 -mindepth 1 -type d -name "${prefix}*" -printf '%T@ %p\n' | sort -nr | awk '{print $2}')
  total="${#dirs[@]}"
  if (( total == 0 )); then
    continue
  fi

  log "Prefix ${prefix}: found ${total} directories"

  # Delete old directories beyond KEEP_RUNS.
  if (( total > KEEP_RUNS )); then
    for ((i=KEEP_RUNS; i<total; i++)); do
      d="${dirs[$i]}"
      run_or_echo "rm -rf '${d}'"
    done
  fi

  # Optionally remove huge raw files in kept directories.
  if [[ "${DELETE_RAW_IN_KEPT}" == "1" ]]; then
    keep_count="${total}"
    if (( keep_count > KEEP_RUNS )); then
      keep_count="${KEEP_RUNS}"
    fi
    for ((i=0; i<keep_count; i++)); do
      d="${dirs[$i]}"
      run_or_echo "find '${d}' -maxdepth 1 -type f \\( -name 'raw-*.json' -o -name 'fault-raw-*.json' \\) -delete"
    done
  fi
done

# Remove temporary run logs.
run_or_echo "rm -f /tmp/c1*-realistic-run*.log /tmp/c2*-realistic-run*.log /tmp/c3*-realistic-run*.log /tmp/c4*-realistic-run*.log /tmp/c*r-*.log /tmp/c*r-prom-pf.log"

size_after="$(du -sh "${RESULTS_DIR}" 2>/dev/null | awk '{print $1}')"
log "Size after: ${size_after}"

log "Done. keep_runs=${KEEP_RUNS}, dry_run=${DRY_RUN}, delete_raw_in_kept=${DELETE_RAW_IN_KEPT}"
