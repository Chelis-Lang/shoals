module Shoals.TestsNeg.BootstrapResidualMismatchedPillarLists
import Std.Test (assert_true)
import Shoals.Curves (cur_par_swap, bootstrap_residual_at_pillar)
-- Negative (shoals#78): bootstrap_residual_at_pillar is the second exported
-- entry point that takes the two pillar lists independently, and it does not
-- route through solve_pillar_rate, so it needs its own guard. Before it, the
-- residual moved with the extra entry (-0.046 at 0.02, -0.079 at 0.50).
def test_neg_bootstrap_residual_rejects_extra_rate_entry() -> unit ! { Test } = {
  r = bootstrap_residual_at_pillar(cur_par_swap(cast(3.0, f32), cast(0.045, f32), cast(1, i64)), [cast(1.0, f32), cast(2.0, f32)], [cast(0.04, f32), cast(0.9, f32), cast(0.02, f32)], cast(0.05, f32))
  assert_true(eq(r, r), "should not reach here")
}
