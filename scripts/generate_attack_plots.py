#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

import matplotlib.pyplot as plt
import pandas as pd
import seaborn as sns


ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "Testing" / "results" / "analysis_figures" / "attack_metrics_20260521"
PER_CONTROL_DIR = OUT_DIR / "per_control_metrics"


def load_c1() -> pd.DataFrame:
    df = pd.read_csv(ROOT / "Testing/results/attack_validation/c1_formal_20260521_194900/results_factorial.csv")
    return df[[
        "variant", "replica", "sqli_mitigation_rate", "avg_ms", "p95_ms", "rps",
        "cpu_mcores", "mem_mib"
    ]].copy()


def load_c2() -> pd.DataFrame:
    rows = []
    for path in sorted((ROOT / "Testing/results/attack_validation/c2_formal_20260521_152517").glob("*_summary.csv")):
        df = pd.read_csv(path)
        for _, row in df.iterrows():
            scenario = str(row["scenario"])
            parts = scenario.split("_")
            variant = "_".join(parts[1:-1])
            replica = parts[-1]
            rows.append({
                "variant": variant,
                "replica": replica,
                "attempts": float(row["attempts"]),
                "mitigation_rate": float(row["mitigation_rate"]),
                "blocked": float(row["blocked"]),
                "passed": float(row["passed"]),
            })
    return pd.DataFrame(rows)


def load_c3() -> pd.DataFrame:
    rows = []
    for path in sorted((ROOT / "Testing/results/attack_validation/c3_formal_20260521_154355").glob("*_summary.csv")):
        if path.name.endswith(".partial.csv"):
            continue
        df = pd.read_csv(path)
        for _, row in df.iterrows():
            scenario = str(row["scenario"])
            parts = scenario.split("_")
            variant = parts[1]
            replica = parts[2]
            rows.append({
                "variant": variant,
                "replica": replica,
                "probe": str(row["probe"]),
                "attempts": float(row["attempts"]),
                "mitigation_rate": float(row["mitigation_rate"]),
                "blocked": float(row["blocked"]),
                "passed": float(row["passed"]),
            })
    return pd.DataFrame(rows)


def load_c4() -> pd.DataFrame:
    df = pd.read_csv(ROOT / "Testing/results/attack_validation/c4_formal_20260521_192658/results_factorial.csv")
    return df[[
        "variant", "replica", "credstuff_mitigation_rate",
        "credstuff_attempts_total", "credstuff_ratelimited_total",
        "credstuff_unauthorized_total", "credstuff_success_total",
        "avg_ms", "p95_ms", "rps", "cpu_mcores", "mem_mib"
    ]].copy()


def save_bar_with_points(df: pd.DataFrame, x: str, y: str, title: str, ylabel: str, out_name: str) -> None:
    fig, ax = plt.subplots(figsize=(9, 6), constrained_layout=True)
    summary = df.groupby(x, observed=True)[y].mean().reset_index()
    sns.barplot(data=summary, x=x, y=y, ax=ax, color="#8fb9a8", edgecolor="#2e4a3f")
    sns.stripplot(data=df, x=x, y=y, ax=ax, color="#9b2c2c", size=8, jitter=0.08)
    ax.set_title(title, fontsize=14, weight="bold")
    ax.set_xlabel("")
    ax.set_ylabel(ylabel)
    ax.grid(True, axis="y", linestyle="--", alpha=0.25)
    fig.savefig(OUT_DIR / out_name, dpi=220, bbox_inches="tight")
    plt.close(fig)


def save_c3_heatmap(df: pd.DataFrame) -> None:
    pivot = df.pivot_table(index="variant", columns="probe", values="mitigation_rate", aggfunc="mean")
    fig, ax = plt.subplots(figsize=(8, 5), constrained_layout=True)
    sns.heatmap(pivot, annot=True, fmt=".2f", cmap="YlGnBu", linewidths=0.5, cbar_kws={"label": "Mitigation rate (%)"}, ax=ax)
    ax.set_title("C3 Attack Mitigation by Variant and Probe", fontsize=14, weight="bold")
    ax.set_xlabel("Probe")
    ax.set_ylabel("Variant")
    fig.savefig(OUT_DIR / "c3_attack_heatmap.png", dpi=220, bbox_inches="tight")
    plt.close(fig)


