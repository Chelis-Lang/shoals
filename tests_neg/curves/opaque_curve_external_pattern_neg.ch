module Shoals.TestsNeg.OpaqueCurveExternalPattern
import Std.Test (assert_true)
import Shoals.Curves (YieldCurve, yield_curve_from_pillars)
-- Negative: opacity also closes the read side. A record pattern outside the
-- module would expose the representation that the guards defend, and is the
-- route by which a consumer could rebuild an unsorted curve field by field.
-- `curve_pillars` is the sanctioned reader.
def test_neg_opaque_curve_rejects_external_pattern() -> unit ! { Test } = {
  curve = yield_curve_from_pillars(to_tensor([cast(1.0, f32), cast(2.0, f32)]), to_tensor([cast(0.01, f32), cast(0.06, f32)]))
  r = match curve with {
    | YieldCurve { kind: _, times: _, rates: rs } => index(to_list(rs), cast(0, i64))
  }
  assert_true(eq(r, r), "should not reach here")
}
