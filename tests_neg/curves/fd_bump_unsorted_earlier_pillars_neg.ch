module Shoals.TestsNeg.FdBumpUnsortedEarlierPillars
import Std.Test (assert_true)
import Shoals.Curves (deposit, fd_bump_pillar_rate)
-- Negative (shoals#76 red team round 2): fd_bump_pillar_rate takes the
-- earlier pillars from its caller, so they need not be sorted. Unsorted
-- earlier pillars [2, 1] must fail loudly even though the new 3y tenor exceeds
-- the last of them; only the earlier-pillar monotonicity check catches this.
def test_neg_fd_bump_rejects_unsorted_earlier_pillars() -> unit ! { Test } = {
  g = fd_bump_pillar_rate(deposit(cast(3.0, f32), cast(0.04, f32)), [cast(2.0, f32), cast(1.0, f32)], [cast(0.04, f32), cast(0.03, f32)], cast(0.0001, f32))
  assert_true(eq(g, g), "should not reach here")
}
