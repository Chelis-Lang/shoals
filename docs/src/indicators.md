# Technical indicators

Module: `Shoals.Indicators`.

Moving averages, true range, ATR, RSI, MACD, Bollinger bands, the stochastic
oscillator, ADX, Donchian channels, VWAP and crossovers, over `List[f64]`.

Two things about this module are unusual, and both are deliberate.

## Every convention is an argument, and none has a default

Technical indicators are not one definition each. The same name covers
several, the variants disagree by a few percent, and **nothing errors** — you
just get different numbers than whoever you are comparing against. Two
examples measured across 431 agent-written Chelis programs (shoals#83):

- 100 of 115 hand-written EMAs seeded the recursion at the first price, the
  way pandas does with `adjust=False`. TA-Lib seeds at the simple average of
  the first `n` prices. Both are "the EMA".
- About 105 programs described their smoothing as "Wilder" while using
  `alpha = 2/(n+1)`. Wilder's is `alpha = 1/n`. For `n = 14` that is 0.133
  against 0.071 — nearly a factor of two in how fast the average forgets.

So the convention is a closed ADT you pass in, and there is no default to
fall through:

```chelis
type EmaSeed = SeedFirstValue | SeedSma
type Alpha = AlphaSpan | AlphaWilder
type Smoothing = SmoothWilder | SmoothEma | SmoothSimple
type Ddof = DdofPopulation | DdofSample
```

| constructor | definition | matches |
|---|---|---|
| `SeedFirstValue` | start at the first valid input | pandas `ewm(adjust=False)` |
| `SeedSma` | start at the mean of the first `n` | TA-Lib `EMA` |
| `AlphaSpan` | `2/(n+1)` | pandas `span=n` |
| `AlphaWilder` | `1/n` | Wilder 1978, TA-Lib `RMA` |
| `SmoothWilder` | `SeedSma` + `AlphaWilder` | Wilder's ATR / RSI |
| `SmoothEma` | `SeedFirstValue` + `AlphaSpan` | the common EMA-scan variant |
| `SmoothSimple` | rolling arithmetic mean | the rolling-mean variant |
| `DdofPopulation` | variance over `n` | TA-Lib `STDDEV`, Bollinger |
| `DdofSample` | variance over `n-1` | pandas `.std()` |

`Ddof` is worth calling out because it is quiet: a Bollinger band built with
`DdofSample` is **wider** than the published definition at every point, and
no caller can tell from the result. `rma(xs, n)` exists as a named function
for the same reason — it is `ema(xs, n, SeedSma, AlphaWilder)`, and naming it
removes the most frequent measured error.

## Warm-up is represented, not filled

Every series-valued function returns `List[Option[f64]]` with **exactly the
input's length**. Output index `i` is input index `i`, always. Indices that no
valid computation covers are `None`:

```chelis
rsi(close, 14, SmoothWilder)
-- [None, None, ..., None, Some(70.53), Some(66.32), ...]
--  \_________ 14 entries _________/
```

The alternatives were a flat `List[f64]` plus a `valid_from` count, and a
shortened list. Both were rejected: a `valid_from` field is ignorable, so a
caller that drops it reads filler as real data, and a shortened list hands
the caller the index arithmetic — which is where hand-written indicators
actually go wrong. You cannot accidentally read a warm-up entry as a number
here; the type will not let you.

**`None` means warm-up and nothing else.** Degenerate cases take a defined
value instead: a dead-flat RSI window reads **0** (TA-Lib guards the *sum* of
smoothed gain and loss and outputs 0 — a monotone rise still reads 100), a
zero-range stochastic window reads 0, and a zero `+DI + -DI` gives `DX = 0`.
Each is commented at its site in `src/indicators.ch`, including where the
module and current TA-Lib differ: the stochastic guard is an exact zero test
where TA-Lib uses a scaled epsilon, and ADX emits 0 where TA-Lib skips the
update and holds the previous value.

**Three cases reach a reported `Some` that is not an ordinary value**, and
they are limitations rather than conventions:

- `DdofSample` with `n = 1` divides by `n - 1 = 0` and yields `Some(NaN)`.
  Reachable through two exports: `ind_rolling_std(xs, 1, DdofSample)` and
  `bollinger(xs, 1, k, DdofSample)` (both bands NaN, mid ordinary). pandas
  gives `NaN` here too, so it is reference-consistent, but it is not guarded
  and `NaN` is not what "a defined value" promises.
- `bollinger(..., k)` with `k < 0` swaps the bands, so `lower` exceeds
  `upper`. The module traps negative volume and negative shifts; it does not
  trap a negative `k`.
- A non-finite input is position-dependent in `ind_rolling_min` /
  `ind_rolling_max`: a window `[10, NaN, 12]` gives min 10 and max 12 (the
  `NaN` is dropped), while `[NaN, 10, 12]` gives `NaN` for both, because the
  fold seeds on the first element and `lt` is false against `NaN`. **Inputs
  are assumed finite.** Guarding would need an O(n) scan per call and is a
  shoals#83 follow-up, not a silent behaviour this page hides.

Warm-up lengths:

| function | warm-up |
|---|---|
| `sma(xs, n)`, `ind_rolling_*(xs, n)` | `n - 1` |
| `ema(xs, n, SeedFirstValue, _)` | none |
| `ema(xs, n, SeedSma, _)`, `rma(xs, n)` | `n - 1` |
| `true_range` | 1 (no previous close) |
| `atr(.., n, SmoothWilder)`, `rsi(.., n, SmoothWilder)` | `n` |
| `adx(.., n)` | `2n - 1` (as TA-Lib) |
| `ind_shift(xs, k)` | `k` |

## Surface

```chelis
def sma(xs: List[f64], n: i64) -> List[Option[f64]]
def ema(xs: List[f64], n: i64, seed: EmaSeed, alpha: Alpha) -> List[Option[f64]]
def rma(xs: List[f64], n: i64) -> List[Option[f64]]
def true_range(high: List[f64], low: List[f64], close: List[f64]) -> List[Option[f64]]
def atr(high: List[f64], low: List[f64], close: List[f64], n: i64, smoothing: Smoothing) -> List[Option[f64]]
def rsi(close: List[f64], n: i64, smoothing: Smoothing) -> List[Option[f64]]
def cumulative_vwap(price: List[f64], volume: List[f64]) -> List[Option[f64]]
def rolling_vwap(price: List[f64], volume: List[f64], n: i64) -> List[Option[f64]]
```

The multi-output indicators return one tuple from one set of bindings, so
their components cannot drift apart:

```chelis
def macd(close: List[f64], fast: i64, slow: i64, signal: i64, seed: EmaSeed, alpha: Alpha)
  -> (List[Option[f64]], List[Option[f64]], List[Option[f64]])   -- (line, signal, histogram)
def bollinger(close: List[f64], n: i64, k: f64, ddof: Ddof)
  -> (List[Option[f64]], List[Option[f64]], List[Option[f64]])   -- (lower, mid, upper)
def stochastic(high: List[f64], low: List[f64], close: List[f64], k_n: i64, d_n: i64, smoothing: Smoothing)
  -> (List[Option[f64]], List[Option[f64]])                      -- (k, d)
def adx(high: List[f64], low: List[f64], close: List[f64], n: i64)
  -> (List[Option[f64]], List[Option[f64]], List[Option[f64]])   -- (+DI, -DI, ADX)
def donchian(high: List[f64], low: List[f64], n: i64)
  -> (List[Option[f64]], List[Option[f64]], List[Option[f64]])   -- (lower, mid, upper)
```

`adx` takes no `Smoothing`: ADX is *defined* with Wilder's, so offering a
choice would invent an indicator Wilder did not publish.

Crossovers consume already-masked series and answer `Option[bool]`, so a
crossing is never reported out of a warm-up:

```chelis
def crossover(a: List[Option[f64]], b: List[Option[f64]]) -> List[Option[bool]]
def crossunder(a: List[Option[f64]], b: List[Option[f64]]) -> List[Option[bool]]
```

```chelis
signals = crossover(sma(close, 50), sma(close, 200))
```

## Rolling layer

```chelis
def ind_rolling_sum(xs: List[f64], n: i64) -> List[Option[f64]]
def ind_rolling_mean(xs: List[f64], n: i64) -> List[Option[f64]]
def ind_rolling_std(xs: List[f64], n: i64, ddof: Ddof) -> List[Option[f64]]
def ind_rolling_min(xs: List[f64], n: i64) -> List[Option[f64]]
def ind_rolling_max(xs: List[f64], n: i64) -> List[Option[f64]]
def ind_shift(xs: List[f64], k: i64) -> List[Option[f64]]
def ind_diff(xs: List[f64], k: i64) -> List[Option[f64]]
```

These are generic time-series primitives, not finance, and they belong in
Nautilus — they are requested there as `nautilus#85`. They carry the `ind_`
prefix to mark them as the borrowed layer, and they live here only because the
rolling family exists in exactly one place in the ecosystem and that copy does
not serve `List[f64]`: `Coral.Window` has the five rolling reductions but only
on
`tensor[n, f32]`, and Coral is not a compiled lane (`coral#26`).
`Nautilus.TimeSeries` is **not** a second copy — it has no rolling family at
any width, only exponential smoothing and AR/ARMA prediction (`nautilus#70`,
`shoals#72`). So `ind_rolling_*` is the second implementation of the
reductions, and `ind_shift` / `ind_diff` duplicate nothing at all: neither
package has a shift, lag or diff. When `nautilus#85` lands, this layer should
be deleted and re-exported.

The rolling reductions re-sum every window rather than carrying a running
total — `O(n*w)` where a running total is `O(n)`. That is deliberate: a
running total accumulates cancellation error across the whole series, and a
library whose entire purpose is agreeing with a named reference should not
trade that away for a constant factor at the window sizes these conventions
use (9, 12, 14, 20, 26).

## Out-of-domain inputs trap

A period below 1, a negative `ind_shift`, unequal input lengths, and negative
volume all `fail(...)`. None of them has a correct answer, and an all-`None`
series would report "no data" for a caller bug. `tests_neg/indicators/`
covers each one.

## Verification

- `properties/indicators.ch` holds the load-bearing checks, and they are
  **analytic identities** rather than recorded outputs: a constant series'
  EMA is that constant under every convention, a strictly rising close gives
  RSI exactly 100, an SMA over an arithmetic ramp is the window midpoint,
  Bollinger's band width is exactly `2*k*sigma`, and the two `Ddof`
  deviations differ by exactly `sqrt(n/(n-1))`. These hold by derivation, so
  they cannot be satisfied by a convention that was misunderstood on both
  sides.
- Two properties assert **no look-ahead** by perturbing only the last input
  and requiring every earlier output to be unchanged — a check on behaviour,
  not on source reading. They cover `ema` and `rsi`. A red-team pass extended
  the same technique to all 22 exported functions with injected-look-ahead detectors
  and found none, but only those two are pinned in the committed suite.
- One property is negative: `wilder_rma_differs_from_span_ema` requires the
  two conflated alphas to be *distinguishable*. Without it, every positive
  test would still pass if `rma` quietly used the span alpha — the exact
  defect shoals#83 measured.
- `references/indicators.ch` recomputes the exponential average from its
  closed form (an explicit geometric-weight sum over the whole prefix)
  rather than its recursion, so a fencepost or seeding error cannot
  reproduce it.
- `scripts/oracle_indicators.py` re-derives every series in Python from the
  cited definitions, sharing no code with `src/`. `tests/indicators.ch` pins
  its decimals. Those figures are transcribed by hand and nothing checks the
  transcription — re-run the script and compare after any kernel change, the
  same way `Shoals.Pricing`'s `erf64` figures work.
- The oracle itself is bracketed by the same derivable facts, because the
  Chelis tests agreeing with it is *symmetric* evidence — it cannot say
  which side is right. `scripts/test_oracle_indicators.py` checks the
  oracle's alphas, analytic identities, published warm-up lengths across
  many periods, and documented degenerate cases.

### Manual gate

`scripts/test_oracle_indicators.py` is a **manual gate**. It is deliberately
not in `scripts/run_local_gate.py` or CI: it guards an evidence-producing
script rather than shipped behaviour, and the shipped behaviour is already
covered by `tests/indicators.ch` in the nightly suite.

| | |
|---|---|
| Command | `python3 scripts/test_oracle_indicators.py` |
| Success | exit 0 with a final `ORACLE SELF-CHECK: PASS` line (16 tests) |
| Owner | shoals#83, `spec/shoals_quant_surface.md` §2.15 |
| Run it | whenever `oracle_indicators.py` changes, and before re-transcribing any decimal into `tests/indicators.ch` |
