# Pricing

Module: `Shoals.Pricing`.

This module provides the Black-Scholes call and put in closed form,
vectorized price tensors over a set of spots, gradient-derived sensitivity
vectors, and a Monte Carlo call pricer that carries the `Random` effect.
The `f32` scalar calls use an `f64` pricing body with this module's own
normal-CDF approximation. The approximation loses relative precision in the
far negative tail. See [Scope and limitations](scope.md) for numerical bounds.

## Closed-form scalars

```chelis
def bs_call_scalar(s: f32, k: f32, r: f32, sigma: f32, t: f32) -> f32
def bs_put_scalar(s: f32, k: f32, r: f32, sigma: f32, t: f32) -> f32
def bs_call_f64(s: f64, k: f64, r: f64, sigma: f64, t: f64) -> f64
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

## Tensor-valued f64 entry

`bs_call_f64_vector` prices matched `f64` tensors of spots, strikes, rates,
volatilities, and maturities. `bs_call_wire_f64` is a separate pure-tensor
entry with explicit tensor inputs for its normal-CDF coefficients. It uses
an Abramowitz–Stegun approximation rather than the scalar kernel's Cody
approximation, so callers should not expect identical values. The source
test compares selected rows within `1e-5 + 1e-8 * abs(expected)`.
`scripts/validate_bs_wire_root.py` checks the compiler-produced graph.

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
def rhos_call[n](spots: tensor[n, f32], k: f32, r: f32, sigma: f32, t: f32) -> tensor[n, f32]
def thetas_call[n](spots: tensor[n, f32], k: f32, r: f32, sigma: f32, t: f32) -> tensor[n, f32]
def gammas_call[n](spots: tensor[n, f32], k: f32, r: f32, sigma: f32, t: f32) -> tensor[n, f32]
def volgas_call[n](spots: tensor[n, f32], k: f32, r: f32, sigma: f32, t: f32) -> tensor[n, f32]
def vannas_call[n](spots: tensor[n, f32], k: f32, r: f32, sigma: f32, t: f32) -> tensor[n, f32]
```

`deltas_call` and `deltas_put` differentiate the total call or put price
with respect to the spot vector using `grad`, yielding a delta per spot.
`vegas_call` differentiates the total call price with respect to a vector
of volatilities, yielding a vega per spot. The other exported calls give
call rho, theta, gamma, volga, and vanna; the last three use nested
derivatives. The [Greeks](greeks.md) chapter documents separate
finite-difference and analytic checks.

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
template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(20000, i64))))
mc_px = with seed(42i64) {
  mc_call_price(template, cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32))
}
```

The source test checks a two-percent tolerance at this path count.
Running the same call twice under the same seed and inputs returns the
identical value.
