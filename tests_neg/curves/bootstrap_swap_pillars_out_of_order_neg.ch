module Shoals.TestsNeg.BootstrapSwapPillarsOutOfOrder
import Std.Test (assert_true)
import Shoals.Curves (deposit, cur_par_swap, bootstrap_multi)
-- Negative: a par swap reads every earlier pillar through interpolation, so a
-- 2y swap after a 3y swap has no well-defined curve to value against. The
-- bootstrap must fail loudly rather than interpolate over unsorted pillars
-- (shoals#75).
def test_neg_bootstrap_rejects_out_of_order_swap_pillars() -> unit ! { Test } = {
  rates = bootstrap_multi([deposit(cast(1.0, f32), cast(0.04, f32)), cur_par_swap(cast(3.0, f32), cast(0.045, f32), cast(1, int64)), cur_par_swap(cast(2.0, f32), cast(0.044, f32), cast(1, int64))]).1
  z = index(rates, cast(2, int64))
  assert_true(eq(z, z), "should not reach here")
}
