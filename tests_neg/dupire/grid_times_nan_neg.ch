module Shoals.TestsNeg.DupireGridTimesNan
import Std.Test (assert_close)
import Shoals.Dupire (du_cubic_log_moneyness_interp)
-- Negative: a NaN grid time has no position relative to any other time, so it
-- cannot be strictly greater than its predecessor and the same `gt` rejects
-- it. Pinned as its own case because that is a consequence of the comparison
-- rather than a separate branch: rewriting the predicate as "not less than or
-- equal" would preserve the other cases and silently readmit NaN.
--
-- The NaN does not propagate into the answer, which is what makes it worth a
-- case of its own: `linear_interp_sorted` finds no bracket at all, falls
-- through to its past-the-end branch and returns the LAST row's level. The
-- query at t=0.375 came back 0.45 -- a finite, confident, wrong implied vol
-- where 0.30 is correct, and no NaN for a caller to test for.
def fixture_level(r: i64) -> f32 = if eq(r, cast(0, i64)) then cast(0.2, f32) else if eq(r, cast(1, i64)) then cast(0.4, f32) else cast(0.45, f32)
def fixture_strikes() -> tensor[5, f32] = to_tensor(map(fn (c: i64) -> add(cast(80.0, f32), mul(cast(c, f32), cast(10.0, f32))), range(cast(0, i64), cast(5, i64))))
def fixture_grid() -> tensor[3, 5, f32] = reshape(to_tensor(map(fn (idx: i64) -> fixture_level(floor_div(idx, cast(5, i64))), range(cast(0, i64), cast(15, i64)))), [cast(3, i64), cast(5, i64)])
def test_neg_dupire_rejects_nan_grid_time() -> unit ! { Test } = {
  nan_t = div(cast(0.0, f32), cast(0.0, f32))
  iv = du_cubic_log_moneyness_interp(fixture_strikes(), to_tensor([cast(0.25, f32), nan_t, cast(0.75, f32)]), fixture_grid(), cast(100.0, f32), cast(100.0, f32), cast(0.375, f32))
  assert_close(iv, cast(0.45, f32), cast(1e-6, f32), "should not reach here: unguarded this returned the last row's 0.45 where 0.30 is correct")
}
