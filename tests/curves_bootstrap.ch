module Shoals.Tests.CurvesBootstrap
import Std.Test (assert_close, assert_true)
import Shoals.Curves (Instrument, YieldCurve, deposit, zero_coupon, cur_par_swap, instrument_tenor, instrument_market_price_or_rate, bootstrap_residual_at_pillar, bootstrap_multi, bootstrap_multi_curve)
def abs_f32(x: f32) -> f32 = if lt(x, cast(0.0, f32)) then neg(x) else x
def test_deposit_instrument_tenor() -> unit ! { Test } = {
  d = deposit(cast(0.25, f32), cast(0.04, f32))
  assert_close(instrument_tenor(d), cast(0.25, f32), cast(1e-6, f32), "deposit tenor preserved")
}
def test_zero_coupon_instrument_price() -> unit ! { Test } = {
  zc = zero_coupon(cast(1.0, f32), cast(0.95, f32))
  assert_close(instrument_market_price_or_rate(zc), cast(0.95, f32), cast(1e-6, f32), "zero-coupon price preserved")
}
def test_par_swap_instrument_par_rate() -> unit ! { Test } = {
  ps = cur_par_swap(cast(5.0, f32), cast(0.045, f32))
  assert_close(instrument_market_price_or_rate(ps), cast(0.045, f32), cast(1e-6, f32), "par swap rate preserved")
}
def test_bootstrap_single_deposit_reproduces_implied_zero() -> unit ! { Test } = {
  insts = [deposit(cast(1.0, f32), cast(0.05, f32))]
  out = bootstrap_multi(insts)
  rates = out.1
  z0 = index(rates, cast(0, int64))
  expected = div(neg(log(div(cast(1.0, f32), cast(1.05, f32)))), cast(1.0, f32))
  assert_close(z0, expected, cast(1e-6, f32), "1y deposit at 5% gives implied zero rate")
}
def test_bootstrap_single_zero_coupon_reproduces_implied_zero() -> unit ! { Test } = {
  insts = [zero_coupon(cast(2.0, f32), cast(0.9, f32))]
  out = bootstrap_multi(insts)
  rates = out.1
  z0 = index(rates, cast(0, int64))
  expected = div(neg(log(cast(0.9, f32))), cast(2.0, f32))
  assert_close(z0, expected, cast(1e-6, f32), "2y zero-coupon at 0.9 gives -log(0.9)/2")
}
def test_bootstrap_par_swap_reproduces_par_price() -> unit ! { Test } = {
  insts = [cur_par_swap(cast(1.0, f32), cast(0.05, f32))]
  out = bootstrap_multi(insts)
  rates = out.1
  z0 = index(rates, cast(0, int64))
  df_1y = exp(neg(mul(z0, cast(1.0, f32))))
  pv = add(mul(cast(0.05, f32), df_1y), df_1y)
  assert_close(pv, cast(1.0, f32), cast(0.0001, f32), "1y par swap at 5% bootstraps to PV = 1")
}
def test_bootstrap_two_pillar_consistency() -> unit ! { Test } = {
  insts = [zero_coupon(cast(1.0, f32), cast(0.95, f32)), zero_coupon(cast(2.0, f32), cast(0.9, f32))]
  out = bootstrap_multi(insts)
  rates = out.1
  z1 = index(rates, cast(0, int64))
  z2 = index(rates, cast(1, int64))
  exp_z1 = div(neg(log(cast(0.95, f32))), cast(1.0, f32))
  exp_z2 = div(neg(log(cast(0.9, f32))), cast(2.0, f32))
  _ = assert_close(z1, exp_z1, cast(1e-6, f32), "1y zero rate")
  assert_close(z2, exp_z2, cast(1e-6, f32), "2y zero rate independent")
}
def test_bootstrap_mixed_deposit_swap() -> unit ! { Test } = {
  insts = [deposit(cast(1.0, f32), cast(0.04, f32)), cur_par_swap(cast(2.0, f32), cast(0.045, f32))]
  out = bootstrap_multi(insts)
  times = out.0
  rates = out.1
  t1 = index(times, cast(1, int64))
  z2 = index(rates, cast(1, int64))
  z1 = index(rates, cast(0, int64))
  df1 = exp(neg(mul(z1, cast(1.0, f32))))
  df2 = exp(neg(mul(z2, cast(2.0, f32))))
  pv = add(mul(cast(0.045, f32), add(df1, df2)), df2)
  _ = assert_close(t1, cast(2.0, f32), cast(1e-6, f32), "2nd pillar tenor preserved")
  assert_close(pv, cast(1.0, f32), cast(0.0001, f32), "mixed deposit+swap bootstrap reproduces par swap PV")
}
def test_bootstrap_residual_at_pillar_zero_at_solution() -> unit ! { Test } = {
  inst = deposit(cast(1.0, f32), cast(0.05, f32))
  z_solved = div(neg(log(div(cast(1.0, f32), cast(1.05, f32)))), cast(1.0, f32))
  resid = bootstrap_residual_at_pillar(inst, [], [], z_solved)
  assert_close(resid, cast(0.0, f32), cast(1e-6, f32), "residual is zero at the solved rate")
}
def test_bootstrap_residual_at_pillar_nonzero_off_solution() -> unit ! { Test } = {
  inst = deposit(cast(1.0, f32), cast(0.05, f32))
  resid = bootstrap_residual_at_pillar(inst, [], [], cast(0.1, f32))
  assert_true(gt(abs_f32(resid), cast(0.01, f32)), "residual is nonzero at off-solution rate")
}
def test_bootstrap_multi_curve_constructs_yield_curve() -> unit ! { Test } = {
  insts = [zero_coupon(cast(1.0, f32), cast(0.95, f32)), zero_coupon(cast(2.0, f32), cast(0.9, f32))]
  template = to_tensor([cast(0.0, f32), cast(0.0, f32)])
  curve = bootstrap_multi_curve(insts, template)
  match curve with {
    | YieldCurve { kind: _, times: ts, rates: rs } => {
    ts_l = to_list(copy(ts))
    rs_l = to_list(copy(rs))
    t0 = index(ts_l, cast(0, int64))
    r1 = index(rs_l, cast(1, int64))
    _ = assert_close(t0, cast(1.0, f32), cast(1e-6, f32), "1st time pillar = 1y")
    assert_close(r1, div(neg(log(cast(0.9, f32))), cast(2.0, f32)), cast(1e-6, f32), "2nd rate matches zero-coupon implied")
  }
  }
}
