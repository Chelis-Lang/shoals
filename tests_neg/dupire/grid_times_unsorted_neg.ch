module Shoals.TestsNeg.DupireGridTimesUnsorted
import Std.Test (assert_close)
import Shoals.Dupire (du_cubic_log_moneyness_interp)
-- Negative: the time axis is read through `linear_interp_sorted`, which folds
-- over the pairs tracking the previous time and takes the first bracket
-- straddling the query. With the times out of order it bracketed
-- (0.25, 0.20) against (0.75, 0.45) instead of (0.25, 0.20) against
-- (0.5, 0.40): the query at t=0.375 returned 0.2625 where 0.30 is correct, a
-- 12.5% relative error on an implied vol with no trap, no NaN and no
-- diagnostic, feeding `du_local_vol_from_iv_surface` and anything priced off
-- the surface. The call must fail loudly instead.
--
-- The assertion is the value the unguarded code returned, not the guard's
-- outcome, so removing the guard makes this file pass and `--expect neg`
-- flags it.
def fixture_level(r: i64) -> f32 = if eq(r, cast(0, i64)) then cast(0.2, f32) else if eq(r, cast(1, i64)) then cast(0.45, f32) else cast(0.4, f32)
def fixture_strikes() -> tensor[5, f32] = to_tensor(map(fn (c: i64) -> add(cast(80.0, f32), mul(cast(c, f32), cast(10.0, f32))), range(cast(0, i64), cast(5, i64))))
def fixture_grid() -> tensor[3, 5, f32] = reshape(to_tensor(map(fn (idx: i64) -> fixture_level(floor_div(idx, cast(5, i64))), range(cast(0, i64), cast(15, i64)))), [cast(3, i64), cast(5, i64)])
def test_neg_dupire_rejects_unsorted_grid_times() -> unit ! { Test } = {
  iv = du_cubic_log_moneyness_interp(fixture_strikes(), to_tensor([cast(0.25, f32), cast(0.75, f32), cast(0.5, f32)]), fixture_grid(), cast(100.0, f32), cast(100.0, f32), cast(0.375, f32))
  assert_close(iv, cast(0.2625, f32), cast(1e-6, f32), "should not reach here: unguarded this returned 0.2625 where 0.30 is correct")
}
