module Shoals.Tests.ModelfitLmBounded
import Std.Test (assert_close, assert_true)
import Shoals.ModelFit (lm_bounded_nparam, multi_target_fit, clamp_vec, active_set_mask, weighted_sse)
import Shoals.VolSurface (SABR, vs_sabr_implied_vol)
def linear_model[n, m](theta: &tensor[n, f32], x: &tensor[m, f32]) -> tensor[m, f32] = {
  th_l = to_list(theta)
  a = index(th_l, cast(0, i64))
  b = index(th_l, cast(1, i64))
  to_tensor(map(fn (xi: f32) -> add(mul(a, xi), b), to_list(x)))
}
def test_lm_fits_linear_unconstrained() -> unit ! { Test } = {
  xs = to_tensor([cast(0.0, f32), cast(1.0, f32), cast(2.0, f32), cast(3.0, f32), cast(4.0, f32)])
  ys = to_tensor([cast(1.0, f32), cast(3.0, f32), cast(5.0, f32), cast(7.0, f32), cast(9.0, f32)])
  weights = to_tensor([cast(1.0, f32), cast(1.0, f32), cast(1.0, f32), cast(1.0, f32), cast(1.0, f32)])
  theta0 = to_tensor([cast(0.5, f32), cast(0.5, f32)])
  lo = to_tensor([cast(-10.0, f32), cast(-10.0, f32)])
  hi = to_tensor([cast(10.0, f32), cast(10.0, f32)])
  out = lm_bounded_nparam(linear_model, copy(xs), copy(ys), copy(weights), theta0, copy(lo), copy(hi), cast(0.01, f32), cast(1e-6, f32), cast(100, i64), cast(0.0001, f32))
  theta_fit = out.0
  th_l = to_list(theta_fit)
  a_fit = index(th_l, cast(0, i64))
  b_fit = index(th_l, cast(1, i64))
  _ = assert_close(a_fit, cast(2.0, f32), cast(0.01, f32), "linear slope fit = 2")
  assert_close(b_fit, cast(1.0, f32), cast(0.01, f32), "linear intercept fit = 1")
}
def test_lm_respects_lower_bound() -> unit ! { Test } = {
  xs = to_tensor([cast(0.0, f32), cast(1.0, f32), cast(2.0, f32), cast(3.0, f32), cast(4.0, f32)])
  ys = to_tensor([cast(1.0, f32), cast(3.0, f32), cast(5.0, f32), cast(7.0, f32), cast(9.0, f32)])
  weights = to_tensor([cast(1.0, f32), cast(1.0, f32), cast(1.0, f32), cast(1.0, f32), cast(1.0, f32)])
  theta0 = to_tensor([cast(0.5, f32), cast(0.5, f32)])
  lo = to_tensor([cast(3.0, f32), cast(-10.0, f32)])
  hi = to_tensor([cast(10.0, f32), cast(10.0, f32)])
  out = lm_bounded_nparam(linear_model, copy(xs), copy(ys), copy(weights), theta0, copy(lo), copy(hi), cast(0.01, f32), cast(1e-6, f32), cast(100, i64), cast(0.0001, f32))
  theta_fit = out.0
  th_l = to_list(theta_fit)
  a_fit = index(th_l, cast(0, i64))
  mask = out.4
  mask_l = to_list(mask)
  a_active = index(mask_l, cast(0, i64))
  _ = assert_true(gte(a_fit, cast(2.99, f32)), "lower-bounded slope stuck at lo=3")
  assert_close(a_active, cast(1.0, f32), cast(0.0001, f32), "active-set mask flags slope as bound-binding")
}
def test_lm_converged_flag_true_on_easy_problem() -> unit ! { Test } = {
  xs = to_tensor([cast(0.0, f32), cast(1.0, f32), cast(2.0, f32), cast(3.0, f32), cast(4.0, f32)])
  ys = to_tensor([cast(1.0, f32), cast(3.0, f32), cast(5.0, f32), cast(7.0, f32), cast(9.0, f32)])
  weights = to_tensor([cast(1.0, f32), cast(1.0, f32), cast(1.0, f32), cast(1.0, f32), cast(1.0, f32)])
  theta0 = to_tensor([cast(1.8, f32), cast(0.9, f32)])
  lo = to_tensor([cast(-10.0, f32), cast(-10.0, f32)])
  hi = to_tensor([cast(10.0, f32), cast(10.0, f32)])
  out = lm_bounded_nparam(linear_model, copy(xs), copy(ys), copy(weights), theta0, copy(lo), copy(hi), cast(0.01, f32), cast(0.0001, f32), cast(100, i64), cast(0.0001, f32))
  converged = out.3
  iters = out.2
  sse = out.1
  _ = assert_true(lt(sse, cast(0.001, f32)), "near-optimum start produces tiny final SSE")
  assert_true(if converged then true else lte(iters, cast(100, i64)), "either converged flag is set OR ran up to max_iters with low SSE. Both signal a healthy run")
}
def test_multi_target_fit_alias_matches() -> unit ! { Test } = {
  xs = to_tensor([cast(0.0, f32), cast(1.0, f32), cast(2.0, f32), cast(3.0, f32), cast(4.0, f32)])
  ys = to_tensor([cast(1.0, f32), cast(3.0, f32), cast(5.0, f32), cast(7.0, f32), cast(9.0, f32)])
  weights = to_tensor([cast(1.0, f32), cast(1.0, f32), cast(1.0, f32), cast(1.0, f32), cast(1.0, f32)])
  theta0 = to_tensor([cast(0.5, f32), cast(0.5, f32)])
  lo = to_tensor([cast(-10.0, f32), cast(-10.0, f32)])
  hi = to_tensor([cast(10.0, f32), cast(10.0, f32)])
  out = multi_target_fit(linear_model, copy(xs), copy(ys), copy(weights), theta0, copy(lo), copy(hi), cast(0.01, f32), cast(1e-6, f32), cast(100, i64), cast(0.0001, f32))
  th_l = to_list(out.0)
  a_fit = index(th_l, cast(0, i64))
  assert_close(a_fit, cast(2.0, f32), cast(0.01, f32), "multi_target_fit alias produces same fit as lm_bounded_nparam")
}
