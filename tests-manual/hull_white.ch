module Shoals.Tests.HullWhite
import Std.Test (assert_true)
import Shoals.HullWhite (hw1f_path)
def abs_f32(x: f32) -> f32 = if lt(x, cast(0.0, f32)) then neg(x) else x
def test_hw1f_zero_vol_deterministic() -> unit ! { Test } = {
  template = to_tensor(map(fn (i: int64) -> cast(0.0, f32), range(cast(0, int64), cast(1, int64))))
  r0 = cast(0.05, f32)
  theta_bar = cast(0.02, f32)
  a = cast(0.4, f32)
  sigma = cast(0.0, f32)
  big_t = cast(3.0, f32)
  n_steps = cast(4000, int64)
  paths = with seed(19) { hw1f_path(template, r0, a, theta_bar, sigma, big_t, n_steps) }
  r_terminal = index(to_list(paths), cast(0, int64))
  expected = add(theta_bar, mul(sub(r0, theta_bar), exp(neg(mul(a, big_t)))))
  rel_err = div(abs_f32(sub(r_terminal, expected)), abs_f32(expected))
  assert_true(lt(rel_err, cast(0.0001, f32)), "HW1F sigma=0 reduces to deterministic ODE r_T = theta_bar + (r_0 - theta_bar) * exp(-a*T) within 1e-4 relative error")
}
