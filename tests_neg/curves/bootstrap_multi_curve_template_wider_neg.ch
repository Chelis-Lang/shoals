module Shoals.TestsNeg.BootstrapMultiCurveTemplateWider
import Std.Test (assert_true)
import Shoals.Curves (deposit, bootstrap_multi_curve, rate_at)
-- Negative (shoals#113): `times_template` is the only source of the type-level
-- `n` in `bootstrap_multi_curve[n]`'s result, and the body never read it. Two
-- instruments against a three-wide template type-checked and returned a value
-- declared `YieldCurve[3]` whose tensors carried two pillars: `rate_at(c, 2.0)`
-- answered 0.043088913, correct for the two real pillars, so the defect was
-- silent, and only a consumer reaching the declared third pillar saw `index 2
-- out of bounds for list of len 2`.
def test_neg_bootstrap_multi_curve_rejects_wider_template() -> unit ! { Test } = {
  insts = [deposit(cast(1.0, f32), cast(0.04, f32)), deposit(cast(2.0, f32), cast(0.045, f32))]
  tmpl = to_tensor([cast(0.0, f32), cast(0.0, f32), cast(0.0, f32)])
  r = rate_at(bootstrap_multi_curve(insts, tmpl), cast(2.0, f32))
  assert_true(eq(r, r), "should not reach here")
}
