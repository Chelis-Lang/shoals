module Shoals.Properties.Indicators
import Shoals.Indicators (sma, ema, rma, atr, rsi, true_range, bollinger, crossover, ind_rolling_std, SeedFirstValue, SeedSma, AlphaSpan, AlphaWilder, SmoothWilder, SmoothSimple, DdofPopulation, DdofSample)
import Shoals.References.Indicators (ema_closed_form_textbook, rsi_from_smoothed_averages, true_range_textbook, span_alpha_textbook, wilder_alpha_textbook)
export (opt_value_or, none_count, max_abs_gap, gap_from_index, both, option_shape_gap, masked_series_agrees, expect_from, algebra_agrees_at_both_rsi_guard_branches, true_range_agrees_with_textbook, reference_alpha_definitions_have_not_drifted, linear_ramp, flat_series, closed_form_ema_agrees, constant_series_ema_is_constant, monotone_up_rsi_is_hundred, monotone_down_rsi_is_zero, wilder_rma_differs_from_span_ema, ramp_sma_is_window_midpoint, bollinger_mid_equals_sma, bollinger_width_is_two_k_sigma, ddof_ratio_is_exact, atr_constant_range_recovers_range, ema_look_ahead_absent, rsi_look_ahead_absent, warmup_lengths_match_spec, crossover_silent_during_warmup, output_length_equals_input_length)
-- Properties for `Shoals.Indicators`. Two kinds, and the distinction
-- matters for what they are worth as evidence:
--
-- 1. ANALYTIC IDENTITIES -- a constant series' EMA is that constant, a
--    monotone-up RSI is exactly 100, an SMA over a linear ramp is the
--    window midpoint, Bollinger's band width is exactly 2*k*sigma. These
--    are derivable without running anything, so they CANNOT agree with a
--    shared misunderstanding the way a transcribed decimal can. They are
--    the load-bearing checks.
-- 2. CROSS-CHECKS against `references/indicators.ch`, which computes the
--    exponential average from its closed form rather than its recursion.
--
-- `tests/indicators.ch` additionally pins decimals from
-- `scripts/oracle_indicators.py`. Those catch transcription drift; they do
-- not substitute for the identities above.
--
-- The negative property is `wilder_rma_differs_from_span_ema`: it asserts
-- the two conventions the measured corpus conflated are DISTINGUISHABLE on
-- this input. Without it, every positive test would still pass if `rma`
-- silently used the span alpha -- which is exactly the defect shoals#83
-- reports in ~105 programs.
def opt_value_or(v: Option[f64], d: f64) -> f64 =
  match v with {
    | Some(x) => x
    | None => d
  }
def none_count(a: List[Option[f64]]) -> i64 =
  fold(fn (acc: i64, v: Option[f64]) -> match v with {
    | Some(_) => acc
    | None => add(acc, cast(1, i64))
  }, cast(0, i64), a)
-- Largest absolute disagreement over [0, upto). Treats `None` as 0.0, so it
-- is paired with `option_shape_gap` below: a value gap of zero is only
-- meaningful alongside an identical Some/None pattern.
def max_abs_gap(a: List[Option[f64]], b: List[Option[f64]], upto: i64) -> f64 =
  fold(fn (acc: f64, i: i64) -> {
    g = abs(sub(opt_value_or(index(a, i), cast(0.0, f64)), opt_value_or(index(b, i), cast(0.0, f64))))
    if lt(acc, g) then g else acc
  }, cast(0.0, f64), range(cast(0, i64), upto))
def both(a: bool, b: bool) -> bool = if a then b else false
-- Largest absolute disagreement over [lo_index, upto). The analytic
-- identities below need this rather than `max_abs_gap`: `opt_value_or`
-- reads `None` as 0.0, so comparing a warm-up `None` against a target of
-- `Some(0.0)` AGREES. That is not a hypothetical -- the first version of
-- `monotone_down_rsi_is_zero` passed for exactly that reason, over a
-- region where the indicator returns nothing at all. Prefer
-- `masked_series_agrees` below, which takes the expected warm-up as an
-- integer and rejects a series that returns nothing. The
-- two look-ahead properties still use this helper directly, because they
-- compare a PREFIX of two runs rather than a series against an expectation;
-- they carry their own `none_count` assertion instead.
def gap_from_index(a: List[Option[f64]], b: List[Option[f64]], lo_index: i64, upto: i64) -> f64 =
  fold(fn (acc: f64, i: i64) -> {
    g = abs(sub(opt_value_or(index(a, i), cast(0.0, f64)), opt_value_or(index(b, i), cast(0.0, f64))))
    if lt(acc, g) then g else acc
  }, cast(0.0, f64), range(lo_index, upto))
