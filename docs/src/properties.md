# Property specifications

Each property below is an exported function that returns `bool`: call it
with your own inputs to check that a finance relationship holds there before
you rely on it. For example,
`put_call_parity_holds(cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32))`
is `true` when the call minus the put is within `0.001` of
`s - k * exp(-r * t)`. A `true` covers the point you passed, not every input.

## Pricing properties

Module: `Shoals.Properties.Pricing`.

- `put_call_parity_holds(s, k, r, sigma, t)`: the call minus the put equals
  `s - k * exp(-r * t)`.
- `call_price_nonneg` and `put_price_nonneg`: check non-negative prices.
- `call_bounded_by_spot(s, k, r, sigma, t)`: checks that the call price
  does not exceed spot at the supplied point.
- `matches_textbook_reference` and `matches_textbook_reference_put`:
  `bs_call_scalar` and `bs_put_scalar` are within `5e-5` of the textbook
  formulas in [Reference oracles](references.md) at the supplied
  point.
- `mc_matches_textbook_mc_reference(template, s0, k, r, sigma, t)`: under a
  shared seed the optimized Monte Carlo agrees with the scalar Monte Carlo
  reference to within five percent.

## No-arbitrage properties

Module: `Shoals.Properties.NoArbitrage`.

- `bull_spread_nonneg(s, k_low, k_high, r, sigma, t)`: checks that a
  lower-strike call costs at least as much as a higher-strike call.
- `butterfly_nonneg(s, k, h, r, sigma, t)`: checks that
  `c(k - h) - 2 c(k) + c(k + h) >= -0.001`, an absolute price tolerance.
Use `0 < h < k`; a `false` means the call prices are not convex in strike
at that point by more than 0.001.

## Greek properties

Module: `Shoals.Properties.Greeks`.

- `fd_delta_in_unit_range_for_call`: the finite-difference call delta lies in
  `[0, 1]`.
- `fd_delta_matches_analytic`: the finite-difference call delta agrees with
  the analytic `N(d1)`.
- `vega_nonneg`: the finite-difference vega is non-negative.

## Monte Carlo properties

Module: `Shoals.Properties.MonteCarlo`.

- `same_literal_seed_same_price(template, s, k, r, sigma, t)`: two Monte Carlo
  runs under the same literal seed return the identical price.
- `mc_within_5pct_of_analytic(template, s, k, r, sigma, t)`: the Monte Carlo
  price is within five percent of the closed form.

## Curve properties

Module: `Shoals.Properties.Curves`.

- `parallel_shift_uniformly_lifts` and `parallel_shift_zero_is_identity`: a
  parallel shift lifts the interpolated rate by exactly the shift, and a zero
  shift changes nothing.
- `twist_at_midpoint_is_average`: a twist applies the average of the short
  and long shifts at the midpoint.
- `key_rate_shift_localized_at_unmoved_pillar`: a key-rate shift does not move
  the rate at an untouched pillar.
- `scale_rates_linear`: scaling multiplies the interpolated rate by the
  factor.

## Volatility-surface properties

Module: `Shoals.Properties.VolSurface`.

- `vs_total_variance_nonneg_for_atm`: the at-the-money total variance is
  non-negative.
- `vs_implied_vol_matches_sqrt_variance`: the implied vol equals
  `sqrt(max(w, 0) / t)`.
- `implied_vol_round_trip(spot, strike, r, t, sigma_true)`: pricing a call at
  a known volatility and inverting recovers that volatility.

## Distribution properties

Module: `Shoals.Properties.Distributions`.

- `lognormal_pdf_matches_textbook`, `lognormal_cdf_matches_textbook`,
  `student_t_pdf_matches_textbook`, `bvn_pdf_matches_textbook`: each density
  or cumulative agrees with its `Shoals.References.Distributions` oracle.
- `lognormal_pdf_nonneg`: the lognormal density is non-negative.
- `student_t_pdf_symmetric_at_zero`: the Student-t density is symmetric.

## Date properties

Module: `Shoals.Properties.Date`.

Year fractions are exact rationals, so every date property is an equality,
not a tolerance.

- `actual_matches_reference(start, end)`: ACT/360 and ACT/365 Fixed equal
  the reference day count over 360 and over 365.
- `isda_matches_reference(start, end)`: ACT/ACT ISDA equals the per-year
  reference sum.
- `icma_matches_reference(start, end, period_start, period_end, frequency)`:
  ACT/ACT ICMA equals the reference ratio.
- `whole_isda_year_is_exactly_one(year)`: a whole calendar year is exactly
  one ACT/ACT ISDA year, leap or not.
- `additive_under_isda(a, b, c)`: the ACT/ACT ISDA fraction over `a..c` is
  the exact sum of those over `a..b` and `b..c`.

These properties describe calendar and tenor relationships. They do not imply
that `make_bar` validates market-data ordering; its input checks are described
in [Scope and limitations](scope.md).

## Tenor properties

