module Shoals.Pricing
import Nautilus.Distributions (normal_sample)
export (erf64, n_cdf64, bs_call_scalar, bs_put_scalar, bs_call_f64, bs_call_f64_vector, bs_call_wire_f64, call_prices, put_prices, call_total, put_total, deltas_call, deltas_put, vegas_call, rhos_call, thetas_call, gammas_call, volgas_call, vannas_call, mc_call_price)
-- One normal CDF behind both price and Greeks. n_cdf(x) = 0.5 * erfc(-x/sqrt2)
-- is the exact expression Shoals.References / Shoals.Greeks use. The displayed
-- Greek is the AD derivative of THIS expression, so price and Greek agree.
--
-- ACCURACY. `erf64` evaluates W. J. Cody's rational approximation (Math. Comp.
-- 23, 1969): three ranges split at 0.5 and 4, saturating at Cody's XBIG =
-- 26.543, where `erfc` reaches the smallest NORMAL f64 (the exact crossing is
-- 26.54325845). An earlier revision saturated at 6 and said that was where
-- `erfc` underflows f64; that was wrong by 290 orders of magnitude --
-- `erfc(6)` is 2.15e-17, and 6 is where `1 - erfc` rounds to 1.0, i.e. where
-- *erf* saturates. `erf64` cannot tell the difference and is bitwise unchanged
-- by the correction. The kernel below that consumes `erfc` directly could not
-- see past x = -8.485 until it was fixed; see shoals#68 and the note above its
-- definition. (Said that way round on purpose: naming it HERE would put its
-- name inside `erf64`'s floor-claim attribution window and the oracle's
-- transcription leg would read `erf64`'s figure as that kernel's -- which it
-- did, when this paragraph was first written.)
--
-- Worst observed absolute `erf64` error >= 3.3675e-16 (~1.52 ulp of
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
-- `abs` is the intrinsic rather than a hand-rolled `if`, which is the clearer
-- spelling and keeps the derivative rule below trivially satisfied. An earlier
-- revision justified it by claiming a hand-rolled `if` returns NaN at +inf; that
-- is withdrawn as unmeasured. Measured at this pin it returns +inf, exactly as
-- the intrinsic does, because a scalar `if` does not propagate the untaken arm's
-- value. The rule that does bind is the DERIVATIVE one (chelis#2640).
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
-- Cody region 2 (0.5 < |x| <= 4): erfc(|x|) = exp(-x^2) * P(|x|)/Q(|x|).
-- `|x| == 4` belongs HERE, not to region 3, which is why the dispatcher below
-- spells its test `lte` rather than `lt`: Cody's CALERF dispatches on
-- `IF (Y .LE. FOUR)` and region 2 is one ulp better at that one point.
-- Measured: this core gives 1.541725790028002e-08 at 4.0, the correctly
-- rounded `erfc(4)`; region 3 gives 1.5417257900280017e-08 (shoals#68).
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
-- Cody region 3 (4 < |x| < 26.543): erfc(|x|) = exp(-x^2)/|x| * (1/sqrt(pi) - R(1/x^2)).
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
-- not defensive. Two reasons, and the first is not the one an earlier revision
-- gave. (1) Numerical: every core runs on every operand the dispatcher sees,
-- and a core evaluated outside its own Cody region returns a wrong number --
-- true of any transform or none. (2) The adjoint: a clamp is an `if`, and under
-- `grad` an untaken arm with an unbounded DERIVATIVE poisons the result even
-- though its value does not propagate (chelis#2640, against
-- `spec/06-transformations.md` §2.10.1; fixed upstream at 0.18.12, not at this
-- pin). The claim that an out-of-region non-finite VALUE poisons the selected
-- arm is withdrawn: measured at this pin, it does not.
--
-- Every core needs one, not only region 3: regions 1 and 2 are
-- P(y)/Q(y) Horner chains with positive coefficients, so numerator AND
-- denominator overflow to +inf and inf/inf = NaN -- their hazard is not
-- division. The clamps never bind where the dispatcher routes, so no returned
-- value changes.
--
-- This makes each core total over the FINITE f64 domain, not over all of f64:
-- the clamps and dispatcher are themselves `if`s, so +/-inf still poisons a
-- sibling arm wherever an untaken arm is unbounded. `min`/`max` would remove
-- the rest but fail at eval under vmap at this pin (chelis#1582).
-- The saturation point is Cody's XBIG, not `erf`'s. 6 was inherited from
-- `erf64`'s needs and silently capped `n_cdf64`'s usable left tail at
-- x = -6*sqrt2 = -8.485, which is where it returned exactly 0.0 (shoals#68).
-- 26.543 moves that to x = -37.537, below which the true `n_cdf64` is itself
-- subnormal. `erf64` is unaffected either way: `1 - erfc(ax)` rounds to 1.0 for
-- every ax >= 6, so no `erf64` value moves. Verified by measurement, not
-- inferred -- `tests/pricing_ncdf_tail.ch` pins both halves.
def erf64_erfc_abs(ax: f64) -> f64 = if lte(ax, cast(4.0, f64)) then erf64_core_erfc_mid(ax) else if lt(ax, cast(26.543, f64)) then erf64_core_erfc_tail(ax) else cast(0.0, f64)
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
-- RELATIVE accuracy in both tails, which is what shoals#68 was about and what
-- the previous spelling did not have. `n_cdf64` used to be
-- `0.5 * (1 - erf64(-x/sqrt2))`, and `erf64` is itself `1 - erfc`, so the ~1 ulp
-- `erfc` that this shell's issue 61 bought passed through TWO subtractions
-- from 1 and the cancellation removed exactly the precision just computed.
-- Measured on that spelling: 2.3e-6 relative at x = -7, 1.8% at x = -8, and
-- exactly 0.0 below about -8.3 where the true value is ~1e-17. Absolute error
-- was unaffected and every published figure stayed true, which is why twelve
-- red-team rounds and an absolute-error oracle all missed it.
--
-- `n_cdf(x) = 0.5 * erfc(-x/sqrt2)` is the identity, and the repair is to
-- evaluate it that way rather than through `erf`. Three arms, and each one
-- places the subtraction where the RESULT is far from zero:
--
--   |u| <  0.5  ->  0.5 + 0.5*erf(u)         result near 0.5; `erf64_erfc_abs`
--                                            is OUT OF REGION below 0.5 (Cody
--                                            region 1 is a separate rational),
--                                            so this arm must exist -- it is
--                                            not a shortcut for small inputs.
--   x   <  0    ->  0.5*erfc(|u|)            no subtraction at all. This is the
--                                            arm shoals#68 asked for.
--   otherwise   ->  1 - 0.5*erfc(u)          cancellation is in the RIGHT tail,
--                                            where the result approaches 1 and
--                                            relative accuracy is unaffected.
--
-- SEQUENTIAL SELECTS, not a nested `if`, and `half_erfc` hoisted so both tail
-- arms share one `erf64_erfc_abs` call. Each `if` is then a two-arm select over
-- values already computed, which keeps the three arms independently readable
-- and evaluates `erf64_erfc_abs` once rather than once per arm. Stated as a
-- preference and not as a workaround: nested `if`s also lower correctly at this
-- pin, measured through both lanes and `grad`, so no upstream defect is being
-- cited here.
--
-- EVERY ARM IS FINITE FOR EVERY FINITE INPUT, and that is load-bearing rather
-- than incidental: under `vmap` a scalar `if` lowers to a masked select that
-- evaluates both arms, so an untaken arm's non-finite value or derivative
-- reaches the result. `erf64_core_small` clamps into +/-0.5 and
-- `erf64_erfc_abs` clamps into each core's own region, so the untaken arms here
-- are bounded polynomials. Checked at the +/-0.7071067811865476 boundary, at
-- zero, at +/-inf and under NaN, through BOTH the scalar and the vmap lane, and
-- for the gradient as well as the value -- the adjoint is the half that a
-- value-only test says is fine when it is not (chelis#2640). The two lanes
-- agree BITWISE at every one of those points, and no finite input yields a NaN
-- in either lane or either gradient.
--
-- ONE EXCEPTION, and it predates this repair: `grad` at +/-inf is NaN, in this
-- spelling and in the one it replaced (measured both ways). That is the
-- documented scope of the guarantee -- total over the FINITE f64 domain, not
-- over all of f64, because the clamps and the dispatcher are themselves `if`s.
-- The VALUE at +/-inf is exactly right. `tests/pricing_ncdf_tail.ch` pins it.
--
-- THE PUBLISHED CONTRACT, stated here so the oracle's transcription leg
-- discovers this file as a carrier and a drifting figure cannot hide in one
-- copy: REL-FLOOR `n_cdf64` >= 4.2025 * (1 + x^2) * 2^-53 over
-- -37.5 <= x <= 6.5, where `(1 + x^2)` is the conditioning of the argument
-- reduction `u = x/sqrt2`. The raw relative error is deliberately NOT restated
-- here: it is grid-dependent, nothing executes it, and a second carrier is one
-- more place for it to drift. docs/CHELIS_SURFACE.md reports it once, for
-- orientation, and labels it as not a floor.
-- Saturates to 0.0 below x = -37.537 (-26.543*sqrt2). No probe point IN the
-- interval returns a silent zero; below it, for about 0.95 units of x, the
-- kernel returns 0.0 while the true value is still a representable subnormal
-- (x = -37.6 -> 1.0748e-309). That band is a narrowed residual of this very
-- defect, not a harmless cut-off, and docs/CHELIS_SURFACE.md states it. Re-measure with
-- `scripts/oracle_erf64_accuracy.py --measurement`;
-- docs/CHELIS_SURFACE.md is the authoritative publication.
--
-- THIS KERNEL HAS A SUCCESSOR AND A SHORT LIFETIME, recorded here so the next
-- pin bump does not re-derive it. Chelis 0.18.13 adds `standard_normal_cdf`, a
-- builtin Phi built from a correctly rounded `erfc` *with a correction for the
-- rounding of `-x/sqrt(2)`* -- the same argument reduction whose conditioning
-- sets the bound above -- and it holds ~1.5 ulp at f64 INCLUDING the deep left
-- tail. That is roughly `(1 + x^2)` better than this kernel in the far tail,
-- because correcting the reduction is precisely what this spelling does not do:
-- at x = -37 the error here is ~1.1e-13 relative and the builtin's would be
-- ~3e-16. Verified present in v0.18.13 and absent in v0.18.11, which is the pin
-- this file compiles against, so the repair below is the 0.18.11 answer and not
-- a competing design. When the pin reaches 0.18.13, `n_cdf64` should delegate
-- and the three arms, the XBIG saturation point and the published relative
-- floor all go away together (chelis#902 is the canonical-erf tracker).
--
-- NaN PROPAGATES rather than saturating, for the same reason `erf64` guards:
-- every `lt` against NaN is false, so without the guard a NaN input falls
-- through to `1 - 0.5*erfc_abs(NaN)` = `1 - 0` and a negative spot prices to a
-- silent 1.0. This no longer inherits `erf64`'s guard, because it no longer
-- calls `erf64`. `eq(x, x)` is false only for NaN, and both arms are finite
-- whenever the input is.
def n_cdf64(x: f64) -> f64 = {
  inv_sqrt_2 = cast(0.7071067811865476, f64)
  u = mul(x, inv_sqrt_2)
  au = abs_f64(u)
  half_erfc = mul(cast(0.5, f64), erf64_erfc_abs(au))
  tails = if lt(x, cast(0.0, f64)) then half_erfc else sub(cast(1.0, f64), half_erfc)
  near_zero = add(cast(0.5, f64), mul(cast(0.5, f64), erf64_core_small(u)))
  finite = if lt(au, cast(0.5, f64)) then near_zero else tails
  if eq(x, x) then finite else x
}
-- DENOMINATOR FLOOR, and why it is a clamp rather than a branch on the price.
--
-- `sigma*sqrt(t)` is exactly 0 whenever t = 0 or sigma = 0, i.e. whenever there
-- is no remaining uncertainty. For num != 0 the unguarded division already
-- behaved correctly: +/-inf saturates `erf64` and the formula collapses to
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
-- that saturates `erf64` identically to the +/-inf it replaces, so no
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
-- DENOMINATOR FLOOR, wire lane. Same defect as `d1_64` above (shoals#88) and a
-- strictly worse symptom: the scalar lane only returned NaN where num was ALSO
-- zero, because +/-inf saturates `erf64`. This lane returned NaN at EVERY
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