-- THE comparison primitive for "these two series are the same". Use it in
-- preference to `max_abs_gap` / `gap_from_index`, which cannot be made safe
-- on their own.
--
-- WHY IT TAKES `warmup` AS A NUMBER. `opt_value_or` reads `None` as 0.0, so
-- a value comparison alone agrees wherever the expected value happens to be
-- the default -- and 0.0 is the most common expected value in numeric tests.
-- Two consecutive red-team rounds found four properties green for that
-- reason (`monotone_down_rsi_is_zero`, both Bollinger width properties,
-- `ddof_ratio_is_exact`), and a fifth, `bollinger_mid_equals_sma`, that a
-- RELATIVE shape check could not save: both its sides come from the same
-- `ind_roll`, so an all-`None` regression gave shape gap 0 AND value gap 0.
--
-- Stating the expected warm-up as an integer is what closes the class. A
-- relative check compares the subject against itself; an absolute one
-- cannot. Asserting it on BOTH sides means a caller has to know the answer
-- rather than derive it from the thing under test.
--
-- WHAT IS ABSOLUTE HERE IS THE COUNT, NOT THE BOUNDARY'S PLACEMENT.
-- `option_shape_gap` pins placement only when `b` is an independent
-- expectation (built with `expect_from`); where `b` is derived from the
-- same subject as `a` -- `bollinger_mid_equals_sma` is the one such case --
-- a regression that moves the `None`s while preserving their number
-- satisfies this helper. A red-team round confirmed that by emitting the
-- warm-up `None`s at the END of the series: the suite still caught it, via
-- the properties that compare against `expect_from`, but not via that one
-- property. If you add another subject-vs-subject comparison, build one
-- side with `expect_from` instead.
def masked_series_agrees(a: List[Option[f64]], b: List[Option[f64]], warmup: i64, tol: f64) -> bool = {
  m = len(a)
  -- `lt(warmup, m)` is what makes "cannot be satisfied by a series that
  -- returns nothing" TRUE rather than merely intended. Without it,
  -- `warmup == m` -- every entry absent on both sides -- satisfies both
  -- count equalities, leaves the shape gap at 0 and leaves an empty value
  -- range, so the whole thing passes while comparing nothing. An empty
  -- series is rejected for the same reason. A red-team round found that
  -- hole by probing the helper directly rather than its call sites.
  -- The guards must gate the comparisons LAZILY. `both` is an ordinary
  -- function, so it evaluates both arguments: written as
  -- `both(eq(len(b), m), <compare>)` the length check does not protect the
  -- comparison, and a shorter `b` TRAPS on an out-of-bounds index instead of
  -- returning false. `if` is the only construct here that does not evaluate
  -- the untaken side. Found by probing this helper with mismatched lengths
  -- rather than through a call site -- every live call site compares
  -- equal-length series, so the trap was unreachable from the suite.
  --
  -- `lt(warmup, m)` is what makes "rejects a series that returns nothing"
  -- true rather than merely intended: without it, `warmup == m` satisfies
  -- both count equalities, leaves the shape gap 0 and the value range empty,
  -- so the whole thing passes while comparing nothing. An empty series is
  -- rejected for the same reason.
  if both(eq(len(b), m), lt(warmup, m)) then both(eq(none_count(a), warmup), both(eq(none_count(b), warmup), both(eq(option_shape_gap(a, b, m), cast(0, i64)), lt(gap_from_index(a, b, warmup, m), tol)))) else false
}
-- Lift a dense expectation to the masked shape, so a property can state its
-- expected values and its expected warm-up in one place.
def expect_from(values: List[f64], warmup: i64) -> List[Option[f64]] = map(fn (pr: (i64, f64)) -> if lt(pr.0, warmup) then None else Some(pr.1), enumerate(values))
-- Count of indices in [0, upto) where one side is `Some` and the other
-- `None`. Zero means the warm-up boundaries agree exactly.
def option_shape_gap(a: List[Option[f64]], b: List[Option[f64]], upto: i64) -> i64 =
  fold(fn (acc: i64, i: i64) -> {
    pa = match index(a, i) with {
      | Some(_) => true
      | None => false
    }
    pb = match index(b, i) with {
      | Some(_) => true
      | None => false
    }
    if eq(pa, pb) then acc else add(acc, cast(1, i64))
  }, cast(0, i64), range(cast(0, i64), upto))
