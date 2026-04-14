# Phase 3l — Shoals

Source of truth for the Shoals shell implementation. Extracted verbatim
from `spec/design/chelis_phase3_plan.md` §3l in the
[`Chelis-Lang/chelis`](https://github.com/Chelis-Lang/chelis) monorepo.
Keep this file in sync with the monorepo section — any change to scope,
module list, test plan, or acceptance oracle lands in both places in the
same change set.

---

## 3l: Shoals — Finance

**Goal:** A reef package for quantitative finance. Pricing models, risk measures, yield
curves, stochastic processes, order books. Built entirely on `chelis-std` + `nautilus` +
`coral`. Contains only finance-specific logic.

**Prerequisite:** 3j (nautilus — distributions, optimization, SDE solvers), 3k (coral —
for loading/manipulating financial data), 3i (Std.Time for dates, Std.Decimal for cash
amounts).

### Modules

| Module | Contents | Key Dependencies |
|---|---|---|
| `Shoals.Pricing` | Black-Scholes analytical, Heston semi-analytical, SABR calibration, Monte Carlo engines with variance reduction. Greeks via `grad` for free — write the pricing function, `grad(price, wrt=(spot, vol, rate))` gives delta/vega/rho automatically. | `Nautilus.Distributions`, `Nautilus.SDE`, `Random` effect, cumsum |
| `Shoals.Risk` | VaR (parametric, historical, Monte Carlo), CVaR/expected shortfall, stress testing, scenario generation | `Nautilus.Stats`, sort/quantile, `Random` effect |
| `Shoals.Curves` | Yield curve construction (bootstrap from market instruments), interpolation (linear, cubic, Nelson-Siegel), day count conventions (ACT/360, ACT/365, 30/360) | `Nautilus.Interpolation`, `Nautilus.Roots`, `Std.Time` |
| `Shoals.Stochastic` | SDE models: GBM, Heston, SABR, jump-diffusion. Path generation using cumsum + `Nautilus.SDE`. Variance reduction (antithetic, control variates). | `Nautilus.SDE`, `Random`, cumsum, einsum |
| `Shoals.Orderbook` | Limit order book representation (price-priority sorted collections), matching logic, bid/ask spread computation, VWAP | Host-side collections, sort, `Std.Decimal` |

### What Makes This Work in Chelis

- **Greeks for free:** `grad(black_scholes_price, wrt=(spot, vol, rate, T))` gives all
  four first-order Greeks in one backward pass. `vmap(grad(...))` gives per-instrument
  Greeks for a portfolio. No bump-and-reprice, no finite differences.
- **Reproducible Monte Carlo:** The `Random` effect with `withSeed` handlers means every
  simulation is exactly reproducible. Two runs with the same seed produce identical
  paths. This is a regulatory requirement.
- **Typed market data:** Named tensor dimensions like `tensor[instrument, scenario, f32]`
  prevent accidentally multiplying a `[portfolio, maturity]` matrix by a
  `[maturity, scenario]` matrix when the dimensions don't match.
- **Effect-tracked data provenance:** A function that reads from a market data feed has
  `IO` effect. A function using Monte Carlo has `Random` effect. The type system tracks
  what each computation depends on.

### Test Plan

- `Shoals.Pricing`: Black-Scholes price matches analytical formula (< 1e-10 error)
- `Shoals.Pricing`: Monte Carlo price converges to Black-Scholes analytical for
  vanilla European call (< 1% error with 100K paths)
- `Shoals.Pricing`: Greeks via `grad` match analytical Black-Scholes Greeks
  (< 1e-6 error)
- `Shoals.Risk`: Parametric VaR matches `Nautilus.Distributions.Normal.ppf` at standard
  confidence levels
- `Shoals.Curves`: Bootstrap reproduces known market instrument prices (< 1bp error)
- `Shoals.Stochastic`: GBM paths satisfy known statistical properties
  (mean = spot * exp(mu*T), variance matches theory)
- `Shoals.Orderbook`: matching logic satisfies price-time priority invariant
- Effect tracking: MC pricing propagates `Random`, curve construction propagates `IO`
  for market data
- Reproducibility: same seed produces identical prices across runs

### Acceptance Oracle

`cargo test -p chelis-cli phase3l_shoals_oracle -- --exact` — prices a European call
option via Black-Scholes and Monte Carlo, verifies convergence, computes Greeks via
`grad`, loads market data via `coral`, and produces a risk report.

**Effort:** medium. Black-Scholes + Monte Carlo + basic risk is the core; curves and
order book are smaller. The bulk of the work is composing existing primitives (`nautilus`
solvers, `coral` dataframes, tensor ops), not implementing new infrastructure.
