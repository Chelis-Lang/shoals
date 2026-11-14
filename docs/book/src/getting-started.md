# Getting started

[Shoals](https://github.com/Chelis-Lang/shoals) is a Chelis library for
financial calculations. Use its package as a Reef dependency.
You do not need a copy of Shoals' source repository. Follow the
[Chelis install guide](https://chelis.ch/docs/chelis/install/) to install the toolchain.

After Shoals 0.25.2 and the four dependency versions below are available as public
GitHub releases, create a project and download them. These downloads need no GitHub token:

```sh
chelisup install 0.23.1
chelis +0.23.1 reef init demo --module-prefix Demo --output demo
cd demo
chelis reef install --from-github chelis-lang/nautilus@v0.7.59
chelis reef install --from-github chelis-lang/coral@v0.7.53
chelis reef install --from-github chelis-lang/shoreleave@v0.1.7
chelis reef install --from-github chelis-lang/chelis-clarabel@v0.1.4
chelis reef install --from-github chelis-lang/shoals@v0.25.2
```

Add the Shoals dependency to the generated `reef.toml`:

```toml
[package]
compiler = "=0.23.1"

[dependencies]
shoals = { version = "=0.25.2" }
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
