#!/usr/bin/env python3
import csv
import json
import math
import re
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Dict, List

ROOT = Path(__file__).resolve().parents[1]
RESULTS_DIR = ROOT / "Testing/results/auto_runs/randomized_campaigns"
INPUT_GLOB = "s2_academic_base_n8_*.json"
DATE_TAG = datetime.now().strftime("%Y-%m-%d")
CSV_OUT = RESULTS_DIR / f"s2_coherence_report_{DATE_TAG}.csv"
MD_OUT = RESULTS_DIR / f"s2_coherence_report_{DATE_TAG}.md"

NAME_RE = re.compile(
    r"s2_academic_base_n8_(B\d+_\d{4}-\d{2}-\d{2})_order(\d+)_([A-Z]\d)_(.+)_(normal|attack)_(\d+)vus\.json$"
)


@dataclass
class RunStats:
    file: str
    block_day: str
    order: int
    control: str
    variant: str
    security_mode: str
    vus: int
    iterations: int
    http_reqs: int
    login_success_total: int
    profile_success_total: int
    users_list_success_total: int
    avg_ms: float
    p95_ms: float
    failed_rate_pct: float
    anomalies: List[str]


def parse_points(path: Path) -> List[dict]:
    points = []
    with path.open("r", encoding="utf-8", errors="ignore") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except Exception:
                continue
            if obj.get("type") == "Point":
                points.append(obj)
    return points


def vals(points: List[dict], metric: str) -> List[float]:
    out = []
    for p in points:
        if p.get("metric") == metric:
            try:
                out.append(float(p.get("data", {}).get("value", 0) or 0))
            except Exception:
                pass
    return out


def sum_metric(points: List[dict], metric: str) -> float:
    return sum(vals(points, metric))


def quantile95(values: List[float]) -> float:
    if not values:
        return 0.0
    s = sorted(values)
    idx = min(int(len(s) * 0.95), len(s) - 1)
    return s[idx]


def analyze_run(path: Path) -> RunStats:
    m = NAME_RE.match(path.name)
    if not m:
        raise ValueError(f"Unexpected filename format: {path.name}")

    block_day, order, control, variant, security_mode, vus = m.groups()
    points = parse_points(path)

    duration_vals = vals(points, "http_req_duration")
    failed_vals = vals(points, "http_req_failed")

    iterations = int(sum_metric(points, "iterations"))
    http_reqs = int(sum_metric(points, "http_reqs"))
    login_success_total = int(sum_metric(points, "login_success_total"))
    profile_success_total = int(sum_metric(points, "profile_success_total"))
    users_list_success_total = int(sum_metric(points, "users_list_success_total"))

    avg_ms = (sum(duration_vals) / len(duration_vals)) if duration_vals else 0.0
    p95_ms = quantile95(duration_vals)
    failed_rate_pct = (
        100.0 * (sum(failed_vals) / len(failed_vals)) if failed_vals else 0.0
    )

    anomalies: List[str] = []

    if avg_ms > p95_ms + 1e-9:
        anomalies.append("avg_http_req_duration_gt_p95")

    if avg_ms < 0 or p95_ms < 0:
        anomalies.append("negative_latency")

    if not (0.0 <= failed_rate_pct <= 100.0):
        anomalies.append("invalid_failed_rate")

    if profile_success_total > login_success_total:
        anomalies.append("profile_success_gt_login_success")

    if users_list_success_total > login_success_total:
        anomalies.append("users_success_gt_login_success")

    if iterations <= 0:
        anomalies.append("zero_or_negative_iterations")

    if http_reqs <= 0:
        anomalies.append("zero_or_negative_http_reqs")

    if security_mode == "normal" and iterations > 0:
        # In this flow we expect ~3 requests per iteration (login/profile/users).
        expected = iterations * 3
        if expected > 0:
            ratio = http_reqs / expected
            if ratio < 0.80 or ratio > 1.20:
                anomalies.append("unexpected_http_reqs_per_iteration")

    if (
        security_mode == "normal"
        and login_success_total >= 50
        and users_list_success_total == 0
    ):
        anomalies.append("users_endpoint_zero_success_with_many_logins")

    if (
        security_mode == "normal"
        and login_success_total >= 50
        and profile_success_total == 0
    ):
        anomalies.append("profile_endpoint_zero_success_with_many_logins")

    return RunStats(
        file=path.name,
        block_day=block_day,
        order=int(order),
        control=control,
        variant=variant,
        security_mode=security_mode,
        vus=int(vus),
        iterations=iterations,
        http_reqs=http_reqs,
        login_success_total=login_success_total,
        profile_success_total=profile_success_total,
        users_list_success_total=users_list_success_total,
        avg_ms=round(avg_ms, 3),
        p95_ms=round(p95_ms, 3),
        failed_rate_pct=round(failed_rate_pct, 3),
        anomalies=anomalies,
    )


def main() -> int:
    files = sorted(RESULTS_DIR.glob(INPUT_GLOB))
    runs = [analyze_run(p) for p in files]

    CSV_OUT.parent.mkdir(parents=True, exist_ok=True)
    with CSV_OUT.open("w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(
            [
                "file",
                "block_day",
                "order",
                "control",
                "variant",
                "security_mode",
                "vus",
                "iterations",
                "http_reqs",
                "login_success_total",
                "profile_success_total",
                "users_list_success_total",
                "avg_http_req_duration_ms",
                "p95_http_req_duration_ms",
                "http_req_failed_rate_pct",
                "anomalies",
            ]
        )
        for r in runs:
            w.writerow(
                [
                    r.file,
                    r.block_day,
                    r.order,
                    r.control,
                    r.variant,
                    r.security_mode,
                    r.vus,
                    r.iterations,
                    r.http_reqs,
                    r.login_success_total,
                    r.profile_success_total,
                    r.users_list_success_total,
                    r.avg_ms,
                    r.p95_ms,
                    r.failed_rate_pct,
                    "|".join(r.anomalies),
                ]
            )

    with MD_OUT.open("w", encoding="utf-8") as fh:
        fh.write("# S2 Coherence Report\n\n")
        fh.write(f"- Runs analyzed: {len(runs)}\n")
        flagged = [r for r in runs if r.anomalies]
        fh.write(f"- Runs with anomalies: {len(flagged)}\n")
        fh.write(f"- CSV detail: {CSV_OUT.relative_to(ROOT)}\n\n")

        if flagged:
            fh.write("## Flagged Runs\n\n")
            for r in flagged:
                fh.write(
                    f"- {r.file}: {', '.join(r.anomalies)} "
                    f"(avg={r.avg_ms}ms, p95={r.p95_ms}ms, fail={r.failed_rate_pct}%)\n"
                )
        else:
            fh.write("## Flagged Runs\n\n- None\n")

    print(f"runs={len(runs)}")
    print(f"flagged={len([r for r in runs if r.anomalies])}")
    print(CSV_OUT)
    print(MD_OUT)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
