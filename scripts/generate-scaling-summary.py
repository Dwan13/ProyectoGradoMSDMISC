#!/usr/bin/env python3
import csv
import glob
import os
import sys
from collections import defaultdict


EXPECTED_PAIRS = [
    ("C1", "baseline"),
    ("C1", "istio"),
    ("C1", "kong"),
    ("C2", "baseline"),
    ("C2", "istio-mtls"),
    ("C2", "linkerd-mtls"),
    ("C3", "baseline"),
    ("C3", "basic"),
    ("C3", "strict"),
    ("C4", "baseline"),
    ("C4", "moderate"),
    ("C4", "strict"),
]
EXPECTED_VUS = [1, 5, 10, 20]


def to_float(v):
    if v is None:
        return None
    s = str(v).strip().replace("%", "")
    if s == "":
        return None
    try:
        return float(s)
    except ValueError:
        return None


def pct_delta(curr, base):
    if curr is None or base is None or base == 0:
        return ""
    return f"{((curr - base) / base) * 100:.2f}"


def load_latest_report(path_arg=None):
    if path_arg:
        if not os.path.exists(path_arg):
            raise FileNotFoundError(path_arg)
        return path_arg

    matches = sorted(glob.glob("Testing/results/scaling_tests/scaling-report_*.csv"))
    if not matches:
        raise FileNotFoundError("No scaling-report_*.csv found")
    return matches[-1]


def main():
    report_path = load_latest_report(sys.argv[1] if len(sys.argv) > 1 else None)
    out_dir = os.path.dirname(report_path)
    suffix = os.path.basename(report_path).replace("scaling-report_", "").replace(".csv", "")

    with open(report_path, newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f))

    if not rows:
        print(f"[WARN] Empty report: {report_path}")
        return 1

    # Index baseline del mismo control por VU para comparacion intra-control.
    baseline_idx = {}
    for r in rows:
        c = r.get("control", "")
        v = r.get("variant", "")
        vus = int(r.get("vus", 0) or 0)
        if v == "baseline":
            baseline_idx[(c, vus)] = {
                "avg_ms": to_float(r.get("avg_ms")),
                "p95_ms": to_float(r.get("p95_ms")),
                "err_pct": to_float(r.get("err_pct")),
                "rps": to_float(r.get("rps")),
                "cpu_mcores": to_float(r.get("cpu_mcores")),
                "mem_mib": to_float(r.get("mem_mib")),
            }

    # Consolidado enriquecido con deltas intra-control.
    summary_rows = []
    for r in sorted(rows, key=lambda x: (x.get("control", ""), x.get("variant", ""), int(x.get("vus", 0) or 0))):
        control = r.get("control", "")
        variant = r.get("variant", "")
        vus = int(r.get("vus", 0) or 0)

        curr = {
            "avg_ms": to_float(r.get("avg_ms")),
            "p95_ms": to_float(r.get("p95_ms")),
            "err_pct": to_float(r.get("err_pct")),
            "rps": to_float(r.get("rps")),
            "cpu_mcores": to_float(r.get("cpu_mcores")),
            "mem_mib": to_float(r.get("mem_mib")),
        }
        base = baseline_idx.get((control, vus), None)

        out = dict(r)
        out["delta_avg_ms_vs_control_baseline_pct"] = pct_delta(curr["avg_ms"], base["avg_ms"] if base else None)
        out["delta_p95_ms_vs_control_baseline_pct"] = pct_delta(curr["p95_ms"], base["p95_ms"] if base else None)
        out["delta_err_pct_vs_control_baseline_pct"] = pct_delta(curr["err_pct"], base["err_pct"] if base else None)
        out["delta_rps_vs_control_baseline_pct"] = pct_delta(curr["rps"], base["rps"] if base else None)
        out["delta_cpu_mcores_vs_control_baseline_pct"] = pct_delta(curr["cpu_mcores"], base["cpu_mcores"] if base else None)
        out["delta_mem_mib_vs_control_baseline_pct"] = pct_delta(curr["mem_mib"], base["mem_mib"] if base else None)
        out["has_control_baseline_for_vus"] = "yes" if base else "no"
        summary_rows.append(out)

    summary_csv = os.path.join(out_dir, f"scaling-summary_{suffix}.csv")
    fieldnames = [
        "control",
        "variant",
        "vus",
        "avg_ms",
        "p95_ms",
        "err_pct",
        "rps",
        "cpu_mcores",
        "mem_mib",
        "delta_avg_ms_vs_control_baseline_pct",
        "delta_p95_ms_vs_control_baseline_pct",
        "delta_err_pct_vs_control_baseline_pct",
        "delta_rps_vs_control_baseline_pct",
        "delta_cpu_mcores_vs_control_baseline_pct",
        "delta_mem_mib_vs_control_baseline_pct",
        "has_control_baseline_for_vus",
    ]
    with open(summary_csv, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        w.writerows(summary_rows)

    # Diagnostico de cobertura por control/escenario y VUs esperados.
    seen = defaultdict(set)
    for r in rows:
        key = (r.get("control", ""), r.get("variant", ""))
        seen[key].add(int(r.get("vus", 0) or 0))

    missing_pairs = [p for p in EXPECTED_PAIRS if p not in seen]
    missing_vus = {}
    for p in EXPECTED_PAIRS:
        have = seen.get(p, set())
        miss = [v for v in EXPECTED_VUS if v not in have]
        if miss:
            missing_vus[p] = miss

    coverage_md = os.path.join(out_dir, f"scaling-coverage_{suffix}.md")
    with open(coverage_md, "w", encoding="utf-8") as f:
        f.write("# Scaling Coverage\n\n")
        f.write(f"Source report: {report_path}\n\n")
        f.write(f"Rows: {len(rows)}\n")
        f.write(f"Scenario pairs present: {len(seen)} / {len(EXPECTED_PAIRS)}\n\n")

        f.write("## Missing Scenario Pairs\n\n")
        if not missing_pairs:
            f.write("None\n\n")
        else:
            for c, v in missing_pairs:
                f.write(f"- {c}/{v}\n")
            f.write("\n")

        f.write("## Missing VU Stages By Pair\n\n")
        if not missing_vus:
            f.write("None\n")
        else:
            for (c, v), miss in sorted(missing_vus.items()):
                f.write(f"- {c}/{v}: missing {miss}\n")

    print(f"[OK] Source:    {report_path}")
    print(f"[OK] Summary:   {summary_csv}")
    print(f"[OK] Coverage:  {coverage_md}")
    print(f"[OK] Pairs:     {len(seen)}/{len(EXPECTED_PAIRS)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
