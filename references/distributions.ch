module Shoals.References.Distributions
import Nautilus.Special (erfc, log_gamma)
export (lognormal_pdf_textbook, lognormal_cdf_textbook, student_t_pdf_textbook, bvn_pdf_textbook)
def lognormal_pdf_textbook(x: f32, mu: f32, sigma: f32) -> f32 = {
  if lte(x, cast(0.0, f32)) then cast(0.0, f32) else {
    lx = log(x)
    diff = sub(lx, mu)
    num = neg(div(mul(diff, diff), mul(cast(2.0, f32), mul(sigma, sigma))))
    denom = mul(x, mul(sigma, cast(2.5066282746310002, f32)))
    div(exp(num), denom)
  }
}
def lognormal_cdf_textbook(x: f32, mu: f32, sigma: f32) -> f32 = {
  if lte(x, cast(0.0, f32)) then cast(0.0, f32) else {
    lx = log(x)
    sqrt_2 = cast(1.4142135623730951, f32)
    z = div(sub(lx, mu), mul(sigma, sqrt_2))
    mul(cast(0.5, f32), erfc(neg(z)))
  }
}
def student_t_pdf_textbook(x: f32, nu: f32) -> f32 = {
  half_nu = mul(cast(0.5, f32), nu)
  half_nup1 = mul(cast(0.5, f32), add(nu, cast(1.0, f32)))
  lg_num = log_gamma(half_nup1)
  lg_den = log_gamma(half_nu)
  pi_f = cast(3.141592653589793, f32)
  sqrt_nu_pi = sqrt(mul(nu, pi_f))
  coef = div(exp(sub(lg_num, lg_den)), sqrt_nu_pi)
  base = add(cast(1.0, f32), div(mul(x, x), nu))
  body = exp(mul(neg(half_nup1), log(base)))
  mul(coef, body)
}
def bvn_pdf_textbook(x: f32, y: f32, mu_x: f32, mu_y: f32, sigma_x: f32, sigma_y: f32, rho: f32) -> f32 = {
  two_pi_f = cast(6.283185307179586, f32)
  one_minus_rho2 = sub(cast(1.0, f32), mul(rho, rho))
  norm_const = div(cast(1.0, f32), mul(two_pi_f, mul(sigma_x, mul(sigma_y, sqrt(one_minus_rho2)))))
  zx = div(sub(x, mu_x), sigma_x)
  zy = div(sub(y, mu_y), sigma_y)
  zxzy = mul(zx, zy)
  quad = sub(add(mul(zx, zx), mul(zy, zy)), mul(cast(2.0, f32), mul(rho, zxzy)))
  exponent = neg(div(quad, mul(cast(2.0, f32), one_minus_rho2)))
  mul(norm_const, exp(exponent))
}
