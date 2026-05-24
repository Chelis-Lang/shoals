module Shoals.Xva
export (survival_probability_constant_hazard, default_probability_in_interval, expected_positive_exposure, expected_negative_exposure, netted_exposure_2_deals, cva_constant_hazard, dva_constant_hazard, discount_factor_constant_rate)
def survival_probability_constant_hazard(hazard: f32, t: f32) -> f32 = exp(neg(mul(hazard, t)))
def default_probability_in_interval(hazard: f32, t_start: f32, t_end: f32) -> f32 = sub(survival_probability_constant_hazard(hazard, t_start), survival_probability_constant_hazard(hazard, t_end))
def discount_factor_constant_rate(r: f32, t: f32) -> f32 = exp(neg(mul(r, t)))
def expected_positive_exposure[n](exposures: tensor[n, f32]) -> f32 = {
  exposures_l = to_list(copy(exposures))
  n_f = cast(numel(copy(exposures)), f32)
  init = cast(0.0, f32)
  positive_sum = fold(fn (acc: f32, x: f32) -> if gt(x, cast(0.0, f32)) then add(acc, x) else acc, init, exposures_l)
  div(positive_sum, n_f)
}
def expected_negative_exposure[n](exposures: tensor[n, f32]) -> f32 = {
  exposures_l = to_list(copy(exposures))
  n_f = cast(numel(copy(exposures)), f32)
  init = cast(0.0, f32)
  negative_sum = fold(fn (acc: f32, x: f32) -> if lt(x, cast(0.0, f32)) then add(acc, x) else acc, init, exposures_l)
  div(negative_sum, n_f)
}
def netted_exposure_2_deals[n](deal_a: tensor[n, f32], deal_b: tensor[n, f32]) -> tensor[n, f32] = {
  a_l = to_list(copy(deal_a))
  b_l = to_list(copy(deal_b))
  pairs = zip(a_l, b_l)
  to_tensor(map(fn (entry: (f32, f32)) -> add(entry.0, entry.1), pairs))
}
def cva_constant_hazard[n](time_grid: tensor[n, f32], epe: tensor[n, f32], hazard: f32, recovery: f32, discount_rate: f32) -> f32 = {
  ts_l = to_list(copy(time_grid))
  epe_l = to_list(copy(epe))
  pairs = zip(ts_l, epe_l)
  init = (cast(0.0, f32), cast(0.0, f32))
  loss_given_default = sub(cast(1.0, f32), recovery)
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
  ts_l = to_list(copy(time_grid))
  ene_l = to_list(copy(ene))
  pairs = zip(ts_l, ene_l)
  init = (cast(0.0, f32), cast(0.0, f32))
  loss_given_default = sub(cast(1.0, f32), recovery_own)
  out = fold(fn (state: (f32, f32), entry: (f32, f32)) -> {
    prev_t = state.0
    accum = state.1
    t_i = entry.0
    ene_i = entry.1
    p_default = default_probability_in_interval(hazard_own, prev_t, t_i)
    df_i = discount_factor_constant_rate(discount_rate, t_i)
    contribution = mul(loss_given_default, mul(p_default, mul(neg(ene_i), df_i)))
    (t_i, add(accum, contribution))
  }, init, pairs)
  out.1
}