def save_c3_probe_lines(df: pd.DataFrame) -> None:
    fig, ax = plt.subplots(figsize=(9, 6), constrained_layout=True)
    sns.pointplot(data=df, x="probe", y="mitigation_rate", hue="variant", dodge=0.25, markers=["o", "s", "D"], capsize=0.1, err_kws={"linewidth": 1.2}, ax=ax)
    sns.stripplot(data=df, x="probe", y="mitigation_rate", hue="variant", dodge=True, jitter=0.07, alpha=0.5, size=4, ax=ax)
    handles, labels = ax.get_legend_handles_labels()
    ax.legend(handles[:3], labels[:3], title="Variant")
    ax.set_title("C3 Attack Mitigation by Probe", fontsize=14, weight="bold")
    ax.set_xlabel("Probe")
    ax.set_ylabel("Mitigation rate (%)")
    ax.grid(True, axis="y", linestyle="--", alpha=0.25)
    fig.savefig(OUT_DIR / "c3_attack_probe_lines.png", dpi=220, bbox_inches="tight")
    plt.close(fig)


def save_attack_overview(c1: pd.DataFrame, c2: pd.DataFrame, c4: pd.DataFrame) -> None:
    fig, axes = plt.subplots(1, 3, figsize=(16, 5), constrained_layout=True)

    datasets = [
        (c1, "variant", "sqli_mitigation_rate", "C1 SQLi"),
        (c2, "variant", "mitigation_rate", "C2 Lateral Movement"),
        (c4, "variant", "credstuff_mitigation_rate", "C4 CredStuff"),
    ]
    for ax, (df, x, y, title) in zip(axes, datasets):
        summary = df.groupby(x, observed=True)[y].mean().reset_index()
        sns.barplot(data=summary, x=x, y=y, ax=ax, color="#9fc5e8", edgecolor="#2b4c6f")
        sns.stripplot(data=df, x=x, y=y, ax=ax, color="#8a1c1c", size=7, jitter=0.08)
        ax.set_title(title, fontsize=12, weight="bold")
        ax.set_xlabel("")
        ax.set_ylabel("Mitigation rate (%)")
        ax.grid(True, axis="y", linestyle="--", alpha=0.25)
    fig.savefig(OUT_DIR / "attack_overview_c1_c2_c4.png", dpi=220, bbox_inches="tight")
    plt.close(fig)


def save_metric_grid(
    df: pd.DataFrame,
    variant_col: str,
    metrics: list[tuple[str, str]],
    title: str,
    out_name: str,
) -> None:
    fig, axes = plt.subplots(2, 2, figsize=(14, 10), constrained_layout=True)
    axes = axes.flatten()
    for ax, (metric, ylabel) in zip(axes, metrics):
        summary = df.groupby(variant_col, observed=True)[metric].mean().reset_index()
        sns.barplot(data=summary, x=variant_col, y=metric, ax=ax, color="#b7d7c8", edgecolor="#36594d")
        sns.stripplot(data=df, x=variant_col, y=metric, ax=ax, color="#9b2c2c", size=7, jitter=0.08)
        ax.set_title(ylabel, fontsize=12, weight="bold")
        ax.set_xlabel("")
        ax.set_ylabel(ylabel)
        ax.grid(True, axis="y", linestyle="--", alpha=0.25)
    fig.suptitle(title, fontsize=16, weight="bold")
    fig.savefig(OUT_DIR / out_name, dpi=220, bbox_inches="tight")
    plt.close(fig)


def save_bar_grid(
    df: pd.DataFrame,
    variant_col: str,
    metrics: list[tuple[str, str]],
    title: str,
    out_name: str,
) -> None:
    fig, axes = plt.subplots(2, 2, figsize=(14, 10), constrained_layout=True)
    axes = axes.flatten()
    for ax, (metric, ylabel) in zip(axes, metrics):
        summary = df.groupby(variant_col, observed=True)[metric].mean().reset_index()
        sns.barplot(data=summary, x=variant_col, y=metric, ax=ax, color="#c6d9f1", edgecolor="#355f8a")
        sns.stripplot(data=df, x=variant_col, y=metric, ax=ax, color="#8a1c1c", size=7, jitter=0.08)
        ax.set_title(ylabel, fontsize=12, weight="bold")
        ax.set_xlabel("")
        ax.set_ylabel(ylabel)
        ax.grid(True, axis="y", linestyle="--", alpha=0.25)
    fig.suptitle(title, fontsize=16, weight="bold")
    fig.savefig(OUT_DIR / out_name, dpi=220, bbox_inches="tight")
    plt.close(fig)


def save_c3_probe_metric_heatmap(df: pd.DataFrame, metric: str, label: str, out_name: str) -> None:
    pivot = df.pivot_table(index="variant", columns="probe", values=metric, aggfunc="mean")
    fig, ax = plt.subplots(figsize=(8, 5), constrained_layout=True)
    sns.heatmap(pivot, annot=True, fmt=".2f", cmap="YlOrBr", linewidths=0.5, cbar_kws={"label": label}, ax=ax)
    ax.set_title(f"C3 {label} by Variant and Probe", fontsize=14, weight="bold")
    ax.set_xlabel("Probe")
    ax.set_ylabel("Variant")
    fig.savefig(OUT_DIR / out_name, dpi=220, bbox_inches="tight")
    plt.close(fig)


