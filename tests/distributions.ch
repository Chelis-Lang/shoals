module Shoals.Tests.Distributions
import Std.Test (assert_close)
import Shoals.Distributions (lognormal_pdf, lognormal_cdf, student_t_pdf, bvn_pdf)
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