Module: `Shoals.Properties.Tenor`.

- `schedule_is_increasing_and_bounded(start, end, months)`: a short-final
  schedule of whole-month tenors starts at `start`, ends at `end`, and is
  strictly increasing, whatever the day of month.

## Market-data properties

Module: `Shoals.Properties.MarketData`.

- `quote_round_trip(side, value, d)`: a constructed quote reads back its
  value.
- `md_bar_high_gte_low`, `md_bar_close_in_high_low_range`,
  `md_bar_open_in_high_low_range`: check a supplied bar's OHLC ordering.
  `make_bar` does not enforce that ordering.
- `snapshot_empty_has_no_quote(d, key)`: an empty snapshot returns no quote.

## Signatures

Every property returns `bool`:

```chelis
def put_call_parity_holds(s: f32, k: f32, r: f32, sigma: f32, t: f32) -> bool
def call_price_nonneg(s: f32, k: f32, r: f32, sigma: f32, t: f32) -> bool
def put_price_nonneg(s: f32, k: f32, r: f32, sigma: f32, t: f32) -> bool
def call_bounded_by_spot(s: f32, k: f32, r: f32, sigma: f32, t: f32) -> bool
def matches_textbook_reference(s: f32, k: f32, r: f32, sigma: f32, t: f32) -> bool
def matches_textbook_reference_put(s: f32, k: f32, r: f32, sigma: f32, t: f32) -> bool
def bull_spread_nonneg(s: f32, k_low: f32, k_high: f32, r: f32, sigma: f32, t: f32) -> bool
def butterfly_nonneg(s: f32, k: f32, h: f32, r: f32, sigma: f32, t: f32) -> bool
def mc_matches_textbook_mc_reference[n](template: tensor[n, f32], s0: f32, k: f32, r: f32, sigma: f32, t: f32) -> bool
def same_literal_seed_same_price[n](template: tensor[n, f32], s: f32, k: f32, r: f32, sigma: f32, t: f32) -> bool
def mc_within_5pct_of_analytic[n](template: tensor[n, f32], s: f32, k: f32, r: f32, sigma: f32, t: f32) -> bool
def fd_delta_in_unit_range_for_call(s: f32, k: f32, r: f32, sigma: f32, t: f32) -> bool
def fd_delta_matches_analytic(s: f32, k: f32, r: f32, sigma: f32, t: f32) -> bool
def vega_nonneg(s: f32, k: f32, r: f32, sigma: f32, t: f32) -> bool
def parallel_shift_uniformly_lifts(c: YieldCurve[3], delta: f32, probe_t: f32) -> bool
def parallel_shift_zero_is_identity(c: YieldCurve[3], probe_t: f32) -> bool
def twist_at_midpoint_is_average(c: YieldCurve[3], short_d: f32, long_d: f32, t_mid: f32) -> bool
def key_rate_shift_localized_at_unmoved_pillar(c: YieldCurve[3], pillar_idx: i64, delta: f32, far_t: f32) -> bool
def scale_rates_linear(c: YieldCurve[3], factor: f32, probe_t: f32) -> bool
def vs_total_variance_nonneg_for_atm(p: SVI) -> bool
def vs_implied_vol_matches_sqrt_variance(p: SVI, k: f32, t: f32) -> bool
def implied_vol_round_trip(spot: f32, strike: f32, r: f32, t: f32, sigma_true: f32) -> bool
def lognormal_pdf_matches_textbook(x: f32, mu: f32, sigma: f32) -> bool
def lognormal_cdf_matches_textbook(x: f32, mu: f32, sigma: f32) -> bool
def student_t_pdf_matches_textbook(x: f32, nu: f32) -> bool
def bvn_pdf_matches_textbook(x: f32, y: f32, mu_x: f32, mu_y: f32, sigma_x: f32, sigma_y: f32, rho: f32) -> bool
def lognormal_pdf_nonneg(x: f32, mu: f32, sigma: f32) -> bool
def student_t_pdf_symmetric_at_zero(nu: f32, dx: f32) -> bool
def actual_matches_reference(start: Date, end: Date) -> bool
def isda_matches_reference(start: Date, end: Date) -> bool
def icma_matches_reference(start: Date, end: Date, period_start: Date, period_end: Date, frequency: i64) -> bool
def whole_isda_year_is_exactly_one(year: i64) -> bool
def additive_under_isda(a: Date, b: Date, c: Date) -> bool
def schedule_is_increasing_and_bounded(start: Date, end: Date, months: i64) -> bool
def quote_round_trip(side: Side, value: f32, d: Date) -> bool
def md_bar_high_gte_low(b: Bar) -> bool
def md_bar_close_in_high_low_range(b: Bar) -> bool
def md_bar_open_in_high_low_range(b: Bar) -> bool
def snapshot_empty_has_no_quote(d: Date, key: string) -> bool
```

See [Scope and limitations](scope.md) for a description of what
these properties do and do not establish.
