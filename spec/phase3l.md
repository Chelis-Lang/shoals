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
curves, stochastic processes, order books. Built on `chelis-std`, `nautilus`,
`coral`, and Shoreleave's published business calendars. Contains only
finance-specific logic.

**Prerequisite:** 3j (nautilus — distributions, optimization, SDE solvers), 3k (coral —
for loading/manipulating financial data), 3i (Std.Datetime for dates, Std.Decimal for cash
amounts).

### Key Design Decision: Instruments as Dicts, Not Closed ADTs

Financial instruments are open-ended — structuring desks invent new payoff formulas
continuously. Representing instruments as `Dict[String, f32]` (or `Dict[String, Column]`
for term structures) lets new instrument types be added as data without modifying the
Shoals source or releasing a new package version. The pricing function dispatches on a
key (e.g., `get(instrument, "type")`), not on a pattern match over a closed enum. This
also serves the AI coding story: an agent generating a new instrument definition writes
a dict literal (well within current LLM capability), not a new ADT variant (which
requires understanding the type system's extension points).

### API Stability Convention

Every function in Shoals' SKILL.md API surface tables carries an implicit stability
label per the cross-cutting design decision in
`chelis/spec/design/chelis_canonical_reference.md`: `stable` (signature frozen —
training-corpus safe) or `alpha` (signature may change — excluded or down-weighted).
Shoals ships with all public API marked `alpha` by default (and starts the
v0.0.1 version track post-reset; the pre-reset v0.1.0 / v0.7.x labelling
remains valid as historical release-history); promotion to `stable` waits
until pricing, risk, and curves pass the Phase 3l acceptance oracle and
the AD-through-instrument-dict story is validated end-to-end.

### Modules

| Module | Contents | Key Dependencies |
|---|---|---|
| `Shoals.Pricing` | Black-Scholes analytical, Heston semi-analytical, SABR calibration, Monte Carlo engines with variance reduction. Executable Greek coverage currently uses finite-difference checks against textbook references; grad-derived Greeks remain an alpha runtime path until the full pricing body is IR-lowerable under host-runtime `grad`. | `Nautilus.Distributions`, `Nautilus.Sde`, explicit keys, cumsum |
| `Shoals.Risk` | VaR (parametric, historical, Monte Carlo), CVaR/expected shortfall, stress testing, scenario generation | `Nautilus.Stats`, sort/quantile, explicit keys |
| `Shoals.Curves` | Yield curve construction (bootstrap from market instruments), interpolation (linear, cubic, Nelson-Siegel) | `Nautilus.Interpolation`, `Nautilus.Roots`, `Std.Datetime` |
| `Shoals.Date` / `Shoals.Tenor` / `Shoals.Schedule` | Exact-rational day counts, calendar-month and business-day tenors, and anchored schedules over Shoreleave market calendars | `Std.Datetime`, `Std.Datetime.Business`, `Shoreleave` |
| `Shoals.Stochastic` | SDE models: GBM, Heston, SABR, jump-diffusion. Path generation using cumsum + `Nautilus.Sde`. Variance reduction (antithetic, control variates). | `Nautilus.Sde`, explicit keys, cumsum, einsum |
| `Shoals.Orderbook` | Limit order book representation (price-priority sorted collections), matching logic, bid/ask spread computation, VWAP | Host-side collections, sort, `Std.Decimal` |

### What Makes This Work in Chelis

- **Greeks with scoped runtime coverage:** Shoals exposes grad-derived Greek functions
  for the intended AD surface, but executable properties currently use finite differences
  against textbook Black-Scholes references. The upstream `grad-eval-host-runtime`
  bug closed (chelis 2026-05-07) — host-runtime `grad` is supported in general — but
  Shoals's specific pricing body uses host-lane list combinators (`to_list` + `map` +
  `to_tensor`) and has not been verified end-to-end through `grad` under the new
  compiler. Full grad-vs-textbook runtime properties remain deferred pending that
  Shoals-specific verification (re-evaluated at the M6 Greeks discipline milestone in
  `docs/plan-quant-surface.md`).
- **Reproducible Monte Carlo:** Every simulation consumes an explicit affine key.
  Reconstructing the same root key from the same seed and following the same key
  derivations reproduces the same paths for fixed program and declared inputs.
- **Typed market data:** Named tensor dimensions like `tensor[instrument, scenario, f32]`
  prevent accidentally multiplying a `[portfolio, maturity]` matrix by a
  `[maturity, scenario]` matrix when the dimensions don't match.
- **Effect-tracked data provenance:** A function that reads from a market data feed has
  `IO` effect. A Monte Carlo function consumes an explicit key argument. The type
  system rejects key reuse; fresh draws require derived keys.

### Test Plan

- `Shoals.Pricing`: Black-Scholes price matches analytical formula (< 1e-10 error)
- `Shoals.Pricing`: Monte Carlo price converges to Black-Scholes analytical for
  vanilla European call. Current executable runtime coverage uses a 20K-path / 2%
  tolerance check; the 100K-path / 1% rigor tier is an explicit manual gate and is
  deferred under the host evaluator (last measured under chelis 0.7.6; not re-measured
  under 0.7.11 at M0).
