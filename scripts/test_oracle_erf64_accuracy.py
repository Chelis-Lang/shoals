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
import math
import shutil
import struct
import subprocess
import sys
import tempfile
import types
import unittest
from decimal import Decimal
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

# The floor-claim marker, composed rather than spelled. This file writes
# claims INTO fixtures; the oracle scans every tracked file, including this
# one, so a literal `>=` beside a number here would be a live claim about the
# kernel. Composing it keeps each fixture byte-identical.
GE = ">" + "="
# shoals#68's marker, composed for the same reason: this file is tracked, the
# oracle greps every tracked file, and the new leg fails any marker that does
# not parse -- so a literal here would fail the gate against its own test suite.
RELMK = "REL-" + "FLOOR"
ORACLE = REPO_ROOT / "scripts" / "oracle_erf64_accuracy.py"

# A fixture tree small enough to read, shaped like the real one: the
# authoritative table, plus carriers in a doc, a source comment and a test.
TABLE = """\
| Kernel | Approximation | Worst observed absolute error (a floor) | Method |
|---|---|---|---|
| `erf64` | Cody | **>= {erf}** (~1.52 ulp of 1.0) | worst observed, measured at 60 dps |
| `n_cdf64` | `0.5 * erfc(-x/sqrt2)` | **>= {ncdf}** (~0.88 ulp) | the same oracle |

| Claim | Interval | Method |
|---|---|---|
| **{relmk} `n_cdf64` >= {rel} * (1 + x^2) * 2^-53** | -37.5 <= x <= 6.5 | the same oracle |
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

    def __init__(self, erf="3.3675e-16", ncdf="1.9495e-16", rel="4.2025",
                 **files):
        self.root = Path(tempfile.mkdtemp(prefix="oracle64-"))
        (self.root / "scripts").mkdir()
        (self.root / "docs").mkdir()
        (self.root / "src").mkdir()
        shutil.copy(ORACLE, self.root / "scripts" / ORACLE.name)
        content = {
            "docs/CHELIS_SURFACE.md": TABLE.format(
                erf=erf, ncdf=ncdf, rel=rel, relmk=RELMK),
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


class MeasurementEnforcement(unittest.TestCase):
    """`run_measurement`'s verdict branches, which `TightnessCheck` does NOT
    reach.

    A red-team pass on PR #108 replaced the `elif not published_is_tight:`
    branch with `elif False:` -- deleting this PR's headline repair -- and the
    suite stayed green, because `TightnessCheck` exercises `floor_at` and
    `Published.sig_digits` in isolation and never calls the one function that
    turns "not tight" into a nonzero exit.

    mpmath and `chelis` are both injected, so this runs under the bare
    interpreter the per-PR job uses. `worst` is stubbed because the subject here
    is the VERDICT, not the sweep; the sweep is covered end to end by the
    nightly measurement leg.
    """

    # The real measured figures, so the fixtures below are the shipped ones.
    MEASURED = {"erf64": 3.367545353985726e-16,
                "n_cdf64": 1.9495914774441617e-16}

    def setUp(self):
        self.mod = load_oracle()
        self.nans = 0
        # `run_measurement` iterates erf64 then n_cdf64, so hand back each
        # kernel's own measurement in that order. Returning one value for both
        # made n_cdf64 fail too and masked the attribution test.
        order = iter(("erf64", "n_cdf64"))
        self.mod.probe_points = lambda: [0.5]
        self.mod.evaluate = lambda points, call: [0.0]
        self.mod.worst = lambda points, values, fn, mp: (
            self.MEASURED[next(order)], 0.5, self.nans)
        fake = types.ModuleType("mpmath")
        fake.mp = types.SimpleNamespace(dps=15)
        fake.mpf = float
        fake.erf = math.erf
        fake.sqrt = math.sqrt
        self._prev = sys.modules.get("mpmath")
        sys.modules["mpmath"] = fake

    def tearDown(self):
        if self._prev is None:
            sys.modules.pop("mpmath", None)
        else:
            sys.modules["mpmath"] = self._prev

    def run_with(self, erf_spelling, ncdf_spelling="1.9495e-16"):
        published = {
            "erf64": self.mod.Published("erf64", erf_spelling, "fixture"),
            "n_cdf64": self.mod.Published("n_cdf64", ncdf_spelling, "fixture"),
        }
        return self.mod.run_measurement(published, verbose=False)

    def test_a_tight_floor_passes(self):
        """Positive control: without it every assertion below could pass
        because the function always fails."""
        rc, report = self.run_with("3.3675e-16", "1.9495e-16")
        self.assertEqual(rc, 0, report["errors"])

    def test_understated_floor_exits_nonzero(self):
        """The branch the red team deleted. 1.0e-30 IS a floor."""
        rc, report = self.run_with("1.0e-30")
        self.assertEqual(rc, 1)
        self.assertTrue(any("not a TIGHT one" in e for e in report["errors"]),
                        report["errors"])

    def test_overstated_floor_exits_nonzero(self):
        rc, report = self.run_with("1.0e-15")
        self.assertEqual(rc, 1)
        self.assertTrue(any("EXCEEDS" in e for e in report["errors"]),
                        report["errors"])

    def test_only_the_offending_kernel_is_named(self):
        """The leg must attribute, not go blanket-red: a failure naming both
        kernels would send a maintainer to the wrong figure."""
        rc, report = self.run_with("1.0e-30", "1.9495e-16")
        self.assertEqual(rc, 1)
        joined = " ".join(report["errors"])
        self.assertIn("erf64", joined)
        self.assertNotIn("n_cdf64", joined)

    def test_an_unpublished_kernel_is_not_silently_skipped(self):
        """A measured kernel with no published floor has nothing to check it
        against, which must fail rather than pass vacuously."""
        published = {"erf64": self.mod.Published("erf64", "3.3675e-16", "fixture")}
        rc, report = self.mod.run_measurement(published, verbose=False)
        self.assertEqual(rc, 1)
        self.assertTrue(any("no published floor" in e for e in report["errors"]),
                        report["errors"])

    def test_a_nan_sweep_fails(self):
        """A sweep that measured nothing must not report a tight floor."""
        self.nans = 7
        rc, report = self.run_with("3.3675e-16")
        self.assertEqual(rc, 1)
        self.assertTrue(any("NaN" in e for e in report["errors"]), report["errors"])


class RelativeMeasurementEnforcement(unittest.TestCase):
    """`run_relative_measurement`'s VERDICT branches. shoals#68.

    This class exists because a red-team pass on the shoals#68 change found
    FOUR surviving mutations of the relative leg -- the silent-zero branch
    (`if zeros:` -> `if False:`), `zeros.append(x)` -> `pass`, and both the
    floor-ness and tightness branches -> `if False:` -- while the 59-test suite
    stayed green. `RelativeClaimFamily` tests `floor_at` and
    `PublishedRelative.sig_digits` in isolation and never calls the one
    function that turns "not tight" into a nonzero exit.

    That is EXACTLY the pattern `MeasurementEnforcement`'s docstring above
    records being found on the absolute leg in PR #108. The same class of
    defect was re-introduced one leg over, in the same file, by a change whose
    stated purpose was to stop a guard being inert. The seam
    (`relative_worst`) was added so this class can exist.

    mpmath is stubbed with `math`, so this runs under the bare interpreter the
    per-PR job uses. `reference_self_test` is stubbed out because f64 is
    deliberately not precise enough to pass it -- that function has its own
    tests in `RelativeClaimFamily`.
    """

    MEASURED = 4.202530048
    AT = -0.7170090691949448

    def setUp(self):
        self.mod = load_oracle()
        self.nans = 0
        self.zeros = []
        self.measured = self.MEASURED
        self.mod.relative_probe_points = lambda: [self.AT]
        self.mod.evaluate = lambda points, call: [0.5]
        self.mod.reference_self_test = lambda mp: None
        # Captured BEFORE the stub replaces it: the two real-loop tests below
        # need the genuine sweep, and reading it off the module after stubbing
        # would silently test the stub against itself.
        self.real_relative_worst = self.mod.relative_worst
        self.mod.relative_worst = lambda points, values, mp, unit: (
            self.measured, self.AT, 2.183991578472283e-13, -33.705,
            self.nans, self.zeros)
        self.fake = types.ModuleType("mpmath")
        self.fake.mp = types.SimpleNamespace(dps=15)
        self.fake.mpf = float
        self.fake.erf = math.erf
        self.fake.erfc = math.erfc
        self.fake.sqrt = math.sqrt

    def run_with(self, spelling="4.2025"):
        published = {"n_cdf64": self.mod.PublishedRelative(
            "n_cdf64", spelling, "fixture")}
        return self.mod.run_relative_measurement(
            published, self.fake, verbose=False)

    def test_a_tight_relative_floor_passes(self):
        """Positive control. Without it every assertion below could pass
        because the function always fails."""
        rc, report = self.run_with()
        self.assertEqual(rc, 0, report["errors"])

    def test_an_understated_relative_floor_exits_nonzero(self):
        """1.0000 IS a floor of 4.2025 and tells a reader nothing. This is the
        mutation the red team found surviving (`elif False:`)."""
        rc, report = self.run_with("1.0000")
        self.assertEqual(rc, 1)
        self.assertTrue(any("not a TIGHT one" in e for e in report["errors"]),
                        report["errors"])

    def test_an_overstated_relative_floor_exits_nonzero(self):
        """A floor above every observation is not a floor (`if False:`)."""
        rc, report = self.run_with("9.9999")
        self.assertEqual(rc, 1)
        self.assertTrue(any("EXCEEDS" in e for e in report["errors"]),
                        report["errors"])

    def test_silent_zeros_exit_nonzero(self):
        """shoals#68's worst symptom. No relative floor bounds it: a returned
        zero has relative error 1 and is excluded from the maxima, so the
        tightness check cannot see it."""
        self.zeros = [-9.0, -20.0]
        rc, report = self.run_with()
        self.assertEqual(rc, 1)
        joined = " ".join(report["errors"])
        self.assertIn("exactly 0.0", joined)
        self.assertIn("shoals#68", joined)
        self.assertEqual(report["kernels"]["n_cdf64"]["silent_zero_count"], 2)

    def test_silent_zeros_fail_even_when_the_floor_is_tight(self):
        """The two requirements are independent. A kernel that returns zeros in
        the tail can still have a tight normalised floor over the points it did
        resolve -- which is precisely how a reinstated shoals#68 would pass a
        floor-only guard."""
        self.zeros = [-20.0]
        rc, report = self.run_with("4.2025")
        self.assertEqual(rc, 1)
        self.assertTrue(report["kernels"]["n_cdf64"]["published_is_tight"])

    def test_an_unpublished_kernel_is_not_silently_skipped(self):
        rc, report = self.mod.run_relative_measurement(
            {}, self.fake, verbose=False)
        self.assertEqual(rc, 1)
        self.assertTrue(any("no published claim" in e for e in report["errors"]),
                        report["errors"])

    def test_a_nan_sweep_fails(self):
        """A sweep that measured nothing must not report a tight floor."""
        self.nans = 7
        rc, report = self.run_with()
        self.assertEqual(rc, 1)
        self.assertTrue(any("NaN" in e for e in report["errors"]),
                        report["errors"])

    def test_the_real_sweep_records_a_kernel_zero(self):
        """The branch INSIDE the sweep, which stubbing `relative_worst` cannot
        reach. `zeros.append(x)` -> `pass` was a surviving mutation: it drops
        the point from the zero list AND from both maxima, so every verdict
        stays green while the kernel returns zeros.

        Real loop, stubbed evaluator: at x = -9 the reference is ~1.13e-19,
        comfortably representable at f64, so a returned 0.0 must be recorded.
        """
        worst, at, raw, raw_at, nans, zeros = self.real_relative_worst(
            [-9.0], [0.0], self.fake, float(2.0 ** -53))
        self.assertEqual(zeros, [-9.0],
                         "a kernel zero against a representable true value "
                         "was not recorded")
        self.assertEqual(nans, 0)
        self.assertEqual(worst, 0.0, "a recorded zero must not enter the max")

    def test_the_real_sweep_counts_a_nan(self):
        """F1 from red-team round 2, and a P1 when it was missing: the NaN
        COUNTER inside the sweep. `test_a_nan_sweep_fails` stubs
        `relative_worst`, so it drives the `if nans:` verdict but never the
        counter that feeds it. With the counter disabled, a kernel returning
        NaN over part of the tail has those points silently dropped from both
        maxima, `nans` stays 0, the verdict never fires, and the oracle reports
        a true and tight floor over whatever survived -- measured: a kernel
        NaN-ing below x = -30 took the oracle from exit 1 (`137 of 6183 ...
        came back NaN`) to exit 0 PASS.

        Same shape as `zeros.append(x)`, which round 1 found surviving and the
        first repair pinned. This is its sibling, left out.
        """
        worst, at, raw, raw_at, nans, zeros = self.real_relative_worst(
            [-9.0], [float("nan")], self.fake, float(2.0 ** -53))
        self.assertEqual(nans, 1, "a NaN was not counted")
        self.assertEqual(zeros, [], "a NaN was misreported as a kernel zero")
        self.assertEqual(worst, 0.0)
        self.assertEqual(raw, 0.0)

    def test_the_real_sweep_drives_every_component_at_a_nonzero_error(self):
        """F2 from round 2: five further mutations survived because the only
        two tests that called the real sweep used values of exactly 0.0, so
        every maximum stayed 0 and the normaliser, the `unit` argument, the
        tuple ordering and both max-assignments were never exercised. A
        CONSTANT AXIS -- each assertion correct, none of them varying the thing
        that was broken.

        Two points with KNOWN, different relative errors, so the argmax has to
        be chosen rather than defaulted, and all six components are asserted.
        """
        mod, fake = self.mod, self.fake
        unit = float(2.0 ** -53)
        # THREE points with the argmax in the MIDDLE. Two points with the
        # argmax last let `if normalised > worst:` be mutated to
        # `if normalised > worst_raw:` and survive: that comparison is true for
        # every point, so every point overwrites the max and the LAST one wins
        # -- which was the right answer purely because of the ordering.
        # `at`/`raw_at` are initialised to `points[0]`, so the argmax must be
        # neither first nor last for either accident to be available.
        small, big, tiny = -4.0, -8.0, -2.0
        t_small = mod.reference_ncdf(fake, small)
        t_big = mod.reference_ncdf(fake, big)
        t_tiny = mod.reference_ncdf(fake, tiny)
        # Normalised: 1e-15/(17*unit) ~= 0.53 at -4; 1e-14/(65*unit) ~= 1.39 at
        # -8; 1e-16/(5*unit) ~= 0.18 at -2. The RAW max is also at -8, so a
        # swapped return tuple is caught by the values, not the argmax.
        #
        # SIGN IS NOT A FREE CHOICE EITHER. `got = t * (1 - eps)` rather than
        # `(1 + eps)` because the real argmax at x = -0.7170090691949448, and
        # every tail point the oracle reports, has sign(got - true) NEGATIVE.
        # With a positive fixture the `abs()` in `rel` can be deleted and this
        # test still passes -- measured. Both axes were constant.
        got_small = t_small * (1 - 1e-15)
        got_big = t_big * (1 - 1e-14)
        got_tiny = t_tiny * (1 - 1e-16)
        worst, at, raw, raw_at, nans, zeros = self.real_relative_worst(
            [small, big, tiny], [got_small, got_big, got_tiny], fake, unit)

        # The expectations are derived from the ACTUAL doubles, not from the
        # 1e-14 that produced them: `t_big * (1 + 1e-14)` rounds, so the
        # achieved relative error is 1e-14 to about 0.14% and asserting the
        # nominal figure fails for a reason that has nothing to do with the
        # subject.
        rel_big = abs(got_big - t_big) / t_big
        rel_small = abs(got_small - t_small) / t_small
        self.assertGreater(rel_big, rel_small * 5, "the fixture lost its spread")

        self.assertEqual(nans, 0)
        self.assertEqual(zeros, [])
        self.assertEqual(at, big, "the normalised argmax was not selected")
        self.assertEqual(raw_at, big, "the raw argmax was not selected")
        # Raw: the relative error itself.
        self.assertAlmostEqual(raw / rel_big, 1.0, places=9)
        # Normalised: divided by BOTH the conditioning and the unit roundoff.
        expected = rel_big / ((1 + big * big) * unit)
        self.assertAlmostEqual(worst / expected, 1.0, places=9)
        # The two are different quantities and must not be interchangeable --
        # this is what a swapped return tuple or a dropped divisor looks like.
        self.assertGreater(worst, raw * 1e10)
        self.assertNotAlmostEqual(worst / (raw / (1 + big * big)), 1.0, places=3)
        self.assertNotAlmostEqual(worst / (raw / unit), 1.0, places=3)

    def test_the_production_call_site_passes_the_unit_roundoff(self):
        """The `unit` the real leg hands `relative_worst`, which the test above
        cannot pin because it passes its own.

        `REL_UNIT_ROUNDOFF_EXP = -52` or a call site spelling `2 ** -52`
        halves every normalised figure and takes the measurement from 4.2025
        to 2.1013 -- loud (the oracle exits 1 on "EXCEEDS") but unpinned by the
        unit suite until now. Captured by recording what the leg actually
        passes rather than by reading the source.
        """
        seen = []

        def spy(points, values, mp, unit):
            seen.append(unit)
            return 0.0, self.AT, 0.0, self.AT, 0, []

        self.mod.relative_worst = spy
        self.mod.evaluate = lambda points, call: [0.0]
        published = {"n_cdf64": self.mod.PublishedRelative(
            "n_cdf64", "4.2025", "fixture")}
        self.mod.run_relative_measurement(published, self.fake, verbose=False)
        self.assertEqual(len(seen), 1, "the sweep was not called exactly once")
        self.assertEqual(seen[0], 2.0 ** -53,
                         "the leg passed the wrong unit roundoff")
        self.assertEqual(self.mod.REL_UNIT_ROUNDOFF_EXP, -53)

    def test_the_reference_self_test_is_actually_invoked(self):
        """`reference_self_test` is called from exactly one place -- this leg --
        and the absolute leg does not call it. Deleting that call removes the
        whole shoals#64-class reference guard (the one that stops the oracle
        measuring against a reference that reproduces the defect) with no test
        noticing: the function has unit tests, its INVOCATION had none.
        """
        called = []
        self.mod.reference_self_test = lambda mp: called.append(mp)
        self.mod.relative_worst = lambda points, values, mp, unit: (
            0.0, self.AT, 0.0, self.AT, 0, [])
        self.mod.evaluate = lambda points, call: [0.0]
        published = {"n_cdf64": self.mod.PublishedRelative(
            "n_cdf64", "4.2025", "fixture")}
        self.mod.run_relative_measurement(published, self.fake, verbose=False)
        self.assertEqual(len(called), 1,
                         "the relative leg did not run its reference self-test")
        self.assertIs(called[0], self.fake)

    def test_the_real_sweep_does_not_record_a_true_zero_as_a_kernel_zero(self):
        """Negative parity: below the representable band BOTH are zero and
        there is nothing to be relative to. Recording that as a silent zero
        would make the guard fire on correct behaviour."""
        *_, nans, zeros = self.real_relative_worst(
            [-40.0], [0.0], self.fake, float(2.0 ** -53))
        self.assertEqual(zeros, [], "a true zero was misreported as a defect")
        self.assertEqual(nans, 0)


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


class SweepIntegrity(unittest.TestCase):
    """A short wire response must not be read as a complete sweep."""

    def setUp(self):
        self.mod = load_oracle()

    def test_a_truncated_response_is_rejected(self):
        self.mod._evaluate_batch = lambda pts, call: [0.0] * (len(pts) - 1)
        with self.assertRaises(SystemExit) as ctx:
            self.mod.evaluate([0.1, 0.2, 0.3], "erf64")
        self.assertIn("probe points", str(ctx.exception))

    def test_an_overlong_response_is_rejected(self):
        self.mod._evaluate_batch = lambda pts, call: [0.0] * (len(pts) + 1)
        with self.assertRaises(SystemExit):
            self.mod.evaluate([0.1, 0.2], "erf64")

    def test_a_complete_response_passes(self):
        self.mod._evaluate_batch = lambda pts, call: [0.0] * len(pts)
        self.assertEqual(len(self.mod.evaluate([0.1, 0.2, 0.3], "erf64")), 3)


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

    def test_ci_sets_the_require_flag_and_the_gate_reads_it(self):
        """Both halves, because either alone is decorative: a renamed key in
        the workflow, or a workflow that sets a key no code consumes, both left
        the old file-wide assertion green."""
        # Colon-anchored on purpose. A bare substring assertion is satisfied by
        # `SHOALS_ORACLE_REQUIRE_CHELIS_X`, so renaming the key -- which
        # silences the flag completely -- stayed green on the first attempt at
        # this fix.
        block = job_block("nightly.yml", "accuracy")
        self.assertIn('SHOALS_ORACLE_REQUIRE_CHELIS: "1"',
                      "\n".join(live_lines(block)))
        gate = (REPO_ROOT / "scripts/oracle_greeks_gate.py").read_text()
        self.assertIn('os.environ.get("SHOALS_ORACLE_REQUIRE_CHELIS") == "1"', gate)

    def test_dependency_is_declared(self):
        req = REPO_ROOT / "scripts" / "requirements-oracle.txt"
        self.assertTrue(req.is_file(), "the mpmath dependency must be declared")
        self.assertIn("mpmath", req.read_text())


class RelativeClaimFamily(unittest.TestCase):
    """shoals#68's leg. Every test is a mutation that must turn the oracle red.

    The positive control is `TranscriptionLeg.test_consistent_tree_passes`,
    whose fixture now carries a relative claim; without it each mutation here
    could pass because the fixture was broken rather than because the mutation
    was caught.
    """

    def mutate(self, path, old, new, **kw):
        f = Fixture(**kw)
        self.addCleanup(f.__exit__)
        target = f.root / path
        text = target.read_text()
        self.assertIn(old, text, "the mutation did not apply; fixture changed")
        target.write_text(text.replace(old, new))
        subprocess.run(["git", "add", "-A"], cwd=f.root, check=True,
                       capture_output=True)
        return f.run()

    def test_a_disagreeing_relative_carrier_is_caught(self):
        """The transcription hop, for the relative family. Same defect class as
        shoals#64, one quantity over."""
        extra = {"src/ncdf_note.ch":
                 f"-- {RELMK} `n_cdf64` {GE} 9.9999 * (1 + x^2) * 2^-53\n"}
        f = Fixture(**extra)
        self.addCleanup(f.__exit__)
        rc, out = f.run()
        self.assertEqual(rc, 1, out)
        self.assertIn("src/ncdf_note.ch:1", out)
        self.assertIn("9.9999", out)

    def test_an_agreeing_relative_carrier_passes(self):
        """Negative parity for the test above: the mechanism must not reject a
        carrier that agrees, or it would be a constant-fail guard."""
        extra = {"src/ncdf_note.ch":
                 f"-- {RELMK} `n_cdf64` {GE} 4.2025 * (1 + x^2) * 2^-53\n"}
        f = Fixture(**extra)
        self.addCleanup(f.__exit__)
        rc, out = f.run()
        self.assertEqual(rc, 0, out)
        self.assertIn("PASS: transcription", out)

    def test_deleting_the_published_relative_claim_is_caught(self):
        """A vanished claim must not take its own guard with it -- which is
        exactly how an inert guard is produced."""
        rc, out = self.mutate("docs/CHELIS_SURFACE.md",
                              f"**{RELMK} `n_cdf64`", "**(removed)")
        self.assertEqual(rc, 1, out)
        self.assertIn("no relative floor published for `n_cdf64`", out)

    def test_an_unparseable_near_miss_marker_is_caught(self):
        """Worse than an absent claim: it reads as published and matches
        nothing, so the kernel silently drops out of the governed set."""
        rc, out = self.mutate(
            "docs/CHELIS_SURFACE.md",
            "* (1 + x^2) * 2^-53", "* (1 + x*x) * 2^-53")
        self.assertEqual(rc, 1, out)
        self.assertIn("does not parse", out)

    def test_a_relative_claim_for_an_unmeasured_kernel_is_caught(self):
        """A claim nothing measures is a claim nobody checks."""
        rc, out = self.mutate("docs/CHELIS_SURFACE.md",
                              f"{RELMK} `n_cdf64`", f"{RELMK} `erf64`")
        self.assertEqual(rc, 1, out)
        self.assertIn("not in REL_FLOOR_KERNELS", out)

    def test_two_relative_claims_for_one_kernel_are_caught(self):
        """Two published figures for one quantity means neither is published."""
        rc, out = self.mutate(
            "docs/CHELIS_SURFACE.md",
            f"**{RELMK} `n_cdf64` {GE} 4.2025 * (1 + x^2) * 2^-53**",
            f"**{RELMK} `n_cdf64` {GE} 4.2025 * (1 + x^2) * 2^-53** and "
            f"**{RELMK} `n_cdf64` {GE} 1.0000 * (1 + x^2) * 2^-53**")
        self.assertEqual(rc, 1, out)
        self.assertIn("more than one relative floor", out)

    def test_the_two_families_do_not_read_each_others_claims(self):
        """The whole reason this is a separate marker. If the absolute pattern
        matched a relative claim, the two figures would each be the other's
        failure; if the relative pattern matched an absolute claim, every
        absolute carrier would be an unparseable relative marker."""
        mod = load_oracle()
        rel_text = f"{RELMK} `n_cdf64` {GE} 4.2025 * (1 + x^2) * 2^-53"
        abs_text = f"worst observed {GE} 3.3675e-16 (~1.52 ulp)"
        self.assertEqual(mod.FLOOR_CLAIM.findall(rel_text), [])
        self.assertEqual(mod.REL_FLOOR_CLAIM.findall(abs_text), [])
        self.assertEqual(mod.REL_FLOOR_CLAIM.findall(rel_text),
                         [("n_cdf64", "4.2025")])
        self.assertEqual(mod.FLOOR_CLAIM.findall(abs_text), ["3.3675e-16"])

    def test_the_oracles_own_source_carries_no_bare_relative_marker(self):
        """The oracle greps every tracked file including itself, and fails any
        marker that does not parse -- so a literal in its own comments or
        diagnostics would fail the gate against the guard. Both files compose
        the marker from parts for that reason; this is the test that keeps them
        doing it."""
        for path in (ORACLE, Path(__file__).resolve()):
            text = path.read_text(encoding="utf-8")
            self.assertNotIn(
                RELMK, text,
                f"{path.name} spells the relative marker literally; compose it")

    def test_the_relative_floor_is_held_to_the_same_tightness_rule(self):
        """An understated relative floor is still technically a floor. 1.0 is a
        floor of 4.2025 and tells a reader nothing."""
        mod = load_oracle()
        published = mod.PublishedRelative("n_cdf64", "4.2025", "fixture")
        self.assertEqual(published.sig_digits, 5)
        self.assertEqual(mod.floor_at(4.202530048, 5), Decimal("4.2025"))
        self.assertNotEqual(mod.floor_at(4.202530048, 5), Decimal("1.0"))
        # and a floor published ABOVE the measurement is not a floor
        self.assertLess(Decimal("4.2025"), Decimal(4.202530048))
        self.assertGreater(Decimal("4.3000"), Decimal(4.202530048))

    def test_the_conditioning_is_the_identitys_not_the_kernels(self):
        """`1 + x^2` comes from `d ln erfc / d ln u` at `u = x/sqrt2`, so it is
        a property of the identity and checkable without any kernel."""
        mod = load_oracle()
        stub = types.SimpleNamespace(mpf=float)
        self.assertEqual(mod.conditioning(stub, 0.0), 1.0)
        self.assertEqual(mod.conditioning(stub, 8.0), 65.0)
        self.assertEqual(mod.conditioning(stub, -8.0), 65.0)

    def test_the_relative_grid_is_a_superset_of_the_absolute_one(self):
        """Not padding. The normalised statistic peaks near x = 0, so a
        tail-weighted grid understates it -- measured 1.918 against 4.203 on
        the same kernel. A floor that a later refinement falsifies is the one
        failure mode a floor must not have."""
        mod = load_oracle()
        lo, hi = mod.REL_INTERVAL
        absolute = {x for x in mod.probe_points() if lo <= x <= hi}
        relative = set(mod.relative_probe_points())
        self.assertTrue(absolute <= relative,
                        f"{len(absolute - relative)} absolute probe points are "
                        f"missing from the relative grid")
        self.assertIn(-0.7170090691949448, relative)
        self.assertTrue(min(relative) <= -37.0,
                        "the relative grid does not reach the saturation point")

    def test_the_relative_reference_must_not_cancel(self):
        """shoals#68's shape, inside the oracle. The absolute leg's reference
        `(1 + erf(x/sqrt2))/2` returns EXACTLY 0.0 in the deep tail at finite
        precision, so an oracle built on it compares the kernel's zero against
        a reference zero and reports PASS on the defect it exists to find.

        Demonstrated at f64 precision, which is the cheapest precision at which
        the cancellation is visible: `math.erf(-9/sqrt(2))` is exactly -1.0, so
        the erf form is 0.0 while the erfc form is 1.13e-19.
        """
        mod = load_oracle()
        stub = types.SimpleNamespace(
            mpf=float, sqrt=math.sqrt, erf=math.erf, erfc=math.erfc)
        via_erf = (1 + math.erf(-9.0 / math.sqrt(2))) / 2
        via_erfc = mod.reference_ncdf(stub, -9.0)
        self.assertEqual(via_erf, 0.0, "the cancellation is no longer visible")
        self.assertGreater(via_erfc, 0.0)
        self.assertAlmostEqual(via_erfc / 1.1285884059538405e-19, 1.0, places=12)

    def test_the_reference_self_test_rejects_insufficient_precision(self):
        """Proves the self-test is not vacuous: hand it a reference evaluated
        at f64 and it must refuse, because the erf form has already cancelled
        at x = -9 where the two are supposed to agree."""
        mod = load_oracle()
        stub = types.SimpleNamespace(
            mpf=float, sqrt=math.sqrt, erf=math.erf, erfc=math.erfc)
        with self.assertRaises(SystemExit) as caught:
            mod.reference_self_test(stub)
        self.assertIn("references disagree", str(caught.exception))

    @unittest.skipUnless(
        importlib.util.find_spec("mpmath"),
        "mpmath is the measurement leg's dependency; the nightly job installs "
        "it and test_nightly_accuracy_job_installs_its_dependency pins that")
    def test_the_reference_self_test_passes_at_the_real_precision(self):
        """Positive control for the test above."""
        import mpmath as mp
        mod = load_oracle()
        mp.mp.dps = 60
        mod.reference_self_test(mp)

    def test_the_relative_leg_is_reached_by_the_measurement_flag(self):
        """A leg nothing invokes is shoals#64's defect, not its fix. The
        nightly job runs `--measurement`; this asserts that flag reaches the
        relative leg, which no workflow grep can show because the leg has no
        command line of its own."""
        mod = load_oracle()
        import inspect
        body = inspect.getsource(mod.main)
        self.assertIn("run_relative_measurement(", body)
        self.assertIn("if do_m:", body)


