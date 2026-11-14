# Shoals

Shoals is a quantitative finance library for [Chelis](https://github.com/Chelis-Lang/chelis). It provides option pricing, Greeks, yield curves, volatility surfaces, stochastic models, risk measures, market data, calendars, and valuation adjustments under the `Shoals` module prefix.

The [Shoals book](https://chelis.ch/docs/shoals/) starts with a pricing
example and documents each module's API, assumptions, and limits. A local
copy is available in [`docs/book/`](docs/book/).

## Install

Shoals is a Reef package; you do not need this repository to use it. Follow the
[Chelis install guide](https://chelis.ch/docs/chelis/install/), then create a
project and download Shoals and the four packages it depends on from their
GitHub releases; these downloads need no GitHub token:

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

Add `shoals = { version = "=0.25.2" }` under `[dependencies]`.
Then run `chelis reef build`.
With `GITHUB_TOKEN` or a signed-in `gh` CLI, Reef downloads missing packages.
The four dependency install commands are then optional.
[Getting started](https://chelis.ch/docs/shoals/getting-started/) gives a first pricing call.

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

## Validation

Hosted checks cover formatting, lint, compilation, short guards, offline
contracts and oracle classifier tests, and book prose and source signatures.
Long numerical suites and runtime book examples are optional local tools.
This command opts in:

```sh
PATH="$PWD/.venv/bin:$PATH" python3 scripts/run_local_gate.py --full
```

They are not required before push, merge, or release. Publication builds and
verifies the actual release assets and their hashes.

## License

MIT
