module Shoals.Tests.McRigorous
import Std.Test (assert_close)
import Nautilus.Stats (mean_vec, variance_vec)
import Shoals.Pricing (bs_call_scalar, mc_call_price)
import Shoals.Stochastic (gbm_terminal)
def test_mc_call_rigorous() -> unit ! { Test } = {
  template = to_tensor(map(fn (i: int64) -> cast(0.0, f32), range(cast(0, int64), cast(100000, int64))))
  mc_px = with seed(42i64) { mc_call_price(template, cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32)) }
  bs_px = bs_call_scalar(cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32))
  diff = sub(mc_px, bs_px)
  abs_diff = if lt(diff, cast(0.0, f32)) then neg(diff) else diff
  rel = div(abs_diff, bs_px)
  ok = lt(rel, cast(0.01, f32))
  assert_close(if ok then cast(1.0, f32) else cast(0.0, f32), cast(1.0, f32), cast(0.001, f32), "MC call within 1% of BS at 100K paths (spec-rigor gate)")
}
def test_gbm_terminal_rigorous() -> unit ! { Test } = {
  template = to_tensor(map(fn (i: int64) -> cast(0.0, f32), range(cast(0, int64), cast(100000, int64))))
  st = with seed(123i64) { gbm_terminal(template, cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32)) }
  m = mean_vec(copy(st))
  expected_mean = mul(cast(100.0, f32), exp(mul(cast(0.05, f32), cast(1.0, f32))))
  diff_m = sub(m, expected_mean)
  abs_dm = if lt(diff_m, cast(0.0, f32)) then neg(diff_m) else diff_m
  rel_m = div(abs_dm, expected_mean)
  mean_ok = lt(rel_m, cast(0.01, f32))
  v = variance_vec(st, cast(1, int64))
  s0_sq = mul(cast(100.0, f32), cast(100.0, f32))
  expected_var = mul(s0_sq, mul(exp(mul(cast(2.0, f32), mul(cast(0.05, f32), cast(1.0, f32)))), sub(exp(mul(mul(cast(0.2, f32), cast(0.2, f32)), cast(1.0, f32))), cast(1.0, f32))))
  vdiff = sub(v, expected_var)
  abs_vdiff = if lt(vdiff, cast(0.0, f32)) then neg(vdiff) else vdiff
  rel_v = div(abs_vdiff, expected_var)
  var_ok = lt(rel_v, cast(0.02, f32))
  both_ok = and(mean_ok, var_ok)
  assert_close(if both_ok then cast(1.0, f32) else cast(0.0, f32), cast(1.0, f32), cast(0.001, f32), "E[S_T] within 1% AND Var[S_T] within 2% at 100K paths (spec-rigor gate)")
}
