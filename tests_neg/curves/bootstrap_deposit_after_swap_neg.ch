module Shoals.TestsNeg.BootstrapDepositAfterSwap
import Std.Test (assert_true)
import Shoals.Curves (deposit, cur_par_swap, bootstrap_multi)
-- Negative (shoals#76 red team round 1): a shorter deposit after a swap would
-- make the returned curve's pillar times non-increasing, so neither input
-- could reprice through `rate_at`. The bootstrap must fail loudly even though
-- the offending instrument is not a swap.
def test_neg_bootstrap_rejects_deposit_shorter_than_earlier_swap() -> unit ! { Test } = {
  rates = bootstrap_multi([cur_par_swap(cast(2.0, f32), cast(0.045, f32), cast(1, i64)), deposit(cast(1.0, f32), cast(0.02, f32))]).1
  z = index(rates, cast(1, i64))
  assert_true(eq(z, z), "should not reach here")
}
