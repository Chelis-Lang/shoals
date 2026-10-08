#!/usr/bin/env python3
"""Check Shoals' `erf64`/`n_cdf64` accuracy, including left-tail relative error.

Two independent legs, because they have different prerequisites and therefore
different homes in CI:

* ``--transcription`` (stdlib only, no toolchain, instant). Parses the floors
  out of the published accuracy table in ``docs/CHELIS_SURFACE.md`` and requires
  every *other* place in the tracked tree that states one of those floors to
  state the same number. This is the leg that closes shoals#64's transcription
  hop, and it is cheap enough for the per-PR ``contract-gate`` job.
* ``--measurement`` (needs mpmath and the pinned ``chelis``; minutes). Measures
  the compiled kernel against a high-precision reference and requires each
  published floor to be a TIGHT floor of what was measured.

Default runs both. Exit 0 only if every requested leg passes.

WHAT EACH LEG CANNOT DO, stated because shoals#64 was a guard that looked like
it covered more than it did:

* The transcription leg proves the carriers AGREE. It cannot prove they are
  right: rewrite every carrier to the same wrong number and this leg is green.
  Only the measurement leg constrains the value itself.
* The measurement leg proves the published absolute floor is tight for the
  points it sampled. A separate relative leg checks `n_cdf64` at negative
  tail inputs, where an absolute sweep would miss cancellation (shoals#68).

MEASURE IN BINARY: the error is `mpf(f64_result) - erf(mpf(exact_f64_input))` at
extended precision. `chelis eval --json` hands back the exact f64 as hex bits
(schema 3's tagged carrier), so no decimal round trip enters the measurement.
Comparing `mpf(repr(result))` against `mpf(decimal_input)` would measure a
decimal round trip instead (~0.04 ulp near the argmax), and rounding the
reference to a double first would quantise every error to a multiple of an ulp.

FLOOR, NOT MAXIMUM: the error is jagged at ulp scale, so any grid reports only
the worst point it lands on, and a finer but differently spaced refinement can
miss the argmax. Every published figure is therefore a floor.

PUBLISH A ROUNDED FIGURE, NOT THE ORACLE'S OWN FULL-PRECISION OUTPUT. The
`--json` report prints `worst_abs` at full repr width (16 significant digits).
That string is NOT publishable: `Decimal(float)` is the exact binary value, and
the shortest round-tripping repr sits just ABOVE it, so pasting it in is
correctly rejected as "not a floor". Publish a rounded-down figure -- four or
five significant digits, as the table does.

A FLOOR ROUNDS DOWN, AND MUST BE TIGHT. Two different mistakes are possible and
both are caught. Rounding a floor UP puts it above the observation it claims to
sit under (the first `n_cdf64` figure written here was 1.9496e-16, the measured
1.949591e-16 rounded up to four places). Rounding it absurdly DOWN -- 1.0e-30 --
is still technically a floor, which is why a one-sided `published <= measured`
check is not enough: shoals#64's own demonstration mutation passes it. So the
requirement is equality with the measurement truncated toward zero at the
published figure's OWN significant-digit count. You may publish as few digits as
you like; the digits you do publish must be the measurement's.

Usage:
    oracle_erf64_accuracy.py                  # both legs
    oracle_erf64_accuracy.py --transcription  # offline leg only (per-PR CI)
    oracle_erf64_accuracy.py --measurement    # measured leg only (nightly CI)
    oracle_erf64_accuracy.py --json           # machine-readable summary
"""

from __future__ import annotations

import argparse
import json
import math
import os
import re
import struct
import subprocess
import sys
from decimal import Context, Decimal, ROUND_FLOOR
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
CHELIS = os.environ.get("CHELIS_BIN") or "chelis"
# Generated inside the package so `chelis eval` resolves Shoals.Pricing.
GEN = REPO_ROOT / ".gate-tmp" / "erf64accuracy.ch"

# The kernels this oracle governs, and the published table that declares their
# floors. The table is the single authority for the NUMBER; this script is the
# authority for whether that number is true.
KERNELS = ("erf64", "n_cdf64")
ACCURACY_DOC = Path("docs/CHELIS_SURFACE.md")

