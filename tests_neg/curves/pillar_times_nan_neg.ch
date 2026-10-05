module Shoals.TestsNeg.PillarTimesNan
import Std.Test (assert_true)
import Shoals.Curves (yield_curve_from_pillars, rate_at)
-- Negative: a NaN pillar time has no position relative to any other time, so
-- it cannot be strictly greater than its predecessor and is rejected by the
-- same `gt`. Recorded as its own case because the guard's handling of NaN is
-- a consequence of the comparison rather than a separate branch: if the
-- predicate were ever rewritten as "not less than or equal", NaN would pass.
def test_neg_yield_curve_rejects_nan_pillar_time() -> unit ! { Test } = {
  nan_t = div(cast(0.0, f32), cast(0.0, f32))
  curve = yield_curve_from_pillars(to_tensor([cast(1.0, f32), nan_t, cast(3.0, f32)]), to_tensor([cast(0.01, f32), cast(0.06, f32), cast(0.07, f32)]))
  r = rate_at(curve, cast(1.5, f32))
  assert_true(eq(r, r), "should not reach here")
}
