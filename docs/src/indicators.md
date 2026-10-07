# Technical indicators

Module: `Shoals.Indicators`.

This module computes moving averages, average true range (ATR), relative
strength index (RSI), moving average convergence/divergence (MACD), average
directional index (ADX), price channels, volume-weighted average price
(VWAP), and crossing signals. Prices and volumes are `List[f64]` series:
one number per observation, in time order. A period such as `n = 14`
counts observations. Multi-series calls expect matching lengths and use
values at the same index. `f64` is a 64-bit floating-point type; periods
and lags use the integer type `i64`. For example, `14i64` is an `i64`
literal.

## Choosing a convention

Some indicator names cover several formulas. Where the module offers a choice,
the caller supplies a constructor from a closed algebraic data type (ADT);
there is no default for that argument.

| Type | Constructor | Meaning |
|---|---|---|
| `EmaSeed` | `SeedFirstValue` | Start an exponential moving average (EMA) at its first available input; the `adjust=False` style of pandas `ewm`. |
| | `SeedSma` | Start at the arithmetic mean of the first `n` available inputs; the TA-Lib EMA seed. |
| `Alpha` | `AlphaSpan` | EMA weight `2 / (n + 1)`. |
| | `AlphaWilder` | EMA weight `1 / n`. |
| `Smoothing` | `SmoothWilder` | SMA seed with Wilder's `1 / n` weight. |
| | `SmoothEma` | First-value seed with `2 / (n + 1)` weight. |
| | `SmoothSimple` | Rolling arithmetic mean of `n` values. |
| `Ddof` | `DdofPopulation` | Divide rolling variance by `n`. |
| | `DdofSample` | Divide rolling variance by `n - 1`. |

`rma(xs, n)` is the fixed combination `ema(xs, n, SeedSma,
AlphaWilder)`. `adx` also fixes Wilder smoothing in its definition. For
Bollinger bands, `DdofPopulation` is the usual population-deviation
convention; with positive `k` and nonzero deviation, `DdofSample` produces
wider bands.

## Reading a result

A numeric output series is a `List[Option[f64]]`; crossing signals use
`List[Option[bool]]`. `Some(value)` reports a result at that observation.
`None` reports an index before the calculation has enough data. Each output
series has the same length as its input, and output index `i` refers to input
index `i`. A tuple-returning function supplies separately aligned series in
the order stated below. A window longer than the available series can leave
all its entries `None`. For crossing signals, `None` also means that the
current or previous pair is unavailable.

The source uses a leading warm-up count internally and masks those positions
at the public boundary. Derived calculations add their own warm-up to their
inputs'. For example, `true_range` needs the previous close, so its first
entry is `None`; Wilder ATR then needs `n` available true-range values and
has `n` leading `None` entries. A recursive EMA starts after its input's
warm-up.

For a series long enough to reach a result, the leading `None` counts are:

| Result | Leading `None` entries |
|---|---:|
| `sma`, `ind_rolling_*`, `rolling_vwap`, Donchian bands, Bollinger bands | `n - 1` |
| `ema(..., SeedFirstValue, ...)` | 0 |
| `ema(..., SeedSma, ...)`, `rma` | `n - 1` |
| `true_range` | 1 |
| `atr(..., SmoothWilder)` and `rsi(..., SmoothWilder)` | `n` |
| `atr` or `rsi` with `SmoothEma` | 1 |
| `atr` or `rsi` with `SmoothSimple` | `n` |
| stochastic `k` | `k_n - 1` |
| stochastic `d` with `SmoothEma`; otherwise | `k_n - 1`; `k_n + d_n - 2` |
| ADX's `plus_di`, `minus_di`; ADX itself | `n`; `2n - 1` |
| `ind_shift(xs, k)`, `ind_diff(xs, k)` | `k` |
| either crossing signal | at least 1; also any index whose current or previous pair contains `None` |

Cumulative VWAP has a leading `None` for each initial observation with zero
cumulative volume. Its warm-up therefore depends on the data. For MACD,
the line begins when both EMAs are available; the signal line adds
`signal - 1` entries if `SeedSma` is used, and the histogram begins with
the signal line. Exact counts for the MACD line follow its chosen seed and
`max(fast, slow)`.

## Indicator functions

The declarations below reproduce the exported parameter and return types in
`src/indicators.ch`; definition bodies are omitted. Every period and
convention argument shown is required.

