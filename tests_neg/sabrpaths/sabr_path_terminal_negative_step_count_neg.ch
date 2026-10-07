module Shoals.TestsNeg.SabrPathsNegativeStepCount
import Std.Test (assert_true)
import Shoals.SabrPaths (sabr_path_terminal)
-- Negative: a negative step count is not a quantity. With `n_steps <= 0` the step range
-- is empty, so the evolution fold returns its initial state and this sampler
-- returned f0 for a one-year horizon it never simulated.
-- sabr_checked_step_count refuses at the entry.
--
-- The assertion below is one that f0 ALSO fails, so deleting the guard does
-- not make this file pass by accident: it would then fail on the assertion
-- rather than on the refusal, and `--expect neg` checks the diagnostic text
-- rather than merely that something failed.
def test_neg_sabr_path_terminal_negative_step_count() -> unit ! { Test } = {
  out = sabr_path_terminal(key_from_seed(7i64), cast(100.0, f32), cast(0.2, f32), cast(0.5, f32), cast(-0.3, f32), cast(0.4, f32), cast(1.0, f32), cast(-8, i64))
  assert_true(gt(out.0, cast(1e30, f32)), "should not reach here: unguarded this returned 100.0, the initial forward, for a one-year horizon")
}