# A floor claim, anywhere in the tracked tree, looks like `>= N.NNNNe-NN`.
#
# ANY negative exponent, deliberately. A band restricted to the exponents an
# f64 absolute-error floor can actually occupy (-15..-18) would silently IGNORE
# a carrier rewritten to 1.0e-30 -- shoals#64's own demonstration mutation, and
# a figure 10^14 better than anything measurable.
#
# THE COST, stated plainly because it is a real one: this predicate keys on the
# `>=` MARKER, not on the governed kernel, so ANY unrelated floor inequality in
# a tracked file is read as a claim about these kernels and fails the per-PR
# gate -- a relative tolerance floored at 1e-6, say, or a finite-difference
# step floored at 1.0e-8, each written as an inequality rather than as prose.
# (Spelled here WITHOUT the marker, for the reason the note below gives.)
# On the tree as it stands there are
# no such lines, but that is a measurement of today's tree, NOT a property of
# the design, and the ASCII form of prose already in `CHANGELOG.md` (which
# spells it with a unicode >=) would trip it. The diagnostic teaches the
# `within ...` convention, so it is recoverable rather than mysterious.
#
# The symmetric gap: a floor claim spelled with unicode >=, `&gt;=`, "at least",
# a line break, or a non-exponent decimal is MISSED. Both halves are the same
# design choice seen from two sides, and the fix for one must not be a naive
# widening of the other -- adding unicode >= to this pattern would immediately
# false-positive on that existing CHANGELOG prose. Keying discovery on a window
# that names a governed kernel is the shape that fixes both; tracked as
# follow-up work rather than patched here.
#
# Note that this pattern scans THIS FILE too, and that is deliberate: a guard
# exempt from its own rule is how the next stale figure hides. It is also why
# the examples in these comments are written WITHOUT the `>=` -- spelling one
# with it would make this docstring a live claim about the kernel.
#
# The same applies to HISTORICAL documents. `CHANGELOG.md` records figures that
# were true of a past release, and rewriting released history when the kernel
# changes would be wrong, so a figure there is written as prose
# ("a published floor of 3.3675e-16") rather than as a claim (`>= N.NNNNe-16`).
# This is a convention, not a path exemption: there is no allowlist, and a file
# that DOES make a live floor claim is held to it wherever it lives.
#
# This pattern is why there is NO hand-maintained list of carrier files here. A
# subset is how a stale figure survives a repair and a count rots the moment a
# carrier is added, so the carriers are DISCOVERED by `git grep` on every run.
# The `>=` is load-bearing and semantic, not cosmetic: a floor claim is exactly
# what this oracle validates. It is what separates these figures from the
# derivative residuals in `research/`, which are stated as "within 5.6e-17" --
# a different quantity that this oracle does not measure and must not police.
FLOOR_CLAIM = re.compile(r">=[ \t]*([0-9]+\.?[0-9]*[eE]-[0-9]+)")
FLOOR_CLAIM_GREP = r">=[[:space:]]*[0-9]+\.?[0-9]*[eE]-[0-9]+"

