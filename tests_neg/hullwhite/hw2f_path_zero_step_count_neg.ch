module Shoals.TestsNeg.HullWhiteTwoFactorZeroStepCount
import Std.Test (assert_true)
import Shoals.HullWhite (hw2f_path)
-- Negative: a zero step count is not a discretisation. With `n_steps <= 0`
-- every per-path step range is empty, so each fold returns its initial state
-- and this sampler returned (x0, y0) at every path for a one-year horizon it
-- never simulated. hw_checked_step_count refuses at the entry.
--
-- This file exists because the two-factor path threads its own copy of the
-- step count through `base = p * n_steps` and builds its own
-- `n_paths * n_steps` draw template, so a deletion here is invisible to the
-- one-factor fixture beside it.
--
-- The assertion below is one that x0 ALSO fails, so deleting the guard does
-- not make this file pass by accident.
def template() -> tensor[8, f32] = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(8, i64))))
def test_neg_hw2f_path_zero_step_count() -> unit ! { Test } = {
  out = hw2f_path(key_from_seed(7i64), template(), cast(0.02, f32), cast(0.01, f32), cast(0.1, f32), cast(0.2, f32), cast(0.01, f32), cast(0.005, f32), cast(-0.3, f32), cast(1.0, f32), cast(0, i64))
  assert_true(gt(tensor_to_scalar(sum(out.0, 0)), cast(1e30, f32)), "should not reach here: unguarded the eight terminal x-factors summed to 0.16, i.e. x0 at every path, for a one-year horizon")
}
