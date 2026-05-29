#!/usr/bin/env python3
"""XVA expansion acceptance oracle (Milestone I / v0.17.0).

Aggregates the five new XVA-suite pieces into a single PASS/FAIL:

- `Shoals.Cds` — CDS bootstrap + premium/protection leg + survival.
- `Shoals.Xva.cva_stochastic_hazard` — CVA with HazardCurve.
- `Shoals.Xva.fva` + `kva` — Burgard-Kjaer FVA, Green-Kenyon KVA.
- `Shoals.Xva.xva_cva_wwr_constant_hazard` — wrong-way risk via
  Gaussian copula on default-time + exposure-shock factor.
- `Shoals.Csa.csa_collateralized_exposure_path` + `Shoals.Xva.
  xva_cva_stochastic_recovery` — multi-CSA netting + beta-recovery
  CVA.

Exit 0 on PASS, 1 on FAIL.
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

GATE_NAME = "phase3l_shoals_oracle_xva_expansion"
REPO_ROOT = Path(__file__).resolve().parents[2]

TEST_FILES = [
    ("cds", "tests/cds.ch"),
    ("xva_stochastic_hazard", "tests/xva_stochastic_hazard.ch"),
    ("xva_fva_kva", "tests/xva_fva_kva.ch"),
    ("xva_wwr", "tests-manual/xva_wwr.ch"),
    ("csa", "tests/csa.ch"),
    ("xva_stochastic_recovery", "tests/xva_stochastic_recovery.ch"),
]


def run_test_file(path: str) -> tuple[int, dict[str, str], dict]:
    proc = subprocess.run(
        ["chelis", "test", path, "--jobs", "1", "--timeout", "600", "--json"],
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
        "milestone": "I",
        "release": "v0.17.0",
        "modules": [],
    }
    all_pass = True
    total_tests = 0
    total_passed = 0
    for tag, test_path in TEST_FILES:
        if not (REPO_ROOT / test_path).exists():
            report["modules"].append(
                {"tag": tag, "test_file": test_path, "missing": True, "ok": False}
            )
            all_pass = False
            continue
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
            f"{len(TEST_FILES)} XVA-suite modules."
        )
        return 0
    print(
        f"FAIL: {GATE_NAME} — see per-module JSON above; "
        f"{total_passed}/{total_tests} passed."
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
