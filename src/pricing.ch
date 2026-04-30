module Shoals.Pricing
import Nautilus.Distributions (normal_sample)
import Nautilus.Special (erfc)
export (bs_call_scalar, bs_put_scalar, call_prices, put_prices, call_total, put_total, deltas_call, deltas_put, vegas_call, mc_call_price)
def n_cdf(x: f32) -> f32 = {
  inv_sqrt_2 = cast(0.7071067811865475, f32)
  mul(cast(0.5, f32), erfc(neg(mul(x, inv_sqrt_2))))
}
def bs_call_scalar(s: f32, k: f32, r: f32, sigma: f32, t: f32) -> f32 = {
  sqrt_t = sqrt(t)
  sig_sqrt_t = mul(sigma, sqrt_t)
  log_sk = log(div(s, k))
  sigma_sq_half = mul(cast(0.5, f32), mul(sigma, sigma))
  drift = mul(add(r, sigma_sq_half), t)
  d1 = div(add(log_sk, drift), sig_sqrt_t)
  d2 = sub(d1, sig_sqrt_t)
  nd1 = n_cdf(d1)
  nd2 = n_cdf(d2)
  disc = exp(neg(mul(r, t)))
  sub(mul(s, nd1), mul(k, mul(disc, nd2)))
}
def bs_put_scalar(s: f32, k: f32, r: f32, sigma: f32, t: f32) -> f32 = {
  sqrt_t = sqrt(t)
  sig_sqrt_t = mul(sigma, sqrt_t)
  log_sk = log(div(s, k))
  sigma_sq_half = mul(cast(0.5, f32), mul(sigma, sigma))
  drift = mul(add(r, sigma_sq_half), t)
  d1 = div(add(log_sk, drift), sig_sqrt_t)
  d2 = sub(d1, sig_sqrt_t)
  n_neg_d1 = n_cdf(neg(d1))
  n_neg_d2 = n_cdf(neg(d2))
  disc = exp(neg(mul(r, t)))
  sub(mul(k, mul(disc, n_neg_d2)), mul(s, n_neg_d1))
}
def call_prices[n](spots: tensor[n, f32], k: f32, r: f32, sigma: f32, t: f32) -> tensor[n, f32] = {
  spots_l = to_list(copy(spots))
  to_tensor(map(fn (s: f32) -> bs_call_scalar(s, k, r, sigma, t), spots_l))
}
def put_prices[n](spots: tensor[n, f32], k: f32, r: f32, sigma: f32, t: f32) -> tensor[n, f32] = {
  spots_l = to_list(copy(spots))
  to_tensor(map(fn (s: f32) -> bs_put_scalar(s, k, r, sigma, t), spots_l))
}
def call_total[n](spots: tensor[n, f32], k: f32, r: f32, sigma: f32, t: f32) -> f32 = tensor_to_scalar(sum(call_prices(spots, k, r, sigma, t), 0))
def put_total[n](spots: tensor[n, f32], k: f32, r: f32, sigma: f32, t: f32) -> f32 = tensor_to_scalar(sum(put_prices(spots, k, r, sigma, t), 0))
def deltas_call[n](spots: tensor[n, f32], k: f32, r: f32, sigma: f32, t: f32) -> tensor[n, f32] = {
  obj = fn (sx: tensor[n, f32]) -> call_total(sx, k, r, sigma, t)
  grad(obj, wrt=sx)(spots)
}
def deltas_put[n](spots: tensor[n, f32], k: f32, r: f32, sigma: f32, t: f32) -> tensor[n, f32] = {
  obj = fn (sx: tensor[n, f32]) -> put_total(sx, k, r, sigma, t)
  grad(obj, wrt=sx)(spots)
}
def call_total_per_sigma[n](spots_in: tensor[n, f32], sigmas_in: tensor[n, f32], k: f32, r: f32, t: f32) -> f32 = {
  pairs = zip(to_list(copy(spots_in)), to_list(copy(sigmas_in)))
  prices = to_tensor(map(fn (pair: (f32, f32)) -> bs_call_scalar(pair.0, k, r, pair.1, t), pairs))
  tensor_to_scalar(sum(prices, 0))
}
def vegas_call[n](spots: tensor[n, f32], k: f32, r: f32, sigma: f32, t: f32) -> tensor[n, f32] = {
  n_len = cast(shape(copy(spots), cast(0, int32)), int64)
  sigma_vec = to_tensor(map(fn (i: int64) -> sigma, range(cast(0, int64), n_len)))
  obj = fn (sigmas: tensor[n, f32]) -> call_total_per_sigma(spots, sigmas, k, r, t)
  grad(obj, wrt=sigmas)(sigma_vec)
}
def mc_call_price[n](template: tensor[n, f32], s0: f32, k: f32, r: f32, sigma: f32, t: f32) -> f32 ! { Random } = {
  z = normal_sample(template, cast(0.0, f32), cast(1.0, f32))
  half_sigma_sq = mul(cast(0.5, f32), mul(sigma, sigma))
  drift = mul(sub(r, half_sigma_sq), t)
  vol_sqrt_t = mul(sigma, sqrt(t))
  zs = to_list(z)
  payoffs = to_tensor(map(fn (zi: f32) -> {
    log_st = add(log(s0), add(drift, mul(vol_sqrt_t, zi)))
    st = exp(log_st)
    pay = sub(st, k)
    if gt(pay, cast(0.0, f32)) then pay else cast(0.0, f32)
  }, zs))
  n_f = cast(numel(copy(payoffs)), f32)
  avg_payoff = div(tensor_to_scalar(sum(payoffs, 0)), n_f)
  disc = exp(neg(mul(r, t)))
  mul(disc, avg_payoff)
}
