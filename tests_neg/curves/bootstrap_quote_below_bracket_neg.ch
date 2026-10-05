module Shoals.TestsNeg.BootstrapQuoteBelowBracket
import Std.Test (assert_true)
import Shoals.Curves (deposit, cur_par_swap, bootstrap_multi)
-- Negative (shoals#79): the opposite bracket miss to the 1000% quote. A 2y par
-- swap quoted at -90% implies a zero rate below -0.5, and the residual is
-- negative at both endpoints. Each direction gets its own case rather than one
-- standing in for both, because the sign of the residual differs and only the
-- product test covers both.
def test_neg_bootstrap_rejects_quote_below_bracket() -> unit ! { Test } = {
  rates = bootstrap_multi([deposit(cast(1.0, f32), cast(0.04, f32)), cur_par_swap(cast(2.0, f32), neg(cast(0.9, f32)), cast(1, i64))]).1
  z = index(rates, cast(1, i64))
  assert_true(eq(z, z), "should not reach here")
}
