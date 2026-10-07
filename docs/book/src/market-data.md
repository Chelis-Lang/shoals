# Market data

Module: `Shoals.MarketData`.

This module provides record types for a single quote, an OHLCV bar, and a
named snapshot of quotes, with constructors, field accessors, and a
linear-scan lookup on a snapshot. Dates come from `Std.Datetime`.

## Quote

```chelis
type Side =
  | Bid
  | Ask
  | Mid
  | Last

type Quote =
  | Quote { side: Side, value: f32, asof: Date }

def make_quote(side: Side, value: f32, asof: Date) -> Quote
def quote_side(q: Quote) -> Side
def quote_value(q: Quote) -> f32
```

A `Quote` carries a side (bid, ask, mid, or last), a value, and an as-of
date. `make_quote` constructs one; `quote_side` and `quote_value` read the side
and value back. For example:

```chelis
d = date(cast(2025, i64), cast(6, i64), cast(15, i64))
q = make_quote(Bid, cast(100.5, f32), d)
v = quote_value(q)  -- v == 100.5
```

## Bar

```chelis
type Bar =
  | Bar { asof: Date, open: f32, high: f32, low: f32, close: f32, volume: f32 }

def make_bar(asof: Date, open: f32, high: f32, low: f32, close: f32, volume: f32) -> Bar
def md_bar_open(b: Bar) -> f32
def md_bar_high(b: Bar) -> f32
def md_bar_low(b: Bar) -> f32
def md_bar_close(b: Bar) -> f32
def md_bar_volume(b: Bar) -> f32
```

A `Bar` is an open-high-low-close-volume record with an as-of date. `make_bar`
constructs one; the `md_bar_*` accessors read each field. For example:

```chelis
b = make_bar(d, cast(100.0, f32), cast(101.0, f32), cast(99.5, f32), cast(100.5, f32), cast(1000.0, f32))
h = md_bar_high(b)  -- h == 101.0
```

## Snapshot

```chelis
type Snapshot =
  | Snapshot { asof: Date, quotes: List[(string, Quote)] }

def make_snapshot(asof: Date, quotes: List[(string, Quote)]) -> Snapshot
def snapshot_lookup(s: Snapshot, key: string) -> Option[Quote]
```

A `Snapshot` is an as-of date and a list of keyed quotes. `make_snapshot`
constructs one from a list of `(key, quote)` pairs without checking for
repeated keys. `snapshot_lookup` scans the list in order and returns
`Some(quote)` for the first pair whose key matches, or `None` if no key
matches; a later pair with the same key is never returned. Key comparison
is exact and case-sensitive.
For example:

```chelis
s = make_snapshot(d, [("SPX", make_quote(Mid, cast(5000.0, f32), d))])
found = match snapshot_lookup(s, "SPX") with {
  | Some(_) => true
  | None => false
}  -- found == true
```
