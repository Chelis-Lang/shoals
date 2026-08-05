module Shoals.Tests.Xva
import Std.Test (assert_close, assert_true)
import Shoals.Xva (survival_probability_constant_hazard, default_probability_in_interval, expected_positive_exposure, expected_negative_exposure, netted_exposure_2_deals, cva_constant_hazard, dva_constant_hazard, discount_factor_constant_rate)
def test_survival_at_zero_is_one() -> unit ! { Test } = assert_close(survival_probability_constant_hazard(cast(0.02, f32), cast(0.0, f32)), cast(1.0, f32), cast(1e-6, f32), "S(0) = 1")
def test_survival_decreases_with_time() -> unit ! { Test } = {
  s_short = survival_probability_constant_hazard(cast(0.02, f32), cast(1.0, f32))
  s_long = survival_probability_constant_hazard(cast(0.02, f32), cast(5.0, f32))
  assert_true(gt(s_short, s_long), "survival probability decreases with time")
}
def test_survival_one_year_2bp_hazard() -> unit ! { Test } = {
  s = survival_probability_constant_hazard(cast(0.02, f32), cast(1.0, f32))
  expected = exp(cast(-0.02, f32))
  assert_close(s, expected, cast(1e-6, f32), "S(1y, hazard=2%) = exp(-0.02)")
}
def test_default_probability_sums_to_1_minus_survival() -> unit ! { Test } = {
  hazard = cast(0.03, f32)
  t = cast(5.0, f32)
  p_default = default_probability_in_interval(hazard, cast(0.0, f32), t)
  expected = sub(cast(1.0, f32), survival_probability_constant_hazard(hazard, t))
  assert_close(p_default, expected, cast(1e-6, f32), "P(default in [0,t]) = 1 - S(t)")
}
def test_epe_only_counts_positive() -> unit ! { Test } = {
  exposures = to_tensor([cast(-10.0, f32), cast(5.0, f32), cast(-3.0, f32), cast(20.0, f32)])
  epe = expected_positive_exposure(exposures)
  expected = div(cast(25.0, f32), cast(4.0, f32))
  assert_close(epe, expected, cast(1e-6, f32), "EPE = sum(max(x,0))/n = 25/4 = 6.25")
}
def test_ene_only_counts_negative() -> unit ! { Test } = {
  exposures = to_tensor([cast(-10.0, f32), cast(5.0, f32), cast(-3.0, f32), cast(20.0, f32)])
  ene = expected_negative_exposure(exposures)
  expected = div(cast(-13.0, f32), cast(4.0, f32))
  assert_close(ene, expected, cast(1e-6, f32), "ENE = sum(min(x,0))/n = -13/4")
}
def test_netting_sums_pointwise() -> unit ! { Test } = {
  a = to_tensor([cast(10.0, f32), cast(-5.0, f32), cast(8.0, f32)])
  b = to_tensor([cast(-3.0, f32), cast(7.0, f32), cast(-2.0, f32)])
  netted = netted_exposure_2_deals(a, b)
  netted_l = to_list(netted)
  v0 = index(netted_l, cast(0, int64))
  v1 = index(netted_l, cast(1, int64))
  v2 = index(netted_l, cast(2, int64))
  _ = assert_close(v0, cast(7.0, f32), cast(1e-6, f32), "deal_a[0] + deal_b[0]")
  _ = assert_close(v1, cast(2.0, f32), cast(1e-6, f32), "deal_a[1] + deal_b[1]")
  assert_close(v2, cast(6.0, f32), cast(1e-6, f32), "deal_a[2] + deal_b[2]")
}
def test_cva_zero_when_zero_hazard() -> unit ! { Test } = {
  time_grid = to_tensor([cast(1.0, f32), cast(2.0, f32), cast(3.0, f32)])
  epe = to_tensor([cast(10.0, f32), cast(15.0, f32), cast(12.0, f32)])
  cva = cva_constant_hazard(time_grid, epe, cast(0.0, f32), cast(0.4, f32), cast(0.03, f32))
  assert_close(cva, cast(0.0, f32), cast(1e-6, f32), "CVA = 0 when hazard = 0")
}
def test_cva_increases_with_hazard() -> unit ! { Test } = {
  time_grid = to_tensor([cast(1.0, f32), cast(2.0, f32), cast(3.0, f32)])
  epe = to_tensor([cast(10.0, f32), cast(15.0, f32), cast(12.0, f32)])
  cva_low = cva_constant_hazard(time_grid, epe, cast(0.01, f32), cast(0.4, f32), cast(0.03, f32))
  cva_high = cva_constant_hazard(time_grid, epe, cast(0.05, f32), cast(0.4, f32), cast(0.03, f32))
  assert_true(gt(cva_high, cva_low), "CVA monotone in hazard")
}
def test_cva_zero_when_full_recovery() -> unit ! { Test } = {
  time_grid = to_tensor([cast(1.0, f32), cast(2.0, f32), cast(3.0, f32)])
  epe = to_tensor([cast(10.0, f32), cast(15.0, f32), cast(12.0, f32)])
  cva = cva_constant_hazard(time_grid, epe, cast(0.05, f32), cast(1.0, f32), cast(0.03, f32))
  assert_close(cva, cast(0.0, f32), cast(1e-6, f32), "CVA = 0 when recovery = 100%")
}
def test_cva_zero_when_zero_epe() -> unit ! { Test } = {
  time_grid = to_tensor([cast(1.0, f32), cast(2.0, f32), cast(3.0, f32)])
  epe = to_tensor([cast(0.0, f32), cast(0.0, f32), cast(0.0, f32)])
  cva = cva_constant_hazard(time_grid, epe, cast(0.05, f32), cast(0.4, f32), cast(0.03, f32))
  assert_close(cva, cast(0.0, f32), cast(1e-6, f32), "CVA = 0 when EPE is zero")
}
def test_dva_positive_for_negative_ene() -> unit ! { Test } = {
  time_grid = to_tensor([cast(1.0, f32), cast(2.0, f32), cast(3.0, f32)])
  ene = to_tensor([cast(-5.0, f32), cast(-8.0, f32), cast(-3.0, f32)])
  dva = dva_constant_hazard(time_grid, ene, cast(0.02, f32), cast(0.4, f32), cast(0.03, f32))
  assert_true(gt(dva, cast(0.0, f32)), "DVA > 0 when ENE is negative (institution gains on own default)")
}
def test_discount_factor_at_zero_is_one() -> unit ! { Test } = assert_close(discount_factor_constant_rate(cast(0.05, f32), cast(0.0, f32)), cast(1.0, f32), cast(1e-6, f32), "df(0) = 1")
def test_discount_factor_one_year() -> unit ! { Test } = {
  d = discount_factor_constant_rate(cast(0.05, f32), cast(1.0, f32))
  assert_close(d, exp(cast(-0.05, f32)), cast(1e-6, f32), "df(1y, 5%) = exp(-0.05)")
}
