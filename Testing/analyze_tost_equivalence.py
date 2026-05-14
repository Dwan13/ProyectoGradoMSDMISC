#!/usr/bin/env python3
"""Run TOST-style equivalence analysis for C1-C4.

This script is intended for campaigns with replicated observations per cell.
It compares each variant against the baseline within each control and VU level.

Default SESOI margins are grounded in the current methodological notes:
- avg_ms: +/-1.0 ms
- p95_ms: +/-3.0 ms
- err_pct: +/-1.0 percentage points
- rps: +/-1.0 req/s
- cpu_mcores: +/-100 mCores
- mem_mib: +/-150 MiB

Usage:
  /bin/python3 Testing/analyze_tost_equivalence.py \
    --input Testing/results/scaling_tests/scaling-report_postgres-real_20260510.csv \
    --output-dir Testing/results/scaling_tests/tost_equivalence

For replicated campaigns across days, pass multiple inputs:
  /bin/python3 Testing/analyze_tost_equivalence.py \
    --input Testing/results/scaling_tests/scaling-report_postgres-real_20260509.csv \
    --input Testing/results/scaling_tests/scaling-report_postgres-real_20260510.csv
"""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import Dict, List

import pandas as pd
from statsmodels.stats.weightstats import ttost_ind

DEFAULT_MARGINS: Dict[str, float] = {
    "avg_ms": 1.0,
    "p95_ms": 3.0,
    "err_pct": 1.0,
    "rps": 1.0,
    "cpu_mcores": 100.0,
    "mem_mib": 150.0,
}

DEFAULT_CONTROLS = ["C1", "C2", "C3", "C4"]
DEFAULT_METRICS = ["avg_ms", "p95_ms", "err_pct", "rps", "cpu_mcores", "mem_mib"]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run TOST equivalence analysis for C1-C4.")
    parser.add_argument("--input", dest="inputs", action="append", required=True, help="Input CSV file. Repeat for multiple campaign files.")
    parser.add_argument("--output-dir", default="Testing/results/scaling_tests/tost_equivalence", help="Output directory for CSV and Markdown reports.")
    parser.add_argument("--controls", nargs="*", default=DEFAULT_CONTROLS, help="Controls to analyze.")
    parser.add_argument("--metrics", nargs="*", default=DEFAULT_METRICS, help="Metrics to analyze.")
    return parser.parse_args()


def load_data(paths: List[str]) -> pd.DataFrame:
    frames = []
    for raw_path in paths:
        path = Path(raw_path)
        frame = pd.read_csv(path)
        frame["source_file"] = path.name
        frames.append(frame)
    data = pd.concat(frames, ignore_index=True)
    return data


def classify_result(p_value: float, mean_diff: float, margin: float) -> str:
    if pd.isna(p_value):
        return "insufficient_data"
    if p_value < 0.05:
        return "equivalent_within_margin"
    if abs(mean_diff) > margin:
        return "difference_exceeds_margin"
    return "inconclusive_power_or_variance"


def main() -> None:
    args = parse_args()
    data = load_data(args.inputs)
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    results = []
    data = data[data["control"].isin(args.controls)].copy()

    for control in sorted(data["control"].unique()):
        control_df = data[data["control"] == control]
        for vus in sorted(control_df["vus"].unique()):
            vus_df = control_df[control_df["vus"] == vus]
            baseline_df = vus_df[vus_df["variant"] == "baseline"]
            if baseline_df.empty:
                continue

            for variant in sorted(v for v in vus_df["variant"].unique() if v != "baseline"):
                variant_df = vus_df[vus_df["variant"] == variant]
                for metric in args.metrics:
                    margin = DEFAULT_MARGINS[metric]
                    baseline_vals = baseline_df[metric].dropna().tolist()
                    variant_vals = variant_df[metric].dropna().tolist()
                    if len(baseline_vals) < 2 or len(variant_vals) < 2:
                        p_value = float("nan")
                        mean_diff = float("nan")
                        low_p = float("nan")
                        high_p = float("nan")
                    else:
                        p_value, (low_stat, low_p, _), (high_stat, high_p, _) = ttost_ind(
                            variant_vals,
                            baseline_vals,
                            -margin,
                            margin,
                            usevar="unequal",
                        )
                        mean_diff = float(pd.Series(variant_vals).mean() - pd.Series(baseline_vals).mean())

                    results.append(
                        {
                            "control": control,
                            "vus": vus,
                            "variant": variant,
                            "baseline_variant": "baseline",
                            "metric": metric,
                            "margin_abs": margin,
                            "baseline_n": len(baseline_vals),
                            "variant_n": len(variant_vals),
                            "mean_diff_variant_minus_baseline": mean_diff,
                            "tost_pvalue": p_value,
                            "lower_test_pvalue": low_p,
                            "upper_test_pvalue": high_p,
                            "interpretation": classify_result(p_value, mean_diff, margin),
                        }
                    )

    result_df = pd.DataFrame(results)
    csv_path = output_dir / "tost_equivalence_results.csv"
    result_df.to_csv(csv_path, index=False)

    lines: List[str] = []
    lines.append("# TOST Equivalence Report")
    lines.append("")
    lines.append("## Decision rule")
    lines.append("- `equivalent_within_margin`: both one-sided tests passed with p < 0.05.")
    lines.append("- `difference_exceeds_margin`: observed mean difference exceeds SESOI margin.")
    lines.append("- `inconclusive_power_or_variance`: not enough evidence to declare equivalence.")
    lines.append("- `insufficient_data`: fewer than 2 observations per group.")
    lines.append("")
    lines.append("## SESOI margins")
    for metric in args.metrics:
        lines.append(f"- {metric}: +/-{DEFAULT_MARGINS[metric]}")
    lines.append("")
    lines.append("## Summary")
    if result_df.empty:
        lines.append("- No comparable rows found for the requested controls/metrics.")
    else:
        summary = result_df.groupby(["metric", "interpretation"]).size().reset_index(name="count")
        for _, row in summary.iterrows():
            lines.append(f"- {row['metric']} | {row['interpretation']} | {int(row['count'])}")
    lines.append("")
    lines.append(f"CSV output: {csv_path.as_posix()}")

    md_path = output_dir / "tost_equivalence_report.md"
    md_path.write_text("\n".join(lines), encoding="utf-8")

    print(csv_path.as_posix())
    print(md_path.as_posix())


if __name__ == "__main__":
    main()
