#!/usr/bin/env python3
"""Calibration II acceptance oracle (Milestone H / v0.16.0).

Aggregates the three new pieces into a single PASS/FAIL verdict:

- `Shoals.ModelFit.bfgs_bounded_nparam` — quasi-Newton optimizer
  with bounds + diagnostics (5 tests in `tests-manual/modelfit_bfgs.ch`).
- `Shoals.Curves.bootstrap_grad_full_jacobian` + `instrument_validate`
  — full off-diagonal IFT Jacobian via triangular forward-substitution
  + input validation on `Instrument` constructors (8 tests in
  `tests/curves_bootstrap_ift_full.ch`).
- `Shoals.ModelFit.sequential_pipeline_2stage` +
  `sequential_pipeline_2stage_gradient` — chain curves → SABR/etc
  with IFT-threaded gradient via full-pipeline FD bump (3 tests in
  `tests-manual/modelfit_pipeline.ch`).

Per-test acceptance lives in the .ch files. Gate re-runs all three,
emits per-module pass/fail + total.

Exit 0 on PASS, 1 on FAIL.
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

GATE_NAME = "phase3l_shoals_oracle_calibration_ii"
REPO_ROOT = Path(__file__).resolve().parents[2]

TEST_FILES = [
    ("bfgs", "tests-manual/modelfit_bfgs.ch"),
    ("full_jacobian", "tests/curves_bootstrap_ift_full.ch"),
    ("sequential_pipeline", "tests-manual/modelfit_pipeline.ch"),
]


def run_test_file(path: str) -> tuple[int, dict[str, str], dict]:
    proc = subprocess.run(
        ["chelis", "test", path, "--jobs", "1", "--timeout", "600", "--json"],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        timeout=2700,
    )
    per_test: dict[str, str] = {}
    summary: dict = {}
    for line in proc.stdout.splitlines():
        try:
            rec = json.loads(line)
        except json.JSONDecodeError:
            continue
        if "test" in rec:
            per_test[rec["test"]] = rec.get("status", "?")
        elif "summary" in rec:
            summary = rec["summary"]
    return proc.returncode, per_test, summary


def main() -> int:
    report: dict = {
        "gate": GATE_NAME,
        "milestone": "H",
        "release": "v0.16.0",
        "modules": [],
    }
    all_pass = True
    total_tests = 0
    total_passed = 0
    for tag, test_path in TEST_FILES:
        code, per_test, summary = run_test_file(test_path)
        n_pass = summary.get("passed", 0)
        n_fail = summary.get("failed", 0)
        ok = (code == 0) and (n_fail == 0) and (n_pass > 0)
        if not ok:
            all_pass = False
        total_tests += n_pass + n_fail
        total_passed += n_pass
        report["modules"].append(
            {
                "tag": tag,
                "test_file": test_path,
                "exit_code": code,
                "passed": n_pass,
                "failed": n_fail,
                "per_test": per_test,
                "ok": ok,
            }
        )
    report["acceptance"] = {
        "total_tests": total_tests,
        "total_passed": total_passed,
        "all_modules_ok": all_pass,
    }
    sys.stdout.write(json.dumps(report, indent=2) + "\n")
    if all_pass:
        print(
            f"PASS: {GATE_NAME} — {total_passed}/{total_tests} tests "
            f"(BFGS + full off-diagonal IFT + sequential pipeline)."
        )
        return 0
    print(
        f"FAIL: {GATE_NAME} — see per-module JSON above; "
        f"{total_passed}/{total_tests} passed."
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
