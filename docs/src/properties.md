# Property specifications

The `properties/` directory holds the finance invariants the library is
expected to satisfy, written as ordinary Chelis functions that return a
`bool` for a given set of inputs. They live under the `Shoals.Properties`
module prefix. Each property states a relationship that should hold for any
admissible input, and the runtime test suite exercises them on concrete grids
of inputs. They are the executable specification of correct behavior: read
them to learn what each part of the library guarantees, and run them through
`tests/` to confirm those guarantees hold on this checkout.

## Pricing properties

Module: `Shoals.Properties.Pricing`.

- `put_call_parity_holds(s, k, r, sigma, t)`: the call minus the put equals
  `s - k * exp(-r * t)`.
- `call_price_nonneg` and `put_price_nonneg`: prices are non-negative.
- `call_bounded_by_spot(s, k, r, sigma, t)`: the call price never exceeds
  the spot.
- `matches_textbook_reference` and `matches_textbook_reference_put`: the
  optimized scalars agree with the `Shoals.References.BlackScholes` oracles.
- `mc_matches_textbook_mc_reference(template, s0, k, r, sigma, t)`: under a
  shared seed the optimized Monte Carlo agrees with the scalar Monte Carlo
  reference to within five percent.

## No-arbitrage properties

Module: `Shoals.Properties.NoArbitrage`.

- `bull_spread_nonneg(s, k_low, k_high, r, sigma, t)`: a call struck lower is
  worth at least as much as one struck higher, so the bull spread is
  non-negative.
- `butterfly_nonneg(s, k, h, r, sigma, t)`: the long-butterfly payoff
  `c(k - h) - 2 c(k) + c(k + h)` is non-negative (within a small tolerance).

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

- `year_fraction_matches_textbook(start, end, convention)`: each day-count
  year fraction agrees with its reference.
- `schedule_monotone_increasing(start, end, step_months)`: a generated
  schedule is strictly increasing.
- `date_roll_following_idempotent_on_weekday(d)`: rolling a weekday forward
  leaves it unchanged.

## Tenor properties

Module: `Shoals.Properties.Tenor`.

- `tenor_apply_advances_by_tenor_to_days(ref, t)`: applying a tenor advances
  the date by exactly the tenor's day count.
- `days_then_weeks_equals_compound(ref, n_days, n_weeks)`: applying a day
  tenor then a week tenor equals one combined shift.
- `tenor_to_days_nonneg_for_positive_count(unit, n)`: a non-negative count
  yields a non-negative day count.

## Market-data properties

Module: `Shoals.Properties.MarketData`.

- `quote_round_trip(side, value, d)`: a constructed quote reads back its
  value.
- `md_bar_high_gte_low`, `md_bar_close_in_high_low_range`,
  `md_bar_open_in_high_low_range`: bar fields satisfy the OHLC ordering.
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
