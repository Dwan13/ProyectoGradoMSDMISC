#!/usr/bin/env python3
"""Generate full S6 integrated matrix.

S6 integrates quality + security by adding security_mode (normal/attack)
on top of the full S2 control/variant/VUs matrix.
"""

from __future__ import annotations

import argparse
import random
from datetime import date, timedelta
from pathlib import Path
from typing import Dict, List

import pandas as pd

BASE_VARIANTS: Dict[str, List[str]] = {
    "C1": ["baseline", "istio", "kong"],
    "C2": ["baseline", "istio-mtls", "linkerd-mtls"],
    "C3": ["baseline", "basic", "strict"],
    "C4": ["baseline", "moderate", "strict"],
}

DEFAULT_VUS = [1, 5, 10, 20]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate S6 integrated randomized blocked matrix.")
    parser.add_argument("--replicates", type=int, default=4, help="Replicates per cell (default: 4).")
    parser.add_argument("--seed", type=int, default=20260513, help="Global random seed (default: 20260513).")
    parser.add_argument("--campaign-id", default="s6_integrated_dual_n4", help="Campaign id label for output rows.")
    parser.add_argument("--start-date", default=str(date.today()), help="Start date for block labels (YYYY-MM-DD).")
    parser.add_argument("--warmup-seconds", type=int, default=30, help="Warmup seconds per row.")
    parser.add_argument("--cooldown-seconds", type=int, default=15, help="Cooldown seconds per row.")
    parser.add_argument("--duration-seconds", type=int, default=60, help="k6 duration seconds per row.")
    parser.add_argument("--security-modes", default="normal,attack", help="Comma-separated security modes.")
    parser.add_argument("--k6-script", default="RealisticServices/k6/realistic-flow.js", help="k6 script path used in each row.")
    parser.add_argument(
        "--output",
        default="Testing/results/scaling_tests/design_matrix_s6_integrated_dual_n4_randomized_blocks.csv",
        help="Output CSV path.",
    )
    return parser.parse_args()


def build_rows(args: argparse.Namespace) -> pd.DataFrame:
    start_day = date.fromisoformat(args.start_date)
    security_modes = [s.strip() for s in args.security_modes.split(',') if s.strip()]
    rows = []

    for rep in range(1, args.replicates + 1):
        block_date = start_day + timedelta(days=rep - 1)
        block_day = f"B{rep}_{block_date.isoformat()}"

        block_rows = []
        for control, variants in BASE_VARIANTS.items():
            for variant in variants:
                for vus in DEFAULT_VUS:
                    for sec_mode in security_modes:
                        block_rows.append(
                            {
                                "campaign_id": args.campaign_id,
                                "block_day": block_day,
                                "replicate": rep,
                                "control": control,
                                "variant": variant,
                                "security_mode": sec_mode,
                                "vus": int(vus),
                                "duration_seconds": int(args.duration_seconds),
                                "warmup_seconds": int(args.warmup_seconds),
                                "cooldown_seconds": int(args.cooldown_seconds),
                                "functional_validation": "required",
                                "k6_script": args.k6_script,
                                "random_order": 0,
                            }
                        )

        rng = random.Random(args.seed + rep)
        rng.shuffle(block_rows)
        for i, row in enumerate(block_rows, start=1):
            row["random_order"] = i

        rows.extend(block_rows)

    df = pd.DataFrame(rows)
    return df[
        [
            "campaign_id",
            "block_day",
            "replicate",
            "random_order",
            "control",
            "variant",
            "security_mode",
            "vus",
            "duration_seconds",
            "warmup_seconds",
            "cooldown_seconds",
            "functional_validation",
            "k6_script",
        ]
    ]


def main() -> None:
    args = parse_args()
    df = build_rows(args)

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    df.to_csv(output, index=False)

    cells_per_block = 4 * 3 * 4 * len([s for s in args.security_modes.split(',') if s.strip()])
    print(f"rows={len(df)}")
    print(f"replicates={args.replicates}")
    print(f"cells_per_block={cells_per_block}")
    print(f"output={output.as_posix()}")


if __name__ == "__main__":
    main()
