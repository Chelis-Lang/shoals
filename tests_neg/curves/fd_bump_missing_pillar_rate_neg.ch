module Shoals.TestsNeg.FdBumpMissingPillarRate
import Std.Test (assert_true)
import Shoals.Curves (cur_par_swap, fd_bump_pillar_rate)
-- Negative (shoals#78): the other mismatch direction. Three times against two
-- rates must fail with the same named contract. This direction already died
-- before the guard, but as a bare `index 3 out of bounds for list of len 3`
-- that named neither the function nor the contract, so each direction needs
-- its own case rather than trusting one of them to cover both.
def test_neg_fd_bump_rejects_missing_pillar_rate() -> unit ! { Test } = {
  g = fd_bump_pillar_rate(cur_par_swap(cast(3.0, f32), cast(0.045, f32), cast(1, i64)), [cast(1.0, f32), cast(2.0, f32), cast(2.5, f32)], [cast(0.04, f32), cast(0.9, f32)], cast(0.0001, f32))
  assert_true(eq(g, g), "should not reach here")
}
