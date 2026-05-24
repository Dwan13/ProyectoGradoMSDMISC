#!/usr/bin/env python3
import csv
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
INPUT_CSV = ROOT / "Testing" / "results" / "s2_full_matrix_all_metrics_48rows.csv"
OUTPUT_YAML = Path(__file__).resolve().parent / "k8s" / "06-final-thesis-comparison-rule.yaml"

def q(v: str) -> str:
    return str(v).replace('"', '').strip()

def to_float(v):
    try:
        return float(v)
    except Exception:
        return None

def emit_rule(lines, metric_name, value, control, tech, vus):
    if value is None:
        return
    lines.append(f"        - record: {metric_name}")
    lines.append(f"          expr: \"vector({value:.6f})\"")
    lines.append("          labels:")
    lines.append(f"            control: \"{control}\"")
    lines.append(f"            technology: \"{tech}\"")
    lines.append(f"            vus: \"{vus}\"")

def main() -> int:
    if not INPUT_CSV.exists():
        print(f"[ERROR] Missing input CSV: {INPUT_CSV}")
        return 1

    rows = []
    with INPUT_CSV.open("r", newline="") as f:
        reader = csv.DictReader(f)
        for r in reader:
            control = q(r.get("control", ""))
            tech = q(r.get("variant", ""))
            vus_raw = r.get("vus", "")
            try:
                vus = str(int(float(vus_raw)))
            except Exception:
                continue

            row = {
                "control": control,
                "technology": tech,
                "vus": vus,
                "avg_ms": to_float(r.get("avg_ms")),
                "p95_ms": to_float(r.get("p95_ms")),
                "err_pct": to_float(r.get("err_pct")),
                "rps": to_float(r.get("rps")),
                "cpu_mcores": to_float(r.get("cpu_mcores")),
                "mem_mib": to_float(r.get("mem_mib")),
            }
            rows.append(row)

    if not rows:
        print("[ERROR] No valid rows parsed")
        return 1

    # Baseline map for overhead metrics (same control + vus)
    baseline = {}
    for r in rows:
        if r["technology"] == "baseline":
            baseline[(r["control"], r["vus"])] = r

    rows.sort(key=lambda x: (x["control"], x["technology"], int(x["vus"])))

    lines = []
    lines.append("apiVersion: monitoring.coreos.com/v1")
    lines.append("kind: PrometheusRule")
    lines.append("metadata:")
    lines.append("  name: mubench-final-thesis-comparison")
    lines.append("  namespace: monitoring")
    lines.append("  labels:")
    lines.append("    app: kube-prometheus-stack")
    lines.append("    app.kubernetes.io/instance: prometheus")
    lines.append("    app.kubernetes.io/managed-by: Helm")
    lines.append("    app.kubernetes.io/part-of: kube-prometheus-stack")
    lines.append("    app.kubernetes.io/version: 84.5.0")
    lines.append("    chart: kube-prometheus-stack-84.5.0")
    lines.append("    heritage: Helm")
    lines.append("    release: prometheus")
    lines.append("spec:")
    lines.append("  groups:")
    lines.append("    - name: mubench-final-thesis-comparison.rules")
    lines.append("      rules:")

    for r in rows:
        c, t, v = r["control"], r["technology"], r["vus"]

        emit_rule(lines, "mubench_final_avg_ms", r["avg_ms"], c, t, v)
        emit_rule(lines, "mubench_final_p95_ms", r["p95_ms"], c, t, v)
        emit_rule(lines, "mubench_final_err_pct", r["err_pct"], c, t, v)
        emit_rule(lines, "mubench_final_rps", r["rps"], c, t, v)
        emit_rule(lines, "mubench_final_cpu_mcores", r["cpu_mcores"], c, t, v)
        emit_rule(lines, "mubench_final_mem_mib", r["mem_mib"], c, t, v)

        b = baseline.get((c, v))
        if b and b.get("avg_ms") and b["avg_ms"] > 0 and r.get("avg_ms") is not None:
            ov = ((r["avg_ms"] - b["avg_ms"]) / b["avg_ms"]) * 100.0
            emit_rule(lines, "mubench_final_overhead_avg_pct", ov, c, t, v)

        if b and b.get("p95_ms") and b["p95_ms"] > 0 and r.get("p95_ms") is not None:
            ov = ((r["p95_ms"] - b["p95_ms"]) / b["p95_ms"]) * 100.0
            emit_rule(lines, "mubench_final_overhead_p95_pct", ov, c, t, v)

    OUTPUT_YAML.write_text("\n".join(lines) + "\n")
    print(f"[INFO] Generated {OUTPUT_YAML}")
    print(f"[INFO] Total rows exported: {len(rows)}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
