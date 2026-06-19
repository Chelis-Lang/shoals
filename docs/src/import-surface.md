# C Note import surface

This is the frozen surface C Note vendors and resolves in its no-network sandbox. It is
pinned so C Note builds against a stable contract while Shoals internals evolve. The
machine-readable manifest is `docs/cnote-import-surface.json`.

Pins: chelis `0.7.27`, shoals `0.20.1`.

Scope: this is the ungated graduation surface at the current pin. The SMT composite
derivatives-property corpus (put-call parity, the upper bound, and the delta bounds as
proven-modulo-a-fuzz-validated-contract) lands at the re-pin and is not part of this
freeze.

## Pricing (`Shoals.Pricing`)

One normal CDF sits behind both price and Greeks: an Abramowitz-Stegun 7.1.26 `erf` in
f64 (the same coefficients as `Nautilus.Special.erf`). The f32 entry points compute the
f64 body and downcast, and every Greek is the automatic-differentiation derivative of that
displayed price, so the delta belongs to the number.

- `bs_call_scalar`, `bs_put_scalar`: scalar f32 price.
- `call_prices`, `put_prices`: price tensors over a spot tensor (tensor lane, grad-able).
- `call_total`, `put_total`: reduced totals.
- `deltas_call`, `deltas_put`, `vegas_call`, `rhos_call`, `thetas_call`: AD-derived
  first-order Greek vectors (`theta = -dC/dt`).
- `mc_call_price`: Monte Carlo call, carries `Random`.

The first-order Greeks are oracle-validated (analytic closed form, the shipped
finite-difference Greeks, and an explicit sign-fold check at and below `d1 = 0`) by
`scripts/oracle_greeks_gate.py`. On chelis 0.7.27 they are validated through that gate
rather than in-suite `Std.Test` assertions, because a rank-0 grad output cannot be
asserted through `Std.Test` yet; that conversion, and the second-order Greeks
(gamma, volga, vanna), land at the re-pin.

## Demos (`Shoals.Demos.Businesswrong`)

Well-typed, business-wrong models caught by the fuzz tier, each paired with a corrected
control: `discount_le_one` / `discount_le_one_fixed` (discount factor above 1),
`variance_nonneg` / `variance_nonneg_fixed` (negative-variance Feller violation),
`call_le_spot` / `call_le_spot_fixed` (call priced above spot). Run with
`chelis prove demos/businesswrong.ch --tier fuzz-only --samples 500 --seed 0 --json`.

## Properties

Shipped verification predicates C Note can surface: `Shoals.Properties.Pricing`,
`Shoals.Properties.Greeks`, and `Shoals.Properties.NoArbitrage` (see the manifest for the
full ID list).

## Dependency tree

C Note vendors the resolved tree from `reef.lock`: `chelis-std 0.4.0` (bundled),
`coral 0.7.25`, `nautilus 0.7.26`, all under compiler `0.7.27`. SHA-256 pins are in the
manifest.
