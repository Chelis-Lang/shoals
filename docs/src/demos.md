# Counterexample demos

`demos/businesswrong.ch` contains three well-typed financial mistakes, each paired with a corrected `*_fixed` control. The properties let the prover search for an input that violates the model's stated bound.

- `discount_le_one`: a wrong-sign linear discount can exceed one. Its control uses a rational discount for nonnegative rate and time.
- `variance_nonneg`: an Euler variance step can become negative. Its control floors the resulting variance at zero.
- `call_le_spot`: adding rather than subtracting the discounted strike term can price a call above spot. Its control uses subtraction.

From the Shoals checkout, run the targeted fuzz search:

```sh
chelis prove demos/businesswrong.ch --tier fuzz-only --samples 500 --seed 0 --json
```

A `failed` property with a `counterexample` gives values that violate the stated bound. A `passed` control means no counterexample was found by this bounded search; it is not a proof for every input.
The command exits nonzero when the deliberately wrong properties fail, so
inspect the JSON records rather than treating its exit status as a
documentation test.

## Model-size examples

`demos/realism.ch` tests a 200-step CRR call, a 60-period coupon bond, and a 10,000-path Monte Carlo call against their formulas at selected parameters. Run its tests from the checkout root:

```sh
chelis test demos/realism.ch --timeout 120 --suite-timeout 180 --jobs 1
```

These are numerical comparisons at the sizes and tolerances in the source file. Runtime varies with the machine and compiler version.
