# Track D results: counterexample value where green is out of reach

Binary: chelis 0.7.27 (smt-enabled). Evidence: `runs/trackD_counterexamples.ndjson`.
Run: `chelis prove counterexample/businesswrong.ch --tier fuzz-only --samples 500 --seed 0 --json`.

Three well-typed models that run cleanly but are business-wrong. The fuzz tier returns a
concrete counterexample whose bindings explain the business error; each is paired with a
corrected control that passes. Binders are raw f32 clamped inside the model, so the
generator does not starve.

| model | property asserted | result | counterexample (seed 0) | business error |
|---|---|---|---|---|
| `d1_discount_le_one` | disc <= 1 | failed (fuzz) | r=4.04, t=4.72 => disc=1+r·t≈20.1 | discount factor above 1: a positive rate over positive time returns ~20x face value (negative implied rate) |
| `d2_variance_nonneg` | var_next >= 0 | failed (fuzz) | v=6.18, shock=6.79 (mean-revert terms clamped to 0) | a variance shock exceeding the current level drives the Euler-discretized variance negative (Feller-condition violation; imaginary vol) |
| `d3_call_le_spot` | call <= spot | failed (fuzz) | k=1.72, nd1,nd2,disc clamp to 1, s clamps to 0 => call=1.72 > 0 | a call priced above spot: buy stock, sell call, lock in riskless profit (static arbitrage) |

## Controls (D2 corrected-model check)

`d1_discount_le_one_fixed` (rational discount 1/(1+r·t)), `d2_variance_nonneg_fixed`
(full-truncation max(0,.)), `d3_call_le_spot_fixed` (correct Black-Scholes minus sign):
all `passed` 500/500. The counterexamples are diagnostic of the bug, not generator
artifacts.

## Determinism (D3)

Same seed reproduces the identical counterexample
(`{disc:9.16…, k:1.72…, nd1:6.56…, nd2:9.11…, s:-5.63…}`) across runs. Verified by
re-running `d3_call_le_spot` twice at seed 0.

## Note on the two refutation surfaces

The SMT tier (Track A/C) reports a refutation as `status:"failed", reason:"smt
counterexample"` but does not surface the cvc5 model bindings. The fuzz tier surfaces the
concrete violating assignment (shown above) with `shrink_steps` (shrinking is deferred in
L2 v1). For decoding a business error into readable bindings, the fuzz tier is the tool.
