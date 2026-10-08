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


class AbsoluteSweepCoverage(unittest.TestCase):
    def test_broad_grid_on_both_sides_is_retained(self):
        points = set(load_oracle().probe_points())
        for i in range(901):
            x = 6.5 * i / 900
            self.assertIn(x, points)
            self.assertIn(-x, points)

    def test_sweep_keeps_historical_dense_window_and_current_tail_coverage(self):
        points = load_oracle().probe_points()
        self.assertEqual(points, sorted(set(points)))
        self.assertGreaterEqual(len(points), 4451)
        for center in (-8.0, -4.0, -1.0, -0.5, 0.5, 1.0, 4.0, 8.0):
            for offset in range(-8, 9):
                self.assertIn(center + offset * math.ulp(center), points)


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
        self.mod.evaluate = lambda points, call: [
            math.erfc(-x / math.sqrt(2)) / 2 if call == "n_cdf64" else 0.0
            for x in points
        ]
        self.mod.worst = lambda points, values, fn, mp: (
            self.MEASURED[next(order)], 0.5, self.nans)
        fake = types.ModuleType("mpmath")
        fake.mp = types.SimpleNamespace(dps=15)
        fake.mpf = float
        fake.erf = math.erf
        fake.erfc = math.erfc
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

    def test_zero_left_tail_fails_relative_leg(self):
        self.mod.evaluate = lambda points, call: [0.0] * len(points)
        rc, report = self.run_with("3.3675e-16")
        self.assertEqual(rc, 1)
        self.assertTrue(any("left-tail" in e for e in report["errors"]), report["errors"])