```text
def sma(xs: List[f64], n: i64) -> List[Option[f64]]
def ema(xs: List[f64], n: i64, seed: EmaSeed, alpha: Alpha) -> List[Option[f64]]
def rma(xs: List[f64], n: i64) -> List[Option[f64]]
def true_range(high: List[f64], low: List[f64], close: List[f64]) -> List[Option[f64]]
def atr(high: List[f64], low: List[f64], close: List[f64], n: i64, smoothing: Smoothing) -> List[Option[f64]]
def rsi(close: List[f64], n: i64, smoothing: Smoothing) -> List[Option[f64]]
def macd(close: List[f64], fast: i64, slow: i64, signal: i64, seed: EmaSeed, alpha: Alpha) -> (List[Option[f64]], List[Option[f64]], List[Option[f64]])
def bollinger(close: List[f64], n: i64, k: f64, ddof: Ddof) -> (List[Option[f64]], List[Option[f64]], List[Option[f64]])
def stochastic(high: List[f64], low: List[f64], close: List[f64], k_n: i64, d_n: i64, smoothing: Smoothing) -> (List[Option[f64]], List[Option[f64]])
def adx(high: List[f64], low: List[f64], close: List[f64], n: i64) -> (List[Option[f64]], List[Option[f64]], List[Option[f64]])
def donchian(high: List[f64], low: List[f64], n: i64) -> (List[Option[f64]], List[Option[f64]], List[Option[f64]])
def cumulative_vwap(price: List[f64], volume: List[f64]) -> List[Option[f64]]
def rolling_vwap(price: List[f64], volume: List[f64], n: i64) -> List[Option[f64]]
def crossover(a: List[Option[f64]], b: List[Option[f64]]) -> List[Option[bool]]
def crossunder(a: List[Option[f64]], b: List[Option[f64]]) -> List[Option[bool]]
```

- `sma` is the arithmetic mean of each full window. `ema` follows
  `out[i] = a * xs[i] + (1 - a) * out[i-1]` after the selected seed;
  `rma` names the Wilder combination.
- `true_range` is `max(high - low, |high - previous_close|,
  |low - previous_close|)`. `atr` smooths that range with the specified
  kernel.
- `rsi` smooths positive close changes (`g`) and negative close changes
  (`l`) separately, then reports `100 * g / (g + l)`. `SmoothWilder` gives
  Wilder's RSI.
- `macd` returns `(line, signal_line, histogram)`:
  `line = EMA(fast) - EMA(slow)`, `signal_line` is an EMA of that line,
  and `histogram = line - signal_line`. Its seed and weight apply to all
  three EMA calculations.
- `bollinger` returns `(lower, mid, upper)` with `mid = sma(close, n)`
  and bands `mid - k * standard_deviation` and
  `mid + k * standard_deviation`.
- `stochastic` returns `(k, d)`. Here `k` is 100 times the close's position
  between the rolling low and high over `k_n`; `d` smooths `k` over `d_n`.
- `adx` returns `(plus_di, minus_di, adx)`. It smooths directional movement
  and true range with Wilder's weight, forms directional indices and DX,
  then smooths DX to obtain ADX.
- `donchian` returns `(lower, mid, upper)`: rolling low, their midpoint,
  and rolling high.
- `cumulative_vwap` divides cumulative price-times-volume by cumulative
  volume. `rolling_vwap` applies the same ratio within each full window.
- `crossover` reports `Some(true)` when `a` moves from at or below `b` at
  the previous index to above it now. `crossunder` reverses the direction.
  A comparable pair without a crossing gives `Some(false)`; missing data
  at either of the two indices gives `None`.

## Rolling and lag functions

These functions accept a plain numeric series and return aligned optional
values. They are also the rolling operations used by the indicators above.

```text
def ind_rolling_sum(xs: List[f64], n: i64) -> List[Option[f64]]
def ind_rolling_mean(xs: List[f64], n: i64) -> List[Option[f64]]
def ind_rolling_std(xs: List[f64], n: i64, ddof: Ddof) -> List[Option[f64]]
def ind_rolling_min(xs: List[f64], n: i64) -> List[Option[f64]]
def ind_rolling_max(xs: List[f64], n: i64) -> List[Option[f64]]
def ind_shift(xs: List[f64], k: i64) -> List[Option[f64]]
def ind_diff(xs: List[f64], k: i64) -> List[Option[f64]]
```

The five rolling reductions operate on each complete window of `n` values.
Standard deviation uses the selected variance divisor. `ind_shift(xs,
k)` reads `xs[i - k]` at index `i`; `ind_diff(xs, k)` reads
`xs[i] - xs[i - k]`. `ind_shift` accepts `k = 0`, while `ind_diff`
requires `k >= 1`.

Rolling reductions recompute each window, so a series of length `m` and
window width `n` takes `O(m * n)` reduction work. `rolling_vwap` also
recomputes each window. Factor that cost into long series or large windows.

## Tensor inputs

