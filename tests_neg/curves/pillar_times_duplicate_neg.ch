module Shoals.TestsNeg.PillarTimesDuplicate
import Std.Test (assert_true)
import Shoals.Curves (yield_curve_from_pillars, rate_at)
-- Negative: the rule is *strictly* increasing, not merely non-decreasing. Two
-- pillars at the same time carry two different rates at one date, so no curve
-- reads both, and the interpolator's bracket width is zero there. This is the
-- negative parity case for the `gt` in the guard: a `gte` would accept it.
-- `bootstrap_multi` already rejects a duplicate tenor for the same reason
-- (`tests_neg/curves/bootstrap_duplicate_tenor_neg.ch`).
def test_neg_yield_curve_rejects_duplicate_pillar_time() -> unit ! { Test } = {
  curve = yield_curve_from_pillars(to_tensor([cast(1.0, f32), cast(2.0, f32), cast(2.0, f32)]), to_tensor([cast(0.01, f32), cast(0.06, f32), cast(0.07, f32)]))
  r = rate_at(curve, cast(1.5, f32))
  assert_true(eq(r, r), "should not reach here")
}
