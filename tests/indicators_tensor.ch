module Shoals.Tests.IndicatorsTensor
import Std.Test (assert_close, assert_eq)
import Shoals.Indicators (sma, ema, rma, true_range, atr, rsi, macd, bollinger, stochastic, adx, donchian, cumulative_vwap, rolling_vwap, crossover, crossunder, ind_rolling_sum, ind_rolling_mean, ind_rolling_std, ind_rolling_min, ind_rolling_max, ind_shift, ind_diff, tensor_sma, tensor_ema, tensor_rma, tensor_true_range, tensor_atr, tensor_rsi, tensor_macd, tensor_bollinger, tensor_stochastic, tensor_adx, tensor_donchian, tensor_cumulative_vwap, tensor_rolling_vwap, tensor_crossover, tensor_crossunder, tensor_ind_rolling_sum, tensor_ind_rolling_mean, tensor_ind_rolling_std, tensor_ind_rolling_min, tensor_ind_rolling_max, tensor_ind_shift, tensor_ind_diff, SeedFirstValue, SeedSma, AlphaSpan, AlphaWilder, SmoothWilder, SmoothSimple, DdofPopulation, DdofSample)
import Shoals.Properties.Indicators (expect_from)
-- Every tensor-accepting variant must be IDENTICAL to its list counterpart,
-- not merely close: it delegates to the same kernel after `to_list`, so
-- any difference at all means the delegation is wrong. Exact equality is the
-- assertion that catches a mis-wired variant -- `tensor_rsi` calling `atr`
-- would still produce plausible numbers, and a tolerance would hide it.
--
-- There are 22 exported variants and a check below for every one of them.
-- That correspondence is NOT asserted here -- Chelis cannot enumerate its own
-- exports at run time, so a test in this file can only check the names it
-- already mentions, which is exactly what goes stale when a 23rd export is
-- added. `scripts/check_tensor_surface_parity.py` does the enumeration over
-- the source instead, and runs as a gate stage.
def identical(a: List[Option[f64]], b: List[Option[f64]]) -> bool = {
  m = len(a)
  if eq(len(b), m) then fold(fn (acc: bool, i: i64) -> if acc then match (index(a, i), index(b, i)) with {
    | (Some(x), Some(y)) => eq(x, y)
    | (None, None) => true
    | _ => false
  } else false, true, range(cast(0, i64), m)) else false
}
def identical_bool(a: List[Option[bool]], b: List[Option[bool]]) -> bool = {
  m = len(a)
  if eq(len(b), m) then fold(fn (acc: bool, i: i64) -> if acc then match (index(a, i), index(b, i)) with {
    | (Some(x), Some(y)) => eq(x, y)
    | (None, None) => true
    | _ => false
  } else false, true, range(cast(0, i64), m)) else false
}
def to01(b: bool) -> f64 = if b then cast(1.0, f64) else cast(0.0, f64)
def tight() -> f64 = cast(1e-12, f64)
def series_high() -> List[f64] = [cast(10.5, f64), cast(11.5, f64), cast(13.0, f64), cast(11.8, f64), cast(10.4, f64), cast(11.6, f64), cast(13.4, f64), cast(14.2, f64), cast(13.5, f64), cast(12.6, f64), cast(14.3, f64), cast(15.4, f64)]
def series_low() -> List[f64] = [cast(9.6, f64), cast(10.4, f64), cast(9.0, f64), cast(10.7, f64), cast(9.5, f64), cast(10.2, f64), cast(11.9, f64), cast(13.1, f64), cast(12.4, f64), cast(11.6, f64), cast(12.9, f64), cast(14.1, f64)]
def series_close() -> List[f64] = [cast(10.0, f64), cast(11.0, f64), cast(12.0, f64), cast(11.0, f64), cast(10.0, f64), cast(11.0, f64), cast(13.0, f64), cast(14.0, f64), cast(13.0, f64), cast(12.0, f64), cast(14.0, f64), cast(15.0, f64)]
def series_volume() -> List[f64] = [cast(100.0, f64), cast(150.0, f64), cast(120.0, f64), cast(180.0, f64), cast(90.0, f64), cast(110.0, f64), cast(200.0, f64), cast(160.0, f64), cast(140.0, f64), cast(130.0, f64), cast(170.0, f64), cast(190.0, f64)]
def series_high_tensor() -> tensor[12, f64] = to_tensor(series_high())
def series_low_tensor() -> tensor[12, f64] = to_tensor(series_low())
def series_close_tensor() -> tensor[12, f64] = to_tensor(series_close())
def series_volume_tensor() -> tensor[12, f64] = to_tensor(series_volume())
def w() -> i64 = cast(3, i64)
def d() -> i64 = cast(2, i64)
-- A CROSSING PAIR. The first fixture never crossed -- `series_close` is below
-- `series_high` at all 12 bars -- so both crossover tests asserted over `None`s
-- and `Some(false)`s only, with zero `Some(true)`, and a fast/slow
-- transposition was invisible. `series_rising` crosses the flat `series_level`
-- upward at index 3 and back down at index 5.
def series_rising() -> List[f64] = [cast(10.0, f64), cast(11.0, f64), cast(12.0, f64), cast(13.0, f64), cast(12.0, f64), cast(11.0, f64), cast(10.0, f64), cast(9.0, f64), cast(10.0, f64), cast(11.0, f64), cast(12.0, f64), cast(13.0, f64)]
def series_level() -> List[f64] = map(fn (_i: i64) -> cast(12.0, f64), range(cast(0, i64), cast(12, i64)))
def series_rising_tensor() -> tensor[12, f64] = to_tensor(series_rising())
def series_level_tensor() -> tensor[12, f64] = to_tensor(series_level())
def count_true(xs: List[Option[bool]]) -> i64 =
  fold(fn (acc: i64, v: Option[bool]) -> match v with {
    | Some(b) => if b then add(acc, cast(1, i64)) else acc
    | None => acc
  }, cast(0, i64), xs)
