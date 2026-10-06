module Shoals.Xva
import Nautilus.Distributions (gamma_sample, normal_sample, normal_cdf)
import Nautilus.Interpolation (linear_interp_sorted)
import Shoals.Cds (HazardCurve, cds_survival_from_hazards)
export (survival_probability_constant_hazard, default_probability_in_interval, expected_positive_exposure, expected_negative_exposure, netted_exposure_2_deals, cva_constant_hazard, dva_constant_hazard, discount_factor_constant_rate, fva, kva, xva_cva_wwr_constant_hazard, xva_cva_stochastic_hazard)
def survival_probability_constant_hazard(hazard: f32, t: f32) -> f32 = exp(neg(mul(hazard, t)))
def default_probability_in_interval(hazard: f32, t_start: f32, t_end: f32) -> f32 = sub(survival_probability_constant_hazard(hazard, t_start), survival_probability_constant_hazard(hazard, t_end))
def discount_factor_constant_rate(r: f32, t: f32) -> f32 = exp(neg(mul(r, t)))
def expected_positive_exposure[n](exposures: tensor[n, f32]) -> f32 = {
  exposures_l = to_list(exposures)
  n_f = cast(numel(exposures), f32)
  init = cast(0.0, f32)
  positive_sum = fold(fn (acc: f32, x: f32) -> if gt(x, cast(0.0, f32)) then add(acc, x) else acc, init, exposures_l)
  div(positive_sum, n_f)
}
def expected_negative_exposure[n](exposures: tensor[n, f32]) -> f32 = {
  exposures_l = to_list(exposures)
  n_f = cast(numel(exposures), f32)
  init = cast(0.0, f32)
  negative_sum = fold(fn (acc: f32, x: f32) -> if lt(x, cast(0.0, f32)) then add(acc, x) else acc, init, exposures_l)
  div(negative_sum, n_f)
}
def netted_exposure_2_deals[n](deal_a: tensor[n, f32], deal_b: tensor[n, f32]) -> tensor[n, f32] = {
  a_l = to_list(deal_a)
  b_l = to_list(deal_b)
  pairs = zip(a_l, b_l)
  to_tensor(map(fn (entry: (f32, f32)) -> add(entry.0, entry.1), pairs))
}
def cva_constant_hazard[n](time_grid: tensor[n, f32], epe: tensor[n, f32], hazard: f32, recovery: f32, discount_rate: f32) -> f32 = {
  ts_l = to_list(time_grid)
  epe_l = to_list(epe)
  pairs = zip(ts_l, epe_l)
  init = (cast(0.0, f32), cast(0.0, f32))
  loss_given_default = 1.0
    |> fn (__chelis_pipe) -> cast(__chelis_pipe, f32) |> sub(recovery)
  out = fold(fn (state: (f32, f32), entry: (f32, f32)) -> {
    prev_t = state.0
    accum = state.1
    t_i = entry.0
    epe_i = entry.1
    p_default = default_probability_in_interval(hazard, prev_t, t_i)
    df_i = discount_factor_constant_rate(discount_rate, t_i)
    contribution = mul(loss_given_default, mul(p_default, mul(epe_i, df_i)))
    (t_i, add(accum, contribution))
  }, init, pairs)
  out.1
}
def dva_constant_hazard[n](time_grid: tensor[n, f32], ene: tensor[n, f32], hazard_own: f32, recovery_own: f32, discount_rate: f32) -> f32 = {
  ts_l = to_list(time_grid)
  ene_l = to_list(ene)
  pairs = zip(ts_l, ene_l)
  init = (cast(0.0, f32), cast(0.0, f32))
  loss_given_default = 1.0
    |> fn (__chelis_pipe) -> cast(__chelis_pipe, f32) |> sub(recovery_own)
  out = fold(fn (state: (f32, f32), entry: (f32, f32)) -> {
    prev_t = state.0
    accum = state.1
    t_i = entry.0
    ene_i = entry.1
    p_default = default_probability_in_interval(hazard_own, prev_t, t_i)
    df_i = discount_factor_constant_rate(discount_rate, t_i)
    contribution = mul(loss_given_default, mul(p_default, ene_i |> neg |> mul(df_i)))
    (t_i, add(accum, contribution))
  }, init, pairs)
  out.1
}
def xva_trapezoidal_df_weighted[n](time_grid: tensor[n, f32], weight: tensor[n, f32], discount_rate: f32) -> f32 = {
  ts_l = to_list(time_grid)
  w_l = to_list(weight)
  pairs = zip(ts_l, w_l)
  init = (cast(0.0, f32), cast(0.0, f32), cast(0.0, f32), cast(0, i64))
  out = fold(fn (state: (f32, f32, f32, i64), entry: (f32, f32)) -> {
    prev_t = state.0
    prev_dfw = state.1
    accum = state.2
    idx = state.3
    t_i = entry.0
    w_i = entry.1
    df_i = discount_factor_constant_rate(discount_rate, t_i)
    dfw_i = mul(df_i, w_i)
    dt_i = sub(t_i, prev_t)
    avg_dfw = add(prev_dfw, dfw_i) |> mul(cast(0.5, f32))
    contribution = if eq(idx, cast(0, i64)) then cast(0.0, f32) else avg_dfw |> mul(dt_i)
    (t_i, dfw_i, add(accum, contribution), add(idx, cast(1, i64)))
  }, init, pairs)
  out.2
}
def fva[n](time_grid: tensor[n, f32], epe: tensor[n, f32], funding_spread: f32, discount_rate: f32) -> f32 = mul(funding_spread, xva_trapezoidal_df_weighted(time_grid, epe, discount_rate))
def kva[n](time_grid: tensor[n, f32], ead: tensor[n, f32], cost_of_capital: f32, regulatory_capital_weight: f32, discount_rate: f32) -> f32 = mul(cost_of_capital, mul(regulatory_capital_weight, xva_trapezoidal_df_weighted(time_grid, ead, discount_rate)))
def xva_cva_stochastic_recovery[n](rng_key: key, time_grid: tensor[n, f32], epe: tensor[n, f32], hazard: f32, recovery_alpha: f32, recovery_beta: f32, discount_rate: f32, n_paths: i64) -> f32 = {
  (rng_draw_0, rng_draw_1) = split_key(rng_key)
  zero_f = cast(0.0, f32)
  one_f = cast(1.0, f32)
  bare = cva_constant_hazard(time_grid, epe, hazard, zero_f, discount_rate)
  template = to_tensor(map(fn (i: i64) -> zero_f, range(cast(0, i64), n_paths)))
  xs = gamma_sample(rng_draw_0, copy(template), recovery_alpha, one_f)
  ys = gamma_sample(rng_draw_1, template, recovery_beta, one_f)
  xs_l = to_list(xs)
  ys_l = to_list(ys)
  pairs = zip(xs_l, ys_l)
  n_f = cast(n_paths, f32)
  acc = fold(fn (a: f32, entry: (f32, f32)) -> {
    r_i = div(entry.0, add(entry.0, entry.1))
    add(a, mul(sub(one_f, r_i), bare))
  }, zero_f, pairs)
  div(acc, n_f)
}
def xva_wwr_exposure_shock(eta: f32, z_e: f32) -> f32 = exp(sub(mul(eta, z_e), mul(cast(0.5, f32), mul(eta, eta))))
def xva_wwr_default_time(rho: f32, z_e: f32, z_d: f32, hazard: f32) -> f32 = {
  one_minus_rho2 = sub(cast(1.0, f32), mul(rho, rho))
  sqrt_term = sqrt(if lt(one_minus_rho2, cast(0.0, f32)) then cast(0.0, f32) else one_minus_rho2)
  x_d = add(mul(neg(rho), z_e), mul(sqrt_term, z_d))
  u_j = normal_cdf(x_d, cast(0.0, f32), cast(1.0, f32))
  one_minus_u = sub(cast(1.0, f32), u_j)
  safe_one_minus_u = if lt(one_minus_u, cast(1e-12, f32)) then cast(1e-12, f32) else one_minus_u
  safe_hazard = if lt(hazard, cast(1e-12, f32)) then cast(1e-12, f32) else hazard
  div(neg(log(safe_one_minus_u)), safe_hazard)
}
def xva_cva_stochastic_hazard[n, m](time_grid: tensor[m, f32], epe: tensor[m, f32], hazards: HazardCurve[n], recovery: f32, discount_rate: f32) -> f32 = {
  ts_l = to_list(time_grid)
  epe_l = to_list(epe)
  pairs = zip(ts_l, epe_l)
  lgd = sub(cast(1.0, f32), recovery)
  match hazards with {
    | HazardCurve { times: ts_h, hazards: hs_h } => {
    h_ts_l = to_list(copy(ts_h))
    h_hs_l = to_list(copy(hs_h))
    init = (cast(0.0, f32), cast(0.0, f32))
    out = fold(fn (state: (f32, f32), entry: (f32, f32)) -> {
      prev_t = state.0
      accum = state.1
      t_i = entry.0
      epe_i = entry.1
      curve_prev = HazardCurve { times: to_tensor(h_ts_l), hazards: to_tensor(h_hs_l) }
      q_prev = cds_survival_from_hazards(curve_prev, prev_t)
      curve_now = HazardCurve { times: to_tensor(h_ts_l), hazards: to_tensor(h_hs_l) }
      q_now = cds_survival_from_hazards(curve_now, t_i)
      p_default = sub(q_prev, q_now)
      df_i = discount_factor_constant_rate(discount_rate, t_i)
      contribution = mul(lgd, mul(p_default, mul(epe_i, df_i)))
      (t_i, add(accum, contribution))
    }, init, pairs)
    out.1
  }
  }
}
def xva_cva_wwr_constant_hazard[n](rng_key: key, time_grid: tensor[n, f32], epe: tensor[n, f32], hazard: f32, recovery: f32, discount_rate: f32, rho: f32, n_paths: i64) -> f32 = {
  (rng_draw_0, rng_draw_1) = split_key(rng_key)
  zero_f = cast(0.0, f32)
  one_f = cast(1.0, f32)
  eta_e = cast(0.5, f32)
  lgd = sub(one_f, recovery)
  template = to_tensor(map(fn (i: i64) -> zero_f, range(cast(0, i64), n_paths)))
  z_e_t = normal_sample(rng_draw_0, copy(template), zero_f, one_f)
  z_d_t = normal_sample(rng_draw_1, template, zero_f, one_f)
  ts_l = to_list(copy(time_grid))
  n_grid = numel(copy(time_grid))
  t_max = index(ts_l, sub(cast(n_grid, i64), cast(1, i64)))
  z_e_l = to_list(z_e_t)
  z_d_l = to_list(z_d_t)
  pairs = zip(z_e_l, z_d_l)
  contribs = map(fn (entry: (f32, f32)) -> {
    z_e_j = entry.0
    z_d_j = entry.1
    tau_j = xva_wwr_default_time(rho, z_e_j, z_d_j, hazard)
    if lt(tau_j, t_max) then {
      epe_at_tau = linear_interp_sorted(copy(time_grid), copy(epe), tau_j)
      shock = xva_wwr_exposure_shock(eta_e, z_e_j)
      exposure = mul(epe_at_tau, shock)
      df_tau = discount_factor_constant_rate(discount_rate, tau_j)
      mul(lgd, mul(exposure, df_tau))
    } else zero_f
  }, pairs)
  n_f = cast(n_paths, f32)
  sum_contribs = fold(fn (a: f32, v: f32) -> add(a, v), zero_f, contribs)
  div(sum_contribs, n_f)
}
