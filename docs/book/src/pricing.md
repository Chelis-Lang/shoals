# Pricing

Module: `Shoals.Pricing`.

This module provides the Black-Scholes call and put in closed form,
vectorized price tensors over a set of spots, gradient-derived sensitivity
vectors, and a Monte Carlo call pricer that takes an explicit random key.
The `f32` scalar calls use an `f64` pricing body with Chelis's
`standard_normal_cdf`, then round the result to `f32`.
See [Scope and limitations](scope.md) for numerical bounds.

## Closed-form scalars

```chelis
def bs_call_scalar(s: f32, k: f32, r: f32, sigma: f32, t: f32) -> f32
def bs_put_scalar(s: f32, k: f32, r: f32, sigma: f32, t: f32) -> f32
def bs_call_f64(s: f64, k: f64, r: f64, sigma: f64, t: f64) -> f64
```

`bs_call_scalar` and `bs_put_scalar` price a European call and put on a
non-dividend-paying underlying. The arguments are spot `s`, strike `k`,
the continuously compounded risk-free rate `r`, volatility `sigma`, and
time to maturity `t` in years.

A one-year at-the-money call and put:

```chelis
px = bs_call_scalar(cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32))
// px is approximately 10.4506

pp = bs_put_scalar(cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32))
// pp is approximately 5.5735
```

These two satisfy put-call parity: `c - p == s - k * exp(-r * t)`.

## Tensor-valued f64 entry

```chelis
def bs_call_f64_vector[n](spots: tensor[n, f64], strikes: tensor[n, f64], rates: tensor[n, f64], sigmas: tensor[n, f64], times: tensor[n, f64]) -> tensor[n, f64]
def bs_call_wire_f64[n](s: tensor[n, f64], k: tensor[n, f64], r: tensor[n, f64], sigma: tensor[n, f64], t: tensor[n, f64], half: tensor[n, f64], inv_sqrt_2: tensor[n, f64], a1: tensor[n, f64], a2: tensor[n, f64], a3: tensor[n, f64], a4: tensor[n, f64], a5: tensor[n, f64], p: tensor[n, f64], two_over_sqrt_pi: tensor[n, f64], small: tensor[n, f64]) -> tensor[n, f64]
```

`bs_call_f64_vector` prices row `i` as `bs_call_f64(spots[i], strikes[i],
rates[i], sigmas[i], times[i])`, so each contract carries its own terms:

```chelis
vec = bs_call_f64_vector(
  to_tensor([cast(100.0, f64), cast(90.0, f64)]),
  to_tensor([cast(100.0, f64), cast(100.0, f64)]),
  to_tensor([cast(0.05, f64), cast(0.05, f64)]),
  to_tensor([cast(0.2, f64), cast(0.2, f64)]),
  to_tensor([cast(1.0, f64), cast(0.5, f64)])
)
// [10.450583572185565, 2.34942829541399]
```

`bs_call_wire_f64` is the same call price written with tensor operations
only, for consumers that need a pure tensor graph. It evaluates the normal
CDF with the Abramowitz-Stegun erf approximation 7.1.26, whose constants it
takes as inputs, each a tensor of length `n` repeating one value:
`half = 0.5`, `inv_sqrt_2 = 0.7071067811865476`, `a1 = 0.254829592`,
`a2 = -0.284496736`, `a3 = 1.421413741`, `a4 = -1.453152027`,
`a5 = 1.061405429`, `p = 0.3275911`,
`two_over_sqrt_pi = 1.1283791670955126`, and `small = 0.00001` (below
`|x| < small` it uses the linear term of erf). That approximation has
absolute error up to about `1.5e-7` in erf, so its prices match
`bs_call_f64` closely but not exactly. Other coefficient values give a
different function, unchecked.

## Vectorized prices

```chelis
def call_prices[n](spots: tensor[n, f32], k: f32, r: f32, sigma: f32, t: f32) -> tensor[n, f32]
def put_prices[n](spots: tensor[n, f32], k: f32, r: f32, sigma: f32, t: f32) -> tensor[n, f32]
def call_total[n](spots: tensor[n, f32], k: f32, r: f32, sigma: f32, t: f32) -> f32
def put_total[n](spots: tensor[n, f32], k: f32, r: f32, sigma: f32, t: f32) -> f32
```

`call_prices` and `put_prices` map the scalar pricer over a tensor of
spots, holding strike, rate, volatility, and maturity fixed. `call_total`
and `put_total` sum the resulting prices to a single `f32`.

For example:

```chelis
spots = to_tensor([cast(80.0, f32), cast(100.0, f32), cast(120.0, f32)])
prices = call_prices(spots, cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32))
// [1.8594197, 10.450583, 26.169044]
```

`call_total(spots, ...)` equals the sum of the entries of
`call_prices(spots, ...)`.

## Gradient-derived sensitivities

