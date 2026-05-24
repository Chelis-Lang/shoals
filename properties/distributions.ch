module Shoals.Properties.Distributions
import Shoals.Distributions (lognormal_pdf, lognormal_cdf, student_t_pdf, bvn_pdf)
import Shoals.References.Distributions (lognormal_pdf_textbook, lognormal_cdf_textbook, student_t_pdf_textbook, bvn_pdf_textbook)
def abs_f32(x: f32) -> f32 = if lt(x, cast(0.0, f32)) then neg(x) else x
def lognormal_pdf_matches_textbook(x: f32, mu: f32, sigma: f32) -> bool = {
  opt = lognormal_pdf(x, mu, sigma)
  ref = lognormal_pdf_textbook(x, mu, sigma)
  lt(abs_f32(sub(opt, ref)), cast(0.00001, f32))
}
def lognormal_cdf_matches_textbook(x: f32, mu: f32, sigma: f32) -> bool = {
  opt = lognormal_cdf(x, mu, sigma)
  ref = lognormal_cdf_textbook(x, mu, sigma)
  lt(abs_f32(sub(opt, ref)), cast(0.00001, f32))
}
def student_t_pdf_matches_textbook(x: f32, nu: f32) -> bool = {
  opt = student_t_pdf(x, nu)
  ref = student_t_pdf_textbook(x, nu)
  lt(abs_f32(sub(opt, ref)), cast(0.00001, f32))
}
def bvn_pdf_matches_textbook(x: f32, y: f32, mu_x: f32, mu_y: f32, sigma_x: f32, sigma_y: f32, rho: f32) -> bool = {
  opt = bvn_pdf(x, y, mu_x, mu_y, sigma_x, sigma_y, rho)
  ref = bvn_pdf_textbook(x, y, mu_x, mu_y, sigma_x, sigma_y, rho)
  lt(abs_f32(sub(opt, ref)), cast(0.00001, f32))
}
def lognormal_pdf_nonneg(x: f32, mu: f32, sigma: f32) -> bool = {
  p = lognormal_pdf(x, mu, sigma)
  gte(p, cast(0.0, f32))
}
def student_t_pdf_symmetric_at_zero(nu: f32, dx: f32) -> bool = {
  p_plus = student_t_pdf(dx, nu)
  p_minus = student_t_pdf(neg(dx), nu)
  lt(abs_f32(sub(p_plus, p_minus)), cast(0.000001, f32))
}
