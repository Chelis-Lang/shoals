#!/usr/bin/env python3
"""Check Shoals' published `erf64`/`n_cdf64` accuracy floors. shoals#61, shoals#64.

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
* The measurement leg proves each published floor is tight for the points it
  sampled, on the dtype, interval and QUANTITY it sampled. The absolute floors
  are swept over +/-6.5; the relative floor is swept over [-37.5, 6.5]. Neither
  constrains the other, and that independence is the shoals#68 lesson: the
  absolute sweep was green while `n_cdf64` had 1.8% relative error at x = -8 and
  returned exactly 0.0 below about -8.3, because absolute error was never
  affected. A new accuracy claim about a NEW quantity needs a new leg, not a
  denser grid on an old one.

THE RELATIVE LEG'S REFERENCE MUST NOT CANCEL EITHER, and this is not a
hypothetical. The absolute leg's `n_cdf64` reference is `(1 + erf(x/sqrt2))/2`,
which at 60 dps returns EXACTLY 0.0 at x = -20 and x = -37 -- the same
cancellation the kernel had, in the oracle that is supposed to detect it. The
relative leg therefore references `erfc(-x/sqrt2)/2`, and `reference_self_test`
below asserts the two agree where the erf form is still valid. A reference that
reproduces the defect reports PASS.

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

A RELATIVE FLOOR IS NORMALISED BY THE CONDITIONING, not published raw. The
attainable relative error is not constant across the tail: `n_cdf(x) =
0.5*erfc(u)` with `u = x/sqrt2`, and `d ln erfc / d ln u ~ -2u^2`, so a
relative perturbation of one unit roundoff in `u` is amplified by `(1 + x^2)`.
A single raw figure would therefore be dominated by whichever end of the
interval the grid happened to reach -- it would move when the interval moved,
which is not a property of the kernel. The published statistic is
`max |rel_err| / ((1 + x^2) * 2^-53)`, a dimensionless multiple of the
conditioning.

It is NOT constant across the sweep, and the published figure is the max rather
than a typical value: measured, it is about 1.9 in the far tail and 4.2 near
x = 0, because two error sources trade places -- the kernel's own ~1.5 ulp
dominates where the result is O(1), and the `(1 + x^2)` amplification dominates
in the tail, where that divisor is largest. A factor of about 2.2 across the
interval. `relative_probe_points` takes the superset of both grids for exactly
this reason; its docstring has the measurement.

Usage:
    oracle_erf64_accuracy.py                  # both legs
    oracle_erf64_accuracy.py --transcription  # offline leg only (per-PR CI)
    oracle_erf64_accuracy.py --measurement    # measured leg only (nightly CI)
    oracle_erf64_accuracy.py --json           # machine-readable summary
"""

from __future__ import annotations

import argparse
import json
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

# `chelis eval --json` schema versions this script knows how to read. An
# unknown version is a LOUD failure, never a duck-typed guess: schema 2 emitted
# `{"type": "float64", "value": 0.5}` and schema 3 (chelis 0.18.7) replaced it
# with the tagged carrier `{"type": "scalar", "value": {"dtype", "bits"}}`.
# Reading 3 as 2 is what killed this script for three pin bumps -- it died with
# `TypeError: cannot create mpf from {'dtype': 'f64', ...}` after 90 seconds of
# real evaluation, and nothing noticed because nothing invoked it (shoals#64).
SUPPORTED_EVAL_SCHEMAS = (2, 3)

