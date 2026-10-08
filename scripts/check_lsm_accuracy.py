#!/usr/bin/env python3
"""Native, fixed-seed LSM accuracy acceptance for shoals#152.

Same-path fitting and valuation has upward look-ahead bias. Replicate standard
error measures sampling variation, not that bias or basis/exercise-grid error.
Require both an independent absolute accuracy envelope and 4 SE + 0.08.
Run separately from evaluator tests: eight 4000-path fits per configuration are
cheap natively but exceed a practical evaluator budget. No compiler means FAIL.
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
import shutil
import statistics
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "manual-gates/lsm_accuracy.ch"
SEEDS = [0, 1, 2, 21, 31, 37, 41, 59]
ROOT_NAMES = {
    f"{case}_{field}"
    for case in ("atm", "itm")
    for field in ("prices", "tree_coarse", "tree_fine")
}


def evaluate_output(output: str) -> dict:
    """Fail closed on missing, duplicated, nonfinite, or truncated measurements."""
    values = {}
    for line in output.splitlines():
        name, separator, raw = line.partition(" = ")
        if separator and name in ROOT_NAMES:
            if name in values:
                raise ValueError(f"duplicate native root: {name}")
            values[name] = json.loads(raw)
    if values.keys() != ROOT_NAMES:
        raise ValueError(f"missing native roots: {sorted(ROOT_NAMES - values.keys())}")
    measurements = {}
    failures = []
    for case, absolute_limit, refinement_limit in (("atm", 0.20, 0.01), ("itm", 0.25, 0.03)):
        prices = values[f"{case}_prices"]
        coarse = values[f"{case}_tree_coarse"]
        fine = values[f"{case}_tree_fine"]
        if not isinstance(prices, list) or len(prices) != len(SEEDS):
            raise ValueError(f"{case}: require all eight fixed-seed prices")
        if not all(type(x) in (int, float) and math.isfinite(x) for x in [*prices, coarse, fine]):
            raise ValueError(f"{case}: measurements must be finite numbers")
        average = statistics.mean(prices)
        se = statistics.stdev(prices) / math.sqrt(len(prices))
        error = abs(average - fine)
        refinement = abs(fine - coarse)
        sampling_limit = 4 * se + 0.08
        if not refinement < refinement_limit:
            failures.append(f"{case}: tree refinement {refinement} >= {refinement_limit}")
        if not error < absolute_limit:
            failures.append(f"{case}: absolute error {error} >= {absolute_limit}")
        if not error <= sampling_limit:
            failures.append(f"{case}: error {error} > 4 SE + 0.08 ({sampling_limit})")
        measurements[case] = {
            "prices": prices, "mean": average, "replicate_se": se,
            "tree_512": coarse, "tree_1024": fine, "refinement": refinement,
            "absolute_error": error, "absolute_limit": absolute_limit,
            "sampling_limit": sampling_limit,
        }
    return {
        "schema": "shoals.lsm-accuracy/1", "seeds": SEEDS,
        "paths": 4000, "dates": 50, "measurements": measurements,
        "failures": failures, "verdict": "fail" if failures else "pass",
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--chelis", default=shutil.which("chelis"))
    args = parser.parse_args()
    if not args.chelis:
        parser.exit(1, "FAIL: pinned Chelis compiler unavailable\n")
    try:
        with tempfile.TemporaryDirectory(prefix="shoals-lsm-accuracy-") as output:
            start = time.monotonic()
            subprocess.run(
                [args.chelis, "build", str(FIXTURE), "--target", "c", "--output", output],
                cwd=ROOT, check=True, capture_output=True, text=True, timeout=600,
            )
            build_seconds = time.monotonic() - start
            start = time.monotonic()
            result = subprocess.run(
                [str(Path(output) / FIXTURE.stem)], cwd=ROOT, check=True,
                capture_output=True, text=True, timeout=180,
            )
            run_seconds = time.monotonic() - start
            report = evaluate_output(result.stdout)
            report["seconds"] = {"build": round(build_seconds, 2), "run": round(run_seconds, 2)}
            print(json.dumps(report, indent=2))
            return 0 if report["verdict"] == "pass" else 1
    except (OSError, ValueError, subprocess.SubprocessError) as exc:
        print(f"FAIL: native LSM accuracy oracle: {exc}")
        if isinstance(exc, subprocess.CalledProcessError):
            print(exc.stderr[-4000:] if exc.stderr else "")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
