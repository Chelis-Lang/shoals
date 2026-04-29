module Shoals.Tests.Risk
import Std.Test (assert_close)
import Shoals.Risk (parametric_var, parametric_cvar, historical_var, historical_cvar, empirical_loss_quantile)
def test_parametric_var_simple() -> unit ! { Test } = {
  losses = to_tensor([cast(-2.0, f32), cast(-1.0, f32), cast(0.0, f32), cast(1.0, f32), cast(2.0, f32)])
  v = parametric_var(losses, cast(0.95, f32))
  assert_close(v, cast(2.6005, f32), cast(0.01, f32), "parametric VaR ~ 2.60")
}
def test_parametric_cvar_exceeds_var() -> unit ! { Test } = {
  losses = to_tensor([cast(-2.0, f32), cast(-1.0, f32), cast(0.0, f32), cast(1.0, f32), cast(2.0, f32)])
  cvar = parametric_cvar(losses, cast(0.95, f32))
  assert_close(cvar, cast(3.2613, f32), cast(0.01, f32), "parametric CVaR ~ 3.26")
}
def test_historical_var_quantile() -> unit ! { Test } = {
  losses = to_tensor(map(fn (i: int64) -> cast(cast(i, int32), f32), range(cast(0, int64), cast(101, int64))))
  v = historical_var(losses, cast(0.95, f32))
  assert_close(v, cast(95.0, f32), cast(0.001, f32), "hist VaR == 95.0")
}
def test_historical_cvar_tail_mean() -> unit ! { Test } = {
  losses = to_tensor(map(fn (i: int64) -> cast(cast(i, int32), f32), range(cast(0, int64), cast(101, int64))))
  cvar = historical_cvar(losses, cast(0.95, f32))
  assert_close(cvar, cast(97.5, f32), cast(0.001, f32), "hist CVaR == 97.5")
}
def test_empirical_quantile_median() -> unit ! { Test } = {
  losses = to_tensor(map(fn (i: int64) -> cast(cast(i, int32), f32), range(cast(0, int64), cast(101, int64))))
  q = empirical_loss_quantile(losses, cast(0.5, f32))
  assert_close(q, cast(50.0, f32), cast(0.001, f32), "median == 50.0")
}
def test_historical_cvar_full_confidence() -> unit ! { Test } = {
  losses = to_tensor([cast(1.0, f32), cast(2.0, f32), cast(3.0, f32)])
  cvar = historical_cvar(losses, cast(1.0, f32))
  assert_close(cvar, cast(3.0, f32), cast(0.001, f32), "100%-CVaR collapses to max")
}
