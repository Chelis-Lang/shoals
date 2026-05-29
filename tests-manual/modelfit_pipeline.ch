module Shoals.Tests.ModelfitPipeline
import Std.Test (assert_close, assert_true)
import Shoals.ModelFit (sequential_pipeline_2stage)
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
