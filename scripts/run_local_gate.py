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
  10. ``scripts/check_tensor_surface_parity.py`` — the list/tensor export
      parity guard for ``Shoals.Indicators`` (shoals#83). Proves that every
      series-taking export has a ``tensor_`` counterpart derivable by the
      naming rule and that none is orphaned. It also reports whether each
      counterpart appears in an equality assertion, but that leg is a
      heuristic over source text, not a proof — see the script's docstring.
      Offline, instant, stdlib-only.
  11. ``scripts/test_check_package_prove_latency.py`` — negative-parity tests
      for the chelis#924 release oracle.
  12. ``scripts/test_risk_invariant_gate.py`` — adversarial compiler-evidence
      and risk-family non-vacuity tests.
  13. ``scripts/test_build_release_assets.py`` — canonical release-builder
      unit tests for the chelis#1002 narrowing.
  14. ``scripts/test_release_workflow.py`` — static release/toolchain and
      hosted/local matrix integrity contracts.
  15. ``.github/scripts/test_secret_scan.py`` — secret-scan contract tests.
  16. ``scripts/oracle_erf64_accuracy.py --transcription`` — the published
      ``erf64``/``n_cdf64`` accuracy floors must be stated identically
      everywhere the tracked tree states them (shoals#64). Offline, instant,
      stdlib-only; the MEASUREMENT leg needs the toolchain and runs under
      ``--full``. This leg proves the carriers agree, never that they are
      right.
  17. ``scripts/test_oracle_erf64_accuracy.py`` — mutation tests over that oracle.
      Eleven mutate a published figure in a throwaway git fixture (the
      shoals#64 mutation among them) and require the oracle to turn red; the
      rest pin the measurement verdict branches, the eval-wire decode, the
      fail-closed paths, sweep-length integrity, and the CI wiring itself.
      Positive controls are included deliberately, since a guard that always
      fails would satisfy every negative test.
  18. ``scripts/check_book.py docs/book/src README.md`` — the user-book lint (CI's
      ``book`` job also runs ``mdbook build docs/book``).
  19. ``scripts/check_book_examples.py`` — book signatures against the source,
      fragments evaluated with the pinned compiler and their shown values
      compared (several minutes).

``--full`` appends the stages CI runs in ``.github/workflows/nightly.yml``
(scheduled, NOT per-PR) — run this at least once at a pin bump
(``AGENTS.md`` §Pin Bump Checklist) or before a release tag:

  16. ``chelis test tests/ --timeout 1200 --suite-timeout 2400 --jobs auto`` — the fast unit
      suite. Its 2400s budget matches the hosted nightly step while measurements
      on Chelis 0.19.0 establish safe headroom. This release includes the
      sharded batching fix in chelis#3058.
  17. The weekly nightly ``heavy`` matrix, one ``tests-manual/<file>.ch`` at
      a time with ``--timeout 1500 --suite-timeout 1650 --jobs 1``. This
      explicitly raises Chelis 0.17.4's separate 600-second whole-suite
      watchdog without weakening any test oracle. It deliberately excludes
      ``modelfit_bfgs_heavy`` pending chelis#408, exactly like hosted nightly;
      an all-directory batch both over-scopes the release gate and hits the
      compiler's whole-suite timeout before completing the reviewed matrix.
  18. ``scripts/oracle_erf64_accuracy.py --measurement`` — measure the
      compiled ``erf64``/``n_cdf64`` kernels against a 60-dps mpmath reference
      and require each published floor to be a TRUE and TIGHT floor
      (shoals#64). ~3 min locally. Needs mpmath:
      ``python3 -m pip install -r scripts/requirements-oracle.txt``. It FAILS
      rather than skips when mpmath is absent.
  19. ``scripts/oracle_greeks_gate.py`` — the AD-Greeks oracle, run with
      ``SHOALS_ORACLE_REQUIRE_CHELIS=1`` so an unavailable toolchain FAILS
      instead of silently skipping (shoals#64).
  20. ``scripts/prove_gate.py`` — the keystone canon self-audit against
      the release binary (real SMT, ~8.6 min; nightly in CI).
  21. ``scripts/check_package_prove_latency.py`` — the chelis#924 release
      oracle: install the just-built Shoals candidate, then require a cold
      trivial package prove in <=20s and an unchanged warm prove in <=5s with
      byte-identical NDJSON.
  22. ``scripts/check_release_artifact_determinism.py`` — two fresh isolated
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
        "prove gate, package-prove latency oracle); required once at a pin "
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
            "book examples against the source",
            ["python3", "scripts/check_book_examples.py"],
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
            "native LSM accuracy against refined American trees",
            ["python3", "scripts/check_lsm_accuracy.py"],
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
