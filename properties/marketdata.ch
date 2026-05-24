module Shoals.Properties.MarketData
import Std.Time (Date)
import Shoals.MarketData (Side, Quote, Bar, Snapshot, quote, bar, quote_value, bar_high, bar_low, bar_open, bar_close, snapshot, snapshot_lookup)
def quote_round_trip(side: Side, value: f32, d: Date) -> bool = {
  q = quote(side, value, d)
  eq(quote_value(q), value)
}
def bar_high_gte_low(b: Bar) -> bool = gte(bar_high(b), bar_low(b))
def bar_close_in_high_low_range(b: Bar) -> bool = and(lte(bar_close(b), bar_high(b)), gte(bar_close(b), bar_low(b)))
def bar_open_in_high_low_range(b: Bar) -> bool = and(lte(bar_open(b), bar_high(b)), gte(bar_open(b), bar_low(b)))
def snapshot_empty_has_no_quote(d: Date, key: string) -> bool = {
  s = snapshot(d, [])
  match snapshot_lookup(s, key) with {
    | None => true
    | Some(_) => false
  }
}
