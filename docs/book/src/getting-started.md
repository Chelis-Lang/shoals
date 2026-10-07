# Getting started

[Shoals](https://github.com/Chelis-Lang/shoals) is a Chelis library for
financial calculations. You use its released package as a Reef dependency;
there is no need to check out Shoals' source repository. Shoals 0.24.15
requires Chelis 0.19.1 (see the [Chelis install guide](https://chelis.ch/docs/chelis/install/)).

Create a project, then download Shoals and the three packages it depends on
from their GitHub releases. These downloads need no GitHub token:

```sh
chelis reef init demo --module-prefix Demo --output demo
cd demo
chelis reef install --from-github Chelis-Lang/nautilus@v0.7.50
chelis reef install --from-github Chelis-Lang/coral@v0.7.47
chelis reef install --from-github Chelis-Lang/shoreleave@v0.1.2
chelis reef install --from-github Chelis-Lang/shoals@v0.24.15
```

Set the compiler pin and the dependency in the generated `reef.toml`:

```toml
[package]
compiler = "=0.19.1"

[dependencies]
shoals = { version = "=0.24.15" }
```

Then run `chelis reef build`. If `GITHUB_TOKEN` is set or the `gh` CLI is
signed in, `chelis reef build` finds and downloads missing packages itself
and the `reef install` lines are unnecessary; without either, it stops with
*remote discovery is unavailable ... GITHUB_TOKEN is not set*. See
[Reef and packages](https://chelis.ch/docs/chelis/reef/) for the project setup.

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

Save it as `src/main.ch` in that project, replacing the starter module, then
run `chelis eval --file src/main.ch`:

```text
px = 10.450583
```
