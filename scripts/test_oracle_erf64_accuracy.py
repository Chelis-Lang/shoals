#!/usr/bin/env python3
"""Negative-parity tests for `oracle_erf64_accuracy.py`. shoals#64.

Every test here is a MUTATION that must turn the oracle red. The oracle that
shipped shoals#64's wrong figure was green against a tree whose published
accuracy claim had been rewritten to 1.0e-30, so "it passes on a clean tree" is
not evidence that it works. These tests are the evidence.

Stdlib only, offline, no toolchain: the transcription leg is exercised
end-to-end against throwaway git fixtures, and the measurement leg's decision
functions are exercised directly so the suite stays seconds rather than minutes.
"""

from __future__ import annotations

import importlib.util
import json
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
from decimal import Decimal
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

# The floor-claim marker, composed rather than spelled. This file writes
# claims INTO fixtures; the oracle scans every tracked file, including this
# one, so a literal `>=` beside a number here would be a live claim about the
# kernel. Composing it keeps each fixture byte-identical.
GE = ">" + "="
ORACLE = REPO_ROOT / "scripts" / "oracle_erf64_accuracy.py"

# A fixture tree small enough to read, shaped like the real one: the
# authoritative table, plus carriers in a doc, a source comment and a test.
TABLE = """\
| Kernel | Approximation | Worst observed absolute error (a floor) | Method |
|---|---|---|---|
| `erf64` | Cody | **>= {erf}** (~1.52 ulp of 1.0) | worst observed, measured at 60 dps |
| `n_cdf64` | `0.5 * (1 - erf64(-x/sqrt2))` | **>= {ncdf}** (~0.88 ulp) | the same oracle |
"""
PRICING = "-- Worst observed absolute error >= {erf} (~1.52 ulp of 1.0) for erf64.\n"
UPSTREAM = "`erf64` accuracy:\n  observed absolute error of >= {erf} (~1.52 ulp)\n"


def load_oracle():
    spec = importlib.util.spec_from_file_location("oracle_under_test", ORACLE)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class Fixture:
    """A throwaway git repo carrying the oracle and a published accuracy table.

    A real git repo, because carrier discovery is `git grep` over TRACKED files
    by design -- an untracked scratch file must not be able to fail the gate,
    and a deleted carrier must disappear from discovery.
    """

    def __init__(self, erf="3.3675e-16", ncdf="1.9495e-16", **files):
        self.root = Path(tempfile.mkdtemp(prefix="oracle64-"))
        (self.root / "scripts").mkdir()
        (self.root / "docs").mkdir()
        (self.root / "src").mkdir()
        shutil.copy(ORACLE, self.root / "scripts" / ORACLE.name)
        content = {
            "docs/CHELIS_SURFACE.md": TABLE.format(erf=erf, ncdf=ncdf),
            "docs/UPSTREAM_BUGS.md": UPSTREAM.format(erf=erf),
            "src/pricing.ch": PRICING.format(erf=erf),
        }
        content.update(files)
        for rel, text in content.items():
            if text is None:
                continue
            path = self.root / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)
        for cmd in (["init", "-q"], ["add", "-A"]):
            subprocess.run(["git", *cmd], cwd=self.root, check=True,
                           capture_output=True)

    def run(self):
        done = subprocess.run(
            [sys.executable, "scripts/oracle_erf64_accuracy.py", "--transcription"],
            cwd=self.root, capture_output=True, text=True, check=False,
        )
        return done.returncode, done.stdout + done.stderr

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        shutil.rmtree(self.root, ignore_errors=True)


