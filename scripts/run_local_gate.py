#!/usr/bin/env python3
"""Run Shoals's lean local validation, with an optional extended numerical suite.

The default validates pins, formatting, lint, compilation, short negative and
blocked guards, conformance, the manifest, offline adversarial oracle units,
published accuracy transcriptions, and book prose/source signatures. The
origin-relative pin-bump check and mdBook rendering run in CI.

``--full`` opts into long-running local tools: the tests/ and tests-manual/
suites, native LSM/PDE references, accuracy measurements, AD and canon proof
checks, bounded pricing properties, latency and cross-registry benchmarks, and
runtime book examples. These are never hosted checks or pre-push, merge, pin
bump, or release blockers. Individual scripts remain directly usable.

To opt in, prepare this worktree's Python 3.11 environment:
    uv venv --python 3.11
    uv pip install -r scripts/requirements-oracle.txt
    PATH="$PWD/.venv/bin:$PATH" python3 scripts/run_local_gate.py --full

Measurement fails without mpmath rather than reporting a skipped pass. Each
runner reports its own evidence; green static checks do not establish new
numerical or proof results.
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

LOCAL_MANUAL_FILES = [
    "composites_binding_heavy",
    "greeks_secondorder",
    "heston",
    "heston_heavy",
    "hull_white",
    "hull_white_heavy",
    "lsm_heavy",
    "modelfit_bfgs",
    # chelis#408 was specific to hosted constrained runners; local execution
    # remains optional and the known local fixture is included.
    "modelfit_bfgs_heavy",
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
    inherits stdout/stderr — used for the optional extended stages so
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
        help="opt into long-running local numerical, proof, benchmark and "
        "runtime book checks; not required before push, merge or release",
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
            "short expiry properties with false controls",
            ["python3", "scripts/check_pricing_fix_properties.py", "--smoke"],
        ),
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
            "Shoals.Indicators list/tensor surface parity (shoals#83)",
            ["python3", "scripts/check_tensor_surface_parity.py"],
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
            "bounded pricing property classifier tests",
            ["python3", "scripts/test_check_pricing_fix_properties.py"],
        ),
        (
            "LSM accuracy oracle adversarial tests",
            ["python3", "scripts/test_check_lsm_accuracy.py"],
        ),
        (
            "spread PDE accuracy oracle adversarial tests",
            ["python3", "scripts/test_spread_adi_oracle.py"],
        ),
        (
            "release workflow integrity tests",
            ["python3", "scripts/test_release_workflow.py"],
        ),
        (
            "secret scan contract tests",
            ["python3", "-m", "unittest", "discover", "-v", "-s", ".github/scripts", "-p", "test_secret_scan.py"],
        ),
        (
            "accuracy-floor transcription (shoals#64)",
            ["python3", "scripts/oracle_erf64_accuracy.py", "--transcription"],
        ),
        (
            "accuracy-floor oracle mutation tests (shoals#64)",
            ["python3", "scripts/test_oracle_erf64_accuracy.py"],
        ),
        (
            "book lint (docs/book/src + README)",
            ["python3", "scripts/check_book.py", "docs/book/src", "README.md"],
        ),
        (
            "book signatures against repository sources",
            ["python3", "scripts/check_book_examples.py", "--source-only"],
        ),
        (
            "source-only book checker regressions",
            ["python3", "scripts/test_check_book_examples.py"],
        ),
    ]
    extended_stages: list[tuple[str, list[str]]] = [
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
            for stem in LOCAL_MANUAL_FILES
        ],
        (
            "native LSM accuracy against refined American trees",
            ["python3", "scripts/check_lsm_accuracy.py"],
        ),
        (
            "native spread PDE accuracy and numerical mutations",
            ["python3", "scripts/manual_gates/spread_adi_oracle.py"],
        ),
        (
            "accuracy-floor measurement (shoals#64)",
            ["python3", "scripts/oracle_erf64_accuracy.py", "--measurement"],
        ),
        (
            "AD-Greeks oracle gate (shoals#64)",
            ["/usr/bin/env", "SHOALS_ORACLE_REQUIRE_CHELIS=1",
             "python3", "scripts/oracle_greeks_gate.py"],
        ),
        (
            "prove_gate (canon self-audit against the release binary)",
            ["/usr/bin/env", "PROVE_GATE_FUZZ=1",
             "python3", "scripts/prove_gate.py"],
        ),
        (
            "bounded pricing regressions with false controls (three seeds)",
            ["python3", "scripts/check_pricing_fix_properties.py"],
        ),
        (
            "chelis#924 package prove latency oracle",
            ["python3", "scripts/check_package_prove_latency.py"],
        ),
        (
            "cross-registry release artifact determinism (chelis#1002)",
            ["python3", "scripts/check_release_artifact_determinism.py"],
        ),
        (
            "book runtime examples and displayed outputs",
            ["python3", "scripts/check_book_examples.py"],
        ),
    ]

    stages = [(label, cmd, False) for label, cmd in per_pr_stages]
    if args.full:
        stages += [(label, cmd, True) for label, cmd in extended_stages]
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

    mode = "optional extended suite" if args.full else "lean validation"
    print(f"OK: shoals local gate green [{mode}]")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
