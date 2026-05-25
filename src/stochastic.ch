module Shoals.Stochastic
import Nautilus.Distributions (normal_sample, uniform_sample)
export (gbm_path, gbm_terminal, gbm_paths_antithetic_terminal_mean, merton_jump_terminal, merton_compensated_drift, correlated_gbm_terminal_2d, cholesky_2x2_lower, heston_qe_step, heston_qe_terminal, heston_qe_paths_terminal)
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
def heston_qe_step(log_s: f32, v: f32, min_v: f32, mu: f32, kappa: f32, theta: f32, sigma: f32, rho: f32, dt: f32, z_v: f32, z_indep: f32, u: f32) -> (f32, f32, f32) = {
  one = cast(1.0, f32)
  two = cast(2.0, f32)
  half = cast(0.5, f32)
  psi_c = cast(1.5, f32)
  zero = cast(0.0, f32)
  e_kdt = exp(neg(mul(kappa, dt)))
  one_minus_e = sub(one, e_kdt)
  m = add(theta, mul(sub(v, theta), e_kdt))
  sigma_sq = mul(sigma, sigma)
  s2_a = mul(div(mul(v, mul(sigma_sq, e_kdt)), kappa), one_minus_e)
  s2_b = mul(div(mul(theta, sigma_sq), mul(two, kappa)), mul(one_minus_e, one_minus_e))
  s2 = add(s2_a, s2_b)
  tiny = cast(0.000000000001, f32)
  m_abs = if lt(m, zero) then neg(m) else m
  s2_abs = if lt(s2, zero) then neg(s2) else s2
  v_next = if lt(m_abs, tiny) then zero else if lt(s2_abs, tiny) then if lt(m, zero) then zero else m else {
    m_safe = if lt(m, tiny) then tiny else m
    psi = div(s2, mul(m_safe, m_safe))
    if lte(psi, psi_c) then {
      two_over_psi = div(two, psi)
      two_over_psi_minus_one = sub(two_over_psi, one)
      two_over_psi_minus_one_safe = if lt(two_over_psi_minus_one, zero) then zero else two_over_psi_minus_one
      b2 = add(two_over_psi_minus_one_safe, mul(sqrt(two_over_psi), sqrt(two_over_psi_minus_one_safe)))
      a = div(m, add(one, b2))
      inner = add(sqrt(b2), z_v)
      mul(a, mul(inner, inner))
    } else {
      p = div(sub(psi, one), add(psi, one))
      beta = div(sub(one, p), m_safe)
      if lte(u, p) then zero else {
        one_minus_p = sub(one, p)
        one_minus_u = sub(one, u)
        one_minus_u_safe = if lt(one_minus_u, tiny) then tiny else one_minus_u
        mul(div(one, beta), log(div(one_minus_p, one_minus_u_safe)))
      }
    }
  }
  v_next_pos = if lt(v_next, zero) then zero else v_next
  one_minus_rho_sq = sub(one, mul(rho, rho))
  sqrt_one_minus_rho_sq = if lt(one_minus_rho_sq, zero) then zero else sqrt(one_minus_rho_sq)
  z1 = add(mul(rho, z_v), mul(sqrt_one_minus_rho_sq, z_indep))
  v_pos = if lt(v, zero) then zero else v
  log_s_next = add(log_s, add(mul(sub(mu, mul(half, v_pos)), dt), mul(sqrt(mul(v_pos, dt)), z1)))
  new_min = if lt(v_next_pos, min_v) then v_next_pos else min_v
  (log_s_next, v_next_pos, new_min)
}
def heston_qe_terminal(s0: f32, v0: f32, mu: f32, kappa: f32, theta: f32, sigma: f32, rho: f32, t: f32, n_steps: int64) -> (f32, f32, f32) ! { Random } = {
  template = to_tensor(map(fn (i: int64) -> cast(0.0, f32), range(cast(0, int64), n_steps)))
  z_v_t = normal_sample(copy(template), cast(0.0, f32), cast(1.0, f32))
  z_ind_t = normal_sample(copy(template), cast(0.0, f32), cast(1.0, f32))
  u_t = uniform_sample(template, cast(0.0, f32), cast(1.0, f32))
  z_v_l = to_list(z_v_t)
  z_ind_l = to_list(z_ind_t)
  u_l = to_list(u_t)
  dt = div(t, cast(n_steps, f32))
  log_s0 = log(s0)
  init_state = (log_s0, v0, v0)
  idxs = range(cast(0, int64), n_steps)
  final_state = fold(fn (state: (f32, f32, f32), i: int64) -> {
    log_s = state.0
    v = state.1
    min_v = state.2
    z_v = index(z_v_l, i)
    z_indep = index(z_ind_l, i)
    u = index(u_l, i)
    heston_qe_step(log_s, v, min_v, mu, kappa, theta, sigma, rho, dt, z_v, z_indep, u)
  }, init_state, idxs)
  (exp(final_state.0), final_state.1, final_state.2)
}
def heston_qe_paths_terminal[n](paths_template: tensor[n, f32], s0: f32, v0: f32, mu: f32, kappa: f32, theta: f32, sigma: f32, rho: f32, t: f32, n_steps: int64) -> (tensor[n, f32], tensor[n, f32], tensor[n, f32]) ! { Random } = {
  n_paths = numel(copy(paths_template))
  total = mul(n_paths, n_steps)
  big_template = to_tensor(map(fn (i: int64) -> cast(0.0, f32), range(cast(0, int64), total)))
  z_v_t = normal_sample(copy(big_template), cast(0.0, f32), cast(1.0, f32))
  z_ind_t = normal_sample(copy(big_template), cast(0.0, f32), cast(1.0, f32))
  u_t = uniform_sample(big_template, cast(0.0, f32), cast(1.0, f32))
  z_v_l = to_list(z_v_t)
  z_ind_l = to_list(z_ind_t)
  u_l = to_list(u_t)
  dt = div(t, cast(n_steps, f32))
  log_s0 = log(s0)
  path_idxs = range(cast(0, int64), n_paths)
  results = map(fn (p: int64) -> {
    base = mul(p, n_steps)
    init_state = (log_s0, v0, v0)
    step_idxs = range(cast(0, int64), n_steps)
    final = fold(fn (state: (f32, f32, f32), i: int64) -> {
      log_s = state.0
      v = state.1
      min_v = state.2
      k = add(base, i)
      z_v = index(z_v_l, k)
      z_indep = index(z_ind_l, k)
      u = index(u_l, k)
      heston_qe_step(log_s, v, min_v, mu, kappa, theta, sigma, rho, dt, z_v, z_indep, u)
    }, init_state, step_idxs)
    (exp(final.0), final.1, final.2)
  }, path_idxs)
  s_t = to_tensor(map(fn (r: (f32, f32, f32)) -> r.0, results))
  v_t = to_tensor(map(fn (r: (f32, f32, f32)) -> r.1, results))
  min_v = to_tensor(map(fn (r: (f32, f32, f32)) -> r.2, results))
  (s_t, v_t, min_v)
}
