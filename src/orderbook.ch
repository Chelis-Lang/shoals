module Shoals.Orderbook
export (Order, OrderBook, empty_book, add_bid, add_ask, best_bid, best_ask, bid_ask_spread, vwap, total_bid_qty, total_ask_qty)
type Order =
  | Order { price: f32, qty: f32 }
type OrderBook =
  | OrderBook { bids: List[Order], asks: List[Order] }
def empty_book() -> OrderBook = OrderBook { bids: [], asks: [] }
def order_price(o: Order) -> f32 = {
  match o with {
    | Order { price: p, qty: _ } => p
  }
}
def order_qty(o: Order) -> f32 = {
  match o with {
    | Order { price: _, qty: q } => q
  }
}
def append_list(xs: List[Order], ys: List[Order]) -> List[Order] = { fold(fn (acc: List[Order], y: Order) -> append(acc, y), xs, ys) }
def insert_desc(orders: List[Order], new_order: Order) -> List[Order] = {
  n_p = order_price(new_order)
  before = fold(fn (acc: List[Order], o: Order) -> { if gt(order_price(o), n_p) then append(acc, o) else acc }, [], orders)
  after = fold(fn (acc: List[Order], o: Order) -> { if lte(order_price(o), n_p) then append(acc, o) else acc }, [], orders)
  append_list(append(before, new_order), after)
}
def insert_asc(orders: List[Order], new_order: Order) -> List[Order] = {
  n_p = order_price(new_order)
  before = fold(fn (acc: List[Order], o: Order) -> { if lt(order_price(o), n_p) then append(acc, o) else acc }, [], orders)
  after = fold(fn (acc: List[Order], o: Order) -> { if gte(order_price(o), n_p) then append(acc, o) else acc }, [], orders)
  append_list(append(before, new_order), after)
}
def add_bid(book: OrderBook, price: f32, qty: f32) -> OrderBook = {
  match book with {
    | OrderBook { bids: bs, asks: as_ } => { OrderBook { bids: insert_desc(bs, Order { price: price, qty: qty }), asks: as_ } }
  }
}
def add_ask(book: OrderBook, price: f32, qty: f32) -> OrderBook = {
  match book with {
    | OrderBook { bids: bs, asks: as_ } => { OrderBook { bids: bs, asks: insert_asc(as_, Order { price: price, qty: qty }) } }
  }
}
def best_bid(book: OrderBook) -> Order = {
  match book with {
    | OrderBook { bids: bs, asks: _ } => if eq(len(bs), cast(0, int64)) then Order { price: div(cast(0.0, f32), cast(0.0, f32)), qty: cast(0.0, f32) } else index(bs, cast(0, int64))
  }
}
def best_ask(book: OrderBook) -> Order = {
  match book with {
    | OrderBook { bids: _, asks: as_ } => if eq(len(as_), cast(0, int64)) then Order { price: div(cast(0.0, f32), cast(0.0, f32)), qty: cast(0.0, f32) } else index(as_, cast(0, int64))
  }
}
def bid_ask_spread(book: OrderBook) -> f32 = {
  ba = best_ask(book)
  bb = best_bid(book)
  sub(order_price(ba), order_price(bb))
}
def vwap(book: OrderBook) -> f32 = {
  match book with {
    | OrderBook { bids: bs, asks: as_ } => {
    all_orders = append_list(bs, as_)
    pq = fold(fn (acc: (f32, f32), o: Order) -> {
      p = order_price(o)
      q = order_qty(o)
      (add(acc.0, mul(p, q)), add(acc.1, q))
    }, (cast(0.0, f32), cast(0.0, f32)), all_orders)
    if eq(pq.1, cast(0.0, f32)) then div(cast(0.0, f32), cast(0.0, f32)) else div(pq.0, pq.1)
  }
  }
}
def total_bid_qty(book: OrderBook) -> f32 = {
  match book with {
    | OrderBook { bids: bs, asks: _ } => fold(fn (acc: f32, o: Order) -> add(acc, order_qty(o)), cast(0.0, f32), bs)
  }
}
def total_ask_qty(book: OrderBook) -> f32 = {
  match book with {
    | OrderBook { bids: _, asks: as_ } => fold(fn (acc: f32, o: Order) -> add(acc, order_qty(o)), cast(0.0, f32), as_)
  }
}
