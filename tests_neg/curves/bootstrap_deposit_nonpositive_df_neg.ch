module Shoals.TestsNeg.BootstrapDepositNonpositiveDf
import Std.Test (assert_true)
import Shoals.Curves (deposit, bootstrap_multi)
-- Negative (shoals#79): a 2y deposit at -60% simple interest implies
-- `1 + rate * tenor = -0.2`, a negative discount factor, so `log(df)` is NaN
-- and the residual is NaN at every candidate rate. The old bound `rate > -1`
-- is this condition only at a one-year tenor, so this quote validated and
-- bootstrapped to a silent NaN pillar. Not one of the issue's reproductions;
-- found while enumerating the ways a validated instrument could still reach
-- the solver with no finite answer.
def test_neg_bootstrap_rejects_deposit_with_nonpositive_discount_factor() -> unit ! { Test } = {
  rates = bootstrap_multi([deposit(cast(2.0, f32), neg(cast(0.6, f32)))]).1
  z = index(rates, cast(0, i64))
  assert_true(eq(z, z), "should not reach here")
}
