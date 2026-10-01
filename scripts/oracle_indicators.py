#!/usr/bin/env python3
"""Reference oracle for `Shoals.Indicators` (shoals#83).

Independent reference values for `tests/indicators.ch`. The formulas here are
written straight from the cited definitions and share no code with
`src/indicators.ch`, so a misreading of a convention shows up as a
disagreement rather than passing both sides.

This is a SUPPORT oracle, not the acceptance oracle: it produces the decimals
that the Chelis tests assert. The load-bearing checks in
`properties/indicators.ch` are analytic identities (a constant series' EMA is
that constant; a monotone-up RSI is exactly 100; ADX on a pure uptrend is
exactly 100), which cannot agree with a shared misunderstanding the way a
transcribed decimal can.

Re-run after any kernel change and compare:

    .venv/bin/python scripts/oracle_indicators.py

Warm-up positions print as `None` and correspond to `None` in the Chelis
`List[Option[f64]]` outputs at the same index.
"""

from __future__ import annotations

HIGH = [10.5, 11.5, 12.5, 11.8, 10.4, 11.6, 13.4, 14.2, 13.5, 12.6, 14.3, 15.4]
LOW = [9.6, 10.4, 11.3, 10.7, 9.5, 10.2, 11.9, 13.1, 12.4, 11.6, 12.9, 14.1]
CLOSE = [10.0, 11.0, 12.0, 11.0, 10.0, 11.0, 13.0, 14.0, 13.0, 12.0, 14.0, 15.0]
VOLUME = [100.0, 150.0, 120.0, 180.0, 90.0, 110.0, 200.0, 160.0, 140.0, 130.0, 170.0, 190.0]

Series = list[float | None]


def alpha_span(n: int) -> float:
    """pandas `ewm(span=n)`."""
    return 2.0 / (n + 1)


def alpha_wilder(n: int) -> float:
    """Wilder 1978 / TA-Lib RMA. NOT 2/(n+1) -- this is the conflation that
    ~105 measured programs made."""
    return 1.0 / n


def rolling(xs: list[float], n: int, red) -> Series:
    """Window reduction with warm-up n-1, re-summing each window."""
    out: Series = [None] * len(xs)
    for i in range(n - 1, len(xs)):
        out[i] = red(xs[i - n + 1 : i + 1])
    return out


def mean(w: list[float]) -> float:
    return sum(w) / len(w)


def var(w: list[float], ddof: int) -> float:
    m = mean(w)
    return sum((x - m) ** 2 for x in w) / (len(w) - ddof)


def ema(xs: Series, n: int, seed: str, a: float) -> Series:
    """out[i] = a*xs[i] + (1-a)*out[i-1], seeded per `seed`, starting after
    the input's own warm-up so filler cannot contaminate the recursion."""
    w = next((i for i, v in enumerate(xs) if v is not None), len(xs))
    dense = [v for v in xs[w:]]
    out: Series = [None] * len(xs)
    if seed == "first":
        start = w
        if start >= len(xs):
            return out
        prev = dense[0]
    elif seed == "sma":
        start = w + n - 1
        if start >= len(xs):
            return out
        prev = mean(dense[:n])
    else:
        raise ValueError(seed)
    out[start] = prev
    for i in range(start + 1, len(xs)):
        prev = a * xs[i] + (1 - a) * prev
        out[i] = prev
    return out


def smooth(xs: Series, n: int, kind: str) -> Series:
    if kind == "wilder":
        return ema(xs, n, "sma", alpha_wilder(n))
    if kind == "ema":
        return ema(xs, n, "first", alpha_span(n))
    if kind == "simple":
        w = next((i for i, v in enumerate(xs) if v is not None), len(xs))
        out: Series = [None] * len(xs)
        for i in range(w + n - 1, len(xs)):
            out[i] = mean(xs[i - n + 1 : i + 1])
        return out
    raise ValueError(kind)


def true_range(high: list[float], low: list[float], close: list[float]) -> Series:
    """max(h-l, |h-prev_c|, |l-prev_c|), Wilder 1978. Warm-up 1: the first
    bar has no previous close, so it is None and NOT h-l."""
    out: Series = [None]
    for i in range(1, len(high)):
        pc = close[i - 1]
        out.append(max(high[i] - low[i], abs(high[i] - pc), abs(low[i] - pc)))
    return out


def rsi(close: list[float], n: int, kind: str) -> Series:
    """100 - 100/(1+avg_gain/avg_loss), Wilder 1978. Zero average loss reads
    100, following TA-Lib's `if prevLoss == 0` guard."""
    gains: Series = [None] + [max(close[i] - close[i - 1], 0.0) for i in range(1, len(close))]
    losses: Series = [None] + [max(close[i - 1] - close[i], 0.0) for i in range(1, len(close))]
    ag = smooth(gains, n, kind)
    al = smooth(losses, n, kind)
    out: Series = []
    for g, l in zip(ag, al):
        if g is None or l is None:
            out.append(None)
        elif l == 0.0:
            out.append(100.0)
        else:
            out.append(100.0 - 100.0 / (1.0 + g / l))
    return out


def macd(close: list[float], fast: int, slow: int, signal: int, seed: str, a) -> tuple[Series, Series, Series]:
    ef = ema(close, fast, seed, a(fast))
    es = ema(close, slow, seed, a(slow))
    line: Series = [None if (x is None or y is None) else x - y for x, y in zip(ef, es)]
    sig = ema(line, signal, seed, a(signal))
    hist: Series = [None if (x is None or y is None) else x - y for x, y in zip(line, sig)]
    return line, sig, hist


