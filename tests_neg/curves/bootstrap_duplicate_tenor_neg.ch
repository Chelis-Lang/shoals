module Shoals.TestsNeg.BootstrapDuplicateTenor
import Std.Test (assert_true)
import Shoals.Curves (zero_coupon, bootstrap_multi)
-- Negative (shoals#76 red team round 1): two zero-coupons at the same tenor
-- with different prices imply two different discount factors at one date, so
-- no curve reprices both. The bootstrap must fail loudly rather than keep one.
def test_neg_bootstrap_rejects_duplicate_tenor() -> unit ! { Test } = {
  rates = bootstrap_multi([zero_coupon(cast(1.0, f32), cast(0.95, f32)), zero_coupon(cast(1.0, f32), cast(0.96, f32))]).1
  z = index(rates, cast(1, i64))
  assert_true(eq(z, z), "should not reach here")
}
