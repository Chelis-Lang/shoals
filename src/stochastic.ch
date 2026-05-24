module Shoals.Stochastic
import Nautilus.Distributions (normal_sample)
export (gbm_path, gbm_terminal, gbm_paths_antithetic_terminal_mean, merton_jump_terminal, merton_compensated_drift, correlated_gbm_terminal_2d, cholesky_2x2_lower)
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
def merton_compensated_drift(mu: f32, sigma: f32, lambda: f32, jump_mean: f32, jump_vol: f32) -> f32 = {
  half_sigma_sq = mul(cast(0.5, f32), mul(sigma, sigma))
  half_jump_vol_sq = mul(cast(0.5, f32), mul(jump_vol, jump_vol))
  expected_jump = sub(exp(add(jump_mean, half_jump_vol_sq)), cast(1.0, f32))
  sub(sub(mu, half_sigma_sq), mul(lambda, expected_jump))
}
def merton_jump_terminal[n](template: tensor[n, f32], jumps_template: tensor[n, f32], s0: f32, mu: f32, sigma: f32, lambda: f32, jump_mean: f32, jump_vol: f32, t: f32) -> tensor[n, f32] ! { Random } = {
  z_diff = normal_sample(template, cast(0.0, f32), cast(1.0, f32))
  z_jumps = normal_sample(jumps_template, cast(0.0, f32), cast(1.0, f32))
  drift = mul(merton_compensated_drift(mu, sigma, lambda, jump_mean, jump_vol), t)
  vol_sqrt_t = mul(sigma, sqrt(t))
  expected_jumps = mul(lambda, t)
  jump_drift = mul(expected_jumps, jump_mean)
  jump_var_per_jump = add(mul(jump_vol, jump_vol), mul(jump_mean, jump_mean))
  total_jump_var = mul(expected_jumps, jump_var_per_jump)
  jump_vol_sqrt = sqrt(total_jump_var)
  log_s0 = log(s0)
  z_diff_l = to_list(z_diff)
  z_jumps_l = to_list(z_jumps)
  pairs = zip(z_diff_l, z_jumps_l)
  to_tensor(map(fn (entry: (f32, f32)) -> {
    log_diffuse = add(drift, mul(vol_sqrt_t, entry.0))
    log_jump = add(jump_drift, mul(jump_vol_sqrt, entry.1))
    exp(add(log_s0, add(log_diffuse, log_jump)))
  }, pairs))
}
def cholesky_2x2_lower(sigma_xx: f32, sigma_xy: f32, sigma_yy: f32) -> (f32, f32, f32) = {
  l11 = sqrt(sigma_xx)
  l21 = div(sigma_xy, l11)
  l22 = sqrt(sub(sigma_yy, mul(l21, l21)))
  (l11, l21, l22)
}
def correlated_gbm_terminal_2d[n](template_x: tensor[n, f32], template_y: tensor[n, f32], s0_x: f32, s0_y: f32, mu_x: f32, mu_y: f32, sigma_x: f32, sigma_y: f32, rho: f32, t: f32) -> (tensor[n, f32], tensor[n, f32]) ! { Random } = {
  zx = normal_sample(template_x, cast(0.0, f32), cast(1.0, f32))
  zy_indep = normal_sample(template_y, cast(0.0, f32), cast(1.0, f32))
  log_s0_x = log(s0_x)
  log_s0_y = log(s0_y)
  drift_x = mul(sub(mu_x, mul(cast(0.5, f32), mul(sigma_x, sigma_x))), t)
  drift_y = mul(sub(mu_y, mul(cast(0.5, f32), mul(sigma_y, sigma_y))), t)
  vol_x_sqrt_t = mul(sigma_x, sqrt(t))
  vol_y_sqrt_t = mul(sigma_y, sqrt(t))
  one_minus_rho_sq = sub(cast(1.0, f32), mul(rho, rho))
  sqrt_one_minus_rho_sq = if lt(one_minus_rho_sq, cast(0.0, f32)) then cast(0.0, f32) else sqrt(one_minus_rho_sq)
  zx_l = to_list(zx)
  zy_l = to_list(zy_indep)
  pairs = zip(zx_l, zy_l)
  x_path = to_tensor(map(fn (e: (f32, f32)) -> exp(add(log_s0_x, add(drift_x, mul(vol_x_sqrt_t, e.0)))), pairs))
  y_path = to_tensor(map(fn (e: (f32, f32)) -> {
    z_corr = add(mul(rho, e.0), mul(sqrt_one_minus_rho_sq, e.1))
    exp(add(log_s0_y, add(drift_y, mul(vol_y_sqrt_t, z_corr))))
  }, pairs))
  (x_path, y_path)
}
