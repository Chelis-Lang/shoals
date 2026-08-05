module Shoals.Cds
import Nautilus.Roots (brent)
export (HazardCurve, hazard_curve_from_pillars, cds_survival_from_hazards, cds_premium_leg_value, cds_protection_leg_value, cds_pv, cds_bootstrap_hazards)
type HazardCurve[n] =
  | HazardCurve { times: tensor[n, f32], hazards: tensor[n, f32] }
def hazard_curve_from_pillars[n](times: tensor[n, f32], hazards: tensor[n, f32]) -> HazardCurve[n] = HazardCurve { times, hazards }
def cds_integrated_hazard(times_l: List[f32], hazards_l: List[f32], t: f32) -> f32 = {
  pairs = zip(times_l, hazards_l)
  init = (cast(0.0, f32), cast(0.0, f32))
  out = fold(fn (state: (f32, f32), entry: (f32, f32)) -> {
    prev_t = state.0
    accum = state.1
    pillar_t = entry.0
    h_i = entry.1
    upper = if lt(pillar_t, t) then pillar_t else t
    dt = if gt(upper, prev_t) then sub(upper, prev_t) else cast(0.0, f32)
    new_accum = add(accum, mul(h_i, dt))
    new_prev = if gt(pillar_t, prev_t) then pillar_t else prev_t
    (new_prev, new_accum)
  }, init, pairs)
  last_pillar = out.0
  base = out.1
  tail_dt = if gt(t, last_pillar) then sub(t, last_pillar) else cast(0.0, f32)
  last_h = fold(fn (acc: f32, h: f32) -> h, cast(0.0, f32), hazards_l)
  add(base, mul(last_h, tail_dt))
}
def cds_survival_from_hazards[n](curve: HazardCurve[n], t: f32) -> f32 =
  match curve with {
    | HazardCurve { times: ts, hazards: hs } => {
    ts_l = to_list(copy(ts))
    hs_l = to_list(copy(hs))
    integral = cds_integrated_hazard(ts_l, hs_l, t)
    exp(neg(integral))
  }
  }
def cds_premium_grid(t_maturity: f32, n_premiums_per_year: int64) -> List[f32] = {
  freq_f = cast(n_premiums_per_year, f32)
  dt = div(cast(1.0, f32), freq_f)
  total_f32 = mul(t_maturity, freq_f)
  total = cast_trunc(total_f32, int64)
  ks = range(cast(1, int64), add(total, cast(1, int64)))
  map(fn (k: int64) -> mul(cast(k, f32), dt), ks)
}
def cds_premium_leg_from_lists(spread: f32, grid: List[f32], times_l: List[f32], hazards_l: List[f32], r: f32) -> f32 = {
  init = (cast(0.0, f32), cast(0.0, f32))
  out = fold(fn (state: (f32, f32), t_j: f32) -> {
    prev_t = state.0
    accum = state.1
    dt = sub(t_j, prev_t)
    df = exp(neg(mul(r, t_j)))
    integral = cds_integrated_hazard(times_l, hazards_l, t_j)
    q = exp(neg(integral))
    contribution = mul(spread, mul(df, mul(q, dt)))
    (t_j, add(accum, contribution))
  }, init, grid)
  out.1
}
def cds_premium_leg_from_grid[n](spread: f32, grid: List[f32], hazards: HazardCurve[n], r: f32) -> f32 =
  match hazards with {
    | HazardCurve { times: ts, hazards: hs } => cds_premium_leg_from_lists(spread, grid, to_list(ts), to_list(hs), r)
  }
