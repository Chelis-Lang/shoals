module Shoals.LiborMarketModel
import Nautilus.Distributions (normal_sample)
import Nautilus.LinAlg (cholesky_n, matvec, scale_vec)
export (lmm_step, lmm_path, hjm_no_arb_drift, step_hjm)
def lmm_terminal_drift_one(f_l: List[f32], tau_l: List[f32], sig_l: List[f32], corr_flat_l: List[f32], i: i64, k_dim: i64) -> f32 = {
  sigma_i = index(sig_l, i)
  start = add(i, cast(1, i64))
  if gte(start, k_dim) then cast(0.0, f32) else {
    j_idxs = range(start, k_dim)
    inner_sum = fold(fn (acc: f32, j: i64) -> {
      tau_j = index(tau_l, j)
      l_j = index(f_l, j)
      sigma_j = index(sig_l, j)
      rho_ij = index(corr_flat_l, add(mul(i, k_dim), j))
      numerator = mul(tau_j, mul(l_j, mul(sigma_j, rho_ij)))
      denominator = add(cast(1.0, f32), mul(tau_j, l_j))
      add(acc, div(numerator, denominator))
    }, cast(0.0, f32), j_idxs)
    neg(mul(sigma_i, inner_sum))
  }
}
def lmm_step_with_chol[k](forwards: tensor[k, f32], tau_l: List[f32], sig_l: List[f32], corr_flat_l: List[f32], chol: &tensor[k, k, f32], dt: f32, normals: tensor[k, f32], k_dim: i64, sqrt_dt: f32) -> tensor[k, f32] = {
  z_corr = matvec(copy(chol), copy(normals))
  z_corr_l = to_list(z_corr)
  f_l = to_list(copy(forwards))
  idxs = range(cast(0, i64), k_dim)
  new_l = map(fn (i: i64) -> {
    l_i = index(f_l, i)
    sigma_i = index(sig_l, i)
    z_i = index(z_corr_l, i)
    drift_i = lmm_terminal_drift_one(f_l, tau_l, sig_l, corr_flat_l, i, k_dim)
    half_sig_sq = mul(cast(0.5, f32), mul(sigma_i, sigma_i))
    log_inc = add(mul(sub(drift_i, half_sig_sq), dt), mul(sigma_i, mul(sqrt_dt, z_i)))
    mul(l_i, exp(log_inc))
  }, idxs)
  to_tensor(new_l)
}
def lmm_step[k](forwards: tensor[k, f32], taus: tensor[k, f32], sigmas: tensor[k, f32], corr: tensor[k, k, f32], dt: f32, normals: tensor[k, f32]) -> tensor[k, f32] = {
  k_dim = len(to_list(copy(forwards)))
  chol = cholesky_n(copy(corr))
  tau_l = to_list(copy(taus))
  sig_l = to_list(copy(sigmas))
  corr_flat_l = to_list(reshape(corr, [mul(k_dim, k_dim)]))
  sqrt_dt = sqrt(dt)
  lmm_step_with_chol(forwards, tau_l, sig_l, corr_flat_l, copy(chol), dt, normals, k_dim, sqrt_dt)
}
-- The step count is a precondition this module did not check. With
-- `n_steps <= 0` lmm_evolve's step range is empty, so its fold returns the
-- initial forward curve and lmm_path returned `forwards0` unchanged for a
-- horizon over which the curve really did evolve. Measured at a flat 3/3.5/4
-- percent three-tenor curve, t = 1.0, n = 8, seed 7: `n_steps = 0` and
-- `n_steps = -8` both summed the eight terminal draws of the first forward to
-- 0.24 -- 0.03 at every path -- against 0.24871594 at `n_steps = 16`.
--
-- The guard goes at lmm_path's entry rather than inside lmm_evolve even
-- though lmm_evolve owns the empty fold, because lmm_evolve also takes `dt`
-- and `sqrt_dt` precomputed by its caller: checking there would refuse the
-- same inputs one frame later while leaving lmm_path's own `dt` division
-- unguarded, and lmm_evolve is exported, so it is guarded too.
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
def lmm_checked_step_count(n_steps: i64) -> i64 = if lt(n_steps, cast(1, i64)) then fail(string_concat("Shoals.LiborMarketModel: the step count must be at least 1, got ", string_concat(to_string(n_steps), "; with no steps the evolution loop never runs, so the sampler would return the initial forward curve unchanged for a horizon it did not simulate"))) else n_steps
def lmm_evolve[k](rng_key: key, forwards: tensor[k, f32], tau_l: List[f32], sig_l: List[f32], corr_flat_l: List[f32], chol: &tensor[k, k, f32], dt: f32, n_steps: i64, k_dim: i64, sqrt_dt: f32) -> tensor[k, f32] = {
  step_idxs = range(cast(0, i64), lmm_checked_step_count(n_steps))
  out = fold(fn (state: (key, tensor[k, f32]), s: i64) -> {
    (draw_key, next_key) = split_key(state.0)
    template = scale_vec(copy(state.1), cast(0.0, f32))
    normals = normal_sample(draw_key, template, cast(0.0, f32), cast(1.0, f32))
    next_forwards = lmm_step_with_chol(state.1, tau_l, sig_l, corr_flat_l, copy(chol), dt, normals, k_dim, sqrt_dt)
    (next_key, next_forwards)
  }, (rng_key, forwards), step_idxs)
  out.1
}
def lmm_path[k, n](rng_key: key, paths_template: tensor[n, f32], forwards0: tensor[k, f32], taus: tensor[k, f32], sigmas: tensor[k, f32], corr: tensor[k, k, f32], t: f32, n_steps: i64, forward_idx: i64) -> tensor[n, f32] = {
  k_dim = len(to_list(copy(forwards0)))
  n_ok = lmm_checked_step_count(n_steps)
  dt = div(t, cast(n_ok, f32))
  sqrt_dt = sqrt(dt)
  chol = cholesky_n(copy(corr))
  tau_l = to_list(copy(taus))
  sig_l = to_list(copy(sigmas))
  corr_flat_l = to_list(reshape(corr, [mul(k_dim, k_dim)]))
  zero_path = scale_vec(copy(paths_template), cast(0.0, f32))
  pl = to_list(zero_path)
  result = fold(fn (state: (key, List[f32]), placeholder: f32) -> {
    (path_key, next_key) = split_key(state.0)
    f0 = copy(forwards0)
    terminal = lmm_evolve(path_key, f0, tau_l, sig_l, corr_flat_l, copy(chol), dt, n_ok, k_dim, sqrt_dt)
    (next_key, append(state.1, index(to_list(terminal), forward_idx)))
  }, (rng_key, []), pl)
  to_tensor(result.1)
}
def hjm_no_arb_drift[k](sigmas: tensor[k, f32], taus: tensor[k, f32]) -> tensor[k, f32] = {
  k_dim = len(to_list(copy(sigmas)))
  sig_l = to_list(copy(sigmas))
  tau_l = to_list(copy(taus))
  idxs = range(cast(0, i64), k_dim)
  to_tensor(map(fn (i: i64) -> {
    sigma_i = index(sig_l, i)
    upper = add(i, cast(1, i64))
    j_idxs = range(cast(0, i64), upper)
    cumulative = fold(fn (acc: f32, j: i64) -> {
      tau_j = index(tau_l, j)
      sigma_j = index(sig_l, j)
      add(acc, mul(tau_j, sigma_j))
    }, cast(0.0, f32), j_idxs)
    mul(sigma_i, cumulative)
  }, idxs))
}
def step_hjm[k](forwards: tensor[k, f32], drifts: tensor[k, f32], sigmas: tensor[k, f32], dt: f32, normals: tensor[k, f32]) -> tensor[k, f32] = {
  sqrt_dt = sqrt(dt)
  f_l = to_list(copy(forwards))
  d_l = to_list(copy(drifts))
  s_l = to_list(copy(sigmas))
  z_l = to_list(copy(normals))
  k_dim = len(f_l)
  idxs = range(cast(0, i64), k_dim)
  to_tensor(map(fn (i: i64) -> {
    f_i = index(f_l, i)
    d_i = index(d_l, i)
    s_i = index(s_l, i)
    z_i = index(z_l, i)
    add(f_i, add(mul(d_i, dt), mul(s_i, mul(sqrt_dt, z_i))))
  }, idxs))
}
