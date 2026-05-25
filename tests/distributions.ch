module Shoals.Tests.Distributions
import Std.Test (assert_close)
import Shoals.Distributions (lognormal_pdf, lognormal_cdf, student_t_pdf, student_t_cdf_exact, student_t_cdf_approx, bvn_pdf, gamma_pdf_s, gamma_cdf_s, gamma_inv_cdf_s, beta_pdf_s, beta_cdf_s, chi_squared_pdf_s, chi_squared_cdf_s, exponential_cdf_s, exponential_inv_cdf_s, uniform_cdf_s, dist_mvn_factor, dist_mvn_sample_one)
import Nautilus.LinAlg (matvec)
import Shoals.Properties.Distributions (lognormal_pdf_matches_textbook, student_t_pdf_symmetric_at_zero)
def to01(b: bool) -> f32 = if b then cast(1.0, f32) else cast(0.0, f32)
def test_lognormal_pdf_known_value() -> unit ! { Test } = {
  p = lognormal_pdf(cast(1.0, f32), cast(0.0, f32), cast(1.0, f32))
  assert_close(p, cast(0.398942, f32), cast(0.0001, f32), "lognormal_pdf(1,0,1) == phi(0) ~ 0.398942")
}
def test_lognormal_cdf_at_one() -> unit ! { Test } = {
  c = lognormal_cdf(cast(1.0, f32), cast(0.0, f32), cast(1.0, f32))
  assert_close(c, cast(0.5, f32), cast(0.0001, f32), "lognormal_cdf(1,0,1) == 0.5")
}
def test_student_t_pdf_at_zero_nu5() -> unit ! { Test } = {
  p = student_t_pdf(cast(0.0, f32), cast(5.0, f32))
  assert_close(p, cast(0.379607, f32), cast(0.0001, f32), "student_t_pdf(0, nu=5) ~ 0.379607")
}
def test_bvn_pdf_at_origin_iid() -> unit ! { Test } = {
  p = bvn_pdf(cast(0.0, f32), cast(0.0, f32), cast(0.0, f32), cast(0.0, f32), cast(1.0, f32), cast(1.0, f32), cast(0.0, f32))
  assert_close(p, cast(0.159155, f32), cast(0.0001, f32), "bvn_pdf at origin iid == 1/(2*pi) ~ 0.159155")
}
def test_lognormal_property_round_trip() -> unit ! { Test } = {
  ok = lognormal_pdf_matches_textbook(cast(2.0, f32), cast(0.5, f32), cast(0.3, f32))
  assert_close(to01(ok), cast(1.0, f32), cast(0.001, f32), "lognormal_pdf matches textbook at x=2,mu=0.5,sigma=0.3")
}
def test_student_t_property_symmetric() -> unit ! { Test } = {
  ok = student_t_pdf_symmetric_at_zero(cast(5.0, f32), cast(1.0, f32))
  assert_close(to01(ok), cast(1.0, f32), cast(0.001, f32), "student_t_pdf(dx,5)==student_t_pdf(-dx,5)")
}
def test_student_t_cdf_exact_nu5_x2() -> unit ! { Test } = {
  c = student_t_cdf_exact(cast(2.0, f32), cast(5.0, f32))
  assert_close(c, cast(0.949038, f32), cast(0.0001, f32), "exact t-cdf(2,5) = 0.949038 (was 0.9707 under Fisher-Cornish approx)")
}
def test_student_t_cdf_exact_better_than_approx() -> unit ! { Test } = {
  exact = student_t_cdf_exact(cast(2.0, f32), cast(5.0, f32))
  approx = student_t_cdf_approx(cast(2.0, f32), cast(5.0, f32))
  exact_err = sub(exact, cast(0.949038, f32))
  approx_err = sub(approx, cast(0.949038, f32))
  abs_exact = if lt(exact_err, cast(0.0, f32)) then neg(exact_err) else exact_err
  abs_approx = if lt(approx_err, cast(0.0, f32)) then neg(approx_err) else approx_err
  assert_close(to01(lt(abs_exact, abs_approx)), cast(1.0, f32), cast(0.001, f32), "exact t-cdf strictly closer to reference than approx")
}
def test_gamma_pdf_wrapper() -> unit ! { Test } = {
  v = gamma_pdf_s(cast(1.0, f32), cast(2.0, f32), cast(1.0, f32))
  assert_close(v, cast(0.367879, f32), cast(0.001, f32), "gamma_pdf(1, shape=2, scale=1) = 1/e")
}
def test_gamma_cdf_at_zero() -> unit ! { Test } = {
  v = gamma_cdf_s(cast(0.0, f32), cast(2.0, f32), cast(1.0, f32))
  assert_close(v, cast(0.0, f32), cast(0.001, f32), "gamma_cdf(0) = 0")
}
def test_exponential_cdf_inv_round_trip() -> unit ! { Test } = {
  q = cast(0.7, f32)
  rate = cast(1.5, f32)
  x = exponential_inv_cdf_s(q, rate)
  c = exponential_cdf_s(x, rate)
  assert_close(c, q, cast(0.001, f32), "exponential cdf-inv round-trip")
}
def test_uniform_cdf_midpoint() -> unit ! { Test } = {
  v = uniform_cdf_s(cast(0.5, f32), cast(0.0, f32), cast(1.0, f32))
  assert_close(v, cast(0.5, f32), cast(0.001, f32), "uniform_cdf(0.5, 0, 1) = 0.5")
}
def test_chi_squared_cdf_at_zero() -> unit ! { Test } = {
  v = chi_squared_cdf_s(cast(0.0, f32), cast(3.0, f32))
  assert_close(v, cast(0.0, f32), cast(0.001, f32), "chi-squared cdf(0) = 0")
}
def test_beta_pdf_uniform_when_a_b_1() -> unit ! { Test } = {
  v = beta_pdf_s(cast(0.5, f32), cast(1.0, f32), cast(1.0, f32))
  assert_close(v, cast(1.0, f32), cast(0.001, f32), "beta(1,1) is uniform; pdf = 1 everywhere on (0,1)")
}
def test_mvn_factor_2x2_identity() -> unit ! { Test } = {
  sigma = to_tensor([cast(1.0, f32), cast(0.0, f32), cast(0.0, f32), cast(1.0, f32)])
  s2 = reshape(sigma, [cast(2, int64), cast(2, int64)])
  lower = dist_mvn_factor(s2)
  diag00 = index(to_list(reshape(copy(lower), [cast(4, int64)])), cast(0, int64))
  diag11 = index(to_list(reshape(copy(lower), [cast(4, int64)])), cast(3, int64))
  _ = assert_close(diag00, cast(1.0, f32), cast(0.0001, f32), "I cholesky [0,0] = 1")
  assert_close(diag11, cast(1.0, f32), cast(0.0001, f32), "I cholesky [1,1] = 1")
}
