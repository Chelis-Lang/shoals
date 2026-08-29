# `chelis reef conform audit` row 12 treats an own-repo citation as an upstream blocker

**Filing condition:** file against `Chelis-Lang/chelis` as soon as the 0.18.6 bump
wave has an owner for the conformance crate. Replace this path with the assigned
`chelis#NNN` at every site that cites it.

**Area:** `area:ecosystem`, `chelis-conformance`
**Introduced in:** 0.18.6 (regression against 0.18.5)
**Impact:** blocks the `Conformance audit` CI step on any shell that cites an
own-repo or registry-sibling issue inside `src/`.

## What happens

chelis#1270 widened `scan_citations` so a registry sibling's `<repo>#NNN` and a
shell's own `<self>#NNN` are recognized citations alongside `chelis#NNN`.
`check_tests_blocked` (`crates/chelis-conformance/src/audit.rs`) was not updated
with it and still reads:

```rust
let has_blocker = dir_has_ch(&ctx.root.join("tests_blocked"))
    || !collect_citations_in_dir(&ctx.root.join("src")).is_empty();
```

`collect_citations_in_dir` now returns every widened form, so *any* citation in
`src/` makes the row conclude "an upstream blocker is cited" and demand a
`tests_blocked/` probe. An own-repo citation is not an upstream blocker, and a
citation whose subject is already resolved is not a blocker at all.

Row 9 (`staleness-audit`) gets this right: it accepts a `docs/UPSTREAM_BUGS.md`
entry or a `tests_blocked/README.md` can't-be-probed note as coverage. Row 12
accepts neither.

## Reproducer (measured, not inferred)

`Chelis-Lang/shoals` at the 0.18.6 pin. `src/pricing.ch:72` reads:

```
-- Pure tensor-DAG Black-Scholes helpers for the Beacon seam (shoals#19).
```

`shoals#19` is an own-repo issue, already resolved, and already recorded in
`docs/UPSTREAM_BUGS.md` §Archived. `tests_blocked/` correctly holds no probe.

| tree | binary | row 12 | `conform audit` exit |
|---|---|---|---|
| unmodified | 0.18.5 | `NA` — "no open upstream blocker with an expressible reproducer" | 0 |
| unmodified | 0.18.6 | `FAIL` — "an upstream blocker is cited but tests_blocked/ has no probe" | 1 |
| that one token rewritten to `(shoals issue 19)`, nothing else changed | 0.18.6 | `NA` | 0 |

## Why the shell cannot fix it locally

The only two ways to satisfy the row are to delete a real design citation, or to
invent a `tests_blocked/` probe for a blocker that does not exist.
`tests_blocked/README.md` defines a probe as "a minimal reproducer of an open
upstream chelis bug that Shoals works around", so there is nothing truthful to
put there. The contract itself sanctions the own-repo form: `UPSTREAM_BUGS.md`'s
header says "own-repo items as `shoals#NNN`".

## Suggested fix

Filter `check_tests_blocked`'s blocker set to upstream `chelis#NNN` tokens whose
subject is an active `docs/UPSTREAM_BUGS.md` entry, and accept the same coverage
sources row 9 accepts. Add a negative control for an own-repo citation with an
empty `tests_blocked/`, and one for a `chelis#NNN` whose entry sits in
§Archived.
