#!/usr/bin/env python3
"""Run the Shoals local acceptance gate.

Default mode mirrors the **lean per-PR CI** (`.github/workflows/ci.yml`)
and nothing more — the real-chelis/real-SMT nightly stages do NOT run
unless you pass ``--full``:

  1. ``python3 scripts/audit_workarounds.py --pins-only`` (the
     hard-rule-guard job: offline pin consistency).
  2. ``chelis fmt --check`` over every ``.ch`` file in ``src/``,
     ``properties/``, ``references/``, ``demos/``, ``tests/``,
     ``tests-manual/``, ``tests_neg/``, ``tests_blocked/``.
  3. ``chelis lint --check`` over those directories + ``manual-gates/``.
  4. ``chelis reef build`` for package-level compiler validation.
  5. ``chelis test tests_neg/ --expect neg`` (contract §6).
  6. ``chelis test tests_blocked/ --expect blocked`` (contract §5 —
     a pass here is FIX-detected and fails loudly by design).
  7. ``chelis reef conform audit`` (contract §11). The per-PR CI also runs
     ``conform bump-check --base origin/main``; that step is CI-only —
     a stale local ``origin/main`` would make it false-fail, and CI runs
     it authoritatively on every PR.
  8. ``scripts/contract_gate.py`` — offline manifest resolvability + pin
     freshness (also a per-PR CI gate).

``--full`` appends the stages CI runs in ``.github/workflows/nightly.yml``
(scheduled, NOT per-PR) — run this at least once at a pin bump
(``AGENTS.md`` §Pin Bump Checklist) or before a release tag:

  9.  ``chelis test tests/ --timeout 1200 --jobs auto`` — the fast unit
      suite (~13 min of real-chelis wall; nightly in CI).
  10. ``chelis test tests-manual/ --timeout 1200 --jobs auto`` — the heavy
      MC / PDE / Fourier / optimization-benchmark suite (weekly nightly
      ``heavy`` matrix in CI, sharded one leg per file; the milestone
      manual-gate scripts under ``scripts/manual_gates/`` exercise these
      files by explicit path).
  11. ``scripts/prove_gate.py`` — the keystone canon self-audit against
      the release binary (real SMT, ~8.6 min; nightly in CI).

Exits 0 only if all requested stages succeed.

Usage:

    python scripts/run_local_gate.py [--quiet] [--full]

This script lives in Python per the repo policy that prohibits shell
scripts (`AGENTS.md`).
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]

LINT_DIRS = [
    "src/",
    "properties/",
    "references/",
    "demos/",
    "tests/",
    "tests-manual/",
    "manual-gates/",
    "tests_neg/",
    "tests_blocked/",
]


def run(cmd: list[str], *, quiet: bool, stream: bool = False) -> int:
    """Run a subprocess, return its exit code.

    Captured by default (output shown only on failure). ``stream=True``
    inherits stdout/stderr — used for the multi-minute nightly stages so
    progress is visible and the full suite output is never buffered.
    """
    if not quiet:
        print(f"  $ {' '.join(cmd)}", flush=True)
    if stream:
        return subprocess.run(cmd, cwd=REPO_ROOT).returncode
    result = subprocess.run(cmd, cwd=REPO_ROOT, capture_output=True, text=True)
    if result.returncode != 0:
        sys.stdout.write(result.stdout)
        sys.stderr.write(result.stderr)
    return result.returncode


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--quiet", action="store_true", help="suppress per-file lines")
    parser.add_argument(
        "--full",
        action="store_true",
        help="also run the nightly-CI stages (unit suite, heavy suite, "
        "prove gate) — required once at a pin bump / before a release tag",
    )
    args = parser.parse_args()
    quiet = args.quiet

    fmt_files = (
        sorted((REPO_ROOT / "src").glob("*.ch"))
        + sorted((REPO_ROOT / "properties").glob("*.ch"))
        + sorted((REPO_ROOT / "references").glob("*.ch"))
        + sorted((REPO_ROOT / "demos").glob("*.ch"))
        + sorted((REPO_ROOT / "tests").glob("*.ch"))
        + sorted((REPO_ROOT / "tests-manual").glob("*.ch"))
        + sorted((REPO_ROOT / "tests_neg").glob("**/*.ch"))
        + sorted((REPO_ROOT / "tests_blocked").glob("**/*.ch"))
    )

    per_pr_stages: list[tuple[str, list[str]]] = [
        (
            "audit_workarounds --pins-only (offline pin consistency)",
            ["python3", "scripts/audit_workarounds.py", "--pins-only"],
        ),
        ("chelis fmt --check", []),  # expanded per-file below
        ("chelis lint --check", ["chelis", "lint", "--check", *LINT_DIRS]),
        ("chelis reef build", ["chelis", "reef", "build"]),
        (
            "chelis test tests_neg/ --expect neg",
            ["chelis", "test", "tests_neg/", "--expect", "neg"],
        ),
        (
            "chelis test tests_blocked/ --expect blocked",
            ["chelis", "test", "tests_blocked/", "--expect", "blocked"],
        ),
        ("chelis reef conform audit", ["chelis", "reef", "conform", "audit"]),
        (
            "contract_gate (offline manifest resolvability + pin freshness)",
            ["python3", "scripts/contract_gate.py"],
        ),
    ]
    nightly_stages: list[tuple[str, list[str]]] = [
        (
            "chelis test tests/ --jobs auto",
            ["chelis", "test", "tests/", "--timeout", "1200", "--jobs", "auto"],
        ),
        (
            "chelis test tests-manual/ --jobs auto",
            ["chelis", "test", "tests-manual/", "--timeout", "1200", "--jobs", "auto"],
        ),
        (
            "prove_gate (canon self-audit against the release binary)",
            ["python3", "scripts/prove_gate.py"],
        ),
    ]

    stages = [(label, cmd, False) for label, cmd in per_pr_stages]
    if args.full:
        stages += [(label, cmd, True) for label, cmd in nightly_stages]
    total = len(stages)

    for i, (label, cmd, stream) in enumerate(stages, start=1):
        print(f"[{i}/{total}] {label}")
        if not cmd:  # the per-file fmt stage
            for path in fmt_files:
                rel = path.relative_to(REPO_ROOT)
                rc = run(["chelis", "fmt", "--check", str(rel)], quiet=quiet)
                if rc != 0:
                    print(f"FAIL: chelis fmt --check {rel}")
                    return rc
            continue
        rc = run(cmd, quiet=False, stream=stream)
        if rc != 0:
            print(f"FAIL: {label}")
            return rc

    mode = "full (per-PR + nightly stages)" if args.full else "per-PR mirror"
    print(f"OK: shoals local gate green [{mode}]")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
