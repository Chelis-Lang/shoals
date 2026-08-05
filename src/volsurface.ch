module Shoals.VolSurface
import Shoals.Pricing (bs_call_scalar)
export (SVI, vs_total_variance, vs_implied_vol, vs_shift_atm, vs_shift_skew, parallel_shift_atm_iv, smile_shift_skew_wing, implied_vol_bisect, implied_vol_from_call, bracket_brackets_root, is_iv_solver_failed, SABR, vs_sabr_implied_vol, vs_sabr_atm_implied_vol, vs_sabr_shift_alpha, vs_sabr_shift_rho, vs_sabr_shift_nu)
type SVI =
  | SVI { a: f32, b: f32, rho: f32, m: f32, sigma: f32 }
type SABR =
  | SABR { alpha: f32, beta: f32, rho: f32, nu: f32 }
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
def implied_vol_bisect(spot: f32, strike: f32, r: f32, t: f32, target: f32, vol_lo: f32, vol_hi: f32, max_iters: int64, tol: f32) -> f32 =
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
def implied_vol_from_call(spot: f32, strike: f32, r: f32, t: f32, target_price: f32) -> f32 = implied_vol_bisect(spot, strike, r, t, target_price, cast(0.0001, f32), cast(5.0, f32), cast(60, int64), cast(1e-6, f32))
def pow_f32(base: f32, expn: f32) -> f32 = exp(mul(expn, log(base)))
def vs_sabr_atm_implied_vol(p: SABR, f: f32, t: f32) -> f32 = {
  one_minus_beta = sub(cast(1.0, f32), p.beta)
  f_pow_1mb = pow_f32(f, one_minus_beta)
  f_pow_2m2b = pow_f32(f, mul(cast(2.0, f32), one_minus_beta))
  leading = div(p.alpha, f_pow_1mb)
  term1 = div(mul(div(mul(one_minus_beta, one_minus_beta), cast(24.0, f32)), mul(p.alpha, p.alpha)), f_pow_2m2b)
  term2 = div(mul(cast(0.25, f32), mul(p.rho, mul(p.beta, mul(p.nu, p.alpha)))), f_pow_1mb)
  term3 = mul(div(sub(cast(2.0, f32), mul(cast(3.0, f32), mul(p.rho, p.rho))), cast(24.0, f32)), mul(p.nu, p.nu))
  correction = mul(add(term1, add(term2, term3)), t)
  mul(leading, add(cast(1.0, f32), correction))
}
def vs_sabr_implied_vol(p: SABR, f: f32, k: f32, t: f32) -> f32 = {
  one_minus_beta = sub(cast(1.0, f32), p.beta)
  fk = mul(f, k)
  fk_pow_1mb = pow_f32(fk, one_minus_beta)
  fk_pow_half1mb = pow_f32(fk, mul(cast(0.5, f32), one_minus_beta))
  log_fk = log(div(f, k))
  log_fk_sq = mul(log_fk, log_fk)
  log_fk_4 = mul(log_fk_sq, log_fk_sq)
  one_minus_beta_sq = mul(one_minus_beta, one_minus_beta)
  one_minus_beta_4 = mul(one_minus_beta_sq, one_minus_beta_sq)
  z = mul(div(p.nu, p.alpha), mul(fk_pow_half1mb, log_fk))
  one_minus_rho = sub(cast(1.0, f32), p.rho)
  inner = sqrt(add(sub(cast(1.0, f32), mul(cast(2.0, f32), mul(p.rho, z))), mul(z, z)))
  x_z = log(div(sub(add(inner, z), p.rho), one_minus_rho))
  num_term1 = div(mul(div(one_minus_beta_sq, cast(24.0, f32)), mul(p.alpha, p.alpha)), fk_pow_1mb)
  num_term2 = div(mul(cast(0.25, f32), mul(p.rho, mul(p.beta, mul(p.nu, p.alpha)))), fk_pow_half1mb)
  num_term3 = mul(div(sub(cast(2.0, f32), mul(cast(3.0, f32), mul(p.rho, p.rho))), cast(24.0, f32)), mul(p.nu, p.nu))
  numerator = mul(p.alpha, add(cast(1.0, f32), mul(add(num_term1, add(num_term2, num_term3)), t)))
  denom_correction = add(cast(1.0, f32), add(mul(div(one_minus_beta_sq, cast(24.0, f32)), log_fk_sq), mul(div(one_minus_beta_4, cast(1920.0, f32)), log_fk_4)))
  denominator = mul(fk_pow_half1mb, denom_correction)
  base_iv = div(numerator, denominator)
  if lt(abs_f32(z), cast(1e-7, f32)) then base_iv else mul(base_iv, div(z, x_z))
}
def vs_sabr_shift_alpha(p: SABR, d: f32) -> SABR = SABR { alpha: add(p.alpha, d), beta: p.beta, rho: p.rho, nu: p.nu }
def vs_sabr_shift_rho(p: SABR, d: f32) -> SABR = SABR { alpha: p.alpha, beta: p.beta, rho: add(p.rho, d), nu: p.nu }
def vs_sabr_shift_nu(p: SABR, d: f32) -> SABR = SABR { alpha: p.alpha, beta: p.beta, rho: p.rho, nu: add(p.nu, d) }
