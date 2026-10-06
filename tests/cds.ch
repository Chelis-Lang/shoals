module Shoals.Tests.Cds
import Std.Test (assert_close, assert_true)
import Shoals.Cds (HazardCurve, hazard_curve_from_pillars, hazard_curve_pillars, cds_survival_from_hazards, cds_premium_leg_value, cds_protection_leg_value, cds_pv, cds_bootstrap_hazards)
def cds_flat_tenors_5() -> tensor[5, f32] = to_tensor([cast(1.0, f32), cast(2.0, f32), cast(3.0, f32), cast(5.0, f32), cast(10.0, f32)])
def cds_flat_hazards_5(h: f32) -> tensor[5, f32] = to_tensor([h, h, h, h, h])
-- The values are intentionally nonconstant: reversing the last two pairs
-- used to drop a pillar's contribution and return 0.73344696 instead.
def test_sorted_hazard_pillars_preserve_survival_and_reader_values() -> unit ! { Test } = {
  curve = hazard_curve_from_pillars(to_tensor([1.0f32, 2.0f32, 3.0f32]), to_tensor([0.01f32, 0.05f32, 0.2f32]))
  pillars = hazard_curve_pillars(curve)
  _ = assert_close(index(to_list(pillars.0), 2i64), 3.0f32, 1e-7f32, "last pillar time is readable")
  _ = assert_close(index(to_list(pillars.1), 1i64), 0.05f32, 1e-7f32, "interior hazard is readable")
  assert_close(cds_survival_from_hazards(hazard_curve_from_pillars(to_tensor([1.0f32, 2.0f32, 3.0f32]), to_tensor([0.01f32, 0.05f32, 0.2f32])), 2.5f32), 0.85214376f32, 1e-6f32, "ordered pillars retain their survival probability")
}
def cds_synthetic_spread_for_tenor(tenor: f32, recovery: f32, r: f32, freq: i64, times_l: List[f32], hazards_l: List[f32]) -> f32 = {
  curve_a = hazard_curve_from_pillars(to_tensor(times_l), to_tensor(hazards_l))
  pl = cds_premium_leg_value(cast(1.0, f32), tenor, freq, curve_a, r)
  curve_b = hazard_curve_from_pillars(to_tensor(times_l), to_tensor(hazards_l))
  prl = cds_protection_leg_value(tenor, recovery, curve_b, r)
  div(prl, pl)
}
def cds_build_synthetic_spreads(tenors_l: List[f32], recovery: f32, r: f32, freq: i64, times_l: List[f32], hazards_l: List[f32]) -> List[f32] = map(fn (tenor: f32) -> cds_synthetic_spread_for_tenor(tenor, recovery, r, freq, times_l, hazards_l), tenors_l)
def test_cds_pv_zero_at_market_spread() -> unit ! { Test } = {
  h = cast(0.02, f32)
  recovery = cast(0.4, f32)
  r = cast(0.03, f32)
  t_mat = cast(5.0, f32)
  freq = cast(4, i64)
  curve = hazard_curve_from_pillars(cds_flat_tenors_5(), cds_flat_hazards_5(h))
  spread_approx = mul(h, sub(cast(1.0, f32), recovery))
  pv = cds_pv(spread_approx, t_mat, freq, recovery, curve, r)
  pv_abs = if lt(pv, cast(0.0, f32)) then neg(pv) else pv
  assert_true(lt(pv_abs, cast(0.001, f32)), "|PV| < 10bp at textbook par spread h*(1-R) with quarterly premiums and monthly protection grid")
}
def test_cds_bootstrap_recovers_constant_hazard() -> unit ! { Test } = {
  h_true = cast(0.025, f32)
  recovery = cast(0.4, f32)
  r = cast(0.03, f32)
  freq = cast(4, i64)
  tenors = to_tensor([cast(1.0, f32), cast(2.0, f32), cast(3.0, f32), cast(5.0, f32), cast(7.0, f32)])
  hazards = to_tensor([h_true, h_true, h_true, h_true, h_true])
  tenors_l = to_list(copy(tenors))
  hazards_l = to_list(copy(hazards))
  spreads_l = cds_build_synthetic_spreads(tenors_l, recovery, r, freq, to_list(copy(tenors)), hazards_l)
  synthetic_spreads = to_tensor(spreads_l)
  recovered = cds_bootstrap_hazards(synthetic_spreads, tenors, recovery, r, freq)
  recovered_hs = hazard_curve_pillars(recovered).1
  recovered_hs_l = to_list(copy(recovered_hs))
  errors = map(fn (h_rec: f32) -> {
    diff = sub(h_rec, h_true)
    if lt(diff, cast(0.0, f32)) then neg(diff) else diff
  }, recovered_hs_l)
  max_err = fold(fn (acc: f32, e: f32) -> if gt(e, acc) then e else acc, cast(0.0, f32), errors)
  assert_true(lt(max_err, cast(0.0001, f32)), "constant-hazard bootstrap recovers each pillar within 1bp")
}
def test_cds_bootstrap_recovers_piecewise_hazard() -> unit ! { Test } = {
  recovery = cast(0.4, f32)
  r = cast(0.03, f32)
  freq = cast(4, i64)
  tenors = to_tensor([cast(1.0, f32), cast(2.0, f32), cast(3.0, f32), cast(5.0, f32), cast(10.0, f32)])
  true_hazards = to_tensor([cast(0.01, f32), cast(0.02, f32), cast(0.03, f32), cast(0.04, f32), cast(0.05, f32)])
  tenors_l = to_list(copy(tenors))
  true_hs_l = to_list(copy(true_hazards))
  spreads_l = cds_build_synthetic_spreads(tenors_l, recovery, r, freq, to_list(copy(tenors)), true_hs_l)
  synthetic_spreads = to_tensor(spreads_l)
  recovered = cds_bootstrap_hazards(synthetic_spreads, tenors, recovery, r, freq)
  recovered_hs = hazard_curve_pillars(recovered).1
  recovered_hs_l = to_list(copy(recovered_hs))
  true_hs_l2 = to_list(copy(true_hazards))
  pairs = zip(true_hs_l2, recovered_hs_l)
  errors = map(fn (e: (f32, f32)) -> {
    diff = sub(e.1, e.0)
    if lt(diff, cast(0.0, f32)) then neg(diff) else diff
  }, pairs)
  max_err = fold(fn (acc: f32, x: f32) -> if gt(x, acc) then x else acc, cast(0.0, f32), errors)
  assert_true(lt(max_err, cast(0.0005, f32)), "piecewise-hazard bootstrap recovers each pillar within 5bp")
}
def test_survival_decreasing() -> unit ! { Test } = {
  tenors = to_tensor([cast(1.0, f32), cast(3.0, f32), cast(5.0, f32), cast(7.0, f32), cast(10.0, f32)])
  hazards = to_tensor([cast(0.01, f32), cast(0.02, f32), cast(0.03, f32), cast(0.04, f32), cast(0.05, f32)])
  tenors_l = to_list(copy(tenors))
  hazards_l = to_list(copy(hazards))
  ts_sample = [cast(0.5, f32), cast(1.0, f32), cast(2.0, f32), cast(3.5, f32), cast(5.0, f32), cast(8.0, f32), cast(12.0, f32)]
  init = (cast(1.0, f32), true)
  out = fold(fn (state: (f32, bool), t: f32) -> {
    prev_q = state.0
    ok_so_far = state.1
    cand_curve = hazard_curve_from_pillars(to_tensor(tenors_l), to_tensor(hazards_l))
    q_now = cds_survival_from_hazards(cand_curve, t)
    still_ok = if ok_so_far then lt(q_now, prev_q) else false
    (q_now, still_ok)
  }, init, ts_sample)
  assert_true(out.1, "survival probability strictly decreasing with time on non-zero hazard curve")
}
