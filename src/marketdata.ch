module Shoals.MarketData
import Std.Time (Date)
export (Side, Quote, Bar, Snapshot, quote, bar, snapshot, quote_side, quote_value, bar_open, bar_high, bar_low, bar_close, bar_volume, snapshot_lookup)
type Side =
  | Bid
  | Ask
  | Mid
  | Last
type Quote =
  | Quote { side: Side, value: f32, asof: Date }
type Bar =
  | Bar { asof: Date, open: f32, high: f32, low: f32, close: f32, volume: f32 }
type Snapshot =
  | Snapshot { asof: Date, quotes: List[(string, Quote)] }
def quote(side: Side, value: f32, asof: Date) -> Quote = Quote { side: side, value: value, asof: asof }
def bar(asof: Date, open: f32, high: f32, low: f32, close: f32, volume: f32) -> Bar = Bar { asof: asof, open: open, high: high, low: low, close: close, volume: volume }
def snapshot(asof: Date, quotes: List[(string, Quote)]) -> Snapshot = Snapshot { asof: asof, quotes: quotes }
def quote_side(q: Quote) -> Side = {
  match q with {
    | Quote { side: s, value: _, asof: _ } => s
  }
}
def quote_value(q: Quote) -> f32 = {
  match q with {
    | Quote { side: _, value: v, asof: _ } => v
  }
}
def bar_open(b: Bar) -> f32 = b.open
def bar_high(b: Bar) -> f32 = b.high
def bar_low(b: Bar) -> f32 = b.low
def bar_close(b: Bar) -> f32 = b.close
def bar_volume(b: Bar) -> f32 = b.volume
def snapshot_lookup(s: Snapshot, key: string) -> Option[Quote] = {
  match s with {
    | Snapshot { asof: _, quotes: qs } => fold(fn (acc: Option[Quote], entry: (string, Quote)) -> match acc with {
    | Some(_) => acc
    | None => if eq(entry.0, key) then Some(entry.1) else None
  }, None, qs)
  }
}
