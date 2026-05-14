#!/usr/bin/env python3
import csv
import glob
import os
from collections import defaultdict

import matplotlib.pyplot as plt

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SCALING_DIR = os.path.join(ROOT, "Testing", "results", "scaling_tests")
OUT_RESULTS = os.path.join(ROOT, "Testing", "results", "control_comparison")
OUT_PLOTS = os.path.join(ROOT, "Testing", "plots", "control_comparison")

METRICS = ["avg_ms", "p95_ms", "err_pct", "rps", "cpu_mcores", "mem_mib"]

VARIANT_ORDER = {
    "C1": ["baseline", "istio", "kong"],
    "C2": ["baseline", "istio-mtls", "linkerd-mtls"],
    "C3": ["baseline", "basic", "strict"],
    "C4": ["baseline", "moderate", "strict"],
}

SCENARIO_COLORS = {
    "S2": "#1f77b4",
    "S3": "#ff7f0e",
}

VARIANT_STYLES = {
    "baseline": ("o", "-"),
    "istio": ("s", "--"),
    "kong": ("^", ":"),
    "istio-mtls": ("s", "--"),
    "linkerd-mtls": ("^", ":"),
    "basic": ("s", "--"),
    "strict": ("^", ":"),
    "moderate": ("s", "--"),
}


def ensure_dirs():
    os.makedirs(OUT_RESULTS, exist_ok=True)
    os.makedirs(OUT_PLOTS, exist_ok=True)


def latest_file(pattern):
    matches = glob.glob(pattern)
    if not matches:
        return None
    matches.sort(key=os.path.getmtime)
    return matches[-1]


def latest_file_excluding(pattern, excluded_suffixes):
    matches = [p for p in glob.glob(pattern) if not any(p.endswith(s) for s in excluded_suffixes)]
    if not matches:
        return None
    matches.sort(key=os.path.getmtime)
    return matches[-1]


def detect_sources():
    s2 = latest_file(os.path.join(SCALING_DIR, "scaling-report_postgres-real_*.csv"))
    s3 = latest_file_excluding(
        os.path.join(SCALING_DIR, "scaling-report_mubench-advanced-controls_*.csv"),
        ["_summary.csv"],
    )
    return s2, s3


def parse_float(v):
    try:
        return float(str(v).strip())
    except Exception:
        return 0.0


def parse_int(v):
    try:
        return int(float(str(v).strip()))
    except Exception:
        return 0


def load_rows(path, scenario_label):
    rows = []
    if not path or not os.path.exists(path):
        return rows

    with open(path, newline="") as f:
        reader = csv.DictReader(f)
        for r in reader:
            status = (r.get("status") or "OK").strip()
            if status and status != "OK":
                continue

            control = (r.get("control") or "").strip()
            variant = (r.get("variant") or "").strip()
            vus = parse_int(r.get("vus", 0))
            if not control or not variant or vus <= 0:
                continue

            row = {
                "scenario": scenario_label,
                "control": control,
                "variant": variant,
                "vus": vus,
            }
            for m in METRICS:
                row[m] = parse_float(r.get(m, 0))
            rows.append(row)
    return rows


def write_long_csv(rows):
    out_path = os.path.join(OUT_RESULTS, "control_comparison_long.csv")
    with open(out_path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["scenario", "control", "variant", "vus", "metric", "value"])
        for r in rows:
            for m in METRICS:
                w.writerow([r["scenario"], r["control"], r["variant"], r["vus"], m, r[m]])
    return out_path


def write_mean_table(rows):
    grouped = defaultdict(list)
    for r in rows:
        grouped[(r["scenario"], r["control"], r["variant"])].append(r)

    out_path = os.path.join(OUT_RESULTS, "control_variant_means.csv")
    with open(out_path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["scenario", "control", "variant", "samples"] + [f"{m}_mean" for m in METRICS])

        for key in sorted(grouped.keys()):
            rs = grouped[key]
            means = []
            for m in METRICS:
                vals = [x[m] for x in rs]
                means.append(sum(vals) / len(vals) if vals else 0.0)
            w.writerow(list(key) + [len(rs)] + [f"{v:.4f}" for v in means])
    return out_path


def order_variants(control, variants):
    ref = VARIANT_ORDER.get(control, [])
    pos = {v: i for i, v in enumerate(ref)}
    return sorted(variants, key=lambda v: (pos.get(v, 999), v))


