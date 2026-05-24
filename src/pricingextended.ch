module Shoals.PricingExtended
import Nautilus.Special (erfc, erf)
export (n_cdf_ext, n_pdf_ext, bachelier_call, bachelier_put, black_call, black_put, garman_kohlhagen_call, garman_kohlhagen_put, margrabe_exchange_call)
def n_cdf_ext(x: f32) -> f32 = {
  inv_sqrt_2 = cast(0.7071067811865475, f32)
  mul(cast(0.5, f32), erfc(neg(mul(x, inv_sqrt_2))))
}
def n_pdf_ext(x: f32) -> f32 = {
  half = cast(0.5, f32)
  inv_sqrt_2pi = cast(0.3989422804014327, f32)
  mul(inv_sqrt_2pi, exp(neg(mul(half, mul(x, x)))))
}
def bachelier_call(f: f32, k: f32, sigma: f32, t: f32, df: f32) -> f32 = {
  sqrt_t = sqrt(t)
  sig_sqrt_t = mul(sigma, sqrt_t)
  d = div(sub(f, k), sig_sqrt_t)
  intrinsic = mul(sub(f, k), n_cdf_ext(d))
  vol_term = mul(sig_sqrt_t, n_pdf_ext(d))
  mul(df, add(intrinsic, vol_term))
}
def bachelier_put(f: f32, k: f32, sigma: f32, t: f32, df: f32) -> f32 = {
  sqrt_t = sqrt(t)
  sig_sqrt_t = mul(sigma, sqrt_t)
  d = div(sub(f, k), sig_sqrt_t)
  intrinsic = mul(sub(k, f), n_cdf_ext(neg(d)))
  vol_term = mul(sig_sqrt_t, n_pdf_ext(d))
  mul(df, add(intrinsic, vol_term))
}
def black_call(f: f32, k: f32, sigma: f32, t: f32, df: f32) -> f32 = {
  sqrt_t = sqrt(t)
  sig_sqrt_t = mul(sigma, sqrt_t)
  log_fk = log(div(f, k))
  sigma_sq_half = mul(cast(0.5, f32), mul(sigma, sigma))
  d1 = div(add(log_fk, mul(sigma_sq_half, t)), sig_sqrt_t)
  d2 = sub(d1, sig_sqrt_t)
  intrinsic = mul(f, n_cdf_ext(d1))
  strike_term = mul(k, n_cdf_ext(d2))
  mul(df, sub(intrinsic, strike_term))
}
def black_put(f: f32, k: f32, sigma: f32, t: f32, df: f32) -> f32 = {
  sqrt_t = sqrt(t)
  sig_sqrt_t = mul(sigma, sqrt_t)
  log_fk = log(div(f, k))
  sigma_sq_half = mul(cast(0.5, f32), mul(sigma, sigma))
  d1 = div(add(log_fk, mul(sigma_sq_half, t)), sig_sqrt_t)
  d2 = sub(d1, sig_sqrt_t)
  strike_term = mul(k, n_cdf_ext(neg(d2)))
  f_term = mul(f, n_cdf_ext(neg(d1)))
  mul(df, sub(strike_term, f_term))
}
def garman_kohlhagen_call(s: f32, k: f32, r_d: f32, r_f: f32, sigma: f32, t: f32) -> f32 = {
  sqrt_t = sqrt(t)
  sig_sqrt_t = mul(sigma, sqrt_t)
  log_sk = log(div(s, k))
  drift = mul(add(sub(r_d, r_f), mul(cast(0.5, f32), mul(sigma, sigma))), t)
  d1 = div(add(log_sk, drift), sig_sqrt_t)
  d2 = sub(d1, sig_sqrt_t)
  disc_f = exp(neg(mul(r_f, t)))
  disc_d = exp(neg(mul(r_d, t)))
  sub(mul(s, mul(disc_f, n_cdf_ext(d1))), mul(k, mul(disc_d, n_cdf_ext(d2))))
}
def garman_kohlhagen_put(s: f32, k: f32, r_d: f32, r_f: f32, sigma: f32, t: f32) -> f32 = {
  sqrt_t = sqrt(t)
  sig_sqrt_t = mul(sigma, sqrt_t)
  log_sk = log(div(s, k))
  drift = mul(add(sub(r_d, r_f), mul(cast(0.5, f32), mul(sigma, sigma))), t)
  d1 = div(add(log_sk, drift), sig_sqrt_t)
  d2 = sub(d1, sig_sqrt_t)
  disc_f = exp(neg(mul(r_f, t)))
  disc_d = exp(neg(mul(r_d, t)))
  sub(mul(k, mul(disc_d, n_cdf_ext(neg(d2)))), mul(s, mul(disc_f, n_cdf_ext(neg(d1)))))
}
def margrabe_exchange_call(s1: f32, s2: f32, sigma1: f32, sigma2: f32, rho: f32, t: f32) -> f32 = {
  variance = sub(add(mul(sigma1, sigma1), mul(sigma2, sigma2)), mul(cast(2.0, f32), mul(rho, mul(sigma1, sigma2))))
  if lt(variance, cast(0.0000000001, f32)) then { if gt(sub(s1, s2), cast(0.0, f32)) then sub(s1, s2) else cast(0.0, f32) } else margrabe_exchange_call_nondegenerate(s1, s2, variance, t)
}
def margrabe_exchange_call_nondegenerate(s1: f32, s2: f32, variance: f32, t: f32) -> f32 = {
  sigma_eff = sqrt(variance)
  sqrt_t = sqrt(t)
  sig_sqrt_t = mul(sigma_eff, sqrt_t)
  log_s1s2 = log(div(s1, s2))
  half_var_t = mul(cast(0.5, f32), mul(variance, t))
  d1 = div(add(log_s1s2, half_var_t), sig_sqrt_t)
  d2 = sub(d1, sig_sqrt_t)
  sub(mul(s1, n_cdf_ext(d1)), mul(s2, n_cdf_ext(d2)))
}