class LeftTailRelativeEnforcement(unittest.TestCase):
    """`left_tail_relative`'s RELATIVE-MAGNITUDE verdict. shoals#140.

    `MeasurementEnforcement.test_zero_left_tail_fails_relative_leg` feeds
    `0.0`, which the `got <= 0` branch rejects before the relative comparison
    is ever reached. So the half of this guard that shoals#68's closing comment
    rests on -- "the relative-error oracle covers the negative tail" -- had no
    test, and four mutations of it survived the suite on `8ac87b1`:

      * `if relative > mp.mpf(LEFT_TAIL_RELATIVE_LIMIT):` -> `if False:`
      * `LEFT_TAIL_RELATIVE_LIMIT = "1e-12"` -> `"1.0"`
      * `LEFT_TAIL_POINTS` five points -> one
      * `worst_relative = max(worst_relative, relative)` -> `pass`

    Same class as shoals#64 (a guard that cannot fail) seen from the other
    side: there, nothing invoked the guard; here, the guard runs and its
    verdict is unreachable by any test. `MeasurementEnforcement`'s docstring
    records the identical defect on the absolute leg, found by a red-team pass
    on PR #108, and names its cause -- tests that exercise the helpers in
    isolation and never call the function that turns a bad measurement into a
    nonzero exit. This class is that function's missing caller.

    mpmath is stubbed with `math`, so this runs under the bare interpreter the
    per-PR job uses: the references are `erfc` at |x| in [4.24, 26.16]. `math.erfc`
    carries up to ~1.3e-13 of its own relative error at the far end, which does
    not matter here because `exact_at` and the leg under test use the SAME stub
    -- an unperturbed point therefore measures as exactly 0.0 relative, and the
    perturbations are 1e-9 or larger. A test that compared the stub against a
    high-precision reference would need real mpmath.
    """

    def setUp(self):
        self.mod = load_oracle()
        self.fake = types.ModuleType("mpmath")
        self.fake.mp = types.SimpleNamespace(dps=15)
        self.fake.mpf = float
        self.fake.erfc = math.erfc
        self.fake.sqrt = math.sqrt

    def exact_at(self, x):
        """The reference the leg itself computes, via the same stub."""
        return math.erfc(-x / math.sqrt(2)) / 2

    def values_with(self, overrides=None):
        """One value per LEFT_TAIL_POINTS entry, correct unless overridden."""
        overrides = overrides or {}
        return [overrides.get(x, self.exact_at(x))
                for x in self.mod.LEFT_TAIL_POINTS]

    def test_a_nan_at_each_left_tail_point_is_rejected(self):
        for x in self.mod.LEFT_TAIL_POINTS:
            with self.subTest(x=x):
                values = self.values_with({x: float("nan")})
                _, errors = self.mod.left_tail_relative(values, self.fake)
                self.assertEqual(len(errors), 1, errors)
                self.assertIn(f"n_cdf64({x})", errors[0])
                self.assertIn("nonpositive or nonfinite", errors[0])
                self.assertIn("nan", errors[0])

    def test_an_all_nan_left_tail_is_rejected(self):
        values = [float("nan")] * len(self.mod.LEFT_TAIL_POINTS)
        _, errors = self.mod.left_tail_relative(values, self.fake)
        self.assertEqual(len(errors), len(self.mod.LEFT_TAIL_POINTS), errors)
        for x, error in zip(self.mod.LEFT_TAIL_POINTS, errors, strict=True):
            self.assertIn(f"n_cdf64({x})", error)
            self.assertIn("nonpositive or nonfinite", error)

    def test_an_infinite_left_tail_result_is_rejected(self):
        # Infinity also exceeds the relative-error limit without isfinite.
        # The NaN tests above distinguish removal of the finiteness guard.
        x = self.mod.LEFT_TAIL_POINTS[3]
        _, errors = self.mod.left_tail_relative(
            self.values_with({x: float("inf")}), self.fake)
        self.assertEqual(len(errors), 1, errors)
        self.assertIn(f"n_cdf64({x})", errors[0])
        self.assertIn("nonpositive or nonfinite", errors[0])

    def test_a_missing_left_tail_result_is_rejected(self):
        x = self.mod.LEFT_TAIL_POINTS[3]
        _, errors = self.mod.left_tail_relative(
            self.values_with({x: None}), self.fake)
        self.assertEqual(len(errors), 1, errors)
        self.assertIn(f"n_cdf64({x})", errors[0])
        self.assertIn("None", errors[0])

    def test_correct_values_pass_and_report_a_nonzero_worst(self):
        """Positive control, and it also pins `worst_relative`. Every
        assertion below would hold vacuously against a function that always
        errored; and a frozen `worst_relative` of 0 would make the reported
        figure meaningless while every verdict still passed.
        """
        x = self.mod.LEFT_TAIL_POINTS[2]
        exact = self.exact_at(x)
        got = exact * (1 - 1e-14)
        # The expectation is derived from the ACTUAL doubles, not from the
        # 1e-14 that produced them: that product rounds, so the achieved
        # relative error differs from the nominal figure by ~0.14%, and
        # asserting the nominal one fails for a reason unrelated to the guard.
        induced = abs(got - exact) / exact
        values = self.values_with({x: got})
        worst, errors = self.mod.left_tail_relative(values, self.fake)
        self.assertEqual(errors, [])
        self.assertGreater(worst, 0.0,
                           "worst_relative was never updated from its initial 0")
        self.assertAlmostEqual(worst / induced, 1.0, places=9)

    def test_an_excessive_relative_error_is_rejected(self):
        """The branch that `if False:` deletes. 1e-9 is a thousand times the
        published limit and is still a perfectly finite, positive, plausible
        number -- so nothing else in the leg objects to it."""
        x = self.mod.LEFT_TAIL_POINTS[3]
        exact = self.exact_at(x)
        got = exact * (1 - 1e-9)
        induced = abs(got - exact) / exact
        values = self.values_with({x: got})
        worst, errors = self.mod.left_tail_relative(values, self.fake)
        self.assertEqual(len(errors), 1, errors)
        self.assertIn(str(x), errors[0])
        self.assertIn("relative error", errors[0])
        self.assertIn(self.mod.LEFT_TAIL_RELATIVE_LIMIT, errors[0])
        self.assertAlmostEqual(worst / induced, 1.0, places=9)

    def test_a_positive_near_zero_is_rejected(self):
        """shoals#68's symptom, in the form that slips past the `got <= 0`
        branch. The defect that issue reported was `n_cdf64` returning exactly
        `0.0`; a kernel that returns the smallest subnormal instead is just as
        wrong and is positive and finite.

        This is also what pins the LIMIT rather than merely the branch: the
        relative error here is just under 1, so a limit of `1.0` would accept
        it. That mutation survives the rest of the suite.
        """
        x = self.mod.LEFT_TAIL_POINTS[-1]
        values = self.values_with({x: 5e-324})
        worst, errors = self.mod.left_tail_relative(values, self.fake)
        self.assertEqual(len(errors), 1, errors)
        self.assertIn(str(x), errors[0])
        # Measured: exactly 1.0. The smallest subnormal is negligible beside
        # the reference at `LEFT_TAIL_POINTS[-1]` -- 5.73e-300 now that the
        # sweep reaches -37.0, and 1.13e-19 when it stopped at -9.0 -- so the
        # relative error rounds to unity either way (5e-324 / 5.73e-300 is
        # 8.7e-25).
        self.assertEqual(worst, 1.0,
                         "a near-zero return must measure as 100% relative")
        # THIS is the assertion that pins the LIMIT rather than the branch. The
        # comparison in the leg is `relative > limit`, so a limit of exactly
        # 1.0 would NOT reject a relative error of 1.0 -- `1.0 > 1.0` is False.
        # That mutation survives every other test in this file.
        self.assertLess(float(self.mod.LEFT_TAIL_RELATIVE_LIMIT), 1.0,
                        "a limit of 1.0 or looser accepts a near-zero return, "
                        "which is the shoals#68 symptom")

    def test_the_limit_rejects_the_errors_shoals68_reported(self):
        """The limit is only meaningful against the magnitudes it exists to
        catch. shoals#68 measured 2.3e-6 relative at x = -7 and 1.8e-2 at
        x = -8 on the pre-repair kernel; both must fail at the published
        limit, or the guard would have been green on the original defect."""
        # `LEFT_TAIL_RELATIVE_LIMIT` is not a PUBLISHED FLOOR: the
        # transcription leg polices only `>= N.NNNNe-NN` claims and this is not
        # one, so nothing in that leg constrains it. An earlier revision of this
        # comment went further and said `1e-12` "has no other carrier in the
        # tree", which is only true under this script's own term of art --
        # docs/CHELIS_SURFACE.md states the limit in prose, and
        # `test_the_published_doc_states_the_same_limit` below is what couples
        # the two. These tests bound the value from both sides rather than pin
        # it exactly; the review measured that it can be loosened 500x, to
        # 5e-10, without any of them objecting.
        limit = float(self.mod.LEFT_TAIL_RELATIVE_LIMIT)
        for reported in (2.3e-6, 1.8e-2):
            self.assertGreater(reported, limit)
        for x, reported in ((-7.0, 2.3e-6), (-8.0, 1.8e-2)):
            self.assertIn(x, self.mod.LEFT_TAIL_POINTS)
            values = self.values_with({x: self.exact_at(x) * (1 - reported)})
            _, errors = self.mod.left_tail_relative(values, self.fake)
            self.assertEqual(len(errors), 1, errors)
            self.assertIn(str(x), errors[0])

    def test_the_swept_points_cover_the_issues_own_table(self):
        """Shrinking `LEFT_TAIL_POINTS` to one entry is a surviving mutation.
        shoals#68's table runs -6 through -9, and those are the magnitudes the
        closing claim is about."""
        points = self.mod.LEFT_TAIL_POINTS
        for x in (-6.0, -7.0, -8.0, -8.5, -9.0):
            self.assertIn(x, points)
        self.assertTrue(all(x < 0 for x in points), points)

    def test_the_sweep_has_no_gap_a_saturation_could_hide_in(self):
        """Endpoints are not coverage. Pinning only the five table points and
        `min == -37.0` left the band between them unlocked: deleting the seven
        intermediate points kept the suite green, and a kernel that saturated
        at, say, -20 would then pass unnoticed -- which is the whole argument
        the extension to -37 rests on.

        Pinned as a PROPERTY rather than a literal list, so legitimate
        re-spacing stays possible: no two consecutive swept points may be more
        than 5 units apart. The shipped sweep's largest gap is exactly 5
        (-15 to -20, -20 to -25, -25 to -30, -30 to -35)."""
        points = sorted(self.mod.LEFT_TAIL_POINTS, reverse=True)
        gaps = [round(a - b, 10) for a, b in zip(points, points[1:])]
        self.assertTrue(gaps, "the sweep has fewer than two points")
        self.assertLessEqual(
            max(gaps), 5.0,
            f"the sweep has a gap of {max(gaps)} units, wide enough for a "
            f"saturation regression to hide in: {points}")

    def test_below_the_swept_range_is_unguarded_and_that_is_declared(self):
        """Not a defect -- a boundary, pinned so it is decided rather than
        discovered. Nothing in this leg constrains x below
        `min(LEFT_TAIL_POINTS)`, and that floor is a measured choice: the kernel
        holds relative error at or under 1.4e-16 to x = -37.5, then the RESULT
        leaves the normal doubles between -37.5 and -37.6 and accuracy collapses
        (3.1e-9 at -38.0, 4.8e-2 at -38.4, exactly 0.0 from about -38.5). -37.0
        is one step clear of that cliff so an upstream change to subnormal
        handling cannot redden this leg with nothing wrong in Shoals.

        The rationale lives on `LEFT_TAIL_POINTS` itself, which is where
        someone changing the range will be standing."""
        self.assertEqual(min(self.mod.LEFT_TAIL_POINTS), -37.0,
                         "the guarded range changed; re-measure at the pin and "
                         "update this test together with BOTH carriers -- the "
                         "boundary comment above LEFT_TAIL_POINTS and the "
                         "accuracy section of docs/CHELIS_SURFACE.md, which "
                         "states the point count and the -37 floor")
        # The floor must stay clear of the subnormal onset between -37.5 and
        # -37.6; a sweep reaching past it fails on representability, not on a
        # kernel defect.
        self.assertGreater(min(self.mod.LEFT_TAIL_POINTS), -37.5,
                           "the sweep reaches the subnormal cliff, where the "
                           "limit cannot be met for reasons outside Shoals")

    def test_an_overshoot_is_rejected_as_well_as_an_undershoot(self):
        """The guard is on |error|, and before this test every override in the
        class undershot (`exact * (1 - eps)`). With the sign held constant,
        rewriting `abs(got - exact) / exact` as `(exact - got) / exact` survived
        the whole suite: an overshooting kernel produces a NEGATIVE relative
        error, `negative > limit` is False, no error is recorded, and
        `worst_relative` comes back 0.0 while the nightly leg exits green.

        That is shoals#68's consequence with the sign flipped, and the fourth
        constant-axis defect found in this file -- which is why the fix is a
        varied axis rather than a patch at one point.
        """
        x = self.mod.LEFT_TAIL_POINTS[2]
        exact = self.exact_at(x)
        got = exact * (1 + 1e-9)
        self.assertGreater(got, exact, "the fixture must overshoot")
        induced = abs(got - exact) / exact
        worst, errors = self.mod.left_tail_relative(
            self.values_with({x: got}), self.fake)
        self.assertEqual(len(errors), 1, errors)
        self.assertIn(str(x), errors[0])
        self.assertGreater(worst, 0.0,
                           "an overshoot must register as a positive magnitude")
        self.assertAlmostEqual(worst / induced, 1.0, places=9)

    def test_every_swept_point_is_actually_measured(self):
        """Membership in `LEFT_TAIL_POINTS` is not measurement, and the
        difference was unpinned: slicing the zip to `LEFT_TAIL_POINTS[1:]` and
        `values[1:]` left x = -6.0 silently unevaluated and the suite green.
        `test_the_swept_points_cover_the_issues_own_table` cannot see that --
        it asserts the tuple's contents, not that each entry is reached.

        Perturbing EVERY index in turn rather than adding a case for index 0:
        this kills any slice at any position, and it cannot go stale when the
        swept range changes.

        THE SIGN ALTERNATES BY INDEX. Holding it positive here would leave one
        cell of direction x position unprobed -- a mutation sparing exactly the
        one index the overshoot test uses survived round 2 for that reason. The
        two axes now vary together, which is the fifth time a constant axis has
        had to be closed in this file.
        """
        for i, x in enumerate(self.mod.LEFT_TAIL_POINTS):
            with self.subTest(index=i, x=x):
                sign = -1.0 if i % 2 == 0 else 1.0
                values = self.values_with(
                    {x: self.exact_at(x) * (1 + sign * 1.8e-2)})
                worst, errors = self.mod.left_tail_relative(values, self.fake)
                self.assertEqual(
                    len(errors), 1,
                    f"index {i} (x = {x}) is in LEFT_TAIL_POINTS but a wrong "
                    f"value there produced {len(errors)} errors: {errors}")
                self.assertIn(str(x), errors[0])
                self.assertGreater(worst, 0.0)

    def test_the_published_doc_states_the_same_limit(self):
        """The one coupling the transcription leg cannot provide.

        `LEFT_TAIL_RELATIVE_LIMIT` is a bare constant, and
        `docs/CHELIS_SURFACE.md` states it in prose. Nothing joined them:
        changing the constant to 1e-11 while the doc still said 1e-12 left both
        the 54-test suite AND the transcription leg green, because that leg only
        discovers `>= N.NNNNe-NN` floor claims and this is not one. Same drift
        class the transcription leg exists to prevent for the floors, one
        quantity over.

        The floor magnitude is locked too, since the same sentence carries it.
        """
        doc = (REPO_ROOT / "docs" / "CHELIS_SURFACE.md").read_text(
            encoding="utf-8")
        limit = self.mod.LEFT_TAIL_RELATIVE_LIMIT
        self.assertIn(
            f"limit of {limit}", doc,
            f"docs/CHELIS_SURFACE.md does not state the configured limit "
            f"{limit!r}; the constant and the doc have drifted apart")
        floor = int(-min(self.mod.LEFT_TAIL_POINTS))
        self.assertIn(
            f"-{floor}", doc,
            f"docs/CHELIS_SURFACE.md does not mention the swept floor -{floor}")

    def test_a_values_length_mismatch_fails_loudly(self):
        """`zip(..., strict=True)` is load-bearing: a short response would
        otherwise measure a prefix and report a clean verdict over points that
        were never evaluated."""
        with self.assertRaises(ValueError):
            self.mod.left_tail_relative(self.values_with()[:-1], self.fake)


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
        with self.assertRaises(ValueError):
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