def adx(high: list[float], low: list[float], close: list[float], n: int) -> tuple[Series, Series, Series]:
    """Wilder's directional movement. ADX warm-up is 2n-1 (TA-Lib)."""
    up = [None] + [high[i] - high[i - 1] for i in range(1, len(high))]
    dn = [None] + [low[i - 1] - low[i] for i in range(1, len(low))]
    pdm: Series = [None] + [max(up[i], 0.0) if up[i] > dn[i] else 0.0 for i in range(1, len(high))]
    mdm: Series = [None] + [max(dn[i], 0.0) if dn[i] > up[i] else 0.0 for i in range(1, len(high))]
    str_ = ema(true_range(high, low, close), n, "sma", alpha_wilder(n))
    spdm = ema(pdm, n, "sma", alpha_wilder(n))
    smdm = ema(mdm, n, "sma", alpha_wilder(n))

    def di(d, t):
        if d is None or t is None:
            return None
        return 0.0 if t == 0.0 else 100.0 * d / t

    pdi = [di(d, t) for d, t in zip(spdm, str_)]
    mdi = [di(d, t) for d, t in zip(smdm, str_)]
    dx: Series = []
    for p, q in zip(pdi, mdi):
        if p is None or q is None:
            dx.append(None)
        else:
            dx.append(0.0 if p + q == 0.0 else 100.0 * abs(p - q) / (p + q))
    return pdi, mdi, ema(dx, n, "sma", alpha_wilder(n))


def show(label: str, s: Series) -> None:
    body = ", ".join("None" if v is None else repr(v) for v in s)
    print(f"{label}\n    [{body}]")


def main() -> None:
    print("# Shoals.Indicators reference values (shoals#83)")
    print(f"# high   = {HIGH}")
    print(f"# low    = {LOW}")
    print(f"# close  = {CLOSE}")
    print(f"# volume = {VOLUME}\n")

    show("sma(close, 3)", rolling(CLOSE, 3, mean))
    show("ema(close, 3, SeedFirstValue, AlphaSpan)   [pandas adjust=False]", ema(CLOSE, 3, "first", alpha_span(3)))
    show("ema(close, 3, SeedSma, AlphaSpan)          [TA-Lib EMA]", ema(CLOSE, 3, "sma", alpha_span(3)))
    show("ema(close, 3, SeedFirstValue, AlphaWilder)", ema(CLOSE, 3, "first", alpha_wilder(3)))
    show("rma(close, 3) = ema(SeedSma, AlphaWilder)  [Wilder]", ema(CLOSE, 3, "sma", alpha_wilder(3)))
    show("true_range(high, low, close)", true_range(HIGH, LOW, CLOSE))
    show("atr(.., 3, SmoothWilder)", smooth(true_range(HIGH, LOW, CLOSE), 3, "wilder"))
    show("atr(.., 3, SmoothEma)", smooth(true_range(HIGH, LOW, CLOSE), 3, "ema"))
    show("atr(.., 3, SmoothSimple)", smooth(true_range(HIGH, LOW, CLOSE), 3, "simple"))
    show("rsi(close, 3, SmoothWilder)", rsi(CLOSE, 3, "wilder"))
    show("rsi(close, 3, SmoothSimple)", rsi(CLOSE, 3, "simple"))

    line, sigl, hist = macd(CLOSE, 2, 4, 3, "first", alpha_span)
    show("macd(close, 2, 4, 3, SeedFirstValue, AlphaSpan).line", line)
    show("  .signal", sigl)
    show("  .histogram", hist)

    mid = rolling(CLOSE, 4, mean)
    devp = rolling(CLOSE, 4, lambda w: var(w, 0) ** 0.5)
    devs = rolling(CLOSE, 4, lambda w: var(w, 1) ** 0.5)
    show("bollinger(close, 4, 2, DdofPopulation).lower", [None if m is None else m - 2 * d for m, d in zip(mid, devp)])
    show("  .mid", mid)
    show("  .upper", [None if m is None else m + 2 * d for m, d in zip(mid, devp)])
    show("ind_rolling_std(close, 4, DdofPopulation)", devp)
    show("ind_rolling_std(close, 4, DdofSample)", devs)

    kn, dn = 3, 3
    kv: Series = [None] * len(CLOSE)
    for i in range(kn - 1, len(CLOSE)):
        lo = min(LOW[i - kn + 1 : i + 1])
        rng = max(HIGH[i - kn + 1 : i + 1]) - lo
        kv[i] = 0.0 if rng == 0.0 else 100.0 * (CLOSE[i] - lo) / rng
    show("stochastic(.., 3, 3, SmoothSimple).k", kv)
    show("  .d", smooth(kv, dn, "simple"))

    pdi, mdi, adxv = adx(HIGH, LOW, CLOSE, 3)
    show("adx(high, low, close, 3).plus_di", pdi)
    show("  .minus_di", mdi)
    show("  .adx", adxv)

    show("donchian(high, low, 3).lower", rolling(LOW, 3, min))
    show("  .upper", rolling(HIGH, 3, max))

    cpv, cv = 0.0, 0.0
    cvwap: Series = []
    for p, v in zip(CLOSE, VOLUME):
        cpv += p * v
        cv += v
        cvwap.append(None if cv == 0.0 else cpv / cv)
    show("cumulative_vwap(close, volume)", cvwap)
    rv: Series = [None] * len(CLOSE)
    for i in range(2, len(CLOSE)):
        pw, vw = CLOSE[i - 2 : i + 1], VOLUME[i - 2 : i + 1]
        tot = sum(vw)
        rv[i] = mean(pw) if tot == 0.0 else sum(p * v for p, v in zip(pw, vw)) / tot
    show("rolling_vwap(close, volume, 3)", rv)


if __name__ == "__main__":
    main()
