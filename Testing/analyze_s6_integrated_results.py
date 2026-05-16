#!/usr/bin/env python3
"""Analyze S6 integrated campaign results (quality + security).

Outputs one CSV row per run with:
- 6 core metrics: avg_ms, p95_ms, err_pct, rps, cpu_mcores, mem_mib
- business/security traces: login_ok, users_ok, jwt_trace_events, unique_jwt_fp
- DB latency traces from API payloads: profile_db_latency_ms_avg, users_db_latency_ms_avg
"""

from __future__ import annotations

import argparse
import csv
import json
import re
from collections import defaultdict
from datetime import datetime, timedelta
from glob import glob
from pathlib import Path
from statistics import mean

import requests


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Analyze S6 integrated results.")
    parser.add_argument(
        "--input-glob",
        default="/home/dwan13/muBench/Testing/results/auto_runs/randomized_campaigns/s6_*.json",
        help="Glob pattern for S6 NDJSON result files.",
    )
    parser.add_argument(
        "--prom-url",
        default="http://localhost:30000",
        help="Prometheus base URL.",
    )
    parser.add_argument(
        "--namespace",
        default="mubench-real",
        help="Kubernetes namespace for resource queries.",
    )
    parser.add_argument(
        "--output",
        default="/home/dwan13/muBench/Testing/results/scaling_tests/s6_integrated_metrics.csv",
        help="Output CSV path.",
    )
    parser.add_argument(
        "--matrix",
        default="/home/dwan13/muBench/Testing/results/scaling_tests/design_matrix_s6_integrated_dual_n4_randomized_blocks.csv",
        help="Optional design matrix CSV used to whitelist expected output filenames.",
    )
    return parser.parse_args()


def load_expected_filenames(matrix_path: str) -> set[str] | None:
    p = Path(matrix_path)
    if not p.exists():
        return None

    expected: set[str] = set()
    with p.open("r", encoding="utf-8", newline="") as fh:
        reader = csv.DictReader(fh)
        required = {
            "campaign_id",
            "block_day",
            "random_order",
            "control",
            "variant",
            "security_mode",
            "vus",
        }
        if not required.issubset(set(reader.fieldnames or [])):
            return None

        for row in reader:
            try:
                filename = (
                    f"{row['campaign_id']}_{row['block_day']}_order{int(row['random_order'])}_"
                    f"{row['control']}_{row['variant']}_{row['security_mode']}_{int(row['vus'])}vus.json"
                )
            except Exception:
                continue
            expected.add(filename)

    return expected if expected else None


def parse_filename(name: str) -> dict:
    # s6_*_B1_2026-05-20_order12_C2_istio-mtls_attack_20vus.json
    m = re.search(r"(B\d+_\d{4}-\d{2}-\d{2})_order(\d+)_([C]\d+)_([^_]+)_(normal|attack)_(\d+)vus", name)
    if not m:
        return {}
    return {
        "block_day": m.group(1),
        "order": int(m.group(2)),
        "control": m.group(3),
        "variant": m.group(4),
        "security_mode": m.group(5),
        "vus": int(m.group(6)),
    }


