module Shoals.Tests.Orderbook
import Std.Test (assert_close, assert_eq_int)
import Shoals.Orderbook (Order, OrderBook, empty_book, add_bid, add_ask, best_bid, best_ask, bid_ask_spread, vwap, total_bid_qty, total_ask_qty)
def order_price_of(o: Order) -> f32 =
  match o with {
    | Order { price: p, qty: _ } => p
  }
def order_qty_of(o: Order) -> f32 =
  match o with {
    | Order { price: _, qty: q } => q
  }
def test_best_bid_highest() -> unit ! { Test } = {
  book = empty_book()
  b1 = add_bid(book, cast(99.0, f32), cast(10.0, f32))
  b2 = add_bid(b1, cast(100.0, f32), cast(5.0, f32))
  b3 = add_bid(b2, cast(98.0, f32), cast(3.0, f32))
  best = best_bid(b3)
  assert_close(order_price_of(best), cast(100.0, f32), cast(1e-6, f32), "best_bid == 100")
}
def test_best_ask_lowest() -> unit ! { Test } = {
  book = empty_book()
  a1 = add_ask(book, cast(102.0, f32), cast(7.0, f32))
  a2 = add_ask(a1, cast(101.0, f32), cast(4.0, f32))
  a3 = add_ask(a2, cast(103.0, f32), cast(2.0, f32))
  best = best_ask(a3)
  assert_close(order_price_of(best), cast(101.0, f32), cast(1e-6, f32), "best_ask == 101")
}
def test_bid_ask_spread() -> unit ! { Test } = {
  book = empty_book()
  b = add_bid(book, cast(100.0, f32), cast(5.0, f32))
  ba = add_ask(b, cast(101.0, f32), cast(5.0, f32))
  spread = bid_ask_spread(ba)
  assert_close(spread, cast(1.0, f32), cast(1e-6, f32), "spread == 1.0")
}
def test_vwap_two_levels() -> unit ! { Test } = {
  book = empty_book()
  b = add_bid(book, cast(100.0, f32), cast(10.0, f32))
  ba = add_ask(b, cast(101.0, f32), cast(5.0, f32))
  v = vwap(ba)
  expected = div(add(mul(cast(100.0, f32), cast(10.0, f32)), mul(cast(101.0, f32), cast(5.0, f32))), cast(15.0, f32))
  assert_close(v, expected, cast(0.00001, f32), "VWAP == 100.333")
}
def test_total_quantities() -> unit ! { Test } = {
  book = empty_book()
  b1 = add_bid(book, cast(100.0, f32), cast(10.0, f32))
  b2 = add_bid(b1, cast(99.0, f32), cast(5.0, f32))
  ba = add_ask(b2, cast(101.0, f32), cast(7.0, f32))
  bq = total_bid_qty(ba)
  aq = total_ask_qty(ba)
  _ = assert_close(bq, cast(15.0, f32), cast(1e-6, f32), "bid qty == 15")
  assert_close(aq, cast(7.0, f32), cast(1e-6, f32), "ask qty == 7")
}
def test_best_bid_empty_is_nan() -> unit ! { Test } = {
  book = empty_book()
  best = best_bid(book)
  p = order_price_of(best)
  is_nan = neq(p, p)
  assert_close(if is_nan then cast(1.0, f32) else cast(0.0, f32), cast(1.0, f32), cast(0.001, f32), "empty best_bid price is NaN")
}
