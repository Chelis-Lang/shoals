module Shoals.TestsNeg.BootstrapQuoteAboveBracket
import Std.Test (assert_true)
import Shoals.Curves (deposit, cur_par_swap, bootstrap_multi)
-- Negative (shoals#79): a 2y par swap quoted at 1000% implies a zero rate
-- above the module's `[-0.5, 2.0]` search bracket, so the repricing residual
-- keeps one sign across it and `Nautilus.Roots.brent` answers NaN. The pillar
-- used to be that NaN, and nothing in the returned curve distinguished it from
-- a solved one.
def test_neg_bootstrap_rejects_quote_above_bracket() -> unit ! { Test } = {
  rates = bootstrap_multi([deposit(cast(1.0, f32), cast(0.04, f32)), cur_par_swap(cast(2.0, f32), cast(10.0, f32), cast(1, i64))]).1
  z = index(rates, cast(1, i64))
  assert_true(eq(z, z), "should not reach here")
}
