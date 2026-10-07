module Shoals.TestsNeg.LmmPathZeroStepCount
import Std.Test (assert_true)
import Shoals.LiborMarketModel (lmm_path)
-- Negative: a zero step count is not a discretisation. With `n_steps <= 0` lmm_evolve's
-- step range is empty, so its fold returns the initial forward curve and
-- lmm_path returned forwards0 at every path for a one-year horizon it never
-- simulated. lmm_checked_step_count refuses at lmm_path's entry, and
-- lmm_evolve carries the same check because it is exported too.
--
-- The assertion below is one that the initial curve ALSO fails, so deleting
-- the guard does not make this file pass by accident.
def template() -> tensor[8, f32] = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(8, i64))))
def forwards() -> tensor[3, f32] = to_tensor([cast(0.03, f32), cast(0.035, f32), cast(0.04, f32)])
def taus() -> tensor[3, f32] = to_tensor([cast(0.5, f32), cast(0.5, f32), cast(0.5, f32)])
def sigmas() -> tensor[3, f32] = to_tensor([cast(0.2, f32), cast(0.2, f32), cast(0.2, f32)])
def corr() -> tensor[3, 3, f32] = reshape(to_tensor([cast(1.0, f32), cast(0.9, f32), cast(0.8, f32), cast(0.9, f32), cast(1.0, f32), cast(0.9, f32), cast(0.8, f32), cast(0.9, f32), cast(1.0, f32)]), [cast(3, i64), cast(3, i64)])
def test_neg_lmm_path_zero_step_count() -> unit ! { Test } = {
  out = lmm_path(key_from_seed(7i64), template(), forwards(), taus(), sigmas(), corr(), cast(1.0, f32), cast(0, i64), cast(0, i64))
  assert_true(gt(tensor_to_scalar(sum(out, 0)), cast(1e30, f32)), "should not reach here: unguarded the eight terminal draws of the first forward summed to 0.24, i.e. 0.03 at every path, for a one-year horizon")
}
