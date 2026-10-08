module Shoals.TestsNeg.HestonCallLewisPanelsPanelCountNearestNeg
import Std.Test (assert_true)
import Shoals.Heston (heston_call_lewis_panels)
-- shoals#166: diagnostic parity for a consumed computational count.
def test_neg_count() -> unit ! { Test } = {
  result = heston_call_lewis_panels(100f32, 100f32, 1f32, 0.05f32, 0.04f32, 2f32, 0.04f32, 0.3f32, -0.7f32, 10f32, 0i64)
  assert_true(eq(result, result), "must refuse an invalid consumed count")
}
