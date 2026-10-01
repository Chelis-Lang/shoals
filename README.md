# Shoals

Shoals is a quantitative finance library for [Chelis](https://github.com/Chelis-Lang/chelis). It provides option pricing, Greeks, yield curves, volatility surfaces, stochastic models, risk measures, market data, calendars, and valuation adjustments under the `Shoals` module prefix. The [Shoals book](docs/src/SUMMARY.md) starts with a pricing example and documents each module's assumptions and limits.

## Install and try it

The package version and exact Chelis, Nautilus, Coral, and standard-library pins are in [`reef.toml`](reef.toml). The current release artifacts are available through the Chelis-Lang GitHub repositories. The Chelis compiler repository is private: installing its release toolchain requires repository access and an authenticated [GitHub CLI](https://cli.github.com/). Access to the pinned dependency release assets is also required. See the [Chelis installation guide](https://github.com/Chelis-Lang/chelis/blob/main/docs/book/src/install.md) for supported platforms and setup details.

From a Shoals source checkout:

```sh
gh auth login                      # once, if needed
gh release download --repo Chelis-Lang/chelis --pattern chelisup.sh --output - | sh
export PATH="$HOME/.chelis/bin:$PATH"
chelisup install 0.18.11
chelis reef build
chelis test tests/pricing.ch --filter test_bs_call_atm --timeout 120 --suite-timeout 180 --jobs 1
```

`chelisup install 0.18.11` installs the compiler pinned by `reef.toml`.
`chelis reef build` resolves the declared dependencies, fetching missing release
packages as needed, then checks and builds Shoals. The last command runs the
source test that prices a one-year at-the-money Black-Scholes call at
approximately 10.4506. Run all commands from the repository root. For the
pricer and a seeded Monte Carlo example, see
[Getting started](docs/src/getting-started.md).

## Modules

| Area | Modules | What they provide |
| --- | --- | --- |
| Options | `Shoals.Pricing`, `Shoals.PricingExtended`, `Shoals.Greeks` | Black-Scholes, Black, Bachelier, FX and exchange pricers; automatic and finite-difference sensitivities |
| Rates and volatility | `Shoals.Curves`, `Shoals.VolSurface`, `Shoals.Date`, `Shoals.Tenor`, `Shoals.HolidayCal` | Curve construction, SVI and SABR approximations, day counts, schedules, and holidays |
| Simulation and risk | `Shoals.Stochastic`, `Shoals.Rng`, `Shoals.Risk`, `Shoals.RiskExt`, `Shoals.Xva` | Seeded paths and estimators, VaR/expected shortfall, and valuation adjustments |
| Data and numerics | `Shoals.MarketData`, `Shoals.Orderbook`, `Shoals.Distributions`, `Shoals.ModelFit`, `Shoals.CurrencyTag` | Quotes, price-priority books, distributions, scalar calibration helpers, and tagged money |

The [book's module reference](docs/src/SUMMARY.md) gives the public calls and examples. [`docs/CHELIS_SURFACE.md`](docs/CHELIS_SURFACE.md) records detailed compiler-facing capabilities. [`docs/src/scope.md`](docs/src/scope.md) describes numerical domains, model assumptions, and other limits. The `references/`, `properties/`, and `demos/` directories contain comparison formulas, sampled checks, and counterexamples; their test results are evidence for the exercised inputs rather than unrestricted finance theorems.

## Development checks

```sh
uv venv --python 3.11
export PATH="$PWD/.venv/bin:$PATH"
.venv/bin/python scripts/run_local_gate.py
```

The default gate runs source formatting, lint, the package build, negative tests, and repository contract checks. The longer runtime, manual, and proof checks run separately in the nightly and release workflows; `scripts/run_local_gate.py --full` runs them locally when needed. A focused pricing test is shown above. Book readers can render the documentation with `mdbook build docs`.

## License

MIT
