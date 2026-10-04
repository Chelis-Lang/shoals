module Shoals.TestsNeg.FullJacobianTemplateNarrower
import Std.Test (assert_true)
import Shoals.Curves (deposit, cur_par_swap, bootstrap_grad_full_jacobian)
-- Negative (shoals#79): the opposite mismatch to the wider template. Three
-- instruments under a two-wide one, which would discard a pillar's row and
-- column rather than invent them. Both directions get a case because the guard
-- is one inequality and a one-sided check would pass one of the two.
def test_neg_full_jacobian_rejects_narrower_template() -> unit ! { Test } = {
  tmpl = to_tensor([cast(0.0, f32), cast(0.0, f32)])
  jac = bootstrap_grad_full_jacobian(&tmpl, [deposit(cast(1.0, f32), cast(0.04, f32)), cur_par_swap(cast(2.0, f32), cast(0.045, f32), cast(1, i64)), cur_par_swap(cast(3.0, f32), cast(0.046, f32), cast(1, i64))])
  v = index(to_list(reshape(jac, [cast(4, i64)])), cast(0, i64))
  assert_true(eq(v, v), "should not reach here")
}
