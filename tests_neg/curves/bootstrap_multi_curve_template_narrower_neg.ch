module Shoals.TestsNeg.BootstrapMultiCurveTemplateNarrower
import Std.Test (assert_true)
import Shoals.Curves (deposit, bootstrap_multi_curve, rate_at)
-- Negative (shoals#113): the opposite mismatch to the wider template, and the
-- quieter one -- nothing traps in this direction. Three instruments against a
-- two-wide template returned a value declared `YieldCurve[2]` whose tensors
-- carried three pillars (measured with the predicate forced to `true`: actual
-- length 3, `rate_at(c, 2.0)` = 0.043088913, `rate_at(c, 3.0)` =
-- 0.046586514). Reads by time see the third pillar; anything trusting the
-- declared extent cannot. Each direction has its own case rather than one
-- standing in for both.
def test_neg_bootstrap_multi_curve_rejects_narrower_template() -> unit ! { Test } = {
  insts = [deposit(cast(1.0, f32), cast(0.04, f32)), deposit(cast(2.0, f32), cast(0.045, f32)), deposit(cast(3.0, f32), cast(0.05, f32))]
  tmpl = to_tensor([cast(0.0, f32), cast(0.0, f32)])
  r = rate_at(bootstrap_multi_curve(insts, tmpl), cast(2.0, f32))
  assert_true(eq(r, r), "should not reach here")
}
