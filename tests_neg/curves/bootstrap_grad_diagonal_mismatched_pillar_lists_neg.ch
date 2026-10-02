module Shoals.TestsNeg.BootstrapGradDiagonalMismatchedPillarLists
import Std.Test (assert_true)
import Shoals.Curves (cur_par_swap, bootstrap_grad_diagonal)
-- Negative (shoals#78): bootstrap_grad_diagonal is the third exported entry
-- point taking the two pillar lists independently. It grew them in #76, which
-- merged 18 minutes before shoals#78 was filed, so the issue's two-function
-- enumeration was incomplete when written rather than overtaken later. Before
-- the guard its diagonal moved with the extra entry (0.70 at 0.02, 1.93 at
-- 0.50).
def test_neg_bootstrap_grad_diagonal_rejects_extra_rate_entry() -> unit ! { Test } = {
  g = bootstrap_grad_diagonal(cur_par_swap(cast(3.0, f32), cast(0.045, f32), cast(1, i64)), [cast(1.0, f32), cast(2.0, f32)], [cast(0.04, f32), cast(0.9, f32), cast(0.02, f32)], cast(0.05, f32))
  assert_true(eq(g, g), "should not reach here")
}
