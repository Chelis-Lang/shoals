# Getting started

[Shoals](https://github.com/Chelis-Lang/shoals) is a Chelis library for
financial calculations. You can use its released package as a Reef dependency;
there is no need to check out Shoals' source repository. Shoals 0.24.15
requires Chelis 0.19.1, so set the compiler pin and the dependency in your
project's `reef.toml`:

```toml
[package]
compiler = "=0.19.1"

[dependencies]
shoals = { version = "=0.24.15" }
```

Then run `chelis reef setup` and `chelis reef build`. Reef fetches released dependencies, including the packages Shoals depends on.
See [Reef and packages](https://chelis.ch/docs/chelis/reef/) for the project setup.

Begin with the [pricing reference](pricing.md) for its exported
pricing functions, then read [conventions](conventions.md) for
tensor inputs and random keys.

## Price a call

`Shoals.Pricing.bs_call_scalar` takes spot, strike, continuously compounded
risk-free rate, volatility, and maturity in years, all as `f32`. It prices a
European call on a non-dividend-paying underlying:

```chelis
module Demo.Main
import Shoals.Pricing (bs_call_scalar)
px = bs_call_scalar(cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32))
```

Save it as `src/main.ch` in a project created with
`chelis reef init demo --module-prefix Demo`, then run
`chelis eval --file src/main.ch`:

```text
px = 10.450583
``` To install Chelis,
see the [Chelis install guide](https://chelis.ch/docs/chelis/install/).
