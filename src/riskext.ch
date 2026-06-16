module Shoals.RiskExt
import Nautilus.Stats (quantile_vec, mean_vec)
import Shoals.Risk (historical_var, historical_cvar)
export (mc_var, mc_expected_shortfall, expected_shortfall_frtb_975, scenario_pnl_grid, kupiec_pof_statistic_simple, re_frtb_ima_zone_at_day, re_frtb_ima_zone_rolling, re_christoffersen_cc, re_acerbi_szekely_es_z1, re_acerbi_szekely_es_z2)
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
def re_frtb_ima_zone_at_day(n_exceptions_window: int64) -> int64 = { if lte(n_exceptions_window, cast(4, int64)) then cast(0, int64) else if lte(n_exceptions_window, cast(9, int64)) then cast(1, int64) else cast(2, int64) }
def re_frtb_ima_window_count(indicators_l: List[f32], t_end: int64) -> int64 = {
  start_idx = sub(t_end, cast(249, int64))
  offsets = range(cast(0, int64), cast(250, int64))
  s = fold(fn (acc: f32, k: int64) -> add(acc, index(indicators_l, add(start_idx, k))), cast(0.0, f32), offsets)
  cast(s, int64)
}
def re_frtb_ima_zone_rolling[n, m](loss_series: tensor[n, f32], var_forecasts: tensor[n, f32]) -> tensor[m, int64] = {
  losses_l = to_list(copy(loss_series))
  vars_l = to_list(copy(var_forecasts))
  pairs = zip(losses_l, vars_l)
  indicators_l = map(fn (p: (f32, f32)) -> if gt(p.0, p.1) then cast(1.0, f32) else cast(0.0, f32), pairs)
  n_total = numel(copy(loss_series))
  m_out = if lt(n_total, cast(250, int64)) then cast(0, int64) else sub(n_total, cast(249, int64))
  out_idxs = range(cast(0, int64), m_out)
  to_tensor(map(fn (j: int64) -> {
    t_end = add(j, cast(249, int64))
    re_frtb_ima_zone_at_day(re_frtb_ima_window_count(indicators_l, t_end))
  }, out_idxs))
}
def re_christoffersen_exception_indicators[n](losses: tensor[n, f32], var_forecasts: tensor[n, f32]) -> List[f32] = {
  losses_l = to_list(copy(losses))
  vars_l = to_list(copy(var_forecasts))
  pairs = zip(losses_l, vars_l)
  map(fn (p: (f32, f32)) -> if gt(p.0, p.1) then cast(1.0, f32) else cast(0.0, f32), pairs)
}
def re_christoffersen_transition_counts(indicators_l: List[f32]) -> (f32, f32, f32, f32) = {
  n_total = len(indicators_l)
  init = (cast(0.0, f32), cast(0.0, f32), cast(0.0, f32), cast(0.0, f32))
  if lt(n_total, cast(2, int64)) then init else {
    idxs = range(cast(1, int64), n_total)
    fold(fn (state: (f32, f32, f32, f32), t: int64) -> {
      t00 = state.0
      t01 = state.1
      t10 = state.2
      t11 = state.3
      prev = index(indicators_l, sub(t, cast(1, int64)))
      curr = index(indicators_l, t)
      is_prev_one = eq(prev, cast(1.0, f32))
      is_curr_one = eq(curr, cast(1.0, f32))
      if is_prev_one then { if is_curr_one then (t00, t01, t10, add(t11, cast(1.0, f32))) else (t00, t01, add(t10, cast(1.0, f32)), t11) } else { if is_curr_one then (t00, add(t01, cast(1.0, f32)), t10, t11) else (add(t00, cast(1.0, f32)), t01, t10, t11) }
    }, init, idxs)
  }
}
def re_safe_xlogx(x: f32, p: f32) -> f32 = { if eq(x, cast(0.0, f32)) then cast(0.0, f32) else if lte(p, cast(0.0, f32)) then cast(0.0, f32) else mul(x, log(p)) }
def re_christoffersen_lr_ind(t00: f32, t01: f32, t10: f32, t11: f32) -> f32 = {
  row0_total = add(t00, t01)
  row1_total = add(t10, t11)
  n_trans = add(row0_total, row1_total)
  n_ones = add(t01, t11)
  pi_01 = if eq(row0_total, cast(0.0, f32)) then cast(0.0, f32) else div(t01, row0_total)
  pi_11 = if eq(row1_total, cast(0.0, f32)) then cast(0.0, f32) else div(t11, row1_total)
  pi_hat = if eq(n_trans, cast(0.0, f32)) then cast(0.0, f32) else div(n_ones, n_trans)
  log_l_null_a = re_safe_xlogx(add(t00, t10), sub(cast(1.0, f32), pi_hat))
  log_l_null_b = re_safe_xlogx(n_ones, pi_hat)
  log_l_null = add(log_l_null_a, log_l_null_b)
  log_l_alt_a = re_safe_xlogx(t00, sub(cast(1.0, f32), pi_01))
  log_l_alt_b = re_safe_xlogx(t01, pi_01)
  log_l_alt_c = re_safe_xlogx(t10, sub(cast(1.0, f32), pi_11))
  log_l_alt_d = re_safe_xlogx(t11, pi_11)
  log_l_alt = add(add(log_l_alt_a, log_l_alt_b), add(log_l_alt_c, log_l_alt_d))
  mul(cast(-2.0, f32), sub(log_l_null, log_l_alt))
}
def re_christoffersen_cc[n](losses: tensor[n, f32], var_forecasts: tensor[n, f32], alpha: f32) -> (f32, bool) = {
  n_total = numel(copy(losses))
  indicators_l = re_christoffersen_exception_indicators(losses, var_forecasts)
  exception_count = fold(fn (acc: f32, e: f32) -> add(acc, e), cast(0.0, f32), indicators_l)
  lr_uc = kupiec_pof_statistic_simple(cast(exception_count, int64), n_total, alpha)
  counts = re_christoffersen_transition_counts(indicators_l)
  lr_ind = re_christoffersen_lr_ind(counts.0, counts.1, counts.2, counts.3)
  lr_cc = add(lr_uc, lr_ind)
  crit_2dof_95 = cast(5.991, f32)
  (lr_cc, gt(lr_cc, crit_2dof_95))
}
def re_acerbi_ratio_accumulator[n](realized_losses: tensor[n, f32], var_forecasts: tensor[n, f32], es_forecasts: tensor[n, f32]) -> (f32, f32) = {
  losses_l = to_list(copy(realized_losses))
  vars_l = to_list(copy(var_forecasts))
  es_l = to_list(copy(es_forecasts))
  pairs_lv = zip(losses_l, vars_l)
  triples = zip(pairs_lv, es_l)
  init = (cast(0.0, f32), cast(0.0, f32))
  fold(fn (state: (f32, f32), entry: ((f32, f32), f32)) -> {
    sum_ratio = state.0
    n_excep = state.1
    lv = entry.0
    loss_v = lv.0
    var_v = lv.1
    es_v = entry.1
    is_excep = gt(loss_v, var_v)
    contrib = if is_excep then if eq(es_v, cast(0.0, f32)) then cast(0.0, f32) else div(loss_v, es_v) else cast(0.0, f32)
    incr = if is_excep then cast(1.0, f32) else cast(0.0, f32)
    (add(sum_ratio, contrib), add(n_excep, incr))
  }, init, triples)
}
def re_acerbi_szekely_es_z1[n](realized_losses: tensor[n, f32], var_forecasts: tensor[n, f32], es_forecasts: tensor[n, f32], alpha: f32) -> f32 = {
  _ = alpha
  acc = re_acerbi_ratio_accumulator(realized_losses, var_forecasts, es_forecasts)
  sum_ratio = acc.0
  n_excep = acc.1
  if eq(n_excep, cast(0.0, f32)) then cast(0.0, f32) else sub(cast(1.0, f32), div(sum_ratio, n_excep))
}
def re_acerbi_szekely_es_z2[n](realized_losses: tensor[n, f32], var_forecasts: tensor[n, f32], es_forecasts: tensor[n, f32], alpha: f32) -> f32 = {
  n_total = cast(numel(copy(realized_losses)), f32)
  acc = re_acerbi_ratio_accumulator(realized_losses, var_forecasts, es_forecasts)
  sum_ratio = acc.0
  denom = mul(n_total, alpha)
  if eq(denom, cast(0.0, f32)) then cast(0.0, f32) else sub(cast(1.0, f32), div(sum_ratio, denom))
}
def re_acerbi_szekely_es_z3[n](realized_losses: tensor[n, f32], var_forecasts: tensor[n, f32], es_forecasts: tensor[n, f32], alpha: f32) -> f32 = {
  _ = alpha
  n_total = cast(numel(copy(realized_losses)), f32)
  acc = re_acerbi_ratio_accumulator(realized_losses, var_forecasts, es_forecasts)
  sum_ratio = acc.0
  n_excep = acc.1
  mean_ratio = if eq(n_total, cast(0.0, f32)) then cast(0.0, f32) else div(sum_ratio, n_total)
  mean_excep = if eq(n_total, cast(0.0, f32)) then cast(0.0, f32) else div(n_excep, n_total)
  if eq(mean_excep, cast(0.0, f32)) then cast(0.0, f32) else sub(cast(1.0, f32), div(mean_ratio, mean_excep))
}
