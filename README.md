# Shoals

Quantitative-finance shell for the
[Chelis](https://github.com/Chelis-Lang/chelis) programming language.
Ships as a reef package under the `Shoals` module prefix.

## Status

v0.20.0. M0-M9 milestone sweep complete + Milestone A
(foundations cleanup) + the FlukeBall currency-tag slice, unioned
into a single line. Full slice:
M0 baseline + M1 foundations (Date, Calendar, Tenor, MarketData,
Distributions) + M2 yield-curve sensitivity ops
(parallel/key-rate/twist/butterfly shifts, log-linear and
Nelson-Siegel-Svensson interpolation, curve-kind metadata for
OIS/IBOR/SOFR/SONIA/ESTR) + M3 vol surfaces (SVI parameterization,
implied-vol solver via bisection, shifts) + M4 SDE-zoo slice
(Merton jump-diffusion with compensated drift; 2-asset correlated
GBM via 2x2 Cholesky) + M5 closed-form pricers (Bachelier, Black,
Garman-Kohlhagen, Margrabe) + M6 Greeks discipline (FD first- and
second-order Greeks, analytic-Greek references, pathwise vs LR
dispatch) + M7 XVA core (constant-hazard survival probabilities,
EPE/ENE aggregation, pointwise netting, CVA + DVA aggregators) +
M8 calibration (weighted-LS / WL1 / vega-weighted residuals,
bound-clamped LM step) + M9 extended risk (MC VaR / ES,
FRTB-IMA 97.5% ES, scenario PnL grid, Kupiec POF backtest
statistic). M10 (verified-AD typing migration) is upstream-gated
and not part of this release line. `Shoals.CurrencyTag` adds the
runtime-tagged money primitives used by Whale and FlukeBall bankroll
code. Every public function carries the
`alpha` stability label per the cross-cutting Chelis convention.
Shoals's version track is its own — the prior 0.7.x labelling was
chasing the compiler version and has been reset; minor bumps now
reflect Shoals's milestone progression. Forward scope — vol
surfaces, advanced SDE, the pricer zoo, Greeks discipline, XVA,
calibration, and advanced risk — is specified in
`spec/shoals_quant_surface.md`, planned in
`docs/plan-quant-surface.md`, and milestone-gated.

## Modules

| Module | Contents | Status |
|---|---|---|
| `Shoals.Pricing` | Black-Scholes call/put (closed form), call/put price tensors, MC engine with `Random` effect, finite-difference Greek checks; grad-derived Greeks are an alpha runtime path | alpha |
| `Shoals.Risk` | Parametric VaR + CVaR (Gaussian), historical VaR + CVaR (empirical-quantile + tail-mean), empirical loss quantiles | alpha |
| `Shoals.Curves` | Linear / cubic-spline / log-linear / Nelson-Siegel-Svensson yield-curve interpolation; discount factors; single-curve par-bond bootstrap; curve-kind metadata (OIS/IBOR/SOFR/SONIA/ESTR/Custom); sensitivity ops (parallel/key-rate/twist/butterfly shifts, scale) | alpha |
| `Shoals.Stochastic` | GBM path generation (log-Euler), terminal draws, antithetic-variates terminal-mean estimator; Merton lognormal jump-diffusion (compensated drift, aggregate-jump Gaussian approximation); 2-asset correlated GBM via 2x2 Cholesky | alpha |
| `Shoals.Orderbook` | Limit order book (price-priority sorted lists), best bid/ask, bid-ask spread, VWAP, side quantities | alpha |
| `Shoals.Date` | Day-count conventions (Act360/Act365/30/360/ActAct), year-fraction, weekend detection, business-day rolling (following/modified-following/preceding), tenor-stepped schedule generation, calendar-aware `add_months` with day-cap correctness, `days_in_month`, `schedule_from_tenor_calendar` | alpha |
| `Shoals.HolidayCal` | NYC + LDN holiday tables (2025 hardcoded + algorithmic via Computus for 1583-9999); Good Friday + Easter Monday derived; multi-year calendar builders; joint-calendar combinator; business-day predicate | alpha |
| `Shoals.Rng` | Sobol low-discrepancy (Joe-Kuo direction-number table, 32-D committed floor); Halton (first 50 primes); variance-reduction combinators (antithetic, control-variate, stratified) | alpha |
| `Shoals.Tenor` | Programmatic `Tenor { count, unit }` constructors (`days_n`, `weeks_n`, `months_n`, `years_n`, `overnight`, `tomorrow_next`, `spot_next`), `tenor_apply` to advance a date; string parser `parse_tenor` for "3M"/"1Y"/"30Y"/"ON"/"TN"/"SN" | alpha |
| `Shoals.MarketData` | `Quote`, `Bar`, `Snapshot` record types with constructors / accessors / linear-scan lookup | alpha |
| `Shoals.Distributions` | Lognormal pdf+cdf; Student-t pdf + exact cdf (delegates to Nautilus) + Fisher-Cornish approximation kept for back-compat; bivariate-normal pdf; Shoals-side re-exports of Nautilus's gamma/beta/chi_squared/exponential/uniform/poisson pdf+cdf+inv_cdf+sample surface; N-dim Cholesky multivariate-normal sampler (`dist_mvn_factor` + `dist_mvn_sample_one`) | alpha |
| `Shoals.VolSurface` | SVI 5-parameter total-variance + implied-vol; ATM/skew/parallel/smile shifts; implied-vol-from-call bisection solver over Black-Scholes; SABR 4-parameter analytic implied-vol via Hagan 2002 simplified expansion (`vs_sabr_implied_vol`, `vs_sabr_atm_implied_vol`, shift constructors) | alpha |
| `Shoals.PricingExtended` | Bachelier (normal-underlying) call/put; Black (forward-priced) call/put; Garman-Kohlhagen (FX) call/put; Margrabe exchange-option call with degenerate-vol intrinsic guard | alpha |
| `Shoals.Greeks` | First-order FD Greeks (delta/vega/rho/theta, call+put); second-order FD (gamma/vanna/volga); analytic-Greek references for FD cross-check; pathwise-smooth and likelihood-ratio dispatchers for the digital-option payoff family | alpha |
| `Shoals.Xva` | Constant-hazard survival / default probability; constant-rate discount factor; expected positive / negative exposure aggregators; pointwise 2-deal netting; CVA + DVA aggregators over a discrete time grid | alpha |
| `Shoals.ModelFit` | Bound projection; weighted-LS / WL1 / vega-weighted residuals; SSE loss; single-parameter bound-clamped LM step (`jtj + lambda` damping with bound projection on the proposed value) | alpha |
| `Shoals.RiskExt` | MC VaR / expected shortfall; FRTB-IMA 97.5% ES helper; linear scenario PnL grid; Kupiec proportion-of-failures backtest statistic | alpha |
| `Shoals.CurrencyTag` | Runtime-tagged `Currency`, `Money`, and `NonNegativeMoney` constructors plus same-currency arithmetic used by Whale bankroll code | alpha |

The reference implementations under `references/` ship the
textbook-formula versions of Black-Scholes (call, put, all five
first-order Greeks), Vasicek (zero-bond pricing, conditional-rate
moments), historical VaR/CVaR, and vanilla Monte Carlo. They are the
ground-truth oracles that `Shoals.Pricing`, `Shoals.Risk`, and
`Shoals.Stochastic` must agree with under the property gate.

## Properties

`properties/` ships function bodies for the canonical finance
properties (put-call parity, call-bounded-by-spot, finite-difference
delta/vega smoke, MC-reproducibility, bull/butterfly-spread
no-arbitrage). Status: mixed. The compiler v0.7.26 does not yet
parse `@property` annotations and ships no `chelis fuzz` subcommand;
the property bodies are written as plain `def name(...) -> bool`
ready to flip to `@property` when the tool ships. See
`spec/phase3l.md` and the upstream `chelis_fuzz_spec.md` for the
plan. `Shoals.Pricing` still exposes grad-derived Greek functions, but
the default executable test suite uses finite differences. The
upstream `grad-eval-host-runtime` bug closed (chelis 2026-05-07);
host-runtime `grad` is supported. Whether Shoals's specific pricing
body (which uses `to_list` + `map` over a host-lane list combinator)
lowers cleanly under `grad` is unverified at M0 — a future milestone
that adds grad-derived Greek properties re-evaluates.

## Toolchain

Pinned to `chelis v0.7.26` in `reef.toml`:

```toml
[package]
compiler = "=0.7.26"
```

Dependencies resolve via the local Reef registry (`~/.chelis/reef/`):

* `chelis-std` 0.4.0 — standard library
* `nautilus`   0.7.25 — distributions, special functions, stats,
  interpolation
* `coral`      0.7.24 — dataframe runtime (transitively required for
  the same `nautilus` minor version)

## Build

```sh
# compiler-owned package gate
chelis reef build

# run the in-tree runtime test suite explicitly
chelis test tests/ --timeout 180 --jobs auto

# serial debugging fallback
chelis test tests/ --timeout 180 --jobs 1

# canonical-formatter parseability gate (single file at a time today)
chelis fmt --check src/pricing.ch
```

`chelis fmt` accepts only one file per invocation; CI loops
over the directory in Python. See `.github/workflows/ci.yml` and
`scripts/run_local_gate.py`.

The default test tier uses 20 000 Monte-Carlo paths and 2 % tolerance
for convergence assertions. The longer `--timeout 180` is required
because the host evaluator runs the 20K MC sample loop in ~60 s. It is
part of the default PR gate.

### Manual rigor gate

The spec-rigor 100 000-path tier lives at
`manual-gates/mc_rigorous.ch` and is **not** walked by
`chelis test tests/`. Invoke it explicitly:

```sh
chelis test manual-gates/mc_rigorous.ch --timeout 900
```

The rigor tier asserts 1 % MC convergence and 2 % terminal-variance
agreement at 100K paths. **Currently not runnable on the chelis host
evaluator** — 100K-path MC simulation in the interpreted host
evaluator does not complete in reasonable wall-clock (>30 min and not
terminating, measured 2026-05-01 on AMD Ryzen AI Max+ 395 under
chelis 0.7.6; not re-measured under 0.7.16 at M0). The gate becomes
practical once Shoals can compile to native code via `chelis build`
AOT; until then the spec rigor at 100K paths is deferred. See
`chelis/spec/upstream-bugs/host-eval-perf-mc-rigor.md`.
The default-tier 20K-path tests in `tests/` exercise the same
correctness invariants at lower rigor and are an explicit local/runtime
gate, not part of every PR push.

## Acceptance gate

Default PR/repo-local gate: `scripts/run_local_gate.py` and CI run
`chelis fmt --check` over repository `.ch` sources,
`chelis lint --check src/ properties/ references/ tests/ manual-gates/`,
`chelis reef build`, and `chelis test tests/ --timeout 180 --jobs auto`.
`chelis reef build` is the compiler-owned package oracle: it resolves
the Reef manifest, lowers the package, and rejects stale source or
dependency wiring; the runtime lane exercises the finance invariants.
The `chelis lint --check` step blocks on any blocking nomenclature
violation per `crates/chelis-lint/` rules; advisory warnings are
non-blocking.

Runtime gate expected success condition: the fast `tests/` unit
suite passes at v0.20.0. The suite unions the M0-M9 + Milestone A
SDE/PDE/XVA coverage with the FlukeBall currency-tag tests; the
heavy MC / PDE / Fourier / optimization files live in
`tests-manual/` and are exercised by the milestone manual-gate
scripts, not per-PR CI. This covers pricing correctness,
finite-difference Greeks (in-unit-range and matches-N(d1) checks), MC
convergence (20K paths, 2 % tolerance) and reproducibility, parametric
and historical VaR/CVaR, yield-curve interpolation and bootstrap
round-trip, GBM path positivity, full-path bit-exact reproducibility,
terminal-mean and terminal-variance theorems, and order-book invariants.
Properties under `properties/` are exercised through
`tests/properties.ch` (textbook call/put agreement,
finite-difference-delta smoke, and optimized-vs-textbook-MC
properties). Grad-vs-textbook Greek runtime properties remain
deferred at M0: the upstream `grad-eval-host-runtime` bug closed
(chelis 2026-05-07), so host-runtime `grad` works in general, but
the specific Shoals pricing body (`to_list` + `map` over a host-lane
list combinator) has not been verified end-to-end through `grad`
under the new compiler. Re-evaluation belongs to the M6 Greeks
discipline milestone in `docs/plan-quant-surface.md`.
The v0.7.6 testing cutover timing is recorded in
`docs/testing_cutover_0.7.6.json`: node-local `--jobs auto` ran 48
tests in 1:04.89; serial `--jobs 1` ran the same suite in 1:25.44.
(Not re-measured under 0.7.16 at M0.)

Phase oracle: the Chelis-monorepo-side
`cargo test -p chelis-cli --test phase3l_shoals_oracle phase3l_shoals_oracle -- --ignored --exact --nocapture`
is a manual gate and is not exercised from this repo. The Shoals
default PR scope includes `chelis reef build` and the node-local
runtime suite; the monorepo oracle remains a separate manual gate.

## Known limitations in v0.20.0

1. **`@property` is design-only.** Compiler v0.7.26 does not parse
   the annotation; the property bodies are plain `def`s that flip to
   `@property` when `chelis fuzz` ships. See above.
2. **`chelis manifest` is design-only.** The MC reproducibility
   contract is enforced by the `Random` effect (the compiler refuses
   unseeded random ops at type-check time). The JSON manifest artifact
   for CI is a Chelis-side follow-up.
3. **MC convergence rigor is split by tier.** The default 20 000-path
   test uses 2 % tolerance and runs in CI through
   `chelis test tests/ --timeout 180 --jobs auto`. The 100 000-path
   / 1 % spec-rigor tier lives at `manual-gates/mc_rigorous.ch` and
   is invoked explicitly (see "Manual rigor gate" above).
4. **Single-curve bootstrap only.** `bootstrap_zero_from_par`
   handles the integer-year-spaced case (one coupon per pillar). The
   multi-instrument bootstrap (deposits + FRAs + futures + swaps)
   with implicit-differentiation gradient through the joint solve is
   an M2-continuation candidate per `docs/plan-quant-surface.md`.
5. **`erfc` direct routing.** Per Chelis architecture, special
   functions live in `Nautilus.Special`. As of `nautilus 0.7.25`
   Shoals routes Black-Scholes through `Nautilus.Special.erfc`
   directly (computing `0.5 * erfc(-x / sqrt(2))` for the standard
   normal CDF), bypassing the higher-level distribution wrapper. No
   shell-private special functions are shipped.

### Canonical layout

Per the trust stack spec, `properties/` and `references/` are top-level
directories alongside `src/`. Shoals adopted the canonical layout
following the chelis-reef v0.4.1 multi-source-roots fix
(`6b58030 feat(reef): multi-source-roots — additional_sources in reef.toml;
bump v0.4.1`). The reef.toml declares
`additional_sources = ["properties", "references"]`. v0.1.0 carries the
canonical layout forward and pins chelis 0.7.26, nautilus 0.7.25, and
coral 0.7.24. (References to the pre-reset v0.7.x numbering point at
the historical version track and remain valid as release-history
records; current planning lives on Shoals's own track per
`docs/plan-quant-surface.md`.)

## Python interop

The Chelis monorepo ships a `chelis-python` package
(`bindings/python/chelis/`) that wraps the in-process evaluator and
exposes `chelis.check(...)` and `chelis.eval(source, bindings)` to
Python. The pre-reset v0.1.0-alpha release verified a Shoals-shaped
program round-trips through that surface; the program shape is
unchanged at v0.1.0, the verification remains valid, and re-running
it under chelis 0.7.26 is a follow-up verification task.

Setup (one-time):

```sh
cd /path/to/chelis
python3 -m venv py/.venv
py/.venv/bin/pip install -e bindings/python
py/.venv/bin/pip install numpy
```

Working invocation against a Shoals-shaped Black-Scholes payoff:

```python
import math
import chelis
import numpy as np

# Discounted European-call payoff at maturity, vectorized over a
# tensor of terminal prices. Same arithmetic shape as
# Shoals.Pricing.bs_call_scalar's MC interior; the Python binding
# does not (yet) link external reefs, so the program is inlined.
PROGRAM = """def loss(
  st: tensor[5, f32],
  k_vec: tensor[5, f32],
  disc_vec: tensor[5, f32]
) -> tensor[f32] = mean(mul(relu(sub(st, k_vec)), disc_vec), 0)
"""

disc = math.exp(-0.05 * 1.0)
result = chelis.eval(PROGRAM, {
    "st": np.array([90.0, 100.0, 110.0, 120.0, 130.0], dtype=np.float32),
    "k_vec": np.array([100.0] * 5, dtype=np.float32),
    "disc_vec": np.array([disc] * 5, dtype=np.float32),
})
loss = next(r for r in result.roots if r.name == "loss")
# loss.value.data == (11.414753437042236,)
```

The reference harness lives at
`manual-gates/python_interop/test_call_price.py` and is committed
to this repo. Run from the Shoals root with the chelis-python venv:

```sh
/path/to/chelis/py/.venv/bin/python manual-gates/python_interop/test_call_price.py
```

See `manual-gates/python_interop/README.md` for setup details.
Expected output:

```
  check: score=1.0 typed_nodes=147
  eval: discounted mean payoff = 11.414753 (expected 11.414753)
  eval: all-OTM payoff = 0.0 (expected 0.0)
PASS: chelis Python binding evaluates a Shoals-shaped program
```

**Caveats** (binding limitations observed in this fix-up):

- The entrypoint must be named `loss` — the binding only surfaces
  `def loss` as a named EvalResult root.
- Patterns using `to_list` / `index` / `scalar_to_tensor` /
  `map`-over-list silently produce empty `roots`; the binding's
  evaluator covers vectorized tensor ops (`sub`, `mul`, `relu`,
  `mean`, etc.) reliably and host-list comprehensions only on the
  paths covered by `manual_phase3b.py`.
- The binding does not link multi-module reef packages — Shoals's
  full `bs_call_scalar` (which imports `Nautilus.Special.erfc`)
  cannot be evaluated through `chelis.eval(...)` until the binding
  acquires reef-aware loading. The harness above demonstrates the
  shape that does work today.

The existing all-paths upstream gate is at
`crates/chelis-python/tests/manual_phase3b.rs` and embeds its own
loss program; it remains the integration-test of record.

## License

MIT
