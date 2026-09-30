# Order book

Module: `Shoals.Orderbook`.

This module is a limit order book held as two price-priority sorted lists,
one for bids and one for asks. It supports adding orders, reading the best
bid and ask, the bid-ask spread, the volume-weighted average price, and the
total quantity on each side. An empty side returns a sentinel NaN price.

## Types

```chelis
type Order =
  | Order { price: f32, qty: f32 }

type OrderBook =
  | OrderBook { bids: List[Order], asks: List[Order] }

def empty_book() -> OrderBook
```

An `Order` is a price and a quantity. An `OrderBook` holds a bid list sorted
by descending price and an ask list sorted by ascending price, so the best
order on each side is always at the head. `empty_book` returns a book with
no orders.

## Adding orders

```chelis
def add_bid(book: OrderBook, price: f32, qty: f32) -> OrderBook
def add_ask(book: OrderBook, price: f32, qty: f32) -> OrderBook
```

`add_bid` inserts a bid into the descending-price list, and `add_ask`
inserts an ask into the ascending-price list, each preserving the sort. Both
return a new book. From `tests/orderbook.ch`:

```chelis
book = empty_book()
b1 = add_bid(book, cast(99.0, f32), cast(10.0, f32))
b2 = add_bid(b1, cast(100.0, f32), cast(5.0, f32))
b3 = add_bid(b2, cast(98.0, f32), cast(3.0, f32))
```

## Reading the book

```chelis
def best_bid(book: OrderBook) -> Order
def best_ask(book: OrderBook) -> Order
def bid_ask_spread(book: OrderBook) -> f32
def vwap(book: OrderBook) -> f32
def total_bid_qty(book: OrderBook) -> f32
def total_ask_qty(book: OrderBook) -> f32
```

`best_bid` returns the highest bid and `best_ask` the lowest ask. On an
empty side they return an order with a NaN price and zero quantity, so a
caller can test for an empty book by checking whether the best price equals
itself. `bid_ask_spread` is the best ask price minus the best bid price.
`vwap` is the volume-weighted average price across all orders on both sides;
it returns NaN when the total quantity is zero. The module sorts supplied
orders but does not match them or validate price and quantity.
`total_bid_qty` and `total_ask_qty` sum the quantities on each side.

From `tests/orderbook.ch`, the best bid of the three-order book above is
`100`, and a one-tick spread reads as expected:

```chelis
best = best_bid(b3)  // best price == 100.0

book = empty_book()
b = add_bid(book, cast(100.0, f32), cast(5.0, f32))
ba = add_ask(b, cast(101.0, f32), cast(5.0, f32))
spread = bid_ask_spread(ba)  // spread == 1.0
```

A two-level book has a volume-weighted average price across both sides:

```chelis
book = empty_book()
b = add_bid(book, cast(100.0, f32), cast(10.0, f32))
ba = add_ask(b, cast(101.0, f32), cast(5.0, f32))
v = vwap(ba)  // (100*10 + 101*5) / 15
```
