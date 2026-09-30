# Working with tensors and effects

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

`to_list` exposes a tensor's entries and `index` reads one. Use `copy` when a tensor is consumed in one call and needed again. A signature with `[n]` preserves the caller's tensor length in its result.

## Seeded randomness

Simulation functions declare `! { Random }`. Handle that effect at the call site with an `i64` seed:

```chelis
mc_px = with seed(42i64) {
  mc_call_price(template, cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32))
}
```

The complete test imports `Shoals.Pricing.mc_call_price`. A repeated call with the same seed and inputs gives the same result. Monte Carlo accuracy is statistical and depends on the number of paths.

## Records and effects

Shoals uses algebraic data types with named fields, such as `Order { price, qty }` and `YieldCurve { kind, times, rates }`. Public accessors often let you read fields without a pattern match. A signature ending in `! { Random }` performs seeded random draws; a signature without an effect clause is pure.
