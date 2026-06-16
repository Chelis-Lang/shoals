module Shoals.LiborMarketModel
import Nautilus.Distributions (normal_sample)
import Nautilus.LinAlg (cholesky_n, matvec, scale_vec)
export (lmm_step, lmm_path, hjm_no_arb_drift, step_hjm)
def lmm_terminal_drift_one(f_l: List[f32], tau_l: List[f32], sig_l: List[f32], corr_flat_l: List[f32], i: int64, k_dim: int64) -> f32 = {
  sigma_i = index(sig_l, i)
  start = add(i, cast(1, int64))
  if gte(start, k_dim) then cast(0.0, f32) else {
    j_idxs = range(start, k_dim)
    inner_sum = fold(fn (acc: f32, j: int64) -> {
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
def lmm_step_with_chol[k](forwards: tensor[k, f32], tau_l: List[f32], sig_l: List[f32], corr_flat_l: List[f32], chol: &tensor[k, k, f32], dt: f32, normals: tensor[k, f32], k_dim: int64, sqrt_dt: f32) -> tensor[k, f32] = {
  z_corr = matvec(copy(chol), copy(normals))
  z_corr_l = to_list(z_corr)
  f_l = to_list(copy(forwards))
  idxs = range(cast(0, int64), k_dim)
  new_l = map(fn (i: int64) -> {
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
def lmm_evolve[k](forwards: tensor[k, f32], tau_l: List[f32], sig_l: List[f32], corr_flat_l: List[f32], chol: &tensor[k, k, f32], dt: f32, n_steps: int64, k_dim: int64, sqrt_dt: f32) -> tensor[k, f32] ! { Random } = {
  step_idxs = range(cast(0, int64), n_steps)
  fold(fn (state: tensor[k, f32], s: int64) -> {
    template = scale_vec(copy(state), cast(0.0, f32))
    normals = normal_sample(template, cast(0.0, f32), cast(1.0, f32))
    lmm_step_with_chol(state, tau_l, sig_l, corr_flat_l, copy(chol), dt, normals, k_dim, sqrt_dt)
  }, forwards, step_idxs)
}
def lmm_path[k, n](paths_template: tensor[n, f32], forwards0: tensor[k, f32], taus: tensor[k, f32], sigmas: tensor[k, f32], corr: tensor[k, k, f32], t: f32, n_steps: int64, forward_idx: int64) -> tensor[n, f32] ! { Random } = {
  k_dim = len(to_list(copy(forwards0)))
  dt = div(t, cast(n_steps, f32))
  sqrt_dt = sqrt(dt)
  chol = cholesky_n(copy(corr))
  tau_l = to_list(copy(taus))
  sig_l = to_list(copy(sigmas))
  corr_flat_l = to_list(reshape(corr, [mul(k_dim, k_dim)]))
  zero_path = scale_vec(copy(paths_template), cast(0.0, f32))
  pl = to_list(zero_path)
  result = map(fn (placeholder: f32) -> {
    f0 = copy(forwards0)
    terminal = lmm_evolve(f0, tau_l, sig_l, corr_flat_l, copy(chol), dt, n_steps, k_dim, sqrt_dt)
    index(to_list(terminal), forward_idx)
  }, pl)
  to_tensor(result)
}
def hjm_no_arb_drift[k](sigmas: tensor[k, f32], taus: tensor[k, f32]) -> tensor[k, f32] = {
  k_dim = len(to_list(copy(sigmas)))
  sig_l = to_list(copy(sigmas))
  tau_l = to_list(copy(taus))
  idxs = range(cast(0, int64), k_dim)
  to_tensor(map(fn (i: int64) -> {
    sigma_i = index(sig_l, i)
    upper = add(i, cast(1, int64))
    j_idxs = range(cast(0, int64), upper)
    cumulative = fold(fn (acc: f32, j: int64) -> {
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
  idxs = range(cast(0, int64), k_dim)
  to_tensor(map(fn (i: int64) -> {
    f_i = index(f_l, i)
    d_i = index(d_l, i)
    s_i = index(s_l, i)
    z_i = index(z_l, i)
    add(f_i, add(mul(d_i, dt), mul(s_i, mul(sqrt_dt, z_i))))
  }, idxs))
}
