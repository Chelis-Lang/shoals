module Shoals.References.Vasicek
export (zero_bond_price_textbook, short_rate_mean_textbook, short_rate_variance_textbook)
def short_rate_mean_textbook(r0: f32, a: f32, b: f32, t: f32) -> f32 = { add(b, r0 |> sub(b) |> mul(exp(neg(mul(a, t))))) }
def short_rate_variance_textbook(a: f32, sigma: f32, t: f32) -> f32 = {
  factor = 1.0
    |> fn (__chelis_pipe) -> cast(__chelis_pipe, f32) |> sub(exp(neg(mul(cast(2.0, f32), mul(a, t)))))
  div(mul(mul(sigma, sigma), factor), mul(cast(2.0, f32), a))
}
def zero_bond_price_textbook(r_t: f32, a: f32, b: f32, sigma: f32, tau: f32) -> f32 = {
  bb = div(sub(cast(1.0, f32), exp(neg(mul(a, tau)))), a)
  a_sq = mul(a, a)
  sigma_sq = mul(sigma, sigma)
  c1 = div(sub(mul(a_sq, b), mul(cast(0.5, f32), sigma_sq)), a_sq)
  log_a = bb |> sub(tau) |> mul(c1)
  log_b = neg(div(mul(sigma_sq, mul(bb, bb)), mul(cast(4.0, f32), a)))
  log_a_factor = add(log_a, log_b)
  log_a_factor |> exp |> mul(exp(neg(mul(bb, r_t))))
}
