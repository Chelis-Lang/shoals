#!/usr/bin/env python3
"""Task 2: compare chelis n_cdf(x) values to scipy's canonical normal CDF.

Input: the chelis test JSON (probe failures carrying `got <value>`), parsed by the
"PROBE x_iii x=<lit>" tag in the message, plus the grid sidecar tsv.

Tolerance derivation (stated, not arbitrary):
  Shoals n_cdf is computed in f32 as 0.5*erfc(-x/sqrt2). The output is a single-precision
  float; its representable spacing (ulp) near values O(1) is 2^-24 ~ 5.96e-8. The chelis
  erfc is itself an f32 routine, so on top of rounding the final result we allow a small
  multiple of ulp for the accumulated rounding of the (scale, erfc, halve) chain.
  We set the pass bound to:
      tol_abs = 8 * 2^-24  ~= 4.77e-7   (8 ulp of an O(1) f32 result)
  This is the correctness bar: chelis n_cdf must equal the true Phi(x) to within a few
  f32 ulp. (scipy ndtr is double precision, taken as ground truth.) A miss beyond this
  would indicate a real algorithmic error in the chelis CDF, not mere rounding.
"""
import json
import math
import re
import sys

from scipy.special import ndtr  # canonical normal CDF (double precision)
from scipy.stats import norm

ULP_F32 = 2.0 ** -24  # ~5.96e-8, spacing of f32 near 1.0
TOL_ABS = 8 * ULP_F32  # ~4.77e-7

MSG_RE = re.compile(r"PROBE (x_\d+) x=([-+0-9.eE]+)\): expected -999, got ([-+0-9.eEnaif]+),")


def main() -> None:
    json_path, grid_path = sys.argv[1], sys.argv[2]

    # grid sidecar: tag -> x
    grid = {}
    with open(grid_path) as f:
        for line in f:
            tag, xs = line.strip().split("\t")
            grid[tag] = float(xs)

    rows = []  # (tag, x, chelis, scipy, abserr)
    with open(json_path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            rec = json.loads(line)
            if "message" not in rec:
                continue
            m = MSG_RE.search(rec["message"])
            if not m:
                continue
            tag = m.group(1)
            x = grid[tag]
            chelis_val = float(m.group(3))
            true_val = float(ndtr(x))
            abserr = abs(chelis_val - true_val)
            rows.append((tag, x, chelis_val, true_val, abserr))

    rows.sort(key=lambda r: r[1])

    print(f"# Task 2: chelis n_cdf vs scipy ndtr  ({len(rows)} grid points)")
    print(f"# tolerance: TOL_ABS = 8*2^-24 = {TOL_ABS:.6e}  (8 ulp of an O(1) f32)")
    print(f"# scipy.special.ndtr is double-precision ground truth; "
          f"cross-checked against scipy.stats.norm.cdf")
    print(f"{'tag':>8} {'x':>8} {'chelis':>16} {'scipy_ndtr':>18} "
          f"{'abserr':>12} {'PASS?':>6}")
    max_abserr = 0.0
    max_at = None
    n_fail = 0
    # sanity: scipy ndtr vs norm.cdf must themselves agree (oracle self-check)
    ndtr_vs_cdf = 0.0
    for tag, x, cv, tv, ae in rows:
        ndtr_vs_cdf = max(ndtr_vs_cdf, abs(tv - float(norm.cdf(x))))
        ok = ae <= TOL_ABS
        if not ok:
            n_fail += 1
        if ae > max_abserr:
            max_abserr = ae
            max_at = (tag, x)
        print(f"{tag:>8} {x:>8.3f} {cv:>16.10g} {tv:>18.12g} "
              f"{ae:>12.3e} {'PASS' if ok else 'FAIL':>6}")

    print()
    print(f"oracle self-check: max |ndtr - norm.cdf| over grid = {ndtr_vs_cdf:.3e} "
          f"(should be ~0, confirms scipy ground truth is consistent)")
    print(f"max abs error chelis-vs-scipy = {max_abserr:.6e} at {max_at}")
    print(f"tolerance                     = {TOL_ABS:.6e}")
    verdict = "PASS" if n_fail == 0 else f"FAIL ({n_fail} points exceed tol)"
    print(f"VERDICT (n_cdf numerical correctness): {verdict}")

    # machine-readable summary line for RESULTS aggregation
    print(json.dumps({
        "check": "ncdf_vs_scipy",
        "n_points": len(rows),
        "max_abserr": max_abserr,
        "tol_abs": TOL_ABS,
        "n_fail": n_fail,
        "verdict": "PASS" if n_fail == 0 else "FAIL",
        "oracle_self_check_max": ndtr_vs_cdf,
    }))


if __name__ == "__main__":
    main()