def parse_ndjson_metrics(path: Path) -> dict:
    durations = []
    req_count = 0
    failed_rate_points = []
    times = []

    login_ok = 0
    users_ok = 0
    jwt_trace_events = 0
    jwt_fps = set()

    profile_db_lat = []
    users_db_lat = []

    with path.open("r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue

            if obj.get("type") != "Point":
                continue

            metric = obj.get("metric", "")
            data = obj.get("data", {})
            tags = data.get("tags", {})

            t = data.get("time")
            if t:
                times.append(t)

            if metric == "http_req_duration":
                try:
                    durations.append(float(data.get("value", 0)))
                except Exception:
                    pass
            elif metric == "http_reqs":
                try:
                    req_count += int(data.get("value", 0))
                except Exception:
                    pass

                name = tags.get("name", "")
                method = tags.get("method", "")
                status = str(tags.get("status", ""))

                if "/login" in name and method == "POST" and status == "200":
                    login_ok += 1
                if "/users" in name and method == "GET" and status == "200":
                    users_ok += 1

            elif metric == "http_req_failed":
                try:
                    failed_rate_points.append(float(data.get("value", 0)))
                except Exception:
                    pass
            elif metric == "jwt_trace_events":
                jwt_trace_events += 1
                fp = tags.get("jwt_fp")
                if fp:
                    jwt_fps.add(fp)
            elif metric == "profile_db_latency_ms":
                try:
                    v = float(data.get("value", 0))
                    if v > 0:
                        profile_db_lat.append(v)
                except Exception:
                    pass
            elif metric == "users_db_latency_ms":
                try:
                    v = float(data.get("value", 0))
                    if v > 0:
                        users_db_lat.append(v)
                except Exception:
                    pass

    durations_sorted = sorted(durations)
    if durations_sorted:
        avg_ms = mean(durations_sorted)
        p95_idx = min(int(0.95 * len(durations_sorted)), len(durations_sorted) - 1)
        p95_ms = durations_sorted[p95_idx]
    else:
        avg_ms = 0.0
        p95_ms = 0.0

    err_pct = (mean(failed_rate_points) * 100.0) if failed_rate_points else 0.0

    start = min(times) if times else None
    end = max(times) if times else None

    return {
        "avg_ms": round(avg_ms, 4),
        "p95_ms": round(p95_ms, 4),
        "err_pct": round(err_pct, 4),
        "total_reqs": req_count,
        "login_ok": login_ok,
        "users_ok": users_ok,
        "jwt_trace_events": jwt_trace_events,
        "unique_jwt_fp": len(jwt_fps),
        "profile_db_latency_ms_avg": round(mean(profile_db_lat), 4) if profile_db_lat else 0.0,
        "users_db_latency_ms_avg": round(mean(users_db_lat), 4) if users_db_lat else 0.0,
        "start_iso": start,
        "end_iso": end,
    }


def parse_iso(ts: str) -> datetime:
    fixed = ts.replace("Z", "+00:00")
    # Trim nanoseconds to microseconds
    if "." in fixed:
        prefix, rest = fixed.split(".", 1)
        if "+" in rest:
            frac, tz = rest.split("+", 1)
            fixed = f"{prefix}.{frac[:6]}+{tz}"
        elif "-" in rest:
            frac, tz = rest.split("-", 1)
            fixed = f"{prefix}.{frac[:6]}-{tz}"
    return datetime.fromisoformat(fixed)


def query_prom(prom_url: str, query: str, start: datetime, end: datetime, step: str = "15s") -> dict:
    url = f"{prom_url}/api/v1/query_range"
    resp = requests.get(
        url,
        params={
            "query": query,
            "start": start.timestamp(),
            "end": end.timestamp(),
            "step": step,
        },
        timeout=20,
    )
    resp.raise_for_status()
    return resp.json()


def summarize_prom(prom_result: dict) -> float | None:
    if prom_result.get("status") != "success":
        return None
    series = prom_result.get("data", {}).get("result", [])
    values = []
    for s in series:
        for _, val in s.get("values", []):
            try:
                values.append(float(val))
            except Exception:
                pass
    if not values:
        return None
    return mean(values)


def fetch_resource_metrics(prom_url: str, namespace: str, start: datetime, end: datetime) -> tuple[float | None, float | None]:
    pod_regex = "(api-service|auth-service|data-service|postgres).*"
    cpu_q = (
        "sum(rate(container_cpu_usage_seconds_total{"
        f'namespace="{namespace}", pod=~"{pod_regex}", container!="POD", image!=""'
        "}[1m])) * 1000"
    )
    mem_q = (
        "sum(container_memory_working_set_bytes{"
        f'namespace="{namespace}", pod=~"{pod_regex}", container!="POD", image!=""'
        "}) / 1024 / 1024"
    )

    cpu = summarize_prom(query_prom(prom_url, cpu_q, start, end))
    mem = summarize_prom(query_prom(prom_url, mem_q, start, end))

    # Retry with margins if scrape windows are sparse
    if cpu is None:
        cpu = summarize_prom(query_prom(prom_url, cpu_q, start - timedelta(minutes=5), end + timedelta(minutes=5)))
    if mem is None:
        mem = summarize_prom(query_prom(prom_url, mem_q, start - timedelta(minutes=5), end + timedelta(minutes=5)))

    return cpu, mem


def main() -> None:
    args = parse_args()
    files = [Path(p) for p in sorted(glob(args.input_glob))]

    expected = load_expected_filenames(args.matrix)
    if expected is not None:
        files = [f for f in files if f.name in expected]

    if not files:
        print("No input files found.")
        return

    rows = []
    for f in files:
        meta = parse_filename(f.name)
        if not meta:
            continue

        m = parse_ndjson_metrics(f)
        if not m.get("start_iso") or not m.get("end_iso"):
            continue

        start = parse_iso(m["start_iso"])
        end = parse_iso(m["end_iso"])
        dur_s = max((end - start).total_seconds(), 1.0)
        rps = m["total_reqs"] / dur_s

        cpu_mcores, mem_mib = fetch_resource_metrics(args.prom_url, args.namespace, start, end)

        row = {
            **meta,
            "file": f.as_posix(),
            "start_iso": m["start_iso"],
            "end_iso": m["end_iso"],
            "avg_ms": m["avg_ms"],
            "p95_ms": m["p95_ms"],
            "err_pct": m["err_pct"],
            "rps": round(rps, 4),
            "cpu_mcores": "" if cpu_mcores is None else round(cpu_mcores, 4),
            "mem_mib": "" if mem_mib is None else round(mem_mib, 4),
            "login_ok": m["login_ok"],
            "users_ok": m["users_ok"],
            "jwt_trace_events": m["jwt_trace_events"],
            "unique_jwt_fp": m["unique_jwt_fp"],
            "profile_db_latency_ms_avg": m["profile_db_latency_ms_avg"],
            "users_db_latency_ms_avg": m["users_db_latency_ms_avg"],
        }
        rows.append(row)

    out_path = Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    fieldnames = [
        "block_day", "order", "control", "variant", "security_mode", "vus",
        "file", "start_iso", "end_iso",
        "avg_ms", "p95_ms", "err_pct", "rps", "cpu_mcores", "mem_mib",
        "login_ok", "users_ok", "jwt_trace_events", "unique_jwt_fp",
        "profile_db_latency_ms_avg", "users_db_latency_ms_avg",
    ]

    with out_path.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)

    print(f"rows={len(rows)}")
    print(f"output={out_path.as_posix()}")


if __name__ == "__main__":
    main()
