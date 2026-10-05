module Shoals.Tests.CurvesBootstrapSchedule
import Std.Test (assert_close, assert_true)
import Shoals.Curves (Instrument, YieldCurve, deposit, zero_coupon, cur_par_swap, instrument_validate, bootstrap_multi, bootstrap_multi_curve, discount_factor, yield_curve_from_pillars, curve_pillars)
-- shoals#75: a par swap's fixed leg is valued over its own coupon schedule
-- (payments_per_year coupons a year, accrual 1/payments_per_year), with
-- discount factors at intermediate dates read from the curve being built
-- under the `rate_at` convention (zero rates linear between pillars, flat
-- outside them). Reference values come from an independent Python model of
-- that convention; they are not re-derived from Shoals code.
def cbs_abs_f32(x: f32) -> f32 = if lt(x, cast(0.0, f32)) then neg(x) else x
def cbs_gapped_annual() -> List[Instrument] = [deposit(cast(0.5, f32), cast(0.041, f32)), deposit(cast(1.0, f32), cast(0.042, f32)), cur_par_swap(cast(2.0, f32), cast(0.0435, f32), cast(1, i64)), cur_par_swap(cast(5.0, f32), cast(0.0452, f32), cast(1, i64)), cur_par_swap(cast(10.0, f32), cast(0.0468, f32), cast(1, i64))]
def cbs_semiannual() -> List[Instrument] = [deposit(cast(0.25, f32), cast(0.04, f32)), cur_par_swap(cast(1.0, f32), cast(0.042, f32), cast(2, i64)), cur_par_swap(cast(2.0, f32), cast(0.044, f32), cast(2, i64)), cur_par_swap(cast(3.5, f32), cast(0.045, f32), cast(2, i64))]
-- Reads the pillars through the exported reader rather than a record pattern:
-- `YieldCurve` is opaque, so the representation is not visible here. The curve
-- is rebuilt per discount factor because it is linear and the fold needs it
-- once per coupon date; the rebuilt curves are untagged, which is immaterial
-- since `kind` does not reach `rate_at`.
def cbs_swap_pv[n](curve: YieldCurve[n], tenor: f32, par_rate: f32, payments_per_year: i64) -> f32 = {
  pillars = curve_pillars(curve)
  ts = pillars.0
  rs = pillars.1
  freq_f = cast(payments_per_year, f32)
  periods = cast_trunc(add(mul(tenor, freq_f), cast(0.5, f32)), i64)
  ks = range(cast(1, i64), add(periods, cast(1, i64)))
  df_maturity = discount_factor(yield_curve_from_pillars(copy(ts), copy(rs)), tenor)
  annuity = fold(fn (acc: f32, i: i64) -> add(acc, discount_factor(yield_curve_from_pillars(copy(ts), copy(rs)), div(cast(i, f32), freq_f))), cast(0.0, f32), ks)
  add(mul(div(par_rate, freq_f), annuity), df_maturity)
}
def test_gapped_annual_pillars_match_reference() -> unit ! { Test } = {
  rates = bootstrap_multi(cbs_gapped_annual()).1
  tol = cast(5e-6, f32)
  _ = assert_close(index(rates, cast(0, i64)), cast(0.0405854, f32), tol, "0.5y deposit zero rate")
  _ = assert_close(index(rates, cast(1, i64)), cast(0.0411419, f32), tol, "1y deposit zero rate")
  _ = assert_close(index(rates, cast(2, i64)), cast(0.0426118, f32), tol, "2y annual swap zero rate (was 0.065363 under one-coupon-per-pillar)")
  _ = assert_close(index(rates, cast(3, i64)), cast(0.0443174, f32), tol, "5y annual swap zero rate over a 2y-5y pillar gap")
  assert_close(index(rates, cast(4, i64)), cast(0.0460236, f32), tol, "10y annual swap zero rate (was 0.023317 under one-coupon-per-pillar)")
}
def test_semiannual_pillars_match_reference() -> unit ! { Test } = {
  rates = bootstrap_multi(cbs_semiannual()).1
  tol = cast(5e-6, f32)
  _ = assert_close(index(rates, cast(0, i64)), cast(0.0398013, f32), tol, "3m deposit zero rate")
  _ = assert_close(index(rates, cast(1, i64)), cast(0.0415774, f32), tol, "1y semiannual swap zero rate")
  _ = assert_close(index(rates, cast(2, i64)), cast(0.0435785, f32), tol, "2y semiannual swap zero rate")
  assert_close(index(rates, cast(3, i64)), cast(0.0445834, f32), tol, "3.5y semiannual swap zero rate")
}
def test_bootstrapped_curve_reprices_gapped_swaps_through_discount_factor() -> unit ! { Test } = {
  curve = bootstrap_multi_curve(cbs_gapped_annual(), to_tensor([cast(0.5, f32), cast(1.0, f32), cast(2.0, f32), cast(5.0, f32), cast(10.0, f32)]))
  tol = cast(0.00002, f32)
  _ = assert_close(cbs_swap_pv(curve, cast(2.0, f32), cast(0.0435, f32), cast(1, i64)), cast(1.0, f32), tol, "2y swap reprices to par on the returned curve")
  _ = assert_close(cbs_swap_pv(curve, cast(5.0, f32), cast(0.0452, f32), cast(1, i64)), cast(1.0, f32), tol, "5y swap reprices to par on the returned curve")
  assert_close(cbs_swap_pv(curve, cast(10.0, f32), cast(0.0468, f32), cast(1, i64)), cast(1.0, f32), tol, "10y swap reprices to par on the returned curve")
}
def test_bootstrapped_curve_reprices_semiannual_swaps_through_discount_factor() -> unit ! { Test } = {
  curve = bootstrap_multi_curve(cbs_semiannual(), to_tensor([cast(0.25, f32), cast(1.0, f32), cast(2.0, f32), cast(3.5, f32)]))
  tol = cast(0.00002, f32)
  _ = assert_close(cbs_swap_pv(curve, cast(1.0, f32), cast(0.042, f32), cast(2, i64)), cast(1.0, f32), tol, "1y semiannual swap reprices to par")
  assert_close(cbs_swap_pv(curve, cast(3.5, f32), cast(0.045, f32), cast(2, i64)), cast(1.0, f32), tol, "3.5y semiannual swap reprices to par")
}
def test_upward_sloping_quotes_give_upward_sloping_zeros() -> unit ! { Test } = {
  rates = bootstrap_multi(cbs_gapped_annual()).1
  idxs = range(cast(1, i64), cast(5, i64))
  increasing = fold(fn (acc: bool, i: i64) -> if acc then lt(index(rates, sub(i, cast(1, i64))), index(rates, i)) else false, true, idxs)
  assert_true(increasing, "strictly upward-sloping instrument quotes bootstrap to strictly increasing zero rates")
}
def test_payment_frequency_changes_the_solved_rate() -> unit ! { Test } = {
  annual = bootstrap_multi([deposit(cast(1.0, f32), cast(0.042, f32)), cur_par_swap(cast(2.0, f32), cast(0.044, f32), cast(1, i64))]).1
  semi = bootstrap_multi([deposit(cast(1.0, f32), cast(0.042, f32)), cur_par_swap(cast(2.0, f32), cast(0.044, f32), cast(2, i64))]).1
  gap = cbs_abs_f32(sub(index(annual, cast(1, i64)), index(semi, cast(1, i64))))
  assert_true(gt(gap, cast(0.0001, f32)), "the same quote at annual and semiannual frequency bootstraps to different 2y zero rates")
}
def test_consecutive_annual_layout_is_unchanged() -> unit ! { Test } = {
  rates = bootstrap_multi([deposit(cast(1.0, f32), cast(0.04, f32)), cur_par_swap(cast(2.0, f32), cast(0.045, f32), cast(1, i64))]).1
  assert_close(index(rates, cast(1, i64)), cast(0.0441251, f32), cast(5e-6, f32), "1y deposit + 2y annual swap: the one layout the old rule priced correctly keeps its value")
}
def test_par_swap_validity_requires_whole_periods_and_positive_frequency() -> unit ! { Test } = {
  _ = assert_true(instrument_validate(cur_par_swap(cast(1.5, f32), cast(0.04, f32), cast(2, i64))), "1.5y semiannual swap has three whole periods and is valid")
  _ = assert_true(instrument_validate(cur_par_swap(cast(0.25, f32), cast(0.04, f32), cast(4, i64))), "3m quarterly swap has one whole period and is valid")
  _ = assert_true(if instrument_validate(cur_par_swap(cast(2.3, f32), cast(0.04, f32), cast(1, i64))) then false else true, "2.3y annual swap is not a whole number of periods")
  _ = assert_true(if instrument_validate(cur_par_swap(cast(2.0, f32), cast(0.04, f32), cast(0, i64))) then false else true, "zero payments per year is invalid")
  assert_true(if instrument_validate(cur_par_swap(cast(2.0, f32), cast(0.04, f32), cast(-2, i64))) then false else true, "negative payments per year is invalid")
}
def test_par_swap_validity_rejects_non_finite_tenor() -> unit ! { Test } = {
  nan_t = div(cast(0.0, f32), cast(0.0, f32))
  inf_t = div(cast(1.0, f32), cast(0.0, f32))
  _ = assert_true(if instrument_validate(cur_par_swap(nan_t, cast(0.04, f32), cast(2, i64))) then false else true, "a NaN par-swap tenor is invalid rather than trapping in cast_trunc")
  assert_true(if instrument_validate(cur_par_swap(inf_t, cast(0.04, f32), cast(2, i64))) then false else true, "an infinite par-swap tenor is invalid rather than trapping in cast_trunc")
}
