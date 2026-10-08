module Shoals.TestsNeg.HestonPathsZeroStepCount
import Std.Test (assert_true)
import Shoals.Stochastic (heston_qe_paths_terminal)
-- Negative: a zero step count is not a discretisation. Each path's step range
-- is empty, so every per-path fold returns its initial state and this sampler
-- returned s0 for all eight terminal spots over a one-year horizon it never
-- simulated. checked_step_count refuses at the entry.
--
-- The multi-path entry point needs its own fixture rather than inheriting the
-- single-path one: it builds its own `n_paths * n_steps` draw template and
-- carries its own copy of the step count through `base = p * n_steps`, so
-- deleting the guard here leaves the single-path fixture green.
--
-- The assertion below is one that s0 ALSO fails, so deleting the guard does
-- not make this file pass by accident: it would then fail on the assertion
-- rather than on the refusal, and `--expect neg` checks the diagnostic text
-- rather than merely that something failed.
def template() -> tensor[8, f32] = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(8, i64))))
def test_neg_heston_paths_zero_step_count() -> unit ! { Test } = {
  out = heston_qe_paths_terminal(key_from_seed(7i64), template(), cast(100.0, f32), cast(0.04, f32), cast(0.05, f32), cast(1.5, f32), cast(0.04, f32), cast(0.3, f32), cast(-0.5, f32), cast(1.0, f32), cast(0, i64))
  assert_true(gt(tensor_to_scalar(sum(out.0, 0)), cast(1e30, f32)), "should not reach here: unguarded the eight terminal spots summed to 800.00006, i.e. s0 at every path, for a one-year horizon")
}
