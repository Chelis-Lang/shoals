module Shoals.Tests.XvaStochasticRecovery
import Std.Test (assert_close, assert_true)
import Shoals.Xva (xva_cva_stochastic_recovery, cva_constant_hazard)
def test_stochastic_recovery_concentrated_equals_deterministic() -> unit ! { Test } = {
  time_grid = to_tensor([cast(1.0, f32), cast(2.0, f32), cast(3.0, f32)])
  epe = to_tensor([cast(10.0, f32), cast(15.0, f32), cast(12.0, f32)])
  hazard = cast(0.03, f32)
  disc = cast(0.03, f32)
  cva_det = cva_constant_hazard(copy(time_grid), copy(epe), hazard, cast(0.5, f32), disc)
  cva_stoch = with seed(42) { xva_cva_stochastic_recovery(time_grid, epe, hazard, cast(50.0, f32), cast(50.0, f32), disc, cast(256, int64)) }
  diff = sub(cva_stoch, cva_det)
  abs_diff = if lt(diff, cast(0.0, f32)) then neg(diff) else diff
  se_mc =
    cva_det
    |> mul(cast(0.5, f32))
    |> div(sqrt(cast(50.0, f32)
  |> mul(cast(2.0, f32))
  |> add(cast(1.0, f32))
  |> mul(cast(256.0, f32))))
  tol = mul(cast(3.0, f32), se_mc)
  assert_true(lt(abs_diff, tol), "concentrated Beta(50,50) recovery: stoch CVA within 3 SE_mc of det CVA at R=0.5")
}
def test_stochastic_recovery_uniform_wider_variance() -> unit ! { Test } = {
  time_grid = to_tensor([cast(1.0, f32), cast(2.0, f32), cast(3.0, f32)])
  epe = to_tensor([cast(10.0, f32), cast(15.0, f32), cast(12.0, f32)])
  hazard = cast(0.03, f32)
  disc = cast(0.03, f32)
  cva_det = cva_constant_hazard(copy(time_grid), copy(epe), hazard, cast(0.5, f32), disc)
  cva_stoch = with seed(7) { xva_cva_stochastic_recovery(time_grid, epe, hazard, cast(1.0, f32), cast(1.0, f32), disc, cast(256, int64)) }
  diff = sub(cva_stoch, cva_det)
  abs_diff = if lt(diff, cast(0.0, f32)) then neg(diff) else diff
  se_mc =
    cva_det
    |> mul(cast(0.5, f32))
    |> div(sqrt(cast(3.0, f32) |> mul(cast(256.0, f32))))
  tol = mul(cast(3.0, f32), se_mc)
  assert_true(lt(abs_diff, tol), "uniform Beta(1,1) recovery: mean CVA within 3 SE_mc of det CVA at R=0.5")
}
def test_stochastic_recovery_zero_hazard_zero_cva() -> unit ! { Test } = {
  time_grid = to_tensor([cast(1.0, f32), cast(2.0, f32), cast(3.0, f32)])
  epe = to_tensor([cast(10.0, f32), cast(15.0, f32), cast(12.0, f32)])
  cva = with seed(13) { xva_cva_stochastic_recovery(time_grid, epe, cast(0.0, f32), cast(2.0, f32), cast(5.0, f32), cast(0.03, f32), cast(64, int64)) }
  assert_close(cva, cast(0.0, f32), cast(0.000001, f32), "hazard = 0 -> all paths give 0 -> MC mean = 0 exactly")
}
