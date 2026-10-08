module Shoals.TestsNeg.TreesCrrAmericanPutStepCount
import Std.Test (assert_true)
import Shoals.Trees (tr_crr_american_put)
-- Negative: a zero step count is not a discretisation. At `n_steps = 0` this pricer forms
-- `dt = t / n_steps`, dividing the horizon by zero; the non-finite step
-- poisons the up and down log-moves and the terminal node prices collapse to
-- a flat 0.0 REGARDLESS OF MONEYNESS. That is not the intrinsic value and not
-- the price of anything. tr_checked_step_count refuses where the step count
-- enters.
--
-- The assertion below is one that 0.0 ALSO fails, so deleting the guard does
-- not make this file pass by accident: it would then fail on the assertion
-- rather than on the refusal, and `--expect neg` checks the diagnostic text
-- rather than merely that something failed.
def test_neg_trees_crr_american_put_step_count() -> unit ! { Test } = {
  price = tr_crr_american_put(cast(100.0, f32), cast(110.0, f32), cast(0.05, f32), cast(0.0, f32), cast(0.2, f32), cast(1.0, f32), cast(0, i64))
  assert_true(gt(price, cast(1e30, f32)), "should not reach here: unguarded this priced at a flat 0.0 regardless of moneyness")
}
