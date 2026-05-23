#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
from pathlib import Path


def to_float(value: str) -> float | None:
    if value is None or value == "":
        return None
    try:
        return float(value)
    except Exception:
        return None


def classify(row: dict) -> tuple[str, str]:
    status = row.get("status", "")
    error = (row.get("error", "") or "").lower()
    checks = to_float(row.get("checks_pct", ""))
    err_pct = to_float(row.get("err_pct", ""))
    cpu = to_float(row.get("cpu_mcores", ""))
    mem = to_float(row.get("mem_mib", ""))

    if "apply-scenario" in error or "tls handshake timeout" in error:
        return "invalid_infra", "scenario_apply_failed"
    if status != "ok":
        return "repeat", "run_status_not_ok"
    if checks is None or err_pct is None:
        return "repeat", "missing_k6_metrics"
    if checks < 99.0 or err_pct > 1.0:
        return "repeat", f"checks={checks:.2f},err={err_pct:.2f}"
    if cpu is None or mem is None:
        return "repeat", "missing_resource_metrics"
    if cpu <= 0.0 or mem <= 0.0:
        return "repeat", f"resource_metrics_suspicious cpu={cpu},mem={mem}"
    return "accept", "ok"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("csv_paths", nargs="+", help="results_factorial.csv a evaluar")
    args = ap.parse_args()

    for csv_path_str in args.csv_paths:
        csv_path = Path(csv_path_str)
        print(f"FILE {csv_path}")
        with csv_path.open(newline="") as f:
            rows = list(csv.DictReader(f))

        counts: dict[str, int] = {}
        flagged: list[tuple[str, str, str]] = []
        for row in rows:
            label, reason = classify(row)
            counts[label] = counts.get(label, 0) + 1
            if label != "accept":
                flagged.append((row.get("run_id", ""), label, reason))

        print("summary", counts)
        if flagged:
            print("flagged_rows")
            for run_id, label, reason in flagged:
                print(run_id, label, reason)
        print()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())