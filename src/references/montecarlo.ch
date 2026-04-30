module Shoals.References.MonteCarlo
import Nautilus.Distributions (normal_sample)
export (vanilla_call_textbook)
def vanilla_call_textbook[n](template: tensor[n, f32], s0: f32, k: f32, r: f32, sigma: f32, t: f32) -> f32 ! { Random } = {
  z = normal_sample(template, cast(0.0, f32), cast(1.0, f32))
  half_sigma_sq = mul(cast(0.5, f32), mul(sigma, sigma))
  drift = mul(sub(r, half_sigma_sq), t)
  vol_sqrt_t = mul(sigma, sqrt(t))
  log_s0 = log(s0)
  zs = to_list(copy(z))
  payoff_sum = fold(fn (acc: f32, zi: f32) -> {
    log_st = add(log_s0, add(drift, mul(vol_sqrt_t, zi)))
    st = exp(log_st)
    pay = sub(st, k)
    pay_pos = if gt(pay, cast(0.0, f32)) then pay else cast(0.0, f32)
    add(acc, pay_pos)
  }, cast(0.0, f32), zs)
  n_f = cast(numel(z), f32)
  avg_payoff = div(payoff_sum, n_f)
  mul(exp(neg(mul(r, t))), avg_payoff)
}
