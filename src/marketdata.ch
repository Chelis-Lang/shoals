module Shoals.MarketData
import Std.Time (Date)
export (Side, Quote, Bar, Snapshot, make_quote, make_bar, make_snapshot, quote_side, quote_value, md_bar_open, md_bar_high, md_bar_low, md_bar_close, md_bar_volume, snapshot_lookup)
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
def make_quote(side: Side, value: f32, asof: Date) -> Quote = Quote { side, value, asof }
def make_bar(asof: Date, open: f32, high: f32, low: f32, close: f32, volume: f32) -> Bar = Bar { asof, open, high, low, close, volume }
def make_snapshot(asof: Date, quotes: List[(string, Quote)]) -> Snapshot = Snapshot { asof, quotes }
def quote_side(q: Quote) -> Side =
  match q with {
    | Quote { side: s, value: _, asof: _ } => s
  }
def quote_value(q: Quote) -> f32 =
  match q with {
    | Quote { side: _, value: v, asof: _ } => v
  }
def md_bar_open(b: Bar) -> f32 = b.open
def md_bar_high(b: Bar) -> f32 = b.high
def md_bar_low(b: Bar) -> f32 = b.low
def md_bar_close(b: Bar) -> f32 = b.close
def md_bar_volume(b: Bar) -> f32 = b.volume
def snapshot_lookup(s: Snapshot, key: string) -> Option[Quote] =
  match s with {
    | Snapshot { asof: _, quotes: qs } => fold(fn (acc: Option[Quote], entry: (string, Quote)) -> match acc with {
    | Some(_) => acc
    | None => if eq(entry.0, key) then Some(entry.1) else None
  }, None, qs)
  }
