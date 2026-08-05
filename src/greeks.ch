module Shoals.Greeks
import Nautilus.Special (erfc)
import Shoals.Pricing (bs_call_scalar, bs_put_scalar)
export (n_pdf, fd_delta_call, fd_delta_put, fd_gamma_call, fd_vega_call, fd_vega_put, fd_rho_call, fd_rho_put, fd_theta_call, fd_theta_put, fd_vanna_call, fd_volga_call, analytic_delta_call, analytic_delta_put, analytic_vega_call, analytic_gamma_call, pathwise_smooth_call_terminal_delta, lr_digital_call_delta)
def n_pdf(x: f32) -> f32 = {
  half = cast(0.5, f32)
  inv_sqrt_2pi = cast(0.3989422804014327, f32)
  mul(inv_sqrt_2pi, exp(neg(mul(half, mul(x, x)))))
}
def n_cdf(x: f32) -> f32 = {
  inv_sqrt_2 = cast(0.7071067811865475, f32)
  mul(cast(0.5, f32), erfc(neg(mul(x, inv_sqrt_2))))
}
def fd_delta_call(s: f32, k: f32, r: f32, sigma: f32, t: f32, h: f32) -> f32 = {
  up = bs_call_scalar(add(s, h), k, r, sigma, t)
  dn = bs_call_scalar(sub(s, h), k, r, sigma, t)
  div(sub(up, dn), mul(cast(2.0, f32), h))
}
def fd_delta_put(s: f32, k: f32, r: f32, sigma: f32, t: f32, h: f32) -> f32 = {
  up = bs_put_scalar(add(s, h), k, r, sigma, t)
  dn = bs_put_scalar(sub(s, h), k, r, sigma, t)
  div(sub(up, dn), mul(cast(2.0, f32), h))
}
def fd_gamma_call(s: f32, k: f32, r: f32, sigma: f32, t: f32, h: f32) -> f32 = {
  up = bs_call_scalar(add(s, h), k, r, sigma, t)
  mid = bs_call_scalar(s, k, r, sigma, t)
  dn = bs_call_scalar(sub(s, h), k, r, sigma, t)
  div(add(sub(up, mul(cast(2.0, f32), mid)), dn), mul(h, h))
}
def fd_vega_call(s: f32, k: f32, r: f32, sigma: f32, t: f32, h: f32) -> f32 = {
  up = bs_call_scalar(s, k, r, add(sigma, h), t)
  dn = bs_call_scalar(s, k, r, sub(sigma, h), t)
  div(sub(up, dn), mul(cast(2.0, f32), h))
}
def fd_vega_put(s: f32, k: f32, r: f32, sigma: f32, t: f32, h: f32) -> f32 = {
  up = bs_put_scalar(s, k, r, add(sigma, h), t)
  dn = bs_put_scalar(s, k, r, sub(sigma, h), t)
  div(sub(up, dn), mul(cast(2.0, f32), h))
}
def fd_rho_call(s: f32, k: f32, r: f32, sigma: f32, t: f32, h: f32) -> f32 = {
  up = bs_call_scalar(s, k, add(r, h), sigma, t)
  dn = bs_call_scalar(s, k, sub(r, h), sigma, t)
  div(sub(up, dn), mul(cast(2.0, f32), h))
}
def fd_rho_put(s: f32, k: f32, r: f32, sigma: f32, t: f32, h: f32) -> f32 = {
  up = bs_put_scalar(s, k, add(r, h), sigma, t)
  dn = bs_put_scalar(s, k, sub(r, h), sigma, t)
  div(sub(up, dn), mul(cast(2.0, f32), h))
}
def fd_theta_call(s: f32, k: f32, r: f32, sigma: f32, t: f32, h: f32) -> f32 = {
  up = bs_call_scalar(s, k, r, sigma, add(t, h))
  dn = bs_call_scalar(s, k, r, sigma, sub(t, h))
  div(sub(dn, up), mul(cast(2.0, f32), h))
}
def fd_theta_put(s: f32, k: f32, r: f32, sigma: f32, t: f32, h: f32) -> f32 = {
  up = bs_put_scalar(s, k, r, sigma, add(t, h))
  dn = bs_put_scalar(s, k, r, sigma, sub(t, h))
  div(sub(dn, up), mul(cast(2.0, f32), h))
}
def fd_vanna_call(s: f32, k: f32, r: f32, sigma: f32, t: f32, h_s: f32, h_v: f32) -> f32 = {
  d_up = fd_delta_call(s, k, r, add(sigma, h_v), t, h_s)
  d_dn = fd_delta_call(s, k, r, sub(sigma, h_v), t, h_s)
  div(sub(d_up, d_dn), mul(cast(2.0, f32), h_v))
}
def fd_volga_call(s: f32, k: f32, r: f32, sigma: f32, t: f32, h: f32) -> f32 = {
  up = bs_call_scalar(s, k, r, add(sigma, h), t)
  mid = bs_call_scalar(s, k, r, sigma, t)
  dn = bs_call_scalar(s, k, r, sub(sigma, h), t)
  div(add(sub(up, mul(cast(2.0, f32), mid)), dn), mul(h, h))
}
def analytic_d1(s: f32, k: f32, r: f32, sigma: f32, t: f32) -> f32 = {
  log_sk = log(div(s, k))
  drift = mul(add(r, mul(cast(0.5, f32), mul(sigma, sigma))), t)
  div(add(log_sk, drift), mul(sigma, sqrt(t)))
}
def analytic_d2(s: f32, k: f32, r: f32, sigma: f32, t: f32) -> f32 = sub(analytic_d1(s, k, r, sigma, t), mul(sigma, sqrt(t)))
def analytic_delta_call(s: f32, k: f32, r: f32, sigma: f32, t: f32) -> f32 = n_cdf(analytic_d1(s, k, r, sigma, t))
def analytic_delta_put(s: f32, k: f32, r: f32, sigma: f32, t: f32) -> f32 = sub(analytic_delta_call(s, k, r, sigma, t), cast(1.0, f32))
def analytic_vega_call(s: f32, k: f32, r: f32, sigma: f32, t: f32) -> f32 = mul(s, mul(n_pdf(analytic_d1(s, k, r, sigma, t)), sqrt(t)))
def analytic_gamma_call(s: f32, k: f32, r: f32, sigma: f32, t: f32) -> f32 = div(n_pdf(analytic_d1(s, k, r, sigma, t)), mul(s, mul(sigma, sqrt(t))))
def pathwise_smooth_call_terminal_delta(s_terminal: f32, k: f32, df: f32, s0: f32) -> f32 = if gt(s_terminal, k) then mul(df, div(s_terminal, s0)) else cast(0.0, f32)
def lr_digital_call_delta(s_terminal: f32, k: f32, s0: f32, sigma: f32, t: f32, df: f32) -> f32 = {
  log_st_s0 = log(div(s_terminal, s0))
  half_sigma_sq_t = mul(cast(0.5, f32), mul(sigma, mul(sigma, t)))
  z = div(sub(log_st_s0, neg(half_sigma_sq_t)), mul(sigma, sqrt(t)))
  score = div(z, mul(s0, mul(sigma, sqrt(t))))
  indicator = if gt(s_terminal, k) then cast(1.0, f32) else cast(0.0, f32)
  mul(df, mul(indicator, score))
}
