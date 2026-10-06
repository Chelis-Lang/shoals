# Property specifications

The `properties/` directory holds finance checks. Many are ordinary
Chelis functions that return a `bool` for one set of inputs under the
`Shoals.Properties` module prefix. The runtime suite calls them on
selected inputs. A passing test establishes that result for those inputs;
read a property's formula and assumptions before applying it elsewhere.
Other files contain `@property` declarations run through a separate
prover.

## Pricing properties

Module: `Shoals.Properties.Pricing`.

- `put_call_parity_holds(s, k, r, sigma, t)`: the call minus the put equals
  `s - k * exp(-r * t)`.
- `call_price_nonneg` and `put_price_nonneg`: check non-negative prices.
- `call_bounded_by_spot(s, k, r, sigma, t)`: checks that the call price
  does not exceed spot at the supplied point.
- `matches_textbook_reference` and `matches_textbook_reference_put`: the
  optimized scalars agree with the `Shoals.References.BlackScholes` oracles.
- `mc_matches_textbook_mc_reference(template, s0, k, r, sigma, t)`: under a
  shared seed the optimized Monte Carlo agrees with the scalar Monte Carlo
  reference to within five percent.

## No-arbitrage properties

Module: `Shoals.Properties.NoArbitrage`.

- `bull_spread_nonneg(s, k_low, k_high, r, sigma, t)`: checks that a
  lower-strike call costs at least as much as a higher-strike call.
- `butterfly_nonneg(s, k, h, r, sigma, t)`: checks that
  `c(k - h) - 2 c(k) + c(k + h)` is non-negative within a small tolerance.

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

These are driven at concrete inputs from `tests/date.ch`. Nothing else in the
repository calls the `properties/` surface, so a property with no test beside it
is compiled and never executed.

## Tenor properties

Module: `Shoals.Properties.Tenor`.

- `schedule_is_increasing_and_bounded(start, end, months)`: a short-final
  schedule of whole-month tenors starts at `start`, ends at `end`, and is
  strictly increasing, whatever the day of month. `tests/schedule.ch` drives
  it.

## Market-data properties

Module: `Shoals.Properties.MarketData`.

- `quote_round_trip(side, value, d)`: a constructed quote reads back its
  value.
- `md_bar_high_gte_low`, `md_bar_close_in_high_low_range`,
  `md_bar_open_in_high_low_range`: check a supplied bar's OHLC ordering.
  `make_bar` does not enforce that ordering.
- `snapshot_empty_has_no_quote(d, key)`: an empty snapshot returns no quote.

## How the properties run

The runtime test suite calls these property functions on fixed input grids
and asserts they return true. `tests/properties.ch` drives the pricing,
no-arbitrage, and Greek properties; `tests/distributions.ch` drives the
distribution properties; and the date, tenor, curve, market-data, and
vol-surface properties are exercised through their respective test modules.
The properties are written as plain boolean functions, which is the form the
test suite consumes. See [Scope and limitations](scope.md) for what this
form does and does not cover.

The `@property` corpus has a separate release gate. Its VaR/expected-
shortfall entries cover confidence monotonicity, shortfall dominance, and
positive-loss behavior for both Gaussian parametric and empirical measures.
The manifest reports `fuzz_validated` for these entries, with 25 accepted
samples at each of seeds 0, 1, and 2, plus controls that detect wrong
results. This is sampled evidence. The method and pinned release identity
are in the [verification manifest](import-surface.md).
