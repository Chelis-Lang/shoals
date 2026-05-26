#!/usr/bin/env python3
"""Rate-model SDE-zoo acceptance oracle (Milestone E / v0.13.0).

Aggregates the four new SDE-zoo test modules into a single pass/fail
verdict + JSON report, matching the pattern of prior milestone gates
(`phase3l_shoals_oracle_heston_qe.py`, `_calibration_smoke.py`).

The four modules under test:

- `Shoals.SabrPaths` — SABR Monte-Carlo (4 tests).
- `Shoals.HullWhite` — Hull-White 1F + 2F + closed-form bond (5 tests).
- `Shoals.LiborMarketModel` — LMM + HJM no-arb drift (7 tests).
- `Shoals.Stochastic` (Kou extension) — Kou double-exponential
  jump-diffusion (5 tests).

Per-test acceptance is encoded inside each `.ch` test file (the
tests fail with an `assert_true` or `assert_close` if a probe
misses tolerance). The gate's role is to (a) run all four test
files in a single deterministic invocation, (b) parse the JSON
per-test verdicts, and (c) emit a PASS/FAIL with the per-module
breakdown so a future reader can audit which probe failed.

Exit 0 on PASS, 1 on FAIL.
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

GATE_NAME = "phase3l_shoals_oracle_rate_sde_zoo"
REPO_ROOT = Path(__file__).resolve().parents[2]

TEST_FILES = [
    ("sabrpaths", "tests/sabrpaths.ch"),
    ("hullwhite", "tests/hull_white.ch"),
    ("libormarketmodel", "tests/libormarketmodel.ch"),
    ("stochastic_kou", "tests/stochastic_kou.ch"),
]


def run_test_file(path: str) -> tuple[int, dict[str, str], dict]:
    """Run one test file under `chelis test --json` and parse results."""
    proc = subprocess.run(
        [
            "chelis",
            "test",
            path,
            "--jobs",
            "1",
            "--timeout",
            "600",
            "--json",
        ],
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
        "milestone": "E",
        "release": "v0.13.0",
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
            f"PASS: {GATE_NAME} — {total_passed}/{total_tests} tests across "
            f"4 modules (SABR paths, Hull-White 1F/2F, LMM/HJM, Kou jumps)."
        )
        return 0
    print(
        f"FAIL: {GATE_NAME} — see per-module JSON above; "
        f"{total_passed}/{total_tests} tests passed across 4 modules."
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
