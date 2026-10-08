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
-- The step count is a precondition this module did not check. With
-- `n_steps <= 0` the step range is empty, so the evolution fold returns its
-- initial state and the sampler returned `(f0, alpha0)` unchanged for a
-- horizon over which the process really did evolve. Measured at f0 = 100,
-- alpha0 = 0.2, t = 1.0, seed 7: `sabr_path_terminal` returned 100.0 for both
-- `n_steps = 0` and `n_steps = -8` against 100.69905 at `n_steps = 64`, and
-- `sabr_paths_terminal` summed its eight terminal forwards to 800.0 at
-- `n_steps = 0` against 797.86395 at `n_steps = 64`.
--
-- A finiteness check on the derived `dt = t / n_steps` is not a substitute,
-- and the reason is narrower than it first looks. Adding such a check CREATES
-- a consumer for `dt`, so it does catch `n_steps = 0`, where `dt` is `+inf`.
-- It does not catch a NEGATIVE count: `t / -8` is finite, the step range is
-- still empty, and the sampler returns its initial state silently. Measured
-- by building that exact mutant on the Heston pair: the two zero fixtures
-- died because the `dt` check fired with the wrong diagnostic, and the two
-- negative fixtures died because it never fired at all. Guarding the input
-- covers both cases with one check and names the parameter the caller got
-- wrong.
--
-- `n_steps = 0` is refused rather than documented as the identity. It is a
-- resolution parameter, not a modelled quantity: `n_steps = 1` is a crude
-- discretisation that still draws, while `n_steps = 0` draws nothing, so zero
-- resolution is unspecified rather than degenerate. A zero HORIZON is the
-- separate case where the initial state genuinely is the right answer, and
-- refusing `n_steps < 1` leaves it reachable at any valid step count.
--
-- Each module carries its own copy of this check so its diagnostic can name
-- the module a caller actually invoked, following ind_require_period's
-- precedent in Shoals.Indicators. The duplication is the message text, not
-- the decision; the decision is stated once in the changelog fragment for
-- this change. (The user book is NOT that place: it mirrors the published
-- site and documents the latest release, and its Shoals pages still describe
-- these counts as unchecked caller obligations until that release lands.)
def sabr_checked_step_count(n_steps: i64) -> i64 = if lt(n_steps, cast(1, i64)) then fail(string_concat("Shoals.SabrPaths: the step count must be at least 1, got ", string_concat(to_string(n_steps), "; with no steps the evolution loop never runs, so the sampler would return (f0, alpha0) unchanged for a horizon it did not simulate"))) else n_steps
def sabr_path_terminal(rng_key: key, f0: f32, alpha0: f32, beta: f32, rho: f32, nu: f32, t: f32, n_steps: i64) -> (f32, f32) = {
  (rng_draw_0, rng_draw_1) = split_key(rng_key)
  n_ok = sabr_checked_step_count(n_steps)
  template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), n_ok)))
  z_f_t = normal_sample(rng_draw_0, copy(template), cast(0.0, f32), cast(1.0, f32))
  z_alpha_t = normal_sample(rng_draw_1, template, cast(0.0, f32), cast(1.0, f32))
  z_f_l = to_list(z_f_t)
  z_alpha_l = to_list(z_alpha_t)
  dt = div(t, cast(n_ok, f32))
  init_state = (f0, alpha0)
  idxs = range(cast(0, i64), n_ok)
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
  n_ok = sabr_checked_step_count(n_steps)
  total = mul(n_paths, n_ok)
  big_template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), total)))
  z_f_t = normal_sample(rng_draw_0, copy(big_template), cast(0.0, f32), cast(1.0, f32))
  z_alpha_t = normal_sample(rng_draw_1, big_template, cast(0.0, f32), cast(1.0, f32))
  z_f_l = to_list(z_f_t)
  z_alpha_l = to_list(z_alpha_t)
  dt = div(t, cast(n_ok, f32))
  path_idxs = range(cast(0, i64), n_paths)
  results = map(fn (p: i64) -> {
    base = mul(p, n_ok)
    init_state = (f0, alpha0)
    step_idxs = range(cast(0, i64), n_ok)
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