# --------------------------------------------------------------------------
# shoals#68: the RELATIVE claim family
# --------------------------------------------------------------------------
# A SEPARATE claim family with its own marker, its own carriers and its own
# measurement, because it is a different quantity. Folding it into FLOOR_CLAIM
# was not an option: `parse_published` requires exactly ONE floor claim per
# kernel row, and `run_transcription` requires every claim attributed to a
# kernel to equal that one -- a second quantity under the same marker would
# make the two figures each other's failure.
#
# THE MARKER NAMES ITS OWN KERNEL, as `<marker> n_cdf64 >= C * ...`. The
# absolute
# family attributes a claim by a markdown first cell or a +/-2 line window,
# and the docstring above records both halves of that fragility: an unrelated
# `>=` inequality is read as a claim about these kernels, and a claim spelled
# any other way is missed. The note there says keying discovery on a window
# that NAMES the governed kernel is the shape that fixes both. This family is
# that shape. It does not retrofit the absolute family -- that stays
# follow-up work -- but a new family had no reason to inherit the defect.
#
# No overlap with FLOOR_CLAIM: that pattern requires `e-NN` immediately after
# the number, and these claims are followed by ` * (1 + x^2) * 2^-53`.
REL_FLOOR_KERNELS = ("n_cdf64",)
# The interval the relative claim covers. Its lower end is where `n_cdf64`
# itself saturates (-26.543*sqrt2, Cody's XBIG), below which the true value is
# subnormal; the upper end matches the absolute sweep.
REL_INTERVAL = (-37.5, 6.5)
# Unit roundoff. The published statistic is a multiple of this times the
# conditioning, never a raw relative error -- see the docstring.
REL_UNIT_ROUNDOFF_EXP = -53
# ASSEMBLED FROM PARTS, and this file never spells it whole. The marker is
# discovered by `git grep` over the tracked tree, this script is tracked, and
# the near-miss check below fails any marker that does not parse -- so a literal
# in a comment or a diagnostic here would fail the guard against itself. The
# absolute family omits `>=` from its own examples for exactly this reason; the
# convention is the same one, applied to a marker that is a word rather than an
# operator. Everything user-facing interpolates REL_FLOOR_MARKER.
REL_FLOOR_MARKER = "REL-" "FLOOR"
REL_FLOOR_CLAIM = re.compile(
    REL_FLOOR_MARKER + r"[ \t]+`?([A-Za-z0-9_]+)`?[ \t]*>=[ \t]*"
    r"([0-9]+\.[0-9]+)[ \t]*\*[ \t]*\(1 \+ x\^2\)[ \t]*\*[ \t]*2\^-53"
)
REL_FLOOR_CLAIM_GREP = REL_FLOOR_MARKER
REL_FLOOR_SPELLING = (
    REL_FLOOR_MARKER + " <kernel> >= C.CCCC * (1 + x^2) * 2^-53")


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


class PublishedRelative:
    """One kernel's published relative floor, as a multiple of the conditioning.

    `value` is the dimensionless constant C in
    `rel_err <= C * (1 + x^2) * 2^-53`, and `sig_digits` is the precision the
    publication claims -- held to exactly the same tight-floor rule as the
    absolute family.
    """

    def __init__(self, kernel: str, spelling: str, source: str) -> None:
        self.kernel = kernel
        self.spelling = spelling
        self.source = source
        self.value = Decimal(spelling)
        mantissa = spelling.replace(".", "").lstrip("0")
        self.sig_digits = len(mantissa.rstrip()) or 1


def tracked_relative_files() -> list[str]:
    done = subprocess.run(
        ["git", "grep", "-l", "-I", "-E", REL_FLOOR_CLAIM_GREP],
        cwd=REPO_ROOT, capture_output=True, text=True, check=False,
    )
    if done.returncode not in (0, 1):
        raise SystemExit(
            f"FAIL: git grep for relative floor claims failed "
            f"(rc={done.returncode})\n{done.stderr[:500]}"
        )
    return [q for q in done.stdout.splitlines() if q]


