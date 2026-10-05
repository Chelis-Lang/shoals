module Shoals.TestsNeg.BootstrapNanQuote
import Std.Test (assert_true)
import Shoals.Curves (deposit, cur_par_swap, bootstrap_multi)
-- Negative (shoals#79): a NaN par-swap quote. `instrument_validate`'s bounds
-- are ordered comparisons, every one of which is false against NaN, so the
-- instrument was accepted and the solve then produced a NaN pillar. Only the
-- swap *tenor* was checked for finiteness before this.
def test_neg_bootstrap_rejects_nan_swap_quote() -> unit ! { Test } = {
  rates = bootstrap_multi([deposit(cast(1.0, f32), cast(0.04, f32)), cur_par_swap(cast(2.0, f32), div(cast(0.0, f32), cast(0.0, f32)), cast(1, i64))]).1
  z = index(rates, cast(1, i64))
  assert_true(eq(z, z), "should not reach here")
}