# `chelis eval` overflows its stack on a single list literal of a few thousand
# elements (rc=-6, "thread 'main' has overflowed its stack"), so the sweep is
# batched. Not a kernel problem and not worked around silently: it is a real
# evaluator limit on literal size, hit at ~4400 elements on this pin.
BATCH = 800
# WHERE THE RELATIVE LEG SWEEPS, AND WHY IT STOPS WHERE IT DOES.
#
# The first five points are shoals#68's own table -- the magnitudes that issue
# measured on the cancelling kernel (2.3e-6 relative at -7, 1.8e-2 at -8,
# exactly 0.0 below about -8.3). They pin the reported defect.
#
# The rest exist because those five do not cover the defect CLASS. shoals#68's
# failure mode was early saturation, and the pre-#136 kernel's silent-zero band
# began at x = -8.485 -- inside the original window. A regression that saturated
# anywhere between -9 and the representability limit would have passed a
# five-point sweep untouched.
#
# -37.0 IS THE FLOOR, and it is a measured choice rather than a round number.
# `standard_normal_cdf` stays under ONE ULP across this whole range -- worst
# observed 2.17e-16 (0.977 ulp) at x = -26.95 over a 631-point scan at step
# 0.05, i.e. about four orders inside the limit below -- because `erfc` carries
# the negative tail directly. At the thirteen SWEPT points specifically the
# worst is 9.37e-17, at x = -9.0. Both figures are maxima over a grid, not
# proofs: an earlier revision of this comment said "at or under 1.4e-16 all the
# way to -37.5", which is true at the swept points and false off them (15 of
# those 631 points exceed it). Zero points of the 631 exceed the limit. Past that the RESULT, not the kernel, runs out of
# room: the true value leaves the normal doubles between -37.5 and -37.6, and
# measured at 0.18.13 the relative error is 3.1e-9 at x = -38.0, 4.8e-2 at
# -38.4, and the call returns exactly 0.0 from about -38.5 (where the true value
# itself rounds to zero below x = -38.4854).
#
# So the sweep stops at -37.0 rather than -37.5: one step clear of the cliff, so
# that an upstream change to subnormal handling cannot turn this leg red without
# anything in Shoals being wrong. Measured margins, 0.18.13, 80-dps reference:
# 9.4e-17 at -9, 8.1e-17 at -10, 1.5e-17 at -20, 2.4e-17 at -30, 6.7e-17 at -37.
#
# BELOW -37.0 IS DELIBERATELY UNGUARDED, and that is a decision, not an
# oversight: the boundary is a property of the f64 subnormal range and of the
# Chelis builtin, so it is upstream's to move. Re-measure before extending.
LEFT_TAIL_POINTS = (-6.0, -7.0, -8.0, -8.5, -9.0, -10.0, -12.0, -15.0,
                    -20.0, -25.0, -30.0, -35.0, -37.0)
LEFT_TAIL_RELATIVE_LIMIT = "1e-12"

# `chelis eval --json` schema versions this script knows how to read. An
# unknown version is a LOUD failure, never a duck-typed guess: schema 2 emitted
# `{"type": "float64", "value": 0.5}` and schema 3 (chelis 0.18.7) replaced it
# with the tagged carrier `{"type": "scalar", "value": {"dtype", "bits"}}`.
# Reading 3 as 2 is what killed this script for three pin bumps -- it died with
# `TypeError: cannot create mpf from {'dtype': 'f64', ...}` after 90 seconds of
# real evaluation, and nothing noticed because nothing invoked it (shoals#64).
SUPPORTED_EVAL_SCHEMAS = (2, 3, 4)


# --------------------------------------------------------------------------
# transcription leg: what the repository publishes, and whether it agrees
# --------------------------------------------------------------------------

class Published:
    """One kernel's published floor, as spelled in the authoritative table."""

    def __init__(self, kernel: str, spelling: str, source: str) -> None:
        self.kernel = kernel
        self.spelling = spelling
        self.source = source
        self.value = Decimal(spelling)
        # Significant digits of the spelling: "3.3675e-16" -> 5. This is the
        # precision the publication claims, and the precision the measurement
        # is held to.
        mantissa = spelling.lower().split("e")[0].replace(".", "").lstrip("0")
        self.sig_digits = len(mantissa.rstrip()) or 1


def tracked_text_files() -> list[str]:
    done = subprocess.run(
        ["git", "grep", "-l", "-I", "-E", FLOOR_CLAIM_GREP],
        cwd=REPO_ROOT, capture_output=True, text=True, check=False,
    )
    # rc 1 means "no matches", which is itself a failure for this oracle (the
    # floors are published nowhere) -- reported by the caller, not swallowed.
    if done.returncode not in (0, 1):
        raise SystemExit(
            f"FAIL: git grep for floor claims failed (rc={done.returncode})\n"
            f"{done.stderr[:500]}"
        )
    return [p for p in done.stdout.splitlines() if p]


