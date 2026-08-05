module Shoals.Tests.RiskExt
import Std.Test (assert_close, assert_true)
import Shoals.RiskExt (mc_var, mc_expected_shortfall, expected_shortfall_frtb_975, scenario_pnl_grid, kupiec_pof_statistic_simple)
def test_mc_var_at_95_simple_quantile() -> unit ! { Test } = {
  losses = to_tensor(map(fn (i: int64) -> cast(cast(i, int32), f32), range(cast(0, int64), cast(101, int64))))
  v = mc_var(losses, cast(0.95, f32))
  assert_close(v, cast(95.0, f32), cast(0.001, f32), "MC VaR @ 95% on 0..100 = 95")
}
def test_mc_es_at_95_tail_mean() -> unit ! { Test } = {
  losses = to_tensor(map(fn (i: int64) -> cast(cast(i, int32), f32), range(cast(0, int64), cast(101, int64))))
  es = mc_expected_shortfall(losses, cast(0.95, f32))
  assert_close(es, cast(97.5, f32), cast(0.001, f32), "MC ES @ 95% on 0..100 = mean(95..100) = 97.5")
}
def test_es_frtb_975_matches_es_at_975() -> unit ! { Test } = {
  losses = to_tensor(map(fn (i: int64) -> cast(cast(i, int32), f32), range(cast(0, int64), cast(1001, int64))))
  es = expected_shortfall_frtb_975(losses)
  es_explicit = mc_expected_shortfall(losses, cast(0.975, f32))
  assert_close(es, es_explicit, cast(0.001, f32), "FRTB 97.5% ES matches explicit ES @ 97.5%")
}
def test_es_at_full_confidence_collapses_to_max_loss() -> unit ! { Test } = {
  losses = to_tensor([cast(1.0, f32), cast(3.0, f32), cast(7.0, f32)])
  es = mc_expected_shortfall(losses, cast(1.0, f32))
  assert_close(es, cast(7.0, f32), cast(0.001, f32), "ES at 100% conf = max loss")
}
def test_scenario_pnl_grid_linear() -> unit ! { Test } = {
  shifts = to_tensor([cast(-0.02, f32), cast(-0.01, f32), cast(0.0, f32), cast(0.01, f32), cast(0.02, f32)])
  pnls = scenario_pnl_grid(cast(100.0, f32), shifts, cast(50.0, f32))
  pnls_l = to_list(pnls)
  v_mid = index(pnls_l, cast(2, int64))
  v_up = index(pnls_l, cast(4, int64))
  v_dn = index(pnls_l, cast(0, int64))
  _ = assert_close(v_mid, cast(100.0, f32), cast(1e-6, f32), "base PnL at 0 shift")
  _ = assert_close(v_up, cast(101.0, f32), cast(1e-6, f32), "+2% shift * 50/unit = +1.0")
  assert_close(v_dn, cast(99.0, f32), cast(1e-6, f32), "-2% shift * 50/unit = -1.0")
}
def test_kupiec_pof_at_expected_rate_near_zero() -> unit ! { Test } = {
  stat = kupiec_pof_statistic_simple(cast(5, int64), cast(100, int64), cast(0.05, f32))
  assert_close(stat, cast(0.0, f32), cast(0.001, f32), "Kupiec POF at observed=expected: LR statistic = 0")
}
def test_kupiec_pof_far_from_expected_positive() -> unit ! { Test } = {
  stat = kupiec_pof_statistic_simple(cast(20, int64), cast(100, int64), cast(0.05, f32))
  assert_true(gt(stat, cast(5.0, f32)), "Kupiec POF for 20/100 vs expected 5%: LR statistic positive")
}
def test_mc_var_99_strict_tail() -> unit ! { Test } = {
  losses = to_tensor(map(fn (i: int64) -> cast(cast(i, int32), f32), range(cast(0, int64), cast(1001, int64))))
  v_95 = mc_var(losses, cast(0.95, f32))
  v_99 = mc_var(losses, cast(0.99, f32))
  assert_true(gt(v_99, v_95), "VaR @ 99% > VaR @ 95% (stricter quantile)")
}
def test_mc_es_dominates_var() -> unit ! { Test } = {
  losses = to_tensor(map(fn (i: int64) -> cast(cast(i, int32), f32), range(cast(0, int64), cast(101, int64))))
  v = mc_var(losses, cast(0.95, f32))
  es = mc_expected_shortfall(losses, cast(0.95, f32))
  assert_true(gte(es, v), "ES >= VaR at same confidence (coherent)")
}
