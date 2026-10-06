module Shoals.Tests.NativeErfPricing
import Shoals.Pricing (erf64, n_cdf64)
import Std.Test (assert_eq, assert_true)
def test_erf64_uses_chelis_primitive() -> unit ! { Test } = {
  _ = assert_eq(erf64(0.5f64), erf(0.5f64), "Shoals erf64 uses the Chelis primitive")
  assert_eq(erf64(-4.0f64), erf(-4.0f64), "Shoals erf64 agrees in the negative tail")
}
def test_normal_cdf_keeps_left_tail() -> unit ! { Test } = {
  at_eight = n_cdf64(-8.0f64)
  at_eight_half = n_cdf64(-8.5f64)
  at_nine = n_cdf64(-9.0f64)
  _ = assert_true(gt(at_eight, 0.0f64), "normal CDF at -8 remains positive")
  _ = assert_true(gt(at_eight_half, 0.0f64), "normal CDF at -8.5 remains positive")
  assert_true(gt(at_nine, 0.0f64), "normal CDF at -9 remains positive")
}
def test_normal_cdf_boundary_and_tensor_lanes() -> unit ! { Test } = {
  xs = to_tensor([-8.5f64, -8.0f64, -1e-6f64, 0.0f64, 1e-6f64, 8.0f64])
  ys = to_list(standard_normal_cdf(xs))
  _ = assert_eq(index(ys, 0i64), n_cdf64(-8.5f64), "tensor left tail matches scalar")
  _ = assert_eq(index(ys, 1i64), n_cdf64(-8.0f64), "tensor at -8 matches scalar")
  _ = assert_eq(index(ys, 2i64), n_cdf64(-1e-6f64), "tensor below zero matches scalar")
  _ = assert_eq(index(ys, 3i64), n_cdf64(0.0f64), "tensor at zero matches scalar")
  _ = assert_eq(index(ys, 4i64), n_cdf64(1e-6f64), "tensor above zero matches scalar")
  assert_eq(index(ys, 5i64), n_cdf64(8.0f64), "tensor right tail matches scalar")
}
