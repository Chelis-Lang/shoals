module Shoals.Risk
import Nautilus.Distributions (normal_inv_cdf)
import Nautilus.Stats (mean_vec, std_vec, quantile_vec)
export (parametric_var, parametric_cvar, historical_var, historical_cvar, empirical_loss_quantile)
def parametric_var[n](losses: tensor[n, f32], confidence: f32) -> f32 = {
  losses_copy = copy(losses)
  mu = mean_vec(copy(losses_copy))
  sigma_loss = std_vec(losses_copy, cast(1, i64))
  z = normal_inv_cdf(confidence, cast(0.0, f32), cast(1.0, f32))
  add(mu, mul(sigma_loss, z))
}
def parametric_cvar[n](losses: tensor[n, f32], confidence: f32) -> f32 = {
  losses_copy = copy(losses)
  mu = mean_vec(copy(losses_copy))
  sigma_loss = std_vec(losses_copy, cast(1, i64))
  z = normal_inv_cdf(confidence, cast(0.0, f32), cast(1.0, f32))
  z_sq_half = mul(cast(0.5, f32), mul(z, z))
  pdf_z = div(exp(neg(z_sq_half)), cast(2.5066282746310002, f32))
  tail_prob = sub(cast(1.0, f32), confidence)
  ratio = div(pdf_z, tail_prob)
  add(mu, mul(sigma_loss, ratio))
}
def historical_var[n](losses: tensor[n, f32], confidence: f32) -> f32 = quantile_vec(losses, confidence)
def historical_cvar[n](losses: tensor[n, f32], confidence: f32) -> f32 = {
  losses_copy = copy(losses)
  threshold = quantile_vec(copy(losses_copy), confidence)
  losses_l = to_list(losses_copy)
  init = (cast(0.0, f32), cast(0, i64))
  acc = fold(fn (state: (f32, i64), x: f32) -> {
    sum_so_far = state.0
    count_so_far = state.1
    if gte(x, threshold) then (add(sum_so_far, x), add(count_so_far, cast(1, i64))) else (sum_so_far, count_so_far)
  }, init, losses_l)
  s = acc.0
  c = acc.1
  if eq(c, cast(0, i64)) then threshold else div(s, cast(c, f32))
}
def empirical_loss_quantile[n](losses: tensor[n, f32], q: f32) -> f32 = quantile_vec(losses, q)
