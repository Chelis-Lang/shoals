module Shoals.Pricing
import Nautilus.Distributions (normal_sample)
export (erf64, n_cdf64, bs_call_scalar, bs_put_scalar, bs_call_f64, bs_call_f64_vector, bs_call_wire_f64, call_prices, put_prices, call_total, put_total, deltas_call, deltas_put, vegas_call, rhos_call, thetas_call, gammas_call, volgas_call, vannas_call, mc_call_price)
-- One normal CDF behind both price and Greeks. n_cdf(x) = 0.5 * erfc(-x/sqrt2)
-- is the exact expression Shoals.References / Shoals.Greeks use. The displayed
-- Greek is the AD derivative of THIS expression, so price and Greek agree.
--
-- ACCURACY. `erf64` evaluates W. J. Cody's rational approximation (Math. Comp.
-- 23, 1969): three ranges split at 0.5 and 4, saturating at 6 where erfc
-- underflows f64. Worst observed absolute error >= 3.3675e-16 (~1.52 ulp of
-- 1.0) at x = 0.507001975, measured at 60 dps by
-- `scripts/oracle_erf64_accuracy.py`. That is a FLOOR: the error is jagged at
-- ulp scale, so a grid reports only the worst point it lands on. Re-measure by
-- running the oracle; docs/CHELIS_SURFACE.md carries the figures.
--
-- It replaced Abramowitz & Stegun 7.1.26 (this shell's issue 61), whose ~1.4e-7
-- bound is a property of its coefficients rather than of the arithmetic, so the
-- f64 entry point had been no better than the f32 `Nautilus.Special.erf` whose
-- coefficients it copied. Hand-rolled here because Chelis has no canonical erf
-- (chelis#902) and `Nautilus.Special` is f32-only (nautilus#59,
-- tests_blocked/special/erf_builtin_absent.ch); the f32 sibling keeps the old
-- bound (nautilus#56).
--
-- Three named helpers rather than one expression, because the AD Greeks
-- differentiate through this path and each branch is separately checkable.
-- `abs` is the intrinsic, not a hand-rolled `if`: that would have the operand
-- as its untaken arm, which under vmap's masked select returns NaN at +inf
-- (chelis#2103).
def abs_f64(x: f64) -> f64 = abs(x)
-- Cody region 1 (|x| <= 0.5): erf(x) = x * P(x^2)/Q(x^2), odd by construction.
def erf64_core_small(x: f64) -> f64 = {
  -- Domain clamp. See the note above `erf64` for why every core clamps.
  xc = if lt(x, cast(-0.5, f64)) then cast(-0.5, f64) else if lt(cast(0.5, f64), x) then cast(0.5, f64) else x
  y = mul(xc, xc)
  xnum0 = mul(cast(0.18577770618460315, f64), y)
  xden0 = y
  xnum1 = mul(add(xnum0, cast(3.1611237438705655, f64)), y)
  xden1 = mul(add(xden0, cast(23.601290952344122, f64)), y)
  xnum2 = mul(add(xnum1, cast(113.86415415105016, f64)), y)
  xden2 = mul(add(xden1, cast(244.02463793444417, f64)), y)
  xnum3 = mul(add(xnum2, cast(377.485237685302, f64)), y)
  xden3 = mul(add(xden2, cast(1282.6165260773723, f64)), y)
  mul(xc, div(add(xnum3, cast(3209.3775891384694, f64)), add(xden3, cast(2844.236833439171, f64))))
}
-- Cody region 2 (0.5 < |x| < 4): erfc(|x|) = exp(-x^2) * P(|x|)/Q(|x|).
-- The dispatcher routes |x| == 4 to region 3; Cody's CALERF puts it here
-- (`IF (Y .LE. FOUR)`), where it is one ulp better. See this shell's issue 68.
def erf64_core_erfc_mid(axr: f64) -> f64 = {
  -- Domain clamp. See the note above `erf64` for why every core clamps.
  ax = if lt(cast(4.0, f64), axr) then cast(4.0, f64) else axr
  xnum0 = mul(cast(2.1531153547440383e-8, f64), ax)
  xden0 = ax
  xnum1 = mul(add(xnum0, cast(0.5641884969886701, f64)), ax)
  xden1 = mul(add(xden0, cast(15.744926110709835, f64)), ax)
  xnum2 = mul(add(xnum1, cast(8.883149794388377, f64)), ax)
  xden2 = mul(add(xden1, cast(117.6939508913125, f64)), ax)
  xnum3 = mul(add(xnum2, cast(66.11919063714163, f64)), ax)
  xden3 = mul(add(xden2, cast(537.1811018620099, f64)), ax)
  xnum4 = mul(add(xnum3, cast(298.6351381974001, f64)), ax)
  xden4 = mul(add(xden3, cast(1621.3895745666903, f64)), ax)
  xnum5 = mul(add(xnum4, cast(881.952221241769, f64)), ax)
  xden5 = mul(add(xden4, cast(3290.7992357334597, f64)), ax)
  xnum6 = mul(add(xnum5, cast(1712.0476126340707, f64)), ax)
  xden6 = mul(add(xden5, cast(4362.619090143247, f64)), ax)
  xnum7 = mul(add(xnum6, cast(2051.0783778260716, f64)), ax)
  xden7 = mul(add(xden6, cast(3439.3676741437216, f64)), ax)
  mul(exp(neg(mul(ax, ax))), div(add(xnum7, cast(1230.3393547979972, f64)), add(xden7, cast(1230.3393548037495, f64))))
}
-- Cody region 3 (4 <= |x| < 6): erfc(|x|) = exp(-x^2)/|x| * (1/sqrt(pi) - R(1/x^2)).
def erf64_core_erfc_tail(axr: f64) -> f64 = {
  -- LOWER clamp only, and the asymmetry is the point. A clamp is safe only when
  -- its UNTAKEN arm has a finite VALUE *and* a finite DERIVATIVE. The
  -- derivative half is not decoration: `if lt(x, 1.0) then 2.0 else sqrt(x)`
  -- has a finite untaken value at x = 0 and still grads to NaN, because the
  -- adjoint multiplies the untaken arm's derivative (+inf) by the 0 mask. Here
  -- the untaken arm is the constant 1.0, so an unbounded operand never reaches
  -- the multiply. NO UPPER CLAMP: its untaken arm would be the operand, +inf at
  -- ax = +inf, so `0 * inf = NaN` -- and this branch is total at +inf where
  -- regions 1 and 2 are not. Adding one for uniformity removes that.
  guarded = if lt(axr, cast(1.0, f64)) then cast(1.0, f64) else axr
  ax = guarded
  y = div(cast(1.0, f64), mul(guarded, guarded))
  xnum0 = mul(cast(0.016315387137302097, f64), y)
  xden0 = y
  xnum1 = mul(add(xnum0, cast(0.30532663496123236, f64)), y)
  xden1 = mul(add(xden0, cast(2.568520192289822, f64)), y)
  xnum2 = mul(add(xnum1, cast(0.36034489994980445, f64)), y)
  xden2 = mul(add(xden1, cast(1.8729528499234604, f64)), y)
  xnum3 = mul(add(xnum2, cast(0.12578172611122926, f64)), y)
  xden3 = mul(add(xden2, cast(0.5279051029514285, f64)), y)
  xnum4 = mul(add(xnum3, cast(0.016083785148742275, f64)), y)
  xden4 = mul(add(xden3, cast(0.06051834131244132, f64)), y)
  r = mul(y, div(add(xnum4, cast(0.0006587491615298378, f64)), add(xden4, cast(0.0023352049762686918, f64))))
  div(mul(exp(neg(mul(ax, ax))), sub(cast(0.5641895835477563, f64), r)), guarded)
}
-- EVERY core clamps its argument into its own region at entry: load-bearing,
-- not defensive. Narrowing for chelis#2103 (`vmap` lowers `if` to a masked
-- select which evaluates BOTH arms, against `spec/06-transformations.md`
-- §2.10.1), so every core runs on every operand the dispatcher sees, and a core
-- returning a non-finite value outside its own region poisons the arm that WAS
-- selected. Every core needs one, not only region 3: regions 1 and 2 are
-- P(y)/Q(y) Horner chains with positive coefficients, so numerator AND
-- denominator overflow to +inf and inf/inf = NaN -- their hazard is not
-- division. The clamps never bind where the dispatcher routes, so no returned
-- value changes.
--
-- This makes each core total over the FINITE f64 domain, not over all of f64:
-- the clamps and dispatcher are themselves `if`s, so +/-inf still poisons a
-- sibling arm wherever an untaken arm is unbounded. Imported Std.Scalar
-- `min`/`max` now work in a standalone 0.18.12 Eval/C vmap probe
-- (chelis#1582 closed); changing this kernel awaits the package-chain gate.
def erf64_erfc_abs(ax: f64) -> f64 = if lt(ax, cast(4.0, f64)) then erf64_core_erfc_mid(ax) else if lt(ax, cast(6.0, f64)) then erf64_core_erfc_tail(ax) else cast(0.0, f64)
def erf64(x: f64) -> f64 = {
  ax = abs_f64(x)
  y = sub(cast(1.0, f64), erf64_erfc_abs(ax))
  signed = if lt(x, cast(0.0, f64)) then neg(y) else y
  finite = if lt(ax, cast(0.5, f64)) then erf64_core_small(x) else signed
  -- NaN propagates rather than saturating. Every `lt` against NaN is false, so
  -- without this guard the dispatcher falls through to the saturation arm and
  -- returns 1.0: a negative spot then priced to a silent 0.0 where the A&S
  -- kernel returned NaN. Answering zero is worse than answering NaN for a
  -- pricing kernel, and it diverged between lanes (vmap still gave NaN).
  --
  -- `eq(x, x)` is false only for NaN. The guard is safe under masked select
  -- because BOTH arms are finite whenever the input is: the untaken arm is
  -- `x` itself for a finite operand, and the saturating 1.0 for a NaN one.
  if eq(x, x) then finite else x
}
-- ABSOLUTE accuracy only. `erf64_erfc_abs` computes erfc to ~1 ulp, but this
-- spelling routes it through `1 - erf64`, and `erf64` is itself `1 - erfc`, so
-- the two subtractions cancel away the relative precision in the LEFT TAIL.
-- Measured on the shipped kernel: n_cdf64(-7) is 2.3e-6 relative, n_cdf64(-8)
-- is 1.8% relative, and below about -8.3 it returns exactly 0.0 where the true
-- value is ~1e-17. Do not use this for deep-tail probabilities. Routing the
-- negative branch straight through `erf64_erfc_abs` would keep the full
-- relative accuracy; that is this shell's issue 68, deliberately not done here.
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
-- This path does NOT evaluate `erf64`. Its erf is Abramowitz & Stegun 7.1.26
-- built from the caller-supplied coefficients, so it kept the ~1.4e-7 bound
-- that this shell's issue 61 removed from the scalar kernel. The two are different
-- approximations and agree only to the scale-aware bound `tests/pricing.ch`
-- asserts. Migrating it is separate work; see docs/CHELIS_SURFACE.md.
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
