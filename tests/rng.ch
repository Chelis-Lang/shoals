module Shoals.Tests.Rng
import Std.Test (assert_close)
import Shoals.Rng (sobol_points)
def to01(b: bool) -> f32 = if b then cast(1.0, f32) else cast(0.0, f32)
def test_sobol_first_point() -> unit ! { Test } = {
  pts = sobol_points(cast(1, int64), cast(8, int64))
  vals = to_list(pts)
  idxs = range(cast(0, int64), cast(8, int64))
  all_zero = fold(fn (acc: bool, i: int64) -> and(acc, eq(index(vals, i), cast(0.0, f32))), true, idxs)
  assert_close(to01(all_zero), cast(1.0, f32), cast(0.001, f32), "sobol_points(1, 8) is all zeros")
}
