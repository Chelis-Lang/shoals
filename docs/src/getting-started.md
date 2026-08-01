# Getting started

Shoals is a reef package. It depends on the Chelis compiler and on the
upstream libraries it builds upon: `chelis-std` (the standard library),
`nautilus` (distributions, special functions, statistics, interpolation),
and `coral` (the dataframe runtime). The dependency wiring is declared in
`reef.toml` at the repository root.

## Building

Shoals 0.24.5 targets Chelis 0.17.5, Nautilus 0.7.37, and Coral 0.7.34.
All three dependencies are published; their release sidecars authenticate the
exact artifacts used by the release gate. Do not use source builds or local
dependency checkouts as release evidence.

The package gate is owned by the compiler:

```sh
# resolve the manifest and lower the package
chelis reef build
```

The in-tree test suite exercises the finance invariants against the
reference oracles:

```sh
# run the runtime test suite
chelis test tests/ --timeout 1200 --jobs auto

# serial run, useful when debugging a single failure
chelis test tests/ --timeout 1200 --jobs 1
```

The formatter checks one file per invocation:

```sh
chelis fmt --check src/pricing.ch
```

The local acceptance gate at `scripts/run_local_gate.py` runs the formatter
check over the `.ch` sources, the linter, `chelis reef build`, and the
runtime suites. Continuous integration runs the same default steps but leaves
the heavy `tests-manual/` suite to the nightly/manual lanes.

## A first price

Black-Scholes is the smallest useful call. `bs_call_scalar` takes spot,
strike, the risk-free rate, volatility, and time to maturity, all `f32`,
and returns the call price. This call, drawn from `tests/pricing.ch`,
prices a one-year at-the-money call:

```chelis
import Shoals.Pricing (bs_call_scalar)

def example() -> f32 = bs_call_scalar(
  cast(100.0, f32),
  cast(100.0, f32),
  cast(0.05, f32),
  cast(0.2, f32),
  cast(1.0, f32)
)
```

The result is approximately `10.4506`. The companion put,
`bs_put_scalar`, takes the same arguments and returns approximately
`5.5735` for the same inputs.

## Pricing a vector of spots

Most pricers have a vectorized form that maps over a tensor of spots. The
following example, from `tests/pricing.ch`, prices a call at three spot
levels at once:

```chelis
import Shoals.Pricing (call_prices)

def example() -> tensor[3, f32] = {
  spots = to_tensor([cast(80.0, f32), cast(100.0, f32), cast(120.0, f32)])
  call_prices(spots, cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32))
}
```

The three prices are approximately `1.8594`, `10.4506`, and `26.169`.

## A Monte Carlo price

The Monte Carlo engine carries the `Random` effect, so it runs inside a
`with seed(...)` block that fixes the random stream. The number of paths is
the length of a template tensor you pass in. This example, from
`tests/pricing.ch`, prices the same call with twenty thousand paths:

```chelis
import Shoals.Pricing (mc_call_price)

def example() -> f32 ! { Random } = {
  template = to_tensor(map(fn (i: int64) -> cast(0.0, f32), range(cast(0, int64), cast(20000, int64))))
  with seed(42) {
    mc_call_price(template, cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32))
  }
}
```

The Monte Carlo estimate converges to the closed-form price as the path
count grows. The next chapter explains the tensor and effect idioms these
examples use.
