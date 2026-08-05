module Shoals.Tests.Curves
import Std.Test (assert_close)
import Shoals.Curves (YieldCurve, yield_curve_from_pillars, rate_at, discount_factor, bootstrap_zero_from_par)
def test_linear_rate_at_midpoint() -> unit ! { Test } = {
  curve = yield_curve_from_pillars(to_tensor([cast(1.0, f32), cast(2.0, f32), cast(3.0, f32)]), to_tensor([cast(0.03, f32), cast(0.04, f32), cast(0.045, f32)]))
  r = rate_at(curve, cast(1.5, f32))
  assert_close(r, cast(0.035, f32), cast(0.00001, f32), "1.5y rate == 3.5%")
}
def test_discount_factor_at_pillar() -> unit ! { Test } = {
  curve = yield_curve_from_pillars(to_tensor([cast(1.0, f32), cast(2.0, f32), cast(3.0, f32)]), to_tensor([cast(0.03, f32), cast(0.04, f32), cast(0.045, f32)]))
  d = discount_factor(curve, cast(2.0, f32))
  assert_close(d, cast(0.9231163, f32), cast(0.00001, f32), "P(2y) = exp(-0.08)")
}
def test_bootstrap_round_trip() -> unit ! { Test } = {
  times = to_tensor([cast(1.0, f32), cast(2.0, f32)])
  pars = to_tensor([cast(0.05, f32), cast(0.06, f32)])
  curve = bootstrap_zero_from_par(times, pars)
  p1 = discount_factor(curve, cast(1.0, f32))
  p2 = discount_factor(curve, cast(2.0, f32))
  pv = add(mul(cast(0.06, f32), p1), mul(cast(1.06, f32), p2))
  assert_close(pv, cast(1.0, f32), cast(0.0001, f32), "par bond reprices to 1.0")
}
def test_rate_at_pillar_exact() -> unit ! { Test } = {
  curve = yield_curve_from_pillars(to_tensor([cast(1.0, f32), cast(2.0, f32), cast(3.0, f32)]), to_tensor([cast(0.03, f32), cast(0.04, f32), cast(0.045, f32)]))
  r2 = rate_at(curve, cast(2.0, f32))
  assert_close(r2, cast(0.04, f32), cast(1e-7, f32), "pillar rate exact")
}
