module Shoals.Tests.RngHeavy
import Std.Test (assert_close)
import Nautilus.Distributions (normal_sample)
import Nautilus.Stats (variance_vec)
import Shoals.Rng (sobol_points, halton_points, antithetic_terminal_mean)
import Shoals.References.Rng (sobol_second_moment)
import Shoals.Properties.Rng (sobol_points_in_unit_interval, halton_points_in_unit_interval, sobol_second_moment_near_one_third)
def to01(b: bool) -> f32 = if b then cast(1.0, f32) else cast(0.0, f32)
def test_sobol_first_point() -> unit ! { Test } = {
  pts = sobol_points(cast(1, int64), cast(8, int64))
  vals = to_list(pts)
  idxs = range(cast(0, int64), cast(8, int64))
  all_zero = fold(fn (acc: bool, i: int64) -> and(acc, eq(index(vals, i), cast(0.0, f32))), true, idxs)
  assert_close(to01(all_zero), cast(1.0, f32), cast(0.001, f32), "sobol_points(1, 8) is all zeros")
}
def test_sobol_no_duplicates_first_pow_two() -> unit ! { Test } = {
  n_p = cast(64, int64)
  n_d = cast(3, int64)
  pts = sobol_points(n_p, n_d)
  vals = to_list(pts)
  row_pairs = range(cast(0, int64), n_p)
  all_distinct = fold(fn (acc: bool, i: int64) -> {
    j_pairs = range(add(i, cast(1, int64)), n_p)
    pairwise = fold(fn (inner_acc: bool, j: int64) -> {
      d_idxs = range(cast(0, int64), n_d)
      same = fold(fn (s: bool, d: int64) -> {
        ai = index(vals, add(mul(i, n_d), d))
        aj = index(vals, add(mul(j, n_d), d))
        and(s, eq(ai, aj))
      }, true, d_idxs)
      and(inner_acc, not(same))
    }, true, j_pairs)
    and(acc, pairwise)
  }, true, row_pairs)
  assert_close(to01(all_distinct), cast(1.0, f32), cast(0.001, f32), "sobol_points(64, 3) has no duplicate rows")
}
def test_sobol_unit_interval() -> unit ! { Test } = {
  ok = sobol_points_in_unit_interval(cast(128, int64), cast(4, int64))
  assert_close(to01(ok), cast(1.0, f32), cast(0.001, f32), "sobol_points(128, 4) values in [0, 1)")
}
def test_sobol_second_moment() -> unit ! { Test } = {
  pts = sobol_points(cast(64, int64), cast(2, int64))
  d_idxs = range(cast(0, int64), cast(2, int64))
  all_close = fold(fn (acc: bool, d: int64) -> {
    m2 = sobol_second_moment(pts, d, cast(64, int64), cast(2, int64))
    and(acc, and(gte(m2, cast(0.28, f32)), lte(m2, cast(0.38, f32))))
  }, true, d_idxs)
  assert_close(to01(all_close), cast(1.0, f32), cast(0.001, f32), "sobol second moment in [0.28, 0.38] for each of 2 dims at n=64; spec-rigor 1024-D smoke is a future manual gate per the host-eval-perf deferral pattern")
}
def test_halton_first_few_dim_zero() -> unit ! { Test } = {
  pts = halton_points(cast(4, int64), cast(1, int64))
  vals = to_list(pts)
  v0 = index(vals, cast(0, int64))
  v1 = index(vals, cast(1, int64))
  v2 = index(vals, cast(2, int64))
  v3 = index(vals, cast(3, int64))
  diff0 = sub(v0, cast(0.5, f32))
  diff1 = sub(v1, cast(0.25, f32))
  diff2 = sub(v2, cast(0.75, f32))
  diff3 = sub(v3, cast(0.125, f32))
  abs_max = fold(fn (acc: f32, d: f32) -> {
    a = if lt(d, cast(0.0, f32)) then neg(d) else d
    if gt(a, acc) then a else acc
  }, cast(0.0, f32), [diff0, diff1, diff2, diff3])
  assert_close(abs_max, cast(0.0, f32), cast(0.0001, f32), "halton(4, 1) = (0.5, 0.25, 0.75, 0.125) van der Corput base 2")
}
def test_halton_unit_interval() -> unit ! { Test } = {
  ok = halton_points_in_unit_interval(cast(128, int64), cast(8, int64))
  assert_close(to01(ok), cast(1.0, f32), cast(0.001, f32), "halton_points(128, 8) values in [0, 1)")
}
def monotone_payoff[n](template: tensor[n, f32]) -> tensor[n, f32] ! { Random } = {
  z = normal_sample(template, cast(0.0, f32), cast(1.0, f32))
  zs = to_list(z)
  to_tensor(map(fn (zi: f32) -> add(cast(1.0, f32), mul(cast(0.5, f32), zi)), zs))
}
def anti_monotone_payoff[n](template: tensor[n, f32]) -> tensor[n, f32] ! { Random } = {
  z = normal_sample(template, cast(0.0, f32), cast(1.0, f32))
  zs = to_list(z)
  to_tensor(map(fn (zi: f32) -> add(cast(1.0, f32), mul(cast(0.5, f32), neg(zi))), zs))
}
def make_zeros(n: int64) -> tensor[m, f32] = to_tensor(map(fn (i: int64) -> cast(0.0, f32), range(cast(0, int64), n)))
def trial_plain[n](template: tensor[n, f32]) -> f32 ! { Random } = {
  g = monotone_payoff(template)
  gl = to_list(copy(g))
  n_f = cast(numel(g), f32)
  s = fold(fn (acc: f32, v: f32) -> add(acc, v), cast(0.0, f32), gl)
  div(s, n_f)
}
def trial_anti[n](template_a: tensor[n, f32], template_b: tensor[n, f32]) -> f32 ! { Random } = {
  gp = monotone_payoff(template_a)
  gm = anti_monotone_payoff(template_b)
  antithetic_terminal_mean(gp, gm)
}
def test_antithetic_mean_reduces_variance() -> unit ! { Test } = {
  k_outer = cast(20, int64)
  k_idxs = range(cast(0, int64), k_outer)
  plain_means = with seed(101i64) { map(fn (k: int64) -> trial_plain(make_zeros(cast(2000, int64))), k_idxs) }
  anti_means = with seed(101i64) { map(fn (k: int64) -> trial_anti(make_zeros(cast(2000, int64)), make_zeros(cast(2000, int64))), k_idxs) }
  var_plain = variance_vec(to_tensor(plain_means), cast(1, int64))
  var_anti = variance_vec(to_tensor(anti_means), cast(1, int64))
  reduced = lt(var_anti, var_plain)
  assert_close(to01(reduced), cast(1.0, f32), cast(0.001, f32), "antithetic mean has lower across-run variance than plain MC on monotone payoff")
}
