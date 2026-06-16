#!/usr/bin/env python3
"""Risk backtest-suite acceptance oracle (Milestone J / v0.18.0).

Aggregates the two new backtest modules in `Shoals.RiskExt`:

- Christoffersen conditional-coverage test + Acerbi-Szekely Z1/Z2/Z3
  ES backtests (`tests/riskext_backtest.ch`, 7 tests).
- FRTB-IMA traffic-light zone classifier (`tests/riskext_frtb_zone.ch`,
  5 tests).

Exit 0 on PASS, 1 on FAIL.
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

GATE_NAME = "phase3l_shoals_oracle_risk_backtest_suite"
REPO_ROOT = Path(__file__).resolve().parents[2]

TEST_FILES = [
    ("backtest_cc_es", "tests/riskext_backtest.ch"),
    ("frtb_ima_zone", "tests/riskext_frtb_zone.ch"),
]


def run_test_file(path: str) -> tuple[int, dict[str, str], dict]:
    proc = subprocess.run(
        ["chelis", "test", path, "--jobs", "1", "--timeout", "300", "--json"],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        timeout=1200,
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
        "milestone": "J",
        "release": "v0.18.0",
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
            f"(Christoffersen + Acerbi-Szekely + FRTB-IMA zone)."
        )
        return 0
    print(
        f"FAIL: {GATE_NAME} — see per-module JSON above; "
        f"{total_passed}/{total_tests} passed."
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
