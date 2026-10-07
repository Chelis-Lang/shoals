# Reference oracles

The `Shoals.References` modules compute the same quantities as the library
directly from their textbook formulas, written for clarity rather than speed.
Call one beside the production function to check a result at your own
inputs. Each section below states the formula the reference evaluates.

## Black-Scholes

Module: `Shoals.References.BlackScholes`.

```chelis
def call_textbook(s: f32, k: f32, r: f32, sigma: f32, t: f32) -> f32
def put_textbook(s: f32, k: f32, r: f32, sigma: f32, t: f32) -> f32
def delta_call_textbook(s: f32, k: f32, r: f32, sigma: f32, t: f32) -> f32
def delta_put_textbook(s: f32, k: f32, r: f32, sigma: f32, t: f32) -> f32
def gamma_textbook(s: f32, k: f32, r: f32, sigma: f32, t: f32) -> f32
def vega_textbook(s: f32, k: f32, r: f32, sigma: f32, t: f32) -> f32
def theta_call_textbook(s: f32, k: f32, r: f32, sigma: f32, t: f32) -> f32
def rho_call_textbook(s: f32, k: f32, r: f32, sigma: f32, t: f32) -> f32
```

With `d1 = (ln(s / k) + (r + sigma^2 / 2) * t) / (sigma * sqrt(t))` and
`d2 = d1 - sigma * sqrt(t)`, `N` the standard normal CDF and `n` its density:

| Function | Formula |
|---|---|
| `call_textbook` | `s * N(d1) - k * exp(-r * t) * N(d2)` |
| `put_textbook` | `k * exp(-r * t) * N(-d2) - s * N(-d1)` |
| `delta_call_textbook`, `delta_put_textbook` | `N(d1)`, `N(d1) - 1` |
| `gamma_textbook` | `n(d1) / (s * sigma * sqrt(t))` |
| `vega_textbook` | `s * n(d1) * sqrt(t)` |
| `theta_call_textbook` | `-s * n(d1) * sigma / (2 * sqrt(t)) - r * k * exp(-r * t) * N(d2)` |
| `rho_call_textbook` | `k * t * exp(-r * t) * N(d2)` |

They evaluate in `f32` with `N(x) = erfc(-x / sqrt(2)) / 2`, while
`bs_call_scalar` and `bs_put_scalar` evaluate in `f64` and round once, so
the two differ in the trailing digits; the `matches_textbook_reference`
property allows an absolute gap of `5e-5`. The references divide by
`sigma * sqrt(t)` without a floor, so at `t = 0` with `s = k` they return
NaN where the production pricers return the expiry limit.

## Vasicek

Module: `Shoals.References.Vasicek`.

```chelis
def zero_bond_price_textbook(r_t: f32, a: f32, b: f32, sigma: f32, tau: f32) -> f32
def short_rate_mean_textbook(r0: f32, a: f32, b: f32, t: f32) -> f32
def short_rate_variance_textbook(a: f32, sigma: f32, t: f32) -> f32
```

For the short rate `dr = a * (b - r) dt + sigma dW`, with `a` the
mean-reversion speed, `b` the long-run level, and `sigma` the rate
volatility:

- `short_rate_mean_textbook` is `b + (r0 - b) * exp(-a * t)`.
- `short_rate_variance_textbook` is `sigma^2 * (1 - exp(-2 * a * t)) / (2 * a)`.
- `zero_bond_price_textbook` is `A * exp(-B * r_t)` for a bond with `tau`
  years left, where `B = (1 - exp(-a * tau)) / a` and
  `ln A = (B - tau) * (a^2 * b - sigma^2 / 2) / a^2 - sigma^2 * B^2 / (4 * a)`.

Every formula divides by `a`, so `a = 0` returns NaN or infinity. The library
has no Vasicek pricer of its own; these are the formulas.

## Historical VaR

Module: `Shoals.References.HistoricalVar`.

```chelis
def var_textbook[n](losses: tensor[n, f32], alpha: f32) -> f32
def cvar_textbook[n](losses: tensor[n, f32], alpha: f32) -> f32
```

`var_textbook` is the empirical quantile at `alpha`, interpolated linearly
between order statistics at position `alpha * (n - 1)` of the sorted losses.
`cvar_textbook` is the mean of the losses at or above that quantile.
`Shoals.Risk.historical_var` and `historical_cvar` compute the same two
numbers.

## Vanilla Monte Carlo

Module: `Shoals.References.MonteCarlo`.

```chelis
def vanilla_call_textbook[n](rng_key: key, template: tensor[n, f32], s0: f32, k: f32, r: f32, sigma: f32, t: f32) -> f32
```

It draws one standard normal `z` per template entry from `rng_key`, sets
`S_T = s0 * exp((r - sigma^2 / 2) * t + sigma * sqrt(t) * z)`, and returns
`exp(-r * t)` times the mean of `max(S_T - k, 0)`, one path at a time.
`Shoals.Pricing.mc_call_price` computes the same estimator; under keys derived
from the same seed the two agree to within five percent.

## Distributions

Module: `Shoals.References.Distributions`.

```chelis
def lognormal_pdf_textbook(x: f32, mu: f32, sigma: f32) -> f32
def lognormal_cdf_textbook(x: f32, mu: f32, sigma: f32) -> f32
def student_t_pdf_textbook(x: f32, nu: f32) -> f32
def bvn_pdf_textbook(x: f32, y: f32, mu_x: f32, mu_y: f32, sigma_x: f32, sigma_y: f32, rho: f32) -> f32
```

The textbook densities and cumulative that the `Shoals.Distributions`
functions match.

## Day counts

Module: `Shoals.References.Date`.

```chelis
def actual_days_reference(start: Date, end: Date) -> i64
def isda_reference(start: Date, end: Date) -> (i64, i64)
def icma_reference(
  start: Date, end: Date, period_start: Date, period_end: Date, frequency: i64
) -> (i64, i64)
```

Reference values for `Shoals.Date.year_fraction`, as a day count or as an
exact fraction `(numerator, denominator)` in lowest terms. They compute an
exact proleptic-Gregorian day number of their own rather than calling
`Std.Datetime.date_days_until`, so they check `Shoals.Date` against an
independently derived calendar. The ISDA reference clamps every calendar
year to the interval and sums the pieces. `Shoals.Date` counts a whole
interior year as exactly 1 and divides only the head and tail stubs, so the
two implementations exercise different year-boundary calculations.
The reference loops over years in the test interval.

`Shoals.Date` also agrees with published values: the ACT/ACT examples of
ISDA's 1999 paper on ACT/ACT under EMU, the ISDA 2006 §4.16 30/360
definitions, and QuantLib 1.43's `Actual360`, `Actual365Fixed`,
`ActualActual(ISDA)` and `Thirty360` conventions. BUS/252 values agree with hand counts against
`Shoreleave.UsFederal.us_federal()`.
