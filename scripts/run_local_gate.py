#!/usr/bin/env python3
"""Run the Shoals local acceptance gate.

Invokes:

  1. ``chelis fmt --check`` over every ``.ch`` file in
     ``src/``, ``properties/``, ``references/``, ``tests/``.
  2. ``chelis lint --check`` over ``src/ properties/ references/
     tests/ manual-gates/``.
  3. ``chelis reef build`` for package-level compiler validation.
  4. ``chelis test tests/ --timeout 120 --jobs auto`` for the native
     runtime suite.

Exits 0 only if all stages succeed. Mirrors the default PR gate in the
GitHub Actions workflow under ``.github/workflows/ci.yml``.

Usage:

    python scripts/run_local_gate.py [--quiet]

This script lives in Python per the repo policy that prohibits shell
scripts (`AGENTS.md`).
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]


def run(cmd: list[str], *, quiet: bool) -> int:
    """Run a subprocess, return its exit code. Streams stdout on failure."""
    if not quiet:
        print(f"  $ {' '.join(cmd)}", flush=True)
    result = subprocess.run(cmd, cwd=REPO_ROOT, capture_output=True, text=True)
    if result.returncode != 0:
        sys.stdout.write(result.stdout)
        sys.stderr.write(result.stderr)
    return result.returncode


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--quiet", action="store_true", help="suppress per-file lines")
    args = parser.parse_args()
    quiet = args.quiet

    fmt_files = (
        sorted((REPO_ROOT / "src").glob("*.ch"))
        + sorted((REPO_ROOT / "properties").glob("*.ch"))
        + sorted((REPO_ROOT / "references").glob("*.ch"))
        + sorted((REPO_ROOT / "tests").glob("*.ch"))
    )

    print("[1/4] chelis fmt --check")
    for path in fmt_files:
        rel = path.relative_to(REPO_ROOT)
        rc = run(["chelis", "fmt", "--check", str(rel)], quiet=quiet)
        if rc != 0:
            print(f"FAIL: chelis fmt --check {rel}")
            return rc

    print("[2/4] chelis lint --check")
    rc = run(
        [
            "chelis",
            "lint",
            "--check",
            "src/",
            "properties/",
            "references/",
            "tests/",
            "manual-gates/",
        ],
        quiet=False,
    )
    if rc != 0:
        print("FAIL: chelis lint --check")
        return rc

    print("[3/4] chelis reef build")
    rc = run(["chelis", "reef", "build"], quiet=False)
    if rc != 0:
        print("FAIL: chelis reef build")
        return rc

    print("[4/4] chelis test tests/ --jobs auto")
    rc = run(["chelis", "test", "tests/", "--timeout", "120", "--jobs", "auto"], quiet=False)
    if rc != 0:
        print("FAIL: chelis test tests/ --jobs auto")
        return rc

    print("OK: shoals local gate green")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
