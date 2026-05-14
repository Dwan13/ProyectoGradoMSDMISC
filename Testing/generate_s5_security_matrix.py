#!/usr/bin/env python3
"""Generate a minimal blocked randomized matrix for S5 security-focused validation.

S5 is intentionally not a full replacement for S2 ANOVA campaigns.
It targets security-defense evidence with a smaller, faster matrix.
"""

from __future__ import annotations

import argparse
import random
from datetime import date, timedelta
from pathlib import Path

import pandas as pd

# Security-focused cell set (26 cells per block):
# - C1: gateway choices at high load (10, 20)
# - C2: mTLS evidence at low/high extremes (1, 20)
# - C3: isolation policies at low/high extremes (1, 20)
# - C4: anti-abuse at medium/high load (5, 20)
CELL_DEFS = [
    ("C1", "baseline", 10), ("C1", "baseline", 20),
    ("C1", "istio", 10), ("C1", "istio", 20),
    ("C1", "kong", 10), ("C1", "kong", 20),

    ("C2", "baseline", 1), ("C2", "baseline", 20),
    ("C2", "istio-mtls", 1), ("C2", "istio-mtls", 20),
    ("C2", "linkerd-mtls", 1), ("C2", "linkerd-mtls", 20),

    ("C3", "baseline", 1), ("C3", "baseline", 20),
    ("C3", "basic", 1), ("C3", "basic", 20),
    ("C3", "moderate", 1), ("C3", "moderate", 20),
    ("C3", "strict", 1), ("C3", "strict", 20),

    ("C4", "baseline", 5), ("C4", "baseline", 20),
    ("C4", "moderate", 5), ("C4", "moderate", 20),
    ("C4", "strict", 5), ("C4", "strict", 20),
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate S5 security-focused randomized blocked matrix.")
    parser.add_argument("--replicates", type=int, default=3, help="Replicates per cell (default: 3).")
    parser.add_argument("--seed", type=int, default=20260513, help="Global random seed (default: 20260513).")
    parser.add_argument("--campaign-id", default="s5_security_focus_n3", help="Campaign id label for output rows.")
    parser.add_argument("--start-date", default=str(date.today()), help="Start date for block labels (YYYY-MM-DD).")
    parser.add_argument("--warmup-seconds", type=int, default=30, help="Warmup seconds per row.")
    parser.add_argument("--cooldown-seconds", type=int, default=15, help="Cooldown seconds per row.")
    parser.add_argument(
        "--output",
        default="Testing/results/scaling_tests/design_matrix_s5_security_minimal_n3_randomized_blocks.csv",
        help="Output CSV path.",
    )
    return parser.parse_args()


def build_rows(args: argparse.Namespace) -> pd.DataFrame:
    start_day = date.fromisoformat(args.start_date)
    rows = []

    for rep in range(1, args.replicates + 1):
        block_date = start_day + timedelta(days=rep - 1)
        block_day = f"B{rep}_{block_date.isoformat()}"

        block_rows = []
        for control, variant, vus in CELL_DEFS:
            block_rows.append(
                {
                    "campaign_id": args.campaign_id,
                    "block_day": block_day,
                    "replicate": rep,
                    "control": control,
                    "variant": variant,
                    "vus": int(vus),
                    "warmup_seconds": int(args.warmup_seconds),
                    "cooldown_seconds": int(args.cooldown_seconds),
                    "functional_validation": "required",
                    "security_focus": "yes",
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
            "vus",
            "warmup_seconds",
            "cooldown_seconds",
            "functional_validation",
            "security_focus",
        ]
    ]


def main() -> None:
    args = parse_args()
    df = build_rows(args)

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    df.to_csv(output, index=False)

    cells_per_block = len(CELL_DEFS)
    print(f"rows={len(df)}")
    print(f"replicates={args.replicates}")
    print(f"cells_per_block={cells_per_block}")
    print(f"output={output.as_posix()}")


if __name__ == "__main__":
    main()
