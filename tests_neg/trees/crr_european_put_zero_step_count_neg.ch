module Shoals.TestsNeg.TreesCrrEuropeanPutZeroStepCount
import Std.Test (assert_true)
import Shoals.Trees (tr_crr_european_put)
-- Negative: a zero step count is not a discretisation. This pricer forms
-- `dt = t / n_steps`, dividing the horizon by zero; the non-finite step
-- poisons the up and down log-moves and the terminal node prices collapse to
-- a flat 0.0 regardless of moneyness. tr_checked_step_count refuses where the
-- step count enters.
--
-- A negative count at this entry point has its own fixture. This file pins
-- the ZERO boundary, which that one cannot: unguarding this site is caught
-- only by the delegated generic's lattice-depth diagnostic, so a weakening
-- that kept this guard's message was invisible to the whole suite until this
-- fixture existed.
--
-- The strike is deliberately in the money. At a strike equal to s0 the
-- intrinsic value is 0.0, so a correct price and a collapsed one agree and
-- the assertion could not tell them apart.
def test_neg_trees_crr_european_put_zero_step_count() -> unit ! { Test } = {
  price = tr_crr_european_put(cast(100.0, f32), cast(110.0, f32), cast(0.05, f32), cast(0.0, f32), cast(0.2, f32), cast(1.0, f32), cast(0, i64))
  assert_true(gt(price, cast(1e30, f32)), "should not reach here: unguarded this priced a put ten points in the money at a flat 0.0")
}