def parse_published_relative() -> tuple[dict[str, PublishedRelative], list[str]]:
    """Read each governed kernel's relative floor out of the authoritative doc.

    Same failure discipline as the absolute family: a missing or unparseable
    claim is a failure, because a claim that silently vanishes takes its own
    guard with it. The difference is that the marker is self-attributing, so a
    malformed one is reported as malformed rather than attributed to whichever
    kernel happened to be nearby.
    """
    errors: list[str] = []
    doc = REPO_ROOT / ACCURACY_DOC
    if not doc.is_file():
        return {}, [f"{ACCURACY_DOC}: the published accuracy table is missing"]

    out: dict[str, PublishedRelative] = {}
    text = doc.read_text(encoding="utf-8")
    # A near-miss is worse than an absent claim: it reads as published and
    # matches nothing, so the kernel silently drops out of the governed set.
    # Count bare markers and require each to parse.
    bare = len(re.findall(REL_FLOOR_CLAIM_GREP, text))
    found = REL_FLOOR_CLAIM.findall(text)
    if len(found) != bare:
        errors.append(
            f"{ACCURACY_DOC}: found {bare} `{REL_FLOOR_MARKER}` marker(s) "
            f"but only {len(found)} parse as `{REL_FLOOR_SPELLING}`. A marker "
            f"that does not parse is not a published claim and nothing "
            f"checks it."
        )
    for kernel, spelling in found:
        if kernel in out:
            errors.append(
                f"{ACCURACY_DOC}: `{kernel}` publishes more than one relative "
                f"floor; there must be exactly one per kernel"
            )
            continue
        out[kernel] = PublishedRelative(
            kernel, spelling, f"{ACCURACY_DOC} (`{kernel}` relative floor)")
    for kernel in REL_FLOOR_KERNELS:
        if kernel not in out:
            errors.append(
                f"{ACCURACY_DOC}: no relative floor published for `{kernel}`. "
                f"shoals#68 is the reason this leg exists; removing the claim "
                f"removes the only guard on the left tail."
            )
    for kernel in out:
        if kernel not in REL_FLOOR_KERNELS:
            errors.append(
                f"{ACCURACY_DOC}: `{kernel}` publishes a relative floor but is "
                f"not in REL_FLOOR_KERNELS, so nothing measures it. Add it "
                f"there or drop the claim."
            )
    return out, errors


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
    published_rel, rel_errors = parse_published_relative()
    errors.extend(rel_errors)
    carriers: list[dict] = []
    rel_carriers: list[dict] = []

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

    # shoals#68's family. Self-attributing, so the loop is a straight equality
    # check against the authoritative doc rather than a context window.
    for rel in tracked_relative_files():
        lines = (REPO_ROOT / rel).read_text(encoding="utf-8").splitlines()
        for idx, line in enumerate(lines):
            bare = len(re.findall(REL_FLOOR_CLAIM_GREP, line))
            parsed = REL_FLOOR_CLAIM.findall(line)
            if bare != len(parsed):
                errors.append(
                    f"{rel}:{idx + 1}: carries a `{REL_FLOOR_MARKER}` "
                    f"marker that does not parse as `{REL_FLOOR_SPELLING}`. "
                    f"Spell it exactly, or do not spell it -- an unparseable "
                    f"marker is checked by nothing."
                )
            for kernel, literal in parsed:
                rel_carriers.append({
                    "file": rel, "line": idx + 1,
                    "literal": literal, "kernel": kernel,
                })
                pub = published_rel.get(kernel)
                if pub is None:
                    errors.append(
                        f"{rel}:{idx + 1}: states a relative floor for "
                        f"`{kernel}`, which {ACCURACY_DOC} does not publish"
                    )
                elif Decimal(literal) != pub.value:
                    errors.append(
                        f"{rel}:{idx + 1}: states `{REL_FLOOR_MARKER} "
                        f"{kernel} >= {literal} * (1 + x^2) * 2^-53`, but "
                        f"{pub.source} publishes `{pub.spelling}`"
                    )

    if verbose:
        for kernel in KERNELS:
            pub = published.get(kernel)
            print(f"{kernel:9s} published floor {pub.spelling if pub else '(UNPARSEABLE)'}"
                  f" ({pub.sig_digits if pub else '-'} sig digits)")
        for kernel in REL_FLOOR_KERNELS:
            rp = published_rel.get(kernel)
            print(f"{kernel:9s} published {REL_FLOOR_MARKER} "
                  f"{rp.spelling if rp else '(UNPARSEABLE)'} * (1 + x^2) * 2^-53"
                  f" ({rp.sig_digits if rp else '-'} sig digits)")
        print(f"\n{len(carriers)} floor claim(s) discovered in "
              f"{len({c['file'] for c in carriers})} tracked file(s):")
        for c in sorted(carriers, key=lambda c: (c["file"], c["line"])):
            who = c["attributed_kernel"] or "unattributed"
            print(f"  {c['file']}:{c['line']}  >= {c['literal']}  [{who}]")
        print(f"\n{len(rel_carriers)} relative floor claim(s) discovered in "
              f"{len({c['file'] for c in rel_carriers})} tracked file(s):")
        for c in sorted(rel_carriers, key=lambda c: (c["file"], c["line"])):
            print(f"  {c['file']}:{c['line']}  {REL_FLOOR_MARKER} "
                  f"{c['kernel']} >= {c['literal']}")

    summary = {
        "published": {k: {"spelling": p.spelling, "sig_digits": p.sig_digits}
                       for k, p in published.items()},
        "published_relative": {
            k: {"spelling": p.spelling, "sig_digits": p.sig_digits}
            for k, p in published_rel.items()},
        "carriers": carriers,
        "relative_carriers": rel_carriers,
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
    """Where to look. The argmax neighbourhood plus broad coverage.

    The dense window is centred on x = 0.507001975 because an exhaustive scan
    of +/-150k consecutive doubles found the local maximum there and nothing
    else in that window passes 3.40e-16. Broad coverage exists to notice a
    kernel change that moves the argmax somewhere else entirely.
    """
    pts: set[float] = set()
    argmax = 0.507001975
    step = 2.0**-53
    for i in range(-600, 601):  # consecutive doubles around the argmax
        pts.add(argmax + i * step)
    lo, hi, n = 0.0, 6.5, 900
    for i in range(n + 1):
        pts.add(lo + (hi - lo) * i / n)
    for boundary in (0.5, 4.0, 6.0):  # the three Cody ranges
        for k in range(-20, 21):
            pts.add(boundary + k * 2.0**-45)
    # Negatives are not optional. `erf` is odd so its error magnitude mirrors,
    # but `n_cdf64` is not: it rounds differently on the two sides. A grid that
    # only swept x >= 0 reported a documented floor as overstated when the
    # grid, not the figure, was what was wrong.
    #
    # THE TWO ANCHORS ARE ADDED BEFORE THE MIRROR, AND THE ORDER IS THE WHOLE
    # POINT. They used to be appended AFTER it, which left the grid with
    # exactly two asymmetric points -- +0.7170090691949448 and
    # -0.7700537662469848 were the only values in +/-6.5 whose mirror was
    # absent. That is not a hypothetical gap: shoals#68's repair moved
    # `n_cdf64`'s argmax onto `+0.7170090691949448`, the grid could not see it,
    # and the PR published 1.8731e-16 when the kernel reaches 1.9495e-16 there.
    # A guard whose coverage depends on statement order will eventually be
    # wrong about whichever point the next kernel change favours, so the fix is
    # the ordering rather than two more literals.
    pts.add(0.7170090691949448)
    pts.add(0.7700537662469848)
    pts |= {-x for x in tuple(pts)}
    return sorted(pts)


def relative_probe_points() -> list[float]:
    """Where to look for a RELATIVE failure, which is nowhere near where an
    absolute one lives.

    The absolute sweep is dense around x = 0.507 because that is where the
    worst absolute error is. Relative error is worst where the RESULT is
    smallest, so this grid is weighted into the left tail and onto every seam a
    relative blowup can hide behind:

    * a broad sweep over the whole interval the claim covers;
    * the region-1/region-2 branch boundary at |x/sqrt2| = 0.5, which is where
      the repaired `n_cdf64` switches spelling;
    * the region-2/region-3 boundary at |x/sqrt2| = 4 and the saturation point
      at |x/sqrt2| = 26.543, mapped back into x;
    * the five points shoals#68 measured by hand, so the issue's own table
      stays checkable against the shipped kernel; and
    * EVERY POINT OF THE ABSOLUTE GRID that falls inside the interval.

    That last one is not padding, and it is the reason this function is not
    simply a tail sweep. The normalised statistic does not peak in the tail: it
    peaks near x = 0. Two different error sources are in play -- the kernel's
    own ~1.5 ulp, which dominates where the result is O(1), and the argument
    reduction's `(1 + x^2)` amplification, which dominates in the tail -- and
    `(1 + x^2)` is SMALLEST where the first one rules. A tail-weighted grid
    measured 1.918 while a grid that reached x = -0.717 measured 4.203 on the
    same kernel. Publishing the first would have been a floor that any later
    grid refinement falsified, which is the one failure mode a FLOOR is
    supposed to be immune to. Taking the superset makes the figure a property
    of the kernel rather than of this function.

    Deliberately NOT symmetric in the tail. `n_cdf64` is not an odd function
    and the defect was one-sided: the right tail approaches 1, where relative
    accuracy is free. The dense windows inherited from the absolute grid are
    symmetric because that grid's argmax is.
    """
    import math

    lo, hi = REL_INTERVAL
    pts: set[float] = {x for x in probe_points() if lo <= x <= hi}
    for i in range(801):
        pts.add(lo + (hi - lo) * i / 800)
    root2 = math.sqrt(2.0)
    # The seams of the repaired kernel, in x. |u| = 0.5 is where `n_cdf64`
    # switches between its region-1 and erfc spellings, so it is stepped at
    # ulp scale rather than at the coarse 2^-48 the far seams use.
    for k in range(-200, 201):
        pts.add(0.5 * root2 + k * 2.0**-53)
        pts.add(-0.5 * root2 + k * 2.0**-53)
    for u in (4.0, 26.543):
        for sign in (-1.0, 1.0):
            xb = sign * u * root2
            for k in range(-30, 31):
                pts.add(xb + k * 2.0**-48)
    for x in (-9.0, -8.5, -8.3, -8.0, -7.0, -6.0, -2.0, -1.0, -0.5, 0.0, 0.5):
        pts.add(x)
    return sorted(x for x in pts if lo <= x <= hi)


def reference_self_test(mp) -> None:
    """The relative leg's own reference must not cancel. shoals#68's shape.

    `(1 + erf(x/sqrt2))/2` -- the absolute leg's reference, and the formula the
    kernel itself used -- returns EXACTLY 0.0 at 60 dps for x = -20 and below,
    because `erf` there is -1 to within 60 digits. An oracle built on it would
    compare the kernel's zero against a reference zero and report PASS on the
    exact defect it exists to find. The relative reference is therefore
    `erfc(-x/sqrt2)/2`.

    Asserted rather than commented: the erfc form must AGREE with the erf form
    where the erf form is still valid, and must DISAGREE where it has cancelled.
    The second half is the one that matters -- it proves this test would notice
    if someone swapped the reference back.
    """
    for x in (-1.0, -4.0, -9.0):
        via_erf = (1 + mp.erf(mp.mpf(x) / mp.sqrt(2))) / 2
        via_erfc = reference_ncdf(mp, x)
        if via_erf == 0 or abs(via_erf - via_erfc) / via_erfc > mp.mpf("1e-40"):
            raise SystemExit(
                f"FAIL: the two n_cdf references disagree at x = {x!r} where "
                f"both should be valid ({via_erf} vs {via_erfc}). One of them "
                f"is wrong; do not measure anything until that is resolved."
            )
    cancelled = (1 + mp.erf(mp.mpf(-20.0) / mp.sqrt(2))) / 2
    if cancelled != 0:
        raise SystemExit(
            "FAIL: `(1 + erf(x/sqrt2))/2` no longer cancels to zero at "
            "x = -20 at this precision, so this self-test no longer proves the "
            "relative reference is the non-cancelling one. Re-derive it rather "
            "than deleting the check."
        )


def reference_ncdf(mp, x: float):
    """The true normal CDF, spelled so it keeps relative accuracy in the tail."""
    return mp.erfc(-mp.mpf(x) / mp.sqrt(2)) / 2


def conditioning(mp, x: float):
    """Amplification of the argument reduction `u = x/sqrt2` at x.

    `n_cdf(x) = 0.5*erfc(u)` and `d ln erfc / d ln u -> -(2u^2 + 1)` as u grows,
    with `u^2 = x^2/2`, so one unit roundoff in `u` costs `(1 + x^2)` of them in
    the result. This is the quantity the published relative floor is normalised
    by; it is a property of the IDENTITY, not of this kernel, so a different
    erfc implementation is held to the same statistic.

    VERIFIED NUMERICALLY, not just derived. Perturbing u by one unit roundoff
    at 60 dps and measuring the relative change in erfc(u) gives, as a ratio of
    the measured amplification to this model: 0.456 at x = -0.5, 0.763 at -1,
    0.949 at -2, 0.994 at -4, 0.9996 at -8, and 1.000 from -20 outward. So the
    model is exact in the tail and CONSERVATIVE near zero -- it over-states the
    attainable error by about 2x at x = -0.5.

    That is also the explanation for the statistic's shape, and it is worth
    having rather than guessing: the normalised figure peaks near x = 0 (4.2)
    and settles lower in the tail (1.9) because near zero the divisor is too
    large by that factor AND the kernel's own ~1.5 ulp is what dominates, while
    in the tail the divisor is exact and the reduction dominates. The peak is
    not a sign of worse accuracy near zero; it is the normaliser being loose
    where it was never derived to be tight.
    """
    return 1 + mp.mpf(x) ** 2


def decode_scalar(entry: dict, schema: int) -> float:
    """One f64 off the eval wire, exactly, for a known schema version."""
    if schema == 2:
        return entry["value"]
    carrier = entry["value"]
    dtype = carrier.get("dtype")
    if dtype != "f64":
        raise SystemExit(
            f"FAIL: expected an f64 on the eval wire, got dtype={dtype!r}. "
            f"These floors are f64 claims; a narrower dtype would silently "
            f"change what is being measured."
        )
    return struct.unpack(">d", bytes.fromhex(carrier["bits"]))[0]


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


def relative_worst(points, values, mp, unit):
    """The relative sweep, as a NAMED SEAM rather than an inline loop.

    This exists for the same reason `worst` does: so a test can stub the sweep
    and reach `run_relative_measurement`'s VERDICT branches directly. Without
    the seam there is no cheap way to drive "not a floor", "not tight" or
    "silent zeros present" under the bare interpreter the per-PR job uses, and
    a red-team pass on this change found four mutations of those three
    branches that a 59-test suite did not catch -- the same class, and one
    literally the same mutation, that `MeasurementEnforcement`'s docstring
    records being found on the absolute leg in PR #108.

    Returns `(worst_normalised, at, worst_raw, raw_at, nan_count, zeros)`.
    A point whose TRUE value is zero is skipped (nothing to be relative to); a
    point where the kernel returned zero and the true value did not is recorded
    in `zeros` and excluded from both maxima, because its relative error is 1
    and would otherwise swamp the statistic it is not a member of.
    """
    worst, at, nans = mp.mpf(0), points[0], 0
    worst_raw, raw_at = mp.mpf(0), points[0]
    zeros: list[float] = []
    for x, got in zip(points, values):
        if got is None or got != got:
            nans += 1
            continue
        true = reference_ncdf(mp, x)
        if true == 0:
            continue
        if got == 0.0:
            zeros.append(x)
            continue
        rel = abs(mp.mpf(got) - true) / true
        if rel > worst_raw:
            worst_raw, raw_at = rel, x
        normalised = rel / (conditioning(mp, x) * unit)
        if normalised > worst:
            worst, at = normalised, x
    return worst, at, worst_raw, raw_at, nans, zeros


def run_relative_measurement(published_rel: dict[str, PublishedRelative],
                             mp, verbose: bool = True) -> tuple[int, dict]:
    """Measure the RELATIVE floor, and the absence of silent zeros. shoals#68.

    Two requirements, and the second is not implied by the first:

    * the published constant C is a true and TIGHT floor of
      `max |rel_err| / ((1 + x^2) * 2^-53)` over the covered interval, under
      exactly the same truncate-to-published-precision rule as the absolute
      family; and
    * the kernel returns a non-zero value at EVERY probe point where the true
      value is representable. A silent zero has relative error 1, so it is
      bounded by the first requirement only if C is large enough to be useless.
      It is checked separately and exactly, because "returns 0.0 below -8.3"
      was shoals#68's worst symptom: a zero is indistinguishable from a true
      zero at the call site.
    """
    reference_self_test(mp)
    points = relative_probe_points()
    unit = mp.mpf(2) ** REL_UNIT_ROUNDOFF_EXP
    results: dict[str, dict] = {}
    errors: list[str] = []

    for name in REL_FLOOR_KERNELS:
        values = evaluate(points, name)
        worst, at, worst_raw, raw_at, nans, zeros = relative_worst(
            points, values, mp, unit)
        measured = float(worst)
        record = {
            "worst_normalised_rel": measured,
            "at": at,
            "worst_raw_rel": float(worst_raw),
            "worst_raw_rel_at": raw_at,
            "points": len(points),
            "nan_points": nans,
            "silent_zero_points": zeros[:20],
            "silent_zero_count": len(zeros),
            "interval": list(REL_INTERVAL),
        }
        if nans:
            errors.append(
                f"{name}: {nans} of {len(points)} relative probe points came "
                f"back NaN; the sweep is not measuring what it claims to"
            )
        if zeros:
            errors.append(
                f"{name}: returned exactly 0.0 at {len(zeros)} probe point(s) "
                f"where the true value is representable, the first at "
                f"x = {zeros[0]!r} (true {reference_ncdf(mp, zeros[0])}). "
                f"That is shoals#68's worst symptom and no relative floor "
                f"bounds it: a zero cannot be told from a true zero at the "
                f"call site."
            )
        pub = published_rel.get(name)
        if pub is None:
            errors.append(
                f"{name}: measured a normalised relative floor of "
                f"{measured:.6f} but no published claim was parsed, so there "
                f"is nothing to check it against"
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
                    f"{name}: published relative floor {pub.spelling} EXCEEDS "
                    f"the worst normalised value measured, {measured:.6f}. A "
                    f"floor above every observation is not a floor."
                )
            elif not record["published_is_tight"]:
                errors.append(
                    f"{name}: published relative floor {pub.spelling} is a "
                    f"floor but not a TIGHT one. The measurement "
                    f"{measured:.6f} truncated to {pub.sig_digits} significant "
                    f"digits is {truncated}. Publish that, or publish fewer "
                    f"digits."
                )
        results[name] = record

    if verbose:
        for name, r in results.items():
            print(
                f"{name:9s} worst relative {r['worst_raw_rel']:.6e} at "
                f"x = {r['worst_raw_rel_at']!r}; normalised by (1 + x^2)*2^-53 "
                f"that is {r['worst_normalised_rel']:.6f} at x = {r['at']!r} "
                f"over {r['points']} points in "
                f"[{r['interval'][0]}, {r['interval'][1]}]; "
                f"silent zeros {r['silent_zero_count']}; published floor "
                f"{r.get('published_floor', '(none)')}"
            )
        print()
        for e in errors:
            print(f"FAIL: {e}")
        if not errors:
            print("PASS: relative measurement -- the published relative floor "
                  "is a true and tight floor, and no probe point returns a "
                  "silent zero.")

    return (1 if errors else 0), {"kernels": results, "errors": errors}


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

    if verbose:
        for name, r in results.items():
            print(
                f"{name:9s} worst observed {r['worst_abs']:.6e} "
                f"({r['worst_ulp_of_one']:.4f} ulp of 1.0) at x = {r['at']!r} "
                f"over {r['points']} points; published floor "
                f"{r.get('published_floor', '(none)')}"
            )
        print()
        for e in errors:
            print(f"FAIL: {e}")
        if not errors:
            print("PASS: measurement -- every published floor is a true and "
                  "tight floor of the compiled kernel.")

    return (1 if errors else 0), {"kernels": results, "errors": errors}


def main() -> int:
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

        # shoals#68. A separate leg, not a denser grid on the one above: it
        # measures a different quantity, over a wider interval, against a
        # different (non-cancelling) reference. Folding it in would have let
        # the absolute floors' PASS speak for the relative one.
        if verbose:
            print("\n== relative measurement leg (shoals#68) ==")
        try:
            import mpmath as mp
        except ImportError:
            print(
                "FAIL: oracle_erf64_accuracy -- mpmath is not installed, so "
                "the published relative floor cannot be measured.",
                file=sys.stderr)
            rc |= 1
            report["relative_measurement"] = {
                "errors": ["mpmath not installed"]}
        else:
            mp.mp.dps = 60
            published_rel, rel_errors = parse_published_relative()
            if rel_errors:
                for e in rel_errors:
                    print(f"FAIL: {e}", file=sys.stderr)
                rc |= 1
            r_rc, r_report = run_relative_measurement(
                published_rel, mp, verbose)
            rc |= r_rc
            report["relative_measurement"] = r_report

    if args.json:
        print(json.dumps(report, indent=2, default=str))
    return rc


if __name__ == "__main__":
    try:
        sys.exit(main())
    finally:
        GEN.unlink(missing_ok=True)
