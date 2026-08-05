module Shoals.References.BlackScholes
import Nautilus.Special (erfc)
export (call_textbook, put_textbook, delta_call_textbook, delta_put_textbook, gamma_textbook, vega_textbook, theta_call_textbook, rho_call_textbook)
def n_cdf(x: f32) -> f32 = {
  inv_sqrt_2 = cast(0.7071067811865475, f32)
  mul(cast(0.5, f32), erfc(neg(mul(x, inv_sqrt_2))))
}
def d1(s: f32, k: f32, r: f32, sigma: f32, t: f32) -> f32 = {
  num = add(log(div(s, k)), mul(add(r, mul(cast(0.5, f32), mul(sigma, sigma))), t))
  den = mul(sigma, sqrt(t))
  div(num, den)
}
def d2(s: f32, k: f32, r: f32, sigma: f32, t: f32) -> f32 = sub(d1(s, k, r, sigma, t), mul(sigma, sqrt(t)))
def n_pdf_std(x: f32) -> f32 = div(exp(neg(mul(cast(0.5, f32), mul(x, x)))), cast(2.5066282746310002, f32))
def call_textbook(s: f32, k: f32, r: f32, sigma: f32, t: f32) -> f32 = {
  d1_v = d1(s, k, r, sigma, t)
  d2_v = d2(s, k, r, sigma, t)
  nd1 = n_cdf(d1_v)
  nd2 = n_cdf(d2_v)
  sub(mul(s, nd1), mul(k, mul(exp(neg(mul(r, t))), nd2)))
}
def put_textbook(s: f32, k: f32, r: f32, sigma: f32, t: f32) -> f32 = {
  d1_v = d1(s, k, r, sigma, t)
  d2_v = d2(s, k, r, sigma, t)
  n_neg_d1 = n_cdf(neg(d1_v))
  n_neg_d2 = n_cdf(neg(d2_v))
  sub(mul(k, mul(exp(neg(mul(r, t))), n_neg_d2)), mul(s, n_neg_d1))
}
def delta_call_textbook(s: f32, k: f32, r: f32, sigma: f32, t: f32) -> f32 = n_cdf(d1(s, k, r, sigma, t))
def delta_put_textbook(s: f32, k: f32, r: f32, sigma: f32, t: f32) -> f32 = sub(n_cdf(d1(s, k, r, sigma, t)), cast(1.0, f32))
def gamma_textbook(s: f32, k: f32, r: f32, sigma: f32, t: f32) -> f32 = {
  d1_v = d1(s, k, r, sigma, t)
  div(n_pdf_std(d1_v), mul(s, mul(sigma, sqrt(t))))
}
def vega_textbook(s: f32, k: f32, r: f32, sigma: f32, t: f32) -> f32 = {
  d1_v = d1(s, k, r, sigma, t)
  mul(s, mul(n_pdf_std(d1_v), sqrt(t)))
}
def theta_call_textbook(s: f32, k: f32, r: f32, sigma: f32, t: f32) -> f32 = {
  d1_v = d1(s, k, r, sigma, t)
  d2_v = d2(s, k, r, sigma, t)
  term1 = neg(div(mul(mul(s, n_pdf_std(d1_v)), sigma), mul(cast(2.0, f32), sqrt(t))))
  nd2 = n_cdf(d2_v)
  term2 = neg(mul(r, mul(k, mul(exp(neg(mul(r, t))), nd2))))
  add(term1, term2)
}
def rho_call_textbook(s: f32, k: f32, r: f32, sigma: f32, t: f32) -> f32 = {
  d2_v = d2(s, k, r, sigma, t)
  nd2 = n_cdf(d2_v)
  mul(k, mul(t, mul(exp(neg(mul(r, t))), nd2)))
}
