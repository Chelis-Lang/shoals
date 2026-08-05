module Shoals.Tests.ModelfitBfgs
import Std.Test (assert_close, assert_true)
import Shoals.ModelFit (bfgs_bounded_nparam)
def linear_model[n, m](theta: &tensor[n, f32], x: &tensor[m, f32]) -> tensor[m, f32] = {
  th_l = to_list(theta)
  a = index(th_l, cast(0, int64))
  b = index(th_l, cast(1, int64))
  to_tensor(map(fn (xi: f32) -> add(mul(a, xi), b), to_list(x)))
}
def test_bfgs_linear_unconstrained() -> unit ! { Test } = {
  xs = to_tensor([cast(0.0, f32), cast(1.0, f32), cast(2.0, f32), cast(3.0, f32), cast(4.0, f32)])
  ys = to_tensor([cast(1.0, f32), cast(3.0, f32), cast(5.0, f32), cast(7.0, f32), cast(9.0, f32)])
  weights = to_tensor([cast(1.0, f32), cast(1.0, f32), cast(1.0, f32), cast(1.0, f32), cast(1.0, f32)])
  theta0 = to_tensor([cast(0.5, f32), cast(0.5, f32)])
  lo = to_tensor([cast(-10.0, f32), cast(-10.0, f32)])
  hi = to_tensor([cast(10.0, f32), cast(10.0, f32)])
  out = bfgs_bounded_nparam(linear_model, copy(xs), copy(ys), copy(weights), theta0, copy(lo), copy(hi), cast(1e-6, f32), cast(200, int64), cast(0.0001, f32))
  theta_fit = out.0
  th_l = to_list(theta_fit)
  a_fit = index(th_l, cast(0, int64))
  b_fit = index(th_l, cast(1, int64))
  _ = assert_close(a_fit, cast(2.0, f32), cast(0.01, f32), "BFGS linear slope = 2")
  assert_close(b_fit, cast(1.0, f32), cast(0.01, f32), "BFGS linear intercept = 1")
}
def test_bfgs_respects_lower_bound() -> unit ! { Test } = {
  xs = to_tensor([cast(0.0, f32), cast(1.0, f32), cast(2.0, f32), cast(3.0, f32), cast(4.0, f32)])
  ys = to_tensor([cast(1.0, f32), cast(3.0, f32), cast(5.0, f32), cast(7.0, f32), cast(9.0, f32)])
  weights = to_tensor([cast(1.0, f32), cast(1.0, f32), cast(1.0, f32), cast(1.0, f32), cast(1.0, f32)])
  theta0 = to_tensor([cast(3.5, f32), cast(0.5, f32)])
  lo = to_tensor([cast(3.0, f32), cast(-10.0, f32)])
  hi = to_tensor([cast(10.0, f32), cast(10.0, f32)])
  out = bfgs_bounded_nparam(linear_model, copy(xs), copy(ys), copy(weights), theta0, copy(lo), copy(hi), cast(1e-6, f32), cast(200, int64), cast(0.0001, f32))
  theta_fit = out.0
  th_l = to_list(theta_fit)
  a_fit = index(th_l, cast(0, int64))
  mask = out.4
  mask_l = to_list(mask)
  a_active = index(mask_l, cast(0, int64))
  _ = assert_true(gte(a_fit, cast(2.99, f32)), "BFGS lower-bounded slope >= 3")
  assert_close(a_active, cast(1.0, f32), cast(0.0001, f32), "BFGS active-set mask flags slope as bound-binding")
}
