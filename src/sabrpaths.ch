module Shoals.SabrPaths
import Nautilus.Distributions (normal_sample)
export (sabr_qe_step, sabr_path_terminal, sabr_paths_terminal)
def sabr_floor() -> f32 = cast(1e-10, f32)
def sabr_clamp_pos(x: f32) -> f32 = if lt(x, sabr_floor()) then sabr_floor() else x
def sabr_qe_step(f: f32, alpha: f32, beta: f32, rho: f32, nu: f32, dt: f32, z_f: f32, z_alpha: f32) -> (f32, f32) = {
  one = cast(1.0, f32)
  half = cast(0.5, f32)
  zero = cast(0.0, f32)
  f_pos = sabr_clamp_pos(f)
  alpha_pos = sabr_clamp_pos(alpha)
  sqrt_dt = sqrt(dt)
  one_minus_rho_sq = sub(one, mul(rho, rho))
  sqrt_one_minus_rho_sq = if lt(one_minus_rho_sq, zero) then zero else sqrt(one_minus_rho_sq)
  z1 = add(mul(rho, z_alpha), mul(sqrt_one_minus_rho_sq, z_f))
  log_f = log(f_pos)
  beta_minus_one = sub(beta, one)
  two_beta_minus_two = mul(cast(2.0, f32), beta_minus_one)
  f_pow_bm1 = exp(mul(beta_minus_one, log_f))
  f_pow_2bm2 = exp(mul(two_beta_minus_two, log_f))
  alpha_sq = mul(alpha_pos, alpha_pos)
  drift_f = mul(neg(half), mul(alpha_sq, mul(f_pow_2bm2, dt)))
  diff_f = mul(alpha_pos, mul(f_pow_bm1, mul(sqrt_dt, z1)))
  log_f_next = add(log_f, add(drift_f, diff_f))
  f_next = sabr_clamp_pos(exp(log_f_next))
  nu_sq = mul(nu, nu)
  alpha_drift = mul(neg(half), mul(nu_sq, dt))
  alpha_diff = mul(nu, mul(sqrt_dt, z_alpha))
  alpha_next = sabr_clamp_pos(mul(alpha_pos, exp(add(alpha_drift, alpha_diff))))
  (f_next, alpha_next)
}
def sabr_path_terminal(rng_key: key, f0: f32, alpha0: f32, beta: f32, rho: f32, nu: f32, t: f32, n_steps: i64) -> (f32, f32) = {
  (rng_draw_0, rng_draw_1) = split_key(rng_key)
  template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), n_steps)))
  z_f_t = normal_sample(rng_draw_0, copy(template), cast(0.0, f32), cast(1.0, f32))
  z_alpha_t = normal_sample(rng_draw_1, template, cast(0.0, f32), cast(1.0, f32))
  z_f_l = to_list(z_f_t)
  z_alpha_l = to_list(z_alpha_t)
  dt = div(t, cast(n_steps, f32))
  init_state = (f0, alpha0)
  idxs = range(cast(0, i64), n_steps)
  final_state = fold(fn (state: (f32, f32), i: i64) -> {
    f = state.0
    alpha = state.1
    z_f = index(z_f_l, i)
    z_alpha = index(z_alpha_l, i)
    sabr_qe_step(f, alpha, beta, rho, nu, dt, z_f, z_alpha)
  }, init_state, idxs)
  (final_state.0, final_state.1)
}
def sabr_paths_terminal[n](rng_key: key, paths_template: tensor[n, f32], f0: f32, alpha0: f32, beta: f32, rho: f32, nu: f32, t: f32, n_steps: i64) -> (tensor[n, f32], tensor[n, f32]) = {
  (rng_draw_0, rng_draw_1) = split_key(rng_key)
  n_paths = numel(copy(paths_template))
  total = mul(n_paths, n_steps)
  big_template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), total)))
  z_f_t = normal_sample(rng_draw_0, copy(big_template), cast(0.0, f32), cast(1.0, f32))
  z_alpha_t = normal_sample(rng_draw_1, big_template, cast(0.0, f32), cast(1.0, f32))
  z_f_l = to_list(z_f_t)
  z_alpha_l = to_list(z_alpha_t)
  dt = div(t, cast(n_steps, f32))
  path_idxs = range(cast(0, i64), n_paths)
  results = map(fn (p: i64) -> {
    base = mul(p, n_steps)
    init_state = (f0, alpha0)
    step_idxs = range(cast(0, i64), n_steps)
    final = fold(fn (state: (f32, f32), i: i64) -> {
      f = state.0
      alpha = state.1
      k = add(base, i)
      z_f = index(z_f_l, k)
      z_alpha = index(z_alpha_l, k)
      sabr_qe_step(f, alpha, beta, rho, nu, dt, z_f, z_alpha)
    }, init_state, step_idxs)
    (final.0, final.1)
  }, path_idxs)
  f_t = to_tensor(map(fn (r: (f32, f32)) -> r.0, results))
  alpha_t = to_tensor(map(fn (r: (f32, f32)) -> r.1, results))
  (f_t, alpha_t)
}
