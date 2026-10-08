#!/usr/bin/env python3
"""Run bounded pricing regressions and require their false controls to fail."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SAMPLES = 25
SEEDS = (0, 1, 2)
# A 25-sample PDE run exceeded 1800s under shared host load while using
# about 840s of CPU. Allow execution headroom without changing its oracle.
RUN_TIMEOUT_SECONDS = 3600
SMOKE_TIMEOUT_SECONDS = 60
SMOKE_PROPERTIES = {
    "canonlsm": ("lsm_expiry_intrinsic",),
    "pde": ("spread_expiry_matches_intrinsic",),
}
FAMILIES = {
    "hestonlewis": (
        "heston_lewis_carr_madan_agreement",
        "heston_lewis_put_call_parity",
        "heston_lewis_call_decreases_in_strike",
    ),
    "canonlsm": (
        "lsm_translated_quadratic_recovery",
        "lsm_observation_order_invariance",
        "lsm_degenerate_constant_fit",
        "lsm_put_payoff_bounds",
        "lsm_expiry_intrinsic",
    ),
    "pde": (
        "spread_expiry_matches_intrinsic",
        "spread_exchange_matches_margrabe",
        "spread_bounded_input_price_bounds",
    ),
    "jumpmoments": (
        "merton_zero_intensity",
        "kou_zero_horizon",
        "merton_matches_poisson_moment",
        "kou_matches_poisson_moment",
    ),
}


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def integer(value: object) -> bool:
    return type(value) is int


def validate_run(stdout: str, returncode: int, family: str, seed: int,
                 *, property_names: tuple[str, ...] | None = None) -> None:
    """Fail closed on missing, skipped, vacuous, or misclassified records."""
    positives = set(FAMILIES[family] if property_names is None else property_names)
    require(bool(positives) and positives <= set(FAMILIES[family]), "invalid property selection")
    controls = {name + "_corrupted" for name in positives}
    expected = positives | controls
    seen: set[str] = set()
    summaries = []
    for line in stdout.splitlines():
        if not line.strip():
            continue
        row = json.loads(line)
        require(isinstance(row, dict), "record must be an object")
        if row.get("kind") == "summary":
            summaries.append(row)
            continue
        require(row.get("kind") == "property", "unexpected record kind")
        name = row.get("name")
        require(isinstance(name, str) and name in expected, "unexpected property")
        require(name not in seen, f"duplicate property: {name}")
        seen.add(name)
        require(row.get("proof_tier") == "fuzz", f"wrong method: {name}")
        require(integer(row.get("seed")) and row["seed"] == seed, f"wrong seed: {name}")
        source = row.get("source")
        require(isinstance(source, dict)
                and source.get("file") == f"properties/{family}.ch",
                f"wrong source: {name}")
        accepted = row.get("accepted_samples")
        attempted = row.get("attempted_samples")
        require(integer(accepted) and integer(attempted)
                and 0 < accepted <= attempted, f"invalid sample counts: {name}")
        if name in positives:
            require(row.get("status") == "passed", f"regression failed: {name}")
            require(accepted == SAMPLES, f"insufficient accepted samples: {name}")
            require(row.get("counterexample") is None, f"passing witness: {name}")
        else:
            require(row.get("status") == "failed", f"false control survived: {name}")
            require(isinstance(row.get("counterexample"), dict)
                    and bool(row["counterexample"]), f"missing witness: {name}")
    require(seen == expected, "missing properties")
    require(len(summaries) == 1, "expected exactly one summary")
    summary = summaries[0]
    for key, value in {"total": len(expected), "passed": len(positives),
                       "failed": len(controls), "errors": 0, "unsupported": 0}.items():
        require(integer(summary.get(key)) and summary[key] == value,
                f"wrong summary {key}")
    # Every invocation contains refuted controls, so success is not exit zero.
    require(returncode == 1, f"unexpected compiler exit: {returncode}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--smoke", action="store_true",
                        help="only LSM/PDE expiry pairs at seed 0, with a 60s ceiling per process")
    args = parser.parse_args()
    families = SMOKE_PROPERTIES if args.smoke else FAMILIES
    seeds = (0,) if args.smoke else SEEDS
    timeout = SMOKE_TIMEOUT_SECONDS if args.smoke else RUN_TIMEOUT_SECONDS
    output_dir = ROOT / "target/pricing-fix-properties" / ("smoke" if args.smoke else "full")
    output_dir.mkdir(parents=True, exist_ok=True)
    for family, names in families.items():
        for seed in seeds:
            prefix = output_dir / f"{family}-seed{seed}"
            command = ["chelis", "prove", f"properties/{family}.ch", "--tier", "fuzz-only",
                       "--samples", str(SAMPLES), "--seed", str(seed), "--json"]
            if args.smoke:
                # --only matches both the positive and its _corrupted twin.
                command += ["--only", names[0]]
            print(f"Running {family}, seed {seed}, {SAMPLES} accepted samples", flush=True)
            try:
                result = subprocess.run(command, cwd=ROOT, capture_output=True,
                                        text=True, timeout=timeout)
                prefix.with_suffix(".jsonl").write_text(result.stdout)
                prefix.with_suffix(".stderr").write_text(result.stderr)
                validate_run(result.stdout, result.returncode, family, seed, property_names=names)
            except (ValueError, subprocess.TimeoutExpired, OSError) as exc:
                print(f"FAIL: {family}, seed {seed}: {exc}", file=sys.stderr)
                return 1
            print(f"PASS: {len(names)} bounded regressions; "
                  f"{len(names)} false controls refuted", flush=True)
    scope = "expiry smoke at seed 0" if args.smoke else "all bounded pricing regressions at three seeds"
    print(f"PASS: {scope} (fuzz evidence)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
