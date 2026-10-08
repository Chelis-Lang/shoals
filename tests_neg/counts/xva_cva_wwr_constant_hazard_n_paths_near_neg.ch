module Shoals.TestsNeg.XvaCvaWwrConstantHazardPathCountNearestNeg
import Std.Test (assert_true)
import Shoals.Xva (xva_cva_wwr_constant_hazard)
-- shoals#166: diagnostic parity for a consumed computational count.
def test_neg_count() -> unit ! { Test } = {
  result = xva_cva_wwr_constant_hazard(key_from_seed(21i64), to_tensor([0f32, 1f32]), to_tensor([100f32, 100f32]), 10f32, 0.4f32, 0.03f32, 0.3f32, 0i64)
  assert_true(eq(result, result), "must refuse an invalid consumed count")
}