def test_tensor_rolling_layer_matches_list() -> unit ! { Test } = {
  _ = assert_close(to01(identical(tensor_ind_rolling_sum(series_close_tensor(), w()), ind_rolling_sum(series_close(), w()))), cast(1.0, f64), tight(), "tensor_ind_rolling_sum")
  _ = assert_close(to01(identical(tensor_ind_rolling_mean(series_close_tensor(), w()), ind_rolling_mean(series_close(), w()))), cast(1.0, f64), tight(), "tensor_ind_rolling_mean")
  _ = assert_close(to01(identical(tensor_ind_rolling_std(series_close_tensor(), w(), DdofPopulation), ind_rolling_std(series_close(), w(), DdofPopulation))), cast(1.0, f64), tight(), "tensor_ind_rolling_std population")
  _ = assert_close(to01(identical(tensor_ind_rolling_std(series_close_tensor(), w(), DdofSample), ind_rolling_std(series_close(), w(), DdofSample))), cast(1.0, f64), tight(), "tensor_ind_rolling_std sample")
  _ = assert_close(to01(identical(tensor_ind_rolling_min(series_close_tensor(), w()), ind_rolling_min(series_close(), w()))), cast(1.0, f64), tight(), "tensor_ind_rolling_min")
  _ = assert_close(to01(identical(tensor_ind_rolling_max(series_close_tensor(), w()), ind_rolling_max(series_close(), w()))), cast(1.0, f64), tight(), "tensor_ind_rolling_max")
  _ = assert_close(to01(identical(tensor_ind_shift(series_close_tensor(), cast(2, i64)), ind_shift(series_close(), cast(2, i64)))), cast(1.0, f64), tight(), "tensor_ind_shift")
  assert_close(to01(identical(tensor_ind_diff(series_close_tensor(), cast(1, i64)), ind_diff(series_close(), cast(1, i64)))), cast(1.0, f64), tight(), "tensor_ind_diff")
}
def test_tensor_averages_match_list() -> unit ! { Test } = {
  _ = assert_close(to01(identical(tensor_sma(series_close_tensor(), w()), sma(series_close(), w()))), cast(1.0, f64), tight(), "tensor_sma")
  _ = assert_close(to01(identical(tensor_ema(series_close_tensor(), w(), SeedFirstValue, AlphaSpan), ema(series_close(), w(), SeedFirstValue, AlphaSpan))), cast(1.0, f64), tight(), "tensor_ema pandas seeding")
  _ = assert_close(to01(identical(tensor_ema(series_close_tensor(), w(), SeedSma, AlphaWilder), ema(series_close(), w(), SeedSma, AlphaWilder))), cast(1.0, f64), tight(), "tensor_ema Wilder")
  assert_close(to01(identical(tensor_rma(series_close_tensor(), w()), rma(series_close(), w()))), cast(1.0, f64), tight(), "tensor_rma")
}
def test_tensor_range_indicators_match_list() -> unit ! { Test } = {
  _ = assert_close(to01(identical(tensor_true_range(series_high_tensor(), series_low_tensor(), series_close_tensor()), true_range(series_high(), series_low(), series_close()))), cast(1.0, f64), tight(), "tensor_true_range")
  _ = assert_close(to01(identical(tensor_atr(series_high_tensor(), series_low_tensor(), series_close_tensor(), w(), SmoothWilder), atr(series_high(), series_low(), series_close(), w(), SmoothWilder))), cast(1.0, f64), tight(), "tensor_atr Wilder")
  assert_close(to01(identical(tensor_rsi(series_close_tensor(), w(), SmoothWilder), rsi(series_close(), w(), SmoothWilder))), cast(1.0, f64), tight(), "tensor_rsi")
}
def test_tensor_tuple_indicators_match_list() -> unit ! { Test } = {
  -- Every variant name appears directly inside an `identical(` argument via
  -- `.N` on the call, rather than being bound to a variable first. That keeps
  -- all 22 checks uniform in shape, which is what lets
  -- `scripts/check_tensor_surface_parity.py` hold one strict rule instead of
  -- special-casing the tuple-returning five.
  _ = assert_close(to01(identical(tensor_macd(series_close_tensor(), cast(2, i64), cast(4, i64), w(), SeedFirstValue, AlphaSpan).0, macd(series_close(), cast(2, i64), cast(4, i64), w(), SeedFirstValue, AlphaSpan).0)), cast(1.0, f64), tight(), "tensor_macd line")
  _ = assert_close(to01(identical(tensor_macd(series_close_tensor(), cast(2, i64), cast(4, i64), w(), SeedFirstValue, AlphaSpan).1, macd(series_close(), cast(2, i64), cast(4, i64), w(), SeedFirstValue, AlphaSpan).1)), cast(1.0, f64), tight(), "tensor_macd signal")
  _ = assert_close(to01(identical(tensor_macd(series_close_tensor(), cast(2, i64), cast(4, i64), w(), SeedFirstValue, AlphaSpan).2, macd(series_close(), cast(2, i64), cast(4, i64), w(), SeedFirstValue, AlphaSpan).2)), cast(1.0, f64), tight(), "tensor_macd histogram")
  _ = assert_close(to01(identical(tensor_bollinger(series_close_tensor(), cast(4, i64), cast(2.0, f64), DdofPopulation).0, bollinger(series_close(), cast(4, i64), cast(2.0, f64), DdofPopulation).0)), cast(1.0, f64), tight(), "tensor_bollinger lower")
  _ = assert_close(to01(identical(tensor_bollinger(series_close_tensor(), cast(4, i64), cast(2.0, f64), DdofPopulation).1, bollinger(series_close(), cast(4, i64), cast(2.0, f64), DdofPopulation).1)), cast(1.0, f64), tight(), "tensor_bollinger mid")
  _ = assert_close(to01(identical(tensor_bollinger(series_close_tensor(), cast(4, i64), cast(2.0, f64), DdofPopulation).2, bollinger(series_close(), cast(4, i64), cast(2.0, f64), DdofPopulation).2)), cast(1.0, f64), tight(), "tensor_bollinger upper")
  _ = assert_close(to01(identical(tensor_stochastic(series_high_tensor(), series_low_tensor(), series_close_tensor(), w(), d(), SmoothSimple).0, stochastic(series_high(), series_low(), series_close(), w(), d(), SmoothSimple).0)), cast(1.0, f64), tight(), "tensor_stochastic k")
  _ = assert_close(to01(identical(tensor_stochastic(series_high_tensor(), series_low_tensor(), series_close_tensor(), w(), d(), SmoothSimple).1, stochastic(series_high(), series_low(), series_close(), w(), d(), SmoothSimple).1)), cast(1.0, f64), tight(), "tensor_stochastic d")
  _ = assert_close(to01(identical(tensor_adx(series_high_tensor(), series_low_tensor(), series_close_tensor(), w()).0, adx(series_high(), series_low(), series_close(), w()).0)), cast(1.0, f64), tight(), "tensor_adx plus_di")
  _ = assert_close(to01(identical(tensor_adx(series_high_tensor(), series_low_tensor(), series_close_tensor(), w()).1, adx(series_high(), series_low(), series_close(), w()).1)), cast(1.0, f64), tight(), "tensor_adx minus_di")
  _ = assert_close(to01(identical(tensor_adx(series_high_tensor(), series_low_tensor(), series_close_tensor(), w()).2, adx(series_high(), series_low(), series_close(), w()).2)), cast(1.0, f64), tight(), "tensor_adx adx")
  _ = assert_close(to01(identical(tensor_donchian(series_high_tensor(), series_low_tensor(), w()).0, donchian(series_high(), series_low(), w()).0)), cast(1.0, f64), tight(), "tensor_donchian lower")
  _ = assert_close(to01(identical(tensor_donchian(series_high_tensor(), series_low_tensor(), w()).1, donchian(series_high(), series_low(), w()).1)), cast(1.0, f64), tight(), "tensor_donchian mid")
  assert_close(to01(identical(tensor_donchian(series_high_tensor(), series_low_tensor(), w()).2, donchian(series_high(), series_low(), w()).2)), cast(1.0, f64), tight(), "tensor_donchian upper")
}
def test_tensor_vwap_matches_list() -> unit ! { Test } = {
  _ = assert_close(to01(identical(tensor_cumulative_vwap(series_close_tensor(), series_volume_tensor()), cumulative_vwap(series_close(), series_volume()))), cast(1.0, f64), tight(), "tensor_cumulative_vwap")
  assert_close(to01(identical(tensor_rolling_vwap(series_close_tensor(), series_volume_tensor(), w()), rolling_vwap(series_close(), series_volume(), w()))), cast(1.0, f64), tight(), "tensor_rolling_vwap")
}
-- The crossover pair is the one place the tensor form takes an argument the
-- list form does not, so its equivalence is stated against an EXPLICITLY
-- masked list input rather than a bare series.
def test_tensor_crossover_matches_explicitly_masked_list() -> unit ! { Test } = {
  fw = cast(1, i64)
  sw = cast(1, i64)
  _ = assert_close(to01(identical_bool(tensor_crossover(series_rising_tensor(), fw, series_level_tensor(), sw), crossover(expect_from(series_rising(), fw), expect_from(series_level(), sw)))), cast(1.0, f64), tight(), "tensor_crossover == crossover over the same masks")
  assert_close(to01(identical_bool(tensor_crossunder(series_rising_tensor(), fw, series_level_tensor(), sw), crossunder(expect_from(series_rising(), fw), expect_from(series_level(), sw)))), cast(1.0, f64), tight(), "tensor_crossunder == crossunder over the same masks")
}
-- The fixture must actually CROSS, or every assertion above is over `None`s
-- and `Some(false)`s and a fast/slow transposition is undetectable. Pinned
-- here so a future fixture edit that removes the crossing fails loudly.
def test_tensor_crossover_fixture_actually_crosses() -> unit ! { Test } = {
  fw = cast(1, i64)
  _ = assert_eq(count_true(tensor_crossover(series_rising_tensor(), fw, series_level_tensor(), fw)), cast(2, i64), "the rising series crosses the level upward twice (indices 3 and 11)")
  _ = assert_eq(count_true(tensor_crossunder(series_rising_tensor(), fw, series_level_tensor(), fw)), cast(1, i64), "and downward once (index 5)")
  -- and the transposition is therefore observable
  assert_close(to01(identical_bool(tensor_crossover(series_rising_tensor(), fw, series_level_tensor(), fw), tensor_crossover(series_level_tensor(), fw, series_rising_tensor(), fw))), cast(0.0, f64), tight(), "swapping fast and slow must change the verdict series")
}
-- A wrong warm-up must change the answer, else the parameter is decoration.
def test_tensor_crossover_warmup_argument_is_load_bearing() -> unit ! { Test } = assert_close(to01(identical_bool(tensor_crossover(series_rising_tensor(), cast(4, i64), series_level_tensor(), cast(4, i64)), tensor_crossover(series_rising_tensor(), cast(0, i64), series_level_tensor(), cast(0, i64)))), cast(0.0, f64), tight(), "a different warm-up must give a different verdict series")
-- SWAPPING THE TWO WARM-UPS IS A NO-OP ON THE SUCCESS DOMAIN, which is where
-- this test exercises it. It is NOT a no-op once either value is out of
-- domain: `(-1, 99)` traps with "warm-up must be >= 0" and `(99, -1)` with
-- "warm-up must not exceed the series length", because the guards check the
-- first argument first. The warm-up guards added in the same commit as this
-- comment created that counterexample, and an earlier revision called the
-- swap "provable" without qualification. Which of two traps fires first is an
-- evaluation-order detail rather than a contract, so it is not pinned.
--
-- On the success domain the mechanism holds: `ind_cross`
-- yields a value only where all four of a[i-1], b[i-1], a[i], b[i] are
-- `Some`, so the `None` pattern is the UNION of the two masks and depends only
-- on `max(fast_warmup, slow_warmup)`; the values at defined positions do not
-- depend on either. A red-team round reported the swap as undetected, which is
-- correct behaviour -- pinned here so nobody "fixes" it later.
def test_tensor_crossover_warmup_order_is_a_no_op() -> unit ! { Test } = assert_close(to01(identical_bool(tensor_crossover(series_rising_tensor(), cast(1, i64), series_level_tensor(), cast(4, i64)), tensor_crossover(series_rising_tensor(), cast(4, i64), series_level_tensor(), cast(1, i64)))), cast(1.0, f64), tight(), "only max(fast_warmup, slow_warmup) is observable, so the order cannot matter")
-- P1(c): EVERY variant at a SECOND argument tuple. With one tuple each, a
-- wrapper can hardcode a forwarded scalar or ADT instead of passing it and
-- still agree -- demonstrated by a red-team mutation where `tensor_atr`
-- ignored its `window` and the suite stayed green.
def test_tensor_variants_at_a_second_argument_tuple() -> unit ! { Test } = {
  v = cast(4, i64)
  _ = assert_close(to01(identical(tensor_ind_rolling_sum(series_close_tensor(), v), ind_rolling_sum(series_close(), v))), cast(1.0, f64), tight(), "rolling_sum @ 4")
  _ = assert_close(to01(identical(tensor_ind_rolling_mean(series_close_tensor(), v), ind_rolling_mean(series_close(), v))), cast(1.0, f64), tight(), "rolling_mean @ 4")
  _ = assert_close(to01(identical(tensor_ind_rolling_std(series_close_tensor(), v, DdofSample), ind_rolling_std(series_close(), v, DdofSample))), cast(1.0, f64), tight(), "rolling_std @ 4 sample")
  _ = assert_close(to01(identical(tensor_ind_rolling_min(series_close_tensor(), v), ind_rolling_min(series_close(), v))), cast(1.0, f64), tight(), "rolling_min @ 4")
  _ = assert_close(to01(identical(tensor_ind_rolling_max(series_close_tensor(), v), ind_rolling_max(series_close(), v))), cast(1.0, f64), tight(), "rolling_max @ 4")
  _ = assert_close(to01(identical(tensor_ind_shift(series_close_tensor(), cast(3, i64)), ind_shift(series_close(), cast(3, i64)))), cast(1.0, f64), tight(), "shift @ 3")
  _ = assert_close(to01(identical(tensor_ind_diff(series_close_tensor(), cast(2, i64)), ind_diff(series_close(), cast(2, i64)))), cast(1.0, f64), tight(), "diff @ 2")
  _ = assert_close(to01(identical(tensor_sma(series_close_tensor(), v), sma(series_close(), v))), cast(1.0, f64), tight(), "sma @ 4")
  _ = assert_close(to01(identical(tensor_ema(series_close_tensor(), v, SeedSma, AlphaSpan), ema(series_close(), v, SeedSma, AlphaSpan))), cast(1.0, f64), tight(), "ema @ 4 SeedSma/AlphaSpan")
  _ = assert_close(to01(identical(tensor_rma(series_close_tensor(), v), rma(series_close(), v))), cast(1.0, f64), tight(), "rma @ 4")
  _ = assert_close(to01(identical(tensor_atr(series_high_tensor(), series_low_tensor(), series_close_tensor(), v, SmoothSimple), atr(series_high(), series_low(), series_close(), v, SmoothSimple))), cast(1.0, f64), tight(), "atr @ 4 SmoothSimple -- pins that `window` and `smoothing` are forwarded")
  _ = assert_close(to01(identical(tensor_rsi(series_close_tensor(), v, SmoothSimple), rsi(series_close(), v, SmoothSimple))), cast(1.0, f64), tight(), "rsi @ 4 SmoothSimple")
  _ = assert_close(to01(identical(tensor_macd(series_close_tensor(), cast(3, i64), cast(5, i64), v, SeedSma, AlphaWilder).0, macd(series_close(), cast(3, i64), cast(5, i64), v, SeedSma, AlphaWilder).0)), cast(1.0, f64), tight(), "macd @ second tuple line")
  _ = assert_close(to01(identical(tensor_macd(series_close_tensor(), cast(3, i64), cast(5, i64), v, SeedSma, AlphaWilder).2, macd(series_close(), cast(3, i64), cast(5, i64), v, SeedSma, AlphaWilder).2)), cast(1.0, f64), tight(), "macd @ second tuple histogram")
  _ = assert_close(to01(identical(tensor_bollinger(series_close_tensor(), cast(5, i64), cast(1.5, f64), DdofSample).0, bollinger(series_close(), cast(5, i64), cast(1.5, f64), DdofSample).0)), cast(1.0, f64), tight(), "bollinger @ second tuple lower")
  _ = assert_close(to01(identical(tensor_bollinger(series_close_tensor(), cast(5, i64), cast(1.5, f64), DdofSample).2, bollinger(series_close(), cast(5, i64), cast(1.5, f64), DdofSample).2)), cast(1.0, f64), tight(), "bollinger @ second tuple upper")
  _ = assert_close(to01(identical(tensor_stochastic(series_high_tensor(), series_low_tensor(), series_close_tensor(), v, cast(3, i64), SmoothWilder).0, stochastic(series_high(), series_low(), series_close(), v, cast(3, i64), SmoothWilder).0)), cast(1.0, f64), tight(), "stochastic @ second tuple k")
  _ = assert_close(to01(identical(tensor_stochastic(series_high_tensor(), series_low_tensor(), series_close_tensor(), v, cast(3, i64), SmoothWilder).1, stochastic(series_high(), series_low(), series_close(), v, cast(3, i64), SmoothWilder).1)), cast(1.0, f64), tight(), "stochastic @ second tuple d")
  _ = assert_close(to01(identical(tensor_adx(series_high_tensor(), series_low_tensor(), series_close_tensor(), v).2, adx(series_high(), series_low(), series_close(), v).2)), cast(1.0, f64), tight(), "adx @ second tuple adx")
  _ = assert_close(to01(identical(tensor_donchian(series_high_tensor(), series_low_tensor(), v).1, donchian(series_high(), series_low(), v).1)), cast(1.0, f64), tight(), "donchian @ second tuple mid")
  _ = assert_close(to01(identical(tensor_true_range(series_high_tensor(), series_low_tensor(), series_close_tensor()), true_range(series_high(), series_low(), series_close()))), cast(1.0, f64), tight(), "true_range (no scalar args; the fixture asymmetry is what pins it)")
  _ = assert_close(to01(identical(tensor_cumulative_vwap(series_close_tensor(), series_volume_tensor()), cumulative_vwap(series_close(), series_volume()))), cast(1.0, f64), tight(), "cumulative_vwap")
  assert_close(to01(identical(tensor_rolling_vwap(series_close_tensor(), series_volume_tensor(), v), rolling_vwap(series_close(), series_volume(), v))), cast(1.0, f64), tight(), "rolling_vwap @ 4")
}
-- The fixture property the true-range checks depend on. Without a bar whose
-- intrabar range strictly exceeds both gap terms, `tr(h,l,c) == tr(l,h,c)` and
-- the archetypal high/low transposition is undetectable.
def test_fixture_is_high_low_asymmetric_for_true_range() -> unit ! { Test } = assert_close(to01(identical(true_range(series_high(), series_low(), series_close()), true_range(series_low(), series_high(), series_close()))), cast(0.0, f64), tight(), "swapping high and low must change true_range on this fixture")
