module Shoals.Tests.IndicatorsRolling
import Std.Test (assert_true, assert_false, assert_eq)
import Shoals.Indicators (ind_rolling_sum, ind_rolling_mean, ind_rolling_std, ind_rolling_min, ind_rolling_max, ind_shift, ind_diff, DdofPopulation, DdofSample)
import Nautilus.Rolling (rolling_sum, rolling_mean, rolling_std, rolling_min, rolling_max, shift, diff)
-- Spec §2.15.2-3: full windows, aligned Option masks, explicit ddof and no
-- look-ahead. The hand-computed fixture is independent of either library.
def values() -> List[f64] = [4.0f64, -2.0f64, 7.0f64, 1.0f64, 1.0f64]
def agrees(a: List[Option[f64]], b: List[Option[f64]]) -> bool =
  if eq(len(a), len(b)) then fold(fn (ok: bool, i: i64) -> if ok then match (index(a, i), index(b, i)) with {
    | (Some(x), Some(y)) => lte(abs(sub(x, y)), 1e-12f64)
    | (None, None) => true
    | _ => false
  } else false, true, range(0i64, len(a))) else false
def all_absent(xs: List[Option[f64]], size: i64) -> bool =
  if eq(len(xs), size) then fold(fn (ok: bool, value: Option[f64]) -> if ok then match value with {
    | None => true
    | Some(_) => false
  } else false, true, xs) else false
