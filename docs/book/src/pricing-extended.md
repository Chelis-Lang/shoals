# Extended pricers

Module: `Shoals.PricingExtended`.

This module includes Bachelier for a normal underlying, Black for a
forward-priced option, Garman-Kohlhagen for FX, and Margrabe and Stulz
exchange options. It also exports asset-or-nothing and cash-or-nothing
calls and puts, and standard-normal helpers.

## Standard normal helpers

```chelis
def n_cdf_ext(x: f32) -> f32
def n_pdf_ext(x: f32) -> f32
```

`n_cdf_ext` is the standard normal CDF, computed as `0.5 * erfc(-x / sqrt(2))`,
and `n_pdf_ext` is the density. For example,
`n_cdf_ext(0) == 0.5` and `n_pdf_ext(0) == 1 / sqrt(2 * pi)`, approximately
`0.3989423`.

## Bachelier (normal underlying)

```chelis
def bachelier_call(f: f32, k: f32, sigma: f32, t: f32, df: f32) -> f32
def bachelier_put(f: f32, k: f32, sigma: f32, t: f32, df: f32) -> f32
```

The Bachelier model prices an option on a normally distributed forward `f`
with absolute (not lognormal) volatility `sigma`, then discounts by the
explicit discount factor `df`. Supply `sigma > 0`, `t > 0`, and
`0 < df <= 1`; nothing is checked. At `sigma = 0` or `t = 0` the price is
`df * max(f - k, 0)` for `f != k` and NaN at `f = k`. For example, an
at-the-money Bachelier call equals `sigma * phi(0)` times the discount
factor:

```chelis
px = bachelier_call(cast(100.0, f32), cast(100.0, f32), cast(10.0, f32), cast(1.0, f32), cast(1.0, f32))
// px == 10.0 * 0.3989423
```

Bachelier call and put obey parity `c - p == df * (f - k)`.

## Black (forward)

```chelis
def black_call(f: f32, k: f32, sigma: f32, t: f32, df: f32) -> f32
def black_put(f: f32, k: f32, sigma: f32, t: f32, df: f32) -> f32
```

The Black model prices an option on a lognormal forward `f` and discounts
by `df`. It needs `f > 0`, `k > 0`, `sigma > 0`, `t > 0`, and
`0 < df <= 1`, none checked; at `sigma = 0` or `t = 0` it returns the
discounted intrinsic value except at `f = k`, where it returns NaN. When the
forward equals `s * exp(r * t)` and `df == exp(-r * t)`,
the Black call equals the Black-Scholes call. For example:

```chelis
f = mul(cast(100.0, f32), exp(mul(cast(0.05, f32), cast(1.0, f32))))
df = exp(neg(mul(cast(0.05, f32), cast(1.0, f32))))
black = black_call(f, cast(100.0, f32), cast(0.2, f32), cast(1.0, f32), df)
// black equals bs_call_scalar(100, 100, 0.05, 0.2, 1.0)
```

Black call and put obey parity `c - p == df * (f - k)`.

## Garman-Kohlhagen (FX)

```chelis
def garman_kohlhagen_call(s: f32, k: f32, r_d: f32, r_f: f32, sigma: f32, t: f32) -> f32
def garman_kohlhagen_put(s: f32, k: f32, r_d: f32, r_f: f32, sigma: f32, t: f32) -> f32
```

The Garman-Kohlhagen model prices a European FX option, where `r_d` is the
domestic rate and `r_f` the foreign rate. With a zero foreign rate it
reduces to Black-Scholes. For example:

```chelis
gk = garman_kohlhagen_call(cast(1.25, f32), cast(1.3, f32), cast(0.04, f32), cast(0.0, f32), cast(0.1, f32), cast(0.5, f32))
// gk equals bs_call_scalar(1.25, 1.3, 0.04, 0.1, 0.5)
```

The pair obeys parity
`c - p == s * exp(-r_f * t) - k * exp(-r_d * t)`.

