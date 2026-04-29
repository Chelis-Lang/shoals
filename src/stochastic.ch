module Shoals.Stochastic
import Nautilus.Distributions (normal_sample)
export (gbm_path, gbm_terminal, gbm_paths_antithetic_terminal_mean)
def gbm_path[n](template: tensor[n, f32], s0: f32, mu: f32, sigma: f32, t: f32) -> tensor[n, f32] ! { Random } = {
  z = normal_sample(template, cast(0.0, f32), cast(1.0, f32))
  n_i = numel(copy(z))
  dt = div(t, cast(n_i, f32))
  sqrt_dt = sqrt(dt)
  half_sigma_sq = mul(cast(0.5, f32), mul(sigma, sigma))
  drift = mul(sub(mu, half_sigma_sq), dt)
  log_incs = to_tensor(map(fn (zi: f32) -> add(drift, mul(sigma, mul(sqrt_dt, zi))), to_list(z)))
  log_path = cumsum(log_incs, 0)
  log_s0 = log(s0)
  to_tensor(map(fn (lp: f32) -> exp(add(log_s0, lp)), to_list(log_path)))
}
def gbm_terminal[n](template: tensor[n, f32], s0: f32, mu: f32, sigma: f32, t: f32) -> tensor[n, f32] ! { Random } = {
  z = normal_sample(template, cast(0.0, f32), cast(1.0, f32))
  half_sigma_sq = mul(cast(0.5, f32), mul(sigma, sigma))
  drift = mul(sub(mu, half_sigma_sq), t)
  vol_sqrt_t = mul(sigma, sqrt(t))
  log_s0 = log(s0)
  to_tensor(map(fn (zi: f32) -> exp(add(log_s0, add(drift, mul(vol_sqrt_t, zi)))), to_list(z)))
}
def gbm_paths_antithetic_terminal_mean[n](template: tensor[n, f32], s0: f32, mu: f32, sigma: f32, t: f32) -> f32 ! { Random } = {
  z = normal_sample(template, cast(0.0, f32), cast(1.0, f32))
  half_sigma_sq = mul(cast(0.5, f32), mul(sigma, sigma))
  drift = mul(sub(mu, half_sigma_sq), t)
  vol_sqrt_t = mul(sigma, sqrt(t))
  log_s0 = log(s0)
  zs = to_list(z)
  pairs = to_tensor(map(fn (zi: f32) -> {
    plus = exp(add(log_s0, add(drift, mul(vol_sqrt_t, zi))))
    minus = exp(add(log_s0, add(drift, mul(vol_sqrt_t, neg(zi)))))
    mul(cast(0.5, f32), add(plus, minus))
  }, zs))
  n_f = cast(numel(copy(pairs)), f32)
  div(tensor_to_scalar(sum(pairs, 0)), n_f)
}