class TranscriptionLeg(unittest.TestCase):
    """The leg that closes shoals#64's transcription hop."""

    def test_consistent_tree_passes(self):
        """Positive control. Without this, every test below could pass vacuously."""
        with Fixture() as f:
            rc, out = f.run()
            self.assertEqual(rc, 0, out)
            self.assertIn("PASS: transcription", out)

    def test_the_shoals64_mutation_is_caught(self):
        """The exact mutation that shipped: rewrite the published figure only.

        shoals#64 demonstrated this against the old oracle at rc=0.
        """
        with Fixture() as f:
            doc = f.root / "docs/CHELIS_SURFACE.md"
            doc.write_text(doc.read_text().replace("3.3675e-16", "1.0000e-17"))
            subprocess.run(["git", "add", "-A"], cwd=f.root, check=True,
                           capture_output=True)
            rc, out = f.run()
            self.assertEqual(rc, 1, out)
            self.assertIn("src/pricing.ch", out)

    def test_a_single_stale_carrier_is_caught(self):
        """A figure repaired in the table but left stale in one other file."""
        with Fixture() as f:
            src = f.root / "src/pricing.ch"
            src.write_text(src.read_text().replace("3.3675e-16", "3.3676e-16"))
            subprocess.run(["git", "add", "-A"], cwd=f.root, check=True,
                           capture_output=True)
            rc, out = f.run()
            self.assertEqual(rc, 1, out)
            self.assertIn("src/pricing.ch:1", out)

    def test_swapped_table_rows_are_caught(self):
        """The two table figures put on each other's rows, carriers left alone.

        A membership-only check would pass this (both numbers are still
        published), which is why table rows are attributed by their own first
        cell rather than by a context window -- the two rows sit inside each
        other's window.
        """
        with Fixture() as f:
            doc = f.root / "docs/CHELIS_SURFACE.md"
            doc.write_text(doc.read_text()
                           .replace("3.3675e-16", "@@").replace("1.9495e-16", "3.3675e-16")
                           .replace("@@", "1.9495e-16"))
            subprocess.run(["git", "add", "-A"], cwd=f.root, check=True,
                           capture_output=True)
            rc, out = f.run()
            self.assertEqual(rc, 1, out)
            self.assertIn("src/pricing.ch", out)

    def test_a_tree_wide_consistent_rewrite_is_NOT_caught(self):
        """The documented limit of this leg, asserted so nobody overstates it.

        Rewrite every carrier to the same wrong number and the transcription
        leg is green: it proves the carriers AGREE, never that they are right.
        Only the measurement leg constrains the value. This test exists so that
        if someone later claims the offline leg is sufficient, it fails.
        """
        with Fixture(erf="1.0000e-17") as f:
            rc, out = f.run()
            self.assertEqual(rc, 0, out)
            self.assertIn("PASS: transcription", out)

    def test_deleted_table_row_is_caught(self):
        """A vanished row must not take its own guard with it."""
        with Fixture() as f:
            doc = f.root / "docs/CHELIS_SURFACE.md"
            kept = [ln for ln in doc.read_text().splitlines()
                    if not ln.startswith("| `n_cdf64`")]
            doc.write_text("\n".join(kept) + "\n")
            subprocess.run(["git", "add", "-A"], cwd=f.root, check=True,
                           capture_output=True)
            rc, out = f.run()
            self.assertEqual(rc, 1, out)
            self.assertIn("n_cdf64", out)

    def test_missing_table_is_caught(self):
        with Fixture(**{"docs/CHELIS_SURFACE.md": ""}) as f:
            rc, out = f.run()
            self.assertEqual(rc, 1, out)

    def test_unrelated_within_bounds_are_not_policed(self):
        """`research/` states derivative residuals as "within", not ">=".

        Those are a different quantity. The oracle must not fail on them, or it
        will be weakened with an allowlist the first time one is added.
        """
        with Fixture(**{
            "research/RESULTS.md": "`grad(n_cdf64)(0.5)` is within 5.6e-17 of analytic.\n"
        }) as f:
            rc, out = f.run()
            self.assertEqual(rc, 0, out)

    def test_an_out_of_band_floor_claim_is_caught_not_ignored(self):
        """A carrier rewritten to an absurd exponent must be REJECTED.

        An exponent band restricted to -15..-18 would discover nothing here and
        pass, which is why discovery accepts any negative exponent. `1.0e-30`
        is shoals#64's own demonstration mutation.
        """
        for absurd in ("1.0e-30", "3.3675e-160"):
            with self.subTest(absurd=absurd):
                with Fixture(**{
                    "demos/note.ch": f"-- erf64 absolute error {GE} {absurd} here.\n"
                }) as f:
                    rc, out = f.run()
                    self.assertEqual(rc, 1, out)
                    self.assertIn("demos/note.ch", out)

    def test_untracked_carrier_cannot_fail_the_gate(self):
        with Fixture() as f:
            (f.root / "scratch.md").write_text(f"junk {GE} 9.9999e-16 erf64\n")
            rc, out = f.run()
            self.assertEqual(rc, 0, out)

    def test_a_new_carrier_needs_no_registration(self):
        """Discovery is `git grep`, not a list. Adding a carrier is free; adding
        an INCONSISTENT one is not."""
        with Fixture(**{
            "demos/note.ch": f"-- erf64 absolute error {GE} 3.3675e-16 here.\n"
        }) as f:
            rc, out = f.run()
            self.assertEqual(rc, 0, out)
            self.assertIn("demos/note.ch", out)
        with Fixture(**{
            "demos/note.ch": f"-- erf64 absolute error {GE} 3.3674e-16 here.\n"
        }) as f:
            rc, out = f.run()
            self.assertEqual(rc, 1, out)