## Margrabe (exchange option)

```chelis
def margrabe_exchange_call(s1: f32, s2: f32, sigma1: f32, sigma2: f32, rho: f32, t: f32) -> f32
```

The Margrabe formula prices the option to exchange asset two for asset one,
with per-asset volatilities `sigma1` and `sigma2` and correlation `rho`.
The effective variance is
`sigma1^2 + sigma2^2 - 2 * rho * sigma1 * sigma2`. When it is below `1e-10`,
negative values included, the function returns the intrinsic value
`max(s1 - s2, 0)` instead of evaluating the formula. A negative effective
variance comes only from a correlation outside `[-1, 1]`, which is not
checked: `rho = 1.5` with `s1 = 110`, `s2 = 100` and both vols `0.2` returns
`10.0`, the intrinsic value. When the two assets are identical (equal spots, equal vols,
correlation one) the option is worthless. For example:

```chelis
px = margrabe_exchange_call(cast(100.0, f32), cast(100.0, f32), cast(0.2, f32), cast(0.2, f32), cast(1.0, f32), cast(1.0, f32))
// px == 0.0
```
## Exchange option with yields

```chelis
def pe_margrabe_stulz(s1: f32, s2: f32, sigma1: f32, sigma2: f32, rho: f32, q1: f32, q2: f32, t: f32) -> f32
```

`pe_margrabe_stulz` is the Margrabe price with continuous yields `q1` and
`q2` on the two assets:
`s1 * exp(-q1 * t) * N(d+) - s2 * exp(-q2 * t) * N(d-)`, with
`d+ = (ln(s1 / s2) + (q2 - q1 + v / 2) * t) / sqrt(v * t)` and
`d- = d+ - sqrt(v * t)` for the effective variance `v` above. With
`q1 = q2 = 0` it equals `margrabe_exchange_call`, `12.9522705` for
`s1 = 100`, `s2 = 95`, vols `0.2` and `0.3`, `rho = 0.5`, `t = 1`. Below
the same `1e-10` variance threshold it returns the forward intrinsic
`max(s1 * exp(-q1 * t) - s2 * exp(-q2 * t), 0)`.

## Digital options

```chelis
def pe_cash_or_nothing_call(s: f32, k: f32, r: f32, q: f32, sigma: f32, t: f32) -> f32
def pe_cash_or_nothing_put(s: f32, k: f32, r: f32, q: f32, sigma: f32, t: f32) -> f32
def pe_asset_or_nothing_call(s: f32, k: f32, r: f32, q: f32, sigma: f32, t: f32) -> f32
def pe_asset_or_nothing_put(s: f32, k: f32, r: f32, q: f32, sigma: f32, t: f32) -> f32
```

Black-Scholes digitals with dividend yield `q`. A cash-or-nothing option
pays 1 unit of cash at expiry when it finishes in the money, so the call is
`exp(-r * t) * N(d2)` and the put `exp(-r * t) * N(-d2)`; scale by the
cash amount yourself. An asset-or-nothing option pays the asset, so the call
is `s * exp(-q * t) * N(d1)` and the put `s * exp(-q * t) * N(-d1)`. Here
`d1 = (ln(s / k) + (r - q + sigma^2 / 2) * t) / (sigma * sqrt(t))` and
`d2 = d1 - sigma * sqrt(t)`. At `s = k = 100`, `r = 0.05`, `q = 0`,
`sigma = 0.2`, `t = 1`, the cash-or-nothing call is `0.53232485` and the
asset-or-nothing call `63.683064`, and `63.683064 - 100 * 0.53232485` is
the vanilla call price `10.4506`.

These pricers do not validate inputs. They need positive spots, strikes,
volatilities, and maturity: at `t = 0` or `sigma = 0` the `d` terms divide
by zero.

## Lattices and finite differences

Tree, finite-difference, and Longstaff-Schwartz pricers, including American
exercise, are in
[Lattices, PDEs, and early exercise](lattices-pde.md).
