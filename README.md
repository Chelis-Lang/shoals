# Shoals

Shoals is a quantitative finance library for [Chelis](https://github.com/Chelis-Lang/chelis). It provides option pricing, Greeks, yield curves, volatility surfaces, stochastic models, risk measures, market data, calendars, and valuation adjustments under the `Shoals` module prefix. The [Shoals book](docs/src/SUMMARY.md) starts with a pricing example and documents each module's assumptions and limits.

## Install and try it

The package version and exact Chelis, Nautilus, Coral, Shoreleave, and
standard-library pins are in [`reef.toml`](reef.toml). Use the
[Chelis installation guide](https://github.com/Chelis-Lang/chelis/blob/main/docs/book/src/install.md)
to install the compiler and the declared package releases. Reef builds use
installed packages; `chelis reef build` does not download missing dependencies.
The [Getting started](docs/src/getting-started.md) chapter shows a pricer and
a seeded Monte Carlo example. The source tests include a one-year
at-the-money Black-Scholes call at approximately 10.4506.

## Modules

| Area | Modules | What they provide |
| --- | --- | --- |
| Options | `Shoals.Pricing`, `Shoals.PricingExtended`, `Shoals.Greeks` | Black-Scholes, Black, Bachelier, FX and exchange pricers; automatic and finite-difference sensitivities |
| Rates and volatility | `Shoals.Curves`, `Shoals.VolSurface`, `Shoals.Date`, `Shoals.Tenor`, `Shoals.Schedule` | Curve construction, SVI and SABR approximations, exact day counts, tenors, and schedules; market calendars come from Shoreleave |
| Simulation and risk | `Shoals.Stochastic`, `Shoals.Rng`, `Shoals.Risk`, `Shoals.RiskExt`, `Shoals.Xva` | Seeded paths and estimators, VaR/expected shortfall, and valuation adjustments |
| Data and numerics | `Shoals.MarketData`, `Shoals.Orderbook`, `Shoals.Distributions`, `Shoals.ModelFit`, `Shoals.CurrencyTag` | Quotes, price-priority books, distributions, scalar calibration helpers, and tagged money |

The [book's module reference](docs/src/SUMMARY.md) gives the public calls and examples. [`docs/CHELIS_SURFACE.md`](docs/CHELIS_SURFACE.md) records detailed compiler-facing capabilities. [`docs/src/scope.md`](docs/src/scope.md) describes numerical domains, model assumptions, and other limits. The `references/`, `properties/`, and `demos/` directories contain comparison formulas, sampled checks, and counterexamples; their test results are evidence for the exercised inputs rather than unrestricted finance theorems.

## Development checks

```sh
uv venv --python 3.11
export PATH="$PWD/.venv/bin:$PATH"
.venv/bin/python scripts/run_local_gate.py
```

Run the gate after installing the package releases declared in `reef.toml`.
It checks source formatting, lint, the package build, negative tests, and
repository contracts. The longer runtime, manual, and proof checks run in
nightly and release workflows; `scripts/run_local_gate.py --full` runs them
locally. Book readers can render the documentation with `mdbook build docs`.

## License

MIT
