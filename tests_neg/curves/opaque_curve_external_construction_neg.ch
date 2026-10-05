module Shoals.TestsNeg.OpaqueCurveExternalConstruction
import Std.Test (assert_true)
import Shoals.Curves (YieldCurve, rate_at, custom_curve)
-- Negative: the four constructor guards cannot see a record literal written
-- outside the module. Before `YieldCurve` was opaque this compiled and
-- answered 0.025 for reordered pillars where 0.035 is correct -- the same
-- silently wrong number shoals#119 reports, reached past every guard. Opacity
-- makes it a compile error, which is what turns the pillar-order rule into a
-- property of the type rather than of four call sites.
def test_neg_opaque_curve_rejects_external_construction() -> unit ! { Test } = {
  curve = YieldCurve { kind: custom_curve("forged"), times: to_tensor([cast(1.0, f32), cast(3.0, f32), cast(2.0, f32)]), rates: to_tensor([cast(0.01, f32), cast(0.07, f32), cast(0.06, f32)]) }
  r = rate_at(curve, cast(1.5, f32))
  assert_true(eq(r, r), "should not reach here")
}
