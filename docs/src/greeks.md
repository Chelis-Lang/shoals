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
bumps maturity, each by `h`, and forms a central difference. The theta
functions return the negative of the maturity derivative, so a long option
that decays in time reports a negative theta.

From `tests/greeks.ch`, an at-the-money call delta with a bump of `0.01`:

```chelis
fd = fd_delta_call(cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32), cast(0.01, f32))
```

Call delta lands in `[0, 1]`, put delta in `[-1, 0]`, and the two differ
by exactly one. Call and put vega are equal. Call rho is positive, put rho
negative, and call theta negative.

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

From `tests/greeks.ch`:

```chelis
g = fd_gamma_call(cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32), cast(0.5, f32))
v = fd_vanna_call(cast(100.0, f32), cast(105.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32), cast(0.01, f32), cast(0.001, f32))
```

## Analytic Greek references

```chelis
def analytic_delta_call(s: f32, k: f32, r: f32, sigma: f32, t: f32) -> f32
def analytic_delta_put(s: f32, k: f32, r: f32, sigma: f32, t: f32) -> f32
def analytic_vega_call(s: f32, k: f32, r: f32, sigma: f32, t: f32) -> f32
def analytic_gamma_call(s: f32, k: f32, r: f32, sigma: f32, t: f32) -> f32
def n_pdf(x: f32) -> f32
```

These are the closed-form Black-Scholes sensitivities. `analytic_delta_call`
is `N(d1)`, `analytic_delta_put` is `N(d1) - 1`, `analytic_vega_call` is
`s * phi(d1) * sqrt(t)`, and `analytic_gamma_call` is
`phi(d1) / (s * sigma * sqrt(t))`. `n_pdf` is the standard normal density.
The test suite uses these to confirm the finite-difference Greeks agree
with the closed forms. From `tests/greeks.ch`:

```chelis
fd = fd_delta_call(cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32), cast(0.01, f32))
an = analytic_delta_call(cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32))
// fd and an agree to within 0.001 at this point
```

## Pathwise and likelihood-ratio estimators

```chelis
def pathwise_smooth_call_terminal_delta(s_terminal: f32, k: f32, df: f32, s0: f32) -> f32
def lr_digital_call_delta(s_terminal: f32, k: f32, s0: f32, sigma: f32, t: f32, df: f32) -> f32
```

`pathwise_smooth_call_terminal_delta` is the pathwise delta estimator for a
single terminal price on a smooth call payoff: in the money it returns
`df * s_terminal / s0`, and out of the money it returns zero. From
`tests/greeks.ch`, an in-the-money single path:

```chelis
d = pathwise_smooth_call_terminal_delta(cast(120.0, f32), cast(100.0, f32), cast(0.95, f32), cast(100.0, f32))
// d == 0.95 * 1.2
```

`lr_digital_call_delta` is the likelihood-ratio delta estimator for a
digital (cash-or-nothing) call. It weights the in-the-money indicator by
the score of the terminal log-price with respect to the initial spot. Out
of the money it returns zero; in the money it returns a nonzero value:

```chelis
d = lr_digital_call_delta(cast(120.0, f32), cast(100.0, f32), cast(100.0, f32), cast(0.2, f32), cast(1.0, f32), cast(0.95, f32))
```
