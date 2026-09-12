# Pricing

Module: `Shoals.Pricing`.

This module provides the Black-Scholes call and put in closed form,
vectorized price tensors over a set of spots, gradient-derived sensitivity
vectors, and a Monte Carlo call pricer that carries the `Random` effect.
The standard normal cumulative distribution is computed by this module's own
`n_cdf64`, because `Nautilus.Special` is f32-only and an f64 grad path cannot
reach its `erfc`. `docs/CHELIS_SURFACE.md` states which approximation `erf64`
evaluates and its measured accuracy.

## Closed-form scalars

```chelis
def bs_call_scalar(s: f32, k: f32, r: f32, sigma: f32, t: f32) -> f32
def bs_put_scalar(s: f32, k: f32, r: f32, sigma: f32, t: f32) -> f32
```

`bs_call_scalar` and `bs_put_scalar` price a European call and put on a
non-dividend-paying underlying. The arguments are spot `s`, strike `k`,
the continuously compounded risk-free rate `r`, volatility `sigma`, and
time to maturity `t` in years.

From `tests/pricing.ch`, a one-year at-the-money call and put:

```chelis
px = bs_call_scalar(cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32))
// px is approximately 10.4506

pp = bs_put_scalar(cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32))
// pp is approximately 5.5735
```

These two satisfy put-call parity: `c - p == s - k * exp(-r * t)`.

## Content-addressed WireDag entry

`bs_call_wire_f64` is the pure-tensor entry for bounded-domain verification
consumers such as Beacon. It accepts same-length f64 tensors for the five market
inputs and for the A-S constants. The constants are explicit point-valued
inputs because host-side broadcasting (`vmap`, `shape`, scalar conversion, or
list mapping) would erase the compiler-owned WireDag root. Its arithmetic and
small-x/sign branches mirror `bs_call_f64`; representative deep-OTM, ATM, and
deep-ITM rows are checked against that scalar pricer with a scale-aware bound.
The executable comparison uses `1e-5 + 1e-8 * abs(expected)`, retaining the
absolute floor near zero while remaining scale-aware for large prices, and
covers both three-row and shape-one inputs.

`python3 scripts/validate_bs_wire_root.py` enforces the `reef.toml` Chelis pin,
compares raw artifacts from independent cold Tide processes, and validates
schema 3, graph integrity, the named f64 tensor root, its exact reachable input
set, its compiler-reported operation closure, and the reviewed raw SHA/root/node
commitment. Any compiler or source change must deliberately refresh that
commitment instead of accepting a merely plausible redirected graph. The result
is a content-addressable compiler artifact; it does not itself claim a global
Black-Scholes theorem.

## Vectorized prices

```chelis
def call_prices[n](spots: tensor[n, f32], k: f32, r: f32, sigma: f32, t: f32) -> tensor[n, f32]
def put_prices[n](spots: tensor[n, f32], k: f32, r: f32, sigma: f32, t: f32) -> tensor[n, f32]
def call_total[n](spots: tensor[n, f32], k: f32, r: f32, sigma: f32, t: f32) -> f32
def put_total[n](spots: tensor[n, f32], k: f32, r: f32, sigma: f32, t: f32) -> f32
```

`call_prices` and `put_prices` map the scalar pricer over a tensor of
spots, holding strike, rate, volatility, and maturity fixed. `call_total`
and `put_total` sum the resulting prices to a single `f32`.

From `tests/pricing.ch`:

```chelis
spots = to_tensor([cast(80.0, f32), cast(100.0, f32), cast(120.0, f32)])
prices = call_prices(spots, cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32))
// prices are approximately 1.8594, 10.4506, 26.169
```

`call_total(spots, ...)` equals the sum of the entries of
`call_prices(spots, ...)`.

## Gradient-derived sensitivities

```chelis
def deltas_call[n](spots: tensor[n, f32], k: f32, r: f32, sigma: f32, t: f32) -> tensor[n, f32]
def deltas_put[n](spots: tensor[n, f32], k: f32, r: f32, sigma: f32, t: f32) -> tensor[n, f32]
def vegas_call[n](spots: tensor[n, f32], k: f32, r: f32, sigma: f32, t: f32) -> tensor[n, f32]
```

`deltas_call` and `deltas_put` differentiate the total call or put price
with respect to the spot vector using `grad`, yielding a delta per spot.
`vegas_call` differentiates the total call price with respect to a vector
of volatilities, yielding a vega per spot. These are the gradient-derived
sensitivity paths; the [Greeks](greeks.md) chapter documents the
finite-difference and analytic Greeks that the test suite uses directly.

## Monte Carlo call price

```chelis
def mc_call_price[n](template: tensor[n, f32], s0: f32, k: f32, r: f32, sigma: f32, t: f32) -> f32 ! { Random }
```

`mc_call_price` simulates terminal prices under geometric Brownian motion,
takes the discounted mean of the call payoff, and returns the Monte Carlo
estimate. The number of paths is the length of the `template` tensor. The
function carries the `Random` effect and must run inside a `with seed(...)`
block.

From `tests/pricing.ch`, a twenty-thousand-path estimate of the ATM call:

```chelis
template = to_tensor(map(fn (i: int64) -> cast(0.0, f32), range(cast(0, int64), cast(20000, int64))))
mc_px = with seed(42) {
  mc_call_price(template, cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32))
}
```

The estimate lands within two percent of `bs_call_scalar` at this path
count. Running the same call twice under the same literal seed returns the
identical value.
