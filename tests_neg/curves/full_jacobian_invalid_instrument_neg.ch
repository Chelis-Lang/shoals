module Shoals.TestsNeg.FullJacobianInvalidInstrument
import Std.Test (assert_true)
import Shoals.Curves (zero_coupon, bootstrap_grad_full_jacobian)
-- Negative (shoals#79): an invalid instrument in a length-matched call. This
-- replaces `test_full_jacobian_returns_nan_for_invalid_input` in
-- `tests/curves_bootstrap_ift_full.ch`, which asserted the sentinel this issue
-- decides against ("invalid instrument list yields a sentinel-NaN Jacobian
-- (caller can test eq(v, v))"). `bootstrap_grad_full_jacobian` no longer
-- pre-validates: it reaches `solve_pillar_rate`, whose diagnostic already
-- names the condition, rather than restating it.
def test_neg_full_jacobian_rejects_invalid_instrument() -> unit ! { Test } = {
  tmpl = to_tensor([cast(0.0, f32), cast(0.0, f32)])
  jac = bootstrap_grad_full_jacobian(&tmpl, [zero_coupon(cast(1.0, f32), cast(0.95, f32)), zero_coupon(neg(cast(2.0, f32)), cast(0.9, f32))])
  v = index(to_list(reshape(jac, [cast(4, i64)])), cast(0, i64))
  assert_true(eq(v, v), "should not reach here")
}
