module Shoals.Curves
import Nautilus.Interpolation (linear_interp_sorted, spline_eval)
export (CurveKind, YieldCurve, yield_curve_from_pillars, yield_curve_tagged, curve_kind, ois, ibor, sofr, sonia, estr, custom_curve, rate_at, spline_rate_at, log_linear_rate_at, nss_rate, discount_factor, bootstrap_zero_from_par, parallel_shift, key_rate_shift, twist, butterfly, scale_rates)
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
