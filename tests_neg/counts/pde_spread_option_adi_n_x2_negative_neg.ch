module Shoals.TestsNeg.PdeSpreadOptionAdiSecondSpatialCountNegativeNeg
import Std.Test (assert_true)
import Shoals.Pde (pde_spread_option_adi)
-- shoals#166: diagnostic parity for a consumed computational count.
def test_neg_count() -> unit ! { Test } = {
  result = pde_spread_option_adi(100f32, 90f32, 5f32, 0.05f32, 0f32, 0f32, 0.2f32, 0.3f32, 0.3f32, 1f32, 3i64, -1i64, 1i64)
  assert_true(eq(result, result), "must refuse an invalid consumed count")
}
