module Shoals.TestsNeg.FdBumpNonfiniteResidual
import Std.Test (assert_true)
import Shoals.Curves (cur_par_swap, fd_bump_pillar_rate)
-- Negative (shoals#79): the non-finite-residual guard is reachable with a
-- perfectly valid instrument, because `fd_bump_pillar_rate` takes the earlier
-- pillars from its caller. A NaN earlier pillar rate makes the par swap's
-- annuity NaN at every candidate rate, so the bump used to return a NaN
-- derivative. This is the case that proves the guard is not dead code:
-- `instrument_validate` cannot see the caller's pillar lists.
def test_neg_fd_bump_rejects_nonfinite_residual() -> unit ! { Test } = {
  g = fd_bump_pillar_rate(cur_par_swap(cast(2.0, f32), cast(0.045, f32), cast(1, i64)), [cast(1.0, f32)], [div(cast(0.0, f32), cast(0.0, f32))], cast(0.0001, f32))
  assert_true(eq(g, g), "should not reach here")
}
