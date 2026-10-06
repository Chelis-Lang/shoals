module Shoals.Lsm
import Nautilus.Distributions (normal_sample)
import Nautilus.LinAlg (solve_3x3)
def lsm_put_payoff(s: f32, k: f32) -> f32 = {
  diff = sub(k, s)
  if gt(diff, cast(0.0, f32)) then diff else cast(0.0, f32)
}
def lsm_vec3(a: f32, b: f32, c: f32) -> tensor[3, f32] = to_tensor(append(append(append([], a), b), c))
def lsm_mat3_from_rows(r0: f32, r1: f32, r2: f32, r3: f32, r4: f32, r5: f32, r6: f32, r7: f32, r8: f32) -> tensor[3, 3, f32] = {
  flat = append(append(append(append(append(append(append(append(append([], r0), r1), r2), r3), r4), r5), r6), r7), r8)
  reshape(to_tensor(flat), [cast(3, i64), cast(3, i64)])
}
def lsm_moments_8(pairs: List[(f32, f32)]) -> (f32, f32, f32, f32, f32, f32, f32, f32) = {
  zero = cast(0.0, f32)
  init = (zero, zero, zero, zero, zero, zero, zero, zero)
  fold(fn (state: (f32, f32, f32, f32, f32, f32, f32, f32), p: (f32, f32)) -> {
    x = p.0
    y = p.1
    x2 = mul(x, x)
    x3 = mul(x2, x)
    x4 = mul(x2, x2)
    n_next = add(state.0, cast(1.0, f32))
    sx_next = add(state.1, x)
    sxx_next = add(state.2, x2)
    sxxx_next = add(state.3, x3)
    sxxxx_next = add(state.4, x4)
    sy_next = add(state.5, y)
    sxy_next = add(state.6, mul(x, y))
    sxxy_next = add(state.7, mul(x2, y))
    (n_next, sx_next, sxx_next, sxxx_next, sxxxx_next, sy_next, sxy_next, sxxy_next)
  }, init, pairs)
}
def lsm_solve_regression_from_moments(n_sum: f32, sx_sum: f32, sxx_sum: f32, sxxx_sum: f32, sxxxx_sum: f32, sy_sum: f32, sxy_sum: f32, sxxy_sum: f32) -> (f32, f32, f32) = {
  xtx = lsm_mat3_from_rows(n_sum, sx_sum, sxx_sum, sx_sum, sxx_sum, sxxx_sum, sxx_sum, sxxx_sum, sxxxx_sum)
  xty = lsm_vec3(sy_sum, sxy_sum, sxxy_sum)
  beta = solve_3x3(copy(xtx), copy(xty))
  beta_l = to_list(beta)
  (index(beta_l, cast(0, i64)), index(beta_l, cast(1, i64)), index(beta_l, cast(2, i64)))
}
def lsm_polynomial_regression[k](xs: tensor[k, f32], ys: tensor[k, f32]) -> (f32, f32, f32) = {
  pairs = zip(to_list(xs), to_list(ys))
  m = lsm_moments_8(pairs)
  lsm_solve_regression_from_moments(m.0, m.1, m.2, m.3, m.4, m.5, m.6, m.7)
}
def lsm_chunk_list_to_lists(flat: List[f32], chunk_size: i64) -> List[List[f32]] = {
  acc_state = fold(fn (state: (List[List[f32]], List[f32], i64), v: f32) -> {
    completed = state.0
    cur = state.1
    cnt = state.2
    next_cnt = add(cnt, cast(1, i64))
    cur_next = append(cur, v)
    if eq(next_cnt, chunk_size) then (append(completed, cur_next), [], cast(0, i64)) else (completed, cur_next, next_cnt)
  }, ([], [], cast(0, i64)), flat)
  acc_state.0
}
def lsm_american_put[n](rng_key: key, paths_template: tensor[n, f32], s0: f32, k: f32, r: f32, sigma: f32, t: f32, n_steps: i64) -> f32 = {
  n_paths = numel(copy(paths_template))
  total_z = mul(n_paths, n_steps)
  z_template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), total_z)))
  _ = paths_template
  z_t = normal_sample(rng_key, z_template, cast(0.0, f32), cast(1.0, f32))
  dt = div(t, cast(n_steps, f32))
  sqrt_dt = sqrt(dt)
  half_sigma_sq = mul(cast(0.5, f32), mul(sigma, sigma))
  drift = mul(sub(r, half_sigma_sq), dt)
  log_s0 = log(s0)
  log_inc_flat = to_tensor(map(fn (zi: f32) -> add(drift, mul(sigma, mul(sqrt_dt, zi))), to_list(z_t)))
  log_inc_2d = reshape(log_inc_flat, [n_paths, n_steps])
  log_cumsum_2d = cumsum(log_inc_2d, 1)
  log_cumsum_T = permute(log_cumsum_2d, 1, 0)
  s_time_major_flat_l = to_list(reshape(log_cumsum_T, [total_z]))
  s_time_major_with_s0 = map(fn (v: f32) -> exp(add(log_s0, v)), s_time_major_flat_l)
  s_per_step = lsm_chunk_list_to_lists(s_time_major_with_s0, n_paths)
  s_at_terminal = index(s_per_step, sub(n_steps, cast(1, i64)))
  init_state_terminal = map(fn (s_term: f32) -> (lsm_put_payoff(s_term, k), cast(n_steps, f32)), s_at_terminal)
  back_step_idxs_rev = map(fn (i: i64) -> sub(sub(n_steps, cast(2, i64)), i), range(cast(0, i64), sub(n_steps, cast(1, i64))))
  final_state = fold(fn (st: List[(f32, f32)], step_idx_zero_based: i64) -> {
    t_idx_calendar = add(step_idx_zero_based, cast(1, i64))
    s_at_step = index(s_per_step, step_idx_zero_based)
    triples = map(fn (entry: ((f32, f32), f32)) -> {
      old = entry.0
      cf = old.0
      t_ex_f = old.1
      s_t = entry.1
      pay_p = lsm_put_payoff(s_t, k)
      t_now_f = cast(t_idx_calendar, f32)
      disc = exp(neg(mul(r, mul(dt, sub(t_ex_f, t_now_f)))))
      y_i = mul(disc, cf)
      (s_t, pay_p, y_i)
    }, zip(st, s_at_step))
    itm_pairs = fold(fn (acc: List[(f32, f32)], tr: (f32, f32, f32)) -> {
      pay_p = tr.1
      if gt(pay_p, cast(0.0, f32)) then append(acc, (tr.0, tr.2)) else acc
    }, [], triples)
    n_itm = cast(len(itm_pairs), i64)
    if lt(n_itm, cast(4, i64)) then st else {
      moms = lsm_moments_8(itm_pairs)
      coeffs = lsm_solve_regression_from_moments(moms.0, moms.1, moms.2, moms.3, moms.4, moms.5, moms.6, moms.7)
      b0 = coeffs.0
      b1 = coeffs.1
      b2 = coeffs.2
      map(fn (entry: ((f32, f32), (f32, f32, f32))) -> {
        old = entry.0
        cf = old.0
        t_ex_f_old = old.1
        tr = entry.1
        s_t = tr.0
        pay_p = tr.1
        if gt(pay_p, cast(0.0, f32)) then {
          c_hat = add(b0, add(mul(b1, s_t), mul(b2, mul(s_t, s_t))))
          if gt(pay_p, c_hat) then (pay_p, cast(t_idx_calendar, f32)) else (cf, t_ex_f_old)
        } else (cf, t_ex_f_old)
      }, zip(st, triples))
    }
  }, init_state_terminal, back_step_idxs_rev)
  pv_list = map(fn (e: (f32, f32)) -> {
    cf = e.0
    t_ex_f = e.1
    mul(exp(neg(mul(r, mul(dt, t_ex_f)))), cf)
  }, final_state)
  n_f = cast(n_paths, f32)
  sum_pv = fold(fn (acc: f32, v: f32) -> add(acc, v), cast(0.0, f32), pv_list)
  div(sum_pv, n_f)
}
export (lsm_put_payoff, lsm_polynomial_regression, lsm_american_put)
