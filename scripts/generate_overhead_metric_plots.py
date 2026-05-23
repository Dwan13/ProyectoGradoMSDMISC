#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

import matplotlib.pyplot as plt
import pandas as pd
import seaborn as sns


ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "Testing" / "results" / "analysis_figures" / "overhead_metrics_20260521"
PER_CONTROL_DIR = OUT_DIR / "per_control_metrics"
MEAN_BARS_DIR = OUT_DIR / "mean_bars"

METRICS = [
    ("avg_ms", "Average Latency (ms)"),
    ("p95_ms", "P95 Latency (ms)"),
    ("err_pct", "Error Rate (%)"),
    ("rps", "Throughput (req/s)"),
    ("cpu_mcores", "CPU (mCores)"),
    ("mem_mib", "Memory (MiB)"),
]

CONTROL_FILES = {
    "C1": [
        ROOT / "Testing/results/factorial_campaign/c1_overhead_block12_20260521_074829/results_factorial.csv",
        ROOT / "Testing/results/factorial_campaign/c1_prelim_block12_20260521_082345/results_factorial.csv",
        ROOT / "Testing/results/factorial_campaign/c1_prelim_block34_20260521_084310/results_factorial.csv",
        ROOT / "Testing/results/factorial_campaign/c1_overhead_r4_20260521_074147/results_factorial.csv",
    ],
    "C2": [
        ROOT / "Testing/results/factorial_campaign/c2_prelim_block12_20260521_091437/results_factorial.csv",
        ROOT / "Testing/results/factorial_campaign/c2_prelim_block34_20260521_094234/results_factorial.csv",
    ],
    "C3": [
        ROOT / "Testing/results/factorial_campaign/c3_prelim_block12_20260521_103639/results_factorial.csv",
        ROOT / "Testing/results/factorial_campaign/c3_prelim_block34_20260521_105430/results_factorial.csv",
    ],
    "C4": [
        ROOT / "Testing/results/factorial_campaign/c4_prelim_block12_20260521_111640/results_factorial.csv",
        ROOT / "Testing/results/factorial_campaign/c4_prelim_block34_nominal_20260521_113553/results_factorial.csv",
    ],
}

VARIANT_ORDER = {
    "C1": ["baseline", "istio", "kong"],
    "C2": ["baseline", "istio_mtls", "linkerd_mtls"],
    "C3": ["baseline", "basic", "strict"],
    "C4": ["baseline", "moderate", "strict"],
}


def load_control_frame(control: str) -> pd.DataFrame:
    frames = []
    for file_path in CONTROL_FILES[control]:
        if file_path.exists():
            frames.append(pd.read_csv(file_path))
    if not frames:
        return pd.DataFrame()

    df = pd.concat(frames, ignore_index=True)
    df = df[(df["control"] == control) & (df["status"] == "ok")].copy()
    df["vus"] = pd.to_numeric(df["vus"], errors="coerce")
    df["replica"] = pd.to_numeric(df["replica"], errors="coerce")
    df["variant"] = pd.Categorical(df["variant"], categories=VARIANT_ORDER[control], ordered=True)
    return df.sort_values(["variant", "vus", "replica", "started_at"])


def style_axes(ax: plt.Axes, title: str, ylabel: str) -> None:
    ax.set_title(title, fontsize=11, weight="bold")
    ax.set_xlabel("VUs")
    ax.set_ylabel(ylabel)
    ax.grid(True, linestyle="--", alpha=0.25)


def save_per_control_figure(control: str, df: pd.DataFrame) -> None:
    fig, axes = plt.subplots(2, 3, figsize=(18, 9), constrained_layout=True)
    fig.suptitle(f"{control} Overhead by Metric", fontsize=16, weight="bold")

    for ax, (metric, label) in zip(axes.flatten(), METRICS):
        raw = df.dropna(subset=[metric]).copy()
        sns.scatterplot(
            data=raw,
            x="vus",
            y=metric,
            hue="variant",
            style="variant",
            s=70,
            alpha=0.8,
            ax=ax,
            legend=False,
        )

        summary = (
            raw.groupby(["variant", "vus"], observed=True)[metric]
            .mean()
            .reset_index()
            .sort_values(["variant", "vus"])
        )
        sns.lineplot(
            data=summary,
            x="vus",
            y=metric,
            hue="variant",
            style="variant",
            markers=True,
            dashes=False,
            linewidth=2.2,
            ax=ax,
            legend=False,
        )
        style_axes(ax, label, label)

    handles, labels = axes[0, 0].get_legend_handles_labels()
    if handles and labels:
        fig.legend(handles, labels, loc="upper center", ncol=3, frameon=False, bbox_to_anchor=(0.5, 1.02))

    fig.savefig(OUT_DIR / f"{control.lower()}_overhead_6metrics.png", dpi=220, bbox_inches="tight")
    plt.close(fig)