def linear_ramp(start: f64, step: f64, m: i64) -> List[f64] = map(fn (i: i64) -> add(start, mul(step, cast(i, f64))), range(cast(0, i64), m))
def flat_series(v: f64, m: i64) -> List[f64] = map(fn (_i: i64) -> v, range(cast(0, i64), m))
-- CROSS-CHECK. The shipped recursion must equal the closed form's
-- geometric-weight sum. `SeedFirstValue` + `AlphaSpan` has no warm-up, so
-- every index is compared.
def closed_form_ema_agrees(xs: List[f64], n: i64, tol: f64) -> bool = {
  shipped = ema(xs, n, SeedFirstValue, AlphaSpan)
  reference = expect_from(ema_closed_form_textbook(xs, n), cast(0, i64))
  masked_series_agrees(shipped, reference, cast(0, i64), tol)
}
-- ANALYTIC. Any exponential average of a constant series is that constant,
-- under every seed and every alpha: the fixed point is reached at the seed.
def constant_series_ema_is_constant(v: f64, n: i64, m: i64, tol: f64) -> bool = {
  xs = flat_series(v, m)
  warm = sub(n, cast(1, i64))
  both(masked_series_agrees(ema(xs, n, SeedFirstValue, AlphaSpan), expect_from(flat_series(v, m), cast(0, i64)), cast(0, i64), tol), both(masked_series_agrees(ema(xs, n, SeedSma, AlphaWilder), expect_from(flat_series(v, m), warm), warm, tol), masked_series_agrees(rma(xs, n), expect_from(flat_series(v, m), warm), warm, tol)))
}
-- ANALYTIC. A strictly increasing close series has zero losses at every
-- step, so with a positive smoothed gain the sum is positive and
-- `100*g/(g+l)` is exactly 100 wherever it is defined. NOT a zero-loss
-- guard -- TA-Lib has none; it guards the SUM and a dead-flat window reads
-- 0 (see `monotone_down_rsi_is_zero`'s sibling edge tests).
def monotone_up_rsi_is_hundred(n: i64, m: i64, tol: f64) -> bool = masked_series_agrees(rsi(linear_ramp(cast(100.0, f64), cast(1.0, f64), m), n, SmoothWilder), expect_from(flat_series(cast(100.0, f64), m), n), n, tol)
-- ANALYTIC. A strictly decreasing series has zero gains, so RS is 0 and RSI
-- is exactly 0.
def monotone_down_rsi_is_zero(n: i64, m: i64, tol: f64) -> bool = masked_series_agrees(rsi(linear_ramp(cast(100.0, f64), cast(-1.0, f64), m), n, SmoothWilder), expect_from(flat_series(cast(0.0, f64), m), n), n, tol)
-- NEGATIVE PARITY. Wilder's alpha (1/n) and the span alpha (2/(n+1)) differ
-- for every n > 1, so `rma` must be DISTINGUISHABLE from the span-seeded
-- average on a non-constant input. If this returns false, `rma` is not
-- Wilder's -- the exact defect shoals#83 measured in ~105 programs, and one
-- that every positive test in this suite would otherwise still pass.
def wilder_rma_differs_from_span_ema(xs: List[f64], n: i64, floor: f64) -> bool = {
  m = len(xs)
  lt(floor, max_abs_gap(rma(xs, n), ema(xs, n, SeedSma, AlphaSpan), m))
}
-- ANALYTIC. The mean of n consecutive terms of an arithmetic progression is
-- the midpoint of the window, so SMA over a ramp is the ramp shifted by
-- (n-1)/2 steps.
def ramp_sma_is_window_midpoint(start: f64, step: f64, n: i64, m: i64, tol: f64) -> bool = {
  offset = mul(step, div(cast(sub(n, cast(1, i64)), f64), cast(2.0, f64)))
  masked_series_agrees(sma(linear_ramp(start, step, m), n), expect_from(map(fn (x: f64) -> sub(x, offset), linear_ramp(start, step, m)), sub(n, cast(1, i64))), sub(n, cast(1, i64)), tol)
}
-- ANALYTIC. Bollinger's middle band IS the simple moving average.
-- Both sides come from the same `ind_roll`, so a RELATIVE shape check
-- agrees under an all-`None` regression (shape gap 0, value gap 0). Only
-- the absolute warm-up closes it; a red-team round found this one green.
def bollinger_mid_equals_sma(xs: List[f64], n: i64, k: f64, tol: f64) -> bool = masked_series_agrees(bollinger(xs, n, k, DdofPopulation).1, sma(xs, n), sub(n, cast(1, i64)), tol)
-- ANALYTIC. upper - lower = 2*k*sigma exactly, whichever ddof is chosen, so
-- this also pins that both bands read the SAME deviation.
def bollinger_width_is_two_k_sigma(xs: List[f64], n: i64, k: f64, ddof_pop: bool, tol: f64) -> bool = {
  m = len(xs)
  bands = if ddof_pop then bollinger(xs, n, k, DdofPopulation) else bollinger(xs, n, k, DdofSample)
  dev = if ddof_pop then ind_rolling_std(xs, n, DdofPopulation) else ind_rolling_std(xs, n, DdofSample)
  warm = sub(n, cast(1, i64))
  gap = fold(fn (acc: f64, i: i64) -> {
    lo = opt_value_or(index(bands.0, i), cast(0.0, f64))
    hi = opt_value_or(index(bands.2, i), cast(0.0, f64))
    s = opt_value_or(index(dev, i), cast(0.0, f64))
    g = abs(sub(sub(hi, lo), mul(mul(cast(2.0, f64), k), s)))
    if lt(acc, g) then g else acc
  }, cast(0.0, f64), range(warm, m))
  -- Shape companion. Without it this property is vacuous under an all-`None`
  -- regression: `opt_value_or` reads every absent band and deviation as 0.0,
  -- so `(0 - 0) - 2k*0` is 0 and the width "agrees" everywhere. A red-team
  -- pass confirmed exactly that -- forcing `bollinger` and `ind_rolling_std`
  -- to return all-`None` left this property PASSING. Same trap as the one
  -- the note above `gap_from_index` describes; three of ten properties did
  -- not get the fix the first time round.
  both(eq(none_count(dev), warm), both(eq(none_count(bands.0), warm), both(eq(none_count(bands.2), warm), lt(gap, tol))))
}
-- ANALYTIC. The population and sample deviations of the same window differ
-- by exactly sqrt(n/(n-1)). This is the `Ddof` axis being real rather than
-- decorative: if both constructors divided by the same n, the ratio would
-- be 1 and this property would fail.
def ddof_ratio_is_exact(xs: List[f64], n: i64, tol: f64) -> bool = {
  m = len(xs)
  pop = ind_rolling_std(xs, n, DdofPopulation)
  samp = ind_rolling_std(xs, n, DdofSample)
  expected = sqrt(div(cast(n, f64), cast(sub(n, cast(1, i64)), f64)))
  warm = sub(n, cast(1, i64))
  gap = fold(fn (acc: f64, i: i64) -> {
    p = opt_value_or(index(pop, i), cast(0.0, f64))
    s = opt_value_or(index(samp, i), cast(0.0, f64))
    g = if lt(p, cast(1e-10, f64)) then cast(0.0, f64) else abs(sub(div(s, p), expected))
    if lt(acc, g) then g else acc
  }, cast(0.0, f64), range(warm, m))
  -- Shape companion, and this one needed it twice over: the `p < 1e-10` skip
  -- above silently exempts every index whose deviation is absent, because
  -- `opt_value_or` reads `None` as 0.0. Under an all-`None` regression every
  -- index was skipped and the property still PASSED (confirmed by a red-team
  -- mutation). The counts are what make the skip safe.
  both(eq(none_count(pop), warm), both(eq(none_count(samp), warm), lt(gap, tol)))
}
-- ANALYTIC. With a constant bar range r and each close equal to the
-- previous close, every true range is exactly r, so any smoothing of it is
-- r. This pins the true-range MAXIMUM (a wrong branch would pick a gap
-- term) and the smoothing's fixed point together.
def atr_constant_range_recovers_range(base: f64, r: f64, n: i64, m: i64, tol: f64) -> bool = {
  half = div(r, cast(2.0, f64))
  masked_series_agrees(atr(flat_series(add(base, half), m), flat_series(add(base, neg(half)), m), flat_series(base, m), n, SmoothWilder), expect_from(flat_series(r, m), n), n, tol)
}
-- NO LOOK-AHEAD. Perturbing only the LAST input changes no earlier output.
-- Checked by running the indicator twice rather than by reading the source,
-- because a stray `index(xs, add(i, 1))` is invisible to inspection but
-- moves these numbers.
def ema_look_ahead_absent(xs: List[f64], n: i64, bump: f64, tol: f64) -> bool = {
  m = len(xs)
  last = sub(m, cast(1, i64))
  perturbed = map(fn (p: (i64, f64)) -> if eq(p.0, last) then add(p.1, bump) else p.1, enumerate(xs))
  base = ema(xs, n, SeedSma, AlphaWilder)
  -- Absolute warm-up assertion, for the reason `masked_series_agrees`
  -- exists: comparing two runs of the SAME function means an all-`None`
  -- regression gives both sides nothing and a prefix gap of 0. A red-team
  -- round confirmed this property green under exactly that mutation.
  both(eq(none_count(base), sub(n, cast(1, i64))), lt(max_abs_gap(base, ema(perturbed, n, SeedSma, AlphaWilder), last), tol))
}
def rsi_look_ahead_absent(xs: List[f64], n: i64, bump: f64, tol: f64) -> bool = {
  m = len(xs)
  last = sub(m, cast(1, i64))
  perturbed = map(fn (p: (i64, f64)) -> if eq(p.0, last) then add(p.1, bump) else p.1, enumerate(xs))
  base = rsi(xs, n, SmoothWilder)
  both(eq(none_count(base), n), lt(max_abs_gap(base, rsi(perturbed, n, SmoothWilder), last), tol))
}
-- The documented warm-up lengths, asserted as `None` counts. `sma` and the
-- `SeedSma` averages warm up for n-1; `SeedFirstValue` does not warm up at
-- all; Wilder-smoothed RSI warms up for n (one for the difference, n-1 for
-- the SMA seed).
def warmup_lengths_match_spec(xs: List[f64], n: i64) -> bool = {
  a = eq(none_count(sma(xs, n)), sub(n, cast(1, i64)))
  b = eq(none_count(ema(xs, n, SeedFirstValue, AlphaSpan)), cast(0, i64))
  c = eq(none_count(ema(xs, n, SeedSma, AlphaSpan)), sub(n, cast(1, i64)))
  d = eq(none_count(rsi(xs, n, SmoothWilder)), n)
  if a then if b then if c then d else false else false else false
}
-- Every series-valued export returns EXACTLY the input length, so output
-- index i always means input index i.
def output_length_equals_input_length(xs: List[f64], n: i64) -> bool = {
  m = len(xs)
  a = eq(len(sma(xs, n)), m)
  b = eq(len(rsi(xs, n, SmoothSimple)), m)
  c = eq(len(rma(xs, n)), m)
  if a then if b then c else false else false
}
-- A crossing is never reported out of a warm-up: wherever either input is
-- `None` at i or i-1, the verdict is `None`, not `false`. A hand-written
-- zero-fill reports a spurious crossing exactly here.
def crossover_silent_during_warmup(xs: List[f64], fast: i64, slow: i64) -> bool = {
  crossings = crossover(sma(xs, fast), sma(xs, slow))
  warm = sub(slow, cast(1, i64))
  silent = fold(fn (acc: bool, i: i64) -> if acc then match index(crossings, i) with {
    | Some(_) => false
    | None => true
  } else false, true, range(cast(0, i64), warm))
  -- "No verdict inside the warm-up" is trivially true of a series that has
  -- no verdicts at all, so also require that one EXISTS past the warm-up.
  -- Same class as the four properties two red-team rounds found vacuous.
  decided = fold(fn (acc: bool, i: i64) -> if acc then true else match index(crossings, i) with {
    | Some(_) => true
    | None => false
  }, false, range(warm, len(xs)))
  both(silent, decided)
}
-- CROSS-CHECKS that `references/indicators.ch` claims to provide. Until a
-- red-team pass pointed it out, four of that file's six exports had no
-- consumer anywhere, so the "agreement checks the algebra, not the
-- transcription" line in its own header described a check that did not
-- exist -- and its RSI entry encoded the same misreading of TA-Lib's guard
-- that the shipped kernel had, so wiring it up unchanged would not have
-- caught that either. Both are fixed, and both are exercised below.
-- ALGEBRA CHECK ONLY. This compares two algebraic FORMS -- TA-Lib's
-- `100*(g/(g+l))` grouping against Wilder's `100 - 100/(1 + g/l)` -- over a
-- grid straddling both guard branches: all-zero (reads 0) and
-- zero-loss-with-positive-gain (reads 100).
--
-- It does NOT call `rsi`, so it does not pin the shipped kernel. The
-- left-hand side is a TRANSCRIPTION of the kernel's expression, and a
-- transcription goes stale silently. A red-team round restored the original
-- loss-guard defect in `src/indicators.ch` and this property stayed green.
-- The shipped guard is pinned by `test_edge_flat_series_rsi_is_zero` and
-- `test_edge_monotone_rise_rsi_is_one_hundred` instead, which do call it.
-- Same overclaim class as `reference_alpha_definitions_have_not_drifted`
-- below, and narrowed the same way rather than given new scope.
def algebra_agrees_at_both_rsi_guard_branches(tol: f64) -> bool = {
  gains = [cast(0.0, f64), cast(0.5, f64), cast(1.0, f64), cast(7.25, f64), cast(100.0, f64)]
  losses = [cast(0.0, f64), cast(0.25, f64), cast(1.0, f64), cast(3.5, f64), cast(99.0, f64)]
  fold(fn (acc: bool, pair: (f64, f64)) -> {
    g = pair.0
    l = pair.1
    kernel_form = if lt(cast(0.0, f64), add(g, l)) then mul(cast(100.0, f64), div(g, add(g, l))) else cast(0.0, f64)
    if acc then lt(abs(sub(kernel_form, rsi_from_smoothed_averages(g, l))), tol) else false
  }, true, flat_map(fn (g: f64) -> map(fn (l: f64) -> (g, l), losses), gains))
}
def ind_min_one(m: i64) -> i64 = if lt(m, cast(1, i64)) then m else cast(1, i64)
-- Pointwise true range against the textbook max, every index past warm-up.
def true_range_agrees_with_textbook(high: List[f64], low: List[f64], close: List[f64], tol: f64) -> bool = {
  m = len(close)
  shipped = true_range(high, low, close)
  gap = fold(fn (acc: f64, i: i64) -> {
    reference = true_range_textbook(index(high, i), index(low, i), index(close, sub(i, cast(1, i64))))
    g = abs(sub(opt_value_or(index(shipped, i), cast(0.0, f64)), reference))
    if lt(acc, g) then g else acc
  }, cast(0.0, f64), range(cast(1, i64), m))
  both(eq(none_count(shipped), ind_min_one(m)), lt(gap, tol))
}
-- REFERENCE-DRIFT GUARD, not a convention check. This pins
-- `references/indicators.ch`'s own alpha definitions against edits to that
-- file. It does NOT test the shipped alphas and must not be read as doing
-- so: a red-team round replaced the shipped `AlphaWilder` with the span
-- alpha -- the exact shoals#83 defect -- and this stayed green.
-- `wilder_rma_differs_from_span_ema` is the property that catches that, by
-- requiring the two to be distinguishable in a real series.
def reference_alpha_definitions_have_not_drifted(tol: f64) -> bool =
  fold(fn (acc: bool, n: i64) -> {
    span = span_alpha_textbook(n)
    wilder = wilder_alpha_textbook(n)
    ok_span = lt(abs(sub(span, div(cast(2.0, f64), cast(add(n, cast(1, i64)), f64)))), tol)
    ok_wilder = lt(abs(sub(wilder, div(cast(1.0, f64), cast(n, f64)))), tol)
    distinct = if eq(n, cast(1, i64)) then true else lt(tol, abs(sub(span, wilder)))
    if acc then both(ok_span, both(ok_wilder, distinct)) else false
  }, true, range(cast(1, i64), cast(30, i64)))
