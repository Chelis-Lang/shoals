module Shoals.TestsNeg.DupireStrikesDuplicate
import Std.Test (assert_close)
import Shoals.Dupire (du_cubic_log_moneyness_interp)
-- Negative: strict ordering on the strike axis too. Two knots at one strike
-- carry two different implied vols for one option, so no smile reads both, and
-- the segment width between them is zero -- which `spline_fit` does not
-- reject: it substitutes 1.0 for any gap below 1e-30 and solves a system whose
-- geometry no longer matches the knots. This is the negative-parity case for
-- the `gt` in the strike guard; a `gte` would accept it.
--
-- The assertion is the value the unguarded code returned, so removing the
-- guard makes this file pass and `--expect neg` flags it.
def fixture_pick(i: i64, a: f32, b: f32, c: f32, d: f32, e: f32) -> f32 = if eq(i, cast(0, i64)) then a else if eq(i, cast(1, i64)) then b else if eq(i, cast(2, i64)) then c else if eq(i, cast(3, i64)) then d else e
def fixture_quad(k: f32) -> f32 = add(cast(0.2, f32), mul(cast(0.001, f32), mul(sub(k, cast(100.0, f32)), sub(k, cast(100.0, f32)))))
def fixture_doubled(i: i64) -> f32 = fixture_pick(i, cast(80.0, f32), cast(90.0, f32), cast(90.0, f32), cast(110.0, f32), cast(120.0, f32))
def fixture_strikes() -> tensor[5, f32] = to_tensor(map(fn (i: i64) -> fixture_doubled(i), range(cast(0, i64), cast(5, i64))))
def fixture_grid() -> tensor[2, 5, f32] = reshape(to_tensor(map(fn (idx: i64) -> fixture_quad(fixture_doubled(mod(idx, cast(5, i64)))), range(cast(0, i64), cast(10, i64)))), [cast(2, i64), cast(5, i64)])
def test_neg_dupire_rejects_duplicate_strikes() -> unit ! { Test } = {
  iv = du_cubic_log_moneyness_interp(fixture_strikes(), to_tensor([cast(0.25, f32), cast(0.75, f32)]), fixture_grid(), cast(100.0, f32), cast(95.0, f32), cast(0.5, f32))
  assert_close(iv, cast(0.25239202, f32), cast(1e-6, f32), "should not reach here: unguarded this returned 0.25239202 from a spline fitted with a substituted knot gap")
}
