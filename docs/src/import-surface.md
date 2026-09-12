# C Note import surface

This is the frozen surface C Note vendors and resolves in its no-network sandbox. It is
pinned so C Note builds against a stable contract while Shoals internals evolve. The
machine-readable manifest is `docs/cnote-import-surface.json`.

Pins: Chelis `0.18.1`, Shoals `0.24.5`, Nautilus `0.7.38`, and Coral `0.7.35`.
The exact dependency chain is published and sidecar-verified. The
machine-readable manifest records only observations reproduced by the final
official-asset gate.

Scope: first-order and second-order AD
Greeks are shipped and validated, and the SMT composite derivatives-property corpus
(parity, the upper bound, the delta bounds) is proven via the bundled `Std.Contracts`
normal-CDF contracts. The no-arbitrage properties that refused value-level abstraction
(non-negativity, intrinsic bound, strike convexity) remain out, as documented
backend-roadmap items.

## Pricing (`Shoals.Pricing`)

One normal CDF sits behind both price and Greeks: since shoals#61 that is W. J. Cody's
rational approximation in f64, measured at a worst observed absolute error of
`>= 3.3675e-16`. It replaced an Abramowitz-Stegun 7.1.26 `erf` that carried the same
coefficients as `Std.Contracts.normal_cdf` and `Nautilus.Special.erf`, which still do. The
f32 entry points compute the f64 body and downcast, and every Greek is the
automatic-differentiation derivative of that displayed price, so the delta belongs to the
number.

- `bs_call_scalar`, `bs_put_scalar`: scalar f32 price.
- `bs_call_wire_f64`: pure-tensor f64 Black-Scholes call entry with a
  compiler-owned WireDag root for bounded-domain verification consumers.
- `call_prices`, `put_prices`: price tensors over a spot tensor (tensor lane, grad-able).
- `call_total`, `put_total`: reduced totals.
- First-order Greeks (AD): `deltas_call`, `deltas_put`, `vegas_call`, `rhos_call`,
  `thetas_call` (`theta = -dC/dt`).
- Second-order Greeks (AD via nested grad): `gammas_call`, `volgas_call`, `vannas_call`.
- `mc_call_price`: Monte Carlo call, carries `Random`.

The Greeks are oracle-validated (analytic closed form, tuned finite differences of the
displayed price, the `d1 = 0` sign fold, and an accuracy-monotone guard) by
`scripts/oracle_greeks_gate.py`, with in-suite `Std.Test` standing assertions (the heavy
second-order grad assertions in `tests-manual/greeks_secondorder.ch`).

### Actual-AD characterization (Shoals#42)

Seven active records call `deltas_call`, `vegas_call`, `rhos_call`,
`thetas_call`, `gammas_call`, `volgas_call`, and `vannas_call` directly and
compare each output with a finite difference of `bs_call_scalar`. The compiler
summary—not source parsing—must report property-to-Greek and property-to-price
edges, plus Greek-to-`bs_call_f64` and price-to-the-same-`bs_call_f64` edges.
Each record has a materially biased corrupt-output twin that must refute with an
in-domain witness at seeds 0, 1, and 2.

This is honest sampled consistency plus the independent 63-cell runtime oracle.
The manifest reports certified-box and global verified-differentiation evidence
as separate deferred levels linked to Shoals#42. Neither the direct bumped-price
sign family nor these sampled records are relabeled as global AD correctness.

## Composite property corpus (`Shoals.Properties.Composites`)

Proven on the pinned 0.18.1 release via the contract mechanism: a
`@property ... with contract = "std.normal_cdf.*"` abstracts calls to the
bundled `Std.Contracts.normal_cdf` into SMT symbols carrying the declared
contract, proves the structure, and emits a composite verdict. The contract is
auto fuzz-discharged (8192 samples, tolerance 1e-10) with a cvc5 non-vacuity
check.

- `put_call_parity_reflection`, `call_upper_bounded_by_spot`, `delta_in_unit_interval`:
  each `proven_modulo_fuzz_validated_contract` (SMT base proof + fuzz-validated
  `std.normal_cdf` range/reflection contracts).
- Integrity probes: `put_call_parity_corrupted` (failed: corrupting the reflection
  coupling flips the verdict) and `delta_unknown_contract` (unsupported: an unknown
  contract id is not a pass).

Run the corpus via
`scripts/manual_gates/phase3l_shoals_oracle_composite_corpus.py` with the exact
release compiler. Do not run
`chelis prove .` on the whole package: that re-runs the starving fuzz demos and
hangs; the gate proves the corpus targeted.

### What a composite green means, and the binding (the honest scoping)

A composite green proves the financial structure for any `N` satisfying the declared,
fuzz-validated contract on `Std.Contracts.normal_cdf` (f32). It is never "Black-Scholes
proven." The shipped pricer computes its normal CDF in f64, and since shoals#61 that is
W. J. Cody's approximation — **not** the A&S model `Std.Contracts.normal_cdf` certifies.
The contract symbol is f32 only and the Greek path needs f64 (gamma especially).
Migrating the pricer to call the
f32 contract symbol would split the body and break the correctness invariant (the delta
would be the derivative of a different-precision function than the displayed price), so
instead the binding is closed by `tests/composites_binding.ch`: the pricer's price agrees
with a `Std.Contracts.normal_cdf`-based price within a stated f32 bound. So the corpus is
proven about the certified f32 contract, and the cross-check shows the shipped f64 pricer
agrees with it — measured agreement, not identity of model. At f32 output width that gap
is dominated by quantization rather than by either approximation's error.

## Demos (`Shoals.Demos.Businesswrong`)

Business-wrong models caught by the fuzz tier, each paired with a corrected control:
`discount_le_one` / `_fixed`, `variance_nonneg` / `_fixed`, `call_le_spot` / `_fixed`.
Run: `chelis prove demos/businesswrong.ch --tier fuzz-only --samples 500 --seed 0 --json`.

## Properties

Shipped verification predicates C Note can surface: `Shoals.Properties.Pricing`,
`Shoals.Properties.Greeks`, `Shoals.Properties.NoArbitrage`, and the contract-bound
`Shoals.Properties.Composites` (see the manifest for the full ID list).

Shoals 0.24.5 carries six `fuzz_validated` VaR/ES entries split across
the parametric inverse-CDF and historical empirical-quantile kinds. Each kind
has confidence-monotonicity, ES-dominates-VaR, and positivity controls. The
release gate requires 25 accepted constraint-directed samples at seeds 0, 1,
and 2, an in-domain corrupt witness, the compiler-owned property-to-output
edge, and—on each dominance relation—the additional edge to the corresponding
CVaR function. The release gate reproduces this evidence against the official
0.18.1 / 0.7.38 / 0.7.35 chain.

## Dependency tree

The 0.24.5 manifest targets `chelis-std 0.4.0` (bundled), Coral 0.7.35,
Nautilus 0.7.38, and compiler 0.18.1. Release identities and hashes come from
independently downloaded, sidecar-verified official assets; they are never
inferred from local checkouts.
