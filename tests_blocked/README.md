# tests_blocked/ — upstream-blocker probes

Every `.ch` here is a **minimal reproducer of an open compiler or sibling-shell
bug** that Shoals works around, **EXPECTED TO FAIL** at the current pin,
run via `chelis test tests_blocked/ --expect blocked` (a pass = FIX-detected:
execute the de-narrowing instructions in the probe's `.expect` sidecar,
promote the probe to a real test, and archive the `docs/UPSTREAM_BUGS.md`
entry in the same change set).

## Current probes

**`timeseries/rolling_f64_absent.ch`** — Nautilus's current TimeSeries
surface remains tensor-shaped and f32-only (nautilus#70 / nautilus#85).
Re-probe it against the next compatible Nautilus release and follow its
sidecar before retiring Shoals's list-shaped f64 indicator layer.

`tests/canonical_erf.ch` checks the available `erf` and `erfc` primitives.
Shoals's Cody kernel remains in use; any replacement must pass the numerical
and Greek oracles.

This directory was deliberately empty from the chelis 0.18.6 bump until
2026-09-05. **That emptiness was load-bearing for the chelis#1387 entry**,
whose re-probe criterion was "row 12 reads `NA` on the unmodified tree" — a
criterion the remaining probe invalidates, since row 12 now reads `PASS` whether
or not chelis#1387 is fixed. That entry's trigger has been amended to move
this directory aside before re-probing; if you add or remove probes here,
check it still discriminates.

Shoals also carries two actively-blocking entries that are not
expressible here: one is a `chelis reef conform audit` row verdict and the
other is a wall-clock measurement, so `chelis test --expect blocked` cannot
express either. Both are listed under §cannot-be-probed below.

`linearity/wildcard_discard_consume.ch` was the probe here. At 0.18.5 it went
**FIX-DETECTED**: chelis#1200's wildcard-discard consume scope is fixed. The
same reproducer checked with an `UseAfterConsume` on the 0.18.4 binary
(``variable `b` (from a destructured binding) was already consumed by call to
`blocked_tag_of` ``) and checks clean on 0.18.5 — a measured before/after pair
run against both binaries, not a changelog reading. Per its sidecar it was
promoted to `tests/wildcard_discard_consume.ch`, the 4 cited `asserted_N`
bindings in `tests/curves_basis.ch` were reverted to `_ =`, and the
`docs/UPSTREAM_BUGS.md` entry was archived — all in that change set.

`runtime/mod_big_i64_precision.ch` was the probe before it. At 0.18.3 it went
**FIX-DETECTED**: chelis#680's i64 `mod` f64-path precision drift is fixed
(`mod(1103515245·1406938949 + 12345, 2147483647)` now returns the exact
`178066070` on both the eval and compiled-C lanes; 0.18.1 returned `178065916`).
Per its sidecar it was promoted to `tests/mod_big_i64_precision.ch`,
`Shoals.Rng`'s internal bit-walk call sites moved back onto the builtin `mod`,
and the `docs/UPSTREAM_BUGS.md` entry was archived — all in that change set.

Because `chelis test --expect` rejects an empty suite (a guard that runs zero
probes would be silently green), the gate steps that invoke it are guarded to
skip when this directory holds no `.ch` files. Drop a probe in and it runs
again with no further wiring — see the `Blocked-probe suite` step in
`.github/workflows/ci.yml` and the matching stage in
`scripts/run_local_gate.py`.

Every other open Shoals blocker is either a **prove-lane** capability gap or a
**tooling** defect (see §cannot-be-probed). For the prove-lane gaps: the failing surface is a `chelis prove` verdict, not a
compile/eval diagnostic, so `chelis test --expect blocked` cannot express
it. The prove-lane verdicts are re-probed instead by the keystone canon
self-audit (`scripts/prove_gate.py`, explicitly selected as optional local
evidence at a relevant pin bump), which classifies every property's verdict from `prove --json`
`proof_tier` — a blocker "flipping" there surfaces as a tier upgrade in the
gate report.

## §cannot-be-probed

- **chelis#637 — coupled-subterm envelope obstruction (BS positivity /
  intrinsic lower bound).** The abstract-subterm envelope path abstracts
  `N(d1)`/`N(d2)` into independent fresh variables, discarding the coupling
  that exact proof depends on. Direct BS/B76 call-price positivity is therefore
  only `fuzz_validated`, and the direct intrinsic-lower-bound candidate remains
  `deferred_invariant` — prove verdicts, not test diagnostics.
  Teaching exemplar: the identical intrinsic-lower-bound invariant PROVES
  on the CRR anchor (`properties/canontrees.ch`) and defers on
  Black–Scholes. Re-probe on any release naming coupled-subterm /
  relational abstraction or whole-expression interval evaluation.
- **chelis#659 — fuzz-tier sampling cost over real transcendental bodies
  (historical).** The obstruction was a prove-fuzz wall-clock budget and
  could not be expressed as an expected-to-fail fixture. The 0.17.4 manual
  re-probe found it fixed; see `docs/UPSTREAM_BUGS.md` §Archived for the
  measured one-sample and 25-sample results. Only direct Black-Scholes and
  Black-76 call-price positivity plus their corrupted twins were observed and
  promoted; monotonicity, Greeks, and risk surfaces still require dedicated
  per-surface probes.

- **chelis#1387 — row 12 of
  `chelis reef conform audit` reads an own-repo citation as an upstream
  blocker.** The failing surface is an audit row verdict, not a compile or eval
  diagnostic. Writing a probe here would also be self-defeating: the row's
  complaint is that this directory is empty, so any `.ch` dropped in would
  silence the finding rather than reproduce it, and the probe would have no
  honest expected diagnostic. Re-probed by running `chelis reef conform audit`
  on the unmodified tree at every pin bump; row 12 must report `NA`.
- **chelis#1391 — `chelis test --batch-mode auto` regressed 2.6x on this
  suite at 0.18.6.** The
  failing surface is wall-clock (3m01s at 0.18.5 vs 7m54s at 0.18.6 over the
  same 43 files and 371 tests on one quiet machine), and an expected-to-fail
  `.ch` carries no timing oracle. Re-probed by timing `chelis test tests/`
  under both `--batch-mode` values when explicitly selected locally. The
  compiler batching fix and historical measurements remain distinct from
  shoals#111's hosted-budget obligation, retired with nightly on 2026-10-08.
  No compiler performance fix is inferred from that policy change.
