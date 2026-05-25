module Shoals.Tests.VolSurface
import Std.Test (assert_close, assert_true, assert_eq_bool)
import Shoals.Pricing (bs_call_scalar)
import Shoals.VolSurface (SVI, vs_total_variance, vs_implied_vol, vs_shift_atm, vs_shift_skew, parallel_shift_atm_iv, smile_shift_skew_wing, implied_vol_from_call, implied_vol_bisect, is_iv_solver_failed, bracket_brackets_root)
def flat_svi() -> SVI = SVI { a: cast(0.04, f32), b: cast(0.0, f32), rho: cast(0.0, f32), m: cast(0.0, f32), sigma: cast(0.1, f32) }
def smile_svi() -> SVI = SVI { a: cast(0.04, f32), b: cast(0.2, f32), rho: cast(-0.3, f32), m: cast(0.0, f32), sigma: cast(0.1, f32) }
def test_flat_svi_total_variance_equals_a() -> unit ! { Test } = {
  p = flat_svi()
  w = vs_total_variance(p, cast(0.0, f32))
  assert_close(w, cast(0.04, f32), cast(0.000001, f32), "flat SVI at k=0 has w == a")
}
def test_flat_svi_independent_of_strike() -> unit ! { Test } = {
  p = flat_svi()
  w0 = vs_total_variance(p, cast(0.0, f32))
  w1 = vs_total_variance(p, cast(0.2, f32))
  diff = sub(w1, w0)
  assert_close(diff, cast(0.0, f32), cast(0.000001, f32), "flat SVI variance constant in k")
}
def test_smile_svi_higher_otm() -> unit ! { Test } = {
  p = smile_svi()
  w_atm = vs_total_variance(p, cast(0.0, f32))
  w_otm = vs_total_variance(p, cast(0.5, f32))
  assert_true(gt(w_otm, w_atm), "OTM total variance > ATM for smile")
}
def test_svi_implied_vol_atm_one_year() -> unit ! { Test } = {
  p = flat_svi()
  iv = vs_implied_vol(p, cast(0.0, f32), cast(1.0, f32))
  assert_close(iv, cast(0.2, f32), cast(0.00001, f32), "sqrt(a/t) = 0.2 for a=0.04, t=1")
}
def test_svi_shift_atm() -> unit ! { Test } = {
  p = flat_svi()
  shifted = vs_shift_atm(p, cast(0.02, f32))
  w_before = vs_total_variance(p, cast(0.0, f32))
  w_after = vs_total_variance(shifted, cast(0.0, f32))
  assert_close(sub(w_after, w_before), cast(0.02, f32), cast(0.000001, f32), "ATM shift adds delta_a to total variance")
}
def test_svi_shift_skew_changes_rho() -> unit ! { Test } = {
  p = smile_svi()
  shifted = vs_shift_skew(p, cast(0.1, f32))
  assert_close(shifted.rho, cast(-0.2, f32), cast(0.000001, f32), "rho updated from -0.3 to -0.2")
}
def test_smile_shift_adds_to_b() -> unit ! { Test } = {
  p = smile_svi()
  shifted = smile_shift_skew_wing(p, cast(0.05, f32))
  assert_close(shifted.b, cast(0.25, f32), cast(0.000001, f32), "smile shift increments b by delta")
}
def test_implied_vol_from_call_round_trip() -> unit ! { Test } = {
  spot = cast(100.0, f32)
  strike = cast(100.0, f32)
  r = cast(0.05, f32)
  t = cast(1.0, f32)
  sigma_true = cast(0.2, f32)
  price = bs_call_scalar(spot, strike, r, sigma_true, t)
  iv = implied_vol_from_call(spot, strike, r, t, price)
  assert_close(iv, sigma_true, cast(0.001, f32), "ATM 1y BS round-trip IV = 0.2")
}
def test_implied_vol_from_call_low_vol() -> unit ! { Test } = {
  spot = cast(100.0, f32)
  strike = cast(95.0, f32)
  r = cast(0.03, f32)
  t = cast(0.5, f32)
  sigma_true = cast(0.15, f32)
  price = bs_call_scalar(spot, strike, r, sigma_true, t)
  iv = implied_vol_from_call(spot, strike, r, t, price)
  assert_close(iv, sigma_true, cast(0.001, f32), "ITM 6m BS round-trip IV = 0.15")
}
def test_implied_vol_from_call_high_vol() -> unit ! { Test } = {
  spot = cast(100.0, f32)
  strike = cast(110.0, f32)
  r = cast(0.02, f32)
  t = cast(2.0, f32)
  sigma_true = cast(0.4, f32)
  price = bs_call_scalar(spot, strike, r, sigma_true, t)
  iv = implied_vol_from_call(spot, strike, r, t, price)
  assert_close(iv, sigma_true, cast(0.001, f32), "OTM 2y high-vol round-trip IV = 0.4")
}
def test_parallel_shift_atm_iv_actually_shifts_iv_by_delta() -> unit ! { Test } = {
  p = smile_svi()
  t = cast(1.0, f32)
  iv_before = vs_implied_vol(p, cast(0.0, f32), t)
  shifted = parallel_shift_atm_iv(p, cast(0.01, f32), t)
  iv_after = vs_implied_vol(shifted, cast(0.0, f32), t)
  assert_close(sub(iv_after, iv_before), cast(0.01, f32), cast(0.0001, f32), "parallel_shift_atm_iv lifts ATM IV by exactly delta")
}
def test_parallel_shift_atm_iv_on_flat_surface() -> unit ! { Test } = {
  p = flat_svi()
  t = cast(1.0, f32)
  iv_before = vs_implied_vol(p, cast(0.0, f32), t)
  shifted = parallel_shift_atm_iv(p, cast(0.02, f32), t)
  iv_after = vs_implied_vol(shifted, cast(0.0, f32), t)
  assert_close(sub(iv_after, iv_before), cast(0.02, f32), cast(0.0001, f32), "parallel_shift_atm_iv on flat surface lifts IV by delta")
}
def test_iv_solver_failure_on_unbracketed_target() -> unit ! { Test } = {
  iv = implied_vol_bisect(cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(1.0, f32), cast(200.0, f32), cast(0.0001, f32), cast(5.0, f32), cast(60, int64), cast(0.000001, f32))
  assert_true(is_iv_solver_failed(iv), "out-of-range target returns NaN sentinel rather than silently pinning at vol_hi")
}
def test_iv_solver_failure_on_negative_target() -> unit ! { Test } = {
  iv = implied_vol_bisect(cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(1.0, f32), cast(-1.0, f32), cast(0.0001, f32), cast(5.0, f32), cast(60, int64), cast(0.000001, f32))
  assert_true(is_iv_solver_failed(iv), "negative target returns NaN sentinel")
}
def test_bracket_brackets_root_valid() -> unit ! { Test } = {
  spot = cast(100.0, f32)
  strike = cast(100.0, f32)
  r = cast(0.05, f32)
  t = cast(1.0, f32)
  sigma_true = cast(0.2, f32)
  price = bs_call_scalar(spot, strike, r, sigma_true, t)
  assert_true(bracket_brackets_root(spot, strike, r, t, price, cast(0.01, f32), cast(1.0, f32)), "0.01 < 0.2 < 1.0 brackets the implied vol")
}
def test_bracket_brackets_root_invalid() -> unit ! { Test } = {
  spot = cast(100.0, f32)
  strike = cast(100.0, f32)
  r = cast(0.05, f32)
  t = cast(1.0, f32)
  sigma_true = cast(0.2, f32)
  price = bs_call_scalar(spot, strike, r, sigma_true, t)
  bracket_ok = bracket_brackets_root(spot, strike, r, t, price, cast(0.3, f32), cast(0.5, f32))
  assert_eq_bool(bracket_ok, false, "0.3 > 0.2 means lo and hi are same-sign; bracket invalid")
}
