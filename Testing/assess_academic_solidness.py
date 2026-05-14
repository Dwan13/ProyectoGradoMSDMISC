#!/usr/bin/env python3
"""Assess whether the S2 campaign meets minimum academic solidity criteria.

Checks:
- Replication coverage per (control, variant, vus)
- Presence of all base cells (4 x 3 x 4 = 48)
- Optional TOST status distribution
- Produces CSV + markdown report with GO/NO-GO verdict
"""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import List

import pandas as pd

BASE_VARIANTS = {
    "C1": ["baseline", "istio", "kong"],
    "C2": ["baseline", "istio-mtls", "linkerd-mtls"],
    "C3": ["baseline", "basic", "strict"],
    "C4": ["baseline", "moderate", "strict"],
}
VUS = [1, 5, 10, 20]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Assess academic solidity of S2 experiment outputs.")
    parser.add_argument("--input", dest="inputs", action="append", required=True, help="Input scaling report CSV (repeat option for multiple campaigns).")
    parser.add_argument("--min-replicates", type=int, default=6, help="Minimum replicate target per cell (default: 6).")
    parser.add_argument("--tost-results", default="", help="Optional TOST results CSV path.")
    parser.add_argument("--output-dir", default="Testing/results/scaling_tests/academic_solidness", help="Output directory.")
    return parser.parse_args()


def load_data(paths: List[str]) -> pd.DataFrame:
    frames = []
    for p in paths:
        path = Path(p)
        df = pd.read_csv(path)
        df["source_file"] = path.name
        frames.append(df)
    data = pd.concat(frames, ignore_index=True)
    return data


def expected_cells() -> pd.DataFrame:
    rows = []
    for c, variants in BASE_VARIANTS.items():
        for v in variants:
            for vus in VUS:
                rows.append({"control": c, "variant": v, "vus": vus})
    return pd.DataFrame(rows)


def main() -> None:
    args = parse_args()
    out_dir = Path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    data = load_data(args.inputs)
    data = data[data["control"].isin(BASE_VARIANTS.keys())].copy()

    counts = (
        data.groupby(["control", "variant", "vus"], as_index=False)
        .size()
        .rename(columns={"size": "replicates"})
    )

    exp = expected_cells()
    coverage = exp.merge(counts, on=["control", "variant", "vus"], how="left")
    coverage["replicates"] = coverage["replicates"].fillna(0).astype(int)
    coverage["meets_min_replicates"] = coverage["replicates"] >= args.min_replicates

    missing_cells = int((coverage["replicates"] == 0).sum())
    low_rep_cells = int((coverage["replicates"] < args.min_replicates).sum())
    complete_cells = int((coverage["replicates"] >= args.min_replicates).sum())
    total_cells = int(len(coverage))

    verdict = "GO"
    blockers = []
    if missing_cells > 0:
        verdict = "NO_GO"
        blockers.append(f"Missing cells: {missing_cells}")
    if low_rep_cells > 0:
        verdict = "NO_GO"
        blockers.append(f"Cells below min replicates ({args.min_replicates}): {low_rep_cells}")

    tost_summary = None
    if args.tost_results:
        tpath = Path(args.tost_results)
        if tpath.exists():
            tdf = pd.read_csv(tpath)
            if not tdf.empty and "interpretation" in tdf.columns:
                tost_summary = (
                    tdf.groupby(["metric", "interpretation"], as_index=False)
                    .size()
                    .rename(columns={"size": "count"})
                )
                inconclusive = int((tdf["interpretation"] == "inconclusive_power_or_variance").sum())
                total_tost = int(len(tdf))
                ratio = inconclusive / total_tost if total_tost else 0.0
                if ratio > 0.20:
                    verdict = "NO_GO"
                    blockers.append(f"TOST inconclusive ratio too high: {ratio:.1%} (>20%)")

    coverage_csv = out_dir / "coverage_by_cell.csv"
    coverage.to_csv(coverage_csv, index=False)

    if tost_summary is not None:
        tost_csv = out_dir / "tost_summary.csv"
        tost_summary.to_csv(tost_csv, index=False)
    else:
        tost_csv = None

    md = out_dir / "academic_solidness_report.md"
    lines = []
    lines.append("# Academic Solidness Assessment")
    lines.append("")
    lines.append(f"- verdict: {verdict}")
    lines.append(f"- total_cells: {total_cells}")
    lines.append(f"- complete_cells_min_replicates: {complete_cells}")
    lines.append(f"- low_replication_cells: {low_rep_cells}")
    lines.append(f"- missing_cells: {missing_cells}")
    lines.append("")
    lines.append("## Inputs")
    for p in args.inputs:
        lines.append(f"- {p}")
    if args.tost_results:
        lines.append(f"- tost_results: {args.tost_results}")
    lines.append("")
    lines.append("## Blockers")
    if blockers:
        for b in blockers:
            lines.append(f"- {b}")
    else:
        lines.append("- none")
    lines.append("")
    lines.append("## Outputs")
    lines.append(f"- coverage: {coverage_csv.as_posix()}")
    if tost_csv:
        lines.append(f"- tost_summary: {tost_csv.as_posix()}")

    md.write_text("\n".join(lines), encoding="utf-8")

    print(md.as_posix())
    print(coverage_csv.as_posix())
    if tost_csv:
        print(tost_csv.as_posix())


if __name__ == "__main__":
    main()
