module Shoals.Heston
import Nautilus.Integrate (gauss_legendre_10)
export (heston_charfn, heston_call_carr_madan, heston_call_carr_madan_panels, heston_put_carr_madan_panels, heston_call_lewis_panels, heston_put_lewis_panels, heston_call_lipton_panels, heston_put_lipton_panels)
def heston_pi_const() -> f32 = cast(3.14159265358979, f32)
def heston_half_pi() -> f32 = div(heston_pi_const(), cast(2.0, f32))
def cadd(a: (f32, f32), b: (f32, f32)) -> (f32, f32) = (add(a.0, b.0), add(a.1, b.1))
def csub(a: (f32, f32), b: (f32, f32)) -> (f32, f32) = (sub(a.0, b.0), sub(a.1, b.1))
def cmul(a: (f32, f32), b: (f32, f32)) -> (f32, f32) = (sub(mul(a.0, b.0), mul(a.1, b.1)), add(mul(a.0, b.1), mul(a.1, b.0)))
def cscale(z: (f32, f32), s: f32) -> (f32, f32) = (mul(z.0, s), mul(z.1, s))
def cdiv(a: (f32, f32), b: (f32, f32)) -> (f32, f32) = {
  denom = add(mul(b.0, b.0), mul(b.1, b.1))
  re = div(add(mul(a.0, b.0), mul(a.1, b.1)), denom)
  im = div(sub(mul(a.1, b.0), mul(a.0, b.1)), denom)
  (re, im)
}
def cexp(z: (f32, f32)) -> (f32, f32) = {
  r_factor = exp(z.0)
  (mul(r_factor, cos(z.1)), mul(r_factor, sin(z.1)))
}
def safe_atan2(y: f32, x: f32) -> f32 =
  if eq(x, cast(0.0, f32)) then if gt(y, cast(0.0, f32)) then heston_half_pi() else if lt(y, cast(0.0, f32)) then neg(heston_half_pi()) else cast(0.0, f32) else {
    a = atan(div(y, x))
    if gt(x, cast(0.0, f32)) then a else if gte(y, cast(0.0, f32)) then add(a, heston_pi_const()) else sub(a, heston_pi_const())
  }
