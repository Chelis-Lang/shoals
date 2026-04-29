module Shoals.Tests.Stochastic
import Std.Test (assert_close)
import Nautilus.Stats (mean_vec)
import Shoals.Stochastic (gbm_path, gbm_terminal, gbm_paths_antithetic_terminal_mean)
def test_gbm_path_positive() -> unit ! { Test } = {
  template = to_tensor(map(fn (i: int64) -> cast(0.0, f32), range(cast(0, int64), cast(50, int64))))
  path = with seed(7) { gbm_path(template, cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32)) }
  pl = to_list(path)
  min_v = fold(fn (acc: f32, v: f32) -> if lt(v, acc) then v else acc, cast(1000000000000000000000000000000.0, f32), pl)
  ok = gt(min_v, cast(0.0, f32))
  assert_close(if ok then cast(1.0, f32) else cast(0.0, f32), cast(1.0, f32), cast(0.001, f32), "all path values positive")
}
def test_gbm_path_reproducible() -> unit ! { Test } = {
  template = to_tensor(map(fn (i: int64) -> cast(0.0, f32), range(cast(0, int64), cast(50, int64))))
  p1 = with seed(7) { gbm_path(copy(template), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32)) }
  p2 = with seed(7) { gbm_path(template, cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32)) }
  l1 = to_list(p1)
  l2 = to_list(p2)
  last_idx = cast(49, int64)
  assert_close(index(l1, last_idx), index(l2, last_idx), cast(0.0, f32), "reproducible terminal")
}
def test_gbm_terminal_mean() -> unit ! { Test } = {
  template = to_tensor(map(fn (i: int64) -> cast(0.0, f32), range(cast(0, int64), cast(5000, int64))))
  st = with seed(123) { gbm_terminal(template, cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32)) }
  m = mean_vec(st)
  expected = mul(cast(100.0, f32), exp(mul(cast(0.05, f32), cast(1.0, f32))))
  diff = sub(m, expected)
  abs_diff = if lt(diff, cast(0.0, f32)) then neg(diff) else diff
  rel = div(abs_diff, expected)
  ok = lt(rel, cast(0.05, f32))
  assert_close(if ok then cast(1.0, f32) else cast(0.0, f32), cast(1.0, f32), cast(0.001, f32), "E[S_T] ~ S0*exp(mu*T)")
}
def test_antithetic_mean_finite() -> unit ! { Test } = {
  template = to_tensor(map(fn (i: int64) -> cast(0.0, f32), range(cast(0, int64), cast(2000, int64))))
  m = with seed(11) { gbm_paths_antithetic_terminal_mean(template, cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32)) }
  expected = mul(cast(100.0, f32), exp(mul(cast(0.05, f32), cast(1.0, f32))))
  diff = sub(m, expected)
  abs_diff = if lt(diff, cast(0.0, f32)) then neg(diff) else diff
  rel = div(abs_diff, expected)
  ok = lt(rel, cast(0.05, f32))
  assert_close(if ok then cast(1.0, f32) else cast(0.0, f32), cast(1.0, f32), cast(0.001, f32), "antithetic mean within 5% of theory")
}
