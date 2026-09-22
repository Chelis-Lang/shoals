module Shoals.Tests.MarketData
import Std.Test (assert_close, assert_true, assert_eq)
import Std.Time (date)
import Shoals.MarketData (Side, Bid, Ask, Mid, Last, Quote, Bar, Snapshot, make_quote, make_bar, make_snapshot, quote_side, quote_value, md_bar_open, md_bar_high, md_bar_low, md_bar_close, md_bar_volume, snapshot_lookup)
def test_quote_construct_and_read() -> unit ! { Test } = {
  d = date(cast(2025, i64), cast(6, i64), cast(15, i64))
  q = make_quote(Bid, cast(100.5, f32), d)
  assert_close(quote_value(q), cast(100.5, f32), cast(1e-6, f32), "quote_value Bid 100.5")
}
def test_quote_side_ask() -> unit ! { Test } = {
  d = date(cast(2025, i64), cast(6, i64), cast(15, i64))
  q = make_quote(Ask, cast(100.7, f32), d)
  is_ask = match quote_side(q) with {
    | Ask => true
    | Bid => false
    | Mid => false
    | Last => false
  }
  assert_true(is_ask, "Ask side preserved")
}
def test_bar_fields() -> unit ! { Test } = {
  d = date(cast(2025, i64), cast(6, i64), cast(15, i64))
  b = make_bar(d, cast(100.0, f32), cast(101.0, f32), cast(99.5, f32), cast(100.5, f32), cast(1000.0, f32))
  assert_close(md_bar_open(b), cast(100.0, f32), cast(1e-6, f32), "bar open")
}
def test_bar_high_low_volume() -> unit ! { Test } = {
  d = date(cast(2025, i64), cast(6, i64), cast(15, i64))
  b = make_bar(d, cast(100.0, f32), cast(101.0, f32), cast(99.5, f32), cast(100.5, f32), cast(1000.0, f32))
  _ = assert_close(md_bar_high(b), cast(101.0, f32), cast(1e-6, f32), "bar high")
  _ = assert_close(md_bar_low(b), cast(99.5, f32), cast(1e-6, f32), "bar low")
  assert_close(md_bar_volume(b), cast(1000.0, f32), cast(1e-6, f32), "bar volume")
}
def test_snapshot_lookup_present() -> unit ! { Test } = {
  d = date(cast(2025, i64), cast(6, i64), cast(15, i64))
  q_spx = make_quote(Mid, cast(5000.0, f32), d)
  s = make_snapshot(d, [("SPX", q_spx)])
  found = match snapshot_lookup(s, "SPX") with {
    | Some(_) => true
    | None => false
  }
  assert_true(found, "snapshot lookup finds SPX")
}
def test_snapshot_lookup_absent() -> unit ! { Test } = {
  d = date(cast(2025, i64), cast(6, i64), cast(15, i64))
  s = make_snapshot(d, [])
  absent = match snapshot_lookup(s, "ZZZZ") with {
    | None => true
    | Some(_) => false
  }
  assert_true(absent, "snapshot lookup returns None for absent key")
}
def test_quote_side_last() -> unit ! { Test } = {
  d = date(cast(2025, i64), cast(6, i64), cast(15, i64))
  q = make_quote(Last, cast(99.9, f32), d)
  is_last = match quote_side(q) with {
    | Last => true
    | Bid => false
    | Ask => false
    | Mid => false
  }
  assert_true(is_last, "Last side preserved")
}
def test_quote_side_mid() -> unit ! { Test } = {
  d = date(cast(2025, i64), cast(6, i64), cast(15, i64))
  q = make_quote(Mid, cast(100.6, f32), d)
  is_mid = match quote_side(q) with {
    | Mid => true
    | Bid => false
    | Ask => false
    | Last => false
  }
  assert_true(is_mid, "Mid side preserved")
}
def test_snapshot_lookup_finds_second_entry() -> unit ! { Test } = {
  d = date(cast(2025, i64), cast(6, i64), cast(15, i64))
  q_aapl = make_quote(Bid, cast(150.0, f32), d)
  q_tsla = make_quote(Bid, cast(250.0, f32), d)
  q_msft = make_quote(Bid, cast(350.0, f32), d)
  s = make_snapshot(d, [("AAPL", q_aapl), ("TSLA", q_tsla), ("MSFT", q_msft)])
  found_value = match snapshot_lookup(s, "MSFT") with {
    | Some(q) => quote_value(q)
    | None => cast(-1.0, f32)
  }
  assert_close(found_value, cast(350.0, f32), cast(1e-6, f32), "snapshot lookup finds MSFT in slot 3")
}