def parse_published() -> tuple[dict[str, Published], list[str]]:
    """Read each kernel's floor out of the authoritative accuracy table.

    A missing or unparseable row is a failure, not a skip: a row that silently
    vanishes would otherwise take its own guard with it.
    """
    errors: list[str] = []
    doc = REPO_ROOT / ACCURACY_DOC
    if not doc.is_file():
        return {}, [f"{ACCURACY_DOC}: the published accuracy table is missing"]

    out: dict[str, Published] = {}
    lines = doc.read_text(encoding="utf-8").splitlines()
    for kernel in KERNELS:
        row_re = re.compile(rf"^\|\s*`{re.escape(kernel)}`\s*\|")
        rows = [ln for ln in lines if row_re.match(ln)]
        if len(rows) != 1:
            errors.append(
                f"{ACCURACY_DOC}: expected exactly one accuracy-table row for "
                f"`{kernel}`, found {len(rows)}"
            )
            continue
        found = FLOOR_CLAIM.findall(rows[0])
        distinct = sorted(set(found))
        if len(distinct) != 1:
            errors.append(
                f"{ACCURACY_DOC}: `{kernel}`'s row must state exactly one floor "
                f"claim (`>= N.NNNNe-16`), found {len(distinct)}: {distinct}"
            )
            continue
        out[kernel] = Published(kernel, distinct[0], f"{ACCURACY_DOC} (`{kernel}` row)")
    return out, errors


def attributed_kernel(lines: list[str], idx: int) -> str | None:
    """Which kernel a floor claim is about, when the context says unambiguously.

    A markdown table row is attributed by its own first cell, so the two
    adjacent accuracy rows do not sit in each other's context window and
    degrade to a membership check -- which would let their figures be swapped.

    Otherwise: word-bounded so `erf64_erfc_abs` is not read as `erf64`, and a
    window, because the claim and the kernel name are not always on one line
    (`UPSTREAM_BUGS.md` names the kernel a line above the figure).
    """
    for kernel in KERNELS:
        if re.match(rf"^\|\s*`{re.escape(kernel)}`\s*\|", lines[idx]):
            return kernel
    window = "\n".join(lines[max(0, idx - 2):idx + 3])
    hits = {
        k for k in KERNELS
        if re.search(rf"(?<![A-Za-z0-9_]){re.escape(k)}(?![A-Za-z0-9_])", window)
    }
    return hits.pop() if len(hits) == 1 else None


def run_transcription(verbose: bool = True) -> tuple[int, dict]:
    published, errors = parse_published()
    carriers: list[dict] = []

    for rel in tracked_text_files():
        lines = (REPO_ROOT / rel).read_text(encoding="utf-8").splitlines()
        for idx, line in enumerate(lines):
            for literal in FLOOR_CLAIM.findall(line):
                kernel = attributed_kernel(lines, idx)
                carriers.append({
                    "file": rel, "line": idx + 1,
                    "literal": literal, "attributed_kernel": kernel,
                })
                value = Decimal(literal)
                known = {k: p.value for k, p in published.items()}
                if kernel is not None and kernel in published:
                    if value != published[kernel].value:
                        errors.append(
                            f"{rel}:{idx + 1}: states `>= {literal}` for "
                            f"`{kernel}`, but {published[kernel].source} "
                            f"publishes `>= {published[kernel].spelling}`"
                        )
                elif value not in known.values():
                    errors.append(
                        f"{rel}:{idx + 1}: states `>= {literal}`, which is not "
                        f"any published floor ({', '.join(f'{k}: {v}' for k, v in known.items())}). "
                        f"If the kernel changed, update {ACCURACY_DOC} and every "
                        f"carrier together. If this is a claim about a DIFFERENT "
                        f"quantity, state it as a bound (`within ...`) rather than "
                        f"a floor (`>= ...`) -- that is how the derivative "
                        f"residuals in `research/` stay out of this oracle's scope."
                    )

    if verbose:
        for kernel in KERNELS:
            pub = published.get(kernel)
            print(f"{kernel:9s} published floor {pub.spelling if pub else '(UNPARSEABLE)'}"
                  f" ({pub.sig_digits if pub else '-'} sig digits)")
        print(f"\n{len(carriers)} floor claim(s) discovered in "
              f"{len({c['file'] for c in carriers})} tracked file(s):")
        for c in sorted(carriers, key=lambda c: (c["file"], c["line"])):
            who = c["attributed_kernel"] or "unattributed"
            print(f"  {c['file']}:{c['line']}  >= {c['literal']}  [{who}]")

    summary = {
        "published": {k: {"spelling": p.spelling, "sig_digits": p.sig_digits}
                       for k, p in published.items()},
        "carriers": carriers,
        "errors": errors,
    }
    if verbose:
        print()
        for e in errors:
            print(f"FAIL: {e}")
        if not errors:
            print("PASS: transcription -- every published floor is stated "
                  "consistently everywhere it appears.")
    return (1 if errors else 0), summary


