# Counterexample examples

Bounded property search can find inputs that violate a financial model's stated
bound. The module `Shoals.Demos.Businesswrong` pairs three wrong models with
corrected controls, each stated as a `@property`. The first pair:

```chelis
def nn(x: f32) -> f32 = if lt(x, cast(0.0, f32)) then cast(0.0, f32) else x
def discount_wrong(r: f32, t: f32) -> f32 = add(cast(1.0, f32), mul(nn(r), nn(t)))
@property discount_le_one forall(r: f32, t: f32):
  {
    factor = discount_wrong(r, t)
    lte(factor, cast(1.0, f32))
  }
def discount_right(r: f32, t: f32) -> f32 = div(cast(1.0, f32), add(cast(1.0, f32), mul(nn(r), nn(t))))
@property discount_le_one_fixed forall(r: f32, t: f32):
  {
    factor = discount_right(r, t)
    lte(factor, cast(1.0, f32))
  }
```

`chelis prove FILE --tier fuzz-only --samples 500 --seed 0` samples each
property's inputs and stops at the first violation. On the module's three
pairs it reports `3 passed, 3 failed`, with these counterexamples:

| Property | Mistake | Counterexample | Control |
|---|---|---|---|
| `discount_le_one` | `1 + r * t` used as a discount factor | `r = 1.5066e-8`, `t = 4.7198`: the factor exceeds 1 | `1 / (1 + r * t)`: 500/500 passed |
| `variance_nonneg` | Euler step `v + kappa * (theta - v) * dt - shock` | `v = kappa = theta = dt = 0`, `shock = 3.77e-16`: the variance is negative | floor at 0: 500/500 passed |
| `call_le_spot` | `s * N(d1) + k * disc * N(d2)` (sign error) | `s = 0`, `k = 3.83e-16`, `nd2 = 0.0089`, `disc` clamped to 1: the call exceeds spot | subtract the strike term: 500/500 passed |

A counterexample demonstrates an input that violates the stated bound. A
bounded search that finds no counterexample does not prove the property for
every possible input.

## Model-size examples

Three pricers at practitioner sizes against their closed forms, at
`s0 = k = 100`, `r = 0.05`, `sigma = 0.2`, `t = 1`:

```chelis
crr = tr_crr_european_call(cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.0, f32), cast(0.2, f32), cast(1.0, f32), cast(200, i64))
// 10.439744; Black-Scholes 10.450583, 0.10% apart
bond = fi_bond_general(cast(0.025, f32), cast(0.02, f32), cast(60, i64))
// 1.1738045; a 30-year 5% semiannual bond at a 4% yield, closed form 1.1738
template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(10000, i64))))
mc = mc_call_price(key_from_seed(42i64), template, cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32))
// 10.341786; 1.0% below Black-Scholes, within one standard error (0.147)
```

The CRR error shrinks roughly in proportion to `1 / n_steps`, and the Monte
Carlo error in proportion to `1 / sqrt(paths)`; a different seed moves the
Monte Carlo value by about `0.15` at this path count. The functions are in
[Lattices, PDEs, and early exercise](lattices-pde.md) and
[Pricing](pricing.md).
