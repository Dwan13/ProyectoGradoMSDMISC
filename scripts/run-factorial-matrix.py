#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import importlib.util
import sys
import time
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RFC_PATH = ROOT / "scripts" / "run-factorial-campaign.py"


def load_rfc_module():
    spec = importlib.util.spec_from_file_location("run_factorial_campaign", RFC_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load module from {RFC_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--matrix", required=True, help="CSV con order,control,variant,vus,replica")
    ap.add_argument("--duration", type=int, default=60)
    ap.add_argument("--warmup", type=int, default=15)
    ap.add_argument("--profile", choices=["crud"], default="crud")
    ap.add_argument("--out-dir", default=None)
    ap.add_argument("--limit", type=int, default=None)
    ap.add_argument("--stop-on-scenario-error", action="store_true", default=True)
    ap.add_argument("--no-stop-on-scenario-error", dest="stop_on_scenario_error", action="store_false")
    args = ap.parse_args()

    rfc = load_rfc_module()
    matrix_path = Path(args.matrix)
    if not matrix_path.exists():
        raise FileNotFoundError(matrix_path)

    out_dir = Path(args.out_dir) if args.out_dir else (
        ROOT / "Testing" / "results" / "factorial_campaign" / f"missing_overhead_run_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
    )
    out_dir.mkdir(parents=True, exist_ok=True)
    csv_path = out_dir / "results_factorial.csv"

    cols = [
        "run_id", "started_at", "profile", "control", "variant", "vus", "replica",
        "avg_ms", "p95_ms", "err_pct", "rps", "cpu_mcores", "mem_mib",
        "checks_pct", "iterations",
        "sqli_attempts_total", "sqli_blocked_total", "sqli_leaked_total",
        "sqli_other_total", "sqli_mitigation_rate",
        "credstuff_attempts_total", "credstuff_ratelimited_total",
        "credstuff_unauthorized_total", "credstuff_success_total",
        "credstuff_mitigation_rate",
        "duration_s", "status", "error",
    ]

    with matrix_path.open(newline="") as f:
        rows = list(csv.DictReader(f))
    if args.limit is not None:
        rows = rows[:args.limit]

    rfc.log(f"Matrix rows: {len(rows)}")
    rfc.log(f"Output: {csv_path}")

    with csv_path.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=cols)
        w.writeheader()

        last_scn = None
        last_env = None

        for idx, item in enumerate(rows, 1):
            control = item["control"]
            variant = item["variant"]
            vus = int(item["vus"])
            replica = int(item["replica"])
            run_id = f"{args.profile}_{control}_{variant}_vus{vus}_r{replica}"
            rfc.log(f"[{idx:3d}/{len(rows)}] {run_id}")

            row = {
                "run_id": run_id,
                "started_at": datetime.now().isoformat(timespec="seconds"),
                "profile": args.profile,
                "control": control,
                "variant": variant,
                "vus": vus,
                "replica": replica,
                "avg_ms": "", "p95_ms": "", "err_pct": "", "rps": "",
                "cpu_mcores": "", "mem_mib": "", "checks_pct": "", "iterations": "",
                "sqli_attempts_total": "", "sqli_blocked_total": "", "sqli_leaked_total": "",
                "sqli_other_total": "", "sqli_mitigation_rate": "",
                "credstuff_attempts_total": "", "credstuff_ratelimited_total": "",
                "credstuff_unauthorized_total": "", "credstuff_success_total": "",
                "credstuff_mitigation_rate": "",
                "duration_s": args.duration, "status": "fail", "error": "",
            }

            try:
                if (control, variant) != last_scn:
                    try:
                        last_env = rfc.apply_scenario(control, variant)
                    except Exception as exc:
                        row["error"] = str(exc)[:300]
                        rfc.log(f"  scenario error: {exc}", "ERROR")
                        w.writerow(row)
                        f.flush()
                        if args.stop_on_scenario_error:
                            rfc.log("Stopping matrix run due to scenario-apply failure", "ERROR")
                            return 2
                        continue
                    last_scn = (control, variant)
                    time.sleep(args.warmup)
                summary = out_dir / f"{run_id}_summary.json"
                extra_env = rfc.build_profile_env(args.profile, control, variant, vus)
                if extra_env:
                    rfc.log(f"  pacing env: {extra_env}", "DEBUG")
                ok, stdout, err = rfc.run_k6(last_env, vus, args.duration, summary, rfc.K6_PROFILES[args.profile], extra_env)
                metrics = rfc.parse_k6_summary(summary)
                resources = rfc.collect_resources()
                row.update(metrics)
                row.update(resources)
                row["status"] = "ok" if ok and metrics.get("checks_pct", 0) >= 80 else "fail"
                if not ok:
                    row["error"] = err.replace("\n", " | ")[:300]
            except Exception as exc:
                row["error"] = str(exc)[:300]
                rfc.log(f"  ERROR: {exc}", "ERROR")

            w.writerow(row)
            f.flush()
            rfc.log(
                f"  {row['status']}  avg={row['avg_ms']}  p95={row['p95_ms']}  rps={row['rps']}  cpu={row['cpu_mcores']}  mem={row['mem_mib']}  err%={row['err_pct']}"
            )

    rfc.log(f"Matrix campaign finished: {csv_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())