def matches_nautilus(xs: List[f64], window: i64, lag: i64) -> bool = {
  sums = agrees(ind_rolling_sum(xs, window), rolling_sum(xs, window, window))
  means = agrees(ind_rolling_mean(xs, window), rolling_mean(xs, window, window))
  mins = agrees(ind_rolling_min(xs, window), rolling_min(xs, window, window))
  maxs = agrees(ind_rolling_max(xs, window), rolling_max(xs, window, window))
  pop = agrees(ind_rolling_std(xs, window, DdofPopulation), rolling_std(xs, window, window, 0i64))
  sample = agrees(ind_rolling_std(xs, window, DdofSample), rolling_std(xs, window, window, 1i64))
  shifted = agrees(ind_shift(xs, lag), shift(xs, lag))
  differenced = agrees(ind_diff(xs, lag), diff(xs, lag))
  (((((((sums && means) && mins) && maxs) && pop) && sample) && shifted) && differenced)
}
def test_rolling_hand_computed_values_and_masks() -> unit ! { Test } = {
  _ = assert_true(agrees(ind_rolling_sum(values(), 3i64), [None, None, Some(9.0f64), Some(6.0f64), Some(9.0f64)]), "sum full windows")
  _ = assert_true(agrees(ind_rolling_mean(values(), 3i64), [None, None, Some(3.0f64), Some(2.0f64), Some(3.0f64)]), "mean full windows")
  _ = assert_true(agrees(ind_rolling_min(values(), 3i64), [None, None, Some(-2.0f64), Some(-2.0f64), Some(1.0f64)]), "minimum full windows")
  _ = assert_true(agrees(ind_rolling_max(values(), 3i64), [None, None, Some(7.0f64), Some(7.0f64), Some(7.0f64)]), "maximum full windows")
  _ = assert_true(agrees(ind_rolling_std(values(), 3i64, DdofPopulation), [None, None, Some(sqrt(14.0f64)), Some(sqrt(14.0f64)), Some(sqrt(8.0f64))]), "population divisor is window")
  assert_true(agrees(ind_rolling_std(values(), 3i64, DdofSample), [None, None, Some(sqrt(21.0f64)), Some(sqrt(21.0f64)), Some(sqrt(12.0f64))]), "sample divisor is window minus one")
}
def test_rolling_masks_do_not_allow_partial_windows() -> unit ! { Test } = {
  _ = assert_false(agrees(ind_rolling_mean(values(), 3i64), rolling_mean(values(), 3i64, 1i64)), "a partial window must stay absent")
  assert_false(agrees(ind_rolling_std(values(), 3i64, DdofPopulation), ind_rolling_std(values(), 3i64, DdofSample)), "ddof choices must remain distinct")
}
def test_rolling_nautilus_equivalence_on_finite_fixtures() -> unit ! { Test } = {
  _ = assert_true(matches_nautilus(values(), 3i64, 2i64), "mixed signs and repeated values")
  _ = assert_true(matches_nautilus([8.0f64, 8.0f64, 8.0f64, 8.0f64], 2i64, 1i64), "constant windows")
  assert_true(matches_nautilus(values(), 8i64, 8i64), "overlong windows and lags")
}
def test_rolling_empty_input_preserves_length() -> unit ! { Test } = {
  empty = take(values(), 0i64)
  _ = assert_true(matches_nautilus(empty, 3i64, 2i64), "all seven empty paths agree")
  assert_eq(len(ind_shift(empty, 0i64)), 0i64, "empty identity lag")
}
def test_rolling_overlong_windows_and_lags_are_all_absent() -> unit ! { Test } = {
  _ = assert_true(all_absent(ind_rolling_sum(values(), 8i64), 5i64), "overlong sum")
  _ = assert_true(all_absent(ind_rolling_mean(values(), 8i64), 5i64), "overlong mean")
  _ = assert_true(all_absent(ind_rolling_min(values(), 8i64), 5i64), "overlong minimum")
  _ = assert_true(all_absent(ind_rolling_max(values(), 8i64), 5i64), "overlong maximum")
  _ = assert_true(all_absent(ind_rolling_std(values(), 8i64, DdofPopulation), 5i64), "overlong population std")
  _ = assert_true(all_absent(ind_rolling_std(values(), 8i64, DdofSample), 5i64), "overlong sample std")
  _ = assert_true(all_absent(ind_shift(values(), 8i64), 5i64), "overlong shift")
  assert_true(all_absent(ind_diff(values(), 8i64), 5i64), "overlong difference")
}
def test_rolling_singleton_windows_preserve_defined_and_undefined_values() -> unit ! { Test } = {
  singleton = [6.0f64]
  _ = assert_true(agrees(ind_rolling_sum(singleton, 1i64), [Some(6.0f64)]), "singleton sum")
  _ = assert_true(agrees(ind_rolling_mean(singleton, 1i64), [Some(6.0f64)]), "singleton mean")
  _ = assert_true(agrees(ind_rolling_min(singleton, 1i64), [Some(6.0f64)]), "singleton minimum")
  _ = assert_true(agrees(ind_rolling_max(singleton, 1i64), [Some(6.0f64)]), "singleton maximum")
  _ = assert_true(agrees(ind_rolling_std(singleton, 1i64, DdofPopulation), [Some(0.0f64)]), "singleton population std is defined")
  sample = ind_rolling_std(singleton, 1i64, DdofSample)
  _ = assert_eq(len(sample), 1i64, "singleton sample std keeps its position")
  assert_true(match index(sample, 0i64) with {
    | Some(x) => not(eq(x, x))
    | None => false
  }, "singleton sample std is Some NaN rather than warm-up")
}
def test_shift_and_difference_keep_alignment() -> unit ! { Test } = {
  _ = assert_true(agrees(ind_shift(values(), 0i64), [Some(4.0f64), Some(-2.0f64), Some(7.0f64), Some(1.0f64), Some(1.0f64)]), "zero lag is identity")
  _ = assert_true(agrees(ind_shift(values(), 2i64), [None, None, Some(4.0f64), Some(-2.0f64), Some(7.0f64)]), "positive lag reads only earlier values")
  assert_true(agrees(ind_diff(values(), 1i64), [None, Some(-6.0f64), Some(9.0f64), Some(-6.0f64), Some(0.0f64)]), "difference subtracts the earlier value")
}
