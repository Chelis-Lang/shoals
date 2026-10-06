# Reference oracles

The `references/` directory holds textbook-formula implementations of the
quantities the optimized library computes. They live under the
`Shoals.References` module prefix and exist to be the ground truth that the
library is checked against. They are written for clarity, following the
closed-form definitions directly, and are not the code paths you call in
production. Use them when you want to confirm a result by an independent
route, or read them to see the formula a Shoals function implements.

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

The textbook call and put, first-order sensitivities, and gamma, written
from the `d1` / `d2` definitions. Shoals tests compare selected inputs
with these formulas.

## Vasicek

Module: `Shoals.References.Vasicek`.

```chelis
def zero_bond_price_textbook(r_t: f32, a: f32, b: f32, sigma: f32, tau: f32) -> f32
def short_rate_mean_textbook(r0: f32, a: f32, b: f32, t: f32) -> f32
def short_rate_variance_textbook(a: f32, sigma: f32, t: f32) -> f32
```

The Vasicek zero-coupon bond price and the conditional mean and variance of
the short rate, where `a` is the mean-reversion speed, `b` the long-run
level, and `sigma` the rate volatility. These are reference formulas; the
library does not ship a Vasicek pricer of its own.

## Historical VaR

Module: `Shoals.References.HistoricalVar`.

```chelis
def var_textbook[n](losses: tensor[n, f32], alpha: f32) -> f32
def cvar_textbook[n](losses: tensor[n, f32], alpha: f32) -> f32
```

The empirical-quantile VaR and tail-mean CVaR that `Shoals.Risk`'s
historical measures reproduce.

## Vanilla Monte Carlo

Module: `Shoals.References.MonteCarlo`.

```chelis
def vanilla_call_textbook[n](rng_key: key, template: tensor[n, f32], s0: f32, k: f32, r: f32, sigma: f32, t: f32) -> f32
```

A straightforward scalar-fold Monte Carlo call pricer, the reference that
`Shoals.Pricing.mc_call_price` is checked against using keys derived from the same seed.

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
independently derived calendar. They also state ISDA differently from the
subject: the reference clamps every calendar year to the interval and sums
the pieces, where `Shoals.Date` counts a whole interior year as exactly 1 and
divides only the head and tail stubs. Agreement is therefore a real
cross-check of the year-boundary handling rather than a restatement. The
reference keeps a per-year loop; its spans are test-sized.

The fixed values in `tests/date.ch` come from published sources: the ACT/ACT
examples of ISDA's 1999 paper on ACT/ACT under EMU, the ISDA 2006 §4.16
30/360 definitions, and QuantLib 1.43's `Actual360`, `Actual365Fixed`,
`ActualActual(ISDA)` and `Thirty360` conventions, which agree with the
Shoals definitions on 20000 sampled date pairs. BUS/252 values are hand
counts against `Shoreleave.UsFederal.us_federal()`.
