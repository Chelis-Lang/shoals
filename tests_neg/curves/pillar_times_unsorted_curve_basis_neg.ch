module Shoals.TestsNeg.PillarTimesUnsortedCurveBasis
import Std.Test (assert_true)
import Shoals.Curves (curve_basis_from_pillars, basis_spread_at)
-- Negative: the basis curve has the same reader and the same precondition.
-- Reordering the same (time, spread) pairs moved the answer at t=1.5 from
-- 0.011 to 0.009 with no diagnostic. The fixture is deliberately
-- non-collinear: with a constant slope every bracket the interpolator could
-- pick gives the identical value, so a collinear fixture cannot see this
-- defect at all and the module's own interpolation test did not.
def test_neg_curve_basis_rejects_unsorted_pillar_times() -> unit ! { Test } = {
  basis = curve_basis_from_pillars(to_tensor([cast(1.0, f32), cast(3.0, f32), cast(2.0, f32)]), to_tensor([cast(0.002, f32), cast(0.03, f32), cast(0.02, f32)]))
  s = basis_spread_at(basis, cast(1.5, f32))
  assert_true(eq(s, s), "should not reach here")
}
