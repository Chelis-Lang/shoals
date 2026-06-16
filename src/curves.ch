module Shoals.Curves
import Nautilus.Interpolation (linear_interp_sorted, spline_eval)
import Nautilus.Roots (brent)
export (CurveKind, YieldCurve, yield_curve_from_pillars, yield_curve_tagged, curve_kind, ois, ibor, sofr, sonia, estr, custom_curve, rate_at, spline_rate_at, log_linear_rate_at, nss_rate, discount_factor, bootstrap_zero_from_par, parallel_shift, key_rate_shift, twist, butterfly, scale_rates, Instrument, deposit, zero_coupon, cur_par_swap, instrument_tenor, instrument_market_price_or_rate, bootstrap_multi, bootstrap_multi_curve, bootstrap_residual_at_pillar, bootstrap_grad_diagonal, bootstrap_grad_at_solution, fd_bump_pillar_rate, instrument_validate, bootstrap_grad_full_jacobian, CurveBasis, curve_basis_from_pillars, basis_spread_at, discount_factor_with_basis, bootstrap_basis_curve)
type CurveKind =
  | Ois
  | Ibor
  | Sofr
  | Sonia
  | Estr
  | Custom { label: string }
type YieldCurve[n] =
  | YieldCurve { kind: CurveKind, times: tensor[n, f32], rates: tensor[n, f32] }