def save_per_metric_figure(metric: str, label: str, frames: dict[str, pd.DataFrame]) -> None:
    fig, axes = plt.subplots(2, 2, figsize=(16, 10), constrained_layout=True)
    fig.suptitle(f"{label} by Control", fontsize=16, weight="bold")

    for ax, control in zip(axes.flatten(), ["C1", "C2", "C3", "C4"]):
        df = frames[control].dropna(subset=[metric]).copy()
        if df.empty:
            ax.text(0.5, 0.5, "No data", ha="center", va="center")
            ax.set_axis_off()
            continue

        sns.scatterplot(
            data=df,
            x="vus",
            y=metric,
            hue="variant",
            style="variant",
            s=65,
            alpha=0.8,
            ax=ax,
            legend=False,
        )
        summary = (
            df.groupby(["variant", "vus"], observed=True)[metric]
            .mean()
            .reset_index()
            .sort_values(["variant", "vus"])
        )
        sns.lineplot(
            data=summary,
            x="vus",
            y=metric,
            hue="variant",
            style="variant",
            markers=True,
            dashes=False,
            linewidth=2.0,
            ax=ax,
            legend=False,
        )
        style_axes(ax, control, label)

    handles, labels = axes[0, 0].get_legend_handles_labels()
    if handles and labels:
        fig.legend(handles, labels, loc="upper center", ncol=3, frameon=False, bbox_to_anchor=(0.5, 1.02))

    fig.savefig(OUT_DIR / f"metric_{metric}_by_control.png", dpi=220, bbox_inches="tight")
    plt.close(fig)


def save_single_metric_control_figure(control: str, df: pd.DataFrame, metric: str, label: str) -> None:
    fig, ax = plt.subplots(figsize=(9, 6), constrained_layout=True)
    raw = df.dropna(subset=[metric]).copy()
    sns.scatterplot(
        data=raw,
        x="vus",
        y=metric,
        hue="variant",
        style="variant",
        s=80,
        alpha=0.85,
        ax=ax,
        legend=False,
    )
    summary = (
        raw.groupby(["variant", "vus"], observed=True)[metric]
        .mean()
        .reset_index()
        .sort_values(["variant", "vus"])
    )
    sns.lineplot(
        data=summary,
        x="vus",
        y=metric,
        hue="variant",
        style="variant",
        markers=True,
        dashes=False,
        linewidth=2.4,
        ax=ax,
        legend=True,
    )
    style_axes(ax, f"{control} - {label}", label)
    ax.legend(title="Variant", frameon=False)
    fig.savefig(PER_CONTROL_DIR / f"{control.lower()}_{metric}.png", dpi=220, bbox_inches="tight")
    plt.close(fig)


def save_control_mean_bars(control: str, df: pd.DataFrame) -> None:
    available = [metric for metric, _ in METRICS if metric in df.columns]
    if not available:
        return

    grouped = (
        df.groupby("variant", observed=True)[available]
        .mean()
        .reset_index()
        .melt(id_vars="variant", var_name="metric", value_name="value")
    )
    label_map = {metric: label for metric, label in METRICS}
    grouped["metric_label"] = grouped["metric"].map(label_map)

    fig, axes = plt.subplots(2, 3, figsize=(18, 9), constrained_layout=True)
    fig.suptitle(f"{control} - Mean Comparison by Metric", fontsize=16, weight="bold")
    for ax, (metric, label) in zip(axes.flatten(), METRICS):
        subset = grouped[grouped["metric"] == metric]
        if subset.empty:
            ax.set_axis_off()
            continue
        sns.barplot(data=subset, x="variant", y="value", ax=ax, color="#b7d7c8", edgecolor="#36594d")
        ax.set_title(label, fontsize=11, weight="bold")
        ax.set_xlabel("")
        ax.set_ylabel(label)
        ax.grid(True, axis="y", linestyle="--", alpha=0.25)
    fig.savefig(MEAN_BARS_DIR / f"{control.lower()}_mean_bars.png", dpi=220, bbox_inches="tight")
    plt.close(fig)


def save_coverage_report(frames: dict[str, pd.DataFrame]) -> None:
    lines = ["# Overhead plot coverage", ""]
    for control, df in frames.items():
        lines.append(f"## {control}")
        if df.empty:
            lines.append("No data found.")
            lines.append("")
            continue
        pivot = df.pivot_table(index="variant", columns="vus", values="replica", aggfunc="count", fill_value=0)
        lines.append(pivot.to_csv())
        lines.append("")
    (OUT_DIR / "coverage.md").write_text("\n".join(lines))


def main() -> None:
    sns.set_theme(style="whitegrid", context="talk")
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    PER_CONTROL_DIR.mkdir(parents=True, exist_ok=True)
    MEAN_BARS_DIR.mkdir(parents=True, exist_ok=True)

    frames = {control: load_control_frame(control) for control in CONTROL_FILES}
    for control, df in frames.items():
        if not df.empty:
            save_per_control_figure(control, df)
            save_control_mean_bars(control, df)
            for metric, label in METRICS:
                save_single_metric_control_figure(control, df, metric, label)

    for metric, label in METRICS:
        save_per_metric_figure(metric, label, frames)

    save_coverage_report(frames)
    print(f"saved_plots={OUT_DIR}")


if __name__ == "__main__":
    main()