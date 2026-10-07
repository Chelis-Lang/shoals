module Shoals.TestsNeg.TreesGenericCallStepCount
import Std.Test (assert_true)
import Shoals.Trees (tr_binom_european_call_generic)
-- Negative: a zero step count is not a discretisation. At `n_steps = 0` the backward
-- induction has no layer to roll back, so this pricer returned a flat 0.0
-- regardless of moneyness -- not the intrinsic value, which would at least be
-- the limiting price of a zero-resolution lattice. tr_checked_step_count
-- refuses where the step count enters.
--
-- The assertion below is one that 0.0 ALSO fails, so deleting the guard does
-- not make this file pass by accident: it would then fail on the assertion
-- rather than on the refusal, and `--expect neg` checks the diagnostic text
-- rather than merely that something failed.
def test_neg_trees_generic_call_step_count() -> unit ! { Test } = {
  price = tr_binom_european_call_generic(cast(100.0, f32), cast(100.0, f32), cast(0.025, f32), cast(-0.025, f32), cast(0.5, f32), cast(0.99, f32), cast(0, i64))
  assert_true(gt(price, cast(1e30, f32)), "should not reach here: unguarded this priced at a flat 0.0 regardless of moneyness")
}