def ois() -> CurveKind = Ois
def ibor() -> CurveKind = Ibor
def sofr() -> CurveKind = Sofr
def sonia() -> CurveKind = Sonia
def estr() -> CurveKind = Estr
def custom_curve(label: string) -> CurveKind = Custom { label: label }
def yield_curve_from_pillars[n](times: tensor[n, f32], rates: tensor[n, f32]) -> YieldCurve[n] = YieldCurve { kind: Custom { label: "untagged" }, times: times, rates: rates }
def yield_curve_tagged[n](kind: CurveKind, times: tensor[n, f32], rates: tensor[n, f32]) -> YieldCurve[n] = YieldCurve { kind: kind, times: times, rates: rates }
def curve_kind[n](curve: YieldCurve[n]) -> CurveKind = {
  match curve with {
    | YieldCurve { kind: k, times: _, rates: _ } => k
  }
}
def rate_at[n](curve: YieldCurve[n], t: f32) -> f32 = {
  match curve with {
    | YieldCurve { kind: _, times: ts, rates: rs } => linear_interp_sorted(ts, rs, t)
  }
}
def spline_rate_at[n](curve: YieldCurve[n], t: f32) -> f32 = {
  match curve with {
    | YieldCurve { kind: _, times: ts, rates: rs } => spline_eval(ts, rs, t)
  }
}
def log_linear_rate_at[n](curve: YieldCurve[n], t: f32) -> f32 = {
  match curve with {
    | YieldCurve { kind: _, times: ts, rates: rs } => {
    log_rs = to_tensor(map(fn (r: f32) -> log(r), to_list(copy(rs))))
    lr = linear_interp_sorted(ts, log_rs, t)
    exp(lr)
  }
  }
}
def nss_rate(beta0: f32, beta1: f32, beta2: f32, beta3: f32, tau1: f32, tau2: f32, t: f32) -> f32 = {
  x1 = div(t, tau1)
  x2 = div(t, tau2)
  e1 = exp(neg(x1))
  e2 = exp(neg(x2))
  term1_num = sub(cast(1.0, f32), e1)
  term1 = if eq(t, cast(0.0, f32)) then cast(1.0, f32) else div(term1_num, x1)
  term2 = sub(term1, e1)
  term3_num = sub(cast(1.0, f32), e2)
  term3_first = if eq(t, cast(0.0, f32)) then cast(1.0, f32) else div(term3_num, x2)
  term3 = sub(term3_first, e2)
  add(beta0, add(mul(beta1, term1), add(mul(beta2, term2), mul(beta3, term3))))
}
def discount_factor[n](curve: YieldCurve[n], t: f32) -> f32 = {
  r = rate_at(curve, t)
  exp(neg(mul(r, t)))
}
def bootstrap_zero_from_par[n](times: tensor[n, f32], par_yields: tensor[n, f32]) -> YieldCurve[n] = {
  ts_l = to_list(copy(times))
  ys_l = to_list(copy(par_yields))
  pairs = zip(ts_l, ys_l)
  init = (cast(0.0, f32), [])
  out = fold(fn (state: (f32, List[f32]), entry: (f32, f32)) -> {
    cum_pv = state.0
    rates_acc = state.1
    t_i = entry.0
    c = entry.1
    numer = sub(cast(1.0, f32), mul(c, cum_pv))
    p_i = div(numer, add(cast(1.0, f32), c))
    r_i = if lte(p_i, cast(0.0, f32)) then div(cast(0.0, f32), cast(0.0, f32)) else div(neg(log(p_i)), t_i)
    new_rates = append(rates_acc, r_i)
    (add(cum_pv, p_i), new_rates)
  }, init, pairs)
  rates_l = out.1
  rates_t = to_tensor(rates_l)
  YieldCurve { kind: Custom { label: "bootstrapped" }, times: times, rates: rates_t }
}
def scale_rates[n](curve: YieldCurve[n], factor: f32) -> YieldCurve[n] = {
  match curve with {
    | YieldCurve { kind: k, times: ts, rates: rs } => {
    new_rates = to_tensor(map(fn (r: f32) -> mul(r, factor), to_list(copy(rs))))
    YieldCurve { kind: k, times: ts, rates: new_rates }
  }
  }
}
def parallel_shift[n](curve: YieldCurve[n], delta: f32) -> YieldCurve[n] = {
  match curve with {
    | YieldCurve { kind: k, times: ts, rates: rs } => {
    new_rates = to_tensor(map(fn (r: f32) -> add(r, delta), to_list(copy(rs))))
    YieldCurve { kind: k, times: ts, rates: new_rates }
  }
  }
}
def key_rate_shift[n](curve: YieldCurve[n], pillar_index: int64, delta: f32) -> YieldCurve[n] = {
  match curve with {
    | YieldCurve { kind: k, times: ts, rates: rs } => {
    rs_l = to_list(copy(rs))
    idxs = range(cast(0, int64), cast(len(rs_l), int64))
    pairs = zip(idxs, rs_l)
    new_rates_l = map(fn (entry: (int64, f32)) -> if eq(entry.0, pillar_index) then add(entry.1, delta) else entry.1, pairs)
    YieldCurve { kind: k, times: ts, rates: to_tensor(new_rates_l) }
  }
  }
}
def twist[n](curve: YieldCurve[n], short_delta: f32, long_delta: f32) -> YieldCurve[n] = {
  match curve with {
    | YieldCurve { kind: k, times: ts, rates: rs } => {
    ts_l = to_list(copy(ts))
    rs_l = to_list(copy(rs))
    t_max = fold(fn (acc: f32, x: f32) -> if gt(x, acc) then x else acc, cast(0.0, f32), ts_l)
    t_min = fold(fn (acc: f32, x: f32) -> if lt(x, acc) then x else acc, t_max, ts_l)
    span = sub(t_max, t_min)
    pairs = zip(ts_l, rs_l)
    new_rates_l = map(fn (entry: (f32, f32)) -> {
      t_i = entry.0
      r_i = entry.1
      alpha = if eq(span, cast(0.0, f32)) then cast(0.0, f32) else div(sub(t_i, t_min), span)
      delta = add(mul(sub(cast(1.0, f32), alpha), short_delta), mul(alpha, long_delta))
      add(r_i, delta)
    }, pairs)
    YieldCurve { kind: k, times: ts, rates: to_tensor(new_rates_l) }
  }
  }
}
def butterfly[n](curve: YieldCurve[n], wing_delta: f32, body_delta: f32) -> YieldCurve[n] = {
  match curve with {
    | YieldCurve { kind: k, times: ts, rates: rs } => {
    ts_l = to_list(copy(ts))
    rs_l = to_list(copy(rs))
    t_max = fold(fn (acc: f32, x: f32) -> if gt(x, acc) then x else acc, cast(0.0, f32), ts_l)
    t_min = fold(fn (acc: f32, x: f32) -> if lt(x, acc) then x else acc, t_max, ts_l)
    t_mid = mul(cast(0.5, f32), add(t_min, t_max))
    span = sub(t_max, t_min)
    half_span = mul(cast(0.5, f32), span)
    pairs = zip(ts_l, rs_l)
    new_rates_l = map(fn (entry: (f32, f32)) -> {
      t_i = entry.0
      r_i = entry.1
      dist_from_mid = if lt(t_i, t_mid) then sub(t_mid, t_i) else sub(t_i, t_mid)
      w = if eq(half_span, cast(0.0, f32)) then cast(0.0, f32) else div(dist_from_mid, half_span)
      delta = add(mul(w, wing_delta), mul(sub(cast(1.0, f32), w), body_delta))
      add(r_i, delta)
    }, pairs)
    YieldCurve { kind: k, times: ts, rates: to_tensor(new_rates_l) }
  }
  }
}
type Instrument =
  | Deposit { tenor: f32, rate: f32 }
  | ZeroCoupon { tenor: f32, price: f32 }
  | ParSwap { tenor: f32, par_rate: f32 }
