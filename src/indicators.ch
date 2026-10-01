module Shoals.Indicators
export (EmaSeed, SeedFirstValue, SeedSma, Alpha, AlphaSpan, AlphaWilder, Smoothing, SmoothWilder, SmoothEma, SmoothSimple, Ddof, DdofPopulation, DdofSample, ind_rolling_sum, ind_rolling_mean, ind_rolling_std, ind_rolling_min, ind_rolling_max, ind_shift, ind_diff, sma, ema, rma, true_range, atr, rsi, macd, bollinger, stochastic, adx, donchian, cumulative_vwap, rolling_vwap, crossover, crossunder, tensor_ind_rolling_sum, tensor_ind_rolling_mean, tensor_ind_rolling_std, tensor_ind_rolling_min, tensor_ind_rolling_max, tensor_ind_shift, tensor_ind_diff, tensor_sma, tensor_ema, tensor_rma, tensor_true_range, tensor_atr, tensor_rsi, tensor_macd, tensor_bollinger, tensor_stochastic, tensor_adx, tensor_donchian, tensor_cumulative_vwap, tensor_rolling_vwap, tensor_crossover, tensor_crossunder)
-- Technical indicators over `List[f64]`, specified in
-- `spec/shoals_quant_surface.md` §2.15 and issue shoals#83.
--
-- WHY THIS MODULE NAMES ITS CONVENTIONS. The indicator families here were
-- absent from the whole Chelis ecosystem while being the most frequently
-- hand-written components in the Voyage benchmark captures (true range /
-- ATR 179 programs, EMA 125, RSI 111, Bollinger 97, MACD 45). The measured
-- problem is not effort, it is that the conventions disagree SILENTLY: 100
-- of 115 hand-written EMAs seeded at the first price where TA-Lib seeds at
-- the first window's SMA, and ~105 programs called their smoothing
-- "Wilder" while using alpha = 2/(n+1) rather than Wilder's 1/n. Neither
-- disagreement errors. Both change the numbers. So every convention is a
-- closed ADT argument here, and NONE has a default: a caller must say
-- which definition it means, and an unhandled convention is a type error.
--
-- WARM-UP IS REPRESENTED, NOT FILLED. Every series-valued export returns
-- `List[Option[f64]]` of exactly the input length, with `None` where no
-- valid computation covers the index and no offset between input and
-- output index. A `valid_from` count would be ignorable and a shortened
-- list would move the alignment burden onto the caller, which is where the
-- measured off-by-one and look-ahead defects appear (nautilus#85).
--
-- DEGENERATE CASES TAKE A DEFINED VALUE, they do not become `None`.
-- `None` means warm-up and nothing else. A dead-flat RSI window yields 0 --
-- TA-Lib guards the SUM of smoothed gain and loss, not the loss alone, so
-- "no movement at all" reads 0 while a monotone rise still reads 100. A
-- zero-range stochastic window yields 0. Each site says so, and each site
-- also names where the module and current TA-Lib DIFFER rather than
-- claiming a parity it does not have.
--
-- Three cases reach a reported `Some` that is not an ordinary value, and
-- they are limitations rather than conventions: `DdofSample` with n = 1
-- divides by zero, a negative Bollinger `k` swaps the bands, and a
-- non-finite input is position-dependent in the rolling min/max fold.
-- Inputs are assumed finite. See docs/src/indicators.md.
--
-- Keeping `None` to one meaning is what lets the internal representation
-- carry a leading warm-up count rather than arbitrary holes.
--
-- NO LOOK-AHEAD. No export reads an input index greater than its own
-- output index. `properties/indicators.ch` checks that for `ema` and `rsi`
-- directly, by perturbing the tail of an input and asserting the earlier
-- outputs do not move rather than by inspection. The requirement holds for
-- the whole surface; only those two are pinned executably. Review evidence
-- for the rest belongs in the pull request record, not in this file.
-- Internal dense series: `values` always has the input's length, and the
-- first `warmup` entries are filler that no exported path can observe.
-- Every combinator below propagates `warmup` so that filler never reaches
-- a position that ends up valid -- in particular a recursion must SEED
-- after its input's warm-up, not at index 0.
type Series =
  | Series { values: List[f64], warmup: i64 }
-- The conventions. See §2.15.1.
type EmaSeed =
  | SeedFirstValue
  | SeedSma
type Alpha =
  | AlphaSpan
  | AlphaWilder
type Smoothing =
  | SmoothWilder
  | SmoothEma
  | SmoothSimple
type Ddof =
  | DdofPopulation
  | DdofSample
-- Filler occupies warm-up positions. Its value is never observable through
-- an export; `ind_mask` replaces every one of them with `None`.
def ind_filler() -> f64 = cast(0.0, f64)
def ind_min_i64(a: i64, b: i64) -> i64 = if lt(a, b) then a else b
def ind_max_i64(a: i64, b: i64) -> i64 = if lt(a, b) then b else a
def ind_repeat(v: f64, k: i64) -> List[f64] = map(fn (_i: i64) -> v, range(cast(0, i64), ind_max_i64(k, cast(0, i64))))
-- Out-of-domain inputs trap (§2.15.5). These are caller bugs with no
-- correct answer, so they are `fail`, not narrowings, and carry no issue
-- citation. An all-`None` series would report "no data" for a bad call.
def ind_require_period(n: i64) -> i64 = if lt(n, cast(1, i64)) then fail("Shoals.Indicators: period must be >= 1") else n
def ind_require_same_len(a: i64, b: i64) -> i64 = if eq(a, b) then a else fail("Shoals.Indicators: input series must have equal length")
def ind_sum_list(xs: List[f64]) -> f64 = fold(fn (a: f64, x: f64) -> add(a, x), cast(0.0, f64), xs)
def ind_mean_list(xs: List[f64]) -> f64 = div(ind_sum_list(xs), cast(len(xs), f64))
def ind_min_list(xs: List[f64]) -> f64 = fold(fn (a: f64, x: f64) -> if lt(x, a) then x else a, index(xs, cast(0, i64)), xs)
def ind_max_list(xs: List[f64]) -> f64 = fold(fn (a: f64, x: f64) -> if lt(a, x) then x else a, index(xs, cast(0, i64)), xs)
def ind_add2(a: f64, b: f64) -> f64 = add(a, b)
def ind_sub2(a: f64, b: f64) -> f64 = sub(a, b)
def ind_max3(a: f64, b: f64, c: f64) -> f64 = {
  ab = if lt(a, b) then b else a
  if lt(ab, c) then c else ab
}
-- Rolling variance. `DdofPopulation` divides by n (TA-Lib STDDEV, and what
-- Bollinger bands are defined against); `DdofSample` divides by n - 1
-- (pandas `.std()` default). A Bollinger band built with `DdofSample` is
-- wider than the published definition at every point and nothing
-- reports it, which is why this is an argument and not a constant.
def ind_var_list(xs: List[f64], ddof: Ddof) -> f64 = {
  k = len(xs)
  m = ind_mean_list(xs)
  ss = fold(fn (a: f64, x: f64) -> {
    d = sub(x, m)
    add(a, mul(d, d))
  }, cast(0.0, f64), xs)
  den = match ddof with {
    | DdofPopulation => cast(k, f64)
    | DdofSample => cast(sub(k, cast(1, i64)), f64)
  }
  div(ss, den)
}
def ind_std_pop(xs: List[f64]) -> f64 = sqrt(ind_var_list(xs, DdofPopulation))
def ind_std_sample(xs: List[f64]) -> f64 = sqrt(ind_var_list(xs, DdofSample))
def ind_dense(xs: List[f64]) -> Series = Series { values: xs, warmup: cast(0, i64) }
def ind_all_warmup(m: i64) -> Series = Series { values: ind_repeat(ind_filler(), m), warmup: m }
-- The public boundary: a leading warm-up count becomes leading `None`s.
def ind_mask(s: Series) -> List[Option[f64]] = {
  w = s.warmup
  map(fn (p: (i64, f64)) -> if lt(p.0, w) then None else Some(p.1), enumerate(s.values))
}
-- Rolling reduction over a window of `n`, re-summing each window rather
-- than carrying a running total. That is O(n*w) where a running total is
-- O(n), and it is deliberate (§2.15.3): a running total accumulates
-- cancellation error across the whole series, and a library whose purpose
-- is that the numbers match a named reference should not trade that away
-- at the window sizes these conventions use (9, 12, 14, 20, 26).
def ind_roll(s: Series, n: i64, red: List[f64] -> f64) -> Series = {
  vs = s.values
  m = len(vs)
  w = add(s.warmup, sub(n, cast(1, i64)))
  out = map(fn (i: i64) -> if lt(i, w) then ind_filler() else red(take(skip(vs, add(sub(i, n), cast(1, i64))), n)), range(cast(0, i64), m))
  Series { values: out, warmup: ind_min_i64(w, m) }
}
-- alpha per §2.15.1: `AlphaSpan` is pandas `span=n`, `AlphaWilder` is
-- Wilder 1978 / TA-Lib RMA. These are the two spellings the measurements
-- found conflated under the name "Wilder".
def ind_alpha(n: i64, alpha: Alpha) -> f64 =
  match alpha with {
    | AlphaSpan => div(cast(2.0, f64), cast(add(n, cast(1, i64)), f64))
    | AlphaWilder => div(cast(1.0, f64), cast(n, f64))
  }
-- out[i] = a * xs[i] + (1 - a) * out[i-1]. The recursion seeds AFTER the
-- input's own warm-up: seeding at index 0 would let filler contaminate
-- every later value, since an exponential average never forgets its seed.
def ind_ema_series(s: Series, n: i64, seed: EmaSeed, alpha: Alpha) -> Series = {
  vs = s.values
  w = s.warmup
  m = len(vs)
  a = ind_alpha(n, alpha)
  extra = match seed with {
    | SeedFirstValue => cast(0, i64)
    | SeedSma => sub(n, cast(1, i64))
  }
  start = add(w, extra)
  if gte(start, m) then ind_all_warmup(m) else {
    seed_value = match seed with {
      | SeedFirstValue => index(vs, start)
      | SeedSma => ind_mean_list(take(skip(vs, w), n))
    }
    rest = scan(fn (prev: f64, x: f64) -> add(mul(a, x), mul(sub(cast(1.0, f64), a), prev)), seed_value, skip(vs, add(start, cast(1, i64))))
    Series { values: concat(concat(ind_repeat(ind_filler(), start), [seed_value]), rest), warmup: start }
  }
}
def ind_smooth_series(s: Series, n: i64, kind: Smoothing) -> Series =
  match kind with {
    | SmoothWilder => ind_ema_series(s, n, SeedSma, AlphaWilder)
    | SmoothEma => ind_ema_series(s, n, SeedFirstValue, AlphaSpan)
    | SmoothSimple => ind_roll(s, n, ind_mean_list)
  }
-- Elementwise combination. The result's warm-up is the later of the two,
-- so filler can only land in a position that is itself warm-up.
def ind_zip_series(a: Series, b: Series, f: f64 -> f64 -> f64) -> Series = {
  w = ind_max_i64(a.warmup, b.warmup)
  Series { values: map(fn (p: (f64, f64)) -> f(p.0, p.1), zip(a.values, b.values)), warmup: w }
}
-- Lag by `k`. A negative `k` is a look-ahead, not a shift, so it traps
-- rather than silently reading the future.
def ind_shift_series(s: Series, k: i64) -> Series = {
  vs = s.values
  m = len(vs)
  kk = if lt(k, cast(0, i64)) then fail("Shoals.Indicators: shift must be >= 0 (a negative shift reads the future)") else k
  w = ind_min_i64(add(s.warmup, kk), m)
  out = map(fn (i: i64) -> if lt(i, w) then ind_filler() else index(vs, sub(i, kk)), range(cast(0, i64), m))
  Series { values: out, warmup: w }
}
def ind_rolling_sum(xs: List[f64], n: i64) -> List[Option[f64]] = ind_mask(ind_roll(ind_dense(xs), ind_require_period(n), ind_sum_list))
def ind_rolling_mean(xs: List[f64], n: i64) -> List[Option[f64]] = ind_mask(ind_roll(ind_dense(xs), ind_require_period(n), ind_mean_list))
def ind_rolling_min(xs: List[f64], n: i64) -> List[Option[f64]] = ind_mask(ind_roll(ind_dense(xs), ind_require_period(n), ind_min_list))
def ind_rolling_max(xs: List[f64], n: i64) -> List[Option[f64]] = ind_mask(ind_roll(ind_dense(xs), ind_require_period(n), ind_max_list))
def ind_rolling_std(xs: List[f64], n: i64, ddof: Ddof) -> List[Option[f64]] = {
  nn = ind_require_period(n)
  red = match ddof with {
    | DdofPopulation => ind_std_pop
    | DdofSample => ind_std_sample
  }
  ind_mask(ind_roll(ind_dense(xs), nn, red))
}
def ind_shift(xs: List[f64], k: i64) -> List[Option[f64]] = ind_mask(ind_shift_series(ind_dense(xs), k))
def ind_diff(xs: List[f64], k: i64) -> List[Option[f64]] = {
  kk = if lt(k, cast(1, i64)) then fail("Shoals.Indicators: diff lag must be >= 1") else k
  ind_mask(ind_diff_series(ind_dense(xs), kk))
}
def ind_diff_series(s: Series, k: i64) -> Series = {
  vs = s.values
  m = len(vs)
  w = ind_min_i64(add(s.warmup, k), m)
  out = map(fn (i: i64) -> if lt(i, w) then ind_filler() else sub(index(vs, i), index(vs, sub(i, k))), range(cast(0, i64), m))
  Series { values: out, warmup: w }
}
-- Rolling arithmetic mean. Warm-up n - 1.
def sma(xs: List[f64], n: i64) -> List[Option[f64]] = ind_rolling_mean(xs, n)
-- The exponential recursion with both conventions exposed. `SeedSma` +
-- `AlphaSpan` is TA-Lib `EMA`; `SeedFirstValue` + `AlphaSpan` is pandas
-- `ewm(span=n, adjust=False)`. Neither is a default.
def ema(xs: List[f64], n: i64, seed: EmaSeed, alpha: Alpha) -> List[Option[f64]] = ind_mask(ind_ema_series(ind_dense(xs), ind_require_period(n), seed, alpha))
-- Wilder's smoothing (Wilder 1978; TA-Lib RMA), named because "Wilder"
-- with alpha = 2/(n+1) was the single most common measured convention
-- error. Defined as the composition so the two cannot drift apart.
def rma(xs: List[f64], n: i64) -> List[Option[f64]] = ema(xs, n, SeedSma, AlphaWilder)
-- max(h - l, |h - prev_c|, |l - prev_c|), Wilder 1978. Warm-up 1: the
-- first bar has no previous close, so it is `None` and NOT h - l. That
-- substitution is one of the three ATR variants the measurements found.
def ind_true_range_series(high: List[f64], low: List[f64], close: List[f64]) -> Series = {
  m = ind_require_same_len(ind_require_same_len(len(high), len(low)), len(close))
  out = map(fn (i: i64) -> if lt(i, cast(1, i64)) then ind_filler() else {
    pc = index(close, sub(i, cast(1, i64)))
    ind_max3(sub(index(high, i), index(low, i)), abs(sub(index(high, i), pc)), abs(sub(index(low, i), pc)))
  }, range(cast(0, i64), m))
  Series { values: out, warmup: ind_min_i64(cast(1, i64), m) }
}
def true_range(high: List[f64], low: List[f64], close: List[f64]) -> List[Option[f64]] = ind_mask(ind_true_range_series(high, low, close))
-- `smoothing` applied to true range. All three measured variants are
-- reachable by name: `SmoothWilder` is Wilder's published ATR,
-- `SmoothEma` the alpha = 2/(n+1) scan, `SmoothSimple` the rolling mean.
def atr(high: List[f64], low: List[f64], close: List[f64], n: i64, smoothing: Smoothing) -> List[Option[f64]] = ind_mask(ind_smooth_series(ind_true_range_series(high, low, close), ind_require_period(n), smoothing))
-- RSI, Wilder 1978. Gains and losses are smoothed separately, then
-- RSI = 100 * avg_gain / (avg_gain + avg_loss), which is Wilder's
-- 100 - 100/(1 + RS) rearranged. `SmoothWilder` is the published
-- definition.
--
-- NO MOVEMENT AT ALL YIELDS 0, which is TA-Lib's guard verbatim
-- (`ta_RSI.c`: `tempValue1 = prevGain + prevLoss; if (tempValue1 > 0.0)
-- outReal = 100.0 * (prevGain / tempValue1); else outReal = 0.0;`).
-- A dead-flat window therefore reads 0, not 100 and not NaN, and `None`
-- keeps meaning warm-up only.
--
-- The guard is on the SUM, not on the loss alone. Those differ only when
-- gain and loss are BOTH zero, and there they land on opposite ends of
-- the oscillator -- 0 against 100. An earlier revision of this module
-- guarded the loss and returned 100 while citing TA-Lib for it; a
-- dead-flat window is reachable mid-series on a halted or illiquid
-- instrument, so that read as maximum overbought on a market that had not
-- moved. A monotone rise still reads 100 here, because then the sum is
-- positive and the division is the ordinary one.
def rsi(close: List[f64], n: i64, smoothing: Smoothing) -> List[Option[f64]] = {
  nn = ind_require_period(n)
  m = len(close)
  gains = map(fn (i: i64) -> if lt(i, cast(1, i64)) then ind_filler() else {
    d = sub(index(close, i), index(close, sub(i, cast(1, i64))))
    if lt(cast(0.0, f64), d) then d else cast(0.0, f64)
  }, range(cast(0, i64), m))
  losses = map(fn (i: i64) -> if lt(i, cast(1, i64)) then ind_filler() else {
    d = sub(index(close, sub(i, cast(1, i64))), index(close, i))
    if lt(cast(0.0, f64), d) then d else cast(0.0, f64)
  }, range(cast(0, i64), m))
  one = ind_min_i64(cast(1, i64), m)
  avg_gain = ind_smooth_series(Series { values: gains, warmup: one }, nn, smoothing)
  avg_loss = ind_smooth_series(Series { values: losses, warmup: one }, nn, smoothing)
  ind_mask(ind_zip_series(avg_gain, avg_loss, fn (g: f64, l: f64) -> if lt(cast(0.0, f64), add(g, l)) then mul(cast(100.0, f64), div(g, add(g, l))) else cast(0.0, f64)))
}
-- MACD, Appel. Returned as one tuple from one set of bindings so the line,
-- the signal and the histogram cannot drift apart. Appel's original is
-- 12/26/9 with `AlphaSpan`.
def macd(close: List[f64], fast: i64, slow: i64, signal: i64, seed: EmaSeed, alpha: Alpha) -> (List[Option[f64]], List[Option[f64]], List[Option[f64]]) = {
  f = ind_require_period(fast)
  s = ind_require_period(slow)
  g = ind_require_period(signal)
  dense = ind_dense(close)
  line = ind_zip_series(ind_ema_series(dense, f, seed, alpha), ind_ema_series(dense, s, seed, alpha), ind_sub2)
  sig_line = ind_ema_series(line, g, seed, alpha)
  (ind_mask(line), ind_mask(sig_line), ind_mask(ind_zip_series(line, sig_line, ind_sub2)))
}
-- Bollinger bands. `mid` is the SMA and the bands sit k standard
-- deviations out. Bollinger's definition is n = 20, k = 2 and the
-- POPULATION deviation; `DdofSample` widens every band and nothing
-- reports it, so the choice is explicit.
def bollinger(close: List[f64], n: i64, k: f64, ddof: Ddof) -> (List[Option[f64]], List[Option[f64]], List[Option[f64]]) = {
  nn = ind_require_period(n)
  red = match ddof with {
    | DdofPopulation => ind_std_pop
    | DdofSample => ind_std_sample
  }
  dense = ind_dense(close)
  mid = ind_roll(dense, nn, ind_mean_list)
  dev = ind_roll(dense, nn, red)
  lower = ind_zip_series(mid, dev, fn (m: f64, d: f64) -> sub(m, mul(k, d)))
  upper = ind_zip_series(mid, dev, fn (m: f64, d: f64) -> add(m, mul(k, d)))
  (ind_mask(lower), ind_mask(mid), ind_mask(upper))
}
-- Stochastic oscillator, Lane. k = 100 * (c - min(low, k_n)) /
-- (max(high, k_n) - min(low, k_n)); d is k smoothed over d_n.
--
-- A ZERO RANGE YIELDS 0 rather than dividing by zero. TA-Lib reaches the
-- same answer but NOT by this test: `ta_STOCH.c` guards with
-- `TA_IS_ZERO_SCALED(highest - lowest, fabs(highest) + fabs(lowest))`, and
-- its change history records the exact comparison used here AS the defect it
-- fixed (fix #107, later scaled by #253). So a window that is flat to 15
-- significant digits but carries a sub-epsilon rounding residue -- which
-- ordinary price arithmetic produces, e.g. 0.1 + 0.2 against 0.3 -- is
-- treated as a REAL range here and as a zero range in TA-Lib. The reported
-- k is then `100*(c - lowest)/epsilon`, i.e. wherever `close` happens to sit
-- inside that sub-epsilon band, so it is an arbitrary point in [0, 100]
-- rather than necessarily 100. Matching
-- the scaled test is a dtype-aware epsilon decision, so it is tracked rather
-- than guessed at: shoals#83 follow-up.
def stochastic(high: List[f64], low: List[f64], close: List[f64], k_n: i64, d_n: i64, smoothing: Smoothing) -> (List[Option[f64]], List[Option[f64]]) = {
  kn = ind_require_period(k_n)
  dn = ind_require_period(d_n)
  m = ind_require_same_len(ind_require_same_len(len(high), len(low)), len(close))
  kw = ind_min_i64(sub(kn, cast(1, i64)), m)
  kvals = map(fn (i: i64) -> if lt(i, kw) then ind_filler() else {
    start = add(sub(i, kn), cast(1, i64))
    lo = ind_min_list(take(skip(low, start), kn))
    rng = sub(ind_max_list(take(skip(high, start), kn)), lo)
    if eq(rng, cast(0.0, f64)) then cast(0.0, f64) else mul(cast(100.0, f64), div(sub(index(close, i), lo), rng))
  }, range(cast(0, i64), m))
  kser = Series { values: kvals, warmup: kw }
  (ind_mask(kser), ind_mask(ind_smooth_series(kser, dn, smoothing)))
}
-- +DI / -DI from a Wilder-smoothed directional movement over a
-- Wilder-smoothed true range. A ZERO SMOOTHED RANGE YIELDS 0 here. TA-Lib
-- does something different: `ta_ADX.c` wraps the whole DI/DX/ADX block in
-- `if (prevTR > 0.0)` and SKIPS it, holding the previous ADX rather than
-- emitting a value. The divergence needs a Wilder-smoothed true range of
-- exactly 0.0, which decays geometrically and does not reach it, so no
-- numerical difference has been demonstrated -- but the citation is stated
-- as a difference rather than as parity.
def ind_di(d: f64, t: f64) -> f64 = if eq(t, cast(0.0, f64)) then cast(0.0, f64) else mul(cast(100.0, f64), div(d, t))
-- DX = 100 * |+DI - -DI| / (+DI + -DI). A ZERO SUM YIELDS 0 here; TA-Lib
-- again SKIPS the ADX update and holds `prevADX` (`!TA_IS_ZERO(tempReal)`),
-- contributing 0 only inside its seed accumulation. Same reachability
-- caveat as `ind_di`.
def ind_dx(p: f64, q: f64) -> f64 = {
  s = add(p, q)
  if eq(s, cast(0.0, f64)) then cast(0.0, f64) else mul(cast(100.0, f64), div(abs(sub(p, q)), s))
}
-- Wilder's directional movement system. Returns (+DI, -DI, ADX).
-- Wilder's smoothing is NOT a convention argument here: ADX is defined
-- with it, so exposing a choice would invent an indicator Wilder did not
-- publish. ADX's warm-up is 2n - 1, matching TA-Lib: n for the DI pair
-- (1 for the directional differences, then n - 1 for their SMA seed) and
-- n - 1 more for the SMA seed of the ADX smoothing on top.
def adx(high: List[f64], low: List[f64], close: List[f64], n: i64) -> (List[Option[f64]], List[Option[f64]], List[Option[f64]]) = {
  nn = ind_require_period(n)
  m = ind_require_same_len(ind_require_same_len(len(high), len(low)), len(close))
  one = ind_min_i64(cast(1, i64), m)
  up = map(fn (i: i64) -> if lt(i, cast(1, i64)) then ind_filler() else sub(index(high, i), index(high, sub(i, cast(1, i64)))), range(cast(0, i64), m))
  down = map(fn (i: i64) -> if lt(i, cast(1, i64)) then ind_filler() else sub(index(low, sub(i, cast(1, i64))), index(low, i)), range(cast(0, i64), m))
  plus_dm = map(fn (p: (f64, f64)) -> if lt(p.1, p.0) then if lt(cast(0.0, f64), p.0) then p.0 else cast(0.0, f64) else cast(0.0, f64), zip(up, down))
  minus_dm = map(fn (p: (f64, f64)) -> if lt(p.0, p.1) then if lt(cast(0.0, f64), p.1) then p.1 else cast(0.0, f64) else cast(0.0, f64), zip(up, down))
  smoothed_tr = ind_ema_series(ind_true_range_series(high, low, close), nn, SeedSma, AlphaWilder)
  pdi = ind_zip_series(ind_ema_series(Series { values: plus_dm, warmup: one }, nn, SeedSma, AlphaWilder), smoothed_tr, ind_di)
  mdi = ind_zip_series(ind_ema_series(Series { values: minus_dm, warmup: one }, nn, SeedSma, AlphaWilder), smoothed_tr, ind_di)
  adx_s = ind_ema_series(ind_zip_series(pdi, mdi, ind_dx), nn, SeedSma, AlphaWilder)
  (ind_mask(pdi), ind_mask(mdi), ind_mask(adx_s))
}
-- Donchian channel: the rolling low, midpoint and high over n.
def donchian(high: List[f64], low: List[f64], n: i64) -> (List[Option[f64]], List[Option[f64]], List[Option[f64]]) = {
  nn = ind_require_period(n)
  m = ind_require_same_len(len(high), len(low))
  hi = ind_roll(Series { values: high, warmup: cast(0, i64) }, nn, ind_max_list)
  lo = ind_roll(Series { values: low, warmup: ind_min_i64(cast(0, i64), m) }, nn, ind_min_list)
  mid = ind_zip_series(hi, lo, fn (h: f64, l: f64) -> div(add(h, l), cast(2.0, f64)))
  (ind_mask(lo), ind_mask(mid), ind_mask(hi))
}
-- A negative volume is a data error, not a weighting, so it traps.
def ind_require_nonneg(xs: List[f64]) -> List[f64] = if eq(len(xs), cast(0, i64)) then xs else if lt(ind_min_list(xs), cast(0.0, f64)) then fail("Shoals.Indicators: volume must be >= 0") else xs
def ind_leading_zero_run(xs: List[f64]) -> i64 = fold(fn (a: (i64, bool), x: f64) -> if a.1 then if eq(x, cast(0.0, f64)) then (add(a.0, cast(1, i64)), true) else (a.0, false) else a, (cast(0, i64), true), xs).0
-- Volume-weighted average price from the start of the series.
--
-- A LEADING RUN OF ZERO VOLUME carries no price information at all, so it
-- reports as warm-up -- which it structurally is, being a leading run.
def cumulative_vwap(price: List[f64], volume: List[f64]) -> List[Option[f64]] = {
  m = ind_require_same_len(len(price), len(volume))
  vol = ind_require_nonneg(volume)
  cum_pv = scan(ind_add2, cast(0.0, f64), map(fn (p: (f64, f64)) -> mul(p.0, p.1), zip(price, vol)))
  cum_v = scan(ind_add2, cast(0.0, f64), vol)
  out = map(fn (p: (f64, f64)) -> if eq(p.1, cast(0.0, f64)) then ind_filler() else div(p.0, p.1), zip(cum_pv, cum_v))
  ind_mask(Series { values: out, warmup: ind_min_i64(ind_leading_zero_run(cum_v), m) })
}
-- Volume-weighted average price over a rolling window of n.
--
-- A WINDOW WITH ZERO TOTAL VOLUME falls back to the unweighted mean of
-- the window's prices. That is this module's stated convention, not a
-- cited reference: with no volume there is no information to weight by,
-- and equal weights is the only defensible reading.
def rolling_vwap(price: List[f64], volume: List[f64], n: i64) -> List[Option[f64]] = {
  nn = ind_require_period(n)
  m = ind_require_same_len(len(price), len(volume))
  vol = ind_require_nonneg(volume)
  w = ind_min_i64(sub(nn, cast(1, i64)), m)
  out = map(fn (i: i64) -> if lt(i, w) then ind_filler() else {
    start = add(sub(i, nn), cast(1, i64))
    pw = take(skip(price, start), nn)
    vw = take(skip(vol, start), nn)
    tot = ind_sum_list(vw)
    if eq(tot, cast(0.0, f64)) then ind_mean_list(pw) else div(ind_sum_list(map(fn (p: (f64, f64)) -> mul(p.0, p.1), zip(pw, vw))), tot)
  }, range(cast(0, i64), m))
  ind_mask(Series { values: out, warmup: w })
}
-- Crossovers over already-masked series. `None` wherever either input is
-- `None` at i or i-1, so a crossing is never reported out of a warm-up --
-- the case where a hand-written `at_z` zero-fill invents a signal.
def ind_cross(a: List[Option[f64]], b: List[Option[f64]], rising: bool) -> List[Option[bool]] = {
  m = ind_require_same_len(len(a), len(b))
  map(fn (i: i64) -> if lt(i, cast(1, i64)) then None else match (index(a, sub(i, cast(1, i64))), index(b, sub(i, cast(1, i64))), index(a, i), index(b, i)) with {
    | (Some(a0), Some(b0), Some(a1), Some(b1)) => if rising then Some(if lte(a0, b0) then lt(b1, a1) else false) else Some(if lte(b0, a0) then lt(a1, b1) else false)
    | _ => None
  }, range(cast(0, i64), m))
}
def crossover(a: List[Option[f64]], b: List[Option[f64]]) -> List[Option[bool]] = ind_cross(a, b, true)
def crossunder(a: List[Option[f64]], b: List[Option[f64]]) -> List[Option[bool]] = ind_cross(a, b, false)
-- TENSOR-ACCEPTING FORMS. shoals#83 asks that every function "accept
-- `List[f64]` or `tensor[n, f64]`"; that bullet governs the INPUT. The
-- return contract is the issue's separate bullet -- "a length-n series with
-- a warm-up mask" -- which `List[Option[f64]]` already satisfies, so these
-- return exactly what their list counterparts return. A tensor CANNOT carry
-- the warm-up: `tensor[n, Option[f64]]` is rejected ("expected precision
-- type name"), so returning a tensor would force a second, weaker warm-up
-- convention. These do not.
--
-- WHY NOT A TENSOR RETURN. Three grounds, one per candidate shape that has
-- actually been proposed. This deliberately does NOT claim to enumerate every
-- conceivable tensor return -- three successive red-team rounds each broke a
-- completeness claim here (first "only two candidates", then one criterion,
-- then two), and the claim was never load-bearing: the decision is the return
-- type, not a proof of impossibility. If a fourth shape turns up, judge it on
-- its own terms rather than extending a lemma.
--
--   * A SIBLING channel -- a scalar count, a parallel `bool` tensor, a record
--     field, a tuple component -- is droppable: a caller reads one component
--     and the marker is gone. That is §2.15.2's hazard verbatim.
--     `(tensor[n, f64], tensor[n, bool])` type-checks at this pin and falls
--     here, not to non-existence.
--   * An IN-ELEMENT SENTINEL (a NaN fill) has no sibling to drop, so the
--     droppability ground does not reach it. It fails because it is
--     indistinguishable from a computed value and propagates silently --
--     "represented, not filled", above.
--   * A MARKER-FREE return (hand the tensor back and document that the first
--     n-1 entries are unspecified) or a SHORTENED one fails on a
--     ground §2.15.2 already states: it moves the alignment burden onto the
--     caller, which is where the measured off-by-one and look-ahead defects
--     appear (nautilus#85).
--
-- `tensor[n, Option[f64]]` is separately not expressible: a tensor element
-- must be a precision type.
--
-- The name of every variant is `tensor_` prepended to the list name, with no
-- exceptions, so a generator can derive it by rule rather than by lookup.
-- That is also why the borrowed-layer `ind_` marker survives into
-- `tensor_ind_rolling_sum` instead of being tidied away: predictability beats
-- the shorter spelling. A `_tensor` SUFFIX was rejected for a duller reason --
-- `true_range_tensor` shares the `true_` prefix with `true_range` and trips
-- §7.1's shared-prefix rule.
def tensor_ind_rolling_sum[n](xs: tensor[n, f64], window: i64) -> List[Option[f64]] = ind_rolling_sum(to_list(xs), window)
def tensor_ind_rolling_mean[n](xs: tensor[n, f64], window: i64) -> List[Option[f64]] = ind_rolling_mean(to_list(xs), window)
def tensor_ind_rolling_std[n](xs: tensor[n, f64], window: i64, ddof: Ddof) -> List[Option[f64]] = ind_rolling_std(to_list(xs), window, ddof)
def tensor_ind_rolling_min[n](xs: tensor[n, f64], window: i64) -> List[Option[f64]] = ind_rolling_min(to_list(xs), window)
def tensor_ind_rolling_max[n](xs: tensor[n, f64], window: i64) -> List[Option[f64]] = ind_rolling_max(to_list(xs), window)
def tensor_ind_shift[n](xs: tensor[n, f64], k: i64) -> List[Option[f64]] = ind_shift(to_list(xs), k)
def tensor_ind_diff[n](xs: tensor[n, f64], k: i64) -> List[Option[f64]] = ind_diff(to_list(xs), k)
def tensor_sma[n](xs: tensor[n, f64], window: i64) -> List[Option[f64]] = sma(to_list(xs), window)
def tensor_ema[n](xs: tensor[n, f64], window: i64, seed: EmaSeed, alpha: Alpha) -> List[Option[f64]] = ema(to_list(xs), window, seed, alpha)
def tensor_rma[n](xs: tensor[n, f64], window: i64) -> List[Option[f64]] = rma(to_list(xs), window)
def tensor_true_range[n](high: tensor[n, f64], low: tensor[n, f64], close: tensor[n, f64]) -> List[Option[f64]] = true_range(to_list(high), to_list(low), to_list(close))
def tensor_atr[n](high: tensor[n, f64], low: tensor[n, f64], close: tensor[n, f64], window: i64, smoothing: Smoothing) -> List[Option[f64]] = atr(to_list(high), to_list(low), to_list(close), window, smoothing)
def tensor_rsi[n](close: tensor[n, f64], window: i64, smoothing: Smoothing) -> List[Option[f64]] = rsi(to_list(close), window, smoothing)
def tensor_macd[n](close: tensor[n, f64], fast: i64, slow: i64, signal: i64, seed: EmaSeed, alpha: Alpha) -> (List[Option[f64]], List[Option[f64]], List[Option[f64]]) = macd(to_list(close), fast, slow, signal, seed, alpha)
def tensor_bollinger[n](close: tensor[n, f64], window: i64, k: f64, ddof: Ddof) -> (List[Option[f64]], List[Option[f64]], List[Option[f64]]) = bollinger(to_list(close), window, k, ddof)
def tensor_stochastic[n](high: tensor[n, f64], low: tensor[n, f64], close: tensor[n, f64], k_n: i64, d_n: i64, smoothing: Smoothing) -> (List[Option[f64]], List[Option[f64]]) = stochastic(to_list(high), to_list(low), to_list(close), k_n, d_n, smoothing)
def tensor_adx[n](high: tensor[n, f64], low: tensor[n, f64], close: tensor[n, f64], window: i64) -> (List[Option[f64]], List[Option[f64]], List[Option[f64]]) = adx(to_list(high), to_list(low), to_list(close), window)
def tensor_donchian[n](high: tensor[n, f64], low: tensor[n, f64], window: i64) -> (List[Option[f64]], List[Option[f64]], List[Option[f64]]) = donchian(to_list(high), to_list(low), window)
def tensor_cumulative_vwap[n](price: tensor[n, f64], volume: tensor[n, f64]) -> List[Option[f64]] = cumulative_vwap(to_list(price), to_list(volume))
def tensor_rolling_vwap[n](price: tensor[n, f64], volume: tensor[n, f64], window: i64) -> List[Option[f64]] = rolling_vwap(to_list(price), to_list(volume), window)
-- Lift a tensor and an explicit warm-up count into the masked shape. Private:
-- the only callers are the two crossover variants below.
def ind_mask_tensor[n](t: tensor[n, f64], warmup: i64) -> List[Option[f64]] = {
  vs = to_list(t)
  m = len(vs)
  -- The warm-up is the only integer the tensor surface accepts that the list
  -- surface does not, and it was the only one on this module with no domain
  -- guard. Unguarded, a negative warm-up read silently as 0, and a warm-up
  -- past the end returned an all-`None` series -- which §2.15.6 names in so
  -- many words as the wrong answer to a caller bug. `ind_shift` traps its
  -- negative offset; this is the same defect shape and now traps too. A
  -- warm-up EQUAL to the length stays legal: a producing indicator whose
  -- window exceeded the series legitimately warms up for all of it.
  bounded = if lt(warmup, cast(0, i64)) then fail("Shoals.Indicators: warm-up must be >= 0") else if lt(m, warmup) then fail("Shoals.Indicators: warm-up must not exceed the series length") else warmup
  map(fn (pr: (i64, f64)) -> if lt(pr.0, bounded) then None else Some(pr.1), enumerate(vs))
}
-- THE CROSSOVER PAIR NEEDS AN ARGUMENT ITS LIST FORM DOES NOT, and this is
-- the one place the tensor surface is not a pure adapter. `crossover` consumes
-- already-masked series, and a tensor cannot carry a mask, so each side's
-- warm-up has to come in separately.
--
-- Supplying it as a REQUIRED PARAMETER is what makes this acceptable. The
-- reason a `valid_from` count was rejected for the RETURN type is that a
-- caller can drop it and read filler as data; a required parameter cannot be
-- dropped -- the call does not compile without it. So the same integer that
-- was unsafe outbound is safe inbound.
--
-- Pass the warm-up the producing indicator documents: `n - 1` for
-- `sma`/`rma`/`ind_rolling_*`, 0 for `SeedFirstValue`, `n` for Wilder ATR and
-- RSI, `2n - 1` for ADX. Getting it wrong reports a crossing out of a
-- warm-up, which is the defect the masked form exists to prevent -- so prefer
-- the list forms, which carry the mask for you, whenever you have the choice.
def tensor_crossover[n](fast: tensor[n, f64], fast_warmup: i64, slow: tensor[n, f64], slow_warmup: i64) -> List[Option[bool]] = crossover(ind_mask_tensor(fast, fast_warmup), ind_mask_tensor(slow, slow_warmup))
def tensor_crossunder[n](fast: tensor[n, f64], fast_warmup: i64, slow: tensor[n, f64], slow_warmup: i64) -> List[Option[bool]] = crossunder(ind_mask_tensor(fast, fast_warmup), ind_mask_tensor(slow, slow_warmup))
