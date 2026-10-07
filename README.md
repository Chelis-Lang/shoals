# Shoals

Shoals is a quantitative finance library for [Chelis](https://github.com/Chelis-Lang/chelis). It provides option pricing, Greeks, yield curves, volatility surfaces, stochastic models, risk measures, market data, calendars, and valuation adjustments under the `Shoals` module prefix.

The Shoals book is published at <https://chelis.ch/docs/shoals/>, and its source is in [`docs/book/`](docs/book/) (render it with `mdbook build docs/book`). It starts with a pricing example and documents each module's API, assumptions and limits.

## Install

Shoals is a Reef package; you do not need this repository to use it. Shoals
0.24.15 requires Chelis 0.19.1 (see the
[Chelis install guide](https://chelis.ch/docs/chelis/install/)). Create a
project and download Shoals and the three packages it depends on from their
GitHub releases; these downloads need no GitHub token:

```sh
chelis reef init demo --module-prefix Demo --output demo
cd demo
chelis reef install --from-github Chelis-Lang/nautilus@v0.7.50
chelis reef install --from-github Chelis-Lang/coral@v0.7.47
chelis reef install --from-github Chelis-Lang/shoreleave@v0.1.2
chelis reef install --from-github Chelis-Lang/shoals@v0.24.15
```

Set `compiler = "=0.19.1"` under `[package]` and
`shoals = { version = "=0.24.15" }` under `[dependencies]` in the generated
`reef.toml`, then run `chelis reef build`. With `GITHUB_TOKEN` set or the `gh`
CLI signed in, `chelis reef build` downloads missing packages itself and the
`reef install` lines are unnecessary. [Getting started](https://chelis.ch/docs/shoals/getting-started/)
continues with a first pricing call.

## Modules

| Area | Modules | What they provide |
| --- | --- | --- |
| Options | `Shoals.Pricing`, `Shoals.PricingExtended`, `Shoals.Greeks` | Black-Scholes, Black, Bachelier, FX and exchange pricers; automatic and finite-difference sensitivities |
| Rates and volatility | `Shoals.Curves`, `Shoals.VolSurface`, `Shoals.Date`, `Shoals.Tenor`, `Shoals.Schedule` | Curve construction, SVI and SABR approximations, exact day counts, tenors, and schedules; market calendars come from Shoreleave |
| Lattices and PDEs | `Shoals.Trees`, `Shoals.Pde`, `Shoals.Lsm`, `Shoals.FixedIncome` | Binomial and trinomial trees, Crank-Nicolson and ADI PDE pricers, Longstaff-Schwartz American exercise, and bond pricing |
| Rate and volatility models | `Shoals.HullWhite`, `Shoals.LiborMarketModel`, `Shoals.SabrPaths`, `Shoals.Heston`, `Shoals.Dupire` | Hull-White and LMM/HJM short-rate and forward paths, SABR paths, Heston Fourier pricers, and Dupire local volatility |
| Credit and collateral | `Shoals.Cds`, `Shoals.Csa` | Hazard curves, CDS legs and bootstrap, and collateralized exposure |
| Simulation and risk | `Shoals.Stochastic`, `Shoals.Rng`, `Shoals.Risk`, `Shoals.RiskExt`, `Shoals.Xva` | Seeded paths and estimators, VaR/expected shortfall, and valuation adjustments |
| Data and numerics | `Shoals.MarketData`, `Shoals.Orderbook`, `Shoals.Distributions`, `Shoals.ModelFit`, `Shoals.CurrencyTag` | Quotes, price-priority books, distributions, scalar calibration helpers, and tagged money |

[Scope and limitations](https://chelis.ch/docs/shoals/scope/) describes numerical domains, model assumptions, and other limits.

## License

MIT
