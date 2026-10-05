module Shoals.TestsNeg.OpaqueBasisExternalConstruction
import Std.Test (assert_true)
import Shoals.Curves (CurveBasis, basis_spread_at)
-- Negative: the same route into `CurveBasis`, which had no external pattern
-- consumers and so is opaque with no reader beyond `basis_pillars`. A forged
-- record answered 0.009 at t=1.5 where 0.011 is correct.
def test_neg_opaque_basis_rejects_external_construction() -> unit ! { Test } = {
  basis = CurveBasis { times: to_tensor([cast(1.0, f32), cast(3.0, f32), cast(2.0, f32)]), spreads: to_tensor([cast(0.002, f32), cast(0.03, f32), cast(0.02, f32)]) }
  s = basis_spread_at(basis, cast(1.5, f32))
  assert_true(eq(s, s), "should not reach here")
}
