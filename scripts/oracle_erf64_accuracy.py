#!/usr/bin/env python3
"""Measure `erf64`/`n_cdf64` against a high-precision reference. shoals#61.

The published accuracy figures were transcribed prose in nine files, and two
consecutive red-team rounds each found a different instance of one defect: a
number the measurement does not support. First a sample maximum presented as a
maximum (2.7e-16), then a floor sitting ABOVE every observable value
(3.45e-16), which came from comparing decimal spellings on both sides.

So the figures are output now, not prose. This script computes them; the docs
quote it. A wrong method fails here instead of shipping in nine files.

MEASURE IN BINARY. The error is

    mpf(f64_result) - erf(mpf(exact_f64_input))

at extended precision. Two ways to get this wrong, both of which produced a
published number:

  * comparing `mpf(repr(result))` against `mpf(decimal_input)` measures a
    decimal round trip, worth ~0.04 ulp near the argmax;
  * rounding the reference to a double first quantises every error to a
    multiple of an ulp.

FLOOR, NOT MAXIMUM. The error is jagged at ulp scale, so any grid reports only
the worst point it lands on. A refinement finer than an earlier sweep but
differently spaced misses the argmax entirely. The documented figure is a floor
and this script enforces exactly that: the docs may not claim MORE than was
measured.

Usage:
    oracle_erf64_accuracy.py            # measure and check the documented floors
    oracle_erf64_accuracy.py --json     # machine-readable summary
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

try:
    import mpmath as mp
except ImportError:  # pragma: no cover - environment guard
    print("SKIP: oracle_erf64_accuracy -- mpmath not installed", file=sys.stderr)
    sys.exit(0)

REPO_ROOT = Path(__file__).resolve().parent.parent
CHELIS = os.environ.get("CHELIS_BIN") or "chelis"
# Generated inside the package so `chelis eval` resolves Shoals.Pricing.
GEN = REPO_ROOT / ".gate-tmp" / "erf64accuracy.ch"

# The figures docs/CHELIS_SURFACE.md, docs/UPSTREAM_BUGS.md and src/pricing.ch
# publish. Floors: measurement must reach at least these, and they must not
# exceed it.
# A FLOOR ROUNDS DOWN. The first n_cdf64 figure written here was 1.9496e-16,
# the measured 1.949591e-16 rounded to four places -- and rounding a floor UP
# puts it above the observation it claims to sit under. This script caught
# that on its first run, which is the whole argument for having it.
DOCUMENTED = {
    "erf64": 3.3675e-16,
    "n_cdf64": 1.9495e-16,
}
ULP1 = mp.mpf(2) ** -52


def probe_points() -> list[float]:
    """Where to look. The argmax neighbourhood plus broad coverage.

    The dense window is centred on x = 0.507001975 because an exhaustive scan
    of +/-150k consecutive doubles found the local maximum there and nothing
    else in that window passes 3.40e-16. Broad coverage exists to notice a
    kernel change that moves the argmax somewhere else entirely.
    """
    pts: set[float] = set()
    argmax = 0.507001975
    step = 2.0**-53
    for i in range(-600, 601):  # consecutive doubles around the argmax
        pts.add(argmax + i * step)
    lo, hi, n = 0.0, 6.5, 900
    for i in range(n + 1):
        pts.add(lo + (hi - lo) * i / n)
    for boundary in (0.5, 4.0, 6.0):  # the three Cody ranges
        for k in range(-20, 21):
            pts.add(boundary + k * 2.0**-45)
    # Negatives are not optional. `erf` is odd so its error magnitude mirrors,
    # but `n_cdf64` is not: `0.5 * (1 - erf64(-x/sqrt2))` rounds differently on
    # the two sides, and its worst observed point is at x = -0.717. A grid that
    # only swept x >= 0 reported a documented floor as overstated when the
    # grid, not the figure, was what was wrong.
    pts |= {-x for x in tuple(pts)}
    pts.add(-0.7170090691949448)
    pts.add(0.7700537662469848)
    return sorted(pts)


# `chelis eval` overflows its stack on a single list literal of a few thousand
# elements (rc=-6, "thread 'main' has overflowed its stack"), so the sweep is
# batched. Not a kernel problem and not worked around silently: it is a real
# evaluator limit on literal size, hit at ~4400 elements on this pin.
BATCH = 800


def evaluate(points: list[float], call: str) -> list[float]:
    out: list[float] = []
    for i in range(0, len(points), BATCH):
        out.extend(_evaluate_batch(points[i : i + BATCH], call))
    return out


def _evaluate_batch(points: list[float], call: str) -> list[float]:
    GEN.parent.mkdir(parents=True, exist_ok=True)
    lits = ", ".join(f"{call}(cast({x!r}, f64))" for x in points)
    GEN.write_text(
        "module Shoals.Gate_Tmp.Erf64Accuracy\n"
        f"import Shoals.Pricing ({call})\n"
        f"probe = [{lits}]\n"
    )
    subprocess.run([CHELIS, "fmt", "--inplace", str(GEN)], cwd=REPO_ROOT,
                   capture_output=True, check=False)
    done = subprocess.run(
        [CHELIS, "eval", "--file", str(GEN), "--json", "--timeout", "900"],
        cwd=REPO_ROOT, capture_output=True, text=True, check=False,
    )
    if done.returncode != 0 or not done.stdout.strip().startswith("{"):
        raise SystemExit(
            f"FAIL: {call} probe did not evaluate (rc={done.returncode})\n"
            f"stderr: {done.stderr[:700]}\nstdout: {done.stdout[:300]}"
        )
    doc = json.loads(done.stdout)
    return [e["value"] for e in doc["roots"][0]["value"]["value"]]


def worst(points: list[float], values: list[float], fn) -> tuple[mp.mpf, float]:
    top, at = mp.mpf(0), points[0]
    for x, got in zip(points, values):
        if got is None:  # NaN on the wire
            continue
        err = abs(mp.mpf(got) - fn(mp.mpf(x)))
        if err > top:
            top, at = err, x
    return top, at


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()
    mp.mp.dps = 60

    points = probe_points()
    results = {}
    for name, fn in (
        ("erf64", mp.erf),
        ("n_cdf64", lambda x: (1 + mp.erf(x / mp.sqrt(2))) / 2),
    ):
        values = evaluate(points, name)
        err, at = worst(points, values, fn)
        results[name] = {
            "worst_abs": float(err),
            "worst_ulp_of_one": float(err / ULP1),
            "at": at,
            "points": len(points),
            "documented_floor": DOCUMENTED[name],
            "documented_is_a_floor": DOCUMENTED[name] <= float(err),
        }

    if args.json:
        print(json.dumps(results, indent=2))

    overstated = [n for n, r in results.items() if not r["documented_is_a_floor"]]
    for name, r in results.items():
        print(
            f"{name:9s} worst observed {r['worst_abs']:.6e} "
            f"({r['worst_ulp_of_one']:.4f} ulp of 1.0) at x = {r['at']!r} "
            f"over {r['points']} points; documented floor {r['documented_floor']:.6e}"
        )
    if overstated:
        print()
        for name in overstated:
            r = results[name]
            print(
                f"FAIL: {name}'s documented floor {r['documented_floor']:.6e} EXCEEDS "
                f"the worst value measured, {r['worst_abs']:.6e}. A floor above "
                f"every observation is not a floor."
            )
        return 1
    print("\nPASS: oracle_erf64_accuracy -- every documented figure is a true floor.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    finally:
        GEN.unlink(missing_ok=True)
