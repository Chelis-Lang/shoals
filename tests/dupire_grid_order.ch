module Shoals.Tests.DupireGridOrder
import Std.Test (assert_close)
import Shoals.Dupire (du_cubic_log_moneyness_interp)
-- Positive parity for the two grid-axis ordering guards on
-- `du_cubic_log_moneyness_interp`. The reordered-axis rejections live in
-- `tests_neg/dupire/`; this file pins that the guards admit everything they
-- should and leave the interpolated implied vols alone.
--
-- The fixture varies NON-LINEARLY IN BOTH AXES, and that is load-bearing
-- rather than stylistic. A surface flat or affine along an axis gives the same
-- answer for every bracket the interpolator could pick on that axis, so it
-- cannot distinguish correct bracketing from the defect these guards close.
-- `tests/dupire.ch`'s own grid was built from the column index alone, which
-- makes it constant along the time axis and therefore blind to any
-- time-bracketing behaviour at all.
--
-- `fixture_quad` is 0.60 / 0.30 / 0.20 / 0.30 / 0.60 across the five strikes,
-- and `fixture_time_factor` scales each row by 0.8 / 1.0 / 1.05, a slope of
-- 0.8 then 0.2 per unit time. A wrong time bracket is visible: at k=F and
-- t=0.375 the 0.25->0.5 bracket gives 0.18, where the same rows and times
-- reordered as 0.25 / 0.75 / 0.5 bracket 0.25 against 0.75 and measured
-- 0.1725.
def fixture_quad(k: f32) -> f32 = add(cast(0.2, f32), mul(cast(0.001, f32), mul(sub(k, cast(100.0, f32)), sub(k, cast(100.0, f32)))))
def fixture_time_factor(r: i64) -> f32 = if eq(r, cast(0, i64)) then cast(0.8, f32) else if eq(r, cast(1, i64)) then cast(1.0, f32) else cast(1.05, f32)
def fixture_strike(c: i64) -> f32 = add(cast(80.0, f32), mul(cast(c, f32), cast(10.0, f32)))
def fixture_strikes() -> tensor[5, f32] = to_tensor(map(fn (c: i64) -> fixture_strike(c), range(cast(0, i64), cast(5, i64))))
def fixture_times() -> tensor[3, f32] = to_tensor([cast(0.25, f32), cast(0.5, f32), cast(0.75, f32)])
def fixture_grid() -> tensor[3, 5, f32] = {
  flat = to_tensor(map(fn (idx: i64) -> mul(fixture_time_factor(floor_div(idx, cast(5, i64))), fixture_quad(fixture_strike(mod(idx, cast(5, i64))))), range(cast(0, i64), cast(15, i64))))
  reshape(flat, [cast(3, i64), cast(5, i64)])
}
def fixture_at(k: f32, t: f32) -> f32 = du_cubic_log_moneyness_interp(fixture_strikes(), fixture_times(), fixture_grid(), cast(100.0, f32), k, t)
def test_sorted_times_interpolate_in_the_right_bracket() -> unit ! { Test } = {
  _ = assert_close(fixture_at(cast(100.0, f32), cast(0.375, f32)), cast(0.18, f32), cast(1e-6, f32), "midpoint of the 0.25-0.5 time bracket at the forward, not of 0.25-0.75 (0.1725)")
  _ = assert_close(fixture_at(cast(100.0, f32), cast(0.625, f32)), cast(0.205, f32), cast(1e-6, f32), "midpoint of the 0.5-0.75 time bracket")
  assert_close(fixture_at(cast(100.0, f32), cast(0.5, f32)), cast(0.2, f32), cast(1e-6, f32), "interior grid time exact")
}
def test_sorted_strikes_interpolate_in_the_right_bracket() -> unit ! { Test } = {
  _ = assert_close(fixture_at(cast(95.0, f32), cast(0.5, f32)), cast(0.2248057, f32), cast(1e-6, f32), "the cubic between the 90 and 100 knots, not the 0.31237233 a reordered strike axis gave")
  assert_close(fixture_at(cast(90.0, f32), cast(0.5, f32)), cast(0.3, f32), cast(1e-6, f32), "grid strike exact")
}
def test_off_grid_in_both_axes() -> unit ! { Test } = assert_close(fixture_at(cast(95.0, f32), cast(0.375, f32)), cast(0.20232514, f32), cast(1e-6, f32), "both brackets at once: the strike cubic scaled by the 0.25-0.5 time factor")
-- One time row has no pair to compare, and the guard must not reject it on an
-- empty comparison: `linear_interp_sorted` reads a one-row surface as flat in
-- time, here well past the only grid time.
def test_single_time_row_is_vacuously_increasing() -> unit ! { Test } = {
  flat = to_tensor(map(fn (c: i64) -> fixture_quad(fixture_strike(c)), range(cast(0, i64), cast(5, i64))))
  got = du_cubic_log_moneyness_interp(fixture_strikes(), to_tensor([cast(0.5, f32)]), reshape(flat, [cast(1, i64), cast(5, i64)]), cast(100.0, f32), cast(95.0, f32), cast(2.0, f32))
  assert_close(got, cast(0.2248057, f32), cast(1e-6, f32), "flat in time: the single row's strike cubic, unscaled")
}
-- The rule on both axes is strict ordering, not a minimum gap. A 1e-4 spacing
-- is accepted and interpolates across it; the paired rejections of a zero gap
-- are `tests_neg/dupire/grid_times_duplicate_neg.ch` and
-- `tests_neg/dupire/strikes_duplicate_neg.ch`.
def test_tightly_spaced_times_are_accepted() -> unit ! { Test } = {
  flat = to_tensor(map(fn (idx: i64) -> mul(if lt(idx, cast(5, i64)) then cast(1.0, f32) else cast(2.0, f32), fixture_quad(fixture_strike(mod(idx, cast(5, i64))))), range(cast(0, i64), cast(10, i64))))
  got = du_cubic_log_moneyness_interp(fixture_strikes(), to_tensor([cast(0.25, f32), cast(0.2501, f32)]), reshape(flat, [cast(2, i64), cast(5, i64)]), cast(100.0, f32), cast(100.0, f32), cast(0.25005, f32))
  assert_close(got, cast(0.3000298, f32), cast(1e-6, f32), "a 1e-4 time gap is strictly increasing and interpolates across it")
}
def test_tightly_spaced_strikes_are_accepted() -> unit ! { Test } = {
  got = du_cubic_log_moneyness_interp(to_tensor([cast(99.0, f32), cast(99.0001, f32)]), to_tensor([cast(0.25, f32), cast(0.75, f32)]), reshape(to_tensor([cast(0.3, f32), cast(0.5, f32), cast(0.3, f32), cast(0.5, f32)]), [cast(2, i64), cast(2, i64)]), cast(100.0, f32), cast(99.00005, f32), cast(0.5, f32))
  assert_close(got, cast(0.41246378, f32), cast(1e-6, f32), "a 1e-4 strike gap is strictly increasing and the spline evaluates across it")
}