class TightnessCheck(unittest.TestCase):
    """The two-sided floor check. A one-sided `published <= measured` accepts
    1.0e-30, which is shoals#64's own demonstration mutation."""

    MEASURED = 3.367545353985726e-16

    def setUp(self):
        self.mod = load_oracle()

    def published(self, spelling):
        return self.mod.Published("erf64", spelling, "fixture")

    def is_tight(self, spelling):
        pub = self.published(spelling)
        return self.mod.floor_at(self.MEASURED, pub.sig_digits) == pub.value

    def is_floor(self, spelling):
        return self.published(spelling).value <= Decimal(self.MEASURED)

    def test_the_shipped_figure_is_a_tight_floor(self):
        self.assertTrue(self.is_floor("3.3675e-16"))
        self.assertTrue(self.is_tight("3.3675e-16"))

    def test_absurdly_understated_floor_is_rejected(self):
        """1.0e-30 IS a floor. Tightness is what rejects it."""
        self.assertTrue(self.is_floor("1.0e-30"))
        self.assertFalse(self.is_tight("1.0e-30"))

    def test_overstated_floor_is_rejected(self):
        self.assertFalse(self.is_floor("1.0e-15"))

    def test_floor_rounded_up_is_rejected(self):
        """The real 1.9496e-16 mistake: a floor rounded UP sits above the
        observation it claims to sit under."""
        self.assertFalse(self.is_tight("3.3676e-16"))

    def test_fewer_published_digits_is_honest(self):
        """Publishing less precision is allowed; publishing wrong digits is not."""
        self.assertTrue(self.is_tight("3.3e-16"))
        self.assertTrue(self.is_tight("3e-16"))
        self.assertFalse(self.is_tight("3.4e-16"))

    def test_significant_digit_counting(self):
        for spelling, expected in (("3.3675e-16", 5), ("1.9495e-16", 5),
                                   ("3.3e-16", 2), ("3e-16", 1)):
            self.assertEqual(self.published(spelling).sig_digits, expected, spelling)


class EvalWireDecode(unittest.TestCase):
    """The break that killed this oracle for three pin bumps."""

    def setUp(self):
        self.mod = load_oracle()

    def test_schema3_tagged_carrier_decodes_exactly(self):
        value = 0.5204998778130465
        bits = struct.pack(">d", value).hex()
        entry = {"type": "scalar", "value": {"dtype": "f64", "bits": bits}}
        self.assertEqual(self.mod.decode_scalar(entry, 3), value)

    def test_schema2_bare_float_still_decodes(self):
        entry = {"type": "float64", "value": 0.5}
        self.assertEqual(self.mod.decode_scalar(entry, 2), 0.5)

    def test_a_narrower_dtype_is_rejected_not_coerced(self):
        """These are f64 claims. Measuring an f32 would silently change the
        subject rather than fail."""
        entry = {"type": "scalar", "value": {"dtype": "f32", "bits": "3f000000"}}
        with self.assertRaises(SystemExit):
            self.mod.decode_scalar(entry, 3)

    def test_unsupported_schema_is_named_in_the_failure(self):
        self.assertNotIn(99, self.mod.SUPPORTED_EVAL_SCHEMAS)
        self.assertIn(3, self.mod.SUPPORTED_EVAL_SCHEMAS)


