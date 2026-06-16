module Shoals.Tests.XvaFvaKva
import Std.Test (assert_close, assert_true)
import Shoals.Xva (fva, kva)
def test_fva_zero_funding_spread_zero() -> unit ! { Test } = {
  time_grid = to_tensor([cast(1.0, f32), cast(2.0, f32), cast(3.0, f32)])
  epe = to_tensor([cast(10.0, f32), cast(15.0, f32), cast(12.0, f32)])
  out = fva(time_grid, epe, cast(0.0, f32), cast(0.03, f32))
  assert_close(out, cast(0.0, f32), cast(0.000001, f32), "FVA = 0 when funding_spread = 0")
}
def test_fva_increasing_in_funding_spread() -> unit ! { Test } = {
  time_grid = to_tensor([cast(1.0, f32), cast(2.0, f32), cast(3.0, f32)])
  epe = to_tensor([cast(10.0, f32), cast(15.0, f32), cast(12.0, f32)])
  fva_low = fva(time_grid, epe, cast(0.005, f32), cast(0.03, f32))
  fva_high = fva(time_grid, epe, cast(0.02, f32), cast(0.03, f32))
  assert_true(gt(fva_high, fva_low), "FVA monotone-increasing in funding_spread")
}
def test_fva_increasing_in_horizon() -> unit ! { Test } = {
  short_grid = to_tensor([cast(0.0, f32), cast(1.0, f32), cast(2.0, f32)])
  short_epe = to_tensor([cast(10.0, f32), cast(10.0, f32), cast(10.0, f32)])
  long_grid = to_tensor([cast(0.0, f32), cast(1.0, f32), cast(2.0, f32), cast(3.0, f32), cast(4.0, f32)])
  long_epe = to_tensor([cast(10.0, f32), cast(10.0, f32), cast(10.0, f32), cast(10.0, f32), cast(10.0, f32)])
  fva_short = fva(short_grid, short_epe, cast(0.01, f32), cast(0.03, f32))
  fva_long = fva(long_grid, long_epe, cast(0.01, f32), cast(0.03, f32))
  assert_true(gt(fva_long, fva_short), "longer horizon at same exposure -> larger FVA")
}
def test_kva_zero_cost_zero() -> unit ! { Test } = {
  time_grid = to_tensor([cast(1.0, f32), cast(2.0, f32), cast(3.0, f32)])
  ead = to_tensor([cast(100.0, f32), cast(120.0, f32), cast(90.0, f32)])
  out = kva(time_grid, ead, cast(0.0, f32), cast(0.08, f32), cast(0.03, f32))
  assert_close(out, cast(0.0, f32), cast(0.000001, f32), "KVA = 0 when cost_of_capital = 0")
}
def test_kva_increasing_in_capital_weight() -> unit ! { Test } = {
  time_grid = to_tensor([cast(1.0, f32), cast(2.0, f32), cast(3.0, f32)])
  ead = to_tensor([cast(100.0, f32), cast(120.0, f32), cast(90.0, f32)])
  kva_low = kva(time_grid, ead, cast(0.1, f32), cast(0.04, f32), cast(0.03, f32))
  kva_high = kva(time_grid, ead, cast(0.1, f32), cast(0.08, f32), cast(0.03, f32))
  assert_true(gt(kva_high, kva_low), "KVA monotone-increasing in regulatory_capital_weight")
}
def test_kva_additivity_in_capital_weight() -> unit ! { Test } = {
  time_grid = to_tensor([cast(1.0, f32), cast(2.0, f32), cast(3.0, f32)])
  ead = to_tensor([cast(100.0, f32), cast(120.0, f32), cast(90.0, f32)])
  kva_w = kva(time_grid, ead, cast(0.1, f32), cast(0.04, f32), cast(0.03, f32))
  kva_2w = kva(time_grid, ead, cast(0.1, f32), cast(0.08, f32), cast(0.03, f32))
  expected = mul(cast(2.0, f32), kva_w)
  assert_close(kva_2w, expected, cast(0.0001, f32), "doubling regulatory_capital_weight doubles KVA (linearity)")
}
