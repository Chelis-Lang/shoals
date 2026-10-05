module Shoals.TestsNeg.DupireGridTimesDuplicate
import Std.Test (assert_close)
import Shoals.Dupire (du_cubic_log_moneyness_interp)
-- Negative: the rule is *strictly* increasing, not merely non-decreasing. Two
-- grid times at the same maturity carry two different implied-vol rows for one
-- date, so no surface reads both, and the time interpolator's bracket width is
-- zero there. This is the negative-parity case for the `gt` in the guard: a
-- `gte` would accept it and the unsorted cases would still be rejected.
--
-- The assertion is the value the unguarded code returned, so removing the
-- guard makes this file pass and `--expect neg` flags it.
def fixture_level(r: i64) -> f32 = if eq(r, cast(0, i64)) then cast(0.2, f32) else if eq(r, cast(1, i64)) then cast(0.4, f32) else cast(0.45, f32)
def fixture_strikes() -> tensor[5, f32] = to_tensor(map(fn (c: i64) -> add(cast(80.0, f32), mul(cast(c, f32), cast(10.0, f32))), range(cast(0, i64), cast(5, i64))))
def fixture_grid() -> tensor[3, 5, f32] = reshape(to_tensor(map(fn (idx: i64) -> fixture_level(floor_div(idx, cast(5, i64))), range(cast(0, i64), cast(15, i64)))), [cast(3, i64), cast(5, i64)])
def test_neg_dupire_rejects_duplicate_grid_times() -> unit ! { Test } = {
  iv = du_cubic_log_moneyness_interp(fixture_strikes(), to_tensor([cast(0.25, f32), cast(0.5, f32), cast(0.5, f32)]), fixture_grid(), cast(100.0, f32), cast(100.0, f32), cast(0.375, f32))
  assert_close(iv, cast(0.3, f32), cast(1e-6, f32), "should not reach here: unguarded this returned 0.3 from whichever duplicate row it reached first")
}
