module Shoals.Tests.Heston
import Std.Test (assert_close, assert_true)
import Nautilus.Stats (mean_vec)
import Shoals.Stochastic (heston_qe_terminal, heston_qe_paths_terminal)
def to01(b: bool) -> f32 = if b then cast(1.0, f32) else cast(0.0, f32)
def abs_f32(x: f32) -> f32 = if lt(x, cast(0.0, f32)) then neg(x) else x
def test_heston_qe_variance_positivity_single_path() -> unit ! { Test } = {
  out = with seed(7) { heston_qe_terminal(cast(100.0, f32), cast(0.04, f32), cast(0.0, f32), cast(0.5, f32), cast(0.04, f32), cast(1.0, f32), cast(-0.9, f32), cast(5.0, f32), cast(1000, int64)) }
  min_v = out.2
  ok = gte(min_v, cast(0.0, f32))
  assert_close(to01(ok), cast(1.0, f32), cast(0.001, f32), "Heston QE variance min along path stays non-negative over 1000 steps under Feller-violating params")
}
def test_heston_qe_variance_positivity_batched() -> unit ! { Test } = {
  template = to_tensor(map(fn (i: int64) -> cast(0.0, f32), range(cast(0, int64), cast(16, int64))))
  out = with seed(11) { heston_qe_paths_terminal(template, cast(100.0, f32), cast(0.04, f32), cast(0.0, f32), cast(0.5, f32), cast(0.04, f32), cast(1.0, f32), cast(-0.9, f32), cast(5.0, f32), cast(260, int64)) }
  min_vs = to_list(out.2)
  init = true
  all_nonneg = fold(fn (acc: bool, mv: f32) -> and(acc, gte(mv, cast(0.0, f32))), init, min_vs)
  assert_true(all_nonneg, "every batched Heston QE path has non-negative min variance across 16 paths x 260 weekly steps under Feller-violating params")
}
def test_heston_qe_mean_reversion() -> unit ! { Test } = {
  template = to_tensor(map(fn (i: int64) -> cast(0.0, f32), range(cast(0, int64), cast(32, int64))))
  kappa = cast(0.5, f32)
  theta = cast(0.04, f32)
  v0 = cast(0.1, f32)
  big_t = cast(100.0, f32)
  out = with seed(13) { heston_qe_paths_terminal(template, cast(100.0, f32), v0, cast(0.0, f32), kappa, theta, cast(1.0, f32), cast(-0.9, f32), big_t, cast(200, int64)) }
  mean_v_t = mean_vec(out.1)
  diff = abs_f32(sub(mean_v_t, theta))
  assert_true(lt(diff, cast(0.05, f32)), "E[v_T] reverts toward theta after many mean-reversion timescales; tolerance 0.05 accommodates 32-path MC error of ~3-sigma at unconditional std sqrt(sigma^2*theta/(2*kappa)) ~ 0.2")
}
def test_heston_qe_low_volvol_deterministic_variance() -> unit ! { Test } = {
  template = to_tensor(map(fn (i: int64) -> cast(0.0, f32), range(cast(0, int64), cast(16, int64))))
  kappa = cast(0.5, f32)
  theta = cast(0.04, f32)
  v0 = cast(0.1, f32)
  big_t = cast(1.0, f32)
  out = with seed(17) { heston_qe_paths_terminal(template, cast(100.0, f32), v0, cast(0.0, f32), kappa, theta, cast(0.001, f32), cast(-0.9, f32), big_t, cast(200, int64)) }
  mean_v_t = mean_vec(out.1)
  expected = add(theta, mul(sub(v0, theta), exp(neg(mul(kappa, big_t)))))
  diff = abs_f32(sub(mean_v_t, expected))
  assert_true(lt(diff, cast(0.0001, f32)), "under tiny vol-of-vol (sigma=0.001), E[v_T] tracks deterministic CIR mean theta + (v0-theta)*exp(-kappa*T) within tight tolerance")
}
def test_heston_qe_zero_vol_deterministic_asset() -> unit ! { Test } = {
  s0 = cast(100.0, f32)
  mu = cast(0.05, f32)
  big_t = cast(2.0, f32)
  out = with seed(23) { heston_qe_terminal(s0, cast(0.0, f32), mu, cast(0.5, f32), cast(0.0, f32), cast(1.0, f32), cast(-0.9, f32), big_t, cast(100, int64)) }
  s_t = out.0
  expected = mul(s0, exp(mul(mu, big_t)))
  rel_err = div(abs_f32(sub(s_t, expected)), expected)
  assert_true(lt(rel_err, cast(0.001, f32)), "with v0=theta=0 the asset degenerates to deterministic S0*exp(mu*T)")
}
def test_heston_qe_log_return_mean() -> unit ! { Test } = {
  template = to_tensor(map(fn (i: int64) -> cast(0.0, f32), range(cast(0, int64), cast(64, int64))))
  s0 = cast(100.0, f32)
  v0 = cast(0.04, f32)
  mu = cast(0.0, f32)
  big_t = cast(0.25, f32)
  out = with seed(29) { heston_qe_paths_terminal(template, s0, v0, mu, cast(0.5, f32), cast(0.04, f32), cast(0.01, f32), cast(-0.9, f32), big_t, cast(64, int64)) }
  s_l = to_list(out.0)
  log_returns = to_tensor(map(fn (s: f32) -> log(div(s, s0)), s_l))
  mean_lr = mean_vec(log_returns)
  expected = mul(cast(-0.5, f32), mul(v0, big_t))
  diff = abs_f32(sub(mean_lr, expected))
  tol = cast(0.04, f32)
  assert_true(lt(diff, tol), "under risk-neutral mu=0 with low vol-of-vol, E[log(S_T/S_0)] tracks -0.5*v0*T at 64 paths within ~3-sigma tolerance (per-path std sqrt(v0*T)=0.1, sample-mean std=0.0125)")
}
