module Shoals.Pde
export (pde_european_call_cn, pde_european_put_cn, pde_american_put_cn, pde_spread_option_adi, pde_thomas_solve)
def pde_checked_count(parameter: string, count: i64, minimum: i64) -> i64 = if lt(count, minimum) then fail(string_concat("Shoals.Pde: ", string_concat(parameter, string_concat(" must be at least ", string_concat(to_string(minimum), string_concat("; received ", to_string(count))))))) else count
def pde_zero() -> f32 = cast(0.0, f32)
def pde_one() -> f32 = cast(1.0, f32)
def pde_half() -> f32 = cast(0.5, f32)
def pde_max(a: f32, b: f32) -> f32 = if gt(a, b) then a else b
def pde_log_grid_params(s0: f32, s_max_mult: f32, n_x: i64) -> (f32, f32) = {
  log_s0 = log(s0)
  log_mult = log(s_max_mult)
  x_min = sub(log_s0, log_mult)
  x_max = add(log_s0, log_mult)
  denom = n_x |> sub(cast(1, i64)) |> cast(f32)
  dx = x_max |> sub(x_min) |> div(denom)
  (x_min, dx)
}
def pde_grid_x(x_min: f32, dx: f32, n_x: i64) -> List[f32] = {
  idxs = 0 |> (fn (__chelis_pipe) -> (cast(__chelis_pipe, i64) |> range(n_x)))
  map(fn (i: i64) -> add(x_min, i |> (fn (__chelis_pipe) -> (cast(__chelis_pipe, f32) |> mul(dx)))), idxs)
}
def pde_payoff_call(xs: List[f32], k: f32) -> List[f32] = map(fn (x: f32) -> pde_max(sub(exp(x), k), pde_zero()), xs)
def pde_payoff_put(xs: List[f32], k: f32) -> List[f32] = map(fn (x: f32) -> (k |> sub(exp(x)) |> pde_max(pde_zero())), xs)
def pde_op_coeffs(sigma: f32, r: f32, q: f32, dx: f32) -> (f32, f32, f32) = {
  sigma_sq = mul(sigma, sigma)
  half_sigma_sq = mul(pde_half(), sigma_sq)
  drift = r |> sub(q) |> sub(half_sigma_sq)
  dx_sq = mul(dx, dx)
  diff_part = div(half_sigma_sq, dx_sq)
  adv_part = div(drift, 2.0 |> (fn (__chelis_pipe) -> (cast(__chelis_pipe, f32) |> mul(dx))))
  a_coef = sub(diff_part, adv_part)
  b_coef = sub(neg(div(sigma_sq, dx_sq)), r)
  c_coef = add(diff_part, adv_part)
  (a_coef, b_coef, c_coef)
}
def pde_build_lhs(a_coef: f32, b_coef: f32, c_coef: f32, alpha: f32, n_x: i64) -> (List[f32], List[f32], List[f32]) = {
  n_xm1 = sub(n_x, cast(1, i64))
  neg_alpha = neg(alpha)
  idxs = 0 |> (fn (__chelis_pipe) -> (cast(__chelis_pipe, i64) |> range(n_x)))
  lower_l = map(fn (i: i64) -> {
    is_lo = eq(i, cast(0, i64))
    is_hi = eq(i, n_xm1)
    if is_lo then pde_zero() else if is_hi then pde_zero() else mul(neg_alpha, a_coef)
  }, idxs)
  diag_l = map(fn (i: i64) -> {
    is_lo = eq(i, cast(0, i64))
    is_hi = eq(i, n_xm1)
    if is_lo then pde_one() else if is_hi then pde_one() else sub(pde_one(), mul(alpha, b_coef))
  }, idxs)
  upper_l = map(fn (i: i64) -> {
    is_lo = eq(i, cast(0, i64))
    is_hi = eq(i, n_xm1)
    if is_lo then pde_zero() else if is_hi then pde_zero() else mul(neg_alpha, c_coef)
  }, idxs)
  (lower_l, diag_l, upper_l)
}
def pde_thomas_fwd(lower: List[f32], diag: List[f32], upper: List[f32], b_vec: List[f32], n_x: i64) -> (List[f32], List[f32]) = {
  d0 = index(diag, cast(0, i64))
  b0 = index(b_vec, cast(0, i64))
  init_state = ([d0], [b0])
  step_idxs = 1
    |> (fn (__chelis_pipe) -> (cast(__chelis_pipe, i64) |> range(n_x)))
  final_state = fold(fn (st: (List[f32], List[f32]), i: i64) -> {
    d_acc = st.0
    b_acc = st.1
    im1 = sub(i, cast(1, i64))
    l_i = index(lower, i)
    d_im1 = index(d_acc, im1)
    u_im1 = index(upper, im1)
    d_i_raw = index(diag, i)
    b_im1 = index(b_acc, im1)
    b_i_raw = index(b_vec, i)
    abs_dim1 = if lt(d_im1, pde_zero()) then neg(d_im1) else d_im1
    safe_dim1 = if lt(abs_dim1, cast(1e-10, f32)) then pde_one() else d_im1
    w = div(l_i, safe_dim1)
    d_i_new = sub(d_i_raw, mul(w, u_im1))
    b_i_new = sub(b_i_raw, mul(w, b_im1))
    (append(d_acc, d_i_new), append(b_acc, b_i_new))
  }, init_state, step_idxs)
  (final_state.0, final_state.1)
}
def pde_thomas_bwd(upper: List[f32], diag_f: List[f32], b_f: List[f32], n_x: i64) -> List[f32] = {
  n_xm1 = sub(n_x, cast(1, i64))
  d_last = index(diag_f, n_xm1)
  b_last = index(b_f, n_xm1)
  abs_dl = if lt(d_last, pde_zero()) then neg(d_last) else d_last
  safe_dl = if lt(abs_dl, cast(1e-10, f32)) then pde_one() else d_last
  x_last = div(b_last, safe_dl)
  init_state = [x_last]
  step_idxs = 1
    |> (fn (__chelis_pipe) -> (cast(__chelis_pipe, i64) |> range(n_x)))
  rev_x = fold(fn (acc: List[f32], j: i64) -> {
    i = n_xm1 |> sub(j) |> sub(cast(0, i64))
    last_idx = sub(cast(len(acc), i64), cast(1, i64))
    x_ip1 = index(acc, last_idx)
    d_i = index(diag_f, i)
    u_i = index(upper, i)
    b_i = index(b_f, i)
    abs_di = if lt(d_i, pde_zero()) then neg(d_i) else d_i
    safe_di = if lt(abs_di, cast(1e-10, f32)) then pde_one() else d_i
    x_i = b_i |> sub(mul(u_i, x_ip1)) |> div(safe_di)
    append(acc, x_i)
  }, init_state, step_idxs)
  rev_idxs = 0 |> (fn (__chelis_pipe) -> (cast(__chelis_pipe, i64) |> range(n_x)))
  map(fn (k: i64) -> {
    rev_pos = n_xm1 |> sub(k) |> sub(cast(0, i64))
    index(rev_x, rev_pos)
  }, rev_idxs)
}
def pde_thomas_solve(lower: List[f32], diag: List[f32], upper: List[f32], b_vec: List[f32], n_x: i64) -> List[f32] = {
  fwd_out = pde_thomas_fwd(lower, diag, upper, b_vec, n_x)
  diag_f = fwd_out.0
  b_f = fwd_out.1
  pde_thomas_bwd(upper, diag_f, b_f, n_x)
}
def pde_apply_op_with_alpha(v: List[f32], a_coef: f32, b_coef: f32, c_coef: f32, alpha: f32, bc_lo: f32, bc_hi: f32, n_x: i64) -> List[f32] = {
  n_xm1 = sub(n_x, cast(1, i64))
  idxs = 0 |> (fn (__chelis_pipe) -> (cast(__chelis_pipe, i64) |> range(n_x)))
  map(fn (i: i64) -> {
    is_lo = eq(i, cast(0, i64))
    is_hi = eq(i, n_xm1)
    if is_lo then bc_lo else if is_hi then bc_hi else {
      vm = index(v, sub(i, cast(1, i64)))
      vi = index(v, i)
      vp = index(v, add(i, cast(1, i64)))
      l_v = add(add(mul(a_coef, vm), mul(b_coef, vi)), mul(c_coef, vp))
      add(vi, mul(alpha, l_v))
    }
  }, idxs)
}
def pde_bc_call(s_max: f32, k: f32, r: f32, q: f32, tau: f32) -> (f32, f32) = {
  bc_lo = pde_zero()
  disc_r = exp(neg(mul(r, tau)))
  disc_q = exp(neg(mul(q, tau)))
  bc_hi = s_max |> mul(disc_q) |> sub(mul(k, disc_r))
  bc_hi_safe = if lt(bc_hi, pde_zero()) then pde_zero() else bc_hi
  (bc_lo, bc_hi_safe)
}
def pde_bc_put(k: f32, r: f32, tau: f32) -> (f32, f32) = {
  disc_r = exp(neg(mul(r, tau)))
  bc_lo = mul(k, disc_r)
  bc_hi = pde_zero()
  (bc_lo, bc_hi)
}
def pde_bc_american_put(k: f32) -> (f32, f32) = (k, pde_zero())
def pde_apply_early_exercise_put(v_cont: List[f32], xs: List[f32], k: f32) -> List[f32] = {
  pairs = zip(v_cont, xs)
  map(fn (e: (f32, f32)) -> {
    vc = e.0
    x = e.1
    intrinsic = k |> sub(exp(x)) |> pde_max(pde_zero())
    pde_max(vc, intrinsic)
  }, pairs)
}
def pde_step_vanilla(v: List[f32], a_coef: f32, b_coef: f32, c_coef: f32, dt: f32, n_x: i64, bc_pair_next: (f32, f32), is_rannacher: bool) -> List[f32] = {
  bc_lo_next = bc_pair_next.0
  bc_hi_next = bc_pair_next.1
  alpha_lhs = if is_rannacher then dt else mul(pde_half(), dt)
  alpha_rhs = if is_rannacher then pde_zero() else mul(pde_half(), dt)
  lhs_triple = pde_build_lhs(a_coef, b_coef, c_coef, alpha_lhs, n_x)
  lower_lhs = lhs_triple.0
  diag_lhs = lhs_triple.1
  upper_lhs = lhs_triple.2
  rhs_vec = pde_apply_op_with_alpha(v, a_coef, b_coef, c_coef, alpha_rhs, bc_lo_next, bc_hi_next, n_x)
  pde_thomas_solve(lower_lhs, diag_lhs, upper_lhs, rhs_vec, n_x)
}
def pde_interp_at_s0(xs: List[f32], v: List[f32], s0: f32, n_x: i64) -> f32 = {
  log_s0 = log(s0)
  x0 = index(xs, cast(0, i64))
  x1 = index(xs, cast(1, i64))
  dx = sub(x1, x0)
  raw_pos = log_s0 |> sub(x0) |> div(dx)
  pos_floor_f = if lt(raw_pos, pde_zero()) then pde_zero() else raw_pos
  pos_floor_int = cast_trunc(pos_floor_f, i64)
  n_xm2 = sub(n_x, cast(2, i64))
  i_lo = if gt(pos_floor_int, n_xm2) then n_xm2 else pos_floor_int
  i_hi = add(i_lo, cast(1, i64))
  x_lo = index(xs, i_lo)
  x_hi = index(xs, i_hi)
  v_lo = index(v, i_lo)
  v_hi = index(v, i_hi)
  span = sub(x_hi, x_lo)
  w_hi = log_s0 |> sub(x_lo) |> div(span)
  w_lo = sub(pde_one(), w_hi)
  w_lo |> mul(v_lo) |> add(mul(w_hi, v_hi))
}
def pde_vanilla_driver(s0: f32, k: f32, r: f32, q: f32, sigma: f32, t: f32, n_x: i64, n_t: i64, s_max_mult: f32, is_call: bool, is_american: bool) -> f32 = {
  n_x_ok = pde_checked_count("n_x", n_x, 3i64)
  n_t_ok = pde_checked_count("n_t", n_t, 1i64)
  grid_params = pde_log_grid_params(s0, s_max_mult, n_x_ok)
  x_min = grid_params.0
  dx = grid_params.1
  xs = pde_grid_x(x_min, dx, n_x_ok)
  n_xm1 = sub(n_x_ok, cast(1, i64))
  s_max = xs |> index(n_xm1) |> exp
  op_coeffs = pde_op_coeffs(sigma, r, q, dx)
  a_coef = op_coeffs.0
  b_coef = op_coeffs.1
  c_coef = op_coeffs.2
  v_init = if is_call then pde_payoff_call(xs, k) else pde_payoff_put(xs, k)
  dt = div(t, cast(n_t_ok, f32))
  step_idxs = 0
    |> (fn (__chelis_pipe) -> (cast(__chelis_pipe, i64) |> range(n_t_ok)))
  v_final = fold(fn (v_acc: List[f32], n: i64) -> {
    tau_next = mul(cast(add(n, cast(1, i64)), f32), dt)
    bc_pair_next = if is_american then pde_bc_american_put(k) else if is_call then pde_bc_call(s_max, k, r, q, tau_next) else pde_bc_put(k, r, tau_next)
    is_rannacher = lt(n, cast(2, i64))
    v_cont = pde_step_vanilla(v_acc, a_coef, b_coef, c_coef, dt, n_x_ok, bc_pair_next, is_rannacher)
    if is_american then pde_apply_early_exercise_put(v_cont, xs, k) else v_cont
  }, v_init, step_idxs)
  pde_interp_at_s0(xs, v_final, s0, n_x_ok)
}
def pde_european_call_cn(s0: f32, k: f32, r: f32, q: f32, sigma: f32, t: f32, n_x: i64, n_t: i64, s_max_mult: f32) -> f32 = pde_vanilla_driver(s0, k, r, q, sigma, t, n_x, n_t, s_max_mult, true, false)
def pde_european_put_cn(s0: f32, k: f32, r: f32, q: f32, sigma: f32, t: f32, n_x: i64, n_t: i64, s_max_mult: f32) -> f32 = pde_vanilla_driver(s0, k, r, q, sigma, t, n_x, n_t, s_max_mult, false, false)
def pde_american_put_cn(s0: f32, k: f32, r: f32, q: f32, sigma: f32, t: f32, n_x: i64, n_t: i64, s_max_mult: f32) -> f32 = pde_vanilla_driver(s0, k, r, q, sigma, t, n_x, n_t, s_max_mult, false, true)
def pde_adi_payoff_spread_2d(xs1: List[f32], xs2: List[f32], k: f32) -> List[List[f32]] =
  map(fn (x1: f32) -> {
    s1 = exp(x1)
    map(fn (x2: f32) -> {
      s2 = exp(x2)
      pde_max(sub(sub(s1, s2), k), pde_zero())
    }, xs2)
  }, xs1)
