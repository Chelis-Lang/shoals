#!/usr/bin/env python3
"""IFT-bootstrap gradient acceptance oracle.

Runs `chelis test tests/curves_bootstrap_ift.ch --jobs 1 --timeout 120`
and reports per-probe pass/fail in JSON, then a `PASS:` or `FAIL:`
terminating line. The five pinned probes are encoded inside the test
file; this gate aggregates and surfaces their outcome for offline
review.

Probes (per plan):
  1. Well-conditioned baseline (IFT-FD < 1% relative on every pillar).
  2. Near-collinear instruments (IFT diagonal finite; FD divergence
     expected on the near-collinear pillar, not flagged).
  3. Parameter at bound (lower-bound rate; IFT diagonal stays bounded
     and matches the analytic single-pillar value).
  4. FD step-size sensitivity (IFT matches FD@1e-4 within the f32+
     brent-1e-7 precision floor; FD coarse/fine spread bounded).
  5. Pathological pillar spacing (two instruments at the same tenor;
     diagonal IFT matches analytic on both, no silent garbage).

Exit 0 on PASS, 1 on FAIL. Final stdout line is `PASS:` or `FAIL:`
followed by the gate name and a one-sentence summary.

Usage:

    python3 scripts/manual_gates/phase3l_shoals_oracle_multi_curve_bootstrap_grad.py
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

GATE_NAME = "phase3l_shoals_oracle_multi_curve_bootstrap_grad"

REPO_ROOT = Path(__file__).resolve().parents[2]

PROBE_TO_TEST = {
    "1_well_conditioned_baseline": [
        "test_grad_well_conditioned_vs_fd",
        "test_grad_well_conditioned_three_pillars_fd_agreement",
    ],
    "2_near_collinear_finite": [
        "test_grad_near_collinear_finite_and_bounded",
    ],
    "3_parameter_at_lower_bound": [
        "test_grad_at_parameter_lower_bound_finite",
    ],
    "4_fd_step_size_stability": [
        "test_grad_fd_step_size_stability",
    ],
    "5_pathological_pillar_spacing": [
        "test_grad_pathological_pillar_returns_finite_or_documented",
    ],
}

ANALYTIC_PROBES = [
    "test_grad_zero_coupon_matches_analytic",
    "test_grad_deposit_matches_analytic",
    "test_grad_par_swap_single_pillar",
]


def parse_test_results(stdout: str) -> dict[str, str]:
    results: dict[str, str] = {}
    line_re = re.compile(r"^\s*(test_\w+)\s+(PASS|FAIL)")
    for line in stdout.splitlines():
        m = line_re.match(line)
        if m:
            results[m.group(1)] = m.group(2)
    return results


def main() -> int:
    proc = subprocess.run(
        [
            "chelis",
            "test",
            "tests/curves_bootstrap_ift.ch",
            "--jobs",
            "1",
            "--timeout",
            "120",
        ],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
    )
    results = parse_test_results(proc.stdout)

    per_probe = {}
    all_pass = True
    for probe_name, tests in PROBE_TO_TEST.items():
        statuses = [results.get(t, "MISSING") for t in tests]
        probe_ok = all(s == "PASS" for s in statuses)
        per_probe[probe_name] = {
            "tests": dict(zip(tests, statuses)),
            "ok": probe_ok,
        }
        if not probe_ok:
            all_pass = False

    analytic_results = {t: results.get(t, "MISSING") for t in ANALYTIC_PROBES}
    analytic_ok = all(s == "PASS" for s in analytic_results.values())
    if not analytic_ok:
        all_pass = False

    report = {
        "gate": GATE_NAME,
        "test_file": "tests/curves_bootstrap_ift.ch",
        "exit_code": proc.returncode,
        "analytic_probes": {
            "tests": analytic_results,
            "ok": analytic_ok,
            "purpose": "single-pillar IFT diagonal matches closed-form analytic for deposit / zero_coupon / par_swap",
        },
        "ift_failure_mode_probes": per_probe,
        "fd_step_size_methodology": (
            "IFT uses no finite difference; FD uses central-rate forward bump with "
            "step in {1e-2, 1e-4, 1e-6}. Tolerance on IFT-FD@1e-4 relative agreement "
            "is 2%, set by the f32 precision floor on a brent root finder converging "
            "to abs tol 1e-7."
        ),
        "near_collinear_methodology": (
            "Two adjacent zero-coupon pillars at t=1.0 (p=0.95) and t=1.001 (p=0.949) — "
            "the IFT diagonal sensitivity is the local dz_i*/dx_i which stays finite "
            "even though a full off-diagonal Jacobian would be ill-conditioned. The "
            "probe asserts |g_i| < 1000 on both pillars; FD divergence on a finite-"
            "difference comparison would be expected behavior, not a gate failure."
        ),
        "pathological_pillar_methodology": (
            "Two zero-coupon instruments at the same tenor t=1.0 with different "
            "prices — the diagonal IFT correctly returns the per-instrument analytic "
            "(-1/(t*p)) for each, with no silent NaN/Inf. A full bootstrap Jacobian "
            "would be singular at this configuration, but the per-pillar diagonal "
            "stays well-defined."
        ),
    }
    sys.stdout.write(json.dumps(report, indent=2) + "\n")
    if all_pass:
        print(
            f"PASS: {GATE_NAME} — all 5 IFT failure-mode probes + analytic single-pillar checks passed."
        )
        return 0
    print(
        f"FAIL: {GATE_NAME} — at least one IFT probe failed; see per-probe ok flags in JSON above."
    )
    if proc.returncode != 0:
        sys.stderr.write(proc.stdout + proc.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
