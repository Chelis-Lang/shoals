# `min`/`max` type-check under `vmap` and then fail at eval as a missing input

**Filing condition:** file against `Chelis-Lang/chelis` when someone is in a
position to act on it. Parked rather than filed because the narrowing it
describes is already disclosed in `docs/UPSTREAM_BUGS.md` and the workaround
(clamp with `if`) is in place, so no shoals work is blocked on the answer.

## The barrier

`min` and `max` evaluate correctly outside a transform, but under `vmap` the
host runtime treats the primitive's own name as a required symbolic input.

```chelis
module Shoals.Minprobe
def clamped(x: f64) -> f64 = min(x, cast(0.5, f64))
def rowwise(t: tensor[3, f64]) -> tensor[3, f64] = {
  s = tensor_to_scalar(sum(t, cast(0, int32)))
  expand(scalar_to_tensor(clamped(s)), cast(0, int32), cast(3, int64))
}
def batched(b: tensor[2, 3, f64]) -> tensor[2, 3, f64] = vmap(rowwise)(b)
inbatch = to_tensor([[cast(1.0, f64), cast(0.0, f64), cast(0.0, f64)], [cast(0.1, f64), cast(0.0, f64), cast(0.0, f64)]])
probe = to_list(sum(batched(inbatch), cast(1, int32)))
```

At chelis 0.18.6:

```text
chelis check src/minprobe.ch   ->  "errors": []
chelis eval  src/minprobe.ch   ->  error: host runtime `vmap` evaluation failed:
                                   missing required input `min`
```

`check` passing and `eval` failing is the sharp edge: the program is accepted
by the type system and fails only when run.

The same defs evaluate correctly outside `vmap` — `min(9.0, 0.5)` returns
`0.5` and `max(0.1, 0.5)` returns `0.5` — so this is specific to the transform
lowering, not to `min`/`max` themselves.

## Not chelis#377

`chelis#377` reports the same *diagnostic* ("missing required input") for
`grad`/`vmap` over a def **capturing a top-level binding**. The reproducer
above captures nothing: `clamped` takes its argument and a literal. The shared
error string looks like one failure mode — an unrecognized name becoming a
required input — reached by two different routes.

## What it costs downstream

`Shoals.Pricing`'s `erf64` cores must be total under `vmap`, because
chelis#1464 makes a masked select evaluate untaken arms. Clamping with `min`
and `max` would make every core total over all of f64; clamping with `if`
only reaches the FINITE domain, since an `if`'s untaken arm is the operand and
`0 * inf = NaN`. The `±inf` residual documented in `docs/UPSTREAM_BUGS.md` is
exactly the gap this issue leaves open.