# --------------------------------------------------------------------------
# measurement leg: whether those published floors are true and tight
# --------------------------------------------------------------------------

def probe_points() -> list[float]:
    """Retain the broad historical sweep and the builtin-kernel neighborhoods."""
    pts = {i / 20.0 for i in range(-200, 201)}
    for center in (-8.0, -4.0, -1.0, -0.5, 0.5, 1.0, 4.0, 8.0):
        step = math.ulp(center)
        for offset in range(-8, 9):
            pts.add(center + offset * step)
    pts.update((-0.7170090691949448, 0.7700537662469848, -8.5, -9.0))
    # The reduced 0.05-spaced sweep missed larger errors at -3.741111...
    # and 0.736666... . Retain the original grid on both sides of zero.
    historical = {6.5 * i / 900 for i in range(901)}
    historical.update(0.507001975 + i * 2.0**-53 for i in range(-600, 601))
    for boundary in (0.5, 4.0, 6.0):
        historical.update(boundary + k * 2.0**-45 for k in range(-20, 21))
    pts.update(historical)
    pts.update(-x for x in historical)
    return sorted(pts)


def decode_scalar(entry: dict, schema: int) -> float:
    """One f64 off the eval wire, exactly, for a known schema version."""
    if schema == 2:
        return entry["value"]
    if entry.get("type") != "scalar":
        raise ValueError(f"expected a scalar on the eval wire: {entry!r}")
    return decode_f64(entry["value"])


def evaluate(points: list[float], call: str) -> list[float]:
    out: list[float] = []
    for i in range(0, len(points), BATCH):
        out.extend(_evaluate_batch(points[i:i + BATCH], call))
    if len(out) != len(points):
        # `worst` zips points with values, so a short response would be
        # SILENTLY ignored while the report still claimed the full sweep. It
        # happens to fail closed today only because the argmax sits mid-sweep;
        # a truncated prefix that happened to include the argmax would PASS
        # with most points unmeasured, and would blame the published figure
        # rather than the sweep.
        raise SystemExit(
            f"FAIL: {call} returned {len(out)} values for {len(points)} probe "
            f"points. The sweep is not measuring what it reports; this is a "
            f"wire or evaluator fault, not a wrong published figure."
        )
    return out


def decode_f64(value: object) -> float:
    """Decode only the evaluator's exact tagged f64 bits."""
    if not isinstance(value, dict):
        raise ValueError(f"unexpected untagged f64 result: {value!r}")
    bits = value.get("bits")
    if (
        set(value) != {"dtype", "bits"}
        or value.get("dtype") != "f64"
        or not isinstance(bits, str)
        or re.fullmatch(r"[0-9a-fA-F]{16}", bits) is None
    ):
        raise ValueError(f"unexpected tagged f64 result: {value!r}")
    number = struct.unpack(">d", bytes.fromhex(bits))[0]
    if not math.isfinite(number):
        raise ValueError(f"non-finite f64 result for finite oracle input: {value!r}")
    return number


def decoder_self_test() -> None:
    for bits, expected in (
        ("3ff0000000000000", 1.0),
        ("bff0000000000000", -1.0),
        ("0000000000000001", math.ldexp(1.0, -1074)),
    ):
        got = decode_f64({"dtype": "f64", "bits": bits})
        if got != expected:
            raise ValueError(f"f64 decoder changed {bits}: {got!r}")
    for bad in (
        {"dtype": "f32", "bits": "3ff0000000000000"},
        {"dtype": "f64", "bits": "3ff"},
        {"dtype": "f64", "bits": "7ff0000000000000"},
        {"dtype": "f64", "bits": "7ff8000000000000"},
        0.0,
        1,
        False,
        None,
    ):
        try:
            decode_f64(bad)
        except ValueError:
            continue
        raise ValueError(f"f64 decoder accepted invalid value {bad!r}")


