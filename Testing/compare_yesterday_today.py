#!/usr/bin/env python3
"""
Compare MuBench randomized campaign results between two dates.

Outputs:
- CSV matrices and detailed tables
- PNG charts for day-over-day comparisons

Focus dimensions:
- VUs: 1, 5, 10, 20
- Controls: C1, C2, C3, C4
- Scenario/variant within each control
- Login/profile success counts derived from k6 check points
"""

from __future__ import annotations

import argparse
import json
import math
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Tuple

import matplotlib.pyplot as plt
import pandas as pd
import seaborn as sns


FILENAME_RE = re.compile(
    r"^(?P<prefix>.+?)_(?P<day>\d{4}-\d{2}-\d{2})_order(?P<order>\d+)_"
    r"(?P<control>C\d)_(?P<variant>.+)_(?P<vus>\d+)vus\.json$"
)

TARGET_VUS = {1, 5, 10, 20}
TARGET_CONTROLS = {"C1", "C2", "C3", "C4"}


@dataclass
class RunMeta:
    path: Path
    day: str
    order: int
    control: str
    variant: str
    vus: int


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Compare campaign results by day")
    parser.add_argument(
        "--input-dir",
        default="Testing/results/auto_runs/randomized_campaigns",
        help="Directory containing campaign JSON NDJSON outputs",
    )
    parser.add_argument("--day-a", required=True, help="First day, e.g. 2026-05-11")
    parser.add_argument("--day-b", required=True, help="Second day, e.g. 2026-05-12")
    parser.add_argument(
        "--output-dir",
        default="Testing/results/comparisons",
        help="Output directory for CSV and PNG files",
    )
    return parser.parse_args()


def discover_runs(input_dir: Path, day_a: str, day_b: str) -> List[RunMeta]:
    runs: List[RunMeta] = []
    wanted_days = {day_a, day_b}

    for path in sorted(input_dir.glob("*.json")):
        m = FILENAME_RE.match(path.name)
        if not m:
            continue

        day = m.group("day")
        if day not in wanted_days:
            continue

        control = m.group("control")
        vus = int(m.group("vus"))
        if control not in TARGET_CONTROLS or vus not in TARGET_VUS:
            continue

        runs.append(
            RunMeta(
                path=path,
                day=day,
                order=int(m.group("order")),
                control=control,
                variant=m.group("variant"),
                vus=vus,
            )
        )

    return runs


def safe_quantile(values: List[float], q: float) -> float:
    if not values:
        return math.nan
    series = pd.Series(values)
    return float(series.quantile(q))


