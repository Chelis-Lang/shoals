#!/usr/bin/env python3
"""Run the Shoals local acceptance gate.

Default mode mirrors every locally meaningful stage of the **lean per-PR CI**
(``.github/workflows/ci.yml``). The origin-relative conformance bump check
remains CI-only because a stale local ``origin/main`` can false-fail it. The
real-chelis/real-SMT nightly stages do NOT run unless you pass ``--full``:

  1. ``python3 scripts/audit_workarounds.py --pins-only`` (the
     hard-rule-guard job: offline pin consistency).
  2. ``chelis fmt --check`` over every ``.ch`` file in ``src/``,
     ``properties/``, ``references/``, ``demos/``, ``tests/``,
     ``tests-manual/``, ``tests_neg/``, ``tests_blocked/``.
  3. ``chelis lint --check`` over those directories + ``manual-gates/``.
  4. ``chelis reef build`` for package-level compiler validation.
  5. ``scripts/validate_bs_wire_root.py`` — lower the real pure-tensor
     Black-Scholes entry and require its named WireDag root (shoals#19).
  6. ``chelis test tests_neg/ --expect neg`` (contract §6).
  7. ``chelis test tests_blocked/ --expect blocked`` (contract §5 —
     a pass here is FIX-detected and fails loudly by design). Skipped when
     ``tests_blocked/`` holds no probes: ``--expect`` rejects an empty suite,
     and the directory is legitimately empty once every pinned blocker has
     been de-narrowed (see ``tests_blocked/README.md``).
  8. ``chelis reef conform audit`` (contract §11). The per-PR CI also runs
     ``conform bump-check --base origin/main``; that step is CI-only —
     a stale local ``origin/main`` would make it false-fail, and CI runs
     it authoritatively on every PR.
  9. ``scripts/contract_gate.py`` — offline manifest resolvability + pin
      freshness (also a per-PR CI gate).
  10. ``scripts/test_check_package_prove_latency.py`` — negative-parity tests
      for the chelis#924 release oracle.
  11. ``scripts/test_risk_invariant_gate.py`` — adversarial compiler-evidence
      and risk-family non-vacuity tests.
  12. ``scripts/test_build_release_assets.py`` — canonical release-builder
      unit tests for the chelis#1002 narrowing.
  13. ``scripts/test_release_workflow.py`` — static release/toolchain and
      hosted/local matrix integrity contracts.

``--full`` appends the stages CI runs in ``.github/workflows/nightly.yml``
(scheduled, NOT per-PR) — run this at least once at a pin bump
(``AGENTS.md`` §Pin Bump Checklist) or before a release tag:

  14. ``chelis test tests/ --timeout 1200 --suite-timeout 2400 --jobs auto`` — the fast unit
      suite (nightly in CI). The suite budget was raised from 1500s at the
      0.18.6 pin to work around chelis#1391, which is OPEN upstream -- a
      narrowing, not a fix; keep it byte-aligned with the hosted nightly step.
  15. The weekly nightly ``heavy`` matrix, one ``tests-manual/<file>.ch`` at
      a time with ``--timeout 1500 --suite-timeout 1650 --jobs 1``. This
      explicitly raises Chelis 0.17.4's separate 600-second whole-suite
      watchdog without weakening any test oracle. It deliberately excludes
      ``modelfit_bfgs_heavy`` pending chelis#408, exactly like hosted nightly;
      an all-directory batch both over-scopes the release gate and hits the
      compiler's whole-suite timeout before completing the reviewed matrix.
  16. ``scripts/prove_gate.py`` — the keystone canon self-audit against
      the release binary (real SMT, ~8.6 min; nightly in CI).
  17. ``scripts/check_package_prove_latency.py`` — the chelis#924 release
      oracle: install the just-built Shoals candidate, then require a cold
      trivial package prove in <=20s and an unchanged warm prove in <=5s with
      byte-identical NDJSON.
  18. ``scripts/check_release_artifact_determinism.py`` — two fresh isolated
      registries (mixed-case manual preseed versus clean canonical) must emit
      byte-identical lock, CHB, and archive payloads despite chelis#1002.

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

NIGHTLY_MANUAL_FILES = [
    "composites_binding_heavy",
    "greeks_secondorder",
    "heston",
    "heston_heavy",
    "hull_white",
    "hull_white_heavy",
    "lsm_heavy",
    "modelfit_bfgs",
    # modelfit_bfgs_heavy is excluded pending chelis#408; keep this list
    # byte-for-byte aligned with the hosted nightly matrix.
    "modelfit_pipeline",
    "modelfit_pipeline_heavy",
    "pde_heavy",
    "rng_heavy",
    "sabrpaths_heavy",
    "stochastic_kou_heavy",
    "trees",
    "trees_heavy",
    "xva_wwr_heavy",
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
        "prove gate, package-prove latency oracle) — required once at a pin "
        "bump / before a release tag",
    )
    args = parser.parse_args()
    quiet = args.quiet

    blocked_probes = sorted((REPO_ROOT / "tests_blocked").glob("**/*.ch"))

    fmt_files = (
        sorted((REPO_ROOT / "src").glob("*.ch"))
        + sorted((REPO_ROOT / "properties").glob("*.ch"))
        + sorted((REPO_ROOT / "references").glob("*.ch"))
        + sorted((REPO_ROOT / "demos").glob("*.ch"))
        + sorted((REPO_ROOT / "tests").glob("*.ch"))
        + sorted((REPO_ROOT / "tests-manual").glob("*.ch"))
        + sorted((REPO_ROOT / "tests_neg").glob("**/*.ch"))
        + blocked_probes
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
            "Shoals Black-Scholes WireDag root (shoals#19)",
            ["python3", "scripts/validate_bs_wire_root.py"],
        ),
        (
            "chelis test tests_neg/ --expect neg",
            ["chelis", "test", "tests_neg/", "--expect", "neg"],
        ),
        # `--expect blocked` errors on an empty suite (a guard running zero
        # probes would be silently green), and tests_blocked/ is legitimately
        # empty whenever every pinned blocker has been de-narrowed. Include
        # the stage only when a probe exists; see tests_blocked/README.md.
        *(
            [
                (
                    "chelis test tests_blocked/ --expect blocked",
                    ["chelis", "test", "tests_blocked/", "--expect", "blocked"],
                )
            ]
            if blocked_probes
            else []
        ),
        ("chelis reef conform audit", ["chelis", "reef", "conform", "audit"]),
        (
            "contract_gate (offline manifest resolvability + pin freshness)",
            ["python3", "scripts/contract_gate.py"],
        ),
        (
            "chelis#924 latency-oracle unit tests",
            ["python3", "scripts/test_check_package_prove_latency.py"],
        ),
        (
            "risk invariant adversarial unit tests",
            ["python3", "scripts/test_risk_invariant_gate.py"],
        ),
        (
            "canonical release-builder unit tests (chelis#1002)",
            ["python3", "scripts/test_build_release_assets.py"],
        ),
        (
            "release workflow integrity tests",
            ["python3", "scripts/test_release_workflow.py"],
        ),
        (
            "secret scan contract tests",
            ["python3", "-m", "unittest", "discover", "-v", "-s", ".github/scripts", "-p", "test_secret_scan.py"],
        ),
    ]
    nightly_stages: list[tuple[str, list[str]]] = [
        (
            "chelis test tests/ --jobs auto",
            [
                "chelis", "test", "tests/", "--timeout", "1200",
                "--suite-timeout", "2400", "--jobs", "auto",
            ],
        ),
        *[
            (
                f"chelis test tests-manual/{stem}.ch --jobs 1",
                [
                    "chelis", "test", f"tests-manual/{stem}.ch",
                    "--timeout", "1500", "--suite-timeout", "1650",
                    "--jobs", "1",
                ],
            )
            for stem in NIGHTLY_MANUAL_FILES
        ],
        (
            "prove_gate (canon self-audit against the release binary)",
            ["/usr/bin/env", "PROVE_GATE_FUZZ=1",
             "python3", "scripts/prove_gate.py"],
        ),
        (
            "chelis#924 package prove latency oracle",
            ["python3", "scripts/check_package_prove_latency.py"],
        ),
        (
            "cross-registry release artifact determinism (chelis#1002)",
            ["python3", "scripts/check_release_artifact_determinism.py"],
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
