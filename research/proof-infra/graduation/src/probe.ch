module GradScratch.Probe
export (erf64, n_cdf64, bs_call_f64, bs_put_f64, scalar_delta, scalar_vega, scalar_rho, scalar_dcdt, call_prices_v, put_prices_v, deltas_v, vegas_v, rhos_v, thetas_v)
-- |x|, branch-free-ish via if (lowers to masked arithmetic)
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
def erfc64(x: f64) -> f64 = sub(cast(1.0, f64), erf64(x))
def n_cdf64(x: f64) -> f64 = {
  inv_sqrt_2 = cast(0.7071067811865476, f64)
  mul(cast(0.5, f64), erfc64(neg(mul(x, inv_sqrt_2))))
}
def d1_64(s: f64, k: f64, r: f64, sigma: f64, t: f64) -> f64 = {
  num = add(log(div(s, k)), mul(add(r, mul(cast(0.5, f64), mul(sigma, sigma))), t))
  den = mul(sigma, sqrt(t))
  div(num, den)
}
def d2_64(s: f64, k: f64, r: f64, sigma: f64, t: f64) -> f64 = sub(d1_64(s, k, r, sigma, t), mul(sigma, sqrt(t)))
def bs_call_f64(s: f64, k: f64, r: f64, sigma: f64, t: f64) -> f64 = {
  d1v = d1_64(s, k, r, sigma, t)
  d2v = d2_64(s, k, r, sigma, t)
  nd1 = n_cdf64(d1v)
  nd2 = n_cdf64(d2v)
  disc = exp(neg(mul(r, t)))
  sub(mul(s, nd1), mul(k, mul(disc, nd2)))
}
def bs_put_f64(s: f64, k: f64, r: f64, sigma: f64, t: f64) -> f64 = {
  d1v = d1_64(s, k, r, sigma, t)
  d2v = d2_64(s, k, r, sigma, t)
  nnd1 = n_cdf64(neg(d1v))
  nnd2 = n_cdf64(neg(d2v))
  disc = exp(neg(mul(r, t)))
  sub(mul(k, mul(disc, nnd2)), mul(s, nnd1))
}
-- PATTERN TEST 1: scalar grad of a NAMED fn with all args explicit (no capture).
-- This is the package-safe form (research trackB_capture_bug case 4).
def scalar_delta(s: f64, k: f64, r: f64, sigma: f64, t: f64) -> f64 = grad(fn (x: f64, kk: f64, rr: f64, sg: f64, tt: f64) -> bs_call_f64(x, kk, rr, sg, tt), wrt=x)(s, k, r, sigma, t)
def scalar_vega(s: f64, k: f64, r: f64, sigma: f64, t: f64) -> f64 = grad(fn (ss: f64, kk: f64, rr: f64, x: f64, tt: f64) -> bs_call_f64(ss, kk, rr, x, tt), wrt=x)(s, k, r, sigma, t)
def scalar_rho(s: f64, k: f64, r: f64, sigma: f64, t: f64) -> f64 = grad(fn (ss: f64, kk: f64, x: f64, sg: f64, tt: f64) -> bs_call_f64(ss, kk, x, sg, tt), wrt=x)(s, k, r, sigma, t)
def scalar_dcdt(s: f64, k: f64, r: f64, sigma: f64, t: f64) -> f64 = grad(fn (ss: f64, kk: f64, rr: f64, sg: f64, x: f64) -> bs_call_f64(ss, kk, rr, sg, x), wrt=x)(s, k, r, sigma, t)
-- Build a length-n f64 column [n,1] all equal to v. Host-lane map is fine here:
-- this builds NON-differentiated inputs; nothing flows grad through the fill.
def const_col[n](spots: tensor[n, f32], v: f64) -> tensor[n, 1, f64] = {
  nn = cast(shape(copy(spots), cast(0, int32)), int64)
  reshape(to_tensor(map(fn (i: int64) -> v, range(cast(0, int64), nn))), [nn, cast(1, int64)])
}
def spot_col[n](spots: tensor[n, f32]) -> tensor[n, 1, f64] = {
  nn = cast(shape(copy(spots), cast(0, int32)), int64)
  reshape(cast(spots, f64), [nn, cast(1, int64)])
}
-- PATTERN TEST 2: tensor-lane vectorized prices via multi-arg vmap (NO capture).
-- vmap can't capture free f64 vars in the host evaluator (missing-input bug), so
-- every scalar param is passed in as a broadcast [n,1] column and the lambda
-- pulls each cell out via tensor_to_scalar(sum(col, 0)). No free vars cross vmap.
def call_prices_v[n](spots: tensor[n, f32], k: f32, r: f32, sigma: f32, t: f32) -> tensor[n, f32] = {
  sc = spot_col(copy(spots))
  kc = const_col(copy(spots), cast(k, f64))
  rc = const_col(copy(spots), cast(r, f64))
  vc = const_col(copy(spots), cast(sigma, f64))
  tc = const_col(spots, cast(t, f64))
  prices64 = vmap(fn (sa: tensor[1, f64], ka: tensor[1, f64], ra: tensor[1, f64], va: tensor[1, f64], ta: tensor[1, f64]) -> bs_call_f64(tensor_to_scalar(sum(sa, 0)), tensor_to_scalar(sum(ka, 0)), tensor_to_scalar(sum(ra, 0)), tensor_to_scalar(sum(va, 0)), tensor_to_scalar(sum(ta, 0))))(sc, kc, rc, vc, tc)
  cast(prices64, f32)
}
def put_prices_v[n](spots: tensor[n, f32], k: f32, r: f32, sigma: f32, t: f32) -> tensor[n, f32] = {
  sc = spot_col(copy(spots))
  kc = const_col(copy(spots), cast(k, f64))
  rc = const_col(copy(spots), cast(r, f64))
  vc = const_col(copy(spots), cast(sigma, f64))
  tc = const_col(spots, cast(t, f64))
  prices64 = vmap(fn (sa: tensor[1, f64], ka: tensor[1, f64], ra: tensor[1, f64], va: tensor[1, f64], ta: tensor[1, f64]) -> bs_put_f64(tensor_to_scalar(sum(sa, 0)), tensor_to_scalar(sum(ka, 0)), tensor_to_scalar(sum(ra, 0)), tensor_to_scalar(sum(va, 0)), tensor_to_scalar(sum(ta, 0))))(sc, kc, rc, vc, tc)
  cast(prices64, f32)
}
-- PATTERN TEST 3: tensor-lane deltas via vmap(grad(price wrt spot)), no capture.
def deltas_v[n](spots: tensor[n, f32], k: f32, r: f32, sigma: f32, t: f32) -> tensor[n, f32] = {
  sc = spot_col(copy(spots))
  kc = const_col(copy(spots), cast(k, f64))
  rc = const_col(copy(spots), cast(r, f64))
  vc = const_col(copy(spots), cast(sigma, f64))
  tc = const_col(spots, cast(t, f64))
  d64 = vmap(fn (sa: tensor[1, f64], ka: tensor[1, f64], ra: tensor[1, f64], va: tensor[1, f64], ta: tensor[1, f64]) -> grad(fn (x: f64, kk: f64, rr: f64, sg: f64, tt: f64) -> bs_call_f64(x, kk, rr, sg, tt), wrt=x)(tensor_to_scalar(sum(sa, 0)), tensor_to_scalar(sum(ka, 0)), tensor_to_scalar(sum(ra, 0)), tensor_to_scalar(sum(va, 0)), tensor_to_scalar(sum(ta, 0))))(sc, kc, rc, vc, tc)
  cast(d64, f32)
}
-- vega = dC/dsigma (grad wrt the sigma slot).
def vegas_v[n](spots: tensor[n, f32], k: f32, r: f32, sigma: f32, t: f32) -> tensor[n, f32] = {
  sc = spot_col(copy(spots))
  kc = const_col(copy(spots), cast(k, f64))
  rc = const_col(copy(spots), cast(r, f64))
  vc = const_col(copy(spots), cast(sigma, f64))
  tc = const_col(spots, cast(t, f64))
  v64 = vmap(fn (sa: tensor[1, f64], ka: tensor[1, f64], ra: tensor[1, f64], va: tensor[1, f64], ta: tensor[1, f64]) -> grad(fn (ss: f64, kk: f64, rr: f64, x: f64, tt: f64) -> bs_call_f64(ss, kk, rr, x, tt), wrt=x)(tensor_to_scalar(sum(sa, 0)), tensor_to_scalar(sum(ka, 0)), tensor_to_scalar(sum(ra, 0)), tensor_to_scalar(sum(va, 0)), tensor_to_scalar(sum(ta, 0))))(sc, kc, rc, vc, tc)
  cast(v64, f32)
}
-- rho = dC/dr (grad wrt the r slot).
def rhos_v[n](spots: tensor[n, f32], k: f32, r: f32, sigma: f32, t: f32) -> tensor[n, f32] = {
  sc = spot_col(copy(spots))
  kc = const_col(copy(spots), cast(k, f64))
  rc = const_col(copy(spots), cast(r, f64))
  vc = const_col(copy(spots), cast(sigma, f64))
  tc = const_col(spots, cast(t, f64))
  r64 = vmap(fn (sa: tensor[1, f64], ka: tensor[1, f64], ra: tensor[1, f64], va: tensor[1, f64], ta: tensor[1, f64]) -> grad(fn (ss: f64, kk: f64, x: f64, sg: f64, tt: f64) -> bs_call_f64(ss, kk, x, sg, tt), wrt=x)(tensor_to_scalar(sum(sa, 0)), tensor_to_scalar(sum(ka, 0)), tensor_to_scalar(sum(ra, 0)), tensor_to_scalar(sum(va, 0)), tensor_to_scalar(sum(ta, 0))))(sc, kc, rc, vc, tc)
  cast(r64, f32)
}
-- theta = -dC/dt (grad wrt the t slot, negated).
def thetas_v[n](spots: tensor[n, f32], k: f32, r: f32, sigma: f32, t: f32) -> tensor[n, f32] = {
  sc = spot_col(copy(spots))
  kc = const_col(copy(spots), cast(k, f64))
  rc = const_col(copy(spots), cast(r, f64))
  vc = const_col(copy(spots), cast(sigma, f64))
  tc = const_col(spots, cast(t, f64))
  dcdt64 = vmap(fn (sa: tensor[1, f64], ka: tensor[1, f64], ra: tensor[1, f64], va: tensor[1, f64], ta: tensor[1, f64]) -> grad(fn (ss: f64, kk: f64, rr: f64, sg: f64, x: f64) -> bs_call_f64(ss, kk, rr, sg, x), wrt=x)(tensor_to_scalar(sum(sa, 0)), tensor_to_scalar(sum(ka, 0)), tensor_to_scalar(sum(ra, 0)), tensor_to_scalar(sum(va, 0)), tensor_to_scalar(sum(ta, 0))))(sc, kc, rc, vc, tc)
  cast(neg(dcdt64), f32)
}
