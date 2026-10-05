module Shoals.Tests.PricingNcdfTail
import Std.Test (assert_true, assert_false)
import Shoals.Pricing (n_cdf64, erf64)
-- shoals#68. `n_cdf64` used to be `0.5 * (1 - erf64(-x/sqrt2))`, and `erf64` is
-- itself `1 - erfc`, so the ~1 ulp `erfc` shoals#61 bought passed through two
-- subtractions from 1 and the cancellation removed it: 2.3e-6 relative at
-- x = -7, 1.8% at x = -8, and exactly 0.0 below about -8.3.
--
-- WHY THIS FILE EXISTS RATHER THAN A WIDER SWEEP. The accuracy oracle bounds
-- ABSOLUTE error over +/-6.5, and absolute error was never affected -- which is
-- why twelve red-team rounds and a green oracle all missed this. Every
-- assertion below is therefore a RELATIVE or an exact-value claim; an absolute
-- tolerance would pass against the broken kernel.
--
-- TIER, stated because the repo's CI is deliberately split: `tests/` runs in
-- .github/workflows/nightly.yml, not on the per-PR path (which stops at
-- `chelis reef build`). The per-PR path checks only that the published floors
-- AGREE across their carriers. So this file is a nightly guard, and the
-- measured relative floor in `scripts/oracle_erf64_accuracy.py --measurement`
-- is its nightly sibling.
def abs64(x: f64) -> f64 = if lt(x, cast(0.0, f64)) then neg(x) else x
-- Exact bit equality. Every value pinned here was measured against mpmath at
-- 50 dps and is the correctly rounded result or within the stated ulp count, so
-- a tolerance would only hide a regression. `eq` on f64 is bitwise for finite
-- operands, which is what these pins want.
def assert_exact(actual: f64, expected: f64, label: string) -> unit ! { Test } = assert_true(eq(actual, expected), label)
-- Relative error, which is the quantity shoals#68 is about. Guarded against a
-- zero reference because the pins below include none.
def assert_rel_within(actual: f64, expected: f64, tol: f64, label: string) -> unit ! { Test } = {
  rel = div(abs64(sub(actual, expected)), abs64(expected))
  assert_true(lte(rel, tol), label)
}
-- The boundary between the two spellings: |x/sqrt2| = 0.5, i.e. Cody region 1
-- against region 2.
def branch_boundary() -> f64 = cast(0.7071067811865476, f64)
def pos_inf() -> f64 = div(cast(1.0, f64), cast(0.0, f64))
def quiet_nan() -> f64 = div(cast(0.0, f64), cast(0.0, f64))
-- POSITIVE: the left tail now carries relative accuracy. Every reference is
-- the CORRECTLY ROUNDED true value -- mpmath's `ncdf` at 50 dps rounded to f64
-- -- and deliberately NOT the kernel's own output, which would turn a relative
-- claim into a bit pin that proves nothing about accuracy.
--
-- The tolerances are the CONDITIONING of the argument reduction, not round
-- numbers. `n_cdf(x) = 0.5*erfc(x/sqrt2)` and `d ln erfc / d ln u ~ -2u^2`, so a
-- relative perturbation of eps in `u = x/sqrt2` is amplified by `(1 + x^2)`.
-- With the measured constant (4.21, see the oracle's relative floor) that is
-- 2.3e-14 at x = -7 rising to 1.9e-13 at x = -20; each tolerance below is that
-- figure rounded up. It is the bound the repair can actually meet, and it is
-- twelve orders tighter than the old kernel's 1.8e-2 at x = -8.
def test_left_tail_is_relatively_accurate() -> unit ! { Test } = {
  _ = assert_rel_within(n_cdf64(cast(-7.0, f64)), cast(1.279812543885835e-12, f64), cast(2.4e-14, f64), "n_cdf64(-7) relative")
  _ = assert_rel_within(n_cdf64(cast(-8.0, f64)), cast(6.220960574271784e-16, f64), cast(3.1e-14, f64), "n_cdf64(-8) relative")
  _ = assert_rel_within(n_cdf64(cast(-8.5, f64)), cast(9.479534822203318e-18, f64), cast(3.5e-14, f64), "n_cdf64(-8.5) relative")
  _ = assert_rel_within(n_cdf64(cast(-9.0, f64)), cast(1.1285884059538405e-19, f64), cast(3.9e-14, f64), "n_cdf64(-9) relative")
  assert_rel_within(n_cdf64(cast(-20.0, f64)), cast(2.7536241186062337e-89, f64), cast(1.9e-13, f64), "n_cdf64(-20) relative")
}
-- NEGATIVE PARITY for the test above: the old kernel's answers must now FAIL a
-- relative check. These are the exact values the broken spelling returned
-- (recorded in shoals#68), so this test is what distinguishes the repair from
-- an absolute-error test that both kernels pass.
def test_the_old_cancelling_answers_are_now_rejected() -> unit ! { Test } = {
  got_m8 = n_cdf64(cast(-8.0, f64))
  _ = assert_false(eq(got_m8, cast(6.106226635438361e-16, f64)), "n_cdf64(-8) is no longer the cancelled 6.1062e-16")
  got_m7 = n_cdf64(cast(-7.0, f64))
  _ = assert_false(eq(got_m7, cast(1.2798095916366492e-12, f64)), "n_cdf64(-7) is no longer the cancelled 1.27980959e-12")
  -- THE KERNEL-DEPENDENT HALF. Both relative errors are taken against the SAME
  -- correctly rounded reference, so this compares the two kernels rather than
  -- restating a recorded figure: the repair must be at least 1e11 times closer
  -- at x = -8. Measured margin is 2.59e12, so the threshold has 25x of room.
  true_m8 = cast(6.220960574271784e-16, f64)
  new_rel = div(abs64(sub(got_m8, true_m8)), true_m8)
  old_rel = div(abs64(sub(cast(6.106226635438361e-16, f64), true_m8)), true_m8)
  _ = assert_true(lt(new_rel, old_rel), "the repair is closer to the truth at -8 than the old kernel")
  _ = assert_true(lt(mul(new_rel, cast(100000000000.0, f64)), old_rel), "and closer by at least 1e11")
  -- CONSTANT-FOLDED, and labelled so no reader mistakes it for a kernel test:
  -- both operands are literals, so this cannot fail on any change to
  -- `n_cdf64`. It is here to make the recorded 1.8% figure checkable
  -- arithmetic rather than a claim in a comment.
  assert_true(lt(cast(0.018, f64), old_rel), "the old answer at -8 was worse than 1.8% relative (arithmetic, not a kernel test)")
}
-- NEGATIVE: no silent zero anywhere the true value is representable. The old
-- kernel returned exactly 0.0 below about x = -8.3, which is the worst failure
-- mode in the issue because it is indistinguishable from a true zero.
def test_no_silent_zero_above_codys_xbig() -> unit ! { Test } = {
  _ = assert_true(lt(cast(0.0, f64), n_cdf64(cast(-8.3, f64))), "n_cdf64(-8.3) > 0")
  _ = assert_true(lt(cast(0.0, f64), n_cdf64(cast(-8.5, f64))), "n_cdf64(-8.5) > 0")
  _ = assert_true(lt(cast(0.0, f64), n_cdf64(cast(-9.0, f64))), "n_cdf64(-9) > 0")
  _ = assert_true(lt(cast(0.0, f64), n_cdf64(cast(-20.0, f64))), "n_cdf64(-20) > 0")
  assert_true(lt(cast(0.0, f64), n_cdf64(cast(-37.0, f64))), "n_cdf64(-37) > 0")
}
-- POSITIVE and NEGATIVE together: where saturation now sits, and that it is
-- declared rather than accidental. `erf64_erfc_abs` saturates at Cody's
-- XBIG = 26.543, so `n_cdf64` saturates at -26.543*sqrt2 = -37.537. For about
-- 0.95 further units of x below that, the kernel returns 0.0 while the true
-- value is STILL a representable subnormal -- a narrowed residual of this
-- defect, not a harmless cut-off; the pin below is inside that band. The old
-- threshold of 6 put the same cliff at -8.485, which is what the issue
-- measured as "0.0 below about -8.3".
def test_saturation_sits_at_codys_xbig_not_erfs() -> unit ! { Test } = {
  _ = assert_exact(n_cdf64(cast(-37.0, f64)), cast(5.7255712225239246e-300, f64), "n_cdf64(-37) is still resolved")
  -- -37.6 is INSIDE the residual band, not past the end of representability:
  -- the true value is 1.0748e-309, a representable subnormal, and the kernel
  -- returns 0.0. The band runs to x ~= -38.4854, where the truth rounds to
  -- zero anyway. So this pins a known loss, not a correct answer; an earlier
  -- revision's "(true value is subnormal)" read as though nothing was lost.
  _ = assert_exact(n_cdf64(cast(-37.6, f64)), cast(0.0, f64), "n_cdf64(-37.6) returns 0.0 against a representable 1.0748e-309")
  -- Just past -6*sqrt2 = -8.48528137423857, the exact point the old saturation
  -- turned into 0.0. MEASURED A/B at this pin: origin/main's kernel returns
  -- 0.0 here; the repair returns 1.0759868356249302e-17 against a true
  -- 1.0759868356249362e-17.
  _ = assert_exact(n_cdf64(cast(-8.485281374238571, f64)), cast(1.0759868356249302e-17, f64), "the old cliff at -6*sqrt2 is gone")
  assert_rel_within(n_cdf64(cast(-8.485281374238571, f64)), cast(1.0759868356249362e-17, f64), cast(3.5e-14, f64), "and the value there is relatively accurate, not merely nonzero")
}
-- POSITIVE: Cody's CALERF dispatches region 2 on `IF (Y .LE. FOUR)`, so
-- |x/sqrt2| == 4 belongs to region 2. x = -5.65685424949238 is chosen because
-- `x * 0.7071067811865476` rounds to exactly 4.0, which is the only way to
-- reach that one point through the public surface.
def test_dispatcher_routes_u_eq_four_to_region_two() -> unit ! { Test } = {
  at_four = n_cdf64(cast(-5.65685424949238, f64))
  -- 0.5 * erfc(4) correctly rounded. Region 3 returns 7.708628950140008e-9
  -- here, one ulp worse, which is what `lt` rather than `lte` used to select.
  _ = assert_exact(at_four, cast(7.70862895014001e-9, f64), "|u| == 4 takes Cody region 2")
  assert_false(eq(at_four, cast(7.708628950140008e-9, f64)), "|u| == 4 is not region 3's value")
}
-- POSITIVE: the region-1 / region-2 branch boundary is continuous to ~1.5 ulp.
-- Both arms exist because `erf64_erfc_abs` is out of region below |u| = 0.5;
-- a reviewer should be able to see the seam is small, not assume it.
def test_branch_boundary_is_continuous() -> unit ! { Test } = {
  b = branch_boundary()
  _ = assert_exact(n_cdf64(neg(b)), cast(0.23975006109347666, f64), "left of boundary, erfc arm")
  _ = assert_exact(n_cdf64(cast(-0.7071067811865475, f64)), cast(0.23975006109347674, f64), "right of boundary, erf arm")
  _ = assert_exact(n_cdf64(b), cast(0.7602499389065234, f64), "positive boundary, erfc arm")
  seam = abs64(sub(n_cdf64(neg(b)), n_cdf64(cast(-0.7071067811865475, f64))))
  assert_true(lt(seam, cast(1e-16, f64)), "the seam at |u| = 0.5 is under 1e-16")
}
-- POSITIVE: the exactly-representable anchors.
def test_centre_and_infinities() -> unit ! { Test } = {
  _ = assert_exact(n_cdf64(cast(0.0, f64)), cast(0.5, f64), "n_cdf64(0) == 0.5 exactly")
  _ = assert_exact(n_cdf64(neg(cast(0.0, f64))), cast(0.5, f64), "n_cdf64(-0) == 0.5 exactly")
  _ = assert_exact(n_cdf64(pos_inf()), cast(1.0, f64), "n_cdf64(+inf) == 1")
  assert_exact(n_cdf64(neg(pos_inf())), cast(0.0, f64), "n_cdf64(-inf) == 0")
}
-- NEGATIVE: a NaN input must not saturate. `n_cdf64` no longer calls `erf64`,
-- so it no longer inherits `erf64`'s NaN guard and carries its own. Without it
-- every `lt` against NaN is false, the dispatcher falls through to
-- `1 - 0.5*erfc_abs(NaN)` = `1 - 0`, and a negative spot prices to a silent
-- 1.0 -- strictly worse than answering NaN for a pricing kernel.
def test_nan_propagates_and_does_not_saturate() -> unit ! { Test } = {
  got = n_cdf64(quiet_nan())
  _ = assert_false(eq(got, got), "n_cdf64(NaN) is NaN")
  _ = assert_false(eq(got, cast(1.0, f64)), "n_cdf64(NaN) did not saturate to 1.0")
  assert_false(eq(got, cast(0.0, f64)), "n_cdf64(NaN) did not saturate to 0.0")
}
-- POSITIVE: `erf64` is bitwise unchanged by raising the saturation point from 6
-- to Cody's XBIG. `1 - erfc(ax)` rounds to 1.0 for every ax >= 6 because
-- erfc(6) = 2.15e-17 is under half an ulp of 1.0, so no `erf64` value moves.
-- This is the regression half of the XBIG change and it is measured, not
-- inferred from that argument.
def test_erf64_is_unchanged_by_the_xbig_extension() -> unit ! { Test } = {
  _ = assert_exact(erf64(cast(6.0, f64)), cast(1.0, f64), "erf64(6) == 1")
  _ = assert_exact(erf64(cast(-6.0, f64)), cast(-1.0, f64), "erf64(-6) == -1")
  _ = assert_exact(erf64(cast(6.5, f64)), cast(1.0, f64), "erf64(6.5) == 1")
  _ = assert_exact(erf64(cast(20.0, f64)), cast(1.0, f64), "erf64(20) == 1")
  _ = assert_exact(erf64(cast(-20.0, f64)), cast(-1.0, f64), "erf64(-20) == -1")
  _ = assert_exact(erf64(cast(30.0, f64)), cast(1.0, f64), "erf64(30) == 1 beyond XBIG")
  assert_exact(erf64(pos_inf()), cast(1.0, f64), "erf64(+inf) == 1")
}
-- THE TENSOR LANE, and why it is not belt-and-braces. Under `vmap` a scalar
-- `if` lowers to a masked select that evaluates BOTH arms, so an untaken arm's
-- non-finite value reaches the result. That is the lowering that produced a P0
-- during shoals#62, and `n_cdf64` now has three arms where it had one. Every
-- point below is a branch boundary, a saturation point, or an infinity -- the
-- places where the two lanes can disagree -- and the comparison is EXACT,
-- because a tolerance is what let the lanes diverge unnoticed before.
def lane_probe() -> tensor[10, 1, f64] = reshape(to_tensor([cast(-40.0, f64), cast(-9.0, f64), cast(-8.0, f64), cast(-0.7071067811865476, f64), cast(-0.1, f64), cast(0.0, f64), cast(0.1, f64), cast(0.7071067811865476, f64), cast(8.0, f64), cast(40.0, f64)]), [cast(10, i64), cast(1, i64)])
def assert_lane_agrees(vmapped: List[f64], i: i64, x: f64, label: string) -> unit ! { Test } = assert_true(eq(index(vmapped, i), n_cdf64(x)), label)
def test_tensor_lane_matches_scalar_exactly() -> unit ! { Test } = {
  lanes = to_list(vmap(fn (v: tensor[1, f64]) -> n_cdf64(tensor_to_scalar(sum(v, 0))))(lane_probe()))
  _ = assert_lane_agrees(lanes, cast(0, i64), cast(-40.0, f64), "vmap == scalar below XBIG saturation")
  _ = assert_lane_agrees(lanes, cast(1, i64), cast(-9.0, f64), "vmap == scalar at -9")
  _ = assert_lane_agrees(lanes, cast(2, i64), cast(-8.0, f64), "vmap == scalar at -8")
  _ = assert_lane_agrees(lanes, cast(3, i64), cast(-0.7071067811865476, f64), "vmap == scalar at the negative branch boundary")
  _ = assert_lane_agrees(lanes, cast(4, i64), cast(-0.1, f64), "vmap == scalar just left of centre")
  _ = assert_lane_agrees(lanes, cast(5, i64), cast(0.0, f64), "vmap == scalar at zero")
  _ = assert_lane_agrees(lanes, cast(6, i64), cast(0.1, f64), "vmap == scalar just right of centre")
  _ = assert_lane_agrees(lanes, cast(7, i64), cast(0.7071067811865476, f64), "vmap == scalar at the positive branch boundary")
  _ = assert_lane_agrees(lanes, cast(8, i64), cast(8.0, f64), "vmap == scalar at 8")
  assert_lane_agrees(lanes, cast(9, i64), cast(40.0, f64), "vmap == scalar at 40")
}
-- NEGATIVE PARITY for the lane test: no lane may come back NaN for a finite
-- input. This is the assertion that would have caught shoals#62's P0, and it
-- is separate from the agreement test because two lanes can agree on NaN.
def test_no_lane_returns_nan_for_a_finite_input() -> unit ! { Test } = {
  lanes = to_list(vmap(fn (v: tensor[1, f64]) -> n_cdf64(tensor_to_scalar(sum(v, 0))))(lane_probe()))
  nan_count = tensor_to_scalar(sum(to_tensor(map(fn (v: f64) -> if eq(v, v) then cast(0, i64) else cast(1, i64), lanes)), 0))
  assert_true(eq(nan_count, cast(0, i64)), "no vmap lane is NaN over the branch-boundary probe")
}
-- THE ADJOINT, which is the half a value-only test says is fine when it is not.
-- A clamp or a select is safe only when its untaken arm has a finite VALUE
-- *and* a finite DERIVATIVE: `grad(if lt(x,1) then 2.0 else sqrt(x))` at x = 0
-- is NaN with no `vmap` anywhere, because the adjoint multiplies the untaken
-- arm's infinite derivative by the zero mask (chelis#2640). The AD Greeks
-- differentiate through `n_cdf64`, so every new arm owes this check.
--
-- d/dx n_cdf(x) is the standard normal pdf, exp(-x^2/2)/sqrt(2*pi). The
-- references are mpmath's `npdf` at 50 dps rounded to f64.
def prime(x: f64) -> f64 = grad(fn (v: f64) -> n_cdf64(v), wrt=v)(x)
def test_gradient_is_the_pdf_at_every_branch() -> unit ! { Test } = {
  b = branch_boundary()
  _ = assert_rel_within(prime(cast(0.0, f64)), cast(0.3989422804014327, f64), cast(1e-15, f64), "pdf(0)")
  _ = assert_rel_within(prime(neg(b)), cast(0.31069656037692767, f64), cast(1e-15, f64), "pdf at the negative branch boundary")
  _ = assert_rel_within(prime(b), cast(0.31069656037692767, f64), cast(1e-15, f64), "pdf at the positive branch boundary")
  _ = assert_rel_within(prime(cast(-8.0, f64)), cast(5.052271083536857e-15, f64), cast(1e-14, f64), "pdf(-8) in the left tail")
  -- The boundary is where a one-sided clamp would show up as an asymmetric
  -- derivative, so pin that the two sides agree exactly rather than only that
  -- each is close to the pdf.
  assert_exact(prime(neg(b)), prime(b), "the pdf is symmetric across the boundary, exactly")
}
-- NEGATIVE PARITY: the adjoint must not be NaN at any branch point or at
-- saturation, in either lane. An untaken arm poisons `grad` through the mask
-- even when its value never propagates, so "the value was right" is not
-- evidence for this.
def test_gradient_is_never_nan_in_either_lane() -> unit ! { Test } = {
  b = branch_boundary()
  g_zero = prime(cast(0.0, f64))
  g_bneg = prime(neg(b))
  g_sat = prime(cast(-40.0, f64))
  _ = assert_true(eq(g_zero, g_zero), "grad at zero is not NaN")
  _ = assert_true(eq(g_bneg, g_bneg), "grad at the branch boundary is not NaN")
  _ = assert_true(eq(g_sat, g_sat), "grad below XBIG saturation is not NaN")
  grads = to_list(vmap(fn (v: tensor[1, f64]) -> grad(fn (w: f64) -> n_cdf64(w), wrt=w)(tensor_to_scalar(sum(v, 0))))(lane_probe()))
  nan_count = tensor_to_scalar(sum(to_tensor(map(fn (v: f64) -> if eq(v, v) then cast(0, i64) else cast(1, i64), grads)), 0))
  assert_true(eq(nan_count, cast(0, i64)), "no vmap(grad) lane is NaN over the branch-boundary probe")
}
-- POSITIVE: `vmap(grad)` and scalar `grad` agree exactly. The Greeks are
-- computed through the vmapped path, so a divergence here is a wrong delta
-- rather than a wrong probability.
def assert_grad_lane_agrees(grads: List[f64], i: i64, x: f64, label: string) -> unit ! { Test } = assert_true(eq(index(grads, i), prime(x)), label)
def test_vmapped_gradient_matches_scalar_gradient() -> unit ! { Test } = {
  grads = to_list(vmap(fn (v: tensor[1, f64]) -> grad(fn (w: f64) -> n_cdf64(w), wrt=w)(tensor_to_scalar(sum(v, 0))))(lane_probe()))
  _ = assert_grad_lane_agrees(grads, cast(1, i64), cast(-9.0, f64), "vmap(grad) == grad at -9")
  _ = assert_grad_lane_agrees(grads, cast(3, i64), cast(-0.7071067811865476, f64), "vmap(grad) == grad at the negative boundary")
  _ = assert_grad_lane_agrees(grads, cast(5, i64), cast(0.0, f64), "vmap(grad) == grad at zero")
  _ = assert_grad_lane_agrees(grads, cast(7, i64), cast(0.7071067811865476, f64), "vmap(grad) == grad at the positive boundary")
  assert_grad_lane_agrees(grads, cast(9, i64), cast(40.0, f64), "vmap(grad) == grad at 40")
}
-- THE CONTRACT BOUNDARY, pinned because it is a wart and an unpinned wart is
-- how a reader concludes the opposite. `n_cdf64` is total over the FINITE f64
-- domain, NOT over all of f64: the clamps and the dispatcher are themselves
-- `if`s, so at +/-inf an untaken arm with an unbounded DERIVATIVE poisons the
-- adjoint through the mask even though no VALUE propagates. The value at
-- +/-inf is still exactly right (1.0 and 0.0, pinned above); only the
-- derivative is NaN.
--
-- MEASURED A/B at this pin rather than inferred: `grad(n_cdf64)(+/-inf)` is NaN
-- on origin/main's `0.5*(1 - erf64(-x/sqrt2))` spelling too, so shoals#68's
-- repair neither introduces nor removes it, and it is out of that issue's
-- scope. Pinned here so a future change to these arms has to decide about it
-- rather than discover it.
def test_grad_at_infinity_is_nan_by_the_finite_domain_contract() -> unit ! { Test } = {
  g_pos = prime(pos_inf())
  g_neg = prime(neg(pos_inf()))
  _ = assert_false(eq(g_pos, g_pos), "grad at +inf is NaN (documented finite-domain contract)")
  _ = assert_false(eq(g_neg, g_neg), "grad at -inf is NaN (documented finite-domain contract)")
  -- The largest finite inputs are INSIDE the contract and must not be NaN,
  -- which is what makes the lines above a statement about infinity rather than
  -- about the far tail.
  g_huge = prime(cast(1e300, f64))
  assert_true(eq(g_huge, g_huge), "grad at the largest finite inputs is not NaN")
}
