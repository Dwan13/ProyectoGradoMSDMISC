#!/usr/bin/env python3
"""Generate an academically robust randomized blocked matrix for the base S2 battery.

Design:
- Full factorial base controls: C1-C4
- Variants supported in postgres-real runtime
- VUs: 1, 5, 10, 20
- Replicates per cell: configurable (default 6)
- Randomized order inside each block (replicate)
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
    parser = argparse.ArgumentParser(description="Generate randomized blocked matrix for academic S2 base campaign.")
    parser.add_argument("--replicates", type=int, default=6, help="Replicates per cell (default: 6).")
    parser.add_argument("--seed", type=int, default=20260510, help="Global random seed (default: 20260510).")
    parser.add_argument("--campaign-id", default="s2_academic_base_n6", help="Campaign id label for output rows.")
    parser.add_argument("--start-date", default=str(date.today()), help="Start date for block labels (YYYY-MM-DD).")
    parser.add_argument("--warmup-seconds", type=int, default=30, help="Warmup seconds per row.")
    parser.add_argument("--cooldown-seconds", type=int, default=15, help="Cooldown seconds per row.")
    parser.add_argument(
        "--output",
        default="Testing/results/scaling_tests/design_matrix_academic_base_n6_randomized_blocks.csv",
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
        for control, variants in BASE_VARIANTS.items():
            for variant in variants:
                for vus in DEFAULT_VUS:
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
        ]
    ]


def main() -> None:
    args = parse_args()
    df = build_rows(args)

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    df.to_csv(output, index=False)

    n_cells = 4 * 3 * 4
    print(f"rows={len(df)}")
    print(f"replicates={args.replicates}")
    print(f"cells_per_block={n_cells}")
    print(f"output={output.as_posix()}")


if __name__ == "__main__":
    main()
