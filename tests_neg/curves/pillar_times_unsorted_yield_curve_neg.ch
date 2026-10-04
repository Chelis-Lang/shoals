module Shoals.TestsNeg.PillarTimesUnsortedYieldCurve
import Std.Test (assert_true)
import Shoals.Curves (yield_curve_from_pillars, rate_at)
-- Negative: `rate_at` reads the pillars through `linear_interp_sorted`, which
-- brackets by traversal order. With the times out of order it bracketed
-- (1, 0.01) against (3, 0.07) instead of (1, 0.01) against (2, 0.06) and
-- returned 0.025 where 0.035 is correct -- a confident wrong number with no
-- trap and no NaN, feeding `discount_factor` and every price below it.
-- Construction must fail loudly instead.
def test_neg_yield_curve_rejects_unsorted_pillar_times() -> unit ! { Test } = {
  curve = yield_curve_from_pillars(to_tensor([cast(1.0, f32), cast(3.0, f32), cast(2.0, f32)]), to_tensor([cast(0.01, f32), cast(0.07, f32), cast(0.06, f32)]))
  r = rate_at(curve, cast(1.5, f32))
  assert_true(eq(r, r), "should not reach here")
}
