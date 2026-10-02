module Shoals.TestsNeg.FdBumpMismatchedPillarLists
import Std.Test (assert_true)
import Shoals.Curves (cur_par_swap, fd_bump_pillar_rate)
-- Negative (shoals#78): fd_bump_pillar_rate takes the earlier pillars as two
-- caller-supplied lists. Three rates against two times must fail loudly. The
-- extra rate is not harmlessly truncated: it is read where the candidate
-- pillar's rate belongs, so before the guard this returned a finite
-- sensitivity that changed with the extra entry (0.76 at 0.02, 0.48 at 0.50)
-- against 0.71 for the matched lists.
def test_neg_fd_bump_rejects_extra_rate_entry() -> unit ! { Test } = {
  g = fd_bump_pillar_rate(cur_par_swap(cast(3.0, f32), cast(0.045, f32), cast(1, i64)), [cast(1.0, f32), cast(2.0, f32)], [cast(0.04, f32), cast(0.9, f32), cast(0.02, f32)], cast(0.0001, f32))
  assert_true(eq(g, g), "should not reach here")
}