def job_block(workflow: str, job: str) -> str:
    """The YAML text of one job, from its `  <job>:` header to the next job.

    Hand-rolled rather than `yaml.safe_load` because this suite runs in the
    per-PR `contract-gate` job, whose whole claim to being there is that it is
    STDLIB-ONLY and needs no toolchain. Importing PyYAML to test that property
    would destroy it. `scripts/test_release_workflow.py` slices the same way.
    """
    lines = (REPO_ROOT / ".github/workflows" / workflow).read_text().splitlines()
    start = next(i for i, ln in enumerate(lines) if ln == f"  {job}:")
    end = len(lines)
    for i in range(start + 1, len(lines)):
        ln = lines[i]
        if ln[:2] == "  " and ln[2:3] not in (" ", "", "#") and ln.rstrip().endswith(":"):
            end = i
            break
    return "\n".join(lines[start:end])


def live_lines(block: str) -> list[str]:
    """Uncommented lines only. A commented-out step must not satisfy a wiring
    assertion -- that was the whole defect: a raw `assertIn` over the file was
    green with every `run:` line commented out."""
    return [ln for ln in block.splitlines() if not ln.lstrip().startswith("#")]


class WiredIntoCi(unittest.TestCase):
    """shoals#64's third inertness: nothing invoked it.

    These assert the wiring exists IN THE NAMED JOB and is not commented out,
    so deleting or disabling it is a test failure rather than a silent return
    to the state this issue describes. An earlier version of this class used
    `assertIn` over the whole file; a red-team pass on PR #108 showed all four
    assertions stayed green with each `run:` line commented out and with the
    env key renamed, so they asserted nothing. Keep these job-scoped and
    comment-aware.
    """

    def assertWired(self, workflow, job, needle):
        block = job_block(workflow, job)
        hits = [ln for ln in live_lines(block) if needle in ln]
        self.assertTrue(
            hits,
            f"{needle!r} is not live in {workflow}'s `{job}` job. Commented "
            f"out, moved to another job, or deleted -- any of which returns "
            f"this guard to the state shoals#64 describes.",
        )
        return block

    def test_transcription_leg_runs_per_pr(self):
        """In `contract-gate`, which is the per-PR offline job. Not merely
        somewhere in the file: a step moved to a workflow_dispatch-only job
        would satisfy a file-wide check."""
        self.assertWired("ci.yml", "contract-gate",
                         "oracle_erf64_accuracy.py --transcription")

    def test_mutation_tests_run_per_pr(self):
        self.assertWired("ci.yml", "contract-gate",
                         "scripts/test_oracle_erf64_accuracy.py")

    def test_per_pr_job_is_triggered_by_pull_request(self):
        """A job nothing triggers is the defect, not the fix."""
        head = (REPO_ROOT / ".github/workflows/ci.yml").read_text().split("jobs:")[0]
        self.assertIn("pull_request", head)

    def test_measurement_leg_runs_nightly(self):
        self.assertWired("nightly.yml", "accuracy",
                         "oracle_erf64_accuracy.py --measurement")

    def test_greeks_oracle_runs_nightly(self):
        self.assertWired("nightly.yml", "accuracy", "oracle_greeks_gate.py")

    def test_nightly_accuracy_job_installs_its_dependency(self):
        """The measurement leg FAILS without mpmath, so a missing install step
        turns the job red rather than skipping -- but red-for-the-wrong-reason
        is still a broken gate."""
        self.assertWired("nightly.yml", "accuracy", "requirements-oracle.txt")

    def test_nightly_accuracy_job_runs_daily(self):
        block = job_block("nightly.yml", "accuracy")
        live = "\n".join(live_lines(block))
        self.assertIn("0 3 * * *", live,
                      "the accuracy job must run on the daily cadence")

    def test_accuracy_failure_is_surfaced(self):
        """A guard that runs but that nothing gates on is only marginally
        better than one that never runs."""
        report = job_block("nightly.yml", "report")
        live = "\n".join(live_lines(report))
        self.assertIn("accuracy", live)
        self.assertIn("ACCURACY_RESULT", live)

    def test_local_gate_runs_both_legs(self):
        gate = (REPO_ROOT / "scripts/run_local_gate.py").read_text()
        self.assertIn("oracle_erf64_accuracy.py", gate)
        self.assertIn("--transcription", gate)
        self.assertIn("--measurement", gate)


if __name__ == "__main__":
    unittest.main(verbosity=2)
