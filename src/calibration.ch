module Shoals.Calibration
export (weighted_squared_residuals, vega_weighted_squared_residuals, weighted_absolute_residuals, clamp_to_bounds, lm_bounded_step_scalar, sse_loss)
def clamp_to_bounds(x: f32, lo: f32, hi: f32) -> f32 = if lt(x, lo) then lo else if gt(x, hi) then hi else x
def weighted_squared_residuals[n](observed: tensor[n, f32], predicted: tensor[n, f32], weights: tensor[n, f32]) -> tensor[n, f32] = {
  o_l = to_list(copy(observed))
  p_l = to_list(copy(predicted))
  w_l = to_list(copy(weights))
  obs_pred = zip(o_l, p_l)
  triples = zip(obs_pred, w_l)
  to_tensor(map(fn (entry: ((f32, f32), f32)) -> {
    op = entry.0
    w = entry.1
    obs = op.0
    pred = op.1
    diff = sub(obs, pred)
    mul(w, mul(diff, diff))
  }, triples))
}
def vega_weighted_squared_residuals[n](observed: tensor[n, f32], predicted: tensor[n, f32], vegas: tensor[n, f32]) -> tensor[n, f32] = {
  v_l = to_list(copy(vegas))
  inv_vega_weights = to_tensor(map(fn (v: f32) -> if eq(v, cast(0.0, f32)) then cast(0.0, f32) else div(cast(1.0, f32), mul(v, v)), v_l))
  weighted_squared_residuals(observed, predicted, inv_vega_weights)
}
def weighted_absolute_residuals[n](observed: tensor[n, f32], predicted: tensor[n, f32], weights: tensor[n, f32]) -> tensor[n, f32] = {
  o_l = to_list(copy(observed))
  p_l = to_list(copy(predicted))
  w_l = to_list(copy(weights))
  obs_pred = zip(o_l, p_l)
  triples = zip(obs_pred, w_l)
  to_tensor(map(fn (entry: ((f32, f32), f32)) -> {
    op = entry.0
    w = entry.1
    obs = op.0
    pred = op.1
    diff = sub(obs, pred)
    abs_diff = if lt(diff, cast(0.0, f32)) then neg(diff) else diff
    mul(w, abs_diff)
  }, triples))
}
def sse_loss[n](residuals: tensor[n, f32]) -> f32 = tensor_to_scalar(sum(residuals, 0))
def lm_bounded_step_scalar(jtj: f32, jtr: f32, lambda: f32, current: f32, lo: f32, hi: f32) -> f32 = {
  numerator = jtr
  denominator = add(jtj, lambda)
  step = if eq(denominator, cast(0.0, f32)) then cast(0.0, f32) else div(numerator, denominator)
  proposed = sub(current, step)
  clamp_to_bounds(proposed, lo, hi)
}
