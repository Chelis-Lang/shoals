module Shoals.TestsNeg.PillarTimesUnsortedZeroFromPar
import Std.Test (assert_true)
import Shoals.Curves (bootstrap_zero_from_par, rate_at)
-- Negative: the third exported entry point whose pillars are the caller's
-- `times`. The precondition binds twice over here -- the fold accumulates the
-- fixed leg's present value in traversal order, so an out-of-order time both
-- discounts against the wrong cumulative PV and leaves the returned curve
-- unreadable by `rate_at`. It answered 0.019086447 for the reordered pairs.
def test_neg_zero_from_par_rejects_unsorted_pillar_times() -> unit ! { Test } = {
  curve = bootstrap_zero_from_par(to_tensor([cast(1.0, f32), cast(3.0, f32), cast(2.0, f32)]), to_tensor([cast(0.01, f32), cast(0.07, f32), cast(0.06, f32)]))
  r = rate_at(curve, cast(1.5, f32))
  assert_true(eq(r, r), "should not reach here")
}
