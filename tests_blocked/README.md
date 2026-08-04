# tests_blocked/ — upstream-blocker probes

Every `.ch` here is a **minimal reproducer of an open upstream chelis
bug** that Shoals works around, **EXPECTED TO FAIL** at the current pin,
run via `chelis test tests_blocked/ --expect blocked` (a pass = FIX-detected:
execute the de-narrowing instructions in the probe's `.expect` sidecar,
promote the probe to a real test, and archive the `docs/UPSTREAM_BUGS.md`
entry in the same change set).

## Current probes

**None — this directory is deliberately empty as of the chelis 0.18.3 bump.**

`runtime/mod_big_i64_precision.ch` was the only probe here. At 0.18.3 it went
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

Every other open Shoals blocker is a **prove-lane** capability gap (see
§cannot-be-probed): the failing surface is a `chelis prove` verdict, not a
compile/eval diagnostic, so `chelis test --expect blocked` cannot express
it. The prove-lane verdicts are re-probed instead by the keystone canon
self-audit (`scripts/prove_gate.py`, run nightly in CI and at every pin
bump), which classifies every property's verdict from `prove --json`
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
