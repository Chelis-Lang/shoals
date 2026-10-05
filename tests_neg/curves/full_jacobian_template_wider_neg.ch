module Shoals.TestsNeg.FullJacobianTemplateWider
import Std.Test (assert_true)
import Shoals.Curves (deposit, cur_par_swap, bootstrap_grad_full_jacobian)
-- Negative (shoals#79, recorded on the issue as its second instance): two
-- instruments under a three-wide `paths_template`. `paths_template` carries
-- only the result's extent, exactly as `times_template` does for
-- `bootstrap_multi_curve`, and a mismatch used to return a full matrix of NaN
-- with nothing to distinguish it from a Jacobian whose entries were NaN for a
-- numerical reason. A length mismatch has no numerical reading at all.
def test_neg_full_jacobian_rejects_wider_template() -> unit ! { Test } = {
  tmpl = to_tensor([cast(0.0, f32), cast(0.0, f32), cast(0.0, f32)])
  jac = bootstrap_grad_full_jacobian(&tmpl, [deposit(cast(1.0, f32), cast(0.04, f32)), cur_par_swap(cast(2.0, f32), cast(0.045, f32), cast(1, i64))])
  v = index(to_list(reshape(jac, [cast(9, i64)])), cast(0, i64))
  assert_true(eq(v, v), "should not reach here")
}
