#!/usr/bin/env python3
"""Guard the 1:1 parity between the list and tensor surfaces of
`Shoals.Indicators` (shoals#83).

WHY THIS IS A SCRIPT AND NOT A CHELIS TEST. The invariant is about the EXPORT
LIST -- "every series-taking export has a `tensor_` counterpart, and every
`tensor_` export has an equivalence check" -- and Chelis cannot enumerate its
own exports at run time. A Chelis test can only check the functions it already
names, which is precisely the thing that goes stale when someone adds a 23rd
export. So the enumeration happens here, over the source.

The parity matters because the naming rule is `tensor_` prepended to the list
name, with no exceptions, so that a caller generating calls can derive the
tensor name rather than look it up. A missing counterpart silently breaks that
derivation for exactly one function, which is the hardest kind of gap to notice.

    Command:   python3 scripts/check_tensor_surface_parity.py
    Success:   exit 0 with `TENSOR SURFACE PARITY: OK`
    Owner:     shoals#83 / spec/shoals_quant_surface.md §2.15
"""

from __future__ import annotations

import io
import re
import sys

SRC = "src/indicators.ch"
TESTS = "tests/indicators_tensor.ch"

# Convention constructors and types: not functions, so no tensor counterpart.
NON_FUNCTION = {
    "EmaSeed", "SeedFirstValue", "SeedSma",
    "Alpha", "AlphaSpan", "AlphaWilder",
    "Smoothing", "SmoothWilder", "SmoothEma", "SmoothSimple",
    "Ddof", "DdofPopulation", "DdofSample",
}


def exports(path: str) -> list[str]:
    src = io.open(path, encoding="utf-8").read()
    m = re.search(r"^export \((.*?)\)$", src, re.M | re.S)
    if m is None:
        sys.exit(f"FAIL: no export list found in {path}")
    return [x.strip() for x in m.group(1).split(",") if x.strip()]


def main() -> int:
    names = exports(SRC)
    tensor = sorted(n for n in names if n.startswith("tensor_"))
    listish = sorted(n for n in names if not n.startswith("tensor_") and n not in NON_FUNCTION)

    problems: list[str] = []

    # 1. Every list function has a tensor counterpart, derivable by the rule.
    missing = [n for n in listish if f"tensor_{n}" not in names]
    if missing:
        problems.append(
            "list exports with no `tensor_` counterpart (the naming rule says "
            f"prepend `tensor_`): {missing}"
        )

    # 2. Every tensor export corresponds to a real list export -- catches a
    #    typo'd or orphaned variant.
    orphans = [t for t in tensor if t[len("tensor_"):] not in names]
    if orphans:
        problems.append(f"`tensor_` exports with no list counterpart: {orphans}")

    # 3. Every tensor export is exercised by the equivalence suite.
    # Strip Chelis comment lines first. Without this a `-- TODO: re-enable
    # tensor_rma(...)` line satisfies the regex below, so a DISABLED check
    # still reports as exercised. Confirmed by a red-team round, which
    # commented out `tensor_rma`'s equivalence check and still got 22/22.
    tests_src = "\n".join(
        line for line in io.open(TESTS, encoding="utf-8").read().splitlines()
        if not line.lstrip().startswith("--")
    )
    unchecked = [t for t in tensor if not re.search(rf"\b{re.escape(t)}\s*\(", tests_src)]
    if unchecked:
        problems.append(f"`tensor_` exports with no check in {TESTS}: {unchecked}")

    print(f"list functions : {len(listish)}")
    print(f"tensor variants: {len(tensor)}")
    print(f"both exercised : {len(tensor) - len(unchecked)}/{len(tensor)}")

    if problems:
        print()
        for p in problems:
            print(f"FAIL: {p}")
        print("\nTENSOR SURFACE PARITY: FAIL")
        return 1

    if len(listish) != len(tensor):
        print(f"\nFAIL: {len(listish)} list functions but {len(tensor)} tensor variants")
        print("\nTENSOR SURFACE PARITY: FAIL")
        return 1

    print("\nTENSOR SURFACE PARITY: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
