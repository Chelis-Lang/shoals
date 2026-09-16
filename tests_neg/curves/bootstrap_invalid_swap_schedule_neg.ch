module Shoals.TestsNeg.BootstrapInvalidSwapSchedule
import Std.Test (assert_true)
import Shoals.Curves (deposit, cur_par_swap, bootstrap_multi)
-- Negative: a par swap whose tenor is not a whole number of payment periods
-- (2.3y annual) has no schedule to value, so the bootstrap must fail loudly
-- rather than snap the schedule or return a sentinel (shoals#75).
def test_neg_bootstrap_rejects_fractional_swap_schedule() -> unit ! { Test } = {
  rates = bootstrap_multi([deposit(cast(1.0, f32), cast(0.04, f32)), cur_par_swap(cast(2.3, f32), cast(0.045, f32), cast(1, int64))]).1
  z = index(rates, cast(1, int64))
  assert_true(eq(z, z), "should not reach here")
}
