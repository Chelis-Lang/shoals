# tests_blocked/ — upstream-blocker probes

Every `.ch` here is a **minimal reproducer of an open upstream chelis
bug** that Shoals works around, **EXPECTED TO FAIL** at the current pin,
run via `chelis test tests_blocked/ --expect blocked` (a pass = FIX-detected:
execute the de-narrowing instructions in the probe's `.expect` sidecar,
promote the probe to a real test, and archive the `docs/UPSTREAM_BUGS.md`
entry in the same change set).

## Current probes

| Probe | Blocker | Expected to flip at |
|---|---|---|
| `runtime/mod_big_i64_precision.ch` | i64 `mod` f64-path precision drift (chelis#680; `docs/UPSTREAM_BUGS.md` §Tracking) — why `Shoals.Rng` hand-rolls `i64_mod` for the Sobol/xor bit walks | any release touching the i64 `mod` runtime |

Every other open Shoals blocker is a **prove-lane** capability gap (see
§cannot-be-probed): the failing surface is a `chelis prove` verdict, not a
compile/eval diagnostic, so `chelis test --expect blocked` cannot express
it. The prove-lane verdicts are re-probed instead by the keystone canon
self-audit (`scripts/prove_gate.py`, run nightly in CI and at every pin
bump), which classifies every property's verdict from `prove --json`
`proof_tier` — a blocker "flipping" there surfaces as a tier upgrade in the
gate report.

## §cannot-be-probed

- **chelis#434 — transcendental SMT discharge for real finance bodies.**
  The obstruction is a prove verdict (`unsupported` naming the
  transcendental at `--tier smt-only`; honest fall to fuzz at `--tier
  auto`) on any goal inlining a real `normal_cdf`/`bs_call` body. Verdicts
  are not expressible as an expected-to-fail test case. Re-probed manually
  per `docs/UPSTREAM_BUGS.md` §Tracking at every pin bump (last: 0.16.1 —
  the certified-envelope discharge shipped in 0.16.0, residual is
  chelis#637 below), and continuously by `scripts/prove_gate.py`.
- **chelis#637 — coupled-subterm envelope obstruction (BS positivity /
  intrinsic lower bound).** The abstract-subterm envelope path abstracts
  `N(d1)`/`N(d2)` into independent fresh variables, discarding the coupling
  that positivity depends on, so the flagship goals stay
  `deferred_invariant` — again a prove verdict, not a test diagnostic.
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
