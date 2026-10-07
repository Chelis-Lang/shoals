# Shoals

Shoals is a quantitative finance library for [Chelis](https://github.com/Chelis-Lang/chelis). It provides option pricing, Greeks, yield curves, volatility surfaces, stochastic models, risk measures, market data, calendars, and valuation adjustments under the `Shoals` module prefix.

The Shoals book is published at <https://chelis.ch/docs/shoals/>, and its source is in [`docs/`](docs/) (render it with `mdbook build docs`). It starts with a pricing example and documents each module's API, assumptions and limits.

## Install

Shoals is a Reef package; you do not need this repository to use it. Add it
under `[dependencies]` in your project's `reef.toml`, set the project compiler
pin to the version this Shoals release requires (the `compiler` field of
[`reef.toml`](reef.toml)), and build:

```sh
chelis reef build
```

Reef fetches the released Shoals package and the packages it depends on. See
[Getting started](https://chelis.ch/docs/shoals/getting-started/) for a first
pricing call and the [Chelis install guide](https://chelis.ch/docs/chelis/install/)
for the compiler.

## Modules

| Area | Modules | What they provide |
| --- | --- | --- |
| Options | `Shoals.Pricing`, `Shoals.PricingExtended`, `Shoals.Greeks` | Black-Scholes, Black, Bachelier, FX and exchange pricers; automatic and finite-difference sensitivities |
| Rates and volatility | `Shoals.Curves`, `Shoals.VolSurface`, `Shoals.Date`, `Shoals.Tenor`, `Shoals.Schedule` | Curve construction, SVI and SABR approximations, exact day counts, tenors, and schedules; market calendars come from Shoreleave |
| Simulation and risk | `Shoals.Stochastic`, `Shoals.Rng`, `Shoals.Risk`, `Shoals.RiskExt`, `Shoals.Xva` | Seeded paths and estimators, VaR/expected shortfall, and valuation adjustments |
| Data and numerics | `Shoals.MarketData`, `Shoals.Orderbook`, `Shoals.Distributions`, `Shoals.ModelFit`, `Shoals.CurrencyTag` | Quotes, price-priority books, distributions, scalar calibration helpers, and tagged money |

[Scope and limitations](https://chelis.ch/docs/shoals/scope/) describes numerical domains, model assumptions, and other limits.

## License

MIT