def summarize_run(meta: RunMeta) -> Dict[str, float]:
    duration_vals: List[float] = []
    http_failed_vals: List[float] = []
    http_reqs_count = 0.0

    checks_success = 0.0
    checks_total = 0

    login_success = 0.0
    login_total = 0
    profile_success = 0.0
    profile_total = 0

    with meta.path.open("r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue

            metric = obj.get("metric")
            if not metric:
                continue

            data = obj.get("data", {})
            val = data.get("value")
            if val is None:
                continue

            tags = data.get("tags", {}) or {}

            if metric == "http_req_duration":
                duration_vals.append(float(val))
            elif metric == "http_req_failed":
                http_failed_vals.append(float(val))
            elif metric == "http_reqs":
                http_reqs_count += float(val)
            elif metric == "checks":
                v = float(val)
                checks_success += v
                checks_total += 1

                check_name = tags.get("check")
                if check_name == "login has token":
                    login_success += v
                    login_total += 1
                elif check_name == "profile has user":
                    profile_success += v
                    profile_total += 1

    failed_count = sum(http_failed_vals)
    err_pct = (failed_count / http_reqs_count * 100.0) if http_reqs_count > 0 else math.nan
    checks_pct = (checks_success / checks_total * 100.0) if checks_total > 0 else math.nan

    login_success_pct = (login_success / login_total * 100.0) if login_total > 0 else math.nan
    profile_success_pct = (profile_success / profile_total * 100.0) if profile_total > 0 else math.nan

    return {
        "day": meta.day,
        "order": meta.order,
        "control": meta.control,
        "variant": meta.variant,
        "vus": meta.vus,
        "avg_ms": float(pd.Series(duration_vals).mean()) if duration_vals else math.nan,
        "p95_ms": safe_quantile(duration_vals, 0.95),
        "http_reqs": http_reqs_count,
        "http_failed_count": failed_count,
        "err_pct": err_pct,
        "checks_pct": checks_pct,
        "login_success": login_success,
        "login_total": login_total,
        "login_success_pct": login_success_pct,
        "profile_success": profile_success,
        "profile_total": profile_total,
        "profile_success_pct": profile_success_pct,
    }


def build_day_summary(df: pd.DataFrame) -> pd.DataFrame:
    group_cols = ["day", "control", "variant", "vus"]
    grouped = (
        df.groupby(group_cols, as_index=False)
        .agg(
            runs=("order", "count"),
            avg_ms=("avg_ms", "mean"),
            p95_ms=("p95_ms", "mean"),
            err_pct=("err_pct", "mean"),
            http_reqs=("http_reqs", "sum"),
            http_failed_count=("http_failed_count", "sum"),
            checks_pct=("checks_pct", "mean"),
            login_success=("login_success", "sum"),
            login_total=("login_total", "sum"),
            profile_success=("profile_success", "sum"),
            profile_total=("profile_total", "sum"),
        )
        .sort_values(["day", "control", "variant", "vus"])
    )

    grouped["login_success_pct"] = (grouped["login_success"] / grouped["login_total"] * 100.0).round(3)
    grouped["profile_success_pct"] = (grouped["profile_success"] / grouped["profile_total"] * 100.0).round(3)

    return grouped


def build_control_vus_matrix(summary: pd.DataFrame, metric: str) -> pd.DataFrame:
    base = (
        summary.groupby(["day", "control", "vus"], as_index=False)[metric]
        .mean()
        .pivot_table(index=["control", "vus"], columns="day", values=metric)
        .reset_index()
    )

    days = [c for c in base.columns if c not in {"control", "vus"}]
    if len(days) == 2:
        base["delta_b_minus_a"] = base[days[1]] - base[days[0]]
    return base


def make_plots(summary: pd.DataFrame, day_a: str, day_b: str, out_dir: Path) -> None:
    sns.set_style("whitegrid")
    plt.rcParams.update({"figure.dpi": 160, "savefig.dpi": 220})

    controls = sorted(summary["control"].unique())
    metrics = [
        ("p95_ms", "P95 Latency (ms)"),
        ("err_pct", "Error Rate (%)"),
        ("login_success_pct", "Login Success (%)"),
        ("profile_success_pct", "Profile Success (%)"),
    ]

    for metric_key, metric_label in metrics:
        fig, axes = plt.subplots(2, 2, figsize=(13, 9), sharex=True)
        fig.suptitle(f"{metric_label}: {day_a} vs {day_b}", fontweight="bold")

        for i, ctrl in enumerate(controls):
            ax = axes[i // 2, i % 2]
            sub = summary[summary["control"] == ctrl]
            sns.lineplot(
                data=sub,
                x="vus",
                y=metric_key,
                hue="day",
                style="variant",
                markers=True,
                dashes=False,
                ax=ax,
            )
            ax.set_title(ctrl)
            ax.set_xticks([1, 5, 10, 20])
            ax.set_xlabel("VUs")
            ax.set_ylabel(metric_label)

        plt.tight_layout()
        fig.savefig(out_dir / f"plot_{metric_key}_by_control.png", bbox_inches="tight")
        plt.close(fig)

    # Heatmap delta p95 by control-vus (averaging variants)
    p95_base = (
        summary.groupby(["day", "control", "vus"], as_index=False)["p95_ms"].mean()
        .pivot_table(index=["control", "vus"], columns="day", values="p95_ms")
        .reset_index()
    )
    if {day_a, day_b}.issubset(set(p95_base.columns)):
        p95_base["delta"] = p95_base[day_b] - p95_base[day_a]
        heat = p95_base.pivot(index="control", columns="vus", values="delta")
        fig, ax = plt.subplots(figsize=(8, 4))
        sns.heatmap(heat, annot=True, fmt=".2f", cmap="RdYlGn_r", center=0, ax=ax)
        ax.set_title(f"Delta P95 (ms): {day_b} - {day_a}")
        fig.savefig(out_dir / "heatmap_delta_p95_control_vus.png", bbox_inches="tight")
        plt.close(fig)


def main() -> None:
    args = parse_args()

    input_dir = Path(args.input_dir)
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    runs = discover_runs(input_dir, args.day_a, args.day_b)
    if not runs:
        raise SystemExit("No se encontraron corridas para esas fechas con C1-C4 y VUs 1/5/10/20")

    rows = [summarize_run(run) for run in runs]
    raw = pd.DataFrame(rows).sort_values(["day", "order"])
    summary = build_day_summary(raw)

    raw.to_csv(output_dir / "raw_runs_yesterday_today.csv", index=False)
    summary.to_csv(output_dir / "summary_by_day_control_variant_vus.csv", index=False)

    # Matrices por control+vus
    for metric in ["p95_ms", "err_pct", "login_success_pct", "profile_success_pct", "http_reqs"]:
        mat = build_control_vus_matrix(summary, metric)
        mat.to_csv(output_dir / f"matrix_control_vus_{metric}.csv", index=False)

    make_plots(summary, args.day_a, args.day_b, output_dir)

    print("[OK] Comparativa generada")
    print(f"[OK] Output: {output_dir}")


if __name__ == "__main__":
    main()