def cds_premium_leg_value[n](spread: f32, t_maturity: f32, n_premiums_per_year: int64, hazards: HazardCurve[n], r: f32) -> f32 = {
  grid = cds_premium_grid(t_maturity, n_premiums_per_year)
  cds_premium_leg_from_grid(spread, grid, hazards, r)
}
def cds_protection_leg_from_lists(grid: List[f32], recovery: f32, times_l: List[f32], hazards_l: List[f32], r: f32) -> f32 = {
  lgd = sub(cast(1.0, f32), recovery)
  init = (cast(0.0, f32), cast(0.0, f32))
  out = fold(fn (state: (f32, f32), t_j: f32) -> {
    prev_t = state.0
    accum = state.1
    t_mid = mul(cast(0.5, f32), add(prev_t, t_j))
    df_mid = exp(neg(mul(r, t_mid)))
    int_prev = cds_integrated_hazard(times_l, hazards_l, prev_t)
    int_now = cds_integrated_hazard(times_l, hazards_l, t_j)
    q_prev = exp(neg(int_prev))
    q_now = exp(neg(int_now))
    p_default = sub(q_prev, q_now)
    contribution = mul(lgd, mul(df_mid, p_default))
    (t_j, add(accum, contribution))
  }, init, grid)
  out.1
}
def cds_protection_leg_from_grid[n](grid: List[f32], recovery: f32, hazards: HazardCurve[n], r: f32) -> f32 =
  match hazards with {
    | HazardCurve { times: ts, hazards: hs } => cds_protection_leg_from_lists(grid, recovery, to_list(ts), to_list(hs), r)
  }
def cds_protection_leg_value[n](t_maturity: f32, recovery: f32, hazards: HazardCurve[n], r: f32) -> f32 = {
  freq_default = cast(12, int64)
  grid = cds_premium_grid(t_maturity, freq_default)
  cds_protection_leg_from_grid(grid, recovery, hazards, r)
}
def cds_pv_from_lists(spread: f32, t_maturity: f32, n_premiums_per_year: int64, recovery: f32, times_l: List[f32], hazards_l: List[f32], r: f32) -> f32 = {
  grid_p = cds_premium_grid(t_maturity, n_premiums_per_year)
  grid_d = cds_premium_grid(t_maturity, cast(12, int64))
  pl = cds_premium_leg_from_lists(spread, grid_p, times_l, hazards_l, r)
  prl = cds_protection_leg_from_lists(grid_d, recovery, times_l, hazards_l, r)
  sub(prl, pl)
}
def cds_pv[n](spread: f32, t_maturity: f32, n_premiums_per_year: int64, recovery: f32, hazards: HazardCurve[n], r: f32) -> f32 =
  match hazards with {
    | HazardCurve { times: ts, hazards: hs } => cds_pv_from_lists(spread, t_maturity, n_premiums_per_year, recovery, to_list(ts), to_list(hs), r)
  }
def cds_bootstrap_step(spread: f32, tenor: f32, recovery: f32, r: f32, n_premiums_per_year: int64, prev_times: List[f32], prev_hazards: List[f32]) -> f32 = {
  residual = fn (h_candidate: f32) -> {
    new_times = append(prev_times, tenor)
    new_hazards = append(prev_hazards, h_candidate)
    cds_pv_from_lists(spread, tenor, n_premiums_per_year, recovery, new_times, new_hazards, r)
  }
  brent(residual, cast(1e-6, f32), cast(2.0, f32), cast(1e-7, f32), cast(100, int64))
}
def cds_bootstrap_hazards[n](spreads: tensor[n, f32], tenors: tensor[n, f32], recovery: f32, r: f32, n_premiums_per_year: int64) -> HazardCurve[n] = {
  spreads_l = to_list(copy(spreads))
  tenors_l = to_list(copy(tenors))
  pairs = zip(tenors_l, spreads_l)
  init = ([], [])
  out = fold(fn (state: (List[f32], List[f32]), entry: (f32, f32)) -> {
    prev_times = state.0
    prev_hazards = state.1
    tenor_i = entry.0
    spread_i = entry.1
    h_i = cds_bootstrap_step(spread_i, tenor_i, recovery, r, n_premiums_per_year, prev_times, prev_hazards)
    (append(prev_times, tenor_i), append(prev_hazards, h_i))
  }, init, pairs)
  HazardCurve { times: to_tensor(out.0), hazards: to_tensor(out.1) }
}
