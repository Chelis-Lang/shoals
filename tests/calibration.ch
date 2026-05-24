module Shoals.Tests.Calibration
import Std.Test (assert_close, assert_true)
import Shoals.Calibration (clamp_to_bounds, weighted_squared_residuals, vega_weighted_squared_residuals, weighted_absolute_residuals, sse_loss, lm_bounded_step_scalar)
def test_clamp_passthrough_in_range() -> unit ! { Test } = assert_close(clamp_to_bounds(cast(0.5, f32), cast(0.0, f32), cast(1.0, f32)), cast(0.5, f32), cast(0.000001, f32), "0.5 stays 0.5 in [0,1]")
def test_clamp_below_lo() -> unit ! { Test } = assert_close(clamp_to_bounds(cast(-1.0, f32), cast(0.0, f32), cast(1.0, f32)), cast(0.0, f32), cast(0.000001, f32), "-1 clamps to 0")
def test_clamp_above_hi() -> unit ! { Test } = assert_close(clamp_to_bounds(cast(5.0, f32), cast(0.0, f32), cast(1.0, f32)), cast(1.0, f32), cast(0.000001, f32), "5 clamps to 1")
def test_weighted_squared_zero_residuals() -> unit ! { Test } = {
  observed = to_tensor([cast(1.0, f32), cast(2.0, f32), cast(3.0, f32)])
  predicted = to_tensor([cast(1.0, f32), cast(2.0, f32), cast(3.0, f32)])
  weights = to_tensor([cast(1.0, f32), cast(1.0, f32), cast(1.0, f32)])
  res = weighted_squared_residuals(observed, predicted, weights)
  loss = sse_loss(res)
  assert_close(loss, cast(0.0, f32), cast(0.000001, f32), "zero residuals -> zero loss")
}
def test_weighted_squared_uniform_weights() -> unit ! { Test } = {
  observed = to_tensor([cast(1.0, f32), cast(2.0, f32), cast(3.0, f32)])
  predicted = to_tensor([cast(1.1, f32), cast(2.2, f32), cast(2.7, f32)])
  weights = to_tensor([cast(1.0, f32), cast(1.0, f32), cast(1.0, f32)])
  res = weighted_squared_residuals(observed, predicted, weights)
  loss = sse_loss(res)
  expected = add(add(cast(0.01, f32), cast(0.04, f32)), cast(0.09, f32))
  assert_close(loss, expected, cast(0.00001, f32), "SSE = 0.01 + 0.04 + 0.09 = 0.14")
}
def test_vega_weighted_higher_at_low_vega() -> unit ! { Test } = {
  observed = to_tensor([cast(0.2, f32), cast(0.25, f32)])
  predicted = to_tensor([cast(0.21, f32), cast(0.26, f32)])
  vegas = to_tensor([cast(0.5, f32), cast(2.0, f32)])
  res = vega_weighted_squared_residuals(observed, predicted, vegas)
  res_l = to_list(res)
  r0 = index(res_l, cast(0, int64))
  r1 = index(res_l, cast(1, int64))
  assert_true(gt(r0, r1), "lower-vega point gets higher weight when residuals equal magnitude")
}
def test_weighted_absolute_zero_residuals() -> unit ! { Test } = {
  observed = to_tensor([cast(1.0, f32), cast(2.0, f32)])
  predicted = to_tensor([cast(1.0, f32), cast(2.0, f32)])
  weights = to_tensor([cast(1.0, f32), cast(1.0, f32)])
  res = weighted_absolute_residuals(observed, predicted, weights)
  loss = sse_loss(res)
  assert_close(loss, cast(0.0, f32), cast(0.000001, f32), "zero residuals -> zero L1 loss")
}
def test_weighted_absolute_nonneg() -> unit ! { Test } = {
  observed = to_tensor([cast(1.0, f32), cast(-2.0, f32)])
  predicted = to_tensor([cast(3.0, f32), cast(0.0, f32)])
  weights = to_tensor([cast(1.0, f32), cast(1.0, f32)])
  res = weighted_absolute_residuals(observed, predicted, weights)
  loss = sse_loss(res)
  assert_close(loss, cast(4.0, f32), cast(0.000001, f32), "|1-3| + |-2-0| = 4")
}
def test_lm_step_zero_residual_no_move() -> unit ! { Test } = {
  step = lm_bounded_step_scalar(cast(1.0, f32), cast(0.0, f32), cast(0.001, f32), cast(0.5, f32), cast(0.0, f32), cast(1.0, f32))
  assert_close(step, cast(0.5, f32), cast(0.000001, f32), "no residual => no move")
}
def test_lm_step_positive_residual_moves_down() -> unit ! { Test } = {
  step = lm_bounded_step_scalar(cast(1.0, f32), cast(0.1, f32), cast(0.001, f32), cast(0.5, f32), cast(0.0, f32), cast(1.0, f32))
  assert_true(lt(step, cast(0.5, f32)), "positive J^T r => move parameter down")
}
def test_lm_step_clamped_at_lower_bound() -> unit ! { Test } = {
  step = lm_bounded_step_scalar(cast(1.0, f32), cast(100.0, f32), cast(0.001, f32), cast(0.5, f32), cast(0.0, f32), cast(1.0, f32))
  assert_close(step, cast(0.0, f32), cast(0.000001, f32), "huge negative step clamps to lo bound 0")
}
def test_lm_step_clamped_at_upper_bound() -> unit ! { Test } = {
  step = lm_bounded_step_scalar(cast(1.0, f32), cast(-100.0, f32), cast(0.001, f32), cast(0.5, f32), cast(0.0, f32), cast(1.0, f32))
  assert_close(step, cast(1.0, f32), cast(0.000001, f32), "huge positive step clamps to hi bound 1")
}
def test_lm_step_damping_attenuates_move() -> unit ! { Test } = {
  small_damp = lm_bounded_step_scalar(cast(1.0, f32), cast(0.1, f32), cast(0.001, f32), cast(0.5, f32), cast(0.0, f32), cast(1.0, f32))
  big_damp = lm_bounded_step_scalar(cast(1.0, f32), cast(0.1, f32), cast(10.0, f32), cast(0.5, f32), cast(0.0, f32), cast(1.0, f32))
  diff_small = sub(cast(0.5, f32), small_damp)
  diff_big = sub(cast(0.5, f32), big_damp)
  assert_true(gt(diff_small, diff_big), "smaller lambda damping -> larger Newton-like step")
}
