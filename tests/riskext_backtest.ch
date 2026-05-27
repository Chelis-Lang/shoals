module Shoals.Tests.RiskextBacktest
import Std.Test (assert_close, assert_true, assert_false)
import Shoals.RiskExt (re_christoffersen_cc, re_acerbi_szekely_es_z1, re_acerbi_szekely_es_z2)
def test_christoffersen_clustered_exceptions_rejects() -> unit ! { Test } = {
  idxs = range(cast(0, int64), cast(250, int64))
  losses = to_tensor(map(fn (i: int64) -> if and(gte(i, cast(100, int64)), lt(i, cast(110, int64))) then cast(2.0, f32) else cast(0.0, f32), idxs))
  vars = to_tensor(map(fn (i: int64) -> {
    _ = i
    cast(1.0, f32)
  }, range(cast(0, int64), cast(250, int64))))
  result = re_christoffersen_cc(losses, vars, cast(0.05, f32))
  lr_cc = result.0
  reject = result.1
  _ = assert_true(gt(lr_cc, cast(5.991, f32)), "Clustered exceptions: LR_cc > chi2(2)_0.95 = 5.991")
  assert_true(reject, "Clustered exceptions: reject=true at 5% significance")
}
def test_christoffersen_evenly_spaced_exceptions_no_reject() -> unit ! { Test } = {
  idxs = range(cast(0, int64), cast(250, int64))
  losses = to_tensor(map(fn (i: int64) -> if eq(mod(i, cast(25, int64)), cast(12, int64)) then cast(2.0, f32) else cast(0.0, f32), idxs))
  vars = to_tensor(map(fn (i: int64) -> {
    _ = i
    cast(1.0, f32)
  }, range(cast(0, int64), cast(250, int64))))
  result = re_christoffersen_cc(losses, vars, cast(0.05, f32))
  reject = result.1
  assert_false(reject, "Evenly-spaced exceptions (10/250): independence holds, no reject")
}
def test_christoffersen_no_exceptions_finite_lr() -> unit ! { Test } = {
  losses = to_tensor(map(fn (i: int64) -> {
    _ = i
    cast(0.0, f32)
  }, range(cast(0, int64), cast(250, int64))))
  vars = to_tensor(map(fn (i: int64) -> {
    _ = i
    cast(1.0, f32)
  }, range(cast(0, int64), cast(250, int64))))
  result = re_christoffersen_cc(losses, vars, cast(0.05, f32))
  lr_cc = result.0
  is_finite = eq(lr_cc, lr_cc)
  is_bounded = lt(lr_cc, cast(1000000.0, f32))
  _ = assert_true(is_finite, "No exceptions: LR_cc is finite (graceful zero-exception handling)")
  _ = assert_true(is_bounded, "No exceptions: LR_cc is bounded (no inf from 0*log(0))")
  assert_true(gte(lr_cc, cast(0.0, f32)), "No exceptions: LR_cc >= 0 (LR statistic non-negative)")
}
def test_acerbi_szekely_z1_underforecast_negative() -> unit ! { Test } = {
  losses = to_tensor(map(fn (i: int64) -> {
    _ = i
    cast(1.5, f32)
  }, range(cast(0, int64), cast(100, int64))))
  vars = to_tensor(map(fn (i: int64) -> {
    _ = i
    cast(0.5, f32)
  }, range(cast(0, int64), cast(100, int64))))
  es = to_tensor(map(fn (i: int64) -> {
    _ = i
    cast(1.0, f32)
  }, range(cast(0, int64), cast(100, int64))))
  z1 = re_acerbi_szekely_es_z1(losses, vars, es, cast(0.025, f32))
  assert_true(lt(z1, cast(0.0, f32)), "Under-forecast (loss 50% above ES): Z1 < 0")
}
def test_acerbi_szekely_z1_correct_forecast_near_zero() -> unit ! { Test } = {
  losses = to_tensor(map(fn (i: int64) -> {
    _ = i
    cast(1.0, f32)
  }, range(cast(0, int64), cast(100, int64))))
  vars = to_tensor(map(fn (i: int64) -> {
    _ = i
    cast(0.5, f32)
  }, range(cast(0, int64), cast(100, int64))))
  es = to_tensor(map(fn (i: int64) -> {
    _ = i
    cast(1.0, f32)
  }, range(cast(0, int64), cast(100, int64))))
  z1 = re_acerbi_szekely_es_z1(losses, vars, es, cast(0.025, f32))
  assert_close(z1, cast(0.0, f32), cast(0.01, f32), "Correct ES forecast: Z1 ≈ 0")
}
def test_acerbi_szekely_z2_underforecast_negative() -> unit ! { Test } = {
  losses = to_tensor(map(fn (i: int64) -> {
    _ = i
    cast(1.5, f32)
  }, range(cast(0, int64), cast(100, int64))))
  vars = to_tensor(map(fn (i: int64) -> {
    _ = i
    cast(0.5, f32)
  }, range(cast(0, int64), cast(100, int64))))
  es = to_tensor(map(fn (i: int64) -> {
    _ = i
    cast(1.0, f32)
  }, range(cast(0, int64), cast(100, int64))))
  z2 = re_acerbi_szekely_es_z2(losses, vars, es, cast(0.025, f32))
  assert_true(lt(z2, cast(0.0, f32)), "Under-forecast (all-exception, n*alpha=2.5): Z2 < 0 (sum_ratio/denom = 150/2.5 = 60, Z2 = 1-60 = -59)")
}
