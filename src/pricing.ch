module Shoals.Pricing
import Nautilus.Distributions (normal_sample)
export (bs_call_scalar, bs_put_scalar, bs_call_f64, bs_call_f64_vector, bs_call_wire_f64, call_prices, put_prices, call_total, put_total, deltas_call, deltas_put, vegas_call, rhos_call, thetas_call, gammas_call, volgas_call, vannas_call, mc_call_price)
-- One normal CDF behind both price and Greeks. erf is the Abramowitz-Stegun
-- 7.1.26 rational approximation in f64 -- byte-for-byte the same coefficients as
-- Nautilus.Special.erf, reimplemented in f64 because the package symbol is
-- f32-only and an f64 grad path needs an f64 erf. n_cdf(x) = 0.5 * erfc(-x/sqrt2)
-- is the exact expression Shoals.References / Shoals.Greeks use. The displayed
-- Greek is the AD derivative of THIS expression, so price and Greek agree.
def abs_f64(x: f64) -> f64 = if lt(x, cast(0.0, f64)) then neg(x) else x
def erf64(x: f64) -> f64 = {
  a1 = cast(0.254829592, f64)
  a2 = cast(-0.284496736, f64)
  a3 = cast(1.421413741, f64)
  a4 = cast(-1.453152027, f64)
  a5 = cast(1.061405429, f64)
  p = cast(0.3275911, f64)
  one = cast(1.0, f64)
  ax = abs_f64(x)
  small = cast(0.00001, f64)
  if lt(ax, small) then mul(x, cast(1.1283791670955126, f64)) else {
    t = div(one, add(one, mul(p, ax)))
    poly = mul(t, add(a1, mul(t, add(a2, mul(t, add(a3, mul(t, add(a4, mul(t, a5)))))))))
    e = exp(neg(mul(ax, ax)))
    y = sub(one, mul(poly, e))
    if lt(x, cast(0.0, f64)) then neg(y) else y
  }
}
def n_cdf64(x: f64) -> f64 = {
  inv_sqrt_2 = cast(0.7071067811865476, f64)
  mul(cast(0.5, f64), sub(cast(1.0, f64), erf64(neg(mul(x, inv_sqrt_2)))))
}
def d1_64(s: f64, k: f64, r: f64, sigma: f64, t: f64) -> f64 = {
  num = add(log(div(s, k)), mul(add(r, mul(cast(0.5, f64), mul(sigma, sigma))), t))
  div(num, mul(sigma, sqrt(t)))
}
def d2_64(s: f64, k: f64, r: f64, sigma: f64, t: f64) -> f64 = sub(d1_64(s, k, r, sigma, t), mul(sigma, sqrt(t)))
-- Black-Scholes call/put, pure scalar f64. SINGLE BODY: the f32 entry points and
-- every Greek differentiate exactly this.
def bs_call_f64(s: f64, k: f64, r: f64, sigma: f64, t: f64) -> f64 = {
  nd1 = n_cdf64(d1_64(s, k, r, sigma, t))
  nd2 = n_cdf64(d2_64(s, k, r, sigma, t))
  disc = exp(neg(mul(r, t)))
  sub(mul(s, nd1), mul(k, mul(disc, nd2)))
}
def bs_put_f64(s: f64, k: f64, r: f64, sigma: f64, t: f64) -> f64 = {
  nnd1 = n_cdf64(neg(d1_64(s, k, r, sigma, t)))
  nnd2 = n_cdf64(neg(d2_64(s, k, r, sigma, t)))
  disc = exp(neg(mul(r, t)))
  sub(mul(k, mul(disc, nnd2)), mul(s, nnd1))
}
-- f32 entry points: compute via the f64 body and downcast. One erf behind price.
def bs_call_scalar(s: f32, k: f32, r: f32, sigma: f32, t: f32) -> f32 = cast(bs_call_f64(cast(s, f64), cast(k, f64), cast(r, f64), cast(sigma, f64), cast(t, f64)), f32)
def bs_put_scalar(s: f32, k: f32, r: f32, sigma: f32, t: f32) -> f32 = cast(bs_put_f64(cast(s, f64), cast(k, f64), cast(r, f64), cast(sigma, f64), cast(t, f64)), f32)
-- Vectorization helpers. vmap cannot capture free f64 vars in the host evaluator
-- (missing-input error), so every scalar param is broadcast to an [n, 1] column
-- and each vmap lane pulls its cell out with tensor_to_scalar(sum(col, 0)); no
-- free var crosses the vmap/grad boundary. const_col builds non-differentiated
-- inputs, so the host-lane map in its fill never has grad flow through it.
def const_col[n](spots: tensor[n, f32], v: f64) -> tensor[n, 1, f64] = {
  nn = cast(shape(copy(spots), cast(0, int32)), int64)
  reshape(to_tensor(map(fn (i: int64) -> v, range(cast(0, int64), nn))), [nn, cast(1, int64)])
}
def spot_col[n](spots: tensor[n, f32]) -> tensor[n, 1, f64] = {
  nn = cast(shape(copy(spots), cast(0, int32)), int64)
  reshape(cast(spots, f64), [nn, cast(1, int64)])
}
def f64_col[n](xs: tensor[n, f64]) -> tensor[n, 1, f64] = {
  nn = cast(shape(copy(xs), cast(0, int32)), int64)
  reshape(xs, [nn, cast(1, int64)])
}
-- Pure tensor-DAG Black-Scholes helpers for the Beacon seam (shoals#19).
-- Constants are point-valued tensor inputs because introducing them through
-- host-only shape/vmap plumbing would erase the named WireDag root. The
-- arithmetic and both erf branches mirror `erf64` above in f64.
def pricing_wire_select_f64[n](mask: &tensor[n, f64], a: tensor[n, f64], b: tensor[n, f64], half: &tensor[n, f64]) -> tensor[n, f64] = {
  one = add(copy(half), copy(half))
  add(mul(copy(mask), a), mul(sub(one, copy(mask)), b))
}
def pricing_wire_abs_f64[n](x: &tensor[n, f64], half: &tensor[n, f64]) -> tensor[n, f64] = {
  neg_mask = cast(lt(copy(x), cast(0.0, f64)), f64)
  pricing_wire_select_f64(&neg_mask, neg(copy(x)), copy(x), half)
}
def pricing_wire_erf_f64[n](x: &tensor[n, f64], a1: &tensor[n, f64], a2: &tensor[n, f64], a3: &tensor[n, f64], a4: &tensor[n, f64], a5: &tensor[n, f64], p: &tensor[n, f64], two_over_sqrt_pi: &tensor[n, f64], small: &tensor[n, f64], half: &tensor[n, f64]) -> tensor[n, f64] = {
  one = add(copy(half), copy(half))
  ax = pricing_wire_abs_f64(x, half)
  linear = mul(copy(x), copy(two_over_sqrt_pi))
  t_v = div(copy(&one), add(copy(&one), mul(copy(p), copy(&ax))))
  poly = mul(copy(&t_v), add(copy(a1), mul(copy(&t_v), add(copy(a2), mul(copy(&t_v), add(copy(a3), mul(copy(&t_v), add(copy(a4), mul(copy(&t_v), copy(a5))))))))))
  y = sub(one, mul(poly, exp(neg(mul(copy(&ax), copy(&ax))))))
  neg_mask = cast(lt(copy(x), cast(0.0, f64)), f64)
  signed = pricing_wire_select_f64(&neg_mask, neg(copy(&y)), y, half)
  small_mask = cast(lt(mul(copy(x), copy(x)), mul(copy(small), copy(small))), f64)
  pricing_wire_select_f64(&small_mask, linear, signed, half)
}
def pricing_wire_normal_cdf_f64[n](x: &tensor[n, f64], half: &tensor[n, f64], inv_sqrt_2: &tensor[n, f64], a1: &tensor[n, f64], a2: &tensor[n, f64], a3: &tensor[n, f64], a4: &tensor[n, f64], a5: &tensor[n, f64], p: &tensor[n, f64], two_over_sqrt_pi: &tensor[n, f64], small: &tensor[n, f64]) -> tensor[n, f64] = {
  one = add(copy(half), copy(half))
  neg_scaled = neg(mul(copy(x), copy(inv_sqrt_2)))
  erf_v = pricing_wire_erf_f64(&neg_scaled, a1, a2, a3, a4, a5, p, two_over_sqrt_pi, small, half)
  mul(copy(half), sub(one, erf_v))
}
def pricing_wire_d1_f64[n](s: &tensor[n, f64], k: &tensor[n, f64], r: &tensor[n, f64], sigma: &tensor[n, f64], t: &tensor[n, f64], half: &tensor[n, f64]) -> tensor[n, f64] = {
  num = add(log(div(copy(s), copy(k))), mul(add(copy(r), mul(copy(half), mul(copy(sigma), copy(sigma)))), copy(t)))
  div(num, mul(copy(sigma), sqrt(copy(t))))
}
-- A producer-clean tensor entry for content-addressed WireDag consumers.
-- It deliberately contains no `vmap`, `shape`, scalar conversion, or host
-- list operation. Beacon binds the coefficient inputs to point intervals.
def bs_call_wire_f64[n](s: tensor[n, f64], k: tensor[n, f64], r: tensor[n, f64], sigma: tensor[n, f64], t: tensor[n, f64], half: tensor[n, f64], inv_sqrt_2: tensor[n, f64], a1: tensor[n, f64], a2: tensor[n, f64], a3: tensor[n, f64], a4: tensor[n, f64], a5: tensor[n, f64], p: tensor[n, f64], two_over_sqrt_pi: tensor[n, f64], small: tensor[n, f64]) -> tensor[n, f64] = {
  d1_v = pricing_wire_d1_f64(&s, &k, &r, &sigma, &t, &half)
  d2_v = sub(copy(&d1_v), mul(copy(&sigma), sqrt(copy(&t))))
  nd1 = pricing_wire_normal_cdf_f64(&d1_v, &half, &inv_sqrt_2, &a1, &a2, &a3, &a4, &a5, &p, &two_over_sqrt_pi, &small)
  nd2 = pricing_wire_normal_cdf_f64(&d2_v, &half, &inv_sqrt_2, &a1, &a2, &a3, &a4, &a5, &p, &two_over_sqrt_pi, &small)
  disc = exp(neg(mul(copy(&r), copy(&t))))
  sub(mul(s, nd1), mul(k, mul(disc, nd2)))
}
def bs_call_f64_vector[n](spots: tensor[n, f64], strikes: tensor[n, f64], rates: tensor[n, f64], sigmas: tensor[n, f64], times: tensor[n, f64]) -> tensor[n, f64] = {
  sc = f64_col(spots)
  kc = f64_col(strikes)
  rc = f64_col(rates)
  vc = f64_col(sigmas)
  tc = f64_col(times)
  vmap(fn (sa: tensor[1, f64], ka: tensor[1, f64], ra: tensor[1, f64], va: tensor[1, f64], ta: tensor[1, f64]) -> bs_call_f64(tensor_to_scalar(sum(sa, 0)), tensor_to_scalar(sum(ka, 0)), tensor_to_scalar(sum(ra, 0)), tensor_to_scalar(sum(va, 0)), tensor_to_scalar(sum(ta, 0))))(sc, kc, rc, vc, tc)
}
-- Tensor-lane prices via multi-arg vmap over the per-spot f64 body (no capture),
-- so grad flows through the same body the Greeks differentiate.
def call_prices[n](spots: tensor[n, f32], k: f32, r: f32, sigma: f32, t: f32) -> tensor[n, f32] = {
  sc = spot_col(copy(spots))
  kc = const_col(copy(spots), cast(k, f64))
  rc = const_col(copy(spots), cast(r, f64))
  vc = const_col(copy(spots), cast(sigma, f64))
  tc = const_col(spots, cast(t, f64))
  p64 = vmap(fn (sa: tensor[1, f64], ka: tensor[1, f64], ra: tensor[1, f64], va: tensor[1, f64], ta: tensor[1, f64]) -> bs_call_f64(tensor_to_scalar(sum(sa, 0)), tensor_to_scalar(sum(ka, 0)), tensor_to_scalar(sum(ra, 0)), tensor_to_scalar(sum(va, 0)), tensor_to_scalar(sum(ta, 0))))(sc, kc, rc, vc, tc)
  cast(p64, f32)
}
def put_prices[n](spots: tensor[n, f32], k: f32, r: f32, sigma: f32, t: f32) -> tensor[n, f32] = {
  sc = spot_col(copy(spots))
  kc = const_col(copy(spots), cast(k, f64))
  rc = const_col(copy(spots), cast(r, f64))
  vc = const_col(copy(spots), cast(sigma, f64))
  tc = const_col(spots, cast(t, f64))
  p64 = vmap(fn (sa: tensor[1, f64], ka: tensor[1, f64], ra: tensor[1, f64], va: tensor[1, f64], ta: tensor[1, f64]) -> bs_put_f64(tensor_to_scalar(sum(sa, 0)), tensor_to_scalar(sum(ka, 0)), tensor_to_scalar(sum(ra, 0)), tensor_to_scalar(sum(va, 0)), tensor_to_scalar(sum(ta, 0))))(sc, kc, rc, vc, tc)
  cast(p64, f32)
}
def call_total[n](spots: tensor[n, f32], k: f32, r: f32, sigma: f32, t: f32) -> f32 = tensor_to_scalar(sum(call_prices(spots, k, r, sigma, t), 0))
def put_total[n](spots: tensor[n, f32], k: f32, r: f32, sigma: f32, t: f32) -> f32 = tensor_to_scalar(sum(put_prices(spots, k, r, sigma, t), 0))
-- First-order Greek vectors via vmap(grad(price)) through the f64 body. Each lane
-- differentiates bs_call_f64 wrt one slot with the others passed explicitly (no
-- capture), so the result is the AD derivative of the displayed price, downcast.
def deltas_call[n](spots: tensor[n, f32], k: f32, r: f32, sigma: f32, t: f32) -> tensor[n, f32] = {
  sc = spot_col(copy(spots))
  kc = const_col(copy(spots), cast(k, f64))
  rc = const_col(copy(spots), cast(r, f64))
  vc = const_col(copy(spots), cast(sigma, f64))
  tc = const_col(spots, cast(t, f64))
  g64 = vmap(fn (sa: tensor[1, f64], ka: tensor[1, f64], ra: tensor[1, f64], va: tensor[1, f64], ta: tensor[1, f64]) -> grad(fn (x: f64, kk: f64, rr: f64, sg: f64, tt: f64) -> bs_call_f64(x, kk, rr, sg, tt), wrt=x)(tensor_to_scalar(sum(sa, 0)), tensor_to_scalar(sum(ka, 0)), tensor_to_scalar(sum(ra, 0)), tensor_to_scalar(sum(va, 0)), tensor_to_scalar(sum(ta, 0))))(sc, kc, rc, vc, tc)
  cast(g64, f32)
}
def deltas_put[n](spots: tensor[n, f32], k: f32, r: f32, sigma: f32, t: f32) -> tensor[n, f32] = {
  sc = spot_col(copy(spots))
  kc = const_col(copy(spots), cast(k, f64))
  rc = const_col(copy(spots), cast(r, f64))
  vc = const_col(copy(spots), cast(sigma, f64))
  tc = const_col(spots, cast(t, f64))
  g64 = vmap(fn (sa: tensor[1, f64], ka: tensor[1, f64], ra: tensor[1, f64], va: tensor[1, f64], ta: tensor[1, f64]) -> grad(fn (x: f64, kk: f64, rr: f64, sg: f64, tt: f64) -> bs_put_f64(x, kk, rr, sg, tt), wrt=x)(tensor_to_scalar(sum(sa, 0)), tensor_to_scalar(sum(ka, 0)), tensor_to_scalar(sum(ra, 0)), tensor_to_scalar(sum(va, 0)), tensor_to_scalar(sum(ta, 0))))(sc, kc, rc, vc, tc)
  cast(g64, f32)
}
def vegas_call[n](spots: tensor[n, f32], k: f32, r: f32, sigma: f32, t: f32) -> tensor[n, f32] = {
  sc = spot_col(copy(spots))
  kc = const_col(copy(spots), cast(k, f64))
  rc = const_col(copy(spots), cast(r, f64))
  vc = const_col(copy(spots), cast(sigma, f64))
  tc = const_col(spots, cast(t, f64))
  g64 = vmap(fn (sa: tensor[1, f64], ka: tensor[1, f64], ra: tensor[1, f64], va: tensor[1, f64], ta: tensor[1, f64]) -> grad(fn (ss: f64, kk: f64, rr: f64, x: f64, tt: f64) -> bs_call_f64(ss, kk, rr, x, tt), wrt=x)(tensor_to_scalar(sum(sa, 0)), tensor_to_scalar(sum(ka, 0)), tensor_to_scalar(sum(ra, 0)), tensor_to_scalar(sum(va, 0)), tensor_to_scalar(sum(ta, 0))))(sc, kc, rc, vc, tc)
  cast(g64, f32)
}
def rhos_call[n](spots: tensor[n, f32], k: f32, r: f32, sigma: f32, t: f32) -> tensor[n, f32] = {
  sc = spot_col(copy(spots))
  kc = const_col(copy(spots), cast(k, f64))
  rc = const_col(copy(spots), cast(r, f64))
  vc = const_col(copy(spots), cast(sigma, f64))
  tc = const_col(spots, cast(t, f64))
  g64 = vmap(fn (sa: tensor[1, f64], ka: tensor[1, f64], ra: tensor[1, f64], va: tensor[1, f64], ta: tensor[1, f64]) -> grad(fn (ss: f64, kk: f64, x: f64, sg: f64, tt: f64) -> bs_call_f64(ss, kk, x, sg, tt), wrt=x)(tensor_to_scalar(sum(sa, 0)), tensor_to_scalar(sum(ka, 0)), tensor_to_scalar(sum(ra, 0)), tensor_to_scalar(sum(va, 0)), tensor_to_scalar(sum(ta, 0))))(sc, kc, rc, vc, tc)
  cast(g64, f32)
}
-- theta = -dC/dt: negate the AD time-derivative.
def thetas_call[n](spots: tensor[n, f32], k: f32, r: f32, sigma: f32, t: f32) -> tensor[n, f32] = {
  sc = spot_col(copy(spots))
  kc = const_col(copy(spots), cast(k, f64))
  rc = const_col(copy(spots), cast(r, f64))
  vc = const_col(copy(spots), cast(sigma, f64))
  tc = const_col(spots, cast(t, f64))
  g64 = vmap(fn (sa: tensor[1, f64], ka: tensor[1, f64], ra: tensor[1, f64], va: tensor[1, f64], ta: tensor[1, f64]) -> grad(fn (ss: f64, kk: f64, rr: f64, sg: f64, x: f64) -> bs_call_f64(ss, kk, rr, sg, x), wrt=x)(tensor_to_scalar(sum(sa, 0)), tensor_to_scalar(sum(ka, 0)), tensor_to_scalar(sum(ra, 0)), tensor_to_scalar(sum(va, 0)), tensor_to_scalar(sum(ta, 0))))(sc, kc, rc, vc, tc)
  cast(neg(g64), f32)
}
-- Second-order Greek vectors via NESTED grad through the same f64 body. Each lane
-- takes grad(grad(bs_call_f64 ...)) so the result is the AD SECOND derivative of
-- the displayed price (the one f64 body), downcast -- gamma/volga are the second
-- derivative wrt one slot, vanna is the mixed s/sigma partial. The explicit-arg
-- form (no free-var capture across vmap/grad) is kept for the same host-evaluator
-- reason the first-order Greeks use it.
-- gamma = d2C/dS2: grad wrt s of (grad wrt s of price).
def gammas_call[n](spots: tensor[n, f32], k: f32, r: f32, sigma: f32, t: f32) -> tensor[n, f32] = {
  sc = spot_col(copy(spots))
  kc = const_col(copy(spots), cast(k, f64))
  rc = const_col(copy(spots), cast(r, f64))
  vc = const_col(copy(spots), cast(sigma, f64))
  tc = const_col(spots, cast(t, f64))
  g64 = vmap(fn (sa: tensor[1, f64], ka: tensor[1, f64], ra: tensor[1, f64], va: tensor[1, f64], ta: tensor[1, f64]) -> grad(fn (x: f64, kk: f64, rr: f64, sg: f64, tt: f64) -> grad(fn (y: f64, k2: f64, r2: f64, s2: f64, t2: f64) -> bs_call_f64(y, k2, r2, s2, t2), wrt=y)(x, kk, rr, sg, tt), wrt=x)(tensor_to_scalar(sum(sa, 0)), tensor_to_scalar(sum(ka, 0)), tensor_to_scalar(sum(ra, 0)), tensor_to_scalar(sum(va, 0)), tensor_to_scalar(sum(ta, 0))))(sc, kc, rc, vc, tc)
  cast(g64, f32)
}
-- volga (vomma) = d2C/dsigma2: grad wrt sigma of (grad wrt sigma of price).
def volgas_call[n](spots: tensor[n, f32], k: f32, r: f32, sigma: f32, t: f32) -> tensor[n, f32] = {
  sc = spot_col(copy(spots))
  kc = const_col(copy(spots), cast(k, f64))
  rc = const_col(copy(spots), cast(r, f64))
  vc = const_col(copy(spots), cast(sigma, f64))
  tc = const_col(spots, cast(t, f64))
  g64 = vmap(fn (sa: tensor[1, f64], ka: tensor[1, f64], ra: tensor[1, f64], va: tensor[1, f64], ta: tensor[1, f64]) -> grad(fn (ss: f64, kk: f64, rr: f64, x: f64, tt: f64) -> grad(fn (s2: f64, k2: f64, r2: f64, y: f64, t2: f64) -> bs_call_f64(s2, k2, r2, y, t2), wrt=y)(ss, kk, rr, x, tt), wrt=x)(tensor_to_scalar(sum(sa, 0)), tensor_to_scalar(sum(ka, 0)), tensor_to_scalar(sum(ra, 0)), tensor_to_scalar(sum(va, 0)), tensor_to_scalar(sum(ta, 0))))(sc, kc, rc, vc, tc)
  cast(g64, f32)
}
-- vanna = d2C/dSdsigma: grad wrt sigma of (grad wrt s of price). Cross partial.
def vannas_call[n](spots: tensor[n, f32], k: f32, r: f32, sigma: f32, t: f32) -> tensor[n, f32] = {
  sc = spot_col(copy(spots))
  kc = const_col(copy(spots), cast(k, f64))
  rc = const_col(copy(spots), cast(r, f64))
  vc = const_col(copy(spots), cast(sigma, f64))
  tc = const_col(spots, cast(t, f64))
  g64 = vmap(fn (sa: tensor[1, f64], ka: tensor[1, f64], ra: tensor[1, f64], va: tensor[1, f64], ta: tensor[1, f64]) -> grad(fn (ss: f64, kk: f64, rr: f64, x: f64, tt: f64) -> grad(fn (y: f64, k2: f64, r2: f64, s2: f64, t2: f64) -> bs_call_f64(y, k2, r2, s2, t2), wrt=y)(ss, kk, rr, x, tt), wrt=x)(tensor_to_scalar(sum(sa, 0)), tensor_to_scalar(sum(ka, 0)), tensor_to_scalar(sum(ra, 0)), tensor_to_scalar(sum(va, 0)), tensor_to_scalar(sum(ta, 0))))(sc, kc, rc, vc, tc)
  cast(g64, f32)
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
