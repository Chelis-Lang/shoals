module Shoals.Tests.RngSobol1024
import Std.Test (assert_close)
import Shoals.Rng (sobol_point_runtime_at, sobol_dim_runtime, rng_sobol_runtime_max_dim, rng_sobol_runtime_native_dim)
def to01(b: bool) -> f32 = if b then cast(1.0, f32) else cast(0.0, f32)
def make_zeros(n: int64) -> tensor[m, f32] = to_tensor(map(fn (i: int64) -> cast(0.0, f32), range(cast(0, int64), n)))
def test_sobol_1024_first_dim_radical_inverse() -> unit ! { Test } = {
  template = make_zeros(cast(8, int64))
  pts = sobol_dim_runtime(cast(0, int64), template)
  vals = to_list(pts)
  expected = [cast(0.0, f32), cast(0.5, f32), cast(0.25, f32), cast(0.75, f32), cast(0.125, f32), cast(0.625, f32), cast(0.375, f32), cast(0.875, f32)]
  pairs = zip(vals, expected)
  max_diff = fold(fn (acc: f32, e: (f32, f32)) -> {
    d = sub(e.0, e.1)
    a = if lt(d, cast(0.0, f32)) then neg(d) else d
    if gt(a, acc) then a else acc
  }, cast(0.0, f32), pairs)
  in_unit = fold(fn (acc: bool, v: f32) -> and(acc, and(gte(v, cast(0.0, f32)), lt(v, cast(1.0, f32)))), true, vals)
  both_ok = and(lt(max_diff, cast(0.0001, f32)), in_unit)
  assert_close(to01(both_ok), cast(1.0, f32), cast(0.001, f32), "sobol_dim_runtime(0, n=8) is van der Corput base 2 (0, 1/2, 1/4, 3/4, 1/8, 5/8, 3/8, 7/8) and spans [0, 1)")
}
def test_sobol_1024_at_dim_512_uniformity() -> unit ! { Test } = {
  template = make_zeros(cast(1024, int64))
  pts = sobol_dim_runtime(cast(512, int64), template)
  vals = to_list(pts)
  n_f = cast(1024.0, f32)
  sum_sq = fold(fn (acc: f32, v: f32) -> add(acc, mul(v, v)), cast(0.0, f32), vals)
  m2 = div(sum_sq, n_f)
  in_band = and(gte(m2, cast(0.3, f32)), lte(m2, cast(0.36, f32)))
  assert_close(to01(in_band), cast(1.0, f32), cast(0.001, f32), "dim 512: empirical second moment over 1024 points lies in [0.30, 0.36] (uniform target 1/3)")
}
def test_sobol_1024_returns_finite_values() -> unit ! { Test } = {
  template = make_zeros(cast(256, int64))
  pts = sobol_dim_runtime(cast(1023, int64), template)
  vals = to_list(pts)
  in_unit = fold(fn (acc: bool, v: f32) -> and(acc, and(gte(v, cast(0.0, f32)), lt(v, cast(1.0, f32)))), true, vals)
  assert_close(to01(in_unit), cast(1.0, f32), cast(0.001, f32), "dim 1023: all 256 points in [0, 1)")
}
def test_sobol_1024_point_runtime_at_matches_dim_runtime() -> unit ! { Test } = {
  template = make_zeros(cast(16, int64))
  pts = sobol_dim_runtime(cast(7, int64), template)
  vals = to_list(pts)
  idxs = range(cast(0, int64), cast(16, int64))
  max_diff = fold(fn (acc: f32, i: int64) -> {
    a = index(vals, i)
    b = sobol_point_runtime_at(cast(7, int64), i)
    d = sub(a, b)
    abs_d = if lt(d, cast(0.0, f32)) then neg(d) else d
    if gt(abs_d, acc) then abs_d else acc
  }, cast(0.0, f32), idxs)
  assert_close(max_diff, cast(0.0, f32), cast(0.0001, f32), "sobol_point_runtime_at agrees with sobol_dim_runtime entry-wise (dim 7, n=16)")
}
def test_sobol_1024_dim_caps() -> unit ! { Test } = {
  max_d = rng_sobol_runtime_max_dim()
  nat_d = rng_sobol_runtime_native_dim()
  ok_max = eq(max_d, cast(1024, int64))
  ok_nat = eq(nat_d, cast(32, int64))
  assert_close(to01(and(ok_max, ok_nat)), cast(1.0, f32), cast(0.001, f32), "rng_sobol_runtime_max_dim == 1024 and rng_sobol_runtime_native_dim == 32")
}