class FailClosed(unittest.TestCase):
    """shoals#64's second inertness: `SKIP ... mpmath not installed`, exit 0."""

    def test_measurement_leg_fails_without_mpmath(self):
        stub = Path(tempfile.mkdtemp(prefix="nompmath-"))
        try:
            # Shadow mpmath with a module that raises ImportError on import.
            (stub / "mpmath.py").write_text("raise ImportError('shadowed')\n")
            done = subprocess.run(
                [sys.executable, "scripts/oracle_erf64_accuracy.py", "--measurement"],
                cwd=REPO_ROOT, capture_output=True, text=True, check=False,
                env={"PATH": "/usr/bin:/bin", "PYTHONPATH": str(stub),
                     "HOME": str(stub)},
            )
            self.assertNotEqual(done.returncode, 0,
                                "a missing reference implementation must FAIL, not SKIP")
            self.assertIn("mpmath", done.stdout + done.stderr)
        finally:
            shutil.rmtree(stub, ignore_errors=True)

    def test_greeks_gate_skips_without_chelis_by_default(self):
        """Positive control for the test below: a clean box still SKIPs, which
        is the behaviour a developer without the pinned toolchain wants."""
        done = subprocess.run(
            [sys.executable, "scripts/oracle_greeks_gate.py"],
            cwd=REPO_ROOT, capture_output=True, text=True, check=False,
            env={"PATH": "/usr/bin:/bin", "CHELIS_BIN": "/nonexistent/chelis"},
        )
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn("SKIP", done.stdout + done.stderr)

    def test_greeks_gate_fails_without_chelis_when_required(self):
        """CI declares the toolchain a prerequisite, so a SKIP there would mean
        the gate silently stopped running -- shoals#64's third inertness.

        This test is what makes the `SHOALS_ORACLE_REQUIRE_CHELIS: "1"` in
        nightly.yml load-bearing rather than decorative.
        """
        done = subprocess.run(
            [sys.executable, "scripts/oracle_greeks_gate.py"],
            cwd=REPO_ROOT, capture_output=True, text=True, check=False,
            env={"PATH": "/usr/bin:/bin", "CHELIS_BIN": "/nonexistent/chelis",
                 "SHOALS_ORACLE_REQUIRE_CHELIS": "1"},
        )
        self.assertNotEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn("refusing to report success", done.stdout + done.stderr)

    def test_ci_sets_the_require_flag(self):
        nightly = (REPO_ROOT / ".github/workflows/nightly.yml").read_text()
        self.assertIn("SHOALS_ORACLE_REQUIRE_CHELIS", nightly)

    def test_dependency_is_declared(self):
        req = REPO_ROOT / "scripts" / "requirements-oracle.txt"
        self.assertTrue(req.is_file(), "the mpmath dependency must be declared")
        self.assertIn("mpmath", req.read_text())


class WiredIntoCi(unittest.TestCase):
    """shoals#64's third inertness: nothing invoked it.

    These assert the wiring exists, so deleting it is a test failure rather
    than a silent return to the state this issue describes.
    """

    def invocations(self, rel):
        return (REPO_ROOT / rel).read_text()

    def test_transcription_leg_runs_per_pr(self):
        ci = self.invocations(".github/workflows/ci.yml")
        self.assertIn("oracle_erf64_accuracy.py --transcription", ci)

    def test_measurement_leg_runs_nightly(self):
        nightly = self.invocations(".github/workflows/nightly.yml")
        self.assertIn("oracle_erf64_accuracy.py --measurement", nightly)

    def test_greeks_oracle_runs_nightly(self):
        nightly = self.invocations(".github/workflows/nightly.yml")
        self.assertIn("oracle_greeks_gate.py", nightly)

    def test_local_gate_runs_both_legs(self):
        gate = self.invocations("scripts/run_local_gate.py")
        self.assertIn("oracle_erf64_accuracy.py", gate)
        self.assertIn("--transcription", gate)
        self.assertIn("--measurement", gate)


if __name__ == "__main__":
    unittest.main(verbosity=2)
