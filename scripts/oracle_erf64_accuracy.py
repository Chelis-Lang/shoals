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
* The measurement leg proves the published floor is tight for the points it
  sampled, on the dtype and interval it sampled. It is ABSOLUTE error over
  +/-6.5 only, so it cannot observe `n_cdf64`'s left-tail RELATIVE blowup
  (1.8% at x = -8, exactly 0.0 below about -8.3) -- that is shoals#68, and
  `docs/CHELIS_SURFACE.md` documents it separately.

MEASURE IN BINARY: the error is `mpf(f64_result) - erf(mpf(exact_f64_input))` at
extended precision. `chelis eval --json` hands back the exact f64 as hex bits
(schema 3's tagged carrier), so no decimal round trip enters the measurement.
Comparing `mpf(repr(result))` against `mpf(decimal_input)` would measure a
decimal round trip instead (~0.04 ulp near the argmax), and rounding the
reference to a double first would quantise every error to a multiple of an ulp.

FLOOR, NOT MAXIMUM: the error is jagged at ulp scale, so any grid reports only
the worst point it lands on, and a finer but differently spaced refinement can
miss the argmax. Every published figure is therefore a floor.

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
# a figure 10^14 better than anything measurable. Measured on the tracked tree,
# widening to any exponent adds zero false positives: the same 11 carriers are
# found either way, because the `>=` already does the discriminating.
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
    # but `n_cdf64` is not: `0.5 * (1 - erf64(-x/sqrt2))` rounds differently on
    # the two sides, and its worst observed point is at x = -0.717. A grid that
    # only swept x >= 0 reported a documented floor as overstated when the
    # grid, not the figure, was what was wrong.
    pts |= {-x for x in tuple(pts)}
    pts.add(-0.7170090691949448)
    pts.add(0.7700537662469848)
    return sorted(pts)


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

    if args.json:
        print(json.dumps(report, indent=2, default=str))
    return rc


if __name__ == "__main__":
    try:
        sys.exit(main())
    finally:
        GEN.unlink(missing_ok=True)