-- Derivative helpers return A_j V (zero on the prescribed perimeter),
-- rather than V + alpha*A_j V. This makes each CS coefficient explicit.
def pde_adi_apply_1d(v_row: List[f32], a_coef: f32, b_coef: f32, c_coef: f32) -> List[f32] = {
  n_last = sub(cast(len(v_row), i64), 1i64)
  map(fn (entry: (i64, f32)) -> {
    i = entry.0
    if or(eq(i, 0i64), eq(i, n_last)) then 0.0f32 else {
      vm = index(v_row, sub(i, 1i64))
      vp = index(v_row, add(i, 1i64))
      add(add(mul(a_coef, vm), mul(b_coef, entry.1)), mul(c_coef, vp))
    }
  }, enumerate(v_row))
}
def pde_adi_transpose(v_2d: List[List[f32]], n_outer: i64, n_inner: i64) -> List[List[f32]] = {
  rows = map(fn (i: i64) -> index(v_2d, i), range(0i64, n_outer))
  map(fn (j: i64) -> map(fn (row: List[f32]) -> index(row, j), rows), range(0i64, n_inner))
}
def pde_adi_apply_rows(v: List[List[f32]], op: (f32, f32, f32)) -> List[List[f32]] = {
  last = sub(cast(len(v), i64), 1i64)
  map(fn (entry: (i64, List[f32])) -> if or(eq(entry.0, 0i64), eq(entry.0, last)) then map(fn (x: f32) -> 0.0f32, entry.1) else pde_adi_apply_1d(entry.1, op.0, op.1, op.2), enumerate(v))
}
def pde_adi_apply_x1(v: List[List[f32]], op: (f32, f32, f32), n_x1: i64, n_x2: i64) -> List[List[f32]] = {
  cols = pde_adi_transpose(v, n_x1, n_x2)
  pde_adi_transpose(pde_adi_apply_rows(cols, op), n_x2, n_x1)
}
def pde_adi_solve_rows(v: List[List[f32]], op: (f32, f32, f32), alpha: f32, n_inner: i64) -> List[List[f32]] = {
  lhs = pde_build_lhs(op.0, op.1, op.2, alpha, n_inner)
  last = sub(cast(len(v), i64), 1i64)
  map(fn (entry: (i64, List[f32])) -> if or(eq(entry.0, 0i64), eq(entry.0, last)) then entry.1 else pde_thomas_solve(lhs.0, lhs.1, lhs.2, entry.1, n_inner), enumerate(v))
}
def pde_adi_solve_x1(v: List[List[f32]], op: (f32, f32, f32), alpha: f32, n_x1: i64, n_x2: i64) -> List[List[f32]] = {
  cols = pde_adi_transpose(v, n_x1, n_x2)
  pde_adi_transpose(pde_adi_solve_rows(cols, op, alpha, n_x1), n_x2, n_x1)
}
def pde_adi_add_scaled(v: List[List[f32]], w: List[List[f32]], alpha: f32) -> List[List[f32]] = map(fn (rows: (List[f32], List[f32])) -> map(fn (cells: (f32, f32)) -> add(cells.0, mul(alpha, cells.1)), zip(rows.0, rows.1)), zip(v, w))
def pde_adi_cross(v: List[List[f32]], cross_coef: f32, dx1: f32, dx2: f32, n_x1: i64, n_x2: i64) -> List[List[f32]] = {
  denom = mul(4.0f32, mul(dx1, dx2))
  map(fn (entry: (i64, List[f32])) -> {
    i = entry.0
    if or(eq(i, 0i64), eq(i, sub(n_x1, 1i64))) then map(fn (x: f32) -> 0.0f32, entry.1) else {
      row_p = index(v, add(i, 1i64))
      row_m = index(v, sub(i, 1i64))
      map(fn (cell: (i64, f32)) -> {
        j = cell.0
        if or(eq(j, 0i64), eq(j, sub(n_x2, 1i64))) then 0.0f32 else {
          v_pp = index(row_p, add(j, 1i64))
          v_pm = index(row_p, sub(j, 1i64))
          v_mp = index(row_m, add(j, 1i64))
          v_mm = index(row_m, sub(j, 1i64))
          mul(cross_coef, div(sub(add(v_pp, v_mm), add(v_pm, v_mp)), denom))
        }
      }, enumerate(entry.1))
    }
  }, enumerate(v))
}
def pde_adi_boundary_grid(s1s: List[f32], s2s: List[f32], k: f32, r: f32, q1: f32, q2: f32, tau: f32) -> List[List[f32]] = {
  disc_q1 = exp(neg(mul(q1, tau)))
  disc_q2 = exp(neg(mul(q2, tau)))
  disc_k = mul(k, exp(neg(mul(r, tau))))
  map(fn (s1: f32) -> {
    s1_disc = mul(s1, disc_q1)
    map(fn (s2: f32) -> pde_max(sub(sub(s1_disc, mul(s2, disc_q2)), disc_k), 0.0f32), s2s)
  }, s1s)
}
def pde_adi_set_boundary(v: List[List[f32]], boundary: List[List[f32]], n_x1: i64, n_x2: i64) -> List[List[f32]] =
  map(fn (entry: (i64, (List[f32], List[f32]))) -> {
    i = entry.0
    rows = entry.1
    if or(eq(i, 0i64), eq(i, sub(n_x1, 1i64))) then rows.1 else map(fn (cell: (i64, (f32, f32))) -> {
      j = cell.0
      values = cell.1
      if or(eq(j, 0i64), eq(j, sub(n_x2, 1i64))) then values.1 else values.0
    }, enumerate(zip(rows.0, rows.1)))
  }, enumerate(zip(v, boundary)))
