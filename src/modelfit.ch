module Shoals.ModelFit
import Nautilus.LinAlg (la_vec_add, la_vec_sub, scale_vec, inner_product, cg_solve, matvec, vecmat, l2_norm_vec)
export (weighted_squared_residuals, vega_weighted_squared_residuals, weighted_absolute_residuals, clamp_to_bounds, lm_bounded_step_scalar, sse_loss, clamp_vec, weighted_sse, lm_bounded_nparam, multi_target_fit, active_set_mask, mf_sabr_smart_initializer, mf_sabr_multi_start_initializer, bfgs_bounded_nparam, sequential_pipeline_2stage, sequential_pipeline_2stage_gradient)
def clamp_to_bounds(x: f32, lo: f32, hi: f32) -> f32 = if lt(x, lo) then lo else if gt(x, hi) then hi else x
def mf_elementwise_mul[n](a: &tensor[n, f32], b: &tensor[n, f32]) -> tensor[n, f32] = to_tensor(map(fn (pair: (f32, f32)) -> mul(pair.0, pair.1), zip(to_list(a), to_list(b))))
def mf_basis_vec[n](k: int64, s: f32, template: &tensor[n, f32]) -> tensor[n, f32] = {
  n_len = len(to_list(template))
  idxs = range(cast(0, int64), n_len)
  to_tensor(map(fn (i: int64) -> if eq(i, k) then s else cast(0.0, f32), idxs))
}
def mf_zero_matrix[n](template: &tensor[n, f32]) -> tensor[n, n, f32] = {
  z_vec = scale_vec(template, cast(0.0, f32))
  einsum("i,j->ij", copy(z_vec), z_vec)
}
def weighted_squared_residuals[n](observed: tensor[n, f32], predicted: tensor[n, f32], weights: tensor[n, f32]) -> tensor[n, f32] = {
  o_l = to_list(observed)
  p_l = to_list(predicted)
  w_l = to_list(weights)
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
  v_l = to_list(vegas)
  inv_vega_weights = to_tensor(map(fn (v: f32) -> if eq(v, cast(0.0, f32)) then cast(0.0, f32) else div(cast(1.0, f32), mul(v, v)), v_l))
  weighted_squared_residuals(observed, predicted, inv_vega_weights)
}
def weighted_absolute_residuals[n](observed: tensor[n, f32], predicted: tensor[n, f32], weights: tensor[n, f32]) -> tensor[n, f32] = {
  o_l = to_list(observed)
  p_l = to_list(predicted)
  w_l = to_list(weights)
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
def sse_loss[n](residuals: tensor[n, f32]) -> f32 = residuals |> sum(0) |> tensor_to_scalar
def lm_bounded_step_scalar(jtj: f32, jtr: f32, lambda: f32, current: f32, lo: f32, hi: f32) -> f32 = {
  numerator = jtr
  denominator = add(jtj, lambda)
  step = if eq(denominator, cast(0.0, f32)) then cast(0.0, f32) else div(numerator, denominator)
  proposed = sub(current, step)
  clamp_to_bounds(proposed, lo, hi)
}
def clamp_vec[n](theta: tensor[n, f32], lo: tensor[n, f32], hi: tensor[n, f32]) -> tensor[n, f32] = {
  th_l = to_list(theta)
  lo_l = to_list(lo)
  hi_l = to_list(hi)
  th_lo = zip(th_l, lo_l)
  trips = zip(th_lo, hi_l)
  to_tensor(map(fn (e: ((f32, f32), f32)) -> {
    pair = e.0
    h = e.1
    x = pair.0
    l = pair.1
    clamp_to_bounds(x, l, h)
  }, trips))
}
def weighted_sse[m](residuals: tensor[m, f32], weights: tensor[m, f32]) -> f32 = {
  r_l = to_list(residuals)
  w_l = to_list(weights)
  pairs = zip(r_l, w_l)
  fold(fn (acc: f32, e: (f32, f32)) -> add(acc, mul(e.1, mul(e.0, e.0))), cast(0.0, f32), pairs)
}
def mf_jcol[n, m](model: &tensor[n, f32] -> &tensor[m, f32] -> tensor[m, f32], x: &tensor[m, f32], theta: &tensor[n, f32], base_pred: &tensor[m, f32], tpl_n: &tensor[n, f32], i: int64, eps: f32) -> tensor[m, f32] = {
  eps_vec = mf_basis_vec(i, eps, tpl_n)
  theta_plus = la_vec_add(theta, eps_vec)
  pred_plus = model(theta_plus, x)
  scale_vec(la_vec_sub(pred_plus, base_pred), div(cast(1.0, f32), eps))
}
def mf_jtwr_acc[n, m](model: &tensor[n, f32] -> &tensor[m, f32] -> tensor[m, f32], x: &tensor[m, f32], theta: &tensor[n, f32], base_pred: &tensor[m, f32], wr: &tensor[m, f32], tpl_n: &tensor[n, f32], i: int64, n_params: int64, eps: f32) -> tensor[n, f32] = {
  if gte(i, n_params) then { to_tensor(map(fn (t: f32) -> cast(0.0, f32), to_list(tpl_n))) } else {
    j_col = mf_jcol(model, copy(x), copy(theta), copy(base_pred), copy(tpl_n), i, eps)
    jtwr_i = inner_product(copy(j_col), copy(wr))
    e_i = mf_basis_vec(i, jtwr_i, copy(tpl_n))
    rest = mf_jtwr_acc(model, x, theta, base_pred, wr, tpl_n, add(i, cast(1, int64)), n_params, eps)
    la_vec_add(e_i, rest)
  }
}
def mf_jtwj_row[n, m](model: &tensor[n, f32] -> &tensor[m, f32] -> tensor[m, f32], x: &tensor[m, f32], theta: &tensor[n, f32], base_pred: &tensor[m, f32], tpl_n: &tensor[n, f32], j_col_i: &tensor[m, f32], weights: &tensor[m, f32], e_i: &tensor[n, f32], j: int64, n_params: int64, eps: f32) -> tensor[n, n, f32] = {
  if gte(j, n_params) then {
    ztj = scale_vec(copy(tpl_n), cast(0.0, f32))
    einsum("i,j->ij", copy(ztj), ztj)
  } else {
    j_col_j = mf_jcol(model, copy(x), copy(theta), copy(base_pred), copy(tpl_n), j, eps)
    wj_col_j = mf_elementwise_mul(copy(weights), copy(j_col_j))
    dot_ij = inner_product(copy(j_col_i), wj_col_j)
    e_j = mf_basis_vec(j, cast(1.0, f32), copy(tpl_n))
    this_entry = einsum("i,j->ij", scale_vec(copy(e_i), dot_ij), e_j)
    rest = mf_jtwj_row(model, x, theta, base_pred, tpl_n, j_col_i, weights, e_i, add(j, cast(1, int64)), n_params, eps)
    add(this_entry, rest)
  }
}
def mf_jtwj_acc[n, m](model: &tensor[n, f32] -> &tensor[m, f32] -> tensor[m, f32], x: &tensor[m, f32], theta: &tensor[n, f32], base_pred: &tensor[m, f32], weights: &tensor[m, f32], tpl_n: &tensor[n, f32], i: int64, n_params: int64, eps: f32) -> tensor[n, n, f32] = {
  if gte(i, n_params) then {
    ztj = scale_vec(copy(tpl_n), cast(0.0, f32))
    einsum("i,j->ij", copy(ztj), ztj)
  } else {
    j_col_i = mf_jcol(model, copy(x), copy(theta), copy(base_pred), copy(tpl_n), i, eps)
    e_i = mf_basis_vec(i, cast(1.0, f32), copy(tpl_n))
    row_i = mf_jtwj_row(model, copy(x), copy(theta), copy(base_pred), copy(tpl_n), j_col_i, copy(weights), e_i, cast(0, int64), n_params, eps)
    rest = mf_jtwj_acc(model, x, theta, base_pred, weights, tpl_n, add(i, cast(1, int64)), n_params, eps)
    add(row_i, rest)
  }
}
def mf_diag_entry[n](mat: &tensor[n, n, f32], i: int64, n_params: int64) -> f32 = {
  e_i = mf_basis_vec(i, cast(1.0, f32), to_tensor(map(fn (k: int64) -> cast(0.0, f32), range(cast(0, int64), n_params))))
  matrix = copy(mat)
  mv = matvec(matrix, copy(e_i))
  inner_product(copy(e_i), mv)
}
def mf_damped_normal[n](jtwj: tensor[n, n, f32], lambda: f32, tpl_n: &tensor[n, f32], n_params: int64) -> tensor[n, n, f32] = {
  jtwj_ref = copy(jtwj)
  fold(fn (acc: tensor[n, n, f32], i: int64) -> {
    diag_i = mf_diag_entry(copy(jtwj_ref), i, n_params)
    safe_diag = if lt(diag_i, cast(0.0000001, f32)) then cast(0.0000001, f32) else diag_i
    scale = mul(lambda, safe_diag)
    le_i = mf_basis_vec(i, scale, copy(tpl_n))
    ue_i = mf_basis_vec(i, cast(1.0, f32), copy(tpl_n))
    add(acc, einsum("i,j->ij", le_i, ue_i))
  }, jtwj, range(cast(0, int64), n_params))
}
def mf_lm_step[n, m](model: &tensor[n, f32] -> &tensor[m, f32] -> tensor[m, f32], x: &tensor[m, f32], y: &tensor[m, f32], weights: &tensor[m, f32], theta: tensor[n, f32], lo: &tensor[n, f32], hi: &tensor[n, f32], lambda: f32, eps: f32) -> (tensor[n, f32], f32) = {
  tpl_n = to_tensor(map(fn (t: f32) -> cast(0.0, f32), to_list(copy(theta))))
  n_params = len(to_list(copy(tpl_n)))
  base_pred = model(copy(theta), copy(x))
  r = la_vec_sub(copy(y), copy(base_pred))
  wr = mf_elementwise_mul(copy(weights), copy(r))
  zero_n = to_tensor(map(fn (t: f32) -> cast(0.0, f32), to_list(copy(tpl_n))))
  jtwr = mf_jtwr_acc(model, copy(x), copy(theta), copy(base_pred), copy(wr), copy(tpl_n), cast(0, int64), n_params, eps)
  jtwj = mf_jtwj_acc(model, copy(x), copy(theta), copy(base_pred), copy(weights), copy(tpl_n), cast(0, int64), n_params, eps)
  h = mf_damped_normal(jtwj, lambda, copy(tpl_n), n_params)
  delta = cg_solve(h, jtwr, zero_n, cast(0.000001, f32), cast(50, int64))
  theta_proposed = clamp_vec(la_vec_add(copy(theta), delta), copy(lo), copy(hi))
  new_pred = model(copy(theta_proposed), copy(x))
  new_r = la_vec_sub(copy(y), new_pred)
  new_sse = weighted_sse(new_r, copy(weights))
  (theta_proposed, new_sse)
}
def active_set_mask[n](theta: &tensor[n, f32], lo: &tensor[n, f32], hi: &tensor[n, f32], eps: f32) -> tensor[n, f32] = {
  th_l = to_list(theta)
  lo_l = to_list(lo)
  hi_l = to_list(hi)
  th_lo = zip(th_l, lo_l)
  trips = zip(th_lo, hi_l)
  to_tensor(map(fn (e: ((f32, f32), f32)) -> {
    pair = e.0
    h = e.1
    x = pair.0
    l = pair.1
    near_lo = lt(sub(x, l), eps)
    near_hi = lt(sub(h, x), eps)
    if near_lo then cast(1.0, f32) else if near_hi then cast(1.0, f32) else cast(0.0, f32)
  }, trips))
}
def mf_lm_rec[n, m](model: &tensor[n, f32] -> &tensor[m, f32] -> tensor[m, f32], features: &tensor[m, f32], observed: &tensor[m, f32], weights: &tensor[m, f32], lo: &tensor[n, f32], hi: &tensor[n, f32], theta: tensor[n, f32], sse: f32, lambda: f32, tol: f32, iters_left: int64, iters_used: int64, fd_eps: f32) -> (tensor[n, f32], f32, int64, bool) = {
  if lte(iters_left, cast(0, int64)) then (theta, sse, iters_used, false) else {
    step_out = mf_lm_step(model, copy(features), copy(observed), copy(weights), copy(theta), copy(lo), copy(hi), lambda, fd_eps)
    theta_prop = step_out.0
    sse_prop = step_out.1
    accepted = lt(sse_prop, sse)
    next_theta = if accepted then theta_prop else theta
    next_sse = if accepted then sse_prop else sse
    lambda_floor = cast(0.0000001, f32)
    lambda_ceiling = cast(10000000.0, f32)
    raw_next = if accepted then div(lambda, cast(3.0, f32)) else mul(lambda, cast(3.0, f32))
    next_lambda = if lt(raw_next, lambda_floor) then lambda_floor else if gt(raw_next, lambda_ceiling) then lambda_ceiling else raw_next
    rel_drop = if eq(sse, cast(0.0, f32)) then cast(0.0, f32) else div(sub(sse, sse_prop), sse)
    abs_rel_drop = if lt(rel_drop, cast(0.0, f32)) then neg(rel_drop) else rel_drop
    now_converged = if accepted then lt(abs_rel_drop, tol) else false
    if now_converged then (next_theta, next_sse, add(iters_used, cast(1, int64)), true) else mf_lm_rec(model, features, observed, weights, lo, hi, next_theta, next_sse, next_lambda, tol, sub(iters_left, cast(1, int64)), add(iters_used, cast(1, int64)), fd_eps)
  }
}
def lm_bounded_nparam[n, m](model: &tensor[n, f32] -> &tensor[m, f32] -> tensor[m, f32], features: &tensor[m, f32], observed: &tensor[m, f32], weights: &tensor[m, f32], theta0: tensor[n, f32], lo: &tensor[n, f32], hi: &tensor[n, f32], lambda0: f32, tol: f32, max_iters: int64, fd_eps: f32) -> (tensor[n, f32], f32, int64, bool, tensor[n, f32]) = {
  theta_clamped0 = clamp_vec(copy(theta0), copy(lo), copy(hi))
  base_pred0 = model(copy(theta_clamped0), copy(features))
  init_r = la_vec_sub(copy(observed), base_pred0)
  init_sse = weighted_sse(init_r, copy(weights))
  rec_out = mf_lm_rec(model, copy(features), copy(observed), copy(weights), copy(lo), copy(hi), theta_clamped0, init_sse, lambda0, tol, max_iters, cast(0, int64), fd_eps)
  theta_final = rec_out.0
  sse_final = rec_out.1
  iters_final = rec_out.2
  converged_final = rec_out.3
  mask = active_set_mask(copy(theta_final), copy(lo), copy(hi), cast(0.0001, f32))
  (theta_final, sse_final, iters_final, converged_final, mask)
}
def multi_target_fit[n, m](model: &tensor[n, f32] -> &tensor[m, f32] -> tensor[m, f32], features: &tensor[m, f32], observed: &tensor[m, f32], weights: &tensor[m, f32], theta0: tensor[n, f32], lo: &tensor[n, f32], hi: &tensor[n, f32], lambda0: f32, tol: f32, max_iters: int64, fd_eps: f32) -> (tensor[n, f32], f32, int64, bool, tensor[n, f32]) = lm_bounded_nparam(model, features, observed, weights, theta0, lo, hi, lambda0, tol, max_iters, fd_eps)
def mf_abs_f32(x: f32) -> f32 = if lt(x, cast(0.0, f32)) then neg(x) else x
def mf_argmin_dist_to(values: List[f32], target: f32) -> int64 = {
  zero_i = cast(0, int64)
  n_len = len(values)
  idxs = range(zero_i, n_len)
  init = (zero_i, mf_abs_f32(sub(index(values, zero_i), target)))
  final = fold(fn (state: (int64, f32), i: int64) -> {
    best_i = state.0
    best_d = state.1
    d_i = mf_abs_f32(sub(index(values, i), target))
    if lt(d_i, best_d) then (i, d_i) else (best_i, best_d)
  }, init, idxs)
  final.0
}
def mf_sabr_smart_initializer[n](strikes: &tensor[n, f32], market_ivs: &tensor[n, f32], forward: f32, t: f32) -> tensor[4, f32] = {
  k_list = to_list(strikes)
  iv_list = to_list(market_ivs)
  n_strikes = len(k_list)
  sqrt_f = sqrt(forward)
  atm_idx = mf_argmin_dist_to(k_list, forward)
  atm_iv = index(iv_list, atm_idx)
  alpha_generic = mul(atm_iv, sqrt_f)
  generic = to_tensor([alpha_generic, cast(0.5, f32), cast(0.0, f32), cast(0.5, f32)])
  if lt(n_strikes, cast(3, int64)) then generic else {
    k_min = fold(fn (acc: f32, k: f32) -> if lt(k, acc) then k else acc, index(k_list, cast(0, int64)), k_list)
    k_max = fold(fn (acc: f32, k: f32) -> if gt(k, acc) then k else acc, index(k_list, cast(0, int64)), k_list)
    spans_forward = if lt(k_min, forward) then gt(k_max, forward) else false
    if not(spans_forward) then to_tensor([alpha_generic, cast(0.5, f32), cast(0.0, f32), cast(0.5, f32)]) else {
      k_low_target = mul(cast(0.9, f32), forward)
      k_high_target = mul(cast(1.1, f32), forward)
      low_idx = mf_argmin_dist_to(k_list, k_low_target)
      high_idx = mf_argmin_dist_to(k_list, k_high_target)
      iv_low = index(iv_list, low_idx)
      iv_high = index(iv_list, high_idx)
      rr = sub(iv_high, iv_low)
      bf = sub(add(iv_high, iv_low), mul(cast(2.0, f32), atm_iv))
      safe_atm = if lt(mf_abs_f32(atm_iv), cast(0.000001, f32)) then cast(0.000001, f32) else atm_iv
      rho_raw = mul(cast(0.5, f32), div(rr, safe_atm))
      rho_0 = clamp_to_bounds(rho_raw, cast(-0.9, f32), cast(0.9, f32))
      nu_raw = mul(cast(2.0, f32), div(bf, safe_atm))
      nu_0 = clamp_to_bounds(nu_raw, cast(0.1, f32), cast(3.0, f32))
      alpha_0 = mul(atm_iv, sqrt_f)
      to_tensor([alpha_0, cast(0.5, f32), rho_0, nu_0])
    }
  }
}
def mf_sabr_multi_start_initializer[n](strikes: &tensor[n, f32], market_ivs: &tensor[n, f32], forward: f32, t: f32) -> tensor[5, 4, f32] = {
  base = mf_sabr_smart_initializer(strikes, market_ivs, forward, t)
  base_l = to_list(base)
  alpha_0 = index(base_l, cast(0, int64))
  beta_0 = index(base_l, cast(1, int64))
  nu_0 = index(base_l, cast(3, int64))
  rho_grid = [cast(-0.7, f32), cast(-0.3, f32), cast(0.0, f32), cast(0.3, f32), cast(0.7, f32)]
  flat = fold(fn (acc: List[f32], r: f32) -> append(append(append(append(acc, alpha_0), beta_0), r), nu_0), [], rho_grid)
  reshape(to_tensor(flat), [cast(5, int64), cast(4, int64)])
}
def mf_identity_matrix[n](template: &tensor[n, f32]) -> tensor[n, n, f32] = {
  n_len = len(to_list(template))
  z_mat = mf_zero_matrix(copy(template))
  idxs = range(cast(0, int64), n_len)
  fold(fn (acc: tensor[n, n, f32], i: int64) -> {
    e_i = mf_basis_vec(i, cast(1.0, f32), copy(template))
    e_j = mf_basis_vec(i, cast(1.0, f32), copy(template))
    add(acc, einsum("i,j->ij", e_i, e_j))
  }, z_mat, idxs)
}
def mf_sse_at[n, m](model: &tensor[n, f32] -> &tensor[m, f32] -> tensor[m, f32], features: &tensor[m, f32], observed: &tensor[m, f32], weights: &tensor[m, f32], theta: &tensor[n, f32]) -> f32 = {
  pred = model(copy(theta), copy(features))
  r = la_vec_sub(copy(observed), pred)
  weighted_sse(r, copy(weights))
}
def mf_fd_gradient_acc[n, m](model: &tensor[n, f32] -> &tensor[m, f32] -> tensor[m, f32], features: &tensor[m, f32], observed: &tensor[m, f32], weights: &tensor[m, f32], theta: &tensor[n, f32], base_sse: f32, tpl_n: &tensor[n, f32], i: int64, n_params: int64, eps: f32) -> tensor[n, f32] = {
  if gte(i, n_params) then { scale_vec(copy(tpl_n), cast(0.0, f32)) } else {
    eps_vec = mf_basis_vec(i, eps, copy(tpl_n))
    theta_plus = la_vec_add(copy(theta), eps_vec)
    sse_plus = mf_sse_at(model, copy(features), copy(observed), copy(weights), copy(theta_plus))
    _ = drop(theta_plus)
    g_i = div(sub(sse_plus, base_sse), eps)
    e_i = mf_basis_vec(i, g_i, copy(tpl_n))
    rest = mf_fd_gradient_acc(model, features, observed, weights, theta, base_sse, tpl_n, add(i, cast(1, int64)), n_params, eps)
    la_vec_add(e_i, rest)
  }
}
def mf_fd_gradient[n, m](model: &tensor[n, f32] -> &tensor[m, f32] -> tensor[m, f32], features: &tensor[m, f32], observed: &tensor[m, f32], weights: &tensor[m, f32], theta: &tensor[n, f32], base_sse: f32, eps: f32) -> tensor[n, f32] = {
  tpl_n = to_tensor(map(fn (t: f32) -> cast(0.0, f32), to_list(theta)))
  n_params = len(to_list(copy(tpl_n)))
  mf_fd_gradient_acc(model, copy(features), copy(observed), copy(weights), copy(theta), base_sse, copy(tpl_n), cast(0, int64), n_params, eps)
}
def mf_bfgs_linesearch[n, m](model: &tensor[n, f32] -> &tensor[m, f32] -> tensor[m, f32], features: &tensor[m, f32], observed: &tensor[m, f32], weights: &tensor[m, f32], theta: &tensor[n, f32], lo: &tensor[n, f32], hi: &tensor[n, f32], p: &tensor[n, f32], sse_curr: f32, gp: f32, alpha: f32, backtracks_left: int64) -> (f32, f32) = {
  step = scale_vec(copy(p), alpha)
  theta_try = clamp_vec(la_vec_add(copy(theta), step), copy(lo), copy(hi))
  sse_try = mf_sse_at(model, copy(features), copy(observed), copy(weights), copy(theta_try))
  _ = drop(theta_try)
  c1 = cast(0.0001, f32)
  armijo = add(sse_curr, mul(mul(c1, alpha), gp))
  if lte(sse_try, armijo) then (alpha, sse_try) else if lte(backtracks_left, cast(0, int64)) then (alpha, sse_try) else mf_bfgs_linesearch(model, features, observed, weights, theta, lo, hi, p, sse_curr, gp, mul(alpha, cast(0.5, f32)), sub(backtracks_left, cast(1, int64)))
}
def mf_bfgs_update[n](h: tensor[n, n, f32], s: &tensor[n, f32], y: &tensor[n, f32], tpl_n: &tensor[n, f32]) -> tensor[n, n, f32] = {
  ys = inner_product(copy(y), copy(s))
  eps_skip = cast(0.0000000001, f32)
  if lte(ys, eps_skip) then {
    _ = drop(tpl_n)
    h
  } else {
    rho = div(cast(1.0, f32), ys)
    neg_rho = neg(rho)
    hy = matvec(copy(h), copy(y))
    hy_scaled = scale_vec(copy(hy), neg_rho)
    _ = drop(hy)
    outer_neg_hy_s = einsum("i,j->ij", hy_scaled, copy(s))
    h1 = add(h, outer_neg_hy_s)
    yt_h1 = vecmat(copy(y), copy(h1))
    yt_h1_scaled = scale_vec(copy(yt_h1), neg_rho)
    _ = drop(yt_h1)
    outer_neg_s_yth1 = einsum("i,j->ij", copy(s), yt_h1_scaled)
    h2 = add(h1, outer_neg_s_yth1)
    s_scaled = scale_vec(copy(s), rho)
    outer_s_s_scaled = einsum("i,j->ij", s_scaled, copy(s))
    _ = drop(tpl_n)
    add(h2, outer_s_s_scaled)
  }
}
def mf_bfgs_rec[n, m](model: &tensor[n, f32] -> &tensor[m, f32] -> tensor[m, f32], features: &tensor[m, f32], observed: &tensor[m, f32], weights: &tensor[m, f32], lo: &tensor[n, f32], hi: &tensor[n, f32], theta: tensor[n, f32], g: tensor[n, f32], h: tensor[n, n, f32], sse: f32, tol: f32, iters_left: int64, iters_used: int64, fd_eps: f32) -> (tensor[n, f32], f32, int64, bool) = {
  if lte(iters_left, cast(0, int64)) then {
    _ = drop(g)
    _ = drop(h)
    (theta, sse, iters_used, false)
  } else {
    hg = matvec(copy(h), copy(g))
    p = scale_vec(copy(hg), cast(-1.0, f32))
    _ = drop(hg)
    gp = inner_product(copy(g), copy(p))
    ls = mf_bfgs_linesearch(model, copy(features), copy(observed), copy(weights), copy(theta), copy(lo), copy(hi), copy(p), sse, gp, cast(1.0, f32), cast(20, int64))
    alpha = ls.0
    sse_new = ls.1
    step = scale_vec(copy(p), alpha)
    _ = drop(p)
    theta_new = clamp_vec(la_vec_add(copy(theta), step), copy(lo), copy(hi))
    g_new = mf_fd_gradient(model, copy(features), copy(observed), copy(weights), copy(theta_new), sse_new, fd_eps)
    s = la_vec_sub(copy(theta_new), copy(theta))
    y = la_vec_sub(copy(g_new), copy(g))
    tpl_n = to_tensor(map(fn (t: f32) -> cast(0.0, f32), to_list(copy(theta_new))))
    h_new = mf_bfgs_update(h, copy(s), copy(y), copy(tpl_n))
    _ = drop(s)
    _ = drop(y)
    _ = drop(g)
    _ = drop(theta)
    _ = drop(tpl_n)
    grad_norm = l2_norm_vec(copy(g_new))
    theta_norm = l2_norm_vec(copy(theta_new))
    one_f = cast(1.0, f32)
    scale_ref = if gt(theta_norm, one_f) then theta_norm else one_f
    grad_conv = lt(grad_norm, mul(tol, scale_ref))
    rel_drop = if eq(sse, cast(0.0, f32)) then cast(0.0, f32) else div(sub(sse, sse_new), sse)
    abs_rel_drop = if lt(rel_drop, cast(0.0, f32)) then neg(rel_drop) else rel_drop
    descended = lt(sse_new, sse)
    sse_conv = if descended then lt(abs_rel_drop, tol) else false
    now_converged = if grad_conv then true else sse_conv
    if now_converged then {
      _ = drop(g_new)
      _ = drop(h_new)
      (theta_new, sse_new, add(iters_used, cast(1, int64)), true)
    } else mf_bfgs_rec(model, features, observed, weights, lo, hi, theta_new, g_new, h_new, sse_new, tol, sub(iters_left, cast(1, int64)), add(iters_used, cast(1, int64)), fd_eps)
  }
}
def bfgs_bounded_nparam[n, m](model: &tensor[n, f32] -> &tensor[m, f32] -> tensor[m, f32], features: &tensor[m, f32], observed: &tensor[m, f32], weights: &tensor[m, f32], theta0: tensor[n, f32], lo: &tensor[n, f32], hi: &tensor[n, f32], tol: f32, max_iters: int64, fd_eps: f32) -> (tensor[n, f32], f32, int64, bool, tensor[n, f32]) = {
  theta_clamped0 = clamp_vec(copy(theta0), copy(lo), copy(hi))
  tpl_n = to_tensor(map(fn (t: f32) -> cast(0.0, f32), to_list(copy(theta_clamped0))))
  init_sse = mf_sse_at(model, copy(features), copy(observed), copy(weights), copy(theta_clamped0))
  init_g = mf_fd_gradient(model, copy(features), copy(observed), copy(weights), copy(theta_clamped0), init_sse, fd_eps)
  init_h = mf_identity_matrix(copy(tpl_n))
  _ = drop(tpl_n)
  rec_out = mf_bfgs_rec(model, copy(features), copy(observed), copy(weights), copy(lo), copy(hi), theta_clamped0, init_g, init_h, init_sse, tol, max_iters, cast(0, int64), fd_eps)
  theta_final = rec_out.0
  sse_final = rec_out.1
  iters_final = rec_out.2
  converged_final = rec_out.3
  mask = active_set_mask(copy(theta_final), copy(lo), copy(hi), cast(0.0001, f32))
  (theta_final, sse_final, iters_final, converged_final, mask)
}
def mf_pipeline_2stage_run[n1, m1, n2, m2](model1: &tensor[n1, f32] -> &tensor[m1, f32] -> tensor[m1, f32], features1: &tensor[m1, f32], observed1: &tensor[m1, f32], weights1: &tensor[m1, f32], theta1_0: tensor[n1, f32], lo1: &tensor[n1, f32], hi1: &tensor[n1, f32], stage1_to_stage2_features: &tensor[n1, f32] -> tensor[m2, f32], model2: &tensor[n2, f32] -> &tensor[m2, f32] -> tensor[m2, f32], observed2: &tensor[m2, f32], weights2: &tensor[m2, f32], theta2_0: tensor[n2, f32], lo2: &tensor[n2, f32], hi2: &tensor[n2, f32], lambda0: f32, tol: f32, max_iters: int64, fd_eps: f32) -> (tensor[n1, f32], tensor[n2, f32], f32, f32, int64, int64, bool, bool) = {
  out1 = lm_bounded_nparam(model1, copy(features1), copy(observed1), copy(weights1), theta1_0, copy(lo1), copy(hi1), lambda0, tol, max_iters, fd_eps)
  theta1_fit = out1.0
  sse1 = out1.1
  iters1 = out1.2
  conv1 = out1.3
  _ = drop(out1.4)
  features2 = stage1_to_stage2_features(copy(theta1_fit))
  out2 = lm_bounded_nparam(model2, copy(features2), copy(observed2), copy(weights2), theta2_0, copy(lo2), copy(hi2), lambda0, tol, max_iters, fd_eps)
  _ = drop(features2)
  theta2_fit = out2.0
  sse2 = out2.1
  iters2 = out2.2
  conv2 = out2.3
  _ = drop(out2.4)
  (theta1_fit, theta2_fit, sse1, sse2, iters1, iters2, conv1, conv2)
}
def sequential_pipeline_2stage[n1, m1, n2, m2](model1: &tensor[n1, f32] -> &tensor[m1, f32] -> tensor[m1, f32], features1: &tensor[m1, f32], observed1: &tensor[m1, f32], weights1: &tensor[m1, f32], theta1_0: tensor[n1, f32], lo1: &tensor[n1, f32], hi1: &tensor[n1, f32], stage1_to_stage2_features: &tensor[n1, f32] -> tensor[m2, f32], model2: &tensor[n2, f32] -> &tensor[m2, f32] -> tensor[m2, f32], observed2: &tensor[m2, f32], weights2: &tensor[m2, f32], theta2_0: tensor[n2, f32], lo2: &tensor[n2, f32], hi2: &tensor[n2, f32], lambda0: f32, tol: f32, max_iters: int64, fd_eps: f32) -> (tensor[n1, f32], tensor[n2, f32], f32, f32, int64, int64, bool, bool) = mf_pipeline_2stage_run(model1, features1, observed1, weights1, theta1_0, lo1, hi1, stage1_to_stage2_features, model2, observed2, weights2, theta2_0, lo2, hi2, lambda0, tol, max_iters, fd_eps)
def mf_pipeline_theta2[n1, m1, n2, m2](model1: &tensor[n1, f32] -> &tensor[m1, f32] -> tensor[m1, f32], features1: &tensor[m1, f32], observed1: &tensor[m1, f32], weights1: &tensor[m1, f32], theta1_0: &tensor[n1, f32], lo1: &tensor[n1, f32], hi1: &tensor[n1, f32], stage1_to_stage2_features: &tensor[n1, f32] -> tensor[m2, f32], model2: &tensor[n2, f32] -> &tensor[m2, f32] -> tensor[m2, f32], observed2: &tensor[m2, f32], weights2: &tensor[m2, f32], theta2_0: &tensor[n2, f32], lo2: &tensor[n2, f32], hi2: &tensor[n2, f32], lambda0: f32, tol: f32, max_iters: int64, fd_eps: f32) -> tensor[n2, f32] = {
  out = mf_pipeline_2stage_run(model1, copy(features1), copy(observed1), copy(weights1), copy(theta1_0), copy(lo1), copy(hi1), stage1_to_stage2_features, model2, copy(observed2), copy(weights2), copy(theta2_0), copy(lo2), copy(hi2), lambda0, tol, max_iters, fd_eps)
  _ = drop(out.0)
  theta2_fit = out.1
  theta2_fit
}
def mf_pipeline_bump_observed1[n1, m1, n2, m2](model1: &tensor[n1, f32] -> &tensor[m1, f32] -> tensor[m1, f32], features1: &tensor[m1, f32], observed1: &tensor[m1, f32], weights1: &tensor[m1, f32], theta1_0: &tensor[n1, f32], lo1: &tensor[n1, f32], hi1: &tensor[n1, f32], stage1_to_stage2_features: &tensor[n1, f32] -> tensor[m2, f32], model2: &tensor[n2, f32] -> &tensor[m2, f32] -> tensor[m2, f32], observed2: &tensor[m2, f32], weights2: &tensor[m2, f32], theta2_0: &tensor[n2, f32], lo2: &tensor[n2, f32], hi2: &tensor[n2, f32], lambda0: f32, tol: f32, max_iters: int64, fd_eps: f32, tpl_m1: &tensor[m1, f32], j: int64, eps_bump: f32) -> tensor[n2, f32] = {
  bump_vec = mf_basis_vec(j, eps_bump, copy(tpl_m1))
  observed1_bumped = la_vec_add(copy(observed1), bump_vec)
  mf_pipeline_theta2(model1, copy(features1), copy(observed1_bumped), copy(weights1), copy(theta1_0), copy(lo1), copy(hi1), stage1_to_stage2_features, model2, copy(observed2), copy(weights2), copy(theta2_0), copy(lo2), copy(hi2), lambda0, tol, max_iters, fd_eps)
}
def mf_pipeline_column_j[n1, m1, n2, m2](model1: &tensor[n1, f32] -> &tensor[m1, f32] -> tensor[m1, f32], features1: &tensor[m1, f32], observed1: &tensor[m1, f32], weights1: &tensor[m1, f32], theta1_0: &tensor[n1, f32], lo1: &tensor[n1, f32], hi1: &tensor[n1, f32], stage1_to_stage2_features: &tensor[n1, f32] -> tensor[m2, f32], model2: &tensor[n2, f32] -> &tensor[m2, f32] -> tensor[m2, f32], observed2: &tensor[m2, f32], weights2: &tensor[m2, f32], theta2_0: &tensor[n2, f32], lo2: &tensor[n2, f32], hi2: &tensor[n2, f32], lambda0: f32, tol: f32, max_iters: int64, fd_eps: f32, tpl_m1: &tensor[m1, f32], theta2_base: &tensor[n2, f32], j: int64, eps_bump: f32) -> List[f32] = {
  theta2_bumped = mf_pipeline_bump_observed1(model1, copy(features1), copy(observed1), copy(weights1), copy(theta1_0), copy(lo1), copy(hi1), stage1_to_stage2_features, model2, copy(observed2), copy(weights2), copy(theta2_0), copy(lo2), copy(hi2), lambda0, tol, max_iters, fd_eps, copy(tpl_m1), j, eps_bump)
  diff = la_vec_sub(theta2_bumped, copy(theta2_base))
  col = scale_vec(diff, div(cast(1.0, f32), eps_bump))
  to_list(col)
}
def mf_pipeline_columns[n1, m1, n2, m2](model1: &tensor[n1, f32] -> &tensor[m1, f32] -> tensor[m1, f32], features1: &tensor[m1, f32], observed1: &tensor[m1, f32], weights1: &tensor[m1, f32], theta1_0: &tensor[n1, f32], lo1: &tensor[n1, f32], hi1: &tensor[n1, f32], stage1_to_stage2_features: &tensor[n1, f32] -> tensor[m2, f32], model2: &tensor[n2, f32] -> &tensor[m2, f32] -> tensor[m2, f32], observed2: &tensor[m2, f32], weights2: &tensor[m2, f32], theta2_0: &tensor[n2, f32], lo2: &tensor[n2, f32], hi2: &tensor[n2, f32], lambda0: f32, tol: f32, max_iters: int64, fd_eps: f32, tpl_m1: &tensor[m1, f32], theta2_base: &tensor[n2, f32], m1_len: int64, eps_bump: f32) -> List[List[f32]] = {
  idxs = range(cast(0, int64), m1_len)
  map(fn (j: int64) -> mf_pipeline_column_j(model1, copy(features1), copy(observed1), copy(weights1), copy(theta1_0), copy(lo1), copy(hi1), stage1_to_stage2_features, model2, copy(observed2), copy(weights2), copy(theta2_0), copy(lo2), copy(hi2), lambda0, tol, max_iters, fd_eps, copy(tpl_m1), copy(theta2_base), j, eps_bump), idxs)
}
def sequential_pipeline_2stage_gradient[n1, m1, n2, m2](model1: &tensor[n1, f32] -> &tensor[m1, f32] -> tensor[m1, f32], features1: &tensor[m1, f32], observed1: &tensor[m1, f32], weights1: &tensor[m1, f32], theta1_0: &tensor[n1, f32], lo1: &tensor[n1, f32], hi1: &tensor[n1, f32], stage1_to_stage2_features: &tensor[n1, f32] -> tensor[m2, f32], model2: &tensor[n2, f32] -> &tensor[m2, f32] -> tensor[m2, f32], observed2: &tensor[m2, f32], weights2: &tensor[m2, f32], theta2_0: &tensor[n2, f32], lo2: &tensor[n2, f32], hi2: &tensor[n2, f32], lambda0: f32, tol: f32, max_iters: int64, fd_eps: f32, bump_eps: f32) -> tensor[n2, m1, f32] = {
  theta2_base = mf_pipeline_theta2(model1, copy(features1), copy(observed1), copy(weights1), copy(theta1_0), copy(lo1), copy(hi1), stage1_to_stage2_features, model2, copy(observed2), copy(weights2), copy(theta2_0), copy(lo2), copy(hi2), lambda0, tol, max_iters, fd_eps)
  tpl_m1 = to_tensor(map(fn (v: f32) -> cast(0.0, f32), to_list(observed1)))
  m1_len = len(to_list(copy(tpl_m1)))
  n2_len = len(to_list(copy(theta2_base)))
  cols = mf_pipeline_columns(model1, features1, observed1, weights1, theta1_0, lo1, hi1, stage1_to_stage2_features, model2, observed2, weights2, theta2_0, lo2, hi2, lambda0, tol, max_iters, fd_eps, copy(tpl_m1), copy(theta2_base), m1_len, bump_eps)
  _ = drop(theta2_base)
  _ = drop(tpl_m1)
  row_idxs = range(cast(0, int64), n2_len)
  col_idxs = range(cast(0, int64), m1_len)
  flat = fold(fn (acc_i: List[f32], i: int64) -> { fold(fn (acc_j: List[f32], j: int64) -> append(acc_j, index(index(cols, j), i)), acc_i, col_idxs) }, [], row_idxs)
  reshape(to_tensor(flat), [n2_len, m1_len])
}
