module Shoals.Dupire
import Nautilus.LinAlg (la_basis_n_f32)
import Shoals.Pricing (bs_call_scalar)
import Nautilus.Interpolation (linear_interp_sorted, spline_eval)
export (du_bs_call_q, du_forward, du_local_vol_from_iv_surface, du_local_vol_from_call_closure, du_cubic_log_moneyness_interp, du_local_vol_sentinel, du_is_local_vol_sentinel)
def du_zero_f() -> f32 = cast(0.0, f32)
def du_one_f() -> f32 = cast(1.0, f32)
def du_two_f() -> f32 = cast(2.0, f32)
def du_half_f() -> f32 = cast(0.5, f32)
def du_min_t() -> f32 = cast(0.0001, f32)
def du_min_d2c_dk2() -> f32 = cast(1e-10, f32)
def du_bs_call_q(s: f32, k: f32, r: f32, q: f32, sigma: f32, t: f32) -> f32 = {
  s_eff = mul(s, exp(neg(mul(q, t))))
  bs_call_scalar(s_eff, k, r, sigma, t)
}
def du_forward(s0: f32, r: f32, q: f32, t: f32) -> f32 = mul(s0, exp(mul(sub(r, q), t)))
def du_local_vol_sentinel() -> f32 = div(du_zero_f(), du_zero_f())
def du_is_local_vol_sentinel(x: f32) -> bool = neq(x, x)
def du_clamp_t(t: f32) -> f32 = if lt(t, du_min_t()) then du_min_t() else t
def du_call_from_iv(iv_surface_fn: f32 -> f32 -> f32, s0: f32, r: f32, q: f32, k: f32, t: f32) -> f32 = {
  t_safe = du_clamp_t(t)
  f_now = du_forward(s0, r, q, t_safe)
  log_m = log(div(k, f_now))
  iv = iv_surface_fn(log_m, t_safe)
  du_bs_call_q(s0, k, r, q, iv, t_safe)
}
def du_local_vol_from_call_closure(call_fn: f32 -> f32 -> f32, r: f32, q: f32, k_query: f32, t_query: f32, fd_eps_k: f32, fd_eps_t: f32) -> f32 = {
  c_kp = call_fn(add(k_query, fd_eps_k), t_query)
  c_km = call_fn(sub(k_query, fd_eps_k), t_query)
  c_kc = call_fn(k_query, t_query)
  t_lo = sub(t_query, fd_eps_t)
  t_lo_safe = if lt(t_lo, du_min_t()) then du_min_t() else t_lo
  c_tp = call_fn(k_query, add(t_query, fd_eps_t))
  c_tm = call_fn(k_query, t_lo_safe)
  dt_eff = sub(add(t_query, fd_eps_t), t_lo_safe)
  dc_dt = div(sub(c_tp, c_tm), dt_eff)
  dc_dk = div(sub(c_kp, c_km), mul(du_two_f(), fd_eps_k))
  d2c_dk2 = div(sub(add(c_kp, c_km), mul(du_two_f(), c_kc)), mul(fd_eps_k, fd_eps_k))
  numerator = add(add(dc_dt, mul(mul(sub(r, q), k_query), dc_dk)), mul(q, c_kc))
  denom_half = mul(du_half_f(), mul(mul(k_query, k_query), d2c_dk2))
  if lt(d2c_dk2, du_min_d2c_dk2()) then du_local_vol_sentinel() else {
    sigma_sq = div(numerator, denom_half)
    if lt(sigma_sq, du_zero_f()) then du_local_vol_sentinel() else sqrt(sigma_sq)
  }
}
def du_local_vol_from_iv_surface(iv_surface_fn: f32 -> f32 -> f32, s0: f32, r: f32, q: f32, k_query: f32, t_query: f32, fd_eps_k: f32, fd_eps_t: f32) -> f32 = {
  call_fn = fn (k: f32, t: f32) -> du_call_from_iv(iv_surface_fn, s0, r, q, k, t)
  du_local_vol_from_call_closure(call_fn, r, q, k_query, t_query, fd_eps_k, fd_eps_t)
}
def du_extract_row[n_k, n_t](iv_grid: &tensor[n_t, n_k, f32], j: i64, tpl_t: &tensor[n_t, f32]) -> tensor[n_k, f32] = {
  e_j = la_basis_n_f32(j, du_one_f(), tpl_t)
  einsum("ij,i->j", iv_grid, e_j)
}
-- Both grid axes are read by interpolators that bracket a query in traversal
-- order, so an axis that is out of order interpolates over the wrong interval
-- and returns a confident wrong implied vol: no trap, no NaN, no diagnostic.
-- `linear_interp_sorted` does that on the time axis; `spline_eval`'s natural
-- cubic fit does it on the log-moneyness knots derived from `strikes`, where a
-- reordered pair also feeds a negative segment width into the tridiagonal
-- solve. The import list names `linear_interp_sorted`, but a precondition
-- stated in a dependency's identifier is a hint to a reader of this module,
-- not a disclosure to a caller of `du_cubic_log_moneyness_interp`, whose own
-- signature names no ordering rule for either axis.
--
-- Reject rather than re-sort. Re-sorting would answer a different question
-- from the one the caller asked, and here it would also have to permute
-- `iv_grid`'s rows and columns to keep them aligned with the axes it moved.
-- The pillar-order guard in `Shoals.Curves` made the same choice.
--
-- Index of the first entry that does not exceed its predecessor, or -1 when
-- the axis is strictly increasing. A NaN entry fails every comparison and so
-- reports as out of order, which is the right answer: it has no position
-- relative to anything.
def du_first_unsorted(xs: List[f32]) -> i64 = {
  idxs = range(cast(1, i64), len(xs))
  fold(fn (acc: i64, j: i64) -> if gte(acc, cast(0, i64)) then acc else if gt(index(xs, j), index(xs, sub(j, cast(1, i64)))) then acc else j, cast(-1, i64), idxs)
}
def du_strictly_increasing(xs: List[f32]) -> bool = lt(du_first_unsorted(xs), cast(0, i64))
-- The measured-values tail shared by both axis diagnostics; `noun` is the axis
-- word, so one helper serves `strike` and `time`. Reached only when
-- `du_first_unsorted` has returned a real index.
def du_unsorted_detail(noun: string, xs: List[f32]) -> string = {
  j = du_first_unsorted(xs)
  i_prev = sub(j, cast(1, i64))
  head = string_concat(": index ", string_concat(to_string(j), string_concat(" has ", noun)))
  mid = string_concat(" ", string_concat(to_string(index(xs, j)), string_concat(", which does not exceed ", noun)))
  tail = string_concat(" ", string_concat(to_string(index(xs, i_prev)), string_concat(" at index ", to_string(i_prev))))
  string_concat(head, string_concat(mid, tail))
}
-- The axes are validated in parameter order, so when both are out of order the
-- strike axis is the one reported. The guard is threaded through `forward`
-- rather than bound on its own, so it is load-bearing on the returned value
-- and cannot be dropped as a dead binding.
def du_cubic_log_moneyness_interp[n_k, n_t](strikes: &tensor[n_k, f32], times: &tensor[n_t, f32], iv_grid: &tensor[n_t, n_k, f32], forward: f32, k_query: f32, t_query: f32) -> f32 = {
  ks_l = to_list(strikes)
  ts_l = to_list(times)
  forward_checked = if not(du_strictly_increasing(ks_l)) then fail(string_concat("Shoals.Dupire.du_cubic_log_moneyness_interp: strikes must be strictly increasing", du_unsorted_detail("strike", ks_l))) else if not(du_strictly_increasing(ts_l)) then fail(string_concat("Shoals.Dupire.du_cubic_log_moneyness_interp: grid times must be strictly increasing", du_unsorted_detail("time", ts_l))) else forward
  x_query = log(div(k_query, forward_checked))
  xs = to_tensor(map(fn (kk: f32) -> log(div(kk, forward_checked)), ks_l))
  n_t_len = len(ts_l)
  tpl_t = to_tensor(map(fn (v: f32) -> du_zero_f(), ts_l))
  iv_at_query_per_t = to_tensor(map(fn (j: i64) -> {
    row = du_extract_row(iv_grid, j, copy(tpl_t))
    spline_eval(copy(xs), row, x_query)
  }, range(cast(0, i64), n_t_len)))
  linear_interp_sorted(times, iv_at_query_per_t, t_query)
}
