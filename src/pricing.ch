module Shoals.Pricing
import Nautilus.Distributions (normal_sample)
export (erf64, n_cdf64, bs_call_scalar, bs_put_scalar, bs_call_f64, bs_call_f64_vector, bs_call_wire_f64, call_prices, put_prices, call_total, put_total, deltas_call, deltas_put, vegas_call, rhos_call, thetas_call, gammas_call, volgas_call, vannas_call, mc_call_price)
-- Pricing uses Chelis's correctly rounded erf and standard normal CDF.
-- Keep the exported f64 names because Shoals schema major 1 is additive-only.
def erf64(x: f64) -> f64 = erf(x)
def n_cdf64(x: f64) -> f64 = standard_normal_cdf(x)
-- DENOMINATOR FLOOR, and why it is a clamp rather than a branch on the price.
--
-- `sigma*sqrt(t)` is exactly 0 whenever t = 0 or sigma = 0, i.e. whenever there
-- is no remaining uncertainty. For num != 0 the unguarded division already
-- behaved correctly: +/-inf saturates the normal CDF and the formula collapses to
-- `max(s - k*exp(-rt), 0)`, which is the right answer. The defect (shoals#88)
-- is only the point where num is ALSO 0 -- the forward sitting exactly on the
-- strike -- where 0/0 is NaN. Measured members of that class: s = k with t = 0
-- (any sigma, any r), and s = k with sigma = 0 and r = 0 at any t. The issue
-- describes it as an expiry bug; the second member is not one.
--
-- Flooring the denominator fixes all of them at once: num/floor is 0 when
-- num is 0, so d1 = d2 = 0, both normal CDFs are 0.5, and the price is
-- 0.5*s - 0.5*k*exp(-rt) = 0 exactly when the forward is at the strike, which
-- is the correct intrinsic. For num != 0, num/floor is a large finite number
-- that saturates the normal CDF identically to the +/-inf it replaces, so no
-- currently-correct value moves.
--
-- IT MUST BE A CLAMP ON THE DENOMINATOR, NOT A BRANCH ON THE PRICE -- and the
-- reason is the ADJOINT, not the value. Measure before changing this: the
-- untaken arm's NaN *value* does NOT propagate at this pin.
-- `vmap(if eq(x,0) then 7.0 else div(x,x))` over `[0.0, 2.0]` evaluates to
-- `[7.0, 1.0]`, and the rejected counterfactual
-- `if t = 0 then max(s-k,0) else <formula>` with an unfloored `d1` returns the
-- CORRECT PRICE at every lane. What it does not return is a usable delta: that
-- comes back NaN, because the adjoint multiplies the untaken arm's derivative
-- by the zero mask and the untaken arm's derivative is infinite. A test of the
-- price alone will therefore say the branch is fine. It is not.
--
-- The hazard is not vmap-specific either: `grad(if lt(x,1) then 2.0 else
-- sqrt(x))` at x = 0 is NaN with no `vmap` anywhere, the untaken arm's value
-- being a finite 0.0 while its derivative is infinite. This is the derivative
-- rule the chelis#2640 entry in `docs/UPSTREAM_BUGS.md` states; every Greek and
-- both f32 entry points differentiate this body, so it binds here.
--
-- THIS CLAMP IS SAFE IN THE s AND sigma DIRECTIONS ONLY, and an earlier revision
-- of this comment claimed it was safe outright. It is not. The untaken arm is
-- `den = sigma*sqrt(t)`, whose t-derivative is sigma/(2*sqrt(t)) = +inf at
-- t = 0, so differentiating wrt t at expiry is exactly the chelis#2640 case.
-- Measured: `grad` of this clamp wrt t is NaN at t = 0, and 0.1 at t = 1. wrt s
-- the untaken arm does not depend on s at all, and its sigma-derivative is
-- sqrt(t) = 0 at t = 0, so both of those directions are finite and clean
-- -- which is why delta, vega and rho are correct at t = 0 and theta was not.
-- The t = 0 Greeks are therefore supplied as closed-form limits in the wrappers
-- rather than by differentiating this body; see the shoals#101 note above
-- `const_vec`. Do not "fix" that by branching in here: a branch on t inside the
-- differentiated body reintroduces the same adjoint problem one level up.
def d1_64(s: f64, k: f64, r: f64, sigma: f64, t: f64) -> f64 = {
  num = add(log(div(s, k)), mul(add(r, mul(cast(0.5, f64), mul(sigma, sigma))), t))
  den = mul(sigma, sqrt(t))
  div(num, if lt(den, cast(1e-300, f64)) then cast(1e-300, f64) else den)
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
-- f32 entry points: compute via the f64 body and downcast.
def bs_call_scalar(s: f32, k: f32, r: f32, sigma: f32, t: f32) -> f32 = cast(bs_call_f64(cast(s, f64), cast(k, f64), cast(r, f64), cast(sigma, f64), cast(t, f64)), f32)
def bs_put_scalar(s: f32, k: f32, r: f32, sigma: f32, t: f32) -> f32 = cast(bs_put_f64(cast(s, f64), cast(k, f64), cast(r, f64), cast(sigma, f64), cast(t, f64)), f32)
-- Vectorization helpers. vmap cannot capture free f64 vars in the host evaluator
-- (missing-input error), so every scalar param is broadcast to an [n, 1] column
-- and each vmap lane pulls its cell out with tensor_to_scalar(sum(col, 0)); no
-- free var crosses the vmap/grad boundary. const_col builds non-differentiated
-- inputs, so the host-lane map in its fill never has grad flow through it.
def const_col[n](spots: tensor[n, f32], v: f64) -> tensor[n, 1, f64] = {
  nn = cast(shape(copy(spots), cast(0, i32)), i64)
  reshape(to_tensor(map(fn (i: i64) -> v, range(cast(0, i64), nn))), [nn, cast(1, i64)])
}
def spot_col[n](spots: tensor[n, f32]) -> tensor[n, 1, f64] = {
  nn = cast(shape(copy(spots), cast(0, i32)), i64)
  reshape(cast(spots, f64), [nn, cast(1, i64)])
}
def f64_col[n](xs: tensor[n, f64]) -> tensor[n, 1, f64] = {
  nn = cast(shape(copy(xs), cast(0, i32)), i64)
  reshape(xs, [nn, cast(1, i64)])
}
-- Pure tensor-DAG Black-Scholes helpers for the Beacon seam (shoals issue 19).
-- Constants are point-valued tensor inputs because introducing them through
-- host-only shape/vmap plumbing would erase the named WireDag root.
--
-- This path does not evaluate `erf64`. Its erf uses the caller-supplied
-- Abramowitz & Stegun coefficients to preserve the public WireDag input
-- contract. The scalar path uses Chelis's correctly rounded builtin, so the
-- two paths agree only within the scale-aware bound in `tests/pricing.ch`.
def pricing_wire_select_f64[n](mask: &tensor[n, f64], a: tensor[n, f64], b: tensor[n, f64], half: &tensor[n, f64]) -> tensor[n, f64] = {
  one = add(copy(half), copy(half))
  add(mul(copy(mask), a), mul(sub(one, copy(mask)), b))
}
def pricing_wire_abs_f64[n](x: &tensor[n, f64], half: &tensor[n, f64]) -> tensor[n, f64] = {
  neg_mask = cast(lt(copy(x), sub(copy(half), copy(half))), f64)
  pricing_wire_select_f64(&neg_mask, neg(copy(x)), copy(x), half)
}
def pricing_wire_erf_f64[n](x: &tensor[n, f64], a1: &tensor[n, f64], a2: &tensor[n, f64], a3: &tensor[n, f64], a4: &tensor[n, f64], a5: &tensor[n, f64], p: &tensor[n, f64], two_over_sqrt_pi: &tensor[n, f64], small: &tensor[n, f64], half: &tensor[n, f64]) -> tensor[n, f64] = {
  one = add(copy(half), copy(half))
  ax = pricing_wire_abs_f64(x, half)
  linear = mul(copy(x), copy(two_over_sqrt_pi))
  t_v = div(copy(&one), add(copy(&one), mul(copy(p), copy(&ax))))
  poly = mul(copy(&t_v), add(copy(a1), mul(copy(&t_v), add(copy(a2), mul(copy(&t_v), add(copy(a3), mul(copy(&t_v), add(copy(a4), mul(copy(&t_v), copy(a5))))))))))
  y = sub(one, mul(poly, exp(neg(mul(copy(&ax), copy(&ax))))))
  neg_mask = cast(lt(copy(x), sub(copy(half), copy(half))), f64)
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
-- DENOMINATOR FLOOR, wire lane. Same defect as `d1_64` above (shoals#88) and a
-- strictly worse symptom: the scalar lane only returned NaN where num was ALSO
-- zero, because +/-inf saturates the scalar normal CDF. This lane returned NaN at EVERY
-- moneyness on expiry, measured, because nothing here saturates -- every
-- selector is arithmetic, and `0 * inf` is NaN.
--
-- The first NaN is in `pricing_wire_abs_f64`: at x = +inf its mask is 0 and it
-- evaluates `0 * neg(inf) + 1 * inf`, whose first term is NaN. Note what this
-- is and is not. It is plain arithmetic in THIS lane's own hand-rolled select,
-- so it needs no upstream citation: `0 * inf` is NaN by IEEE, whatever the
-- compiler does with a real `if`. The scalar lane is not exposed to it, because
-- a scalar `if` is a genuine select and does not propagate the untaken arm's
-- value. This lane has no `if` to use: it must stay producer-clean for the
-- WireDag seam, so every selector here is multiplication and addition.
-- `linear` has the same shape: `x * two_over_sqrt_pi` is inf, and the
-- `small_mask` select multiplies it by 0.
--
-- So the fix is to keep x FINITE rather than to patch each selector: with a
-- floored denominator every intermediate is a large finite number, `0 * finite`
-- is 0, and all three selects behave. The floor is `small^8` (1e-40), built by
-- squaring rather than taken as a new parameter: `small` is already one of the
-- 15 named loads this entry is pinned against, so threading it here changes no
-- load and leaves `bs_call_wire_f64`'s public signature alone. Note that
-- `small` is a public parameter, so `small^8` is 1e-40 at the value every call
-- site in this repo passes rather than as a property of this function; for any
-- `small` small enough to be a correct erf linearisation threshold (<= 0.1) the
-- floor is at most 1e-8, still far below any reachable denominator. 1e-40 is below
-- any reachable `sigma*sqrt(t)` -- a 0.01 vol over one day is 5e-4 -- so no
-- value that works today moves.
def pricing_wire_d1_f64[n](s: &tensor[n, f64], k: &tensor[n, f64], r: &tensor[n, f64], sigma: &tensor[n, f64], t: &tensor[n, f64], half: &tensor[n, f64], small: &tensor[n, f64]) -> tensor[n, f64] = {
  num = add(log(div(copy(s), copy(k))), mul(add(copy(r), mul(copy(half), mul(copy(sigma), copy(sigma)))), copy(t)))
  den = mul(copy(sigma), sqrt(copy(t)))
  sq2 = mul(copy(small), copy(small))
  sq4 = mul(copy(&sq2), copy(&sq2))
  den_floor = mul(copy(&sq4), copy(&sq4))
  floor_mask = cast(lt(copy(&den), copy(&den_floor)), f64)
  div(num, pricing_wire_select_f64(&floor_mask, copy(&den_floor), den, half))
}
-- A producer-clean tensor entry for content-addressed WireDag consumers.
-- It deliberately contains no `vmap`, `shape`, scalar conversion, or host
-- list operation. Beacon binds the coefficient inputs to point intervals.
def bs_call_wire_f64[n](s: tensor[n, f64], k: tensor[n, f64], r: tensor[n, f64], sigma: tensor[n, f64], t: tensor[n, f64], half: tensor[n, f64], inv_sqrt_2: tensor[n, f64], a1: tensor[n, f64], a2: tensor[n, f64], a3: tensor[n, f64], a4: tensor[n, f64], a5: tensor[n, f64], p: tensor[n, f64], two_over_sqrt_pi: tensor[n, f64], small: tensor[n, f64]) -> tensor[n, f64] = {
  d1_v = pricing_wire_d1_f64(&s, &k, &r, &sigma, &t, &half, &small)
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
-- EXPIRY LIMITS FOR THE GREEK VECTORS (shoals#101).
--
-- At t = 0 the AD path cannot produce the limits, for two measured reasons, and
-- neither is fixable by adjusting the price body:
--
--   1. `thetas_call` differentiates wrt t, and the shoals#88 denominator clamp's
--      UNTAKEN arm is `sigma*sqrt(t)`, whose t-derivative is sigma/(2*sqrt(t)) =
--      +inf at t = 0. chelis#2640 then poisons the result even though the
--      constant arm is the one selected. Measured: `grad` of that clamp wrt t is
--      NaN at t = 0 and 0.1 at t = 1. The clamp stays safe for the s and sigma
--      directions, which is exactly why delta, vega and rho survive at t = 0 --
--      the untaken arm does not depend on s at all, and its sigma-derivative
--      is sqrt(t), which is 0 at t = 0 rather than unbounded.
--   2. The second-order Greeks square a first derivative that the floor has made
--      enormous: d(d1)/ds = 1/(s*den) is 1e298 with den floored to 1e-300, and
--      squaring that overflows to +inf, which then multiplies an underflowed
--      second-order factor. Measured: 0 * inf = NaN.
--
-- So the limits are supplied in closed form HERE, in the wrappers, rather than
-- by differentiating. That is sound because nothing differentiates these
-- wrappers: the `if` below is an ordinary scalar branch on a parameter, outside
-- every `grad` and `vmap`, so no adjoint sees it.
--
-- Per-lane selection uses `where`, NOT a hand-rolled arithmetic select. This is
-- the one place on this surface where that distinction decides a value: the
-- gamma limit is +inf at the strike, and an arithmetic select computes
-- `0 * inf = NaN` for every OTHER lane. Measured, side by side:
--   where(...)                      -> [inf, 0.0, 0.0]
--   mask*inf + (1-mask)*0           -> [inf, NaN, NaN]
-- `where` is a genuine elementwise select and does not evaluate the unselected
-- branch into the result. Do not "simplify" it into arithmetic.
def const_vec[n](template: tensor[n, f32], v: f32) -> tensor[n, f32] = {
  nn = cast(shape(copy(template), cast(0, i32)), i64)
  to_tensor(map(fn (i: i64) -> v, range(cast(0, i64), nn)))
}
def pricing_inf32() -> f32 = div(cast(1.0, f32), cast(0.0, f32))
-- delta at t = 0: 1 above the strike, 0 below, and 0.5 AT it. The 0.5 is the
-- limit in TIME at s = k, not a convention: d1 = (r + sigma^2/2)*sqrt(t)/sigma
-- tends to 0 there, so N(d1) tends to N(0). Measured approach at s = k = 100:
-- 0.6368 at t=1, 0.5140 at t=1e-2, 0.5014 at t=1e-4, 0.50014 at t=1e-6.
def delta_call_at_expiry[n](spots: tensor[n, f32], k: f32) -> tensor[n, f32] = {
  kv = const_vec(copy(spots), k)
  above = cast(gt(copy(spots), copy(&kv)), f32)
  at = mul(cast(eq(spots, kv), f32), const_vec(copy(&above), cast(0.5, f32)))
  add(above, at)
}
-- put delta at t = 0: -1 below the strike, 0 above, -0.5 AT it. Same reasoning as
-- the call: at expiry the price is max(k - s, 0), whose derivative is -1 below
-- the strike and 0 above, and the limit in time at s = k is -N(0) = -0.5.
-- Measured approach at s = k = 100: -0.48604 at t=1e-2 and -0.49860 at t=1e-4.
def delta_put_at_expiry[n](spots: tensor[n, f32], k: f32) -> tensor[n, f32] = {
  kv = const_vec(copy(spots), k)
  below = cast(lt(copy(spots), copy(&kv)), f32)
  at = mul(cast(eq(spots, kv), f32), const_vec(copy(&below), cast(0.5, f32)))
  -- Subtract from zero rather than negating the sum: `neg` turns the
  -- above-the-strike cell into -0.0, which compares equal to 0.0 but prints
  -- asymmetrically beside the call surface's 0.0.
  sub(const_vec(copy(&below), cast(0.0, f32)), add(below, at))
}
-- gamma at t = 0: 0 away from the strike, +inf at it. The divergence is real --
-- gamma ~ 1/(s*sigma*sqrt(t)) -- so a finite answer here would be a lie.
-- Measured approach at s = k = 100: 0.199 at t=1e-2, 1.995 at t=1e-4.
def gamma_call_at_expiry[n](spots: tensor[n, f32], k: f32) -> tensor[n, f32] = {
  kv = const_vec(copy(spots), k)
  where(eq(spots, copy(&kv)), const_vec(copy(&kv), pricing_inf32()), const_vec(kv, cast(0.0, f32)))
}
-- theta at t = 0: -r*k above the strike (the price is s - k*exp(-rt) there, so
-- dC/dt = r*k*exp(-rt) and theta = -dC/dt = -r*k), 0 below, and -inf at the
-- strike. Measured approach: -4.998 at t=1e-2 and -4.99998 at t=1e-4 for
-- s = 110, k = 100, r = 5% (so -r*k = -5); -42 then -401 at s = k.
def theta_call_at_expiry[n](spots: tensor[n, f32], k: f32, r: f32) -> tensor[n, f32] = {
  kv = const_vec(copy(spots), k)
  itm = const_vec(copy(&kv), neg(mul(r, k)))
  zero = const_vec(copy(&kv), cast(0.0, f32))
  off = where(gt(copy(spots), copy(&kv)), itm, zero)
  where(eq(spots, kv), const_vec(copy(&off), neg(pricing_inf32())), off)
}
-- First-order Greek vectors via vmap(grad(price)) through the f64 body. Each lane
-- differentiates bs_call_f64 wrt one slot with the others passed explicitly (no
-- capture), so the result is the AD derivative of the displayed price, downcast.
def deltas_call[n](spots: tensor[n, f32], k: f32, r: f32, sigma: f32, t: f32) -> tensor[n, f32] =
  if eq(t, cast(0.0, f32)) then delta_call_at_expiry(spots, k) else {
    sc = spot_col(copy(spots))
    kc = const_col(copy(spots), cast(k, f64))
    rc = const_col(copy(spots), cast(r, f64))
    vc = const_col(copy(spots), cast(sigma, f64))
    tc = const_col(spots, cast(t, f64))
    g64 = vmap(fn (sa: tensor[1, f64], ka: tensor[1, f64], ra: tensor[1, f64], va: tensor[1, f64], ta: tensor[1, f64]) -> grad(fn (x: f64, kk: f64, rr: f64, sg: f64, tt: f64) -> bs_call_f64(x, kk, rr, sg, tt), wrt=x)(tensor_to_scalar(sum(sa, 0)), tensor_to_scalar(sum(ka, 0)), tensor_to_scalar(sum(ra, 0)), tensor_to_scalar(sum(va, 0)), tensor_to_scalar(sum(ta, 0))))(sc, kc, rc, vc, tc)
    cast(g64, f32)
  }
def deltas_put[n](spots: tensor[n, f32], k: f32, r: f32, sigma: f32, t: f32) -> tensor[n, f32] =
  if eq(t, cast(0.0, f32)) then delta_put_at_expiry(spots, k) else {
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
def thetas_call[n](spots: tensor[n, f32], k: f32, r: f32, sigma: f32, t: f32) -> tensor[n, f32] =
  if eq(t, cast(0.0, f32)) then theta_call_at_expiry(spots, k, r) else {
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
def gammas_call[n](spots: tensor[n, f32], k: f32, r: f32, sigma: f32, t: f32) -> tensor[n, f32] =
  if eq(t, cast(0.0, f32)) then gamma_call_at_expiry(spots, k) else {
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
def vannas_call[n](spots: tensor[n, f32], k: f32, r: f32, sigma: f32, t: f32) -> tensor[n, f32] =
  if eq(t, cast(0.0, f32)) then const_vec(spots, cast(0.0, f32)) else {
    sc = spot_col(copy(spots))
    kc = const_col(copy(spots), cast(k, f64))
    rc = const_col(copy(spots), cast(r, f64))
    vc = const_col(copy(spots), cast(sigma, f64))
    tc = const_col(spots, cast(t, f64))
    g64 = vmap(fn (sa: tensor[1, f64], ka: tensor[1, f64], ra: tensor[1, f64], va: tensor[1, f64], ta: tensor[1, f64]) -> grad(fn (ss: f64, kk: f64, rr: f64, x: f64, tt: f64) -> grad(fn (y: f64, k2: f64, r2: f64, s2: f64, t2: f64) -> bs_call_f64(y, k2, r2, s2, t2), wrt=y)(ss, kk, rr, x, tt), wrt=x)(tensor_to_scalar(sum(sa, 0)), tensor_to_scalar(sum(ka, 0)), tensor_to_scalar(sum(ra, 0)), tensor_to_scalar(sum(va, 0)), tensor_to_scalar(sum(ta, 0))))(sc, kc, rc, vc, tc)
    cast(g64, f32)
  }
def mc_call_price[n](rng_key: key, template: tensor[n, f32], s0: f32, k: f32, r: f32, sigma: f32, t: f32) -> f32 = {
  z = normal_sample(rng_key, template, cast(0.0, f32), cast(1.0, f32))
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
