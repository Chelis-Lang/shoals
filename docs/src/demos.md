# Business-wrong demos

The `demos/` directory holds counterexample demos under the
`Shoals.Demos` module prefix. Each demo is a well-typed model that
compiles and runs cleanly but encodes a financial error, written as a
`@property` so the prover can search for an input that breaks it. Every
wrong model is paired with a corrected control that holds.

They exist to show what a falsifiable business invariant looks like and
what a refutation reports: run them through the fuzz tier and the wrong
models return a concrete counterexample whose bindings explain the
mistake, while the controls pass.

Module: `Shoals.Demos.Businesswrong`.

- `discount_le_one` / `discount_le_one_fixed`: a linear discount
  `1 + r t` is allowed above one (negative implied rate); the control
  uses the rational discount `1 / (1 + r t)`, which stays at most one.
- `variance_nonneg` / `variance_nonneg_fixed`: an Euler step of a
  mean-reverting variance can go negative (Feller violation); the
  control applies the full-truncation `max(0, .)` scheme.
- `call_le_spot` / `call_le_spot_fixed`: a call mis-priced above spot
  (a sign bug, `+` instead of `-`) admits static arbitrage; the control
  restores the Black-Scholes minus and respects `C <= S`.

## Running the demos

```
chelis prove demos/businesswrong.ch --tier fuzz-only --samples 500 --seed 0 --json
```

The three wrong properties report `status: "failed"` with a
`counterexample` object; the three `*_fixed` controls report
`status: "passed"`. The search is deterministic: the same seed
reproduces the same counterexample on every run.

---

# Model realism demos

The `demos/realism.ch` module exercises the canon's model universe at
practitioner-scale sizes with real market parameters, demonstrating that
the verified lattice, bond, and MC pricers produce correct prices at
the sizes a desk actually runs. **No proof-tier claims are made** —
these are convergence assertions, not formal invariants.

Module: `Shoals.Demos.Realism`.

- `test_crr_200step_converges_to_bs`: a 200-step CRR lattice prices a
  1Y ATM European call (S=100, K=100, r=5%, σ=20%) and asserts within
  0.5% of the Black-Scholes closed form. This is the lattice depth a
  desk uses for vanilla pricing.
- `test_bond_60period_semiannual`: a 60-period (30Y semiannual) coupon
  bond at c=5%, y=4% is priced by `fi_bond_general` and compared to
  the analytic present-value formula, asserting within 1%.
- `test_mc_10k_converges_to_bs`: 10,000 GBM paths price the same 1Y
  ATM call and assert within 2% of Black-Scholes. This is a quick
  intraday path count.

## Running

```
chelis test demos/realism.ch --timeout 120
```

All three tests pass. Execution time is under 60s on a single core.
