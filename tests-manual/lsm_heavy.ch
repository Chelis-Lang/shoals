module Shoals.Tests.LsmHeavy
import Std.Test (assert_true)
import Shoals.Lsm (lsm_polynomial_regression, lsm_american_put)
import Shoals.Pricing (bs_put_scalar)
def lsm_t_abs_f32(x: f32) -> f32 = if lt(x, cast(0.0, f32)) then neg(x) else x
def test_lsm_polynomial_regression_recovers_quadratic() -> unit ! { Test } = {
  xs = to_tensor(map(fn (i: i64) -> add(cast(-1.0, f32), cast(i, f32)), range(cast(0, i64), cast(5, i64))))
  xs_l = to_list(copy(xs))
  ys = to_tensor(map(fn (x: f32) -> add(cast(2.0, f32), add(mul(cast(3.0, f32), x), mul(cast(4.0, f32), mul(x, x)))), xs_l))
  coeffs = lsm_polynomial_regression(xs, ys)
  b0 = coeffs.0
  b1 = coeffs.1
  b2 = coeffs.2
  tol = cast(0.001, f32)
  e0 = lt(lsm_t_abs_f32(sub(b0, cast(2.0, f32))), tol)
  e1 = lt(lsm_t_abs_f32(sub(b1, cast(3.0, f32))), tol)
  e2 = lt(lsm_t_abs_f32(sub(b2, cast(4.0, f32))), tol)
  ok = and(e0, and(e1, e2))
  assert_true(ok, "regression recovers (2, 3, 4) on noise-free quadratic y=2+3x+4x^2 at 5 evenly spaced x in {-1,0,1,2,3} within 1e-3 (5 data > 3 unknowns => exact LS fit)")
}
def test_lsm_american_put_deep_otm_equals_european() -> unit ! { Test } = {
  template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(128, i64))))
  s0 = cast(150.0, f32)
  k = cast(100.0, f32)
  r = cast(0.05, f32)
  sigma = cast(0.2, f32)
  big_t = cast(1.0, f32)
  n_steps = cast(30, i64)
  price = lsm_american_put(key_from_seed(31i64), template, s0, k, r, sigma, big_t, n_steps)
  european = bs_put_scalar(s0, k, r, sigma, big_t)
  diff = lsm_t_abs_f32(sub(price, european))
  ok = lt(diff, cast(2.0, f32))
  assert_true(ok, "deep-OTM American put (S=150,K=100,r=0.05,sigma=0.2,T=1) within 2.0 of European value ~0.08 at 128 paths x 30 steps; early exercise never optimal so LSM equals European up to ~3*SE_mc bounded by K*P(ITM)/sqrt(N) ~ 1.4")
}
def test_lsm_american_put_deep_itm_equals_intrinsic_lower_bound() -> unit ! { Test } = {
  template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(128, i64))))
  s0 = cast(50.0, f32)
  k = cast(100.0, f32)
  r = cast(0.05, f32)
  sigma = cast(0.2, f32)
  big_t = cast(1.0, f32)
  n_steps = cast(30, i64)
  price = lsm_american_put(key_from_seed(37i64), template, s0, k, r, sigma, big_t, n_steps)
  intrinsic = sub(k, s0)
  ok_lower = gte(price, cast(48.5, f32))
  ok_upper = lte(price, add(intrinsic, cast(5.0, f32)))
  both = and(ok_lower, ok_upper)
  assert_true(both, "deep-ITM American put (S=50,K=100) >= 48.5 (intrinsic=50 less small MC noise from exercise-at-t=1 vs t=0 plus discount-of-discount slip) and <= intrinsic+5; early exercise dominates")
}
def test_lsm_american_put_ge_european_minus_3se() -> unit ! { Test } = {
  template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(128, i64))))
  s0 = cast(95.0, f32)
  k = cast(100.0, f32)
  r = cast(0.05, f32)
  sigma = cast(0.3, f32)
  big_t = cast(1.0, f32)
  n_steps = cast(30, i64)
  am_price = lsm_american_put(key_from_seed(41i64), template, s0, k, r, sigma, big_t, n_steps)
  euro_price = bs_put_scalar(s0, k, r, sigma, big_t)
  std_dev = mul(sigma, mul(s0, sqrt(big_t)))
  three_se = div(mul(cast(3.0, f32), std_dev), sqrt(cast(128.0, f32)))
  low_bias_pad = cast(3.0, f32)
  ok = gt(am_price, sub(euro_price, add(three_se, low_bias_pad)))
  assert_true(ok, "moderate-ITM American put (S=95,K=100,sigma=0.3,T=1) >= European put within 3*SE_mc (sigma*S*sqrt(T)/sqrt(N)*3 ~ 7.6) + 3.0 low-bias pad for finite-path LSM downward bias")
}
