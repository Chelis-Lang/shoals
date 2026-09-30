# Working with tensors and keys

The Shoals examples in this book lean on a small number of Chelis idioms.
This chapter collects them so the module chapters can stay focused on
finance.

## Scalars are explicitly typed

Numeric literals are cast to their element type. A 32-bit float literal is
written `cast(100.0, f32)`, and an integer is written `cast(3, i64)`.
Every Shoals price, rate, and volatility argument is `f32`. Indices and
counts are `i64`.

## Building tensors

A tensor is built from a list with `to_tensor`:

```chelis
spots = to_tensor([cast(80.0, f32), cast(100.0, f32), cast(120.0, f32)])
```

To build a tensor of a fixed length programmatically, map over a range. A
template of twenty thousand zeros, used to size a Monte Carlo run, is:

```chelis
template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(20000, i64))))
```

A tensor is turned back into a list with `to_list`, and an element is read
with `index`:

```chelis
prices = to_list(call_prices(spots, cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32)))
first = index(prices, cast(0, i64))
```

Tensors that are consumed more than once are duplicated with `copy`, so a
value can be passed to one call and reused afterward. Several Shoals
signatures are generic over a tensor length, written `[n]`, which the
caller fixes by the tensor it passes.

## Explicit random keys

Functions that draw random numbers take an explicit affine `key` as their
first argument. Construct one from an integer seed for repeatable Monte
Carlo results, and split it before making two distinct draws:

```chelis
px = mc_call_price(key_from_seed(42i64), template, cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32))
```

Two calls with separately constructed keys from the same seed produce
bit-identical results. A key is consumed by a draw; `split_key` creates
distinct child keys for multiple draws.

## Records and pattern matching

Shoals defines record-style algebraic types, for example the order
`Order { price, qty }` and the yield curve `YieldCurve { kind, times, rates }`.
You read a field either with a dotted accessor where the language supports
it (`bar.high`) or by matching:

```chelis
match book with {
  | OrderBook { bids: bs, asks: as_ } => ...
}
```

The module chapters show the accessor functions each type ships, so you
rarely need to match by hand.

## Keys and result types in signatures

Throughout this book a signature like

```chelis
def mc_call_price[n](rng_key: key, template: tensor[n, f32], s0: f32, k: f32, r: f32, sigma: f32, t: f32) -> f32
```

reads as: generic over length `n`, consumes a key, takes a length-`n`
template tensor and five `f32` arguments, and returns an `f32`. A caller
must supply a fresh key or an unused child from `split_key`.
