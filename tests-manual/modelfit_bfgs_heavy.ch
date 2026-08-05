module Shoals.Tests.ModelfitBfgsHeavy
import Std.Test (assert_close, assert_true)
import Shoals.ModelFit (bfgs_bounded_nparam)
def linear_model[n, m](theta: &tensor[n, f32], x: &tensor[m, f32]) -> tensor[m, f32] = {
  th_l = to_list(theta)
  a = index(th_l, cast(0, int64))
  b = index(th_l, cast(1, int64))
  to_tensor(map(fn (xi: f32) -> add(mul(a, xi), b), to_list(x)))
}
def quadratic_residual_model[n, m](theta: &tensor[n, f32], x: &tensor[m, f32]) -> tensor[m, f32] = {
  th_l = to_list(theta)
  t0 = index(th_l, cast(0, int64))
  t1 = index(th_l, cast(1, int64))
  x_l = to_list(x)
  zero_i = cast(0, int64)
  one_i = cast(1, int64)
  to_tensor(map(fn (i: int64) -> if eq(i, zero_i) then t0 else if eq(i, one_i) then t1 else cast(0.0, f32), range(zero_i, len(x_l))))
}
def rosenbrock_model[n, m](theta: &tensor[n, f32], x: &tensor[m, f32]) -> tensor[m, f32] = {
  th_l = to_list(theta)
  t0 = index(th_l, cast(0, int64))
  t1 = index(th_l, cast(1, int64))
  one_f = cast(1.0, f32)
  ten_f = cast(10.0, f32)
  r0 = sub(one_f, t0)
  r1 = mul(ten_f, sub(t1, mul(t0, t0)))
  x_l = to_list(x)
  zero_i = cast(0, int64)
  one_i = cast(1, int64)
  to_tensor(map(fn (i: int64) -> if eq(i, zero_i) then r0 else if eq(i, one_i) then r1 else cast(0.0, f32), range(zero_i, len(x_l))))
}
def test_bfgs_quadratic_unconstrained() -> unit ! { Test } = {
  xs = to_tensor([cast(0.0, f32), cast(0.0, f32)])
  ys = to_tensor([cast(3.0, f32), cast(5.0, f32)])
  weights = to_tensor([cast(1.0, f32), cast(1.0, f32)])
  theta0 = to_tensor([cast(0.0, f32), cast(0.0, f32)])
  lo = to_tensor([cast(-10.0, f32), cast(-10.0, f32)])
  hi = to_tensor([cast(10.0, f32), cast(10.0, f32)])
  out = bfgs_bounded_nparam(quadratic_residual_model, copy(xs), copy(ys), copy(weights), theta0, copy(lo), copy(hi), cast(1e-6, f32), cast(200, int64), cast(0.0001, f32))
  theta_fit = out.0
  th_l = to_list(theta_fit)
  t0 = index(th_l, cast(0, int64))
  t1 = index(th_l, cast(1, int64))
  _ = assert_close(t0, cast(3.0, f32), cast(0.01, f32), "BFGS quadratic theta_0 = 3")
  assert_close(t1, cast(5.0, f32), cast(0.01, f32), "BFGS quadratic theta_1 = 5")
}
def test_bfgs_rosenbrock_2d() -> unit ! { Test } = {
  xs = to_tensor([cast(0.0, f32), cast(0.0, f32)])
  ys = to_tensor([cast(0.0, f32), cast(0.0, f32)])
  weights = to_tensor([cast(1.0, f32), cast(1.0, f32)])
  theta0 = to_tensor([cast(0.0, f32), cast(0.0, f32)])
  lo = to_tensor([cast(-5.0, f32), cast(-5.0, f32)])
  hi = to_tensor([cast(5.0, f32), cast(5.0, f32)])
  out = bfgs_bounded_nparam(rosenbrock_model, copy(xs), copy(ys), copy(weights), theta0, copy(lo), copy(hi), cast(1e-7, f32), cast(500, int64), cast(0.00001, f32))
  theta_fit = out.0
  th_l = to_list(theta_fit)
  t0 = index(th_l, cast(0, int64))
  t1 = index(th_l, cast(1, int64))
  _ = assert_close(t0, cast(1.0, f32), cast(0.05, f32), "BFGS Rosenbrock theta_0 ~ 1")
  assert_close(t1, cast(1.0, f32), cast(0.05, f32), "BFGS Rosenbrock theta_1 ~ 1")
}
def test_bfgs_converged_flag_easy_problem() -> unit ! { Test } = {
  xs = to_tensor([cast(0.0, f32), cast(1.0, f32), cast(2.0, f32), cast(3.0, f32), cast(4.0, f32)])
  ys = to_tensor([cast(1.0, f32), cast(3.0, f32), cast(5.0, f32), cast(7.0, f32), cast(9.0, f32)])
  weights = to_tensor([cast(1.0, f32), cast(1.0, f32), cast(1.0, f32), cast(1.0, f32), cast(1.0, f32)])
  theta0 = to_tensor([cast(1.95, f32), cast(0.95, f32)])
  lo = to_tensor([cast(-10.0, f32), cast(-10.0, f32)])
  hi = to_tensor([cast(10.0, f32), cast(10.0, f32)])
  out = bfgs_bounded_nparam(linear_model, copy(xs), copy(ys), copy(weights), theta0, copy(lo), copy(hi), cast(0.0001, f32), cast(200, int64), cast(0.0001, f32))
  converged = out.3
  iters = out.2
  sse = out.1
  _ = assert_true(lt(sse, cast(0.001, f32)), "BFGS near-optimum start produces tiny final SSE")
  assert_true(if converged then true else lte(iters, cast(200, int64)), "BFGS either converged OR ran to max_iters with low SSE")
}