Every function above has a `tensor[n, f64]` form named by adding `tensor_`
to the list function's name: `sma` has `tensor_sma`, and `ind_rolling_mean`
has `tensor_ind_rolling_mean`. This includes the rolling and lag functions.

```text
def tensor_sma[n](xs: tensor[n, f64], window: i64) -> List[Option[f64]]
def tensor_ind_rolling_std[n](xs: tensor[n, f64], window: i64, ddof: Ddof) -> List[Option[f64]]
def tensor_atr[n](high: tensor[n, f64], low: tensor[n, f64], close: tensor[n, f64],
                  window: i64, smoothing: Smoothing) -> List[Option[f64]]
def tensor_macd[n](close: tensor[n, f64], fast: i64, slow: i64, signal: i64,
                   seed: EmaSeed, alpha: Alpha)
    -> (List[Option[f64]], List[Option[f64]], List[Option[f64]])
def tensor_crossover[n](fast: tensor[n, f64], fast_warmup: i64,
                        slow: tensor[n, f64], slow_warmup: i64) -> List[Option[bool]]
```

A tensor form returns what its list counterpart returns, element type and
structure included. Each numeric result series keeps its `Option[f64]` mask.
`tensor_macd`, `tensor_bollinger`, `tensor_adx` and `tensor_donchian` return
their three series as a tuple, and `tensor_stochastic` its two, exactly as the
list forms do. `tensor_crossover` and `tensor_crossunder` return
`List[Option[bool]]`. Read a result as you read the list form's: the alignment
and leading-`None` counts in [Reading a result](#reading-a-result) apply
unchanged, so a tensor input adds no warm-up rules of its own.

The tensor forms return lists with the same optional values as the list forms.

The scalar and convention arguments follow the list form's, in the same order
and with the same meaning, so `Ddof`, `Smoothing`, `EmaSeed` and `Alpha`
selections carry across. One spelling differs: wherever a list form calls its
width `n`, the tensor form calls it `window`, because `n` is the dimension
variable in the tensor signature. Widths with another name are unchanged, so
`ind_shift` and `ind_diff` keep `k`.

Length agreement is stronger here than on the list surface. One `[n]` covers
every series a call takes, so a multi-series call such as `tensor_atr` cannot be
given mismatched lengths in the first place. On the list surface that is a trap
checked at run time.

### Crossings need an explicit warm-up

`crossover` and `crossunder` read masked series, and a `tensor[n, f64]` cannot
carry a mask. Their tensor forms therefore take each side's warm-up as a
required `i64`: the number of leading entries the producing indicator left
without a valid value.

```text
tensor_crossover(fast_tensor, 9, slow_tensor, 25)
```

Pass the warm-up the producing indicator actually has. A warm-up of `0` declares
every entry valid; a warm-up equal to the series length declares none valid,
which is legal and reports no crossings. A negative warm-up and a warm-up
greater than the series length are both caller errors and trap.

## Defined cases and input limits

An available result can be zero even when no movement occurs. A flat RSI
window reports `Some(0.0)`; a rise with positive gains and no losses
reports `Some(100.0)`. A stochastic window with exactly zero high-low
range reports `Some(0.0)` for `k`. For ADX, zero smoothed true range gives
a directional index of 0, and zero `plus_di + minus_di` gives DX of 0.
These conditions use exact zero tests. In particular, a tiny nonzero
stochastic range is divided normally, unlike TA-Lib's scaled-epsilon
zero-range test; TA-Lib also holds an ADX update where its directional
checks skip it.

A zero-total-volume *rolling* VWAP window reports the unweighted mean of
its prices. A *cumulative* VWAP remains `None` until cumulative volume
becomes positive.

The module assumes finite numeric inputs. It does not check every `NaN` or
infinity: rolling minimum and maximum can handle a `NaN` differently
depending on its position in the window. Two other cases need care:

- `ind_rolling_std(xs, 1, DdofSample)` yields `Some(NaN)` because its
  divisor is zero. In `bollinger(close, 1, k, DdofSample)`, the lower and
  upper bands are likewise `Some(NaN)` while the midpoint is defined.
- A negative Bollinger `k` is accepted and reverses the band order when
  the deviation is positive.

These are reported values or ordering effects, not `None` warm-up entries.
The module traps a period below 1, unequal lengths in multi-series calls,
negative volume, a negative `ind_shift` lag, and an `ind_diff` lag below 1. On
the tensor crossing forms it also traps a negative warm-up and a warm-up greater
than the series length; a warm-up equal to the length is legal.

See [Property specifications](properties.md) for the financial
relationships stated by this library and [Scope and limitations](scope.md)
for input assumptions and limits.