def _evaluate_batch(points: list[float], call: str) -> list[float]:
    GEN.parent.mkdir(parents=True, exist_ok=True)
    lits = ", ".join(f"{call}(cast({x!r}, f64))" for x in points)
    GEN.write_text(
        "module Shoals.Gate_Tmp.Erf64Accuracy\n"
        f"import Shoals.Pricing ({call})\n"
        f"probe = [{lits}]\n"
    )
    subprocess.run([CHELIS, "fmt", "--inplace", str(GEN)], cwd=REPO_ROOT,
                   capture_output=True, check=False)
    done = subprocess.run(
        [CHELIS, "eval", "--file", str(GEN), "--json", "--timeout", "900"],
        cwd=REPO_ROOT, capture_output=True, text=True, check=False,
    )
    if done.returncode != 0 or not done.stdout.strip().startswith("{"):
        raise SystemExit(
            f"FAIL: {call} probe did not evaluate (rc={done.returncode})\n"
            f"stderr: {done.stderr[:700]}\nstdout: {done.stdout[:300]}"
        )
    doc = json.loads(done.stdout)
    schema = doc.get("schema_version")
    if schema not in SUPPORTED_EVAL_SCHEMAS:
        raise SystemExit(
            f"FAIL: `chelis eval --json` reported schema_version={schema!r}, "
            f"which this oracle does not know how to read (supported: "
            f"{list(SUPPORTED_EVAL_SCHEMAS)}). Teach `decode_scalar` the new "
            f"carrier shape and re-measure; do NOT guess at it. Reading a new "
            f"schema as an old one is how this script spent three pin bumps "
            f"crashing after 90 seconds of work (shoals#64)."
        )
    return [decode_scalar(e, schema)
            for e in doc["roots"][0]["value"]["value"]]


def floor_at(value: float, sig_digits: int) -> Decimal:
    """`value` truncated toward zero to `sig_digits` significant digits.

    `Decimal(float)` is the exact binary value, so no decimal round trip enters
    the comparison. ROUND_FLOOR on a positive magnitude is truncation.
    """
    return Context(prec=sig_digits, rounding=ROUND_FLOOR).create_decimal(
        Decimal(value)
    )


def worst(points, values, fn, mp):
    top, at, nans = mp.mpf(0), points[0], 0
    for x, got in zip(points, values):
        if got is None or got != got:  # NaN on the wire
            nans += 1
            continue
        err = abs(mp.mpf(got) - fn(mp.mpf(x)))
        if err > top:
            top, at = err, x
    return top, at, nans


def left_tail_relative(values, mp):
    """Measure each left-tail sample against a high-precision erfc reference.

    Sweeps `LEFT_TAIL_POINTS` and flags any |relative error| above
    `LEFT_TAIL_RELATIVE_LIMIT`. The range and its floor are a measured choice;
    the reasoning is on `LEFT_TAIL_POINTS`. Below that floor is unguarded.
    """
    errors = []
    worst_relative = mp.mpf(0)
    for x, got in zip(LEFT_TAIL_POINTS, values, strict=True):
        exact = mp.erfc(-mp.mpf(x) / mp.sqrt(2)) / 2
        if got is None or not math.isfinite(got) or got <= 0:
            errors.append(f"n_cdf64({x}): nonpositive or nonfinite left-tail result {got!r}")
            continue
        relative = abs(mp.mpf(got) - exact) / exact
        worst_relative = max(worst_relative, relative)
        if relative > mp.mpf(LEFT_TAIL_RELATIVE_LIMIT):
            errors.append(
                f"n_cdf64({x}): relative error {float(relative):.6e} exceeds "
                f"{LEFT_TAIL_RELATIVE_LIMIT}"
            )
    return float(worst_relative), errors


