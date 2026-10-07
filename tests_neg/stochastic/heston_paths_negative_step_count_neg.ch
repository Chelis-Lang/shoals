module Shoals.TestsNeg.HestonPathsNegativeStepCount
import Std.Test (assert_true)
import Shoals.Stochastic (heston_qe_paths_terminal)
-- Negative: a negative step count is not a quantity. `range(0, -8)` is empty
-- for every path, so each per-path fold returns its initial state and this
-- sampler returned s0 for all eight terminal spots over a one-year horizon it
-- never simulated. checked_step_count refuses at the entry.
--
-- This is the unarguable half of the step-count precondition. It gets its own
-- file for the same two reasons the single-path pair does: the warrant differs
-- from the zero case's, and this entry point's step count is threaded
-- separately from the single-path one.
--
-- The assertion below is one that s0 ALSO fails, so deleting the guard does
-- not make this file pass by accident: it would then fail on the assertion
-- rather than on the refusal, and `--expect neg` checks the diagnostic text
-- rather than merely that something failed.
def template() -> tensor[8, f32] = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(8, i64))))
def test_neg_heston_paths_negative_step_count() -> unit ! { Test } = {
  out = heston_qe_paths_terminal(key_from_seed(7i64), template(), cast(100.0, f32), cast(0.04, f32), cast(0.05, f32), cast(1.5, f32), cast(0.04, f32), cast(0.3, f32), cast(-0.5, f32), cast(1.0, f32), cast(-8, i64))
  assert_true(gt(tensor_to_scalar(sum(out.0, 0)), cast(1e30, f32)), "should not reach here: unguarded the eight terminal spots summed to 800.00006, i.e. s0 at every path, for a one-year horizon")
}