```chelis
def deltas_call[n](spots: tensor[n, f32], k: f32, r: f32, sigma: f32, t: f32) -> tensor[n, f32]
def deltas_put[n](spots: tensor[n, f32], k: f32, r: f32, sigma: f32, t: f32) -> tensor[n, f32]
def vegas_call[n](spots: tensor[n, f32], k: f32, r: f32, sigma: f32, t: f32) -> tensor[n, f32]
def rhos_call[n](spots: tensor[n, f32], k: f32, r: f32, sigma: f32, t: f32) -> tensor[n, f32]
def thetas_call[n](spots: tensor[n, f32], k: f32, r: f32, sigma: f32, t: f32) -> tensor[n, f32]
def gammas_call[n](spots: tensor[n, f32], k: f32, r: f32, sigma: f32, t: f32) -> tensor[n, f32]
def volgas_call[n](spots: tensor[n, f32], k: f32, r: f32, sigma: f32, t: f32) -> tensor[n, f32]
def vannas_call[n](spots: tensor[n, f32], k: f32, r: f32, sigma: f32, t: f32) -> tensor[n, f32]
```

`deltas_call` and `deltas_put` differentiate the total call or put price
with respect to the spot vector using `grad`, yielding a delta per spot.
`vegas_call` differentiates the total call price with respect to a vector
of volatilities, yielding a vega per spot. The other exported calls give
call rho, theta, gamma, volga, and vanna; the last three use nested
derivatives. The [Greeks](greeks.md) chapter documents separate
finite-difference and analytic checks.

### At expiry

At `t = 0` these return the limit as expiry is approached, and none of them
returns `NaN`. Two values are infinite, because the quantities themselves
diverge:

| | `s < k` | `s = k` | `s > k` |
|---|---|---|---|
| `deltas_call` | `0` | `0.5` | `1` |
| `deltas_put` | `-1` | `-0.5` | `0` |
| `gammas_call` | `0` | `+inf` | `0` |
| `thetas_call` | `0` | `-inf` | `-r * k` |
| `vannas_call` | `0` | `0` | `0` |
| `vegas_call`, `rhos_call`, `volgas_call` | `0` | `0` | `0` |

The closed-form limits follow from the payoff and its derivatives:

- At `t = 0` the price is the payoff `max(s - k, 0)`. Delta is its first
  derivative, a step; gamma is its second, a spike at the strike and zero
  elsewhere.
- Above the strike the price is `s - k * exp(-r * t)`, so `dC/dt` is
  `r * k * exp(-r * t)` and theta, which is `-dC/dt`, is `-r * k`. Volatility
  does not enter it.
- Below the strike the price is zero in a neighborhood, so every sensitivity
  there is zero.
- Delta at the strike is `0.5` because `d1 = (r + sigma^2/2) * sqrt(t) / sigma`
  tends to zero, so `N(d1)` tends to `N(0)`. It is the limit in time, not a
  midpoint convention.
- Vanna is `-n(d1) * d2 / sigma`. At the strike `n(d1)` tends to `n(0)`, which
  is not zero, but `d2` tends to zero, so vanna does too. It is zero across
  the whole surface at expiry.
- Vega, rho and volga each carry a `sqrt(t)` or `t` factor.
- Put delta follows from the call by put-call parity: differentiating it in the
  spot gives `delta_call - delta_put = 1` at every spot and every `t`, expiry
  included. At the strike that is `0.5 - (-0.5)`.

Gamma at the strike grows like `n(d1) / (s * sigma * sqrt(t))` and theta like
`-s * sigma * n(d1) / (2 * sqrt(t))`, where `n` is the standard normal density,
so both grow without bound as `t` falls to zero. The infinities report that
divergence. Gamma at expiry is a Dirac delta, with no pointwise value;
the returned `+inf` preserves the sign of the diverging limit.

If you aggregate a Greek vector, test for finiteness rather than for `NaN`: a
`x == x` check is true for an infinity and will pass it through.

## Monte Carlo call price

```chelis
def mc_call_price[n](rng_key: key, template: tensor[n, f32], s0: f32, k: f32, r: f32, sigma: f32, t: f32) -> f32
```

`mc_call_price` draws one standard normal `z` per path, sets
`S_T = s0 * exp((r - sigma^2 / 2) * t + sigma * sqrt(t) * z)`, and returns
`exp(-r * t)` times the mean of `max(S_T - k, 0)`. The number of paths is
the length of `template`; its values are ignored. An empty template divides
by zero paths and returns NaN. The function takes a `key` as its first
argument; derive a reproducible key with `key_from_seed`.

For example, estimate an at-the-money call with twenty thousand paths:

```chelis
template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(20000, i64))))
mc_px = mc_call_price(key_from_seed(42i64), template, cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32))
// 10.531636 (closed form 10.450583)
```

The standard error of the estimate is about `14.7 / sqrt(paths)` here, `0.10`
at twenty thousand paths, so a different seed moves the result by that much.
Running the same call twice with keys derived from the same seed and the same
other inputs returns identical values.
