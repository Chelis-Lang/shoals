module Shoals.VolSurface
import Shoals.Pricing (bs_call_scalar)
export (SVI, vs_total_variance, vs_implied_vol, vs_shift_atm, vs_shift_skew, parallel_shift_atm_iv, smile_shift_skew_wing, implied_vol_bisect, implied_vol_from_call, bracket_brackets_root, is_iv_solver_failed)
type SVI =
  | SVI { a: f32, b: f32, rho: f32, m: f32, sigma: f32 }
def vs_total_variance(p: SVI, k: f32) -> f32 = {
  km = sub(k, p.m)
  sq_term = sqrt(add(mul(km, km), mul(p.sigma, p.sigma)))
  add(p.a, mul(p.b, add(mul(p.rho, km), sq_term)))
}
def vs_implied_vol(p: SVI, k: f32, t: f32) -> f32 = {
  w = vs_total_variance(p, k)
  w_clamped = if lt(w, cast(0.0, f32)) then cast(0.0, f32) else w
  sqrt(div(w_clamped, t))
}
def vs_shift_atm(p: SVI, delta_a: f32) -> SVI = SVI { a: add(p.a, delta_a), b: p.b, rho: p.rho, m: p.m, sigma: p.sigma }
def vs_shift_skew(p: SVI, delta_rho: f32) -> SVI = SVI { a: p.a, b: p.b, rho: add(p.rho, delta_rho), m: p.m, sigma: p.sigma }
def parallel_shift_atm_iv(p: SVI, delta_iv: f32, t: f32) -> SVI = {
  w_now = vs_total_variance(p, cast(0.0, f32))
  w_clamped = if lt(w_now, cast(0.0, f32)) then cast(0.0, f32) else w_now
  iv_now = sqrt(div(w_clamped, t))
  iv_new = add(iv_now, delta_iv)
  w_new = mul(mul(iv_new, iv_new), t)
  vs_shift_atm(p, sub(w_new, w_now))
}
def smile_shift_skew_wing(p: SVI, delta_b: f32) -> SVI = SVI { a: p.a, b: add(p.b, delta_b), rho: p.rho, m: p.m, sigma: p.sigma }
def bs_call_minus_target(spot: f32, strike: f32, r: f32, sigma: f32, t: f32, target: f32) -> f32 = sub(bs_call_scalar(spot, strike, r, sigma, t), target)
def abs_f32(x: f32) -> f32 = if lt(x, cast(0.0, f32)) then neg(x) else x
def bracket_brackets_root(spot: f32, strike: f32, r: f32, t: f32, target: f32, vol_lo: f32, vol_hi: f32) -> bool = {
  flo = bs_call_minus_target(spot, strike, r, vol_lo, t, target)
  fhi = bs_call_minus_target(spot, strike, r, vol_hi, t, target)
  lt(mul(flo, fhi), cast(0.0, f32))
}
def is_iv_solver_failed(iv: f32) -> bool = neq(iv, iv)
def implied_vol_bisect(spot: f32, strike: f32, r: f32, t: f32, target: f32, vol_lo: f32, vol_hi: f32, max_iters: int64, tol: f32) -> f32 = {
  if not(bracket_brackets_root(spot, strike, r, t, target, vol_lo, vol_hi)) then div(cast(0.0, f32), cast(0.0, f32)) else {
    iters = range(cast(0, int64), max_iters)
    init = (vol_lo, vol_hi, cast(0.5, f32))
    out = fold(fn (state: (f32, f32, f32), unused: int64) -> {
      lo = state.0
      hi = state.1
      mid = mul(cast(0.5, f32), add(lo, hi))
      fmid = bs_call_minus_target(spot, strike, r, mid, t, target)
      flo = bs_call_minus_target(spot, strike, r, lo, t, target)
      if lt(abs_f32(fmid), tol) then (mid, mid, mid) else if lt(mul(flo, fmid), cast(0.0, f32)) then (lo, mid, mid) else (mid, hi, mid)
    }, init, iters)
    out.2
  }
}
def implied_vol_from_call(spot: f32, strike: f32, r: f32, t: f32, target_price: f32) -> f32 = implied_vol_bisect(spot, strike, r, t, target_price, cast(0.0001, f32), cast(5.0, f32), cast(60, int64), cast(0.000001, f32))
