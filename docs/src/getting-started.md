# Getting started

[Shoals](https://github.com/Chelis-Lang/shoals) is a Chelis library for
financial calculations. You can use its released package as a Reef dependency;
there is no need to check out Shoals' source repository. Add `shoals` under
`[dependencies]` in your project's `reef.toml` and run `chelis reef build`.
Set the project compiler pin to the version required by the Shoals release.
Reef fetches released dependencies, including the packages Shoals depends on.
See [Reef and packages](https://chelis.ch/docs/chelis/reef/) for the project setup.

Begin with the [pricing reference](pricing.md) for its exported
pricing functions, then read [conventions](conventions.md) for
tensor inputs and random keys.

## Price a call

`Shoals.Pricing.bs_call_scalar` takes spot, strike, continuously compounded
risk-free rate, volatility, and maturity in years, all as `f32`. It prices a
European call on a non-dividend-paying underlying:

```chelis
px = bs_call_scalar(cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32))
```

For these inputs, the price is approximately **10.4506**. To install Chelis,
see the [Chelis install guide](https://chelis.ch/docs/chelis/install/).
