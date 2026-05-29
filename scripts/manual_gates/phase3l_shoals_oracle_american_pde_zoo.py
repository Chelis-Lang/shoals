#!/usr/bin/env python3
"""American & PDE pricing-zoo acceptance oracle (Milestone F / v0.14.0).

Aggregates the four new pricing modules into a single PASS/FAIL
verdict + JSON report, matching the convention of prior milestone
gates.

Modules covered:

- `Shoals.Trees` (10 exports — CRR / Tian / JR binomial + Boyle
  trinomial; European + American; 7 tests).
- `Shoals.Pde` (4 exports — Crank-Nicolson + Rannacher for European
  call/put + American put + 2-D ADI for spread option; 5 tests).
- `Shoals.Lsm` (3 exports — Longstaff-Schwartz American MC with
  polynomial regression; 4 tests).
- `Shoals.Heston` (extended: Lewis 2001 + Lipton inversion variants
  alongside the existing Carr-Madan; +4 tests, 12 total).

Per-test acceptance is encoded inside each `.ch` file; the gate
runs all four, parses JSON verdicts, and emits a PASS/FAIL with
the per-module breakdown.

Exit 0 on PASS, 1 on FAIL.
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

GATE_NAME = "phase3l_shoals_oracle_american_pde_zoo"
REPO_ROOT = Path(__file__).resolve().parents[2]

TEST_FILES = [
    ("trees", "tests-manual/trees.ch"),
    ("pde", "tests-manual/pde.ch"),
    ("lsm", "tests-manual/lsm.ch"),
    ("heston_fourier", "tests-manual/heston.ch"),
]


def run_test_file(path: str) -> tuple[int, dict[str, str], dict]:
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
        timeout=3600,
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
        "milestone": "F",
        "release": "v0.14.0",
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
            f"4 modules (Trees, PDE, LSM, Heston Lewis/Lipton)."
        )
        return 0
    print(
        f"FAIL: {GATE_NAME} — see per-module JSON above; "
        f"{total_passed}/{total_tests} tests passed."
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
