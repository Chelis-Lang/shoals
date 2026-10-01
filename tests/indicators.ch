module Shoals.Tests.Indicators
import Std.Test (assert_close, assert_eq)
import Shoals.Indicators (sma, ema, rma, atr, rsi, macd, bollinger, stochastic, adx, donchian, cumulative_vwap, rolling_vwap, true_range, crossover, crossunder, ind_rolling_sum, ind_rolling_mean, ind_rolling_std, ind_rolling_min, ind_rolling_max, ind_shift, ind_diff, SeedFirstValue, SeedSma, AlphaSpan, AlphaWilder, SmoothWilder, SmoothEma, SmoothSimple, DdofPopulation, DdofSample)
import Shoals.Properties.Indicators (opt_value_or, none_count, closed_form_ema_agrees, constant_series_ema_is_constant, monotone_up_rsi_is_hundred, monotone_down_rsi_is_zero, wilder_rma_differs_from_span_ema, ramp_sma_is_window_midpoint, bollinger_mid_equals_sma, bollinger_width_is_two_k_sigma, ddof_ratio_is_exact, atr_constant_range_recovers_range, ema_look_ahead_absent, rsi_look_ahead_absent, warmup_lengths_match_spec, crossover_silent_during_warmup, output_length_equals_input_length)
-- Executable suite for `Shoals.Indicators` (shoals#83).
--
-- TWO TIERS, and the second is the one that carries the weight.
--
-- The `test_property_*` cases below run `properties/indicators.ch`. Those
-- are analytic identities and a closed-form cross-check: they hold by
-- derivation, so they cannot be satisfied by a convention I misunderstood.
--
-- The `test_oracle_*` cases pin decimals produced by
-- `scripts/oracle_indicators.py`, which re-derives every series from the
-- cited definitions in Python with no shared code. Those catch transcription
-- and fencepost drift. They are transcribed BY HAND and nothing checks the
-- transcription -- re-run the script and compare after any kernel change,
-- exactly as `Shoals.Pricing`'s erf64 figures work.
--
-- `test_negative_*` is the parity tier: it asserts that the conventions
-- shoals#83 found conflated are actually DISTINGUISHABLE here. Runtime
-- traps live in `tests_neg/indicators/`.
def to01(b: bool) -> f64 = if b then cast(1.0, f64) else cast(0.0, f64)
def value_at(xs: List[Option[f64]], i: i64) -> f64 = opt_value_or(index(xs, i), cast(-999999.0, f64))
def high_series() -> List[f64] = [cast(10.5, f64), cast(11.5, f64), cast(12.5, f64), cast(11.8, f64), cast(10.4, f64), cast(11.6, f64), cast(13.4, f64), cast(14.2, f64), cast(13.5, f64), cast(12.6, f64), cast(14.3, f64), cast(15.4, f64)]
def low_series() -> List[f64] = [cast(9.6, f64), cast(10.4, f64), cast(11.3, f64), cast(10.7, f64), cast(9.5, f64), cast(10.2, f64), cast(11.9, f64), cast(13.1, f64), cast(12.4, f64), cast(11.6, f64), cast(12.9, f64), cast(14.1, f64)]
def close_series() -> List[f64] = [cast(10.0, f64), cast(11.0, f64), cast(12.0, f64), cast(11.0, f64), cast(10.0, f64), cast(11.0, f64), cast(13.0, f64), cast(14.0, f64), cast(13.0, f64), cast(12.0, f64), cast(14.0, f64), cast(15.0, f64)]
def volume_series() -> List[f64] = [cast(100.0, f64), cast(150.0, f64), cast(120.0, f64), cast(180.0, f64), cast(90.0, f64), cast(110.0, f64), cast(200.0, f64), cast(160.0, f64), cast(140.0, f64), cast(130.0, f64), cast(170.0, f64), cast(190.0, f64)]
def tight() -> f64 = cast(1e-12, f64)
-- Tier 1: properties.
def test_property_closed_form_ema_agrees() -> unit ! { Test } = assert_close(to01(closed_form_ema_agrees(close_series(), cast(3, i64), tight())), cast(1.0, f64), tight(), "ema recursion == closed-form geometric sum")
def test_property_constant_series_ema_is_constant() -> unit ! { Test } = assert_close(to01(constant_series_ema_is_constant(cast(7.25, f64), cast(4, i64), cast(10, i64), tight())), cast(1.0, f64), tight(), "every ema convention fixes a constant series")
def test_property_monotone_up_rsi_is_hundred() -> unit ! { Test } = assert_close(to01(monotone_up_rsi_is_hundred(cast(3, i64), cast(10, i64), tight())), cast(1.0, f64), tight(), "strictly rising close => RSI exactly 100")
def test_property_monotone_down_rsi_is_zero() -> unit ! { Test } = assert_close(to01(monotone_down_rsi_is_zero(cast(3, i64), cast(10, i64), tight())), cast(1.0, f64), tight(), "strictly falling close => RSI exactly 0")
def test_property_ramp_sma_is_window_midpoint() -> unit ! { Test } = assert_close(to01(ramp_sma_is_window_midpoint(cast(5.0, f64), cast(2.0, f64), cast(4, i64), cast(12, i64), tight())), cast(1.0, f64), tight(), "SMA over an arithmetic ramp is the window midpoint")
def test_property_bollinger_mid_equals_sma() -> unit ! { Test } = assert_close(to01(bollinger_mid_equals_sma(close_series(), cast(4, i64), cast(2.0, f64), tight())), cast(1.0, f64), tight(), "Bollinger mid band IS the SMA")
def test_property_bollinger_width_population() -> unit ! { Test } = assert_close(to01(bollinger_width_is_two_k_sigma(close_series(), cast(4, i64), cast(2.0, f64), true, tight())), cast(1.0, f64), tight(), "population band width == 2*k*sigma")
def test_property_bollinger_width_sample() -> unit ! { Test } = assert_close(to01(bollinger_width_is_two_k_sigma(close_series(), cast(4, i64), cast(2.0, f64), false, tight())), cast(1.0, f64), tight(), "sample band width == 2*k*sigma")
def test_property_ddof_ratio_is_exact() -> unit ! { Test } = assert_close(to01(ddof_ratio_is_exact(close_series(), cast(4, i64), cast(1e-10, f64))), cast(1.0, f64), tight(), "sample/population deviation ratio == sqrt(n/(n-1))")
def test_property_atr_constant_range_recovers_range() -> unit ! { Test } = assert_close(to01(atr_constant_range_recovers_range(cast(50.0, f64), cast(1.5, f64), cast(3, i64), cast(10, i64), tight())), cast(1.0, f64), tight(), "constant bar range => ATR is that range")
def test_property_ema_look_ahead_absent() -> unit ! { Test } = assert_close(to01(ema_look_ahead_absent(close_series(), cast(3, i64), cast(50.0, f64), tight())), cast(1.0, f64), tight(), "perturbing the last close moves no earlier ema value")
def test_property_rsi_look_ahead_absent() -> unit ! { Test } = assert_close(to01(rsi_look_ahead_absent(close_series(), cast(3, i64), cast(50.0, f64), tight())), cast(1.0, f64), tight(), "perturbing the last close moves no earlier RSI value")
def test_property_warmup_lengths_match_spec() -> unit ! { Test } = assert_close(to01(warmup_lengths_match_spec(close_series(), cast(4, i64))), cast(1.0, f64), tight(), "documented warm-up lengths hold (§2.15.4)")
def test_property_output_length_equals_input_length() -> unit ! { Test } = assert_close(to01(output_length_equals_input_length(close_series(), cast(4, i64))), cast(1.0, f64), tight(), "every series export returns the input length")
def test_property_crossover_silent_during_warmup() -> unit ! { Test } = assert_close(to01(crossover_silent_during_warmup(close_series(), cast(2, i64), cast(5, i64))), cast(1.0, f64), tight(), "no crossing is reported out of a warm-up")
-- Tier 2: negative parity. The conflated conventions must be distinguishable.
def test_negative_wilder_rma_differs_from_span_ema() -> unit ! { Test } = assert_close(to01(wilder_rma_differs_from_span_ema(close_series(), cast(3, i64), cast(0.01, f64))), cast(1.0, f64), tight(), "rma (alpha=1/n) is NOT the span average (alpha=2/(n+1))")
def test_negative_ema_seeding_is_observable() -> unit ! { Test } = {
  first_seeded = value_at(ema(close_series(), cast(3, i64), SeedFirstValue, AlphaSpan), cast(11, i64))
  sma_seeded = value_at(ema(close_series(), cast(3, i64), SeedSma, AlphaSpan), cast(11, i64))
  assert_close(sub(first_seeded, sma_seeded), cast(0.00048828125, f64), tight(), "pandas and TA-Lib seeding differ by a measurable amount at index 11")
}
def test_negative_atr_smoothing_variants_differ() -> unit ! { Test } = {
  wilder = value_at(atr(high_series(), low_series(), close_series(), cast(3, i64), SmoothWilder), cast(11, i64))
  simple = value_at(atr(high_series(), low_series(), close_series(), cast(3, i64), SmoothSimple), cast(11, i64))
  assert_close(sub(wilder, simple), cast(-0.040415587054818604, f64), tight(), "Wilder and rolling-mean ATR disagree at index 11")
}
def test_negative_ddof_choice_changes_band_width() -> unit ! { Test } = {
  pop = value_at(ind_rolling_std(close_series(), cast(4, i64), DdofPopulation), cast(3, i64))
  samp = value_at(ind_rolling_std(close_series(), cast(4, i64), DdofSample), cast(3, i64))
  assert_close(sub(samp, pop), cast(0.10938979974117838, f64), tight(), "DdofSample and DdofPopulation deviations differ")
}
def test_negative_true_range_first_bar_is_none() -> unit ! { Test } = assert_eq(none_count(true_range(high_series(), low_series(), close_series())), cast(1, i64), "the first bar has no previous close, so true range is None there")
def test_negative_adx_warmup_is_two_n_minus_one() -> unit ! { Test } = assert_eq(none_count(adx(high_series(), low_series(), close_series(), cast(3, i64)).2), cast(5, i64), "ADX(3) warm-up is 2n-1 == 5 (TA-Lib)")
-- Tier 3: oracle decimals from scripts/oracle_indicators.py.
def test_oracle_sma() -> unit ! { Test } = {
  out = sma(close_series(), cast(3, i64))
  _ = assert_close(value_at(out, cast(2, i64)), cast(11.0, f64), tight(), "sma[2]")
  _ = assert_close(value_at(out, cast(3, i64)), cast(11.333333333333334, f64), tight(), "sma[3]")
  assert_close(value_at(out, cast(11, i64)), cast(13.666666666666666, f64), tight(), "sma[11]")
}
def test_oracle_ema_pandas_seeding() -> unit ! { Test } = {
  out = ema(close_series(), cast(3, i64), SeedFirstValue, AlphaSpan)
  _ = assert_close(value_at(out, cast(0, i64)), cast(10.0, f64), tight(), "ema first-seeded[0] == close[0]")
  _ = assert_close(value_at(out, cast(2, i64)), cast(11.25, f64), tight(), "ema first-seeded[2]")
  assert_close(value_at(out, cast(11, i64)), cast(14.12158203125, f64), tight(), "ema first-seeded[11]")
}
def test_oracle_ema_talib_seeding() -> unit ! { Test } = {
  out = ema(close_series(), cast(3, i64), SeedSma, AlphaSpan)
  _ = assert_close(value_at(out, cast(2, i64)), cast(11.0, f64), tight(), "ema sma-seeded[2] == mean of first 3")
  assert_close(value_at(out, cast(11, i64)), cast(14.12109375, f64), tight(), "ema sma-seeded[11]")
}
def test_oracle_rma_wilder() -> unit ! { Test } = {
  out = rma(close_series(), cast(3, i64))
  _ = assert_close(value_at(out, cast(2, i64)), cast(11.0, f64), tight(), "rma[2] == mean of first 3")
  _ = assert_close(value_at(out, cast(4, i64)), cast(10.666666666666668, f64), tight(), "rma[4]")
  assert_close(value_at(out, cast(11, i64)), cast(13.611492150586804, f64), tight(), "rma[11]")
}
def test_oracle_true_range() -> unit ! { Test } = {
  out = true_range(high_series(), low_series(), close_series())
  _ = assert_close(value_at(out, cast(1, i64)), cast(1.5, f64), tight(), "true_range[1]")
  assert_close(value_at(out, cast(6, i64)), cast(2.4000000000000004, f64), tight(), "true_range[6] takes the gap term")
}
def test_oracle_atr_three_variants() -> unit ! { Test } = {
  _ = assert_close(value_at(atr(high_series(), low_series(), close_series(), cast(3, i64), SmoothWilder), cast(11, i64)), cast(1.6595844129451818, f64), tight(), "atr SmoothWilder[11]")
  _ = assert_close(value_at(atr(high_series(), low_series(), close_series(), cast(3, i64), SmoothEma), cast(11, i64)), cast(1.6488281250000003, f64), tight(), "atr SmoothEma[11]")
  assert_close(value_at(atr(high_series(), low_series(), close_series(), cast(3, i64), SmoothSimple), cast(11, i64)), cast(1.7000000000000004, f64), tight(), "atr SmoothSimple[11]")
}
def test_oracle_rsi() -> unit ! { Test } = {
  wilder = rsi(close_series(), cast(3, i64), SmoothWilder)
  _ = assert_close(value_at(wilder, cast(3, i64)), cast(66.66666666666666, f64), cast(1e-10, f64), "rsi wilder[3]")
  _ = assert_close(value_at(wilder, cast(11, i64)), cast(77.93025962040046, f64), cast(1e-10, f64), "rsi wilder[11]")
  assert_close(value_at(rsi(close_series(), cast(3, i64), SmoothSimple), cast(7, i64)), cast(100.0, f64), tight(), "rsi simple[7] == 100 (window all gains)")
}
def test_oracle_macd() -> unit ! { Test } = {
  triple = macd(close_series(), cast(2, i64), cast(4, i64), cast(3, i64), SeedFirstValue, AlphaSpan)
  _ = assert_close(value_at(triple.0, cast(11, i64)), cast(0.642958175657208, f64), cast(1e-10, f64), "macd line[11]")
  _ = assert_close(value_at(triple.1, cast(11, i64)), cast(0.46843527798279055, f64), cast(1e-10, f64), "macd signal[11]")
  assert_close(value_at(triple.2, cast(11, i64)), cast(0.17452289767441748, f64), cast(1e-10, f64), "macd histogram[11] == line - signal")
}
def test_oracle_bollinger() -> unit ! { Test } = {
  bands = bollinger(close_series(), cast(4, i64), cast(2.0, f64), DdofPopulation)
  _ = assert_close(value_at(bands.0, cast(3, i64)), cast(9.585786437626904, f64), cast(1e-10, f64), "bollinger lower[3]")
  _ = assert_close(value_at(bands.1, cast(3, i64)), cast(11.0, f64), tight(), "bollinger mid[3]")
  assert_close(value_at(bands.2, cast(3, i64)), cast(12.414213562373096, f64), cast(1e-10, f64), "bollinger upper[3]")
}
def test_oracle_rolling_std_both_ddof() -> unit ! { Test } = {
  _ = assert_close(value_at(ind_rolling_std(close_series(), cast(4, i64), DdofPopulation), cast(3, i64)), cast(0.7071067811865476, f64), tight(), "population std[3]")
  assert_close(value_at(ind_rolling_std(close_series(), cast(4, i64), DdofSample), cast(3, i64)), cast(0.816496580927726, f64), tight(), "sample std[3]")
}
def test_oracle_stochastic() -> unit ! { Test } = {
  pair = stochastic(high_series(), low_series(), close_series(), cast(3, i64), cast(3, i64), SmoothSimple)
  _ = assert_close(value_at(pair.0, cast(2, i64)), cast(82.75862068965517, f64), cast(1e-10, f64), "stochastic k[2]")
  assert_close(value_at(pair.1, cast(4, i64)), cast(42.6655719759168, f64), cast(1e-10, f64), "stochastic d[4]")
}
def test_oracle_adx() -> unit ! { Test } = {
  triple = adx(high_series(), low_series(), close_series(), cast(3, i64))
  _ = assert_close(value_at(triple.0, cast(3, i64)), cast(46.51162790697673, f64), cast(1e-10, f64), "plus_di[3]")
  _ = assert_close(value_at(triple.1, cast(3, i64)), cast(13.953488372093055, f64), cast(1e-10, f64), "minus_di[3]")
  assert_close(value_at(triple.2, cast(5, i64)), cast(31.777143044748637, f64), cast(1e-10, f64), "adx[5], the first defined index")
}
def test_oracle_donchian() -> unit ! { Test } = {
  triple = donchian(high_series(), low_series(), cast(3, i64))
  _ = assert_close(value_at(triple.0, cast(2, i64)), cast(9.6, f64), tight(), "donchian lower[2]")
  _ = assert_close(value_at(triple.2, cast(2, i64)), cast(12.5, f64), tight(), "donchian upper[2]")
  assert_close(value_at(triple.1, cast(2, i64)), cast(11.05, f64), tight(), "donchian mid[2] is the channel midpoint")
}
def test_oracle_vwap() -> unit ! { Test } = {
  cum = cumulative_vwap(close_series(), volume_series())
  _ = assert_close(value_at(cum, cast(1, i64)), cast(10.6, f64), tight(), "cumulative_vwap[1]")
  _ = assert_close(value_at(cum, cast(11, i64)), cast(12.431034482758621, f64), cast(1e-10, f64), "cumulative_vwap[11]")
  roll = rolling_vwap(close_series(), volume_series(), cast(3, i64))
  _ = assert_close(value_at(roll, cast(2, i64)), cast(11.054054054054054, f64), cast(1e-10, f64), "rolling_vwap[2]")
  assert_close(value_at(roll, cast(11, i64)), cast(13.857142857142858, f64), cast(1e-10, f64), "rolling_vwap[11]")
}
def test_oracle_rolling_layer() -> unit ! { Test } = {
  _ = assert_close(value_at(ind_rolling_sum(close_series(), cast(3, i64)), cast(2, i64)), cast(33.0, f64), tight(), "rolling_sum[2]")
  _ = assert_close(value_at(ind_rolling_mean(close_series(), cast(3, i64)), cast(2, i64)), cast(11.0, f64), tight(), "rolling_mean[2]")
  _ = assert_close(value_at(ind_rolling_min(close_series(), cast(3, i64)), cast(4, i64)), cast(10.0, f64), tight(), "rolling_min[4]")
  assert_close(value_at(ind_rolling_max(close_series(), cast(3, i64)), cast(4, i64)), cast(12.0, f64), tight(), "rolling_max[4]")
}
def test_oracle_shift_and_diff() -> unit ! { Test } = {
  lagged = ind_shift(close_series(), cast(2, i64))
  _ = assert_eq(none_count(lagged), cast(2, i64), "shift by 2 warms up for 2")
  _ = assert_close(value_at(lagged, cast(5, i64)), cast(11.0, f64), tight(), "shift(2)[5] == close[3] == 11.0")
  differenced = ind_diff(close_series(), cast(1, i64))
  _ = assert_close(value_at(differenced, cast(1, i64)), cast(1.0, f64), tight(), "diff(1)[1] == close[1] - close[0]")
  assert_eq(none_count(differenced), cast(1, i64), "diff by 1 warms up for 1")
}
def test_oracle_crossovers() -> unit ! { Test } = {
  fast = sma(close_series(), cast(2, i64))
  slow = sma(close_series(), cast(5, i64))
  ups = crossover(fast, slow)
  downs = crossunder(fast, slow)
  _ = assert_eq(len(ups), cast(12, i64), "crossover output is input-length")
  assert_eq(len(downs), cast(12, i64), "crossunder output is input-length")
}
-- Tier 4: edges and degenerate cases. Each pins a documented convention that
-- is otherwise a silent fallback inside the module.
def test_edge_empty_series_is_empty() -> unit ! { Test } = {
  empty = take(close_series(), cast(0, i64))
  _ = assert_eq(len(sma(empty, cast(3, i64))), cast(0, i64), "sma of an empty series is empty, not a trap")
  _ = assert_eq(len(rma(empty, cast(3, i64))), cast(0, i64), "rma of an empty series is empty")
  _ = assert_eq(len(rsi(empty, cast(3, i64), SmoothWilder)), cast(0, i64), "rsi of an empty series is empty")
  _ = assert_eq(len(true_range(empty, empty, empty)), cast(0, i64), "true_range of an empty series is empty")
  assert_eq(len(cumulative_vwap(empty, empty)), cast(0, i64), "cumulative_vwap of an empty series is empty")
}
def test_edge_window_longer_than_series_is_all_none() -> unit ! { Test } = {
  short = take(close_series(), cast(2, i64))
  _ = assert_eq(len(sma(short, cast(5, i64))), cast(2, i64), "output keeps the input length")
  _ = assert_eq(none_count(sma(short, cast(5, i64))), cast(2, i64), "a window longer than the series is all None")
  assert_eq(none_count(rma(short, cast(5, i64))), cast(2, i64), "an unreachable ema seed is all None, not a partial average")
}
def test_edge_single_element_window_is_identity() -> unit ! { Test } = {
  _ = assert_eq(none_count(sma(close_series(), cast(1, i64))), cast(0, i64), "a window of 1 has no warm-up")
  assert_close(value_at(sma(close_series(), cast(1, i64)), cast(7, i64)), cast(14.0, f64), tight(), "sma(xs, 1) is xs")
}
def test_edge_flat_series_rsi_is_one_hundred() -> unit ! { Test } = {
  flat = [cast(5.0, f64), cast(5.0, f64), cast(5.0, f64), cast(5.0, f64), cast(5.0, f64), cast(5.0, f64)]
  out = rsi(flat, cast(3, i64), SmoothWilder)
  _ = assert_eq(none_count(out), cast(3, i64), "flat-series RSI still warms up for n")
  assert_close(value_at(out, cast(5, i64)), cast(100.0, f64), tight(), "zero average loss reads 100, per TA-Lib's guard -- not 50 and not NaN")
}
def test_edge_zero_range_stochastic_is_zero() -> unit ! { Test } = {
  flat = [cast(7.0, f64), cast(7.0, f64), cast(7.0, f64), cast(7.0, f64), cast(7.0, f64)]
  pair = stochastic(flat, flat, flat, cast(3, i64), cast(2, i64), SmoothSimple)
  _ = assert_close(value_at(pair.0, cast(4, i64)), cast(0.0, f64), tight(), "a zero high-low range reads k = 0, per TA-Lib's guard -- not a division by zero")
  assert_close(value_at(pair.1, cast(4, i64)), cast(0.0, f64), tight(), "and d follows")
}
def test_edge_zero_volume_window_falls_back_to_mean() -> unit ! { Test } = {
  zeros = [cast(0.0, f64), cast(0.0, f64), cast(0.0, f64), cast(0.0, f64)]
  prices = [cast(10.0, f64), cast(12.0, f64), cast(14.0, f64), cast(16.0, f64)]
  _ = assert_close(value_at(rolling_vwap(prices, zeros, cast(3, i64)), cast(2, i64)), cast(12.0, f64), tight(), "a zero-volume window is the unweighted mean of its prices (stated convention)")
  assert_eq(none_count(cumulative_vwap(prices, zeros)), cast(4, i64), "an all-zero-volume cumulative VWAP is all warm-up")
}
def test_edge_warmup_generalises_beyond_one_period() -> unit ! { Test } = {
  _ = assert_close(to01(warmup_lengths_match_spec(close_series(), cast(2, i64))), cast(1.0, f64), tight(), "warm-up lengths hold at n = 2")
  _ = assert_close(to01(warmup_lengths_match_spec(close_series(), cast(6, i64))), cast(1.0, f64), tight(), "warm-up lengths hold at n = 6")
  _ = assert_eq(none_count(adx(high_series(), low_series(), close_series(), cast(2, i64)).2), cast(3, i64), "ADX(2) warm-up is 2n-1 == 3")
  assert_eq(none_count(adx(high_series(), low_series(), close_series(), cast(5, i64)).2), cast(9, i64), "ADX(5) warm-up is 2n-1 == 9")
}
