module Shoals.Tests.Lsm
import Std.Test (assert_true)
import Shoals.Lsm (lsm_polynomial_regression)
def lsm_t_abs_f32(x: f32) -> f32 = if lt(x, cast(0.0, f32)) then neg(x) else x
def test_lsm_polynomial_regression_recovers_quadratic() -> unit ! { Test } = {
  xs = to_tensor(map(fn (i: int64) -> add(cast(-1.0, f32), cast(i, f32)), range(cast(0, int64), cast(5, int64))))
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
