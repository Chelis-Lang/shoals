# Greeks

Module: `Shoals.Greeks`.

This module computes option sensitivities by central finite differences on
the Black-Scholes scalars from [`Shoals.Pricing`](pricing.md), provides
analytic Greek formulas for cross-checking the finite-difference results,
and offers pathwise and likelihood-ratio estimators for single-path
delta. Every finite-difference function takes an explicit bump size.

## First-order finite-difference Greeks

```chelis
def fd_delta_call(s: f32, k: f32, r: f32, sigma: f32, t: f32, h: f32) -> f32
def fd_delta_put(s: f32, k: f32, r: f32, sigma: f32, t: f32, h: f32) -> f32
def fd_vega_call(s: f32, k: f32, r: f32, sigma: f32, t: f32, h: f32) -> f32
def fd_vega_put(s: f32, k: f32, r: f32, sigma: f32, t: f32, h: f32) -> f32
def fd_rho_call(s: f32, k: f32, r: f32, sigma: f32, t: f32, h: f32) -> f32
def fd_rho_put(s: f32, k: f32, r: f32, sigma: f32, t: f32, h: f32) -> f32
def fd_theta_call(s: f32, k: f32, r: f32, sigma: f32, t: f32, h: f32) -> f32
def fd_theta_put(s: f32, k: f32, r: f32, sigma: f32, t: f32, h: f32) -> f32
```

Delta bumps spot, vega bumps volatility, rho bumps the rate, and theta
bumps maturity, each by `h` in that input's own units. Delta, vega, and rho
return `(price(x + h) - price(x - h)) / (2 * h)`; theta returns
`(price(t - h) - price(t + h)) / (2 * h)`, the negative of the maturity
derivative, so a long option that decays in time
reports a negative theta.

Choose `h > 0` and small against the bumped input: `h < s` for delta,
`h < sigma` for vega, `h < t` for theta. Nothing checks this. A down-bump
past zero evaluates the pricer outside its domain rather than failing. At
`s = k = 100`, `r = 0.05`, `sigma = 0.2`, `t = 0.5`, theta with `h = 1.0`
is NaN (the square root of a negative maturity). At `t = 1`, delta with
`h = 150` is NaN (the log of a negative spot), and vega with `h = 0.3`
returns `28.192575` against `analytic_vega_call`'s `37.524036`, a wrong number
with no warning.

For example, estimate an at-the-money call delta with a bump of `0.01`:

```chelis
fd = fd_delta_call(cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32), cast(0.01, f32))
// 0.6369591
```

For standard positive Black-Scholes inputs, call delta is in `[0, 1]`,
put delta is in `[-1, 0]`, and they differ by one. Call and put vega are
equal. With positive spot, strike, rate, volatility, and maturity, call rho
is positive, put rho is negative, and call theta is negative.

## Second-order finite-difference Greeks

```chelis
def fd_gamma_call(s: f32, k: f32, r: f32, sigma: f32, t: f32, h: f32) -> f32
def fd_vanna_call(s: f32, k: f32, r: f32, sigma: f32, t: f32, h_s: f32, h_v: f32) -> f32
def fd_volga_call(s: f32, k: f32, r: f32, sigma: f32, t: f32, h: f32) -> f32
```

`fd_gamma_call` is the second spot derivative from a three-point stencil.
`fd_volga_call` is the second volatility derivative. `fd_vanna_call` is the
cross derivative of delta with respect to volatility and so takes two bump
sizes, one for spot (`h_s`) and one for volatility (`h_v`).

For example:

```chelis
g = fd_gamma_call(cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32), cast(0.5, f32))
// 0.018764496
v = fd_vanna_call(cast(100.0, f32), cast(105.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32), cast(0.01, f32), cast(0.001, f32))
// 0.19073485
```

## Analytic Greek references

```chelis
def analytic_delta_call(s: f32, k: f32, r: f32, sigma: f32, t: f32) -> f32
def analytic_delta_put(s: f32, k: f32, r: f32, sigma: f32, t: f32) -> f32
def analytic_vega_call(s: f32, k: f32, r: f32, sigma: f32, t: f32) -> f32
def analytic_gamma_call(s: f32, k: f32, r: f32, sigma: f32, t: f32) -> f32
def n_pdf(x: f32) -> f32
```

These are the closed-form Black-Scholes sensitivities, with
`d1 = (ln(s / k) + (r + sigma^2 / 2) * t) / (sigma * sqrt(t))`, `N` the
standard normal CDF, and `phi` its density. `analytic_delta_call` is
`N(d1)`, `analytic_delta_put` is `N(d1) - 1`, `analytic_vega_call` is
`s * phi(d1) * sqrt(t)`, and `analytic_gamma_call` is
`phi(d1) / (s * sigma * sqrt(t))`. `n_pdf` is the standard normal density.
For example, compare a finite-difference estimate with the closed-form
delta at a representative input:

```chelis
fd = fd_delta_call(cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32), cast(0.01, f32))
an = analytic_delta_call(cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32))
// fd == 0.6369591, an == 0.6368306
```

## Pathwise and likelihood-ratio estimators

```chelis
def pathwise_smooth_call_terminal_delta(s_terminal: f32, k: f32, df: f32, s0: f32) -> f32
def lr_digital_call_delta(s_terminal: f32, k: f32, s0: f32, sigma: f32, t: f32, df: f32) -> f32
```

`pathwise_smooth_call_terminal_delta` is the pathwise delta estimator for a
single terminal price on a smooth call payoff: in the money it returns
`df * s_terminal / s0`, and out of the money it returns zero.
For an in-the-money single path:

```chelis
d = pathwise_smooth_call_terminal_delta(cast(120.0, f32), cast(100.0, f32), cast(0.95, f32), cast(100.0, f32))
// 1.14 == 0.95 * 1.2
```

`lr_digital_call_delta` is the likelihood-ratio delta estimator for a
digital call paying 1 at expiry when `s_terminal > k`. It returns
`df * 1[s_terminal > k] * z / (s0 * sigma * sqrt(t))` with
`z = (ln(s_terminal / s0) + sigma^2 * t / 2) / (sigma * sqrt(t))`. That
score assumes `ln(s_terminal / s0)` is normal with mean `-sigma^2 * t / 2`
and variance `sigma^2 * t`: GBM with zero drift. There is no rate input.
For a path simulated with drift `r`, pass `s_terminal * exp(-r * t)` and
`k * exp(-r * t)`, which keeps the exercise test and makes the score
correct, and pass `exp(-r * t)` as `df`.
Average the estimator over many paths to estimate delta:

```chelis
d = lr_digital_call_delta(cast(120.0, f32), cast(100.0, f32), cast(100.0, f32), cast(0.2, f32), cast(1.0, f32), cast(0.95, f32))
// 0.048051372
```
