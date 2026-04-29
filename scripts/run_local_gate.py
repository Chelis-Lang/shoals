#!/usr/bin/env python3
"""Run the Shoals local acceptance gate.

Invokes:

  1. ``chelis check`` over every source file under
     ``src/``, ``src/properties/``, ``src/references/``.
  2. ``chelis fmt --check`` over every ``.ch`` file in
     ``src/``, ``src/properties/``, ``src/references/``, ``tests/``.
  3. ``chelis test tests/``.

Exits 0 only if all three stages succeed. Mirrors the steps in the
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

    src_files = (
        sorted((REPO_ROOT / "src").glob("*.ch"))
        + sorted((REPO_ROOT / "src" / "properties").glob("*.ch"))
        + sorted((REPO_ROOT / "src" / "references").glob("*.ch"))
    )
    test_files = sorted((REPO_ROOT / "tests").glob("*.ch"))
    fmt_files = src_files + test_files

    print("[1/3] chelis check")
    for path in src_files:
        rel = path.relative_to(REPO_ROOT)
        rc = run(["chelis", "check", str(rel)], quiet=quiet)
        if rc != 0:
            print(f"FAIL: chelis check {rel}")
            return rc

    print("[2/3] chelis fmt --check")
    for path in fmt_files:
        rel = path.relative_to(REPO_ROOT)
        rc = run(["chelis", "fmt", "--check", str(rel)], quiet=quiet)
        if rc != 0:
            print(f"FAIL: chelis fmt --check {rel}")
            return rc

    print("[3/3] chelis test tests/")
    rc = run(["chelis", "test", "tests/"], quiet=False)
    if rc != 0:
        print("FAIL: chelis test")
        return rc

    print("OK: shoals local gate green")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
