module Shoals.References.HistoricalVar
import Nautilus.Stats (quantile_vec)
export (var_textbook, cvar_textbook)
def var_textbook[n](losses: tensor[n, f32], alpha: f32) -> f32 = quantile_vec(losses, alpha)
def cvar_textbook[n](losses: tensor[n, f32], alpha: f32) -> f32 = {
  losses_copy = copy(losses)
  threshold = quantile_vec(copy(losses_copy), alpha)
  losses_l = to_list(losses_copy)
  init = (cast(0.0, f32), cast(0, i64))
  acc = fold(fn (state: (f32, i64), x: f32) -> if gte(x, threshold) then (add(state.0, x), add(state.1, cast(1, i64))) else state, init, losses_l)
  if eq(acc.1, cast(0, i64)) then threshold else div(acc.0, cast(acc.1, f32))
}
