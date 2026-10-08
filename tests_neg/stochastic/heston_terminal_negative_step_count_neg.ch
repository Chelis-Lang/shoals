module Shoals.TestsNeg.HestonTerminalNegativeStepCount
import Std.Test (assert_true)
import Shoals.Stochastic (heston_qe_terminal)
-- Negative: a negative step count is not a quantity. `range(0, -8)` is empty,
-- so the evolution fold returns its initial state and this sampler returned
-- `exp(log(s0))` -- s0 to within the round trip -- for a one-year horizon it
-- never simulated. checked_step_count refuses at the entry.
--
-- This is the unarguable half of the step-count precondition and the reason
-- the defect was filed. The zero case has a defensible reading that has to be
-- rejected on a stated ground; a negative step count has none, and the
-- diagnostic names the value so a caller can see what arrived. Kept in its
-- own file so that if the zero decision is ever revisited this case is
-- untouched by that change.
--
-- The assertion below is one that s0 ALSO fails, so deleting the guard does
-- not make this file pass by accident: it would then fail on the assertion
-- rather than on the refusal, and `--expect neg` checks the diagnostic text
-- rather than merely that something failed.
def test_neg_heston_terminal_negative_step_count() -> unit ! { Test } = {
  out = heston_qe_terminal(key_from_seed(7i64), cast(100.0, f32), cast(0.04, f32), cast(0.05, f32), cast(1.5, f32), cast(0.04, f32), cast(0.3, f32), cast(-0.5, f32), cast(1.0, f32), cast(-8, i64))
  assert_true(gt(out.0, cast(1e30, f32)), "should not reach here: unguarded this returned 100.00001, the initial spot, for a one-year horizon")
}
