module Shoals.References.Sabr
export (sabr_atm_iv_textbook)
def pow_textbook(base: f32, expn: f32) -> f32 = expn |> mul(log(base)) |> exp
def sabr_atm_iv_textbook(alpha: f32, beta: f32, rho: f32, nu: f32, f: f32, t: f32) -> f32 = {
  one_minus_beta = 1.0
    |> fn (__chelis_pipe) -> cast(__chelis_pipe, f32) |> sub(beta)
  f_pow_1mb = pow_textbook(f, one_minus_beta)
  f_pow_2m2b = pow_textbook(f, 2.0 |> fn (__chelis_pipe) -> cast(__chelis_pipe, f32) |> mul(one_minus_beta))
  leading = div(alpha, f_pow_1mb)
  t1 = div(mul(div(mul(one_minus_beta, one_minus_beta), cast(24.0, f32)), mul(alpha, alpha)), f_pow_2m2b)
  t2 = div(mul(cast(0.25, f32), mul(rho, mul(beta, mul(nu, alpha)))), f_pow_1mb)
  t3 = mul(div(sub(cast(2.0, f32), mul(cast(3.0, f32), mul(rho, rho))), cast(24.0, f32)), mul(nu, nu))
  correction = t1 |> add(add(t2, t3)) |> mul(t)
  mul(leading, 1.0 |> fn (__chelis_pipe) -> cast(__chelis_pipe, f32) |> add(correction))
}
