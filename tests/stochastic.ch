module Shoals.Tests.Stochastic
import Std.Test (assert_close)
import Nautilus.Stats (mean_vec, variance_vec)
import Shoals.Stochastic (gbm_path, gbm_terminal, gbm_paths_antithetic_terminal_mean, merton_jump_terminal, sto_kou_jump_terminal, correlated_gbm_terminal_2d, heston_qe_terminal, heston_qe_paths_terminal, heston_qe_step)
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
-- Positive parity for the shoals#139 horizon guard. checked_horizon refuses a
-- negative, infinite or NaN horizon at all nine sampler entry points, and the
-- fixtures under tests_neg/stochastic/ pin that refusal one file per sampler.
-- What those files cannot establish is that the guard stops where it should:
-- a guard written as `gt(t, 0.0)`, or one that rejected the sign bit of
-- `-0.0`, would pass every one of them while refusing a legitimate input.
--
-- `t = 0` is a legitimate horizon: no time passes, so every terminal value is
-- s0 exactly, up to the log/exp round trip each sampler performs. `t = -0.0`
-- is the same horizon with its sign bit set, which is exactly the value that
-- let shoals#139 through the `lambda * t` rate guard -- `gte(-0.0, 0.0)` is
-- true, `sqrt(-0.0)` is `-0.0`, and no answer changes. Both must be ADMITTED,
-- and the tolerance below is a round-trip tolerance, not a Monte-Carlo one:
-- these assertions do not depend on the draws at all.
def zero_horizon_template() -> tensor[8, f32] = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(8, i64))))
def path_sum[n](xs: tensor[n, f32]) -> f32 = tensor_to_scalar(sum(xs, 0))
def test_zero_horizon_is_admitted_by_every_sampler() -> unit ! { Test } = {
  z = cast(0.0, f32)
  s0 = cast(100.0, f32)
  tol = cast(0.05, f32)
  eight_s0 = cast(800.0, f32)
  _ = assert_close(path_sum(gbm_terminal(key_from_seed(7i64), zero_horizon_template(), s0, cast(0.05, f32), cast(0.2, f32), z)), eight_s0, tol, "gbm_terminal at t = 0 must return s0 for every path")
  _ = assert_close(path_sum(gbm_path(key_from_seed(7i64), zero_horizon_template(), s0, cast(0.05, f32), cast(0.2, f32), z)), eight_s0, tol, "gbm_path at t = 0 must return s0 at every step")
  _ = assert_close(gbm_paths_antithetic_terminal_mean(key_from_seed(7i64), zero_horizon_template(), s0, cast(0.05, f32), cast(0.2, f32), z), s0, tol, "gbm_paths_antithetic_terminal_mean at t = 0 must return s0")
  _ = assert_close(path_sum(merton_jump_terminal(key_from_seed(7i64), zero_horizon_template(), zero_horizon_template(), s0, cast(0.05, f32), cast(0.2, f32), cast(4.0, f32), cast(0.1, f32), cast(0.2, f32), z)), eight_s0, tol, "merton_jump_terminal at t = 0 must return s0 for every path")
  _ = assert_close(path_sum(sto_kou_jump_terminal(key_from_seed(7i64), zero_horizon_template(), zero_horizon_template(), s0, cast(0.05, f32), cast(0.2, f32), cast(4.0, f32), cast(0.5, f32), cast(3.0, f32), cast(4.0, f32), z)), eight_s0, tol, "sto_kou_jump_terminal at t = 0 must return s0 for every path")
  legs = correlated_gbm_terminal_2d(key_from_seed(7i64), zero_horizon_template(), zero_horizon_template(), s0, cast(90.0, f32), cast(0.05, f32), cast(0.04, f32), cast(0.2, f32), cast(0.3, f32), cast(0.5, f32), z)
  _ = assert_close(path_sum(legs.0), eight_s0, tol, "correlated_gbm_terminal_2d at t = 0 must return s0_x on the x leg")
  _ = assert_close(path_sum(legs.1), cast(720.0, f32), tol, "correlated_gbm_terminal_2d at t = 0 must return s0_y on the y leg")
  heston_one = heston_qe_terminal(key_from_seed(7i64), s0, cast(0.04, f32), cast(0.05, f32), cast(1.5, f32), cast(0.04, f32), cast(0.3, f32), cast(-0.5, f32), z, cast(8, i64))
  _ = assert_close(heston_one.0, s0, tol, "heston_qe_terminal at t = 0 must return s0")
  heston_many = heston_qe_paths_terminal(key_from_seed(7i64), zero_horizon_template(), s0, cast(0.04, f32), cast(0.05, f32), cast(1.5, f32), cast(0.04, f32), cast(0.3, f32), cast(-0.5, f32), z, cast(8, i64))
  _ = assert_close(path_sum(heston_many.0), eight_s0, tol, "heston_qe_paths_terminal at t = 0 must return s0 for every path")
  step = heston_qe_step(log(s0), cast(0.04, f32), cast(0.04, f32), cast(0.05, f32), cast(1.5, f32), cast(0.04, f32), cast(0.3, f32), cast(-0.5, f32), z, cast(0.3, f32), cast(-0.2, f32), cast(0.4, f32))
  assert_close(exp(step.0), s0, tol, "heston_qe_step at dt = 0 must be the identity step on log-spot")
}
def test_negative_zero_horizon_is_admitted_and_changes_no_answer() -> unit ! { Test } = {
  neg_z = neg(cast(0.0, f32))
  s0 = cast(100.0, f32)
  tol = cast(0.05, f32)
  eight_s0 = cast(800.0, f32)
  _ = assert_close(path_sum(gbm_terminal(key_from_seed(7i64), zero_horizon_template(), s0, cast(0.05, f32), cast(0.2, f32), neg_z)), eight_s0, tol, "gbm_terminal at t = -0.0 must return s0; -0.0 is a zero horizon with its sign bit set")
  _ = assert_close(path_sum(merton_jump_terminal(key_from_seed(7i64), zero_horizon_template(), zero_horizon_template(), s0, cast(0.05, f32), cast(0.2, f32), cast(4.0, f32), cast(0.1, f32), cast(0.2, f32), neg_z)), eight_s0, tol, "merton_jump_terminal at t = -0.0 must return s0; this is the value whose -0.0 product let shoals#139 through the rate guard")
  _ = assert_close(path_sum(sto_kou_jump_terminal(key_from_seed(7i64), zero_horizon_template(), zero_horizon_template(), s0, cast(0.05, f32), cast(0.2, f32), cast(4.0, f32), cast(0.5, f32), cast(3.0, f32), cast(4.0, f32), neg_z)), eight_s0, tol, "sto_kou_jump_terminal at t = -0.0 must return s0; this is the value whose -0.0 product let shoals#139 through the rate guard")
  legs = correlated_gbm_terminal_2d(key_from_seed(7i64), zero_horizon_template(), zero_horizon_template(), s0, cast(90.0, f32), cast(0.05, f32), cast(0.04, f32), cast(0.2, f32), cast(0.3, f32), cast(0.5, f32), neg_z)
  _ = assert_close(add(path_sum(legs.0), path_sum(legs.1)), cast(1520.0, f32), tol, "correlated_gbm_terminal_2d at t = -0.0 must return s0_x and s0_y")
  heston_many = heston_qe_paths_terminal(key_from_seed(7i64), zero_horizon_template(), s0, cast(0.04, f32), cast(0.05, f32), cast(1.5, f32), cast(0.04, f32), cast(0.3, f32), cast(-0.5, f32), neg_z, cast(8, i64))
  assert_close(path_sum(heston_many.0), eight_s0, tol, "heston_qe_paths_terminal at t = -0.0 must return s0 for every path")
}