def clog(z: (f32, f32)) -> (f32, f32) = {
  r2 = add(mul(z.0, z.0), mul(z.1, z.1))
  (mul(cast(0.5, f32), log(r2)), safe_atan2(z.1, z.0))
}
def csqrt(z: (f32, f32)) -> (f32, f32) = {
  r_mag = sqrt(add(mul(z.0, z.0), mul(z.1, z.1)))
  re = sqrt(mul(cast(0.5, f32), add(r_mag, z.0)))
  im_abs = sqrt(mul(cast(0.5, f32), sub(r_mag, z.0)))
  im = if gte(z.1, cast(0.0, f32)) then im_abs else neg(im_abs)
  (re, im)
}
def heston_charfn(u: (f32, f32), s0: f32, r: f32, v0: f32, kappa: f32, theta: f32, sigma: f32, rho: f32, t: f32) -> (f32, f32) = {
  iu = (neg(u.1), u.0)
  rho_sig_iu = cscale(iu, mul(rho, sigma))
  a_term = csub((kappa, cast(0.0, f32)), rho_sig_iu)
  u_sq = cmul(u, u)
  sig2_factor = cscale(cadd(iu, u_sq), mul(sigma, sigma))
  d_sq = cadd(cmul(a_term, a_term), sig2_factor)
  d_term = csqrt(d_sq)
  num_a_minus_d = csub(a_term, d_term)
  den_a_plus_d = cadd(a_term, d_term)
  g_term = cdiv(num_a_minus_d, den_a_plus_d)
  exp_neg_dt = cexp(cscale(d_term, neg(t)))
  one = (cast(1.0, f32), cast(0.0, f32))
  one_minus_g_edt = csub(one, cmul(g_term, exp_neg_dt))
  one_minus_edt = csub(one, exp_neg_dt)
  d_num_part = cmul(num_a_minus_d, one_minus_edt)
  d_capital = cscale(cdiv(d_num_part, one_minus_g_edt), div(cast(1.0, f32), mul(sigma, sigma)))
  iurt = cscale(iu, mul(r, t))
  a_d_t = cscale(num_a_minus_d, t)
  log_ratio = clog(cdiv(one_minus_g_edt, csub(one, g_term)))
  log_term = cscale(log_ratio, cast(2.0, f32))
  c_body = csub(a_d_t, log_term)
  c_scaled = cscale(c_body, div(mul(kappa, theta), mul(sigma, sigma)))
  c_capital = cadd(iurt, c_scaled)
  d_v0 = cscale(d_capital, v0)
  iu_log_s0 = cscale(iu, log(s0))
  arg = cadd(c_capital, cadd(d_v0, iu_log_s0))
  cexp(arg)
}
def heston_call_carr_madan(s0: f32, k: f32, t: f32, r: f32, v0: f32, kappa: f32, theta: f32, sigma: f32, rho: f32, alpha: f32, u_max: f32) -> f32 = {
  log_k = log(k)
  alpha_plus_one = add(alpha, cast(1.0, f32))
  two_alpha_plus_one = add(mul(cast(2.0, f32), alpha), cast(1.0, f32))
  alpha2_plus_alpha = add(mul(alpha, alpha), alpha)
  exp_neg_rt = exp(neg(mul(r, t)))
  integrand = fn (u: f32) -> {
    u_complex = (u, neg(alpha_plus_one))
    phi_val = heston_charfn(u_complex, s0, r, v0, kappa, theta, sigma, rho, t)
    denom_complex = (sub(alpha2_plus_alpha, mul(u, u)), mul(two_alpha_plus_one, u))
    psi = cscale(cdiv(phi_val, denom_complex), exp_neg_rt)
    arg_osc = neg(mul(u, log_k))
    exp_term = (cos(arg_osc), sin(arg_osc))
    integrand_complex = cmul(exp_term, psi)
    integrand_complex.0
  }
  integral_value = gauss_legendre_10(integrand, cast(0.0, f32), u_max)
  exp_neg_alpha_lnk = exp(neg(mul(alpha, log_k)))
  raw_price = div(mul(exp_neg_alpha_lnk, integral_value), heston_pi_const())
  if gt(raw_price, cast(0.0, f32)) then raw_price else cast(0.0, f32)
}
def gauss_legendre_panels(f: f32 -> f32, a: f32, b: f32, n_panels: i64) -> f32 = {
  panel_width = div(sub(b, a), cast(n_panels, f32))
  idxs = range(cast(0, i64), n_panels)
  parts = map(fn (i: i64) -> {
    sub_a = add(a, mul(cast(i, f32), panel_width))
    sub_b = add(sub_a, panel_width)
    gauss_legendre_10(f, sub_a, sub_b)
  }, idxs)
  fold(fn (acc: f32, x: f32) -> add(acc, x), cast(0.0, f32), parts)
}
def heston_call_carr_madan_panels(s0: f32, k: f32, t: f32, r: f32, v0: f32, kappa: f32, theta: f32, sigma: f32, rho: f32, alpha: f32, u_max: f32, n_panels: i64) -> f32 = {
  log_k = log(k)
  alpha_plus_one = add(alpha, cast(1.0, f32))
  two_alpha_plus_one = add(mul(cast(2.0, f32), alpha), cast(1.0, f32))
  alpha2_plus_alpha = add(mul(alpha, alpha), alpha)
  exp_neg_rt = exp(neg(mul(r, t)))
  integrand = fn (u: f32) -> {
    u_complex = (u, neg(alpha_plus_one))
    phi_val = heston_charfn(u_complex, s0, r, v0, kappa, theta, sigma, rho, t)
    denom_complex = (sub(alpha2_plus_alpha, mul(u, u)), mul(two_alpha_plus_one, u))
    psi = cscale(cdiv(phi_val, denom_complex), exp_neg_rt)
    arg_osc = neg(mul(u, log_k))
    exp_term = (cos(arg_osc), sin(arg_osc))
    integrand_complex = cmul(exp_term, psi)
    integrand_complex.0
  }
  integral_value = gauss_legendre_panels(integrand, cast(0.0, f32), u_max, n_panels)
  exp_neg_alpha_lnk = exp(neg(mul(alpha, log_k)))
  raw_price = div(mul(exp_neg_alpha_lnk, integral_value), heston_pi_const())
  if gt(raw_price, cast(0.0, f32)) then raw_price else cast(0.0, f32)
}
def heston_put_carr_madan_panels(s0: f32, k: f32, t: f32, r: f32, v0: f32, kappa: f32, theta: f32, sigma: f32, rho: f32, alpha: f32, u_max: f32, n_panels: i64) -> f32 = {
  call_price = heston_call_carr_madan_panels(s0, k, t, r, v0, kappa, theta, sigma, rho, alpha, u_max, n_panels)
  exp_neg_rt = exp(neg(mul(r, t)))
  raw_put = sub(add(call_price, mul(k, exp_neg_rt)), s0)
  if gt(raw_put, cast(0.0, f32)) then raw_put else cast(0.0, f32)
}
def heston_call_lewis_panels(s0: f32, k: f32, t: f32, r: f32, v0: f32, kappa: f32, theta: f32, sigma: f32, rho: f32, u_max: f32, n_panels: i64) -> f32 = {
  exp_neg_rt = exp(neg(mul(r, t)))
  forward = div(s0, exp_neg_rt)
  log_k = log(k)
  sqrt_forward = sqrt(forward)
  quarter = cast(0.25, f32)
  integrand = fn (u: f32) -> {
    u_complex = (u, cast(-0.5, f32))
    phi_val = heston_charfn(u_complex, s0, r, v0, kappa, theta, sigma, rho, t)
    arg_osc = neg(mul(u, log_k))
    exp_term = (cos(arg_osc), sin(arg_osc))
    prod = cmul(exp_term, phi_val)
    denom = add(mul(u, u), quarter)
    div(prod.0, denom)
  }
  integral_value = gauss_legendre_panels(integrand, cast(0.0, f32), u_max, n_panels)
  correction = div(mul(mul(k, exp_neg_rt), integral_value), mul(heston_pi_const(), sqrt_forward))
  raw_price = sub(s0, correction)
  if gt(raw_price, cast(0.0, f32)) then raw_price else cast(0.0, f32)
}
def heston_put_lewis_panels(s0: f32, k: f32, t: f32, r: f32, v0: f32, kappa: f32, theta: f32, sigma: f32, rho: f32, u_max: f32, n_panels: i64) -> f32 = {
  call_price = heston_call_lewis_panels(s0, k, t, r, v0, kappa, theta, sigma, rho, u_max, n_panels)
  exp_neg_rt = exp(neg(mul(r, t)))
  raw_put = sub(add(call_price, mul(k, exp_neg_rt)), s0)
  if gt(raw_put, cast(0.0, f32)) then raw_put else cast(0.0, f32)
}
def heston_lipton_pj(s0: f32, k: f32, t: f32, r: f32, v0: f32, kappa: f32, theta: f32, sigma: f32, rho: f32, u_max: f32, n_panels: i64, j: i64) -> f32 = {
  log_k = log(k)
  exp_neg_rt = exp(neg(mul(r, t)))
  forward = div(s0, exp_neg_rt)
  integrand = fn (u: f32) -> {
    u_complex = (u, cast(0.0, f32))
    phi_val = heston_charfn(u_complex, s0, r, v0, kappa, theta, sigma, rho, t)
    f_val = if eq(j, cast(1, i64)) then {
      u_shifted = (u, cast(-1.0, f32))
      phi_shifted = heston_charfn(u_shifted, s0, r, v0, kappa, theta, sigma, rho, t)
      cscale(phi_shifted, div(cast(1.0, f32), forward))
    } else phi_val
    arg_osc = neg(mul(u, log_k))
    exp_term = (cos(arg_osc), sin(arg_osc))
    prod = cmul(exp_term, f_val)
    div(prod.1, u)
  }
  integral_value = gauss_legendre_panels(integrand, cast(0.0, f32), u_max, n_panels)
  add(cast(0.5, f32), div(integral_value, heston_pi_const()))
}
def heston_call_lipton_panels(s0: f32, k: f32, t: f32, r: f32, v0: f32, kappa: f32, theta: f32, sigma: f32, rho: f32, u_max: f32, n_panels: i64) -> f32 = {
  exp_neg_rt = exp(neg(mul(r, t)))
  p1 = heston_lipton_pj(s0, k, t, r, v0, kappa, theta, sigma, rho, u_max, n_panels, cast(1, i64))
  p2 = heston_lipton_pj(s0, k, t, r, v0, kappa, theta, sigma, rho, u_max, n_panels, cast(2, i64))
  raw_price = sub(mul(s0, p1), mul(mul(k, exp_neg_rt), p2))
  if gt(raw_price, cast(0.0, f32)) then raw_price else cast(0.0, f32)
}
def heston_put_lipton_panels(s0: f32, k: f32, t: f32, r: f32, v0: f32, kappa: f32, theta: f32, sigma: f32, rho: f32, u_max: f32, n_panels: i64) -> f32 = {
  call_price = heston_call_lipton_panels(s0, k, t, r, v0, kappa, theta, sigma, rho, u_max, n_panels)
  exp_neg_rt = exp(neg(mul(r, t)))
  raw_put = sub(add(call_price, mul(k, exp_neg_rt)), s0)
  if gt(raw_put, cast(0.0, f32)) then raw_put else cast(0.0, f32)
}
