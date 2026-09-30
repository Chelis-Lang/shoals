module Shoals.Tests.Stochastic
import Std.Test (assert_close)
import Nautilus.Stats (mean_vec, variance_vec)
import Shoals.Stochastic (gbm_path, gbm_terminal, gbm_paths_antithetic_terminal_mean)
def test_gbm_path_positive() -> unit ! { Test } = {
  template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(50, i64))))
  path = gbm_path(key_from_seed(7i64), template, cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32))
  pl = to_list(path)
  min_v = fold(fn (acc: f32, v: f32) -> if lt(v, acc) then v else acc, cast(1e30, f32), pl)
  ok = gt(min_v, cast(0.0, f32))
  assert_close(if ok then cast(1.0, f32) else cast(0.0, f32), cast(1.0, f32), cast(0.001, f32), "all path values positive")
}
def test_gbm_path_reproducible() -> unit ! { Test } = {
  template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(50, i64))))
  p1 = gbm_path(key_from_seed(7i64), copy(template), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32))
  p2 = gbm_path(key_from_seed(7i64), template, cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32))
  l1 = to_list(p1)
  l2 = to_list(p2)
  idxs = range(cast(0, i64), cast(50, i64))
  per_index_match = fold(fn (acc: bool, i: i64) -> and(acc, eq(index(l1, i), index(l2, i))), true, idxs)
  assert_close(if per_index_match then cast(1.0, f32) else cast(0.0, f32), cast(1.0, f32), cast(0.001, f32), "all 50 indices bit-exact between two seed-7 runs")
}
def test_gbm_terminal_mean() -> unit ! { Test } = {
  template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(20000, i64))))
  st = gbm_terminal(key_from_seed(123i64), template, cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32))
  m = mean_vec(copy(st))
  expected_mean = mul(cast(100.0, f32), exp(mul(cast(0.05, f32), cast(1.0, f32))))
  diff = sub(m, expected_mean)
  abs_diff = if lt(diff, cast(0.0, f32)) then neg(diff) else diff
  rel_mean = div(abs_diff, expected_mean)
  mean_ok = lt(rel_mean, cast(0.02, f32))
  v = variance_vec(st, cast(1, i64))
  s0_sq = mul(cast(100.0, f32), cast(100.0, f32))
  expected_var = mul(s0_sq, mul(exp(mul(cast(2.0, f32), mul(cast(0.05, f32), cast(1.0, f32)))), sub(exp(mul(mul(cast(0.2, f32), cast(0.2, f32)), cast(1.0, f32))), cast(1.0, f32))))
  vdiff = sub(v, expected_var)
  abs_vdiff = if lt(vdiff, cast(0.0, f32)) then neg(vdiff) else vdiff
  rel_var = div(abs_vdiff, expected_var)
  var_ok = lt(rel_var, cast(0.05, f32))
  both_ok = and(mean_ok, var_ok)
  assert_close(if both_ok then cast(1.0, f32) else cast(0.0, f32), cast(1.0, f32), cast(0.001, f32), "E[S_T] ~ S0*exp(mu*T) within 2% AND Var[S_T] within 5% of theory at 20K paths")
}
def test_antithetic_mean_finite() -> unit ! { Test } = {
  template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(2000, i64))))
  m = gbm_paths_antithetic_terminal_mean(key_from_seed(11i64), template, cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32))
  expected = mul(cast(100.0, f32), exp(mul(cast(0.05, f32), cast(1.0, f32))))
  diff = sub(m, expected)
  abs_diff = if lt(diff, cast(0.0, f32)) then neg(diff) else diff
  rel = div(abs_diff, expected)
  ok = lt(rel, cast(0.05, f32))
  assert_close(if ok then cast(1.0, f32) else cast(0.0, f32), cast(1.0, f32), cast(0.001, f32), "antithetic mean within 5% of theory")
}
