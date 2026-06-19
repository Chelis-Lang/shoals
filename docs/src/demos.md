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