-- Craig-Sneyd is MCS at theta=1/2. The complete mixed derivative enters
-- the Euler predictor, then its trapezoidal correction uses the predicted
-- end state. Unlike applying half_dt once, its dt->0 limit is
-- A0+A1+A2. Boundary source terms are carried by old/new perimeter values.
def pde_adi_step(v: List[List[f32]], op1: (f32, f32, f32), op2: (f32, f32, f32), cross_coef: f32, dx1: f32, dx2: f32, n_x1: i64, n_x2: i64, boundary_next: List[List[f32]], dt: f32, damped: bool) -> List[List[f32]] = {
  a0_v = pde_adi_cross(v, cross_coef, dx1, dx2, n_x1, n_x2)
  a1_v = pde_adi_apply_x1(v, op1, n_x1, n_x2)
  a2_v = pde_adi_apply_rows(v, op2)
  alpha = if damped then dt else mul(0.5f32, dt)
  y0_raw = pde_adi_add_scaled(pde_adi_add_scaled(pde_adi_add_scaled(v, a0_v, dt), a1_v, dt), a2_v, dt)
  y0 = pde_adi_set_boundary(y0_raw, boundary_next, n_x1, n_x2)
  rhs1 = pde_adi_set_boundary(pde_adi_add_scaled(y0, a1_v, neg(alpha)), boundary_next, n_x1, n_x2)
  y1 = pde_adi_solve_x1(rhs1, op1, alpha, n_x1, n_x2)
  rhs2 = pde_adi_set_boundary(pde_adi_add_scaled(y1, a2_v, neg(alpha)), boundary_next, n_x1, n_x2)
  y2 = pde_adi_solve_rows(rhs2, op2, alpha, n_x2)
  if damped then y2 else {
    a0_y2 = pde_adi_cross(y2, cross_coef, dx1, dx2, n_x1, n_x2)
    corrected = pde_adi_add_scaled(pde_adi_add_scaled(y0, a0_y2, alpha), a0_v, neg(alpha))
    corrected_rhs1 = pde_adi_set_boundary(pde_adi_add_scaled(corrected, a1_v, neg(alpha)), boundary_next, n_x1, n_x2)
    corrected_y1 = pde_adi_solve_x1(corrected_rhs1, op1, alpha, n_x1, n_x2)
    corrected_rhs2 = pde_adi_set_boundary(pde_adi_add_scaled(corrected_y1, a2_v, neg(alpha)), boundary_next, n_x1, n_x2)
    pde_adi_solve_rows(corrected_rhs2, op2, alpha, n_x2)
  }
}
def pde_adi_log_half_width(sigma: f32, r: f32, q: f32, t: f32) -> f32 = {
  sigma_sq = mul(sigma, sigma)
  drift = sub(sub(r, q), mul(0.5f32, sigma_sq))
  abs_drift = if lt(drift, 0.0f32) then neg(drift) else drift
  moment_shift = mul(sigma_sq, t)
  diffusion_width = mul(6.0f32, mul(sigma, sqrt(t)))
  pde_max(log(2.0f32), add(add(mul(abs_drift, t), moment_shift), diffusion_width))
}
-- Private width inputs support domain-refinement probes without growing the
-- public API. The wrapper always uses the automatic six-sigma widths.
def pde_adi_spread_driver(s1_0: f32, s2_0: f32, k: f32, r: f32, q1: f32, q2: f32, sigma1: f32, sigma2: f32, rho: f32, t: f32, n_x1: i64, n_x2: i64, n_t: i64, width1: f32, width2: f32) -> f32 = {
  n_x1_ok = pde_checked_count("n_x1", n_x1, 3i64)
  n_x2_ok = pde_checked_count("n_x2", n_x2, 3i64)
  n_t_ok = pde_checked_count("n_t", n_t, 1i64)
  x_min_1 = sub(log(s1_0), width1)
  dx1 = div(mul(2.0f32, width1), cast(sub(n_x1_ok, 1i64), f32))
  x_min_2 = sub(log(s2_0), width2)
  dx2 = div(mul(2.0f32, width2), cast(sub(n_x2_ok, 1i64), f32))
  xs1 = pde_grid_x(x_min_1, dx1, n_x1_ok)
  xs2 = pde_grid_x(x_min_2, dx2, n_x2_ok)
  s1s = map(fn (x: f32) -> exp(x), xs1)
  s2s = map(fn (x: f32) -> exp(x), xs2)
  raw_op1 = pde_op_coeffs(sigma1, r, q1, dx1)
  raw_op2 = pde_op_coeffs(sigma2, r, q2, dx2)
  half_r = mul(0.5f32, r)
  op1 = (raw_op1.0, add(raw_op1.1, half_r), raw_op1.2)
  op2 = (raw_op2.0, add(raw_op2.1, half_r), raw_op2.2)
  cross_coef = mul(rho, mul(sigma1, sigma2))
  v_init = pde_adi_payoff_spread_2d(xs1, xs2, k)
  dt = div(t, cast(n_t_ok, f32))
  half_dt = mul(0.5f32, dt)
  v_final = fold(fn (v: List[List[f32]], n: i64) -> {
    tau_old = mul(cast(n, f32), dt)
    tau_next = mul(cast(add(n, 1i64), f32), dt)
    boundary_next = pde_adi_boundary_grid(s1s, s2s, k, r, q1, q2, tau_next)
    if lt(n, 2i64) then {
      tau_half = add(tau_old, half_dt)
      boundary_half = pde_adi_boundary_grid(s1s, s2s, k, r, q1, q2, tau_half)
      half = pde_adi_step(v, op1, op2, cross_coef, dx1, dx2, n_x1_ok, n_x2_ok, boundary_half, half_dt, true)
      pde_adi_step(half, op1, op2, cross_coef, dx1, dx2, n_x1_ok, n_x2_ok, boundary_next, half_dt, true)
    } else pde_adi_step(v, op1, op2, cross_coef, dx1, dx2, n_x1_ok, n_x2_ok, boundary_next, dt, false)
  }, v_init, range(0i64, n_t_ok))
  log_s1 = log(s1_0)
  log_s2 = log(s2_0)
  x1_0 = index(xs1, cast(0, i64))
  x2_0 = index(xs2, cast(0, i64))
  raw_pos_1 = log_s1 |> sub(x1_0) |> div(dx1)
  raw_pos_2 = log_s2 |> sub(x2_0) |> div(dx2)
  pos_1_safe = if lt(raw_pos_1, pde_zero()) then pde_zero() else raw_pos_1
  pos_2_safe = if lt(raw_pos_2, pde_zero()) then pde_zero() else raw_pos_2
  pos_1_int = cast_trunc(pos_1_safe, i64)
  pos_2_int = cast_trunc(pos_2_safe, i64)
  n_x1m2 = sub(n_x1_ok, cast(2, i64))
  n_x2m2 = sub(n_x2_ok, cast(2, i64))
  i_lo = if gt(pos_1_int, n_x1m2) then n_x1m2 else pos_1_int
  j_lo = if gt(pos_2_int, n_x2m2) then n_x2m2 else pos_2_int
  i_hi = add(i_lo, cast(1, i64))
  j_hi = add(j_lo, cast(1, i64))
  x1_lo = index(xs1, i_lo)
  x1_hi = index(xs1, i_hi)
  x2_lo = index(xs2, j_lo)
  x2_hi = index(xs2, j_hi)
  w1_hi = log_s1 |> sub(x1_lo) |> div(sub(x1_hi, x1_lo))
  w1_lo = sub(pde_one(), w1_hi)
  w2_hi = log_s2 |> sub(x2_lo) |> div(sub(x2_hi, x2_lo))
  w2_lo = sub(pde_one(), w2_hi)
  row_lo = index(v_final, i_lo)
  row_hi = index(v_final, i_hi)
  v_ll = index(row_lo, j_lo)
  v_lh = index(row_lo, j_hi)
  v_hl = index(row_hi, j_lo)
  v_hh = index(row_hi, j_hi)
  v_l = w2_lo |> mul(v_ll) |> add(mul(w2_hi, v_lh))
  v_h = w2_lo |> mul(v_hl) |> add(mul(w2_hi, v_hh))
  w1_lo |> mul(v_l) |> add(mul(w1_hi, v_h))
}
def pde_spread_option_adi(s1_0: f32, s2_0: f32, k: f32, r: f32, q1: f32, q2: f32, sigma1: f32, sigma2: f32, rho: f32, t: f32, n_x1: i64, n_x2: i64, n_t: i64) -> f32 =
  if eq(t, 0.0f32) then pde_max(sub(sub(s1_0, s2_0), k), 0.0f32) else {
    width1 = pde_adi_log_half_width(sigma1, r, q1, t)
    width2 = pde_adi_log_half_width(sigma2, r, q2, t)
    pde_adi_spread_driver(s1_0, s2_0, k, r, q1, q2, sigma1, sigma2, rho, t, n_x1, n_x2, n_t, width1, width2)
  }