def deposit(tenor: f32, rate: f32) -> Instrument = Deposit { tenor: tenor, rate: rate }
def zero_coupon(tenor: f32, price: f32) -> Instrument = ZeroCoupon { tenor: tenor, price: price }
def cur_par_swap(tenor: f32, par_rate: f32) -> Instrument = ParSwap { tenor: tenor, par_rate: par_rate }
def instrument_tenor(inst: Instrument) -> f32 = {
  match inst with {
    | Deposit { tenor: t, rate: _ } => t
    | ZeroCoupon { tenor: t, price: _ } => t
    | ParSwap { tenor: t, par_rate: _ } => t
  }
}
def instrument_market_price_or_rate(inst: Instrument) -> f32 = {
  match inst with {
    | Deposit { tenor: _, rate: r } => r
    | ZeroCoupon { tenor: _, price: p } => p
    | ParSwap { tenor: _, par_rate: r } => r
  }
}
def deposit_implied_zero(t: f32, simple_rate: f32) -> f32 = {
  df = div(cast(1.0, f32), add(cast(1.0, f32), mul(simple_rate, t)))
  div(neg(log(df)), t)
}
def zero_coupon_implied_zero(t: f32, price: f32) -> f32 = div(neg(log(price)), t)
def cum_pv_at(times_so_far: List[f32], rates_so_far: List[f32]) -> f32 = {
  pairs = zip(times_so_far, rates_so_far)
  fold(fn (acc: f32, e: (f32, f32)) -> add(acc, exp(neg(mul(e.1, e.0)))), cast(0.0, f32), pairs)
}
def cur_par_swap_residual(t_i: f32, par_rate: f32, cum_pv: f32, zero_rate_candidate: f32) -> f32 = {
  df_i = exp(neg(mul(zero_rate_candidate, t_i)))
  full_pv = add(mul(par_rate, add(cum_pv, df_i)), df_i)
  sub(full_pv, cast(1.0, f32))
}
def bootstrap_residual_at_pillar(inst: Instrument, times_so_far: List[f32], rates_so_far: List[f32], zero_rate_candidate: f32) -> f32 = {
  match inst with {
    | Deposit { tenor: t, rate: r } => sub(zero_rate_candidate, deposit_implied_zero(t, r))
    | ZeroCoupon { tenor: t, price: p } => sub(zero_rate_candidate, zero_coupon_implied_zero(t, p))
    | ParSwap { tenor: t, par_rate: r } => cur_par_swap_residual(t, r, cum_pv_at(times_so_far, rates_so_far), zero_rate_candidate)
  }
}
def solve_pillar_rate(inst: Instrument, times_so_far: List[f32], rates_so_far: List[f32]) -> f32 = {
  f_at = fn (z: f32) -> bootstrap_residual_at_pillar(inst, times_so_far, rates_so_far, z)
  brent(f_at, cast(-0.5, f32), cast(2.0, f32), cast(0.0000001, f32), cast(100, int64))
}
def bootstrap_multi(instruments: List[Instrument]) -> (List[f32], List[f32]) = {
  init = ([], [])
  fold(fn (state: (List[f32], List[f32]), inst: Instrument) -> {
    ts_so_far = state.0
    rs_so_far = state.1
    r_new = solve_pillar_rate(inst, ts_so_far, rs_so_far)
    t_new = instrument_tenor(inst)
    (append(ts_so_far, t_new), append(rs_so_far, r_new))
  }, init, instruments)
}
def bootstrap_multi_curve[n](instruments: List[Instrument], times_template: tensor[n, f32]) -> YieldCurve[n] = {
  out = bootstrap_multi(instruments)
  times_t = to_tensor(out.0)
  rates_t = to_tensor(out.1)
  YieldCurve { kind: Custom { label: "bootstrap-multi" }, times: times_t, rates: rates_t }
}
def bootstrap_grad_diagonal(inst: Instrument, solved_rate: f32, cum_pv_before: f32) -> f32 = {
  match inst with {
    | Deposit { tenor: t, rate: r } => div(cast(1.0, f32), add(cast(1.0, f32), mul(r, t)))
    | ZeroCoupon { tenor: t, price: p } => neg(div(cast(1.0, f32), mul(t, p)))
    | ParSwap { tenor: t, par_rate: r } => {
    e_neg_zt = exp(neg(mul(solved_rate, t)))
    partial_z = neg(mul(t, mul(add(r, cast(1.0, f32)), e_neg_zt)))
    partial_r = add(cum_pv_before, e_neg_zt)
    neg(div(partial_r, partial_z))
  }
  }
}
def fd_bump_pillar_rate(inst: Instrument, times_so_far: List[f32], rates_so_far: List[f32], step: f32) -> f32 = {
  bumped = match inst with {
    | Deposit { tenor: t, rate: r } => deposit(t, add(r, step))
    | ZeroCoupon { tenor: t, price: p } => zero_coupon(t, add(p, step))
    | ParSwap { tenor: t, par_rate: r } => cur_par_swap(t, add(r, step))
  }
  z_up = solve_pillar_rate(bumped, times_so_far, rates_so_far)
  z_base = solve_pillar_rate(inst, times_so_far, rates_so_far)
  div(sub(z_up, z_base), step)
}
def bootstrap_grad_at_solution(instruments: List[Instrument]) -> List[f32] = {
  init = ([], [], [], cast(0.0, f32))
  out = fold(fn (state: (List[f32], List[f32], List[f32], f32), inst: Instrument) -> {
    ts_so_far = state.0
    rs_so_far = state.1
    grads_so_far = state.2
    cum_pv_so_far = state.3
    r_new = solve_pillar_rate(inst, ts_so_far, rs_so_far)
    t_new = instrument_tenor(inst)
    g_raw = bootstrap_grad_diagonal(inst, r_new, cum_pv_so_far)
    g_new = if eq(r_new, r_new) then g_raw else div(cast(0.0, f32), cast(0.0, f32))
    df_new = exp(neg(mul(r_new, t_new)))
    (append(ts_so_far, t_new), append(rs_so_far, r_new), append(grads_so_far, g_new), add(cum_pv_so_far, df_new))
  }, init, instruments)
  out.2
}
def instrument_validate(inst: Instrument) -> bool = {
  match inst with {
    | Deposit { tenor: t, rate: r } => if lte(t, cast(0.0, f32)) then false else if lte(r, cast(-1.0, f32)) then false else true
    | ZeroCoupon { tenor: t, price: p } => if lte(t, cast(0.0, f32)) then false else if lte(p, cast(0.0, f32)) then false else if gt(p, cast(1.0, f32)) then false else true
    | ParSwap { tenor: t, par_rate: _ } => if lte(t, cast(0.0, f32)) then false else true
  }
}
def cur_all_instruments_valid(instruments: List[Instrument]) -> bool = fold(fn (acc: bool, inst: Instrument) -> if acc then instrument_validate(inst) else false, true, instruments)
def cur_l_row_for_pillar(inst: Instrument, t_i: f32, z_i: f32, times_so_far: List[f32], rates_so_far: List[f32]) -> List[f32] = {
  match inst with {
    | Deposit { tenor: _, rate: _ } => map(fn (t_k: f32) -> cast(0.0, f32), times_so_far)
    | ZeroCoupon { tenor: _, price: _ } => map(fn (t_k: f32) -> cast(0.0, f32), times_so_far)
    | ParSwap { tenor: _, par_rate: r } => {
    denom = neg(mul(t_i, mul(add(cast(1.0, f32), r), exp(neg(mul(z_i, t_i))))))
    pairs = zip(times_so_far, rates_so_far)
    map(fn (e: (f32, f32)) -> {
      t_k = e.0
      z_k = e.1
      numer = mul(r, neg(mul(t_k, exp(neg(mul(z_k, t_k))))))
      div(numer, denom)
    }, pairs)
  }
  }
}
def cur_dot_l_j(l_row: List[f32], j_prev_col: List[f32]) -> f32 = {
  pairs = zip(l_row, j_prev_col)
  fold(fn (acc: f32, e: (f32, f32)) -> add(acc, mul(e.0, e.1)), cast(0.0, f32), pairs)
}
def cur_jacobian_row(diag_i: f32, l_row: List[f32], j_prev_rows: List[List[f32]], m_len: int64, i_pos: int64) -> List[f32] = {
  col_idxs = range(cast(0, int64), m_len)
  map(fn (j: int64) -> {
    j_prev_col = map(fn (row: List[f32]) -> index(row, j), j_prev_rows)
    correction = cur_dot_l_j(l_row, j_prev_col)
    d_ij = if eq(j, i_pos) then diag_i else cast(0.0, f32)
    sub(d_ij, correction)
  }, col_idxs)
}
def cur_nan_jacobian[m](paths_template: &tensor[m, f32]) -> tensor[m, m, f32] = {
  m_len = len(to_list(paths_template))
  nan_val = div(cast(0.0, f32), cast(0.0, f32))
  total = mul(m_len, m_len)
  idxs = range(cast(0, int64), total)
  flat = map(fn (k: int64) -> nan_val, idxs)
  reshape(to_tensor(flat), [m_len, m_len])
}
def cur_full_jacobian_rows(instruments: List[Instrument], m_len: int64) -> List[List[f32]] = {
  init = ([], [], cast(0.0, f32), [], cast(0, int64))
  out = fold(fn (state: (List[f32], List[f32], f32, List[List[f32]], int64), inst: Instrument) -> {
    ts_so_far = state.0
    rs_so_far = state.1
    cum_pv_so_far = state.2
    rows_so_far = state.3
    i_pos = state.4
    r_new = solve_pillar_rate(inst, ts_so_far, rs_so_far)
    t_new = instrument_tenor(inst)
    diag_raw = bootstrap_grad_diagonal(inst, r_new, cum_pv_so_far)
    diag_i = if eq(r_new, r_new) then diag_raw else div(cast(0.0, f32), cast(0.0, f32))
    l_row = cur_l_row_for_pillar(inst, t_new, r_new, ts_so_far, rs_so_far)
    row_i = cur_jacobian_row(diag_i, l_row, rows_so_far, m_len, i_pos)
    df_new = exp(neg(mul(r_new, t_new)))
    (append(ts_so_far, t_new), append(rs_so_far, r_new), add(cum_pv_so_far, df_new), append(rows_so_far, row_i), add(i_pos, cast(1, int64)))
  }, init, instruments)
  out.3
}
def bootstrap_grad_full_jacobian[m](paths_template: &tensor[m, f32], instruments: List[Instrument]) -> tensor[m, m, f32] = {
  m_len = len(to_list(paths_template))
  insts_len = len(instruments)
  if neq(insts_len, m_len) then cur_nan_jacobian(paths_template) else if cur_all_instruments_valid(instruments) then {
    rows = cur_full_jacobian_rows(instruments, m_len)
    flat = fold(fn (acc: List[f32], row: List[f32]) -> fold(fn (a: List[f32], v: f32) -> append(a, v), acc, row), [], rows)
    reshape(to_tensor(flat), [m_len, m_len])
  } else cur_nan_jacobian(paths_template)
}
type CurveBasis[n] =
  | CurveBasis { times: tensor[n, f32], spreads: tensor[n, f32] }
def curve_basis_from_pillars[n](times: tensor[n, f32], spreads: tensor[n, f32]) -> CurveBasis[n] = CurveBasis { times: times, spreads: spreads }
def basis_spread_at[n](basis: CurveBasis[n], t: f32) -> f32 = {
  match basis with {
    | CurveBasis { times: ts, spreads: ss } => linear_interp_sorted(ts, ss, t)
  }
}
def discount_factor_with_basis[n, m](domestic: YieldCurve[n], basis: CurveBasis[m], t: f32) -> f32 = {
  r_dom = rate_at(domestic, t)
  s = basis_spread_at(basis, t)
  exp(neg(mul(add(r_dom, s), t)))
}
def bootstrap_basis_curve[n, k](domestic: YieldCurve[k], basis_quotes_times: tensor[n, f32], basis_quotes_spreads: tensor[n, f32]) -> CurveBasis[n] = CurveBasis { times: basis_quotes_times, spreads: basis_quotes_spreads }