- `Shoals.Pricing`: finite-difference Greek checks match analytical Black-Scholes
  Greeks. Grad-vs-textbook runtime coverage is deferred: the upstream host-runtime
  `grad` constraint resolved (chelis 2026-05-07) but the Shoals pricing body's
  host-lane list-combinator shape has not been verified end-to-end through `grad` —
  the focused upstream smoke continues to skip with a warning pending that
  Shoals-specific verification at M6.
- `Shoals.Risk`: Parametric VaR matches `Nautilus.Distributions.Normal.ppf` at standard
  confidence levels
- `Shoals.Curves`: Bootstrap reproduces known market instrument prices (< 1bp error)
- `Shoals.Stochastic`: GBM paths satisfy known statistical properties
  (mean = spot * exp(mu*T), variance matches theory)
- `Shoals.Orderbook`: matching logic satisfies price-time priority invariant
- Effect tracking: curve construction propagates `IO` for market data.
- Reproducibility: Monte Carlo tests reconstruct keys for exact replay and split
  keys for separate draws; negative tests reject keyless calls and key reuse.

**Reproducibility manifests.** The planned Chelis manifest command records
reproducibility metadata; key validity is enforced by the checker. Every random
Shoals export accepts a key, and multi-draw implementations derive distinct
child keys before sampling. Randomness carries no effect and has no seed handler.
The controlling
contracts are Chelis `spec/04-type-system.md` [04-LIN-9] and
`spec/05-risc-primitives.md` [05-OP-69] through [05-OP-72].

**Canonical finance properties.** Shoals ships with a `properties/` directory of
reference `@property` functions:

- `properties/pricing.ch` — put-call parity, price positivity, call bounded by spot,
  and optimized-vs-textbook price agreement
- `properties/greeks.ch` — finite-difference delta range/matches-textbook checks and
  non-negative finite-difference vega smoke; grad-vs-textbook runtime properties are
  deferred — host-runtime `grad` is now supported upstream (chelis 2026-05-07), but
  Shoals's pricing body's host-lane `to_list` + `map` shape has not yet been verified
  end-to-end through `grad`
- `properties/montecarlo.ch` — Monte Carlo price converges to analytic price as path
  count increases, variance decreases with path count
- `properties/noarbitrage.ch` — bull spread payoff non-negative, butterfly spread
  payoff non-negative

Convention (cross-cutting, applies to every domain shell): properties are co-located
with the implementation code they constrain — same repo, same package, version-
controlled together. Properties are NOT a separate shell. The intended future
`chelis fuzz src/` runner should run them all against the shipped exports once the
compiler-side property runner exists. In the
chelis 0.7.11 toolchain, Shoals exercises property bodies through ordinary `Test` functions
under `tests/`; `chelis fuzz` and first-class `@property` annotations are not part of
the default CI gate. Status of the underlying tool: `chelis fuzz` with first-class
`@property` annotations is **demo-blocking, scoped, ready to build** for the first
commercial CProof prospect. Full conventions: `chelis_trust_stack.md`,
`chelis_fuzz_spec.md`.

**Reference implementations.** Shoals' delivery scope now includes a `references/`
directory alongside `properties/`. Each standard model in `Shoals.Pricing`,
`Shoals.Stochastic`, `Shoals.Curves`, and `Shoals.Risk` ships a simple
textbook-formula reference (Black-Scholes call/put + Greeks, Heston, Vasicek, CIR,
vanilla Monte Carlo, VaR/CVaR via historical simulation). The optimized `src/`
implementation is verified against the reference by
`@property fn matches_textbook_reference(...)` in `properties/pricing.ch`. Customers
write their own references only for proprietary models. Full design:
`chelis_reference_implementations_spec.md` in the chelis monorepo.

### Acceptance Oracle

`cargo test -p chelis-cli --test phase3l_shoals_oracle phase3l_shoals_oracle -- --ignored --exact --nocapture`
— prices a European call option via Black-Scholes and Monte Carlo, verifies
convergence, and checks same-seed reproducibility. The Chelis-side focused
`phase3l_shoals_oracle_grad_greeks_match_analytic` manual smoke records the
current scoped status without paying the Monte Carlo oracle cost. The focused
smoke runtime-skips with a warning while the downstream pricing body contains
constructs the IR DAG path cannot execute.

**Effort:** medium. Black-Scholes + Monte Carlo + basic risk is the core; curves and
order book are smaller. The bulk of the work is composing existing primitives (`nautilus`
solvers, `coral` dataframes, tensor ops), not implementing new infrastructure.

---

## Forward-looking scope: verified-AD quant finance surface

The baseline above is the v0.0.1 starting point (post-version-track
reset; the originally-shipped surface was tagged v0.7.6 before the
reset). The full functional
surface and the structural AD commitments required for verified-AD-
for-quant-finance — distributions, dates, calendars, tenors,
multi-curve, vol surfaces, advanced SDE schemes, the pricer zoo,
Greek discipline, XVA, calibration, advanced risk measures, and the
type-level `Differentiable`/`Discrete` discipline — are specified in
the companion document `spec/shoals_quant_surface.md`. The
milestone-by-milestone implementation plan, agent-team allocation,
and red-team exit checkpoints live in `docs/plan-quant-surface.md`.

The companion spec is a Shoals-owned extension to §3l. When changes
to the extended scope land here, mirror them into the chelis monorepo
in the same change set per the Scaffolding Drift Rule in `AGENTS.md`.
