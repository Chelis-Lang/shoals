module Shoals.Tests.CurvesPillarOrder
import Std.Test (assert_close, assert_eq)
import Shoals.Curves (CurveKind, YieldCurve, yield_curve_from_pillars, yield_curve_tagged, curve_kind, curve_pillars, ois, rate_at, discount_factor, bootstrap_zero_from_par, CurveBasis, curve_basis_from_pillars, basis_pillars, basis_spread_at, parallel_shift)
-- Positive parity for the four pillar-order guards. The reordered-pillar
-- rejections live in `tests_neg/curves/pillar_times_*_neg.ch`; this file pins
-- that the guards admit everything they should and leave the answers alone.
--
-- Every fixture here is NON-COLLINEAR, and that is load-bearing rather than
-- stylistic. With a constant slope, every bracket the interpolator could pick
-- interpolates to the same value, so a collinear fixture gives the identical
-- answer whatever the bracketing code does -- it cannot distinguish correct
-- interpolation from the defect these guards close, and cannot distinguish it
-- from a body that ignores the curve and evaluates the affine function.
-- Rates 0.01 / 0.06 / 0.07 at times 1 / 2 / 3 have slope 0.05 then 0.01, so a
-- wrong bracket is visible: 0.035 is right and the first-to-last bracket gives
-- 0.025.
def pillar_times() -> tensor[3, f32] = to_tensor([cast(1.0, f32), cast(2.0, f32), cast(3.0, f32)])
def pillar_rates() -> tensor[3, f32] = to_tensor([cast(0.01, f32), cast(0.06, f32), cast(0.07, f32)])
def pillar_spreads() -> tensor[3, f32] = to_tensor([cast(0.002, f32), cast(0.02, f32), cast(0.03, f32)])
def test_sorted_pillars_interpolate_in_the_right_bracket() -> unit ! { Test } = {
  curve = yield_curve_from_pillars(pillar_times(), pillar_rates())
  _ = assert_close(rate_at(curve, cast(1.5, f32)), cast(0.035, f32), cast(1e-6, f32), "midpoint of the 1y-2y bracket, not of 1y-3y")
  _ = assert_close(rate_at(yield_curve_from_pillars(pillar_times(), pillar_rates()), cast(2.5, f32)), cast(0.065, f32), cast(1e-6, f32), "midpoint of the 2y-3y bracket")
  _ = assert_close(rate_at(yield_curve_from_pillars(pillar_times(), pillar_rates()), cast(2.0, f32)), cast(0.06, f32), cast(1e-7, f32), "interior pillar exact")
  assert_close(discount_factor(yield_curve_from_pillars(pillar_times(), pillar_rates()), cast(1.5, f32)), cast(0.9488543, f32), cast(1e-6, f32), "the DF the guarded curve discounts to")
}
def test_sorted_pillars_accepted_by_the_tagged_constructor() -> unit ! { Test } = {
  curve = yield_curve_tagged(ois(), pillar_times(), pillar_rates())
  _ = assert_close(rate_at(curve, cast(1.5, f32)), cast(0.035, f32), cast(1e-6, f32), "tagged constructor answers like the untagged one")
  assert_eq(curve_kind(yield_curve_tagged(ois(), pillar_times(), pillar_rates())), ois(), "the guard does not disturb the stored kind")
}
def test_sorted_pillars_accepted_by_the_basis_constructor() -> unit ! { Test } = {
  basis = curve_basis_from_pillars(pillar_times(), pillar_spreads())
  _ = assert_close(basis_spread_at(basis, cast(1.5, f32)), cast(0.011, f32), cast(1e-6, f32), "midpoint of the 1y-2y spread bracket, not of 1y-3y (0.009)")
  assert_close(basis_spread_at(curve_basis_from_pillars(pillar_times(), pillar_spreads()), cast(2.25, f32)), cast(0.0225, f32), cast(1e-6, f32), "quarter of the way into the 2y-3y spread bracket")
}
def test_sorted_pillars_accepted_by_bootstrap_zero_from_par() -> unit ! { Test } = assert_close(rate_at(bootstrap_zero_from_par(pillar_times(), pillar_rates()), cast(1.5, f32)), cast(0.03485328, f32), cast(1e-6, f32), "par bootstrap still returns its curve for increasing times")
-- A single pillar has no pair to compare, and the guard must not reject it on
-- an empty comparison: `linear_interp_sorted` reads a one-pillar curve as flat.
def test_single_pillar_is_vacuously_increasing() -> unit ! { Test } = assert_close(rate_at(yield_curve_from_pillars(to_tensor([cast(2.0, f32)]), to_tensor([cast(0.05, f32)])), cast(1.5, f32)), cast(0.05, f32), cast(1e-7, f32), "flat before the only pillar")
-- The rule is strict ordering, not a minimum gap. A 1e-4 spacing is accepted
-- and interpolates across it; the paired rejection of a zero gap is
-- `tests_neg/curves/pillar_times_duplicate_neg.ch`.
def test_tightly_spaced_pillars_are_accepted() -> unit ! { Test } = assert_close(rate_at(yield_curve_from_pillars(to_tensor([cast(1.0, f32), cast(1.0001, f32)]), to_tensor([cast(0.01, f32), cast(0.09, f32)])), cast(1.00005, f32)), cast(0.04995233, f32), cast(1e-6, f32), "a 1e-4 pillar gap is strictly increasing and interpolates")
-- Positive parity for the readers opacity makes necessary. The paired
-- rejections of the record literal and the record pattern are
-- `tests_neg/curves/opaque_*_neg.ch`.
def test_pillar_readers_return_what_was_built() -> unit ! { Test } = {
  pillars = curve_pillars(yield_curve_from_pillars(pillar_times(), pillar_rates()))
  ts_l = to_list(pillars.0)
  rs_l = to_list(pillars.1)
  _ = assert_close(index(ts_l, cast(2, i64)), cast(3.0, f32), cast(1e-7, f32), "last pillar time round-trips through the reader")
  _ = assert_close(index(rs_l, cast(1, i64)), cast(0.06, f32), cast(1e-7, f32), "interior pillar rate round-trips through the reader")
  bp = basis_pillars(curve_basis_from_pillars(pillar_times(), pillar_spreads()))
  _ = assert_close(index(to_list(bp.0), cast(0, i64)), cast(1.0, f32), cast(1e-7, f32), "first basis time round-trips")
  assert_close(index(to_list(bp.1), cast(2, i64)), cast(0.03, f32), cast(1e-7, f32), "last basis spread round-trips")
}
-- Second shape/config case for `basis_pillars` (shell contract §9, which
-- `conform audit` row 16 routes to a reviewer): a two-pillar basis rather than
-- the three-pillar one above, so the new verb is exercised at more than one
-- extent and from more than one literal.
def test_basis_pillars_at_a_second_extent() -> unit ! { Test } = {
  bp = basis_pillars(curve_basis_from_pillars(to_tensor([cast(0.5, f32), cast(4.0, f32)]), to_tensor([cast(0.001, f32), cast(0.009, f32)])))
  _ = assert_close(index(to_list(bp.0), cast(1, i64)), cast(4.0, f32), cast(1e-7, f32), "n=2 basis time round-trips")
  assert_close(index(to_list(bp.1), cast(0, i64)), cast(0.001, f32), cast(1e-7, f32), "n=2 basis spread round-trips")
}
-- A derived curve is still a curve built inside the module, so the reader sees
-- the shifted rates and the original times. This exercises one instance of the
-- inductive step the opacity argument rests on; the other four shifts are
-- covered by `tests/curves_ops.ch`'s value assertions.
def test_shifted_curve_keeps_its_pillar_times() -> unit ! { Test } = {
  pillars = curve_pillars(parallel_shift(yield_curve_from_pillars(pillar_times(), pillar_rates()), cast(0.01, f32)))
  _ = assert_close(index(to_list(pillars.0), cast(1, i64)), cast(2.0, f32), cast(1e-7, f32), "a shift preserves pillar times verbatim")
  assert_close(index(to_list(pillars.1), cast(1, i64)), cast(0.07, f32), cast(1e-6, f32), "a shift moves the rate by delta")
}
