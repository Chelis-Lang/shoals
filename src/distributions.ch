module Shoals.Distributions
import Nautilus.Distributions (normal_cdf, normal_pdf, student_t_cdf, gamma_pdf, gamma_cdf, gamma_inv_cdf, gamma_sample, beta_pdf, beta_cdf, chi_squared_pdf, chi_squared_cdf, chi_squared_inv_cdf, chi_squared_sample, exponential_pdf, exponential_cdf, exponential_inv_cdf, exponential_sample, uniform_pdf, uniform_cdf, uniform_inv_cdf, uniform_sample, poisson_pmf, poisson_cdf, normal_sample)
import Nautilus.Special (log_gamma)
import Nautilus.LinAlg (cholesky_n, matvec)
export (lognormal_pdf, lognormal_cdf, student_t_pdf, student_t_cdf_approx, student_t_cdf_exact, bvn_pdf, gamma_pdf_s, gamma_cdf_s, gamma_inv_cdf_s, gamma_sample_s, beta_pdf_s, beta_cdf_s, chi_squared_pdf_s, chi_squared_cdf_s, chi_squared_inv_cdf_s, chi_squared_sample_s, exponential_pdf_s, exponential_cdf_s, exponential_inv_cdf_s, exponential_sample_s, uniform_pdf_s, uniform_cdf_s, uniform_inv_cdf_s, uniform_sample_s, poisson_pmf_s, poisson_cdf_s, dist_mvn_factor, dist_mvn_sample_one)
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
def student_t_cdf_exact(x: f32, nu: f32) -> f32 = student_t_cdf(x, nu)
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
def gamma_pdf_s(x: f32, shape: f32, scale: f32) -> f32 = gamma_pdf(x, shape, scale)
def gamma_cdf_s(x: f32, shape: f32, scale: f32) -> f32 = gamma_cdf(x, shape, scale)
def gamma_inv_cdf_s(q: f32, shape: f32, scale: f32) -> f32 = gamma_inv_cdf(q, shape, scale)
def gamma_sample_s[n](template: tensor[n, f32], shape: f32, scale: f32) -> tensor[n, f32] ! { Random } = gamma_sample(template, shape, scale)
def beta_pdf_s(x: f32, a: f32, b: f32) -> f32 = beta_pdf(x, a, b)
def beta_cdf_s(x: f32, a: f32, b: f32) -> f32 = beta_cdf(x, a, b)
def chi_squared_pdf_s(x: f32, df: f32) -> f32 = chi_squared_pdf(x, df)
def chi_squared_cdf_s(x: f32, df: f32) -> f32 = chi_squared_cdf(x, df)
def chi_squared_inv_cdf_s(q: f32, df: f32) -> f32 = chi_squared_inv_cdf(q, df)
def chi_squared_sample_s[n](template: tensor[n, f32], df: f32) -> tensor[n, f32] ! { Random } = chi_squared_sample(template, df)
def exponential_pdf_s(x: f32, rate: f32) -> f32 = exponential_pdf(x, rate)
def exponential_cdf_s(x: f32, rate: f32) -> f32 = exponential_cdf(x, rate)
def exponential_inv_cdf_s(q: f32, rate: f32) -> f32 = exponential_inv_cdf(q, rate)
def exponential_sample_s[n](template: tensor[n, f32], rate: f32) -> tensor[n, f32] ! { Random } = exponential_sample(template, rate)
def uniform_pdf_s(x: f32, lo: f32, hi: f32) -> f32 = uniform_pdf(x, lo, hi)
def uniform_cdf_s(x: f32, lo: f32, hi: f32) -> f32 = uniform_cdf(x, lo, hi)
def uniform_inv_cdf_s(q: f32, lo: f32, hi: f32) -> f32 = uniform_inv_cdf(q, lo, hi)
def uniform_sample_s[n](template: tensor[n, f32], lo: f32, hi: f32) -> tensor[n, f32] ! { Random } = uniform_sample(template, lo, hi)
def poisson_pmf_s(k: f32, lambda: f32) -> f32 = poisson_pmf(k, lambda)
def poisson_cdf_s(k: f32, lambda: f32) -> f32 = poisson_cdf(k, lambda)
def dist_mvn_factor[d](sigma: &tensor[d, d, f32]) -> tensor[d, d, f32] = cholesky_n(sigma)
def dist_mvn_sample_one[d](template: tensor[d, f32], mu: tensor[d, f32], sigma_lower: tensor[d, d, f32]) -> tensor[d, f32] ! { Random } = {
  z = normal_sample(template, cast(0.0, f32), cast(1.0, f32))
  add(matvec(sigma_lower, z), mu)
}
