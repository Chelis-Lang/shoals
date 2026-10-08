module Shoals.TestsNeg.HullWhiteZeroStepCount
import Std.Test (assert_true)
import Shoals.HullWhite (hw1f_path)
-- Negative: a zero step count is not a discretisation. With `n_steps <= 0` every per-path
-- step range is empty, so each fold returns its initial state and this
-- sampler returned r0 at every path for a one-year horizon it never
-- simulated. hw_checked_step_count refuses at the entry.
--
-- The assertion below is one that r0 ALSO fails, so deleting the guard does
-- not make this file pass by accident: it would then fail on the assertion
-- rather than on the refusal, and `--expect neg` checks the diagnostic text
-- rather than merely that something failed.
def template() -> tensor[8, f32] = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(8, i64))))
def test_neg_hw1f_path_zero_step_count() -> unit ! { Test } = {
  out = hw1f_path(key_from_seed(7i64), template(), cast(0.03, f32), cast(0.1, f32), cast(0.03, f32), cast(0.01, f32), cast(1.0, f32), cast(0, i64))
  assert_true(gt(tensor_to_scalar(sum(out, 0)), cast(1e30, f32)), "should not reach here: unguarded the eight terminal rates summed to 0.24, i.e. r0 at every path, for a one-year horizon")
}
