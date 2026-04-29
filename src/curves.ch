module Shoals.Curves
import Nautilus.Interpolation (linear_interp_sorted, spline_eval)
export (YieldCurve, yield_curve_from_pillars, rate_at, discount_factor, bootstrap_zero_from_par, spline_rate_at)
type YieldCurve[n] =
  | YieldCurve { times: tensor[n, f32], rates: tensor[n, f32] }
def yield_curve_from_pillars[n](times: tensor[n, f32], rates: tensor[n, f32]) -> YieldCurve[n] = { YieldCurve { times: times, rates: rates } }
def rate_at[n](curve: YieldCurve[n], t: f32) -> f32 = { match curve with {
  | YieldCurve { times: ts, rates: rs } => linear_interp_sorted(ts, rs, t)
} }
def spline_rate_at[n](curve: YieldCurve[n], t: f32) -> f32 = { match curve with {
  | YieldCurve { times: ts, rates: rs } => spline_eval(ts, rs, t)
} }
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
  YieldCurve { times: times, rates: rates_t }
}
