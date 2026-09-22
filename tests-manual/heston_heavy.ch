module Shoals.Tests.HestonHeavy
import Std.Test (assert_close, assert_true)
import Nautilus.Stats (mean_vec)
import Shoals.Stochastic (heston_qe_terminal, heston_qe_paths_terminal)
import Shoals.Heston (heston_call_carr_madan_panels, heston_put_carr_madan_panels, heston_call_lewis_panels, heston_call_lipton_panels, heston_put_lipton_panels)
def to01(b: bool) -> f32 = if b then cast(1.0, f32) else cast(0.0, f32)
def abs_f32(x: f32) -> f32 = if lt(x, cast(0.0, f32)) then neg(x) else x
def test_heston_qe_variance_positivity_single_path() -> unit ! { Test } = {
  out = with seed(7i64) { heston_qe_terminal(cast(100.0, f32), cast(0.04, f32), cast(0.0, f32), cast(0.5, f32), cast(0.04, f32), cast(1.0, f32), cast(-0.9, f32), cast(5.0, f32), cast(1000, i64)) }
  min_v = out.2
  ok = gte(min_v, cast(0.0, f32))
  assert_close(to01(ok), cast(1.0, f32), cast(0.001, f32), "Heston QE variance min along path stays non-negative over 1000 steps under Feller-violating params")
}
def test_heston_qe_variance_positivity_batched() -> unit ! { Test } = {
  template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(16, i64))))
  out = with seed(11i64) { heston_qe_paths_terminal(template, cast(100.0, f32), cast(0.04, f32), cast(0.0, f32), cast(0.5, f32), cast(0.04, f32), cast(1.0, f32), cast(-0.9, f32), cast(5.0, f32), cast(260, i64)) }
  min_vs = to_list(out.2)
  init = true
  all_nonneg = fold(fn (acc: bool, mv: f32) -> and(acc, gte(mv, cast(0.0, f32))), init, min_vs)
  assert_true(all_nonneg, "every batched Heston QE path has non-negative min variance across 16 paths x 260 weekly steps under Feller-violating params")
}
def test_heston_qe_mean_reversion() -> unit ! { Test } = {
  template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(32, i64))))
  kappa = cast(0.5, f32)
  theta = cast(0.04, f32)
  v0 = cast(0.1, f32)
  big_t = cast(100.0, f32)
  out = with seed(13i64) { heston_qe_paths_terminal(template, cast(100.0, f32), v0, cast(0.0, f32), kappa, theta, cast(1.0, f32), cast(-0.9, f32), big_t, cast(200, i64)) }
  mean_v_t = mean_vec(out.1)
  diff = abs_f32(sub(mean_v_t, theta))
  assert_true(lt(diff, cast(0.05, f32)), "E[v_T] reverts toward theta after many mean-reversion timescales; tolerance 0.05 accommodates 32-path MC error of ~3-sigma at unconditional std sqrt(sigma^2*theta/(2*kappa)) ~ 0.2")
}
def test_heston_qe_low_volvol_deterministic_variance() -> unit ! { Test } = {
  template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(16, i64))))
  kappa = cast(0.5, f32)
  theta = cast(0.04, f32)
  v0 = cast(0.1, f32)
  big_t = cast(1.0, f32)
  out = with seed(17i64) { heston_qe_paths_terminal(template, cast(100.0, f32), v0, cast(0.0, f32), kappa, theta, cast(0.001, f32), cast(-0.9, f32), big_t, cast(200, i64)) }
  mean_v_t = mean_vec(out.1)
  expected = add(theta, mul(sub(v0, theta), exp(neg(mul(kappa, big_t)))))
  diff = abs_f32(sub(mean_v_t, expected))
  assert_true(lt(diff, cast(0.0001, f32)), "under tiny vol-of-vol (sigma=0.001), E[v_T] tracks deterministic CIR mean theta + (v0-theta)*exp(-kappa*T) within tight tolerance")
}
def test_heston_qe_log_return_mean() -> unit ! { Test } = {
  template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(64, i64))))
  s0 = cast(100.0, f32)
  v0 = cast(0.04, f32)
  mu = cast(0.0, f32)
  big_t = cast(0.25, f32)
  out = with seed(29i64) { heston_qe_paths_terminal(template, s0, v0, mu, cast(0.5, f32), cast(0.04, f32), cast(0.01, f32), cast(-0.9, f32), big_t, cast(64, i64)) }
  s_l = to_list(out.0)
  log_returns = to_tensor(map(fn (s: f32) -> log(div(s, s0)), s_l))
  mean_lr = mean_vec(log_returns)
  expected = mul(cast(-0.5, f32), mul(v0, big_t))
  diff = abs_f32(sub(mean_lr, expected))
  tol = cast(0.04, f32)
  assert_true(lt(diff, tol), "under risk-neutral mu=0 with low vol-of-vol, E[log(S_T/S_0)] tracks -0.5*v0*T at 64 paths within ~3-sigma tolerance (per-path std sqrt(v0*T)=0.1, sample-mean std=0.0125)")
}
def test_lewis_vs_carr_madan_agreement() -> unit ! { Test } = {
  cm = heston_call_carr_madan_panels(cast(100.0, f32), cast(100.0, f32), cast(1.0, f32), cast(0.0, f32), cast(0.04, f32), cast(0.5, f32), cast(0.04, f32), cast(1.0, f32), cast(-0.9, f32), cast(1.5, f32), cast(200.0, f32), cast(200, i64))
  lw = heston_call_lewis_panels(cast(100.0, f32), cast(100.0, f32), cast(1.0, f32), cast(0.0, f32), cast(0.04, f32), cast(0.5, f32), cast(0.04, f32), cast(1.0, f32), cast(-0.9, f32), cast(200.0, f32), cast(200, i64))
  diff = abs_f32(sub(lw, cm))
  assert_true(lt(diff, cast(0.01, f32)), "Lewis ATM call agrees with Carr-Madan within 0.01 absolute at the M-C stress config (f32 + panel quadrature floor)")
}
def test_lipton_vs_carr_madan_agreement() -> unit ! { Test } = {
  cm = heston_call_carr_madan_panels(cast(100.0, f32), cast(100.0, f32), cast(1.0, f32), cast(0.0, f32), cast(0.04, f32), cast(0.5, f32), cast(0.04, f32), cast(1.0, f32), cast(-0.9, f32), cast(1.5, f32), cast(200.0, f32), cast(200, i64))
  lp = heston_call_lipton_panels(cast(100.0, f32), cast(100.0, f32), cast(1.0, f32), cast(0.0, f32), cast(0.04, f32), cast(0.5, f32), cast(0.04, f32), cast(1.0, f32), cast(-0.9, f32), cast(200.0, f32), cast(200, i64))
  diff = abs_f32(sub(lp, cm))
  assert_true(lt(diff, cast(0.01, f32)), "Lipton ATM call agrees with Carr-Madan within 0.01 absolute at the M-C stress config (f32 + panel quadrature floor)")
}
def test_lewis_otm_clamp_nonnegative() -> unit ! { Test } = {
  p = heston_call_lewis_panels(cast(100.0, f32), cast(120.0, f32), cast(1.0, f32), cast(0.0, f32), cast(0.04, f32), cast(0.5, f32), cast(0.04, f32), cast(1.0, f32), cast(-0.9, f32), cast(25.0, f32), cast(200, i64))
  assert_true(gte(p, cast(0.0, f32)), "Lewis OTM K=120 at low u_max=25 clamped to non-negative")
}
def test_lipton_put_call_parity() -> unit ! { Test } = {
  call_p = heston_call_lipton_panels(cast(100.0, f32), cast(100.0, f32), cast(1.0, f32), cast(0.0, f32), cast(0.04, f32), cast(0.5, f32), cast(0.04, f32), cast(1.0, f32), cast(-0.9, f32), cast(200.0, f32), cast(200, i64))
  put_p = heston_put_lipton_panels(cast(100.0, f32), cast(100.0, f32), cast(1.0, f32), cast(0.0, f32), cast(0.04, f32), cast(0.5, f32), cast(0.04, f32), cast(1.0, f32), cast(-0.9, f32), cast(200.0, f32), cast(200, i64))
  diff = abs_f32(sub(call_p, put_p))
  assert_true(lt(diff, cast(0.001, f32)), "Lipton ATM put-call parity at r=0: call ≈ put")
}
