#!/usr/bin/env python3
import csv
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
INPUT_CSV = ROOT / "Testing" / "results" / "all-controls-comparison.csv"
OUTPUT_YAML = Path(__file__).resolve().parent / "k8s" / "06-experiment-comparison-rule.yaml"


def safe(s: str) -> str:
    return str(s).replace('"', "").strip()


def main() -> int:
    if not INPUT_CSV.exists():
        print(f"[WARN] Missing input CSV: {INPUT_CSV}")
        return 1

    grouped = defaultdict(lambda: {"avg": [], "p95": []})
    with INPUT_CSV.open("r", newline="") as f:
        reader = csv.DictReader(f)
        for r in reader:
            try:
                control = safe(r["control"])
                tech = safe(r["scenario"])
                vus = str(int(float(r["vus"])))
                avg_ms = float(r["avg_ms"])
                p95_ms = float(r["p95_ms"])
            except Exception:
                continue
            k = (control, tech, vus)
            grouped[k]["avg"].append(avg_ms)
            grouped[k]["p95"].append(p95_ms)

    if not grouped:
        print("[WARN] No valid rows in comparison CSV")
        return 1

    aggregated = []
    for (control, tech, vus), vals in grouped.items():
        avg = sum(vals["avg"]) / len(vals["avg"])
        p95 = sum(vals["p95"]) / len(vals["p95"])
        aggregated.append((control, tech, vus, avg, p95))

    aggregated.sort(key=lambda x: (x[0], x[1], int(x[2])))

    # Compute overhead vs baseline per (control, vus)
    baseline = {}
    for control, tech, vus, avg, p95 in aggregated:
        if tech == "baseline":
            baseline[(control, vus)] = {"avg": avg, "p95": p95}

    lines = []
    lines.append("apiVersion: monitoring.coreos.com/v1")
    lines.append("kind: PrometheusRule")
    lines.append("metadata:")
    lines.append("  name: mubench-experiment-comparison")
    lines.append("  namespace: observability")
    lines.append("  labels:")
    lines.append("    release: kube-prom-stack")
    lines.append("spec:")
    lines.append("  groups:")
    lines.append("    - name: mubench-experiment-comparison.rules")
    lines.append("      rules:")

    for control, tech, vus, avg, p95 in aggregated:
        lines.append("        - record: mubench_experiment_avg_ms")
        lines.append(f"          expr: \"vector({avg:.6f})\"")
        lines.append("          labels:")
        lines.append(f"            control: \"{control}\"")
        lines.append(f"            technology: \"{tech}\"")
        lines.append(f"            vus: \"{vus}\"")

        lines.append("        - record: mubench_experiment_p95_ms")
        lines.append(f"          expr: \"vector({p95:.6f})\"")
        lines.append("          labels:")
        lines.append(f"            control: \"{control}\"")
        lines.append(f"            technology: \"{tech}\"")
        lines.append(f"            vus: \"{vus}\"")

        b = baseline.get((control, vus))
        if b and b["avg"] > 0:
            overhead_avg = ((avg - b["avg"]) / b["avg"]) * 100.0
            lines.append("        - record: mubench_experiment_overhead_avg_pct")
            lines.append(f"          expr: \"vector({overhead_avg:.6f})\"")
            lines.append("          labels:")
            lines.append(f"            control: \"{control}\"")
            lines.append(f"            technology: \"{tech}\"")
            lines.append(f"            vus: \"{vus}\"")

        if b and b["p95"] > 0:
            overhead_p95 = ((p95 - b["p95"]) / b["p95"]) * 100.0
            lines.append("        - record: mubench_experiment_overhead_p95_pct")
            lines.append(f"          expr: \"vector({overhead_p95:.6f})\"")
            lines.append("          labels:")
            lines.append(f"            control: \"{control}\"")
            lines.append(f"            technology: \"{tech}\"")
            lines.append(f"            vus: \"{vus}\"")

    OUTPUT_YAML.write_text("\n".join(lines) + "\n")
    print(f"[INFO] Generated: {OUTPUT_YAML}")
    print(f"[INFO] Rows: {len(aggregated)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
