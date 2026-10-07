# Working with tensors and keys

Use Shoals as a Reef dependency, as described in
[Getting started](getting-started.md).

## Types and tensors

Chelis makes element types explicit. Most finance amounts in Shoals are `f32`; the pricing module also exports `f64` kernels. Indices, lengths, and seeds are `i64`. Use explicit casts for numeric literals, such as `cast(100.0, f32)` and `cast(3, i64)`.

A tensor can be built from a list:

```chelis
spots = to_tensor([cast(80.0, f32), cast(100.0, f32), cast(120.0, f32)])
-- tensor(shape=[3], data=[80.0, 100.0, 120.0]): a tensor[3, f32]
```

`call_prices(spots, ...)` then returns a `tensor[3, f32]` of the same
length, one price per spot (see [Pricing](pricing.md)).

A Monte Carlo function uses the length of a template tensor to set its path count:

```chelis
template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(20000, i64))))
```

`to_list` exposes a tensor's entries and `index` reads one. A call with a `&tensor` parameter borrows its tensor argument. Passing a borrowed `&tensor` to a function that takes ownership requires `copy(x)` to supply a fresh owner. A signature with `[n]` preserves the caller's tensor length in its result.

## Keyed randomness

Simulation functions take an explicit `key`. `key_from_seed(seed: i64) -> key`
and `split_key(k: key) -> (key, key)` are Chelis builtins, available
without an import. Derive a key from an `i64` seed when you want a
reproducible draw:

```chelis
mc_px = mc_call_price(key_from_seed(42i64), template, cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32))
-- 10.531636 with the 20,000-path template above; the closed form is 10.450583
```

Import `Shoals.Pricing.mc_call_price` in your module. Deriving a new key
from the same seed and using the same inputs gives the same result. Split a key
when a computation needs independent draws. Monte Carlo accuracy is statistical
and depends on the number of paths.

## Records and purity

Shoals uses algebraic data types with named fields, such as
`Order { price, qty }`. For opaque types such as `YieldCurve`, use the
public constructors and accessors described in [Yield curves](curves.md).
Simulation
functions are pure calls whose results depend on their explicit keys and
other inputs.
