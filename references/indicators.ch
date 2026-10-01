module Shoals.References.Indicators
export (ema_closed_form_textbook, rsi_from_smoothed_averages, true_range_textbook, span_alpha_textbook, wilder_alpha_textbook, integer_power)
-- Textbook forms for `Shoals.Indicators`, written to be INDEPENDENT of the
-- shipped implementation rather than merely different text.
--
-- `src/indicators.ch` computes the exponential average by the recursion
-- `out[i] = a*x[i] + (1-a)*out[i-1]`. This module computes the SAME series
-- from its closed form, as an explicit geometric-weight sum over the whole
-- prefix. The two share no control flow: a fencepost or seeding error in
-- the recursion cannot reproduce the closed form's weights, so
-- `properties/indicators.ch` comparing them is a real cross-check and not a
-- restatement. That is also why this file does not re-derive SMA or the
-- rolling reductions: a second direct window sum would prove nothing.
--
-- The RSI entry is here for the same reason, and the two sides are this way
-- round: THIS FILE evaluates Wilder's `100 - 100/(1 + g/l)`, the SHIPPED
-- kernel evaluates `100*(g/(g+l))`. Agreement checks the algebra, not the
-- transcription. (An earlier revision of this comment named them the other
-- way round -- i.e. described the restatement that keeping them distinct
-- exists to avoid.)
-- 2/(n+1), pandas `ewm(span=n)`.
def span_alpha_textbook(n: i64) -> f64 = div(cast(2.0, f64), cast(add(n, cast(1, i64)), f64))
-- 1/n, Wilder 1978. The distinction from `span_alpha_textbook` is the single
-- most frequently conflated convention in the measured corpus (shoals#83).
def wilder_alpha_textbook(n: i64) -> f64 = div(cast(1.0, f64), cast(n, f64))
def integer_power(b: f64, k: i64) -> f64 = fold(fn (acc: f64, _i: i64) -> mul(acc, b), cast(1.0, f64), range(cast(0, i64), k))
-- The closed form of the first-value-seeded exponential average:
--
--   out[i] = (1-a)^i * x[0] + sum_{j=1..i} a*(1-a)^(i-j) * x[j]
--
-- Derived by unrolling the recursion to its seed. No scan, no running
-- state: each output index re-weights the entire prefix from scratch.
def ema_closed_form_textbook(xs: List[f64], n: i64) -> List[f64] = {
  a = span_alpha_textbook(n)
  one_minus = sub(cast(1.0, f64), a)
  map(fn (i: i64) -> fold(fn (acc: f64, p: (i64, f64)) -> {
    j = p.0
    weight = if eq(j, cast(0, i64)) then integer_power(one_minus, i) else mul(a, integer_power(one_minus, sub(i, j)))
    add(acc, mul(weight, p.1))
  }, cast(0.0, f64), enumerate(take(xs, add(i, cast(1, i64))))), range(cast(0, i64), len(xs)))
}
-- Wilder's `100 - 100/(1 + RS)` with `RS = g/l`, which is algebraically
-- equal to the shipped kernel's `100*g/(g+l)` whenever l > 0. The two
-- spellings are kept on opposite sides deliberately: if both evaluated the
-- same expression this cross-check would be a restatement.
--
-- No movement at all reads 0, matching TA-Lib's sum guard. A zero loss with
-- a positive gain reads 100; the explicit branch for it is deliberate rather
-- than load-bearing, since the fall-through would already return 100 via
-- `g/0 = +inf` and `100 - 100/(1+inf)`. Relying on infinity arithmetic to
-- carry a reference value is worse than naming the case, so the branch
-- stays. Either way the agreement below covers the degenerate boundary, not
-- just the interior.
def rsi_from_smoothed_averages(g: f64, l: f64) -> f64 = if lte(add(g, l), cast(0.0, f64)) then cast(0.0, f64) else if eq(l, cast(0.0, f64)) then cast(100.0, f64) else sub(cast(100.0, f64), div(cast(100.0, f64), add(cast(1.0, f64), div(g, l))))
-- max(h - l, |h - prev_c|, |l - prev_c|), Wilder 1978.
def true_range_textbook(h: f64, l: f64, prev_c: f64) -> f64 = {
  a = sub(h, l)
  b = abs(sub(h, prev_c))
  c = abs(sub(l, prev_c))
  ab = if lt(a, b) then b else a
  if lt(ab, c) then c else ab
}
