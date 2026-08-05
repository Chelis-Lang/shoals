module Shoals.Properties.MarketData
import Std.Time (Date)
import Shoals.MarketData (Side, Quote, Bar, Snapshot, make_quote, make_bar, quote_value, md_bar_high, md_bar_low, md_bar_open, md_bar_close, make_snapshot, snapshot_lookup)
def quote_round_trip(side: Side, value: f32, d: Date) -> bool = {
  q = make_quote(side, value, d)
  eq(quote_value(q), value)
}
def md_bar_high_gte_low(b: Bar) -> bool = gte(md_bar_high(b), md_bar_low(b))
def md_bar_close_in_high_low_range(b: Bar) -> bool = and(lte(md_bar_close(b), md_bar_high(b)), gte(md_bar_close(b), md_bar_low(b)))
def md_bar_open_in_high_low_range(b: Bar) -> bool = and(lte(md_bar_open(b), md_bar_high(b)), gte(md_bar_open(b), md_bar_low(b)))
def snapshot_empty_has_no_quote(d: Date, key: string) -> bool = {
  s = make_snapshot(d, [])
  match snapshot_lookup(s, key) with {
    | None => true
    | Some(_) => false
  }
}
