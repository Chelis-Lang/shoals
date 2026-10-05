module Shoals.TestsNeg.PillarTimesUnsortedYieldCurveTagged
import Std.Test (assert_true)
import Shoals.Curves (yield_curve_tagged, rate_at, ois)
-- Negative: `yield_curve_tagged` is the second exported constructor taking the
-- pillar times directly, and it was unguarded for the same reason the untagged
-- one was. The tag is the only difference between them, so it answered 0.025
-- for the same reordered pillars. Enumerating constructors by the issue text
-- alone has already missed one entry point in this module once (shoals#78).
def test_neg_yield_curve_tagged_rejects_unsorted_pillar_times() -> unit ! { Test } = {
  curve = yield_curve_tagged(ois(), to_tensor([cast(1.0, f32), cast(3.0, f32), cast(2.0, f32)]), to_tensor([cast(0.01, f32), cast(0.07, f32), cast(0.06, f32)]))
  r = rate_at(curve, cast(1.5, f32))
  assert_true(eq(r, r), "should not reach here")
}
