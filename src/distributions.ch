module Shoals.Distributions
import Nautilus.Distributions (normal_cdf, normal_pdf)
import Nautilus.Special (log_gamma)
export (lognormal_pdf, lognormal_cdf, student_t_pdf, student_t_cdf_approx, bvn_pdf)
def lognormal_pdf(x: f32, mu: f32, sigma: f32) -> f32 = {
  if lte(x, cast(0.0, f32)) then cast(0.0, f32) else {
    lx = log(x)
    div(normal_pdf(lx, mu, sigma), x)
  }
}
def lognormal_cdf(x: f32, mu: f32, sigma: f32) -> f32 = {
  if lte(x, cast(0.0, f32)) then cast(0.0, f32) else {
    lx = log(x)
    normal_cdf(lx, mu, sigma)
  }
}
def student_t_pdf(x: f32, nu: f32) -> f32 = {
  half_nu = mul(cast(0.5, f32), nu)
  half_nup1 = mul(cast(0.5, f32), add(nu, cast(1.0, f32)))
  lg_num = log_gamma(half_nup1)
  lg_den = log_gamma(half_nu)
  gamma_ratio = exp(sub(lg_num, lg_den))
  pi_f = cast(3.141592653589793, f32)
  sqrt_nu_pi = sqrt(mul(nu, pi_f))
  coef = div(gamma_ratio, sqrt_nu_pi)
  x2_over_nu = div(mul(x, x), nu)
  base = add(cast(1.0, f32), x2_over_nu)
  exponent = neg(half_nup1)
  body = exp(mul(exponent, log(base)))
  mul(coef, body)
}
def student_t_cdf_approx(x: f32, nu: f32) -> f32 = {
  four_nu_m1 = sub(mul(cast(4.0, f32), nu), cast(1.0, f32))
  two_over = div(cast(2.0, f32), four_nu_m1)
  scale = sqrt(sub(cast(1.0, f32), two_over))
  z = mul(x, scale)
  normal_cdf(z, cast(0.0, f32), cast(1.0, f32))
}
def bvn_pdf(x: f32, y: f32, mu_x: f32, mu_y: f32, sigma_x: f32, sigma_y: f32, rho: f32) -> f32 = {
  two_pi_f = cast(6.283185307179586, f32)
  one_minus_rho2 = sub(cast(1.0, f32), mul(rho, rho))
  denom = mul(two_pi_f, mul(sigma_x, mul(sigma_y, sqrt(one_minus_rho2))))
  zx = div(sub(x, mu_x), sigma_x)
  zy = div(sub(y, mu_y), sigma_y)
  quad = sub(add(mul(zx, zx), mul(zy, zy)), mul(cast(2.0, f32), mul(rho, mul(zx, zy))))
  exponent = neg(div(quad, mul(cast(2.0, f32), one_minus_rho2)))
  div(exp(exponent), denom)
}
