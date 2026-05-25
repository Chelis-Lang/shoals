module Shoals.Properties.VolSurface
import Shoals.Pricing (bs_call_scalar)
import Shoals.VolSurface (SVI, vs_total_variance, vs_implied_vol, implied_vol_from_call, SABR, vs_sabr_atm_implied_vol)
import Shoals.References.Sabr (sabr_atm_iv_textbook)
def abs_f32(x: f32) -> f32 = if lt(x, cast(0.0, f32)) then neg(x) else x
def vs_total_variance_nonneg_for_atm(p: SVI) -> bool = gte(vs_total_variance(p, cast(0.0, f32)), cast(0.0, f32))
def vs_implied_vol_matches_sqrt_variance(p: SVI, k: f32, t: f32) -> bool = {
  iv = vs_implied_vol(p, k, t)
  w = vs_total_variance(p, k)
  w_clamped = if lt(w, cast(0.0, f32)) then cast(0.0, f32) else w
  expected = sqrt(div(w_clamped, t))
  lt(abs_f32(sub(iv, expected)), cast(0.000001, f32))
}
def implied_vol_round_trip(spot: f32, strike: f32, r: f32, t: f32, sigma_true: f32) -> bool = {
  price = bs_call_scalar(spot, strike, r, sigma_true, t)
  iv = implied_vol_from_call(spot, strike, r, t, price)
  lt(abs_f32(sub(iv, sigma_true)), cast(0.001, f32))
}
def vs_sabr_atm_matches_textbook(alpha: f32, beta: f32, rho: f32, nu: f32, f: f32, t: f32) -> bool = {
  p = SABR { alpha: alpha, beta: beta, rho: rho, nu: nu }
  module_val = vs_sabr_atm_implied_vol(p, f, t)
  ref_val = sabr_atm_iv_textbook(alpha, beta, rho, nu, f, t)
  lt(abs_f32(sub(module_val, ref_val)), cast(0.000001, f32))
}