def plot_by_control(rows):
    by_sc_ctrl = defaultdict(list)
    for r in rows:
        by_sc_ctrl[(r["scenario"], r["control"])].append(r)

    saved = []

    for (scenario, control), rs in sorted(by_sc_ctrl.items()):
        by_variant = defaultdict(list)
        for r in rs:
            by_variant[r["variant"]].append(r)

        variants = order_variants(control, list(by_variant.keys()))

        fig, axes = plt.subplots(2, 3, figsize=(16, 9), dpi=140)
        axes = axes.flatten()

        for idx, metric in enumerate(METRICS):
            ax = axes[idx]
            for variant in variants:
                pts = sorted(by_variant[variant], key=lambda x: x["vus"])
                x = [p["vus"] for p in pts]
                y = [p[metric] for p in pts]
                marker, line = VARIANT_STYLES.get(variant, ("o", "-"))
                ax.plot(x, y, marker=marker, linestyle=line, linewidth=2, markersize=5, label=variant)

            ax.set_title(metric)
            ax.set_xlabel("VUs")
            ax.set_ylabel(metric)
            ax.grid(alpha=0.25)
            ax.set_xticks(sorted({p["vus"] for p in rs}))

        handles, labels = axes[0].get_legend_handles_labels()
        fig.legend(handles, labels, loc="upper center", ncol=min(4, len(labels)), frameon=False)
        fig.suptitle(f"{scenario} - {control}: baseline vs variantes por metrica", y=0.98)
        fig.tight_layout(rect=[0, 0, 1, 0.94])

        out_png = os.path.join(OUT_PLOTS, f"{scenario}_{control}_variants_metrics.png")
        fig.savefig(out_png)
        plt.close(fig)
        saved.append(out_png)

    return saved


def plot_cross_scenario(rows):
    by_ctrl_var_metric = defaultdict(list)
    for r in rows:
        for m in METRICS:
            by_ctrl_var_metric[(r["control"], r["variant"], m)].append(r)

    saved = []
    for (control, variant, metric), rs in sorted(by_ctrl_var_metric.items()):
        scenarios = sorted({r["scenario"] for r in rs})
        if len(scenarios) < 2:
            continue

        fig, ax = plt.subplots(figsize=(8, 5), dpi=140)
        for sc in scenarios:
            pts = sorted([r for r in rs if r["scenario"] == sc], key=lambda x: x["vus"])
            x = [p["vus"] for p in pts]
            y = [p[metric] for p in pts]
            color = SCENARIO_COLORS.get(sc, None)
            ax.plot(x, y, marker="o", linewidth=2, label=sc, color=color)

        ax.set_title(f"{control}/{variant} - {metric} (S2 vs S3)")
        ax.set_xlabel("VUs")
        ax.set_ylabel(metric)
        ax.grid(alpha=0.25)
        ax.legend(frameon=False)

        out_png = os.path.join(OUT_PLOTS, f"cross_{control}_{variant}_{metric}.png")
        fig.tight_layout()
        fig.savefig(out_png)
        plt.close(fig)
        saved.append(out_png)

    return saved


def write_report_md(s2_src, s3_src, long_csv, means_csv, per_control_pngs, cross_pngs):
    out = os.path.join(OUT_RESULTS, "control_comparison_report.md")
    with open(out, "w") as f:
        f.write("# Control Comparison Report (Baseline vs Variants)\n\n")
        f.write("Fuentes usadas:\n")
        f.write(f"- S2: `{s2_src or 'N/A'}`\n")
        f.write(f"- S3: `{s3_src or 'N/A'}`\n\n")

        f.write("Archivos generados:\n")
        f.write(f"- Long CSV (Grafana): `{long_csv}`\n")
        f.write(f"- Means CSV: `{means_csv}`\n")
        f.write(f"- Plots por control: {len(per_control_pngs)}\n")
        f.write(f"- Plots S2 vs S3 por control/variante/metrica: {len(cross_pngs)}\n\n")

        f.write("Lectura recomendada:\n")
        f.write("1. Revisar primero plots por control (baseline vs variantes).\n")
        f.write("2. Revisar luego plots cross_ para contrastar el mismo control/variante entre S2 y S3.\n")
        f.write("3. En Grafana, filtrar por control y metrica usando el long CSV.\n")

    return out


def main():
    ensure_dirs()

    s2_src, s3_src = detect_sources()
    rows = []
    rows.extend(load_rows(s2_src, "S2"))
    rows.extend(load_rows(s3_src, "S3"))

    if not rows:
        print("No rows loaded. Verify source CSV files in Testing/results/scaling_tests.")
        raise SystemExit(1)

    long_csv = write_long_csv(rows)
    means_csv = write_mean_table(rows)
    per_control = plot_by_control(rows)
    cross = plot_cross_scenario(rows)
    report = write_report_md(s2_src, s3_src, long_csv, means_csv, per_control, cross)

    print("Generated:")
    print(long_csv)
    print(means_csv)
    print(report)
    for p in per_control[:6]:
        print(p)
    if len(per_control) > 6:
        print(f"... ({len(per_control)} control plots total)")
    for p in cross[:6]:
        print(p)
    if len(cross) > 6:
        print(f"... ({len(cross)} cross-scenario plots total)")


if __name__ == "__main__":
    main()
