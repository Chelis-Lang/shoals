module Shoals.TestsNeg.TinyNegativeHorizon
import Std.Test (assert_true)
import Shoals.Stochastic (gbm_terminal)
-- Negative: the guard's LOWER boundary. Every other horizon fixture here uses
-- t = -1.0 (or dt = -0.125), and the positive-parity tests in
-- tests/stochastic.ch pin t = 0 and t = -0.0 from above. Between those two
-- lies an untested interval, and a threshold shifted into it reintroduces
-- shoals#139 exactly while the whole rest of the suite stays green: the mutant
-- `gte(t, -0.01)` was measured to pass all 88 negative fixtures AND both
-- positive tests, while gbm_terminal at t = -0.001 returned NaN for every one
-- of eight paths. Any threshold in (-0.125, 0) survived. This file is the one
-- that dies instead.
--
-- The horizon here is the SMALLEST-MAGNITUDE negative f32, the negative min
-- subnormal -1.4e-45, and the choice is forced rather than stylistic. A
-- fixture at a merely small value like -1e-6 kills only thresholds coarser
-- than itself: the mutant `gte(t, -1e-9)` still REFUSES -1e-6, so that fixture
-- passes and the mutant survives (measured). Because `gte(-1.4e-45, x)` is
-- true for every negative f32 `x`, a fixture at this value is admitted by any
-- negative threshold whatsoever, so it kills the entire family in one file.
-- `sqrt` of a negative subnormal is still NaN, so the all-NaN consequence is
-- unchanged.
--
-- The assertion is one that NaN also fails, so deleting the guard makes this
-- file report WRONG-DIAGNOSTIC rather than pass.
def template() -> tensor[8, f32] = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(8, i64))))
def non_nan_count[n](xs: tensor[n, f32]) -> f32 = tensor_to_scalar(sum(cast(eq(copy(xs), xs), f32), 0))
def test_neg_tiny_negative_horizon() -> unit ! { Test } = {
  paths = gbm_terminal(key_from_seed(7i64), template(), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(-1.4e-45, f32))
  assert_true(eq(non_nan_count(paths), cast(8.0, f32)), "should not reach here: the smallest-magnitude negative f32 is still negative, and unguarded it returned NaN for every one of the eight paths")
}
