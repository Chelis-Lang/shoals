module Shoals.Tests.ModelfitPipeline
import Std.Test (assert_close, assert_true)
import Shoals.ModelFit (sequential_pipeline_2stage, sequential_pipeline_2stage_gradient, lm_bounded_nparam)
def mp_linear_model[n, m](theta: &tensor[n, f32], x: &tensor[m, f32]) -> tensor[m, f32] = {
  th_l = to_list(theta)
  a = index(th_l, cast(0, int64))
  b = index(th_l, cast(1, int64))
  to_tensor(map(fn (xi: f32) -> add(mul(a, xi), b), to_list(x)))
}
def mp_stage1_to_stage2_passthrough[n](theta1: &tensor[n, f32]) -> tensor[2, f32] = {
  th_l = to_list(theta1)
  a = index(th_l, cast(0, int64))
  b = index(th_l, cast(1, int64))
  to_tensor([a, b])
}
def mp_stage2_model[n, m](theta: &tensor[n, f32], features: &tensor[m, f32]) -> tensor[m, f32] = {
  th_l = to_list(theta)
  c = index(th_l, cast(0, int64))
  d = index(th_l, cast(1, int64))
  f_l = to_list(features)
  a = index(f_l, cast(0, int64))
  b = index(f_l, cast(1, int64))
  to_tensor([mul(c, a), mul(d, b)])
}
def mp_run_pipeline_default() -> (tensor[2, f32], tensor[2, f32], f32, f32, int64, int64, bool, bool) = {
  xs = to_tensor([cast(0.0, f32), cast(1.0, f32), cast(2.0, f32), cast(3.0, f32), cast(4.0, f32)])
  ys = to_tensor([cast(1.0, f32), cast(3.0, f32), cast(5.0, f32), cast(7.0, f32), cast(9.0, f32)])
  weights1 = to_tensor([cast(1.0, f32), cast(1.0, f32), cast(1.0, f32), cast(1.0, f32), cast(1.0, f32)])
  theta1_0 = to_tensor([cast(0.5, f32), cast(0.5, f32)])
  lo1 = to_tensor([cast(-10.0, f32), cast(-10.0, f32)])
  hi1 = to_tensor([cast(10.0, f32), cast(10.0, f32)])
  observed2 = to_tensor([cast(4.0, f32), cast(2.0, f32)])
  weights2 = to_tensor([cast(1.0, f32), cast(1.0, f32)])
  theta2_0 = to_tensor([cast(1.0, f32), cast(1.0, f32)])
  lo2 = to_tensor([cast(-10.0, f32), cast(-10.0, f32)])
  hi2 = to_tensor([cast(10.0, f32), cast(10.0, f32)])
  sequential_pipeline_2stage(mp_linear_model, copy(xs), copy(ys), copy(weights1), theta1_0, copy(lo1), copy(hi1), mp_stage1_to_stage2_passthrough, mp_stage2_model, copy(observed2), copy(weights2), theta2_0, copy(lo2), copy(hi2), cast(0.01, f32), cast(0.000001, f32), cast(100, int64), cast(0.0001, f32))
}
def test_pipeline_2stage_linear_chain() -> unit ! { Test } = {
  out = mp_run_pipeline_default()
  theta1_fit = out.0
  theta2_fit = out.1
  th1_l = to_list(theta1_fit)
  th2_l = to_list(theta2_fit)
  a_fit = index(th1_l, cast(0, int64))
  b_fit = index(th1_l, cast(1, int64))
  c_fit = index(th2_l, cast(0, int64))
  d_fit = index(th2_l, cast(1, int64))
  _ = assert_close(a_fit, cast(2.0, f32), cast(0.01, f32), "stage 1 slope a fits to 2")
  _ = assert_close(b_fit, cast(1.0, f32), cast(0.01, f32), "stage 1 intercept b fits to 1")
  _ = assert_close(c_fit, cast(2.0, f32), cast(0.05, f32), "stage 2 c fits to 4/a ~= 2")
  assert_close(d_fit, cast(2.0, f32), cast(0.05, f32), "stage 2 d fits to 2/b ~= 2")
}
def test_pipeline_2stage_each_stage_converged() -> unit ! { Test } = {
  xs = to_tensor([cast(0.0, f32), cast(1.0, f32), cast(2.0, f32), cast(3.0, f32), cast(4.0, f32)])
  ys = to_tensor([cast(1.05, f32), cast(2.95, f32), cast(5.02, f32), cast(6.98, f32), cast(9.01, f32)])
  weights1 = to_tensor([cast(1.0, f32), cast(1.0, f32), cast(1.0, f32), cast(1.0, f32), cast(1.0, f32)])
  theta1_0 = to_tensor([cast(1.8, f32), cast(0.9, f32)])
  lo1 = to_tensor([cast(-10.0, f32), cast(-10.0, f32)])
  hi1 = to_tensor([cast(10.0, f32), cast(10.0, f32)])
  observed2 = to_tensor([cast(4.05, f32), cast(2.05, f32)])
  weights2 = to_tensor([cast(1.0, f32), cast(1.0, f32)])
  theta2_0 = to_tensor([cast(1.9, f32), cast(1.9, f32)])
  lo2 = to_tensor([cast(-10.0, f32), cast(-10.0, f32)])
  hi2 = to_tensor([cast(10.0, f32), cast(10.0, f32)])
  max_it = cast(200, int64)
  out = sequential_pipeline_2stage(mp_linear_model, copy(xs), copy(ys), copy(weights1), theta1_0, copy(lo1), copy(hi1), mp_stage1_to_stage2_passthrough, mp_stage2_model, copy(observed2), copy(weights2), theta2_0, copy(lo2), copy(hi2), cast(0.01, f32), cast(0.0001, f32), max_it, cast(0.0001, f32))
  sse1 = out.2
  sse2 = out.3
  iters1 = out.4
  iters2 = out.5
  conv1 = out.6
  conv2 = out.7
  healthy1 = if conv1 then true else if lt(sse1, cast(0.01, f32)) then lte(iters1, max_it) else false
  healthy2 = if conv2 then true else if lt(sse2, cast(0.01, f32)) then lte(iters2, max_it) else false
  _ = assert_true(healthy1, "stage 1 either reports converged or hit max_iters with low SSE")
  assert_true(healthy2, "stage 2 either reports converged or hit max_iters with low SSE")
}
def mp_pipeline_at_observed1(observed1: tensor[5, f32]) -> tensor[2, f32] = {
  xs = to_tensor([cast(0.0, f32), cast(1.0, f32), cast(2.0, f32), cast(3.0, f32), cast(4.0, f32)])
  weights1 = to_tensor([cast(1.0, f32), cast(1.0, f32), cast(1.0, f32), cast(1.0, f32), cast(1.0, f32)])
  theta1_0 = to_tensor([cast(0.5, f32), cast(0.5, f32)])
  lo1 = to_tensor([cast(-10.0, f32), cast(-10.0, f32)])
  hi1 = to_tensor([cast(10.0, f32), cast(10.0, f32)])
  observed2 = to_tensor([cast(4.0, f32), cast(2.0, f32)])
  weights2 = to_tensor([cast(1.0, f32), cast(1.0, f32)])
  theta2_0 = to_tensor([cast(1.0, f32), cast(1.0, f32)])
  lo2 = to_tensor([cast(-10.0, f32), cast(-10.0, f32)])
  hi2 = to_tensor([cast(10.0, f32), cast(10.0, f32)])
  out = sequential_pipeline_2stage(mp_linear_model, copy(xs), copy(observed1), copy(weights1), theta1_0, copy(lo1), copy(hi1), mp_stage1_to_stage2_passthrough, mp_stage2_model, copy(observed2), copy(weights2), theta2_0, copy(lo2), copy(hi2), cast(0.01, f32), cast(0.000001, f32), cast(200, int64), cast(0.0001, f32))
  out.1
}
def mp_bump_jth(observed1: &tensor[5, f32], j: int64, eps: f32) -> tensor[5, f32] = {
  obs_l = to_list(observed1)
  n = len(obs_l)
  idxs = range(cast(0, int64), n)
  pairs = zip(idxs, obs_l)
  to_tensor(map(fn (e: (int64, f32)) -> if eq(e.0, j) then add(e.1, eps) else e.1, pairs))
}
def mp_rel_err(a: f32, b: f32) -> f32 = {
  diff = sub(a, b)
  abs_diff = if lt(diff, cast(0.0, f32)) then neg(diff) else diff
  abs_b = if lt(b, cast(0.0, f32)) then neg(b) else b
  denom = if lt(abs_b, cast(0.0001, f32)) then cast(0.0001, f32) else abs_b
  div(abs_diff, denom)
}
def test_pipeline_2stage_gradient_vs_full_fd_bump() -> unit ! { Test } = {
  xs = to_tensor([cast(0.0, f32), cast(1.0, f32), cast(2.0, f32), cast(3.0, f32), cast(4.0, f32)])
  ys = to_tensor([cast(1.0, f32), cast(3.0, f32), cast(5.0, f32), cast(7.0, f32), cast(9.0, f32)])
  weights1 = to_tensor([cast(1.0, f32), cast(1.0, f32), cast(1.0, f32), cast(1.0, f32), cast(1.0, f32)])
  theta1_0 = to_tensor([cast(0.5, f32), cast(0.5, f32)])
  lo1 = to_tensor([cast(-10.0, f32), cast(-10.0, f32)])
  hi1 = to_tensor([cast(10.0, f32), cast(10.0, f32)])
  observed2 = to_tensor([cast(4.0, f32), cast(2.0, f32)])
  weights2 = to_tensor([cast(1.0, f32), cast(1.0, f32)])
  theta2_0 = to_tensor([cast(1.0, f32), cast(1.0, f32)])
  lo2 = to_tensor([cast(-10.0, f32), cast(-10.0, f32)])
  hi2 = to_tensor([cast(10.0, f32), cast(10.0, f32)])
  bump_eps = cast(0.001, f32)
  jac = sequential_pipeline_2stage_gradient(mp_linear_model, copy(xs), copy(ys), copy(weights1), copy(theta1_0), copy(lo1), copy(hi1), mp_stage1_to_stage2_passthrough, mp_stage2_model, copy(observed2), copy(weights2), copy(theta2_0), copy(lo2), copy(hi2), cast(0.01, f32), cast(0.000001, f32), cast(200, int64), cast(0.0001, f32), bump_eps)
  theta2_base = mp_pipeline_at_observed1(copy(ys))
  theta2_base_l = to_list(theta2_base)
  jac_flat = to_list(reshape(jac, [cast(10, int64)]))
  m1_len = cast(5, int64)
  idxs_j = range(cast(0, int64), m1_len)
  per_col_ok = map(fn (j: int64) -> {
    ys_bumped = mp_bump_jth(copy(ys), j, bump_eps)
    theta2_bumped = mp_pipeline_at_observed1(ys_bumped)
    theta2_bumped_l = to_list(theta2_bumped)
    g0_ref = div(sub(index(theta2_bumped_l, cast(0, int64)), index(theta2_base_l, cast(0, int64))), bump_eps)
    g1_ref = div(sub(index(theta2_bumped_l, cast(1, int64)), index(theta2_base_l, cast(1, int64))), bump_eps)
    g0_api = index(jac_flat, j)
    g1_api = index(jac_flat, add(m1_len, j))
    rel0 = mp_rel_err(g0_api, g0_ref)
    rel1 = mp_rel_err(g1_api, g1_ref)
    if lt(rel0, cast(0.02, f32)) then lt(rel1, cast(0.02, f32)) else false
  }, idxs_j)
  all_ok = fold(fn (acc: bool, b: bool) -> if acc then b else false, true, per_col_ok)
  assert_true(all_ok, "pipeline-composition gradient agrees with full-pipeline FD bump on observed1 within 2% relative per entry")
}