def run_measurement(published: dict[str, Published], verbose: bool = True
                    ) -> tuple[int, dict]:
    try:
        import mpmath as mp
    except ImportError:
        # NOT a skip. An oracle that reports success because its reference
        # implementation is absent is worse than no oracle: shoals#64.
        print(
            "FAIL: oracle_erf64_accuracy -- mpmath is not installed, so the "
            "published floors cannot be measured. Install it "
            "(`python3 -m pip install -r scripts/requirements-oracle.txt`) or "
            "run only the offline leg with `--transcription`.",
            file=sys.stderr,
        )
        return 1, {"errors": ["mpmath not installed"]}

    mp.mp.dps = 60
    points = probe_points()
    results: dict[str, dict] = {}
    errors: list[str] = []

    for name, fn in (
        ("erf64", mp.erf),
        ("n_cdf64", lambda x: (1 + mp.erf(x / mp.sqrt(2))) / 2),
    ):
        values = evaluate(points, name)
        err, at, nans = worst(points, values, fn, mp)
        measured = float(err)
        record = {
            "worst_abs": measured,
            "worst_ulp_of_one": float(err / (mp.mpf(2) ** -52)),
            "at": at,
            "points": len(points),
            "nan_points": nans,
        }
        if nans:
            errors.append(
                f"{name}: {nans} of {len(points)} probe points came back NaN; "
                f"the sweep is not measuring what it claims to"
            )
        pub = published.get(name)
        if pub is None:
            errors.append(
                f"{name}: measured {measured:.6e} but no published floor was "
                f"parsed, so there is nothing to check it against"
            )
        else:
            truncated = floor_at(measured, pub.sig_digits)
            record |= {
                "published_floor": pub.spelling,
                "published_sig_digits": pub.sig_digits,
                "measurement_truncated_to_published_precision": str(truncated),
                "published_is_a_floor": pub.value <= Decimal(measured),
                "published_is_tight": truncated == pub.value,
            }
            if not record["published_is_a_floor"]:
                errors.append(
                    f"{name}: published floor {pub.spelling} EXCEEDS the worst "
                    f"value measured, {measured:.6e}. A floor above every "
                    f"observation is not a floor."
                )
            elif not record["published_is_tight"]:
                errors.append(
                    f"{name}: published floor {pub.spelling} is a floor but not "
                    f"a TIGHT one. The measurement {measured:.6e} truncated to "
                    f"{pub.sig_digits} significant digits is {truncated}. "
                    f"Publish that, or publish fewer digits -- an understated "
                    f"floor is still technically true and still misleading."
                )
        results[name] = record

    tail_values = evaluate(list(LEFT_TAIL_POINTS), "n_cdf64")
    worst_relative, tail_errors = left_tail_relative(tail_values, mp)
    errors.extend(tail_errors)
    results["n_cdf64"]["left_tail_worst_relative"] = worst_relative
    results["n_cdf64"]["left_tail_points"] = list(LEFT_TAIL_POINTS)

    if verbose:
        for name, r in results.items():
            print(
                f"{name:9s} worst observed {r['worst_abs']:.6e} "
                f"({r['worst_ulp_of_one']:.4f} ulp of 1.0) at x = {r['at']!r} "
                f"over {r['points']} points; published floor "
                f"{r.get('published_floor', '(none)')}"
            )
        print(f"n_cdf64 left-tail worst relative {worst_relative:.6e} "
              f"over {len(LEFT_TAIL_POINTS)} points")
        print()
        for e in errors:
            print(f"FAIL: {e}")
        if not errors:
            print("PASS: measurement -- every published floor is a true and "
                  "tight floor of the compiled kernel.")

    return (1 if errors else 0), {"kernels": results, "errors": errors}


def main() -> int:
    decoder_self_test()
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--transcription", action="store_true",
                    help="offline leg only: no toolchain, no mpmath")
    ap.add_argument("--measurement", action="store_true",
                    help="measured leg only: needs mpmath and the pinned chelis")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()
    # Neither flag means both legs.
    do_t = args.transcription or not args.measurement
    do_m = args.measurement or not args.transcription

    verbose = not args.json
    report: dict = {}
    rc = 0

    published: dict[str, Published] = {}
    if do_t:
        if verbose:
            print("== transcription leg (offline) ==")
        t_rc, t_report = run_transcription(verbose)
        rc |= t_rc
        report["transcription"] = t_report
        published, _ = parse_published()
    else:
        published, errors = parse_published()
        if errors:
            for e in errors:
                print(f"FAIL: {e}", file=sys.stderr)
            return 1

    if do_m:
        if verbose:
            print("\n== measurement leg (mpmath + pinned chelis) ==")
        m_rc, m_report = run_measurement(published, verbose)
        rc |= m_rc
        report["measurement"] = m_report

    if args.json:
        print(json.dumps(report, indent=2, default=str))
    return rc


if __name__ == "__main__":
    try:
        sys.exit(main())
    finally:
        GEN.unlink(missing_ok=True)
