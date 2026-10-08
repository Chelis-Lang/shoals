module Shoals.TestsNeg.TreesJrEuropeanCallZeroStepCount
import Std.Test (assert_true)
import Shoals.Trees (tr_jr_european_call)
-- Negative: a zero step count is not a discretisation. This pricer forms
-- `dt = t / n_steps`, dividing the horizon by zero; the non-finite step
-- poisons the up and down log-moves and the terminal node prices collapse to
-- a flat 0.0 regardless of moneyness. tr_checked_step_count refuses where the
-- step count enters.
--
-- The strike is deliberately in the money. At a strike equal to s0 the
-- intrinsic value is 0.0, so a correct price and a collapsed one agree and
-- the assertion could not tell them apart.
--
-- The assertion below is one that 0.0 ALSO fails, so deleting the guard does
-- not make this file pass by accident: it would then fail on the assertion
-- rather than on the refusal, and `--expect neg` checks the diagnostic text.
def test_neg_trees_jr_european_call_zero_step_count() -> unit ! { Test } = {
  price = tr_jr_european_call(cast(100.0, f32), cast(90.0, f32), cast(0.05, f32), cast(0.0, f32), cast(0.2, f32), cast(1.0, f32), cast(0, i64))
  assert_true(gt(price, cast(1e30, f32)), "should not reach here: unguarded this priced an in-the-money option at a flat 0.0")
}
