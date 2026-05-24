module Shoals.RiskExt
import Nautilus.Stats (quantile_vec, mean_vec)
import Shoals.Risk (historical_var, historical_cvar)
export (mc_var, mc_expected_shortfall, expected_shortfall_frtb_975, scenario_pnl_grid, kupiec_pof_statistic_simple)
def mc_var[n](losses: tensor[n, f32], confidence: f32) -> f32 = historical_var(losses, confidence)
def mc_expected_shortfall[n](losses: tensor[n, f32], confidence: f32) -> f32 = historical_cvar(losses, confidence)
def expected_shortfall_frtb_975[n](losses: tensor[n, f32]) -> f32 = mc_expected_shortfall(losses, cast(0.975, f32))
def scenario_pnl_grid[m](base_value: f32, scenario_shifts: tensor[m, f32], pnl_per_unit_shift: f32) -> tensor[m, f32] = {
  shifts_l = to_list(copy(scenario_shifts))
  to_tensor(map(fn (shift: f32) -> add(base_value, mul(pnl_per_unit_shift, shift)), shifts_l))
}
def kupiec_pof_statistic_simple(num_violations: int64, total_observations: int64, expected_rate: f32) -> f32 = {
  n_v = cast(num_violations, f32)
  n_t = cast(total_observations, f32)
  observed_rate = if eq(n_t, cast(0.0, f32)) then cast(0.0, f32) else div(n_v, n_t)
  log_lik_h0 = mul(n_v, log(expected_rate))
  log_lik_h0_b = mul(sub(n_t, n_v), log(sub(cast(1.0, f32), expected_rate)))
  log_lik_h1 = if eq(n_v, cast(0.0, f32)) then cast(0.0, f32) else mul(n_v, log(observed_rate))
  log_lik_h1_b = if eq(observed_rate, cast(1.0, f32)) then cast(0.0, f32) else mul(sub(n_t, n_v), log(sub(cast(1.0, f32), observed_rate)))
  mul(cast(-2.0, f32), sub(add(log_lik_h0, log_lik_h0_b), add(log_lik_h1, log_lik_h1_b)))
}
