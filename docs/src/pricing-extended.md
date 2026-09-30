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
and `n_pdf_ext` is the density. From `tests/pricingextended.ch`,
`n_cdf_ext(0) == 0.5` and `n_pdf_ext(0) == 1 / sqrt(2 * pi)`, approximately
`0.3989423`.

## Bachelier (normal underlying)

```chelis
def bachelier_call(f: f32, k: f32, sigma: f32, t: f32, df: f32) -> f32
def bachelier_put(f: f32, k: f32, sigma: f32, t: f32, df: f32) -> f32
```

The Bachelier model prices an option on a normally distributed forward `f`
with absolute (not lognormal) volatility `sigma`, then discounts by the
explicit discount factor `df`. From `tests/pricingextended.ch`, an
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
by `df`. When the forward equals `s * exp(r * t)` and `df == exp(-r * t)`,
the Black call equals the Black-Scholes call. From `tests/pricingextended.ch`:

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
reduces to Black-Scholes. From `tests/pricingextended.ch`:

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
`sigma1^2 + sigma2^2 - 2 * rho * sigma1 * sigma2`. When that variance is
near zero the function returns the intrinsic value `max(s1 - s2, 0)`. When
the two assets are identical (equal spots, equal vols, correlation one) the
option is worthless. From `tests/pricingextended.ch`:

```chelis
px = margrabe_exchange_call(cast(100.0, f32), cast(100.0, f32), cast(0.2, f32), cast(0.2, f32), cast(1.0, f32), cast(1.0, f32))
// px == 0.0
```
## Other payoffs and numerical helpers

`pe_margrabe_stulz` includes per-asset continuous yields `q1` and `q2`
in the exchange-option formula. The
`pe_asset_or_nothing_*` and `pe_cash_or_nothing_*` functions price digital
calls and puts. These pricers assume the usual positive inputs for their
model formulas; their constructors do not validate market data.

Separate modules provide lattice and PDE helpers. `Shoals.Trees` includes
`tr_binom_european_call_generic`, which accepts a nonnegative step count,
finite inputs, and an up probability in `[0, 1]`. `Shoals.Pde.pde_thomas_solve`
solves a supplied tridiagonal system without pivoting. It substitutes one
for a pivot smaller than `1e-10` without a diagnostic, so near-singular
systems are outside its accuracy contract.
