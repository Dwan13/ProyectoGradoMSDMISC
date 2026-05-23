#!/usr/bin/env python3
from pathlib import Path

import matplotlib.pyplot as plt
import pandas as pd
import seaborn as sns
from matplotlib.lines import Line2D


INPUT_CSV = Path("Testing/results/factorial_campaign/anova_overhead_matrix_n4_20260523.csv")
OUTPUT_DIR = Path("Testing/results/factorial_campaign/overhead_plots_20260523")

METRICS = {
    "avg_ms": "Average Latency (ms)",
    "p95_ms": "P95 Latency (ms)",
    "err_pct": "Error Rate (%)",
    "rps": "Throughput (req/s)",
    "cpu_mcores": "CPU (mCores)",
    "mem_mib": "Memory (MiB)",
}

CONTROL_VARIANTS = {
    "C1": ["baseline", "istio", "kong"],
    "C2": ["baseline", "istio_mtls", "linkerd_mtls"],
    "C3": ["baseline", "basic", "strict"],
    "C4": ["baseline", "moderate", "strict"],
}

VARIANT_COLORS = {
    "baseline": "#4C72B0",
    "istio": "#DD8452",
    "kong": "#55A868",
    "istio_mtls": "#DD8452",
    "linkerd_mtls": "#55A868",
    "basic": "#DD8452",
    "moderate": "#DD8452",
    "strict": "#55A868",
}


def prepare_data() -> pd.DataFrame:
    df = pd.read_csv(INPUT_CSV)
    df["vus"] = df["vus"].astype(int)
    df["replica"] = df["replica"].astype(int)
    return df.sort_values(["control", "variant", "vus", "replica"])


def build_variant_legend(control: str) -> list:
    legend_items = []
    for variant in CONTROL_VARIANTS[control]:
        legend_items.append(
            Line2D(
                [0],
                [0],
                color=VARIANT_COLORS[variant],
                marker="o",
                linewidth=2,
                markersize=7,
                label=f"{variant} = {VARIANT_COLORS[variant]}",
            )
        )
    return legend_items


def plot_metric_by_control(df: pd.DataFrame, metric_key: str, metric_label: str) -> None:
    fig, axes = plt.subplots(2, 2, figsize=(16, 10), sharex=False)
    fig.suptitle(
        f"Overhead Experiment 2026-05-23: {metric_label} by Control",
        fontsize=17,
        fontweight="bold",
        y=0.98,
    )

    for ax, control in zip(axes.flatten(), sorted(CONTROL_VARIANTS)):
        control_df = df[df["control"] == control].copy()
        summary = (
            control_df.groupby(["variant", "vus"], as_index=False)[metric_key]
            .mean()
            .sort_values(["variant", "vus"])
        )

        for variant in CONTROL_VARIANTS[control]:
            variant_df = control_df[control_df["variant"] == variant].copy()
            variant_summary = summary[summary["variant"] == variant]

            ax.scatter(
                variant_df["vus"],
                variant_df[metric_key],
                color=VARIANT_COLORS[variant],
                alpha=0.75,
                marker="o" if variant == "baseline" else ("x" if VARIANT_COLORS[variant] == "#DD8452" else "s"),
                s=38,
            )
            ax.plot(
                variant_summary["vus"],
                variant_summary[metric_key],
                color=VARIANT_COLORS[variant],
                linewidth=1.8,
            )

        vus_values = sorted(control_df["vus"].unique())
        ax.set_title(control, fontweight="bold")
        ax.set_xlabel("VUs")
        ax.set_ylabel(metric_label)
        ax.set_xticks(vus_values)
        ax.grid(True, alpha=0.25, linestyle="--")
        ax.legend(handles=build_variant_legend(control), title="Color mapping", loc="best", fontsize=9)

    plt.tight_layout(rect=[0, 0, 1, 0.95])
    plt.savefig(OUTPUT_DIR / f"metric_{metric_key}_by_control.png", dpi=300, bbox_inches="tight")
    plt.close(fig)


def plot_control_dashboard(df: pd.DataFrame, control: str) -> None:
    control_df = df[df["control"] == control].copy()
    fig, axes = plt.subplots(2, 3, figsize=(18, 10), sharex=False)
    fig.suptitle(
        f"{control} Overhead by Metric",
        fontsize=18,
        fontweight="bold",
        y=0.98,
    )

    for ax, (metric_key, metric_label) in zip(axes.flatten(), METRICS.items()):
        summary = (
            control_df.groupby(["variant", "vus"], as_index=False)[metric_key]
            .mean()
            .sort_values(["variant", "vus"])
        )

        for variant in CONTROL_VARIANTS[control]:
            variant_df = control_df[control_df["variant"] == variant].copy()
            variant_summary = summary[summary["variant"] == variant]

            ax.scatter(
                variant_df["vus"],
                variant_df[metric_key],
                color=VARIANT_COLORS[variant],
                alpha=0.75,
                marker="o" if variant == "baseline" else ("x" if VARIANT_COLORS[variant] == "#DD8452" else "s"),
                s=34,
            )
            ax.plot(
                variant_summary["vus"],
                variant_summary[metric_key],
                color=VARIANT_COLORS[variant],
                linewidth=1.8,
            )

        ax.set_title(metric_label, fontsize=12, fontweight="bold")
        ax.set_xlabel("VUs")
        ax.set_ylabel(metric_label)
        ax.set_xticks(sorted(control_df["vus"].unique()))
        ax.grid(True, alpha=0.25, linestyle="--")

    fig.legend(
        handles=build_variant_legend(control),
        title=f"{control} color mapping",
        loc="lower center",
        ncol=3,
        bbox_to_anchor=(0.5, -0.01),
        frameon=True,
    )
    plt.tight_layout(rect=[0, 0.05, 1, 0.95])
    plt.savefig(OUTPUT_DIR / f"{control.lower()}_overhead_dashboard.png", dpi=300, bbox_inches="tight")
    plt.close(fig)


def write_readme(df: pd.DataFrame) -> None:
    lines = [
        "# Overhead Plots - 2026-05-23",
        "",
        f"Input dataset: {INPUT_CSV}",
        f"Rows: {len(df)}",
        f"Controls: {', '.join(sorted(df['control'].unique()))}",
        f"VUs: {', '.join(map(str, sorted(df['vus'].unique())))}",
        f"Replicas per cell: {df.groupby(['control', 'variant', 'vus']).size().iloc[0]}",
        "",
        "Color mapping by control:",
        "- C1: baseline blue, istio orange, kong green",
        "- C2: baseline blue, istio_mtls orange, linkerd_mtls green",
        "- C3: baseline blue, basic orange, strict green",
        "- C4: baseline blue, moderate orange, strict green",
        "",
        "Generated files:",
    ]
    for path in sorted(OUTPUT_DIR.glob("*.png")):
        lines.append(f"- {path.name}")
    (OUTPUT_DIR / "README.txt").write_text("\n".join(lines) + "\n")


def main() -> None:
    sns.set_theme(style="whitegrid")
    plt.rcParams.update(
        {
            "figure.dpi": 200,
            "savefig.dpi": 300,
            "axes.titlesize": 13,
            "axes.labelsize": 12,
            "legend.fontsize": 9,
        }
    )
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    df = prepare_data()

    for metric_key, metric_label in METRICS.items():
        plot_metric_by_control(df, metric_key, metric_label)

    for control in sorted(CONTROL_VARIANTS):
        plot_control_dashboard(df, control)

    write_readme(df)
    print(f"Generated plots in {OUTPUT_DIR}")


if __name__ == "__main__":
    main()