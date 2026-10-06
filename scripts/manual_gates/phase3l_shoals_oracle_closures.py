#!/usr/bin/env python3
"""Closures acceptance oracle (Milestone K / v0.19.0).

Aggregates the small-wins closure pieces:

- Cross-currency basis curves (`Shoals.Curves.CurveBasis` +
  `curve_basis_from_pillars` + `discount_factor_with_basis`).
- Sobol 1024-D runtime construction (`Shoals.Rng.sobol_dim_runtime`
  + `sobol_point_runtime_at`).
- Margrabe-Stulz exchange option + asset/cash-or-nothing digital
  options (`Shoals.PricingExtended.pe_*`).

Exit 0 on PASS, 1 on FAIL.
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

GATE_NAME = "phase3l_shoals_oracle_closures"
REPO_ROOT = Path(__file__).resolve().parents[2]

TEST_FILES = [
    ("curves_basis", "tests/curves_basis.ch"),
    ("rng_sobol_1024", "tests/rng_sobol_1024.ch"),
    ("pricingextended_closedforms", "tests/pricingextended_closedforms.ch"),
]


def run_test_file(path: str) -> tuple[int, dict[str, str], dict]:
    proc = subprocess.run(
        ["chelis", "test", path, "--jobs", "1", "--timeout", "300", "--json"],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        timeout=1800,
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
        "milestone": "K",
        "release": "v0.19.0",
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
            f"3 closure modules (cross-ccy basis, Sobol 1024-D, "
            f"Margrabe-Stulz + digitals)."
        )
        return 0
    print(
        f"FAIL: {GATE_NAME} — see per-module JSON above; "
        f"{total_passed}/{total_tests} passed."
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
