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

TWO LEGS, AND ONLY ONE OF THEM IS SOUND. Read this before trusting a green.

  1. EXPORT PARITY is sound. It reads the `export (...)` list, which is
     unambiguous, and decides whether every list function has a counterpart
     and every counterpart has a list function. A green here is proof.

  2. "IS EXERCISED" IS A HEURISTIC, not a proof, and cannot be made into one
     here. It pattern-matches the test source for the name inside an
     `identical(`/`identical_bool(` argument. Source text can always be
     arranged to satisfy a pattern without asserting anything, and two
     red-team rounds demonstrated four such spellings: a whole-line `--`
     comment (round 1), then a nestable `{- -}` block comment, a trailing
     inline comment, a string literal, and a call bound with `_ =` and never
     asserted (round 2). Each fix was followed by another spelling, which is
     the signal that the approach is wrong rather than incomplete.

     The spellings above are now handled. The leg is still labelled heuristic
     BECAUSE THE NEXT SPELLING IS NOT KNOWN. Do not read leg 2's green as
     proof that a check exists; read it as "no obvious hole".

     The structural fix is to make coverage unloseable rather than detectable
     -- route every equivalence check through one helper driven by a single
     table, so this script counts entries in a data structure instead of
     matching prose. That is new test architecture rather than a correction,
     so it is tracked separately rather than grown into the change that
     introduced this guard.

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


def _strip_non_code(src: str) -> str:
    """Remove string literals, nestable `{- -}` block comments and `--` line
    comments (including trailing ones), so a name surviving in the result is
    really in code. Each of these three was a live way to fool the previous
    version, and the string-literal case is the one most likely to happen by
    accident -- this test file is full of string assertion labels."""
    out: list[str] = []
    i, depth, in_str = 0, 0, False
    while i < len(src):
        two = src[i : i + 2]
        if in_str:
            if src[i] == "\\":
                i += 2
                continue
            if src[i] == '"':
                in_str = False
            i += 1
            continue
        if two == "{-":
            depth += 1
            i += 2
            continue
        if two == "-}" and depth:
            depth -= 1
            i += 2
            continue
        if depth:
            i += 1
            continue
        if two == "--":                      # line comment, leading or trailing
            while i < len(src) and src[i] != "\n":
                i += 1
            continue
        if src[i] == '"':
            in_str = True
            i += 1
            continue
        out.append(src[i])
        i += 1
    return "".join(out)


def _is_asserted(name: str, code: str) -> bool:
    """True when `name(` appears inside an `identical(`/`identical_bool(` call.
    Scans forward from each equivalence call to its matching paren so a name in
    a neighbouring statement does not count."""
    for m in re.finditer(r"\bidentical(?:_bool)?\s*\(", code):
        i, depth = m.end() - 1, 0
        while i < len(code):
            if code[i] == "(":
                depth += 1
            elif code[i] == ")":
                depth -= 1
                if depth == 0:
                    break
            i += 1
        if re.search(rf"\b{re.escape(name)}\s*\(", code[m.end() : i]):
            return True
    return False


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
    tests_src = _strip_non_code(io.open(TESTS, encoding="utf-8").read())
    # The name must appear inside an `identical(` / `identical_bool(`
    # argument, not merely somewhere in the file: a bare `_ = tensor_rma(x)`
    # calls the function and asserts nothing, which a red-team round used to
    # satisfy the previous presence-only regex.
    unchecked = [t for t in tensor if not _is_asserted(t, tests_src)]
    if unchecked:
        problems.append(f"`tensor_` exports with no check in {TESTS}: {unchecked}")

    print(f"list functions : {len(listish)}")
    print(f"tensor variants: {len(tensor)}")
    print(f"asserted (heuristic): {len(tensor) - len(unchecked)}/{len(tensor)}")

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

    print("\nTENSOR SURFACE PARITY: OK (export parity proven; \"asserted\" is heuristic -- see the module docstring)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
