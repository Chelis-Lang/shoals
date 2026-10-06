# Working with tensors and keys

The module chapters show short excerpts from Shoals source and tests. They are call examples, not standalone files. [Getting started](getting-started.md) gives a complete command to run a source test.

## Types and tensors

Chelis makes element types explicit. Most finance amounts in Shoals are `f32`; the pricing module also exports `f64` kernels. Indices, lengths, and seeds are `i64`. Existing Shoals tests write `cast(100.0, f32)` and `cast(3, i64)`.

A tensor can be built from a list:

```chelis
spots = to_tensor([cast(80.0, f32), cast(100.0, f32), cast(120.0, f32)])
```

A Monte Carlo function uses the length of a template tensor to set its path count:

```chelis
template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(20000, i64))))
```

`to_list` exposes a tensor's entries and `index` reads one. A call with a `&tensor` parameter borrows its tensor argument. Passing a borrowed `&tensor` to a function that takes ownership requires `copy(x)` to supply a fresh owner. A signature with `[n]` preserves the caller's tensor length in its result.

## Keyed randomness

Simulation functions take an explicit `key`. Derive one from an `i64` seed
when you want a reproducible draw:

```chelis
mc_px = mc_call_price(key_from_seed(42i64), template, cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32))
```

The complete test imports `Shoals.Pricing.mc_call_price`. Deriving a new key
from the same seed and using the same inputs gives the same result. Split a key
when a computation needs independent draws. Monte Carlo accuracy is statistical
and depends on the number of paths.

## Records and purity

Shoals uses algebraic data types with named fields, such as
`Order { price, qty }` and `YieldCurve { kind, times, rates }`. Public
accessors often let you read fields without a pattern match. Simulation
functions are pure calls whose results depend on their explicit keys and
other inputs.