def save_c3_probe_count_lines(df: pd.DataFrame, metric: str, label: str, out_name: str) -> None:
    fig, ax = plt.subplots(figsize=(9, 6), constrained_layout=True)
    sns.pointplot(data=df, x="probe", y=metric, hue="variant", dodge=0.25, markers=["o", "s", "D"], capsize=0.1, err_kws={"linewidth": 1.2}, ax=ax)
    sns.stripplot(data=df, x="probe", y=metric, hue="variant", dodge=True, jitter=0.07, alpha=0.5, size=4, ax=ax)
    handles, labels = ax.get_legend_handles_labels()
    ax.legend(handles[:3], labels[:3], title="Variant")
    ax.set_title(f"C3 {label} by Probe", fontsize=14, weight="bold")
    ax.set_xlabel("Probe")
    ax.set_ylabel(label)
    ax.grid(True, axis="y", linestyle="--", alpha=0.25)
    fig.savefig(OUT_DIR / out_name, dpi=220, bbox_inches="tight")
    plt.close(fig)


def main() -> None:
    sns.set_theme(style="whitegrid", context="talk")
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    PER_CONTROL_DIR.mkdir(parents=True, exist_ok=True)

    c1 = load_c1()
    c2 = load_c2()
    c3 = load_c3()
    c4 = load_c4()

    save_bar_with_points(c1, "variant", "sqli_mitigation_rate", "C1 SQLi Mitigation by Gateway", "Mitigation rate (%)", "c1_attack_mitigation.png")
    save_bar_with_points(c2, "variant", "mitigation_rate", "C2 Mitigation by mTLS Variant", "Mitigation rate (%)", "c2_attack_mitigation.png")
    save_bar_with_points(c4, "variant", "credstuff_mitigation_rate", "C4 CredStuff Mitigation by Rate Limit", "Mitigation rate (%)", "c4_attack_mitigation.png")

    save_c3_heatmap(c3)
    save_c3_probe_lines(c3)
    save_attack_overview(c1, c2, c4)
    save_bar_grid(
        c2,
        "variant",
        [("mitigation_rate", "Mitigation rate (%)"), ("blocked", "Blocked requests"), ("passed", "Passed requests"), ("attempts", "Attempts")],
        "C2 Attack Comparison by mTLS Variant",
        "c2_attack_counts_and_mitigation.png",
    )
    save_bar_grid(
        c4,
        "variant",
        [("credstuff_mitigation_rate", "Mitigation rate (%)"), ("credstuff_ratelimited_total", "Rate-limited requests"), ("credstuff_unauthorized_total", "Unauthorized requests"), ("credstuff_attempts_total", "Attempts")],
        "C4 Attack Comparison by Rate Limit",
        "c4_attack_counts_and_mitigation.png",
    )
    save_metric_grid(
        c1,
        "variant",
        [("avg_ms", "Average latency (ms)"), ("p95_ms", "P95 latency (ms)"), ("rps", "Throughput (req/s)"), ("cpu_mcores", "CPU (mCores)")],
        "C1 Attack-Phase Performance by Gateway",
        "c1_attack_performance_metrics.png",
    )
    save_metric_grid(
        c4,
        "variant",
        [("avg_ms", "Average latency (ms)"), ("p95_ms", "P95 latency (ms)"), ("rps", "Throughput (req/s)"), ("cpu_mcores", "CPU (mCores)")],
        "C4 Attack-Phase Performance by Rate Limit",
        "c4_attack_performance_metrics.png",
    )
    save_c3_probe_metric_heatmap(c3, "blocked", "Blocked requests", "c3_attack_blocked_heatmap.png")
    save_c3_probe_metric_heatmap(c3, "passed", "Passed requests", "c3_attack_passed_heatmap.png")
    save_c3_probe_count_lines(c3, "blocked", "Blocked requests", "c3_attack_blocked_lines.png")
    save_c3_probe_count_lines(c3, "passed", "Passed requests", "c3_attack_passed_lines.png")

    (OUT_DIR / "attack_plot_notes.txt").write_text(
        "C1/C2/C4 show per-replica mitigation by variant. C3 includes heatmaps and probe-level comparisons for mitigation, blocked, and passed counts. Additional C1/C4 performance grids expose attack-phase differences in latency, throughput, and CPU that are hidden when only mitigation_rate is plotted.\n"
    )
    print(f"saved_plots={OUT_DIR}")


if __name__ == "__main__":
    main()