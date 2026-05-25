# Shoals Quant Surface — Implementation Plan

Milestone-structured plan to land the Shoals quant finance surface
specified in `spec/shoals_quant_surface.md`. Each milestone names its
work packets, suggested agent-team allocation, acceptance criteria
(correctness + AD verification status), and red-team exit checkpoint.

## Conventions

- **Spec-first.** Each milestone starts by ratifying the spec section
  it implements (`spec/shoals_quant_surface.md` §X) and ends by
  reconciling any spec drift back into that file (and the chelis
  monorepo's `chelis_phase3_plan.md` §3l per the Scaffolding Drift
  Rule).
- **Properties co-located.** Every new module ships `references/X.ch`
  (textbook formula), `properties/X.ch` (property functions that
  compare `src/` to `references/`), and `tests/X.ch` (exercises the
  property bodies as ordinary `Test` functions until `chelis fuzz`
  ships first-class `@property` support).
- **AD verification status is an acceptance criterion, not a
  description.** Every milestone's acceptance section enumerates each
  exported function's AD profile (see `AD profile classification`
  below). "Matches reference within tolerance" is correctness;
  "verified by composition over [list]" is verification. The plan
  separates the two.
- **Verified-AD vs functional-only milestones.** Each milestone is
  tagged with one of:
  - **`FN`** — ships functional surface; AD profile is unproven-
    primitive or unsupported. Useful immediately as a library; the
    verified-AD claim is aspirational pending upstream theorems.
  - **`FN+V`** — ships functional surface AND has all exports in
    `AD: composed` status once the upstream theorem this milestone
    depends on lands. The plan calls out the upstream dependency.
  - **`V-only`** — no new functional surface; migrates existing
    exports to verified status as upstream theorems close.
- **Red-team at every milestone exit.** Invoke the `redteam-exec`
  skill (a.k.a. `/red-team`) before closing the milestone. The skill
  spawns a fresh-context local subagent that runs the milestone's
  acceptance commands, probes adversarial edges, and reports
  findings. Do not declare a milestone complete without the
  redteam-exec record in the PR.
- **Agent-team allocation.** Each work packet is annotated with the
  recommended `Agent`-tool subagent_type and, when applicable, a
  parallelization hint. Independent packets fan out in a single
  message with multiple `Agent` calls.
- **Stability label.** Every new export lands at `alpha`. Promotion to
  `stable` happens module-by-module after the corresponding manual
  oracle in `phase3l_shoals_oracle_*` is green AND the AD profile
  is `composed` (not `unproven-primitive` or `unsupported`).
- **Native testing discipline.** Default per-PR gate is
  `chelis fmt --check && chelis reef build && chelis test tests/
  --timeout 180 --jobs auto`. Heavier oracles (multi-curve bootstrap,
  Heston QE, XVA smoke) run as manual gates at milestone exits via
  scripts under `scripts/manual_gates/`.
- **Manual-gate pattern.** Each named gate
  (`phase3l_shoals_oracle_*`) is a python script under
  `scripts/manual_gates/<gate_name>.py` that drives `chelis` from
  the command line, evaluates the acceptance criterion, prints a
  structured report to stdout, and exits 0 / 1. The convention:
  - Stdout final line is `PASS:` or `FAIL:` followed by the gate
    name and a one-sentence summary.
  - Stdout body is a JSON object with the measurements that backed
    the decision (tolerances, counts, sample sizes), so the report
    can be diffed across runs.
  - Failed runs print the offending case before the `FAIL:` line.
  - The PR attaches the captured stdout for each gate run at the
    milestone exit.
- **No calendar time estimates.** This plan describes scope, work-
  packet counts, and parallelization fan-out. It does not estimate
  calendar duration.

## AD profile classification (authoritative copy is `spec/shoals_quant_surface.md` §3.2)

Three buckets, recorded in SKILL.md and the in-source doc string:

- **`AD: composed`** — function is built entirely from primitives
  that are themselves verified-AD-correct (upstream LaCaDiLE proof,
  or deeper composition over such primitives). Verified-AD property
  holds by construction. No per-function proof obligation.
- **`AD: unproven-primitive`** — function is a leaf: specific RNG
  step, specific Sobol direction-number table, specific solver inner
  loop, specific characteristic-function inversion contour. AD
  correctness is assumed and FD-cross-checked in the property suite
  but is not proven. Each unproven primitive is enumerated in the
  Shoals trust manifest.
- **`AD: unsupported`** — function contains control flow, effects, or
  higher-order patterns that the upstream AD theorems don't yet
  cover. Marked alpha with an explicit pointer to the upstream
  blocker (chelis D1 / D3 / higher-order / linearity / etc.).

Promotion paths:
- `unproven-primitive → composed` when the leaf gets a LaCaDiLE
  proof.
- `unsupported → composed` (or `→ unproven-primitive`) when the
  relevant upstream theorem closes.

## Upstream dependencies tracked on the critical path

The verified half of "verified-AD-for-quant-finance" gates on
upstream work in the chelis monorepo and the LaCaDiLE proof project.
The plan names which milestones produce code whose verified-AD label
is gated on which upstream item:

| Upstream | Owner | Shoals milestones that flip from `FN` to `FN+V` when this lands |
|---|---|---|
| Control-flow AD (chelis D1, tracks chelis#199) | chelis monorepo | M5 (trees with early exercise), M7 (XVA exposure exercise decisions), M8 (sequential calibration if it includes regime switches) |
| AdjointTyping theorem | LaCaDiLE | M1 (foundations), M2 (curves) — first-order verified status |
| Higher-order AD theorem | LaCaDiLE | M3.4 (Dupire local vol), M6.2 (gamma/volga/vanna) |
| Effect-AD interaction (chelis D3) | chelis monorepo + LaCaDiLE | M5 (MC pricers), M7 (XVA paths), M9 (MC VaR) — any export over the `Random` effect |
| Linearity-AD interaction | chelis monorepo + LaCaDiLE | M6.3 (bucket sensitivities returning curve / surface tensors) |
| Differentiability typing (chelis D5) | chelis monorepo | M10 (type-system migration) |

Until each upstream item closes, the Shoals exports it gates carry
`AD: unsupported` per §3.2; their functional behavior ships and is
FD-cross-checked, but the verified-AD label does not apply. The
milestone acceptance criteria below enumerate the per-export status
under both pre- and post-upstream conditions.

## Dependency cascade (M0)

The reef chain is `chelis-std + nautilus + coral → shoals`.

Org-release snapshot at M0 planning, 2026-05-24
(`gh release list`; a later reader should re-run, not treat this as
live):

- chelis: v0.7.12 latest, v0.7.11 prior
- nautilus: v0.7.13 latest
- coral: v0.7.13 latest

M0 picks compiler `=0.7.11` rather than the absolute-latest
`=0.7.12` because **nautilus 0.7.13 and coral 0.7.13 ship with
compiler pin `=0.7.11`**. Reef pins are strict equality; matching
the shells' pin is necessary. The next compiler bump for Shoals will
follow whatever nautilus and coral choose to align with.

## Milestones

### M0 — Dep cascade, version reset, spec ratification

**Tag:** `V-only` (no new functional surface).
**Spec sections:** none (this milestone exists to set the foundation).
**Status (as landed):** completed. `reef.toml` pins
`compiler = "=0.7.11"`, `nautilus = "0.7.13"`, `coral = "0.7.13"`,
`version = "0.0.1"`. `reef.lock` refreshed; local gate green (48
tests). README + CHANGELOG + AGENTS.md updated. CI workflows
(`.github/workflows/ci.yml`, `release.yml`) re-pinned. Three source
files (`src/curves.ch`, `src/orderbook.ch`, `tests/orderbook.ch`)
reformatted to the canonical 0.7.11 shape (multi-line `match`); no
semantic change. M0.7 (monorepo mirror) intentionally deferred — the
new companion spec is a Shoals-owned extension; the monorepo §3l
can incorporate it later.

**Work packets:**

| # | Packet | Agent | Notes |
|---|---|---|---|
| M0.1 | Bump `reef.toml`: `compiler` pin (matches the compiler version nautilus/coral's latest ship with — `=0.7.11` at this M0), `nautilus = "0.7.13"`, `coral = "0.7.13"`. **Reset** `version` to `"0.0.1"` — Shoals's own track restarts from pre-foundations alpha; the prior 0.7.x labelling was inheriting chelis's number and overstating maturity. Subsequent milestones ladder up: M1 lands → 0.1.0, M2 lands → 0.2.0, etc. | direct | sequential |
| M0.2 | Refresh `reef.lock` via `chelis reef build`; resolve any breaking-change diagnostics from the bump. If new diagnostics surface (formatter drift, syntax changes), fix in place; do not silence. | direct | sequential |
| M0.3 | Run local gate: `python scripts/run_local_gate.py`. | direct | |
| M0.4 | Update `README.md` version strings (Toolchain table, Status section, dep list, Known-limitations heading); add CHANGELOG entry under a new `## 0.0.1 — unreleased` heading explaining the version-track reset; update `AGENTS.md` (== `CLAUDE.md` symlink) toolchain-pin section so the agent contract names the correct compiler version and the version-track-independence rule. | direct | parallel with M0.5 |
| M0.4b | **Update CI/release workflows** — `.github/workflows/ci.yml` env block (`CHELIS_TAG`, `CHELIS_VERSION`, `NAUTILUS_TAG`, `CORAL_TAG`) and `.github/workflows/release.yml` env block (same four plus `PACKAGE_VERSION`). **`PACKAGE_VERSION` tracks the Shoals package version, NOT the compiler version** — keep these decoupled per the version-track-independence rule in `AGENTS.md`. CI must move in the same change set as `reef.toml`; otherwise CI's "Verify toolchain version" step (`test "$(chelis --version)" = "chelis ${CHELIS_VERSION}"`) fails on the first PR after the bump. | direct | parallel with M0.4 |
| M0.5 | **Check whatever compiler M0.1 actually pinned** for the upstream `grad-eval-host-runtime` status. Pull from `chelis/spec/upstream-bugs/grad-eval-host-runtime.md` in the local checkout (or from the org remote if missing). The closure status determines whether the grad-vs-textbook deferral hedges in `properties/greeks.ch`, `README.md`, and `spec/phase3l.md` can be lifted. **Be careful:** "host runtime supports `grad`" and "Shoals's pricing body (with `to_list` + `map` over a host-lane list combinator) lowers under `grad`" are two different conditions; the first being closed does not imply the second. If unverified at M0, document the refined two-clause hedge in CHANGELOG and README. | Explore | parallel with M0.4 |
| M0.6 | Ratify `spec/shoals_quant_surface.md`; verify the `spec/phase3l.md` cross-reference at the bottom still resolves. | direct | |
| M0.7 | Mirror the spec extension into the chelis monorepo's `spec/design/chelis_phase3_plan.md` §3l per the Scaffolding Drift Rule (or open a tracking issue if monorepo write access is gated on a separate change set). | general-purpose | parallel with M0.4-M0.5 |

**Acceptance:** `python scripts/run_local_gate.py` exits 0; `reef.lock` committed; `README.md` pin lines, `AGENTS.md`/`CLAUDE.md` toolchain-pin section, and **both** `.github/workflows/*.yml` env blocks agree on the pinned compiler / shell / package versions; CHANGELOG `0.0.1` entry written explaining the version-track reset; spec extension ratified; mirror to chelis monorepo either landed or tracked as a follow-up.

**AD verification status:** unchanged from baseline. All exports remain in their pre-M0 buckets.

**Red team:** `/red-team` reviews the dep bump for missed test regressions, breaking-change diagnostics that were silently swallowed, stale `0.7.6` strings in docs/spec/CI/AGENTS.md, the version-reset rationale being defensible, and the four pinned-version sources (`reef.toml` ↔ `reef.lock` ↔ `README.md` ↔ `.github/workflows/`) agreeing.

---

### M1 — Foundations (data types + RNG + distributions)

**Tag:** `FN+V` (functional surface ships; verified-AD label per export gates on AdjointTyping theorem upstream).
**Spec sections:** §2.1, §2.2, §2.3, §2.4, §2.5, §2.6.
**Status (as landed):** first-ship slice complete at v0.1.0. Date,
Calendar, Tenor (programmatic constructors only — string parser
deferred pending `Std.String` import resolution), MarketData record
types, and a 4-function Distributions slice (lognormal pdf+cdf,
Student-t pdf+cdf approximation, bivariate-normal pdf) landed and
green: 96/96 tests pass. The Joe-Kuo Sobol direction-number table
(M1.2) and the remaining 7 univariate distribution families (full
M1.1) are explicit M1-continuation items per the CHANGELOG; the
v0.1.0 surface is the smallest credible foundation slice for M2 to
build on. See CHANGELOG `## [0.1.0]` for the full slice / deferral
breakdown.

**Work packets (parallelizable):**

| # | Packet | Agent | Output |
|---|---|---|---|
| M1.1 | `src/distributions.ch`: lognormal, Student-t, gamma, beta, chi-squared, exponential, Poisson, uniform — `pdf`, `cdf`, `inv_cdf`, `sample`. Extend `Nautilus.Distributions` where the upstream is missing; multivariate normal (Cholesky) and multivariate t live here. AD must flow through pdf and cdf wrt parameters. | general-purpose | references + properties + tests |
| M1.2 | `src/rng.ch`: Sobol with Joe-Kuo direction numbers, 1024-D minimum (table extends to 21201-D per spec §2.2); Halton, 50-D minimum. Mersenne / PCG go through the existing `Random` effect — no new generators added. Add control-variate, stratified-sampling, importance-sampling combinators alongside the existing antithetic. | general-purpose | references + properties + tests |
| M1.3 | `src/date.ch`: day-count conventions (ACT/360, ACT/365, 30/360 variants, ACT/ACT-ISDA, ACT/ACT-ISMA, Business/252), business-day rolling, schedule generation, year-fraction. `Date` is `Discrete` — type-system rejection of `grad(..., wrt=date)` lands via doc-string + lint convention pre-D5. | general-purpose | references + properties + tests |
| M1.4 | `src/calendar.ch`: built-in calendars (NYC, LDN, TYO, SYD, FRA, HKG) with named-holiday tables; joint-calendar combinator; user-registry hook. | general-purpose | references + properties + tests |
| M1.5 | `src/tenor.ch`: tenor parser ("3M", "1Y", "30Y", "ON", "TN", "SN") → integer-day shift relative to a reference. Overnight specials documented and tested. | general-purpose | references + properties + tests |
| M1.6 | `src/market_data.ch`: `Quote { side, value, timestamp, validity }`, tick-stream type (column-store via Coral), OHLCV bar aggregation, reference-data record types, snapshot type. | general-purpose | references + properties + tests |
| M1.7 | Update SKILL.md with new module tables; flag each export with its AD profile (`composed` / `unproven-primitive` / `unsupported`) per the inline classification above. Distributions sampling functions are `unproven-primitive` until the inv-cdf primitive gets a LaCaDiLE proof; Sobol direction-table lookup is `unproven-primitive` (the table itself is data); date / calendar / tenor are `unsupported` because they're `Discrete`. | general-purpose | doc |

**Parallelization:** spawn M1.1-M1.6 as a single message with six parallel `Agent` calls; M1.7 runs after they merge.

**Acceptance:**
- Module exports build under `chelis reef build`; each new module's `tests/` is green.
- New `properties/` bodies match references under finite-difference tolerance (per-module documented).
- **AD verification status table** in SKILL.md is populated for every new export. Expected distribution at M1 exit:
  - Univariate `pdf` / `cdf` / `inv_cdf`: `unproven-primitive` pending leaves get LaCaDiLE proofs (post-AdjointTyping).
  - Multivariate normal / t sampling: `unproven-primitive` (Cholesky is the leaf).
  - Sobol / Halton point generation: `unproven-primitive` (direction-number table is the leaf).
  - Variance-reduction combinators: `composed` over the underlying RNG + arithmetic.
  - Dates / calendars / tenors: `unsupported` (Discrete; type-system rejection enforced via doc-string + lint pre-D5).
  - Market-data types: `unsupported` (no AD intent).

**Red team:** `/red-team` exercises the distribution tail behavior, RNG dimensionality (does Sobol actually fill 1024-D? probe the Joe-Kuo bound), date edge cases (month-end roll, leap years, EOM convention), calendar joins, tenor "ON"/"TN"/"SN" overnight specials, quote-type ergonomics, and AD-profile annotations for false-positive `composed` claims.

---

### M2 — Yield curves and rate machinery

**Tag:** `FN+V` (functional surface ships; verified-AD label gates on AdjointTyping theorem AND linearity-AD interaction theorem for bucket-shape returns).
**Spec sections:** §2.7.
**Status (as landed):** first-ship slice complete at v0.2.0. Curve
operations (parallel/key-rate/twist/butterfly shifts, scale), curve
kind discriminator (OIS / IBOR / SOFR / SONIA / ESTR / Custom),
log-linear and Nelson-Siegel-Svensson interpolation all landed.
112/112 tests pass. Multi-instrument bootstrap (deposits + FRAs +
futures + swaps with IFT gradient through the joint solve, M2.4a +
M2.4b), cross-currency basis curves, and the M2.5 AD-doc-convention
lint script are explicit follow-ups per the CHANGELOG.

**Work packets:**

| # | Packet | Agent | Output |
|---|---|---|---|
| M2.1 | `src/curves.ch` extensions: log-linear interpolation, monotone cubic (Hyman, Steffen), Nelson-Siegel-Svensson parametric forms. | general-purpose | additions + properties |
| M2.2 | Multi-curve framework: OIS, IBOR, SOFR/SONIA/€STR risk-free curves, cross-currency basis. Types: `Curve { kind, pillars, values, interp }`. | general-purpose | new module section + properties |
| M2.3 | Curve operations: parallel shift, key-rate shift, twist, butterfly. Each differentiable in its scaling parameter. | general-purpose | additions + properties |
| M2.4a | **Multi-instrument bootstrap — forward correctness.** Deposits + FRAs + futures + swaps → joint curve solve. Nonlinear root-find using Nautilus solvers. The forward path must reproduce the input market instrument prices to <1bp on a 20-instrument calibration set. Manual gate: `phase3l_shoals_oracle_multi_curve_bootstrap_forward`. | general-purpose | additions + manual gate script |
| M2.4b | **Multi-instrument bootstrap — implicit-differentiation gradient.** Gradient-through-solve via the implicit-function-theorem hook (`Nautilus.Roots` IFT path). FD cross-check against a 20-instrument bootstrap and a curve-sensitive instrument. Manual gate: `phase3l_shoals_oracle_multi_curve_bootstrap_grad`. This is where the first verified-AD-through-a-solve work shows up in Shoals; treat the red-team accordingly. | general-purpose | additions + manual gate script |
| M2.5 | `Curve[Differentiable[f64]]` type for per-pillar sensitivity returns. Pre-D5: doc-string + signature-naming convention + lint enforcement. **Lint rule (new):** `scripts/lint_ad_doc_convention.py` reads each `src/*.ch` file, checks that any function whose signature mentions a parameter named `*_diff` or whose return type names a curve / surface carries a doc comment listing its differentiable parameters and AD profile bucket. Lint runs as part of the local gate. | general-purpose | doc + signature updates + lint script + lint wired into `scripts/run_local_gate.py` |

**Parallelization:** M2.1, M2.2, M2.3 fan out in parallel; M2.4a depends on M2.2 (curve type); M2.4b depends on M2.4a (forward must work before grad); M2.5 lands last (audits everything in M2).

**Acceptance:**
- `phase3l_shoals_oracle_multi_curve_bootstrap_forward` passes: OIS+SOFR bootstrap on a 20-instrument calibration set reproduces market prices to <1bp.
- `phase3l_shoals_oracle_multi_curve_bootstrap_grad` passes: AD-derived per-pillar sensitivities agree with bumped FD sensitivities to within FD step-size noise.
- Bucket sensitivities sum to the parallel-shift sensitivity within tolerance (already a property check, formalized here).
- Lint script runs clean; any function that violates the doc-string convention either has its doc updated or its signature corrected.
- **AD verification status table:** curve types, interpolators, and shift operations land in `composed` (built over verified arithmetic); the implicit-differentiation gradient hook (`M2.4b`) lands as `unproven-primitive` (the IFT hook in Nautilus is the leaf), pending an upstream proof of the IFT primitive.

**Red team:** `/red-team` exercises pathological calibration sets (near-collinear instruments, sub-1-bp price moves), monotone-cubic overshoot avoidance, and — critically for M2.4b — the implicit-differentiation gradient correctness via FD cross-check across a range of curve shapes. The red-team also audits the lint script for false negatives (functions that should carry the doc convention but don't).

---

### M3 — Volatility surfaces

**Tag:** `FN` (functional ships; M3.4 Dupire local vol cannot be differentiated through until upstream higher-order AD lands).
**Spec sections:** §2.8.
**Status (as landed):** first-ship slice complete at v0.3.0. SVI
parameterization (5 params), ATM / skew / parallel / smile shifts,
implied-vol-from-Black-Scholes solver via bisection (60 iterations,
1e-6 tolerance; round-trips to 1e-3). 123/123 tests pass. Deferred to
M3-continuation: SABR Hagan analytic (uses Bessel-like functions
that want a Nautilus.Special extension), Dupire local volatility
(blocked on upstream higher-order AD per spec §3.4), cubic-in-
log-moneyness × time interpolation.

**Work packets:**

| # | Packet | Agent | Output |
|---|---|---|---|
| M3.1 | `src/vol_surface.ch`: surface type (`tensor[strike, maturity, f32]` + interpolator), SABR (Hagan analytic), SVI (Gatheral), cubic-in-log-moneyness × time. | general-purpose | properties |
| M3.2 | Surface arithmetic: parallel shift, smile shift, term-structure shift; each differentiable in its scaling parameter. | general-purpose | properties |
| M3.3 | Implied vol solver: given option price → implied vol. Brent or Jäckel "Let's Be Rational"; implicit-differentiation hook for `d(impliedVol)/d(price)`. Manual gate: `phase3l_shoals_oracle_vol_surface_round_trip`. | general-purpose | properties + manual gate script |
| M3.4 | Local volatility (Dupire formula). **Cannot be differentiated through** until upstream higher-order AD lands per §2.8 + §3.4. Ships in `AD: unsupported`. SKILL.md entry and doc string include the warning: "Evaluating local volatility is supported; differentiating through it for sensitivities requires upstream higher-order AD (LaCaDiLE) and is unavailable today." Cross-check via finite-difference on a synthetic SVI surface. | general-purpose | properties + warning marker + lint check |

**Acceptance:**
- SVI / SABR fits reproduce a synthetic smile within configured tolerance.
- Implied-vol round-trip reproduces input price within 1e-8.
- Dupire local vol cross-checks FD on a smooth surface.
- **AD verification status table:**
  - SABR / SVI / cubic interpolation: `composed` (closed-form arithmetic).
  - Surface shifts: `composed`.
  - Implied vol solver: `unproven-primitive` (Brent / Jäckel inner loop is the leaf).
  - Dupire local vol: `unsupported` (gates on upstream higher-order AD).

**Red team:** `/red-team` probes butterfly arbitrage, calendar arbitrage, implied-vol solver behavior near deep OTM / deep ITM regimes, and confirms the Dupire local-vol warning is reachable from any caller about to chain it into a `grad(...)` (lint check).

---

### M4 — Stochastic processes

**Tag:** `FN+V` (functional ships; verified-AD label gates on effect-AD interaction theorem for any process exercised through MC).
**Spec sections:** §2.9.
**Status (as landed):** first-ship slice complete at v0.4.0. Merton
jump-diffusion with compensated drift (aggregate-jump Gaussian
approximation) and 2-asset correlated GBM via a hand-rolled 2x2
Cholesky helper. 137/137 tests pass. Heston QE (M4.1 with the pinned
Feller-violation stress config), SABR path simulation (M4.2),
Hull-White 1F/2F (M4.4), LMM (M4.5), HJM (M4.6), and Kou
double-exponential jumps are explicit M4-continuation items.

**Process-pricer AD pairing matrix (spec-pinned in §3.3) governs what each process expects from the pricer side; M5 obeys the same matrix.**

**Work packets (parallelizable across processes):**

| # | Packet | Agent | Output |
|---|---|---|---|
| M4.1 | Heston with Andersen QE scheme; full-truncation Euler fallback. Variance positivity property. **Pinned stress config (per spec §2.9):** `kappa = 0.5`, `theta = 0.04`, `sigma = 1.0`, `rho = -0.9`, `v0 = 0.04`, `T = 5y`, `dt = 1/52`, 100k paths — Feller condition violated. Manual gate: `phase3l_shoals_oracle_heston_qe`. | general-purpose | references + properties + manual gate script |
| M4.2 | SABR path simulation (in addition to Hagan analytic from M3). | general-purpose | references + properties |
| M4.3 | Jump-diffusion: Merton lognormal jumps, Kou double-exponential, abstract Lévy template. | general-purpose | references + properties |
| M4.4 | Hull-White 1F and 2F (Gaussian short-rate); closed-form bond pricing as reference. | general-purpose | references + properties |
| M4.5 | Libor Market Model with shifted-lognormal drift. | general-purpose | references + properties |
| M4.6 | HJM framework with the no-arbitrage drift. | general-purpose | references + properties |
| M4.7 | Multi-asset correlated GBM via Cholesky from `Shoals.Distributions`. | general-purpose | references + properties |

**Parallelization:** M4.1, M4.4, M4.7 first (most independent); M4.2, M4.3 next; M4.5 and M4.6 after the IR framework is shaken out.

**Acceptance:**
- Each process matches its closed-form or characteristic-function reference for pricing instruments where one exists.
- Heston QE preserves variance positivity over 100k paths on the pinned stress configuration.
- **AD verification status table:** every process's path-generation function lands as `unsupported` until effect-AD upstream lands (each process runs over the `Random` effect). Closed-form references that don't touch `Random` land as `composed`. The matrix in §3.3 is the source of truth for what each process pairs with on the pricing side.

**Red team:** `/red-team` probes Feller-condition violation in Heston (does QE actually keep variance non-negative under the pinned stress config?), Kou tail behavior, Hull-White negative-rate handling, LMM drift in long-dated tenors, and audits that every process's AD profile annotation matches the matrix in §3.3.

---

### M5 — Option pricing primitives

**Tag:** `FN` (functional ships; verified-AD label gates on multiple upstream theorems per pricer family — see matrix in §3.3).
**Spec sections:** §2.10.
**Status (as landed):** first-ship closed-form slice complete at
v0.5.0. Bachelier (normal-underlying), Black (forward-priced),
Garman-Kohlhagen (FX), Margrabe (exchange option) all landed with
put-call parity and BS-reduction identity checks. 148/148 tests
pass. Tree methods (M5.2), PDE methods (M5.3), Longstaff-Schwartz
(M5.4), and Fourier methods (M5.5) are explicit M5-continuation
items per the CHANGELOG.

**Work packets (parallelizable across pricer families):**

| # | Packet | Agent | Output |
|---|---|---|---|
| M5.1 | Closed-form: Bachelier, Black (forward), Garman-Kohlhagen (FX), Margrabe, Margrabe-Stulz. | general-purpose | references + properties |
| M5.2 | Tree methods: CRR binomial, Tian, Jarrow-Rudd binomial, trinomial. American exercise via backward induction. AD-through-early-exercise gates on chelis D1 (control-flow AD). | general-purpose | references + properties |
| M5.3 | PDE methods: Crank-Nicolson with Rannacher smoothing; ADI for 2-D. **AD approach (spec-pinned in §2.10):** reverse-mode AD through the time-stepping loop with adjoint-PDE substitution at the linear-solve step (no naive AD-through-iterative-solve). | general-purpose | references + properties |
| M5.4 | Longstaff-Schwartz for American MC. **AD approach (spec-pinned in §2.10):** regression coefficients treated as outputs of an implicit problem; gradients flow through the normal-equations optimum, not through the regression refit. Pathwise where the optimal-exercise policy is locally constant; LR Greeks on the policy boundary. | general-purpose | references + properties |
| M5.5 | Fourier methods: Heston char-fn pricing (Lewis or Lipton inversion); Carr-Madan FFT. | general-purpose | references + properties |

**Acceptance:**
- Each pricer matches the appropriate analytic limit or high-accuracy alternative (FFT vs MC Heston, trinomial vs PDE, etc.).
- **AD verification status table** — per the matrix in §3.3:
  - Closed-form (M5.1): `composed` (analytic arithmetic) for the smooth payoffs.
  - Trees (M5.2): `unsupported` until D1 lands (control-flow over the early-exercise comparison); functional ships.
  - PDE (M5.3): `unproven-primitive` (the adjoint-PDE primitive is a leaf) until that primitive gets a LaCaDiLE proof.
  - LSM (M5.4): `unproven-primitive` (IFT through the normal equations) plus `unsupported` for the policy-boundary LR path.
  - Fourier (M5.5): `unproven-primitive` (characteristic-function inversion is a leaf).

**Red team:** `/red-team` probes American early-exercise boundary behavior, PDE convergence at the payoff discontinuity (Rannacher matters), Longstaff-Schwartz basis-overfit on small sample sizes, FFT damping-parameter sensitivity, and the AD-approach-vs-implementation consistency for M5.3 / M5.4 (the spec pin is on the algorithm; the red-team checks the code matches).

---

### M6 — Greeks discipline

**Tag:** `FN+V` partial — first-order Greeks land verified once AdjointTyping closes; second-order gates on higher-order AD theorem.
**Spec sections:** §2.11.
**Status (as landed):** first-ship slice complete at v0.6.0.
First-order FD Greeks (delta/vega/rho/theta, call+put), second-order
FD (gamma/vanna/volga, marked alpha), analytic-Greek references for
cross-check, and pathwise / LR dispatchers on a smooth-call and
digital-call example. 165/165 tests pass. Bucket sensitivities
(M6.3 — `curve_delta`, `surface_vega` returning shape-preserving
sensitivity objects) are explicit M6-continuation items; functional
implementation depends on linearity-AD upstream. `grad`-derived
Greeks (the AD-composed alternative to FD) deferred until the
Shoals pricing body's host-lane composition is verified end-to-end
through `grad`.

**Work packets:**

| # | Packet | Agent | Output |
|---|---|---|---|
| M6.1 | `src/greeks.ch`: first-order constructors (`delta`, `vega`, `rho`, `theta`) wrapping `grad(...)` with parameter selection. **Functional surface** ships; verified-AD label flips when AdjointTyping closes upstream and the underlying pricer is `composed`. | general-purpose | properties |
| M6.2 | Second-order constructors: `gamma`, `volga`, `vanna`. Always `unsupported` until upstream higher-order AD lands; FD cross-check in the meantime. SKILL.md + doc string flag this. | general-purpose | properties |
| M6.3 | Bucket sensitivity API: `curve_delta` returns `Curve`-shaped sensitivity; `surface_vega` returns `Surface`-shaped sensitivity. Verified status gates on linearity-AD upstream. Manual gate: `phase3l_shoals_oracle_greeks_bucket`. | general-purpose | properties + manual gate script |
| M6.4 | Pathwise vs likelihood-ratio dispatch: `pathwise_greek` and `lr_greek` constructors. Worked examples on a digital option and a continuous payoff. | general-purpose | properties |
| M6.5 | Mode-disclosure annotations in SKILL.md: per-export, document reverse vs forward preference. | general-purpose | doc |

**Acceptance:**
- Bucket-delta sums to parallel-shift delta within tolerance.
- LR Greek for a digital option matches the analytic formula.
- FD cross-check on second-order Greeks for vanilla BS within 1% (slack accounts for FD step-size error).
- **AD verification status table:**
  - First-order Greek constructors (M6.1): `composed` *only* when paired with a `composed` pricer AND AdjointTyping has closed upstream. Until then: `unproven-primitive` (depends on `grad(...)` semantics).
  - Second-order constructors (M6.2): `unsupported` (gates on higher-order AD).
  - Bucket sensitivities (M6.3): `unsupported` (gates on linearity-AD) but functional output is correct per the FD cross-check.
  - Pathwise / LR dispatchers (M6.4): `composed` when paired with `composed` pricers; otherwise inherits the worst bucket of the chain.

**Red team:** `/red-team` probes the pathwise-vs-LR dispatch on a barrier option (should use LR at the barrier, pathwise elsewhere), bucket-sensitivity dimensionality (does it carry the right `Curve` shape?), the mode-disclosure honesty in SKILL.md, and audits each Greek's AD profile against its underlying pricer's profile (a `composed` Greek over an `unproven-primitive` pricer is a label violation).

---

### M7 — XVA

**Tag:** `FN` shipping; verified-AD label gates on effect-AD AND (for portfolios with exercise decisions) control-flow AD.
**Spec sections:** §2.12.
**Status (as landed):** first-ship core slice complete at v0.7.0.
Constant-hazard survival / default probability, constant-rate
discount factor, EPE/ENE aggregators, pointwise 2-deal netting, CVA
and DVA aggregators over a discrete time grid. 179/179 tests pass.
Stochastic hazard / term-structured CDS bootstrap, FVA, KVA,
wrong-way risk, multi-CSA netting, and stochastic recovery are
explicit M7-continuation items per the CHANGELOG.

**Work packets:**

| # | Packet | Agent | Output |
|---|---|---|---|
| M7.1 | `src/xva/exposure.ch`: exposure simulation `tensor[path, time, deal, f32]`. Memory-staging discipline for long horizons. | general-purpose | properties |
| M7.2 | `src/xva/netting.ch`: CSA netting, threshold / MTA / IA handling, variation- and initial-margin haircuts. | general-purpose | properties |
| M7.3 | `src/xva/default.ch`: credit curves from CDS quotes, survival probability term structure, deterministic and stochastic recovery. | general-purpose | properties |
| M7.4 | `src/xva/aggregation.ch`: CVA, DVA, FVA, KVA aggregations. Wrong-way risk via correlated default × exposure paths. Manual gate: `phase3l_shoals_oracle_xva_smoke` (CVA on a netted 2-deal portfolio matches an analytic benchmark). | general-purpose | properties + manual gate script |
| M7.5 | XVA sensitivity surface: gradients w.r.t. market parameters. AD-vs-bumping cross-check on a 2-deal portfolio. | general-purpose | properties |

**Acceptance:**
- CVA on a netted 2-deal portfolio matches an analytic benchmark.
- XVA gradients via AD agree with bumped FD gradients to within MC noise on a 50k-path run.
- **AD verification status table** — explicit per the critique:
  - Pre-upstream (no effect-AD or control-flow AD landed): every XVA-related export is `AD: unsupported`. The acceptance criterion above ("AD agrees with bumped FD to within MC noise") establishes functional correctness, NOT verification. SKILL.md states explicitly: "XVA sensitivities are functional and FD-cross-checked at this milestone; the verified-AD label is unavailable until effect-AD (chelis D3) and control-flow AD (chelis D1) close upstream."
  - Post-upstream (D1 + D3 closed, plus the underlying pricers verified): XVA exposure paths become `composed` over the verified path-generation primitives; netting is `composed` over verified arithmetic; default modeling is `composed` over verified credit-curve primitives; XVA aggregation is `composed`. The verified-AD label flips on the SKILL.md entries at the upstream-tracking milestone (M10 or earlier as theorems land).

**Red team:** `/red-team` probes netting under thresholds (does MTA preserve linearity?), recovery-rate stochasticity, wrong-way risk correlation handling, AD stability through long-horizon path products, and explicitly verifies that the SKILL.md AD-status entries match the upstream gate (no premature `composed` claims).

---

### M8 — Calibration

**Tag:** `FN+V` (functional ships; verified-AD label gates on AdjointTyping and on the underlying pricers' status).
**Spec sections:** §2.13.
**Status (as landed):** first-ship slice complete at v0.8.0.
Weighted-LS / WL1 / vega-weighted residuals, SSE loss,
single-parameter bound-clamped LM step. 201/201 tests pass. BFGS
with bounds, SQP, multi-target combinator, sequential pipeline, and
full vectorized LM are explicit M8-continuation items per the
CHANGELOG.

**Work packets:**

| # | Packet | Agent | Output |
|---|---|---|---|
| M8.1 | `src/calibration/loss.ch`: weighted-LS, weighted-AD, mixed; vega-weighted as the default for vol-surface fits. | general-purpose | properties |
| M8.2 | `src/calibration/lm.ch`: bound-constrained Levenberg-Marquardt extending `Nautilus.CurveFit`. Manual gate: `phase3l_shoals_oracle_calibration_smoke`. | general-purpose | properties + manual gate script |
| M8.3 | `src/calibration/bfgs.ch`: bound-constrained BFGS. | general-purpose | properties |
| M8.4 | `src/calibration/sqp.ch`: SQP for nonlinear constraints (vol-surface no-arbitrage constraints). | general-purpose | properties |
| M8.5 | Multi-target combinator: fit one model to many instruments at once with shared parameters. | general-purpose | properties |
| M8.6 | Sequential pipeline: chain curves → surfaces → exotic params; implicit-differentiation at the optimum threads gradients between stages. | general-purpose | properties |

**Acceptance:**
- SABR fit to 5-strike smile converges to documented tolerance.
- Sequential calibration pipeline (curves first, then SVI on top) produces gradient-correct downstream sensitivities (FD cross-check).
- **AD verification status table:**
  - Loss functions (M8.1): `composed` (arithmetic).
  - LM / BFGS / SQP iteration: `unproven-primitive` (each optimizer's update step is a leaf).
  - Multi-target combinator: `composed` over the underlying optimizer.
  - Sequential pipeline: `unproven-primitive` (the IFT at each stage's optimum is a leaf).

**Red team:** `/red-team` probes optimizer behavior near bound constraints, ill-conditioned Jacobians, and the implicit-function gradient correctness across the sequential pipeline.

---

### M9 — Advanced risk measures

**Tag:** `FN` (functional ships; verified-AD label gates on effect-AD for any MC-based VaR / ES).
**Spec sections:** §2.14.
**Status (as landed):** first-ship slice complete at v0.8.0. MC VaR
/ ES (alias to historical quantile / tail-mean on MC-simulated
losses), FRTB-IMA 97.5% ES helper, linear scenario PnL grid,
Kupiec POF backtest statistic. 201/201 tests pass.
Christoffersen CC, Acerbi-Szekely ES backtest, sensitivity-based
VaR (gates on M6.3 bucket sensitivities), and the 250-day FRTB-IMA
zone classifier are explicit M9-continuation items per the
CHANGELOG.

**Work packets:**

| # | Packet | Agent | Output |
|---|---|---|---|
| M9.1 | MC VaR: simulate portfolio paths and quantile the loss distribution. | general-purpose | properties |
| M9.2 | Expected shortfall under Basel FRTB conventions (97.5% ES). Implementation targets FRTB-IMA per spec §2.14. | general-purpose | properties |
| M9.3 | Scenario analysis: PnL across a parameter grid; canonical stress scenarios (2008, COVID, rate-hike). | general-purpose | properties |
| M9.4 | Backtesting infrastructure: Kupiec POF, Christoffersen CC, Acerbi-Szekely ES. Match Basel FRTB-IMA: 250-day rolling window, green/yellow/amber zones, 97.5% ES model-eligibility test. Manual gate: `phase3l_shoals_oracle_es_backtest`. | general-purpose | properties + manual gate script |
| M9.5 | Sensitivity-based VaR: delta-gamma approximation using bucket sensitivities from M6. | general-purpose | properties |

**Acceptance:**
- Kupiec / Christoffersen tests pass on a known DGP at documented confidence levels.
- Sensitivity-based VaR matches full revaluation VaR within tolerance on a smooth portfolio; diverges in the documented way on a non-smooth portfolio.
- ES backtest matches the Basel FRTB-IMA zone classification on the reference DGP.
- **AD verification status table:**
  - Parametric / historical VaR / CVaR: `composed` (arithmetic + quantile).
  - MC VaR: `unsupported` (gates on effect-AD); functional output is correct.
  - Backtest statistics: `composed` (pure arithmetic over historical PnL).
  - Sensitivity-based VaR: inherits the worst bucket of its bucket-sensitivity inputs (M6.3).

**Red team:** `/red-team` probes backtest statistic distributions under finite-sample sizes, ES estimator bias near the tail, sensitivity-based VaR breakdown on a barrier-option-heavy portfolio, and FRTB-IMA zone classification edge cases.

---

### M10 — Verified-AD migration (post-upstream)

**Tag:** `V-only`.
**Spec sections:** §3.1, §3.2.

**Work packets (run as upstream theorems close — milestones may be interleaved):**

| # | Packet | Agent | Output |
|---|---|---|---|
| M10.1 | When AdjointTyping closes: audit every Shoals export with `AD: unproven-primitive` on a first-order AD path. Promote to `composed` where the proof composes; document any leaves that still need targeted proof effort. | Explore + general-purpose | report + SKILL.md updates |
| M10.2 | When chelis D5 (Differentiability typing) closes: migrate signatures from doc-string convention to the upstream `Differentiable` / `Discrete` type annotations. Mechanical refactor; no semantic change. Lint script from M2.5 can be retired (subsumed by the type checker). | general-purpose | code change |
| M10.3 | When chelis D1 (control-flow AD) closes: promote tree pricers (M5.2), LSM policy-boundary path (M5.4), and XVA exposure-with-exercise paths (M7) from `unsupported` to `composed` (or `unproven-primitive` if any leaves remain). | general-purpose | SKILL.md updates + tests |
| M10.4 | When chelis D3 (effect-AD) closes: promote all `Random`-effect MC pricers, MC VaR, and XVA paths. | general-purpose | SKILL.md updates + tests |
| M10.5 | When higher-order AD theorem closes: promote second-order Greeks (M6.2) and Dupire local vol (M3.4). | general-purpose | SKILL.md updates + tests |
| M10.6 | When linearity-AD theorem closes: promote bucket sensitivities (M6.3). | general-purpose | SKILL.md updates + tests |
| M10.7 | Refresh SKILL.md's verified-AD subset table — the running list of exports with `AD: composed`. This is the verifiable claim Shoals makes to the C Proof pitch: this list, not "Shoals supports AD." Flip stability label to `stable` for any export now fully `composed` AND green on its acceptance oracle. | direct | doc + SKILL.md |

**Acceptance:** every Shoals export carries one of the three AD bucket labels in SKILL.md; the SKILL.md "verified-AD subset" table is non-empty and exactly enumerates what is verified by composition over verified primitives. No export claims `composed` while transitively depending on an `unproven-primitive` or `unsupported` element.

**Red team:** `/red-team` looks for false-positive `composed` claims (composition over an unproven leaf that should propagate its alpha status upward) and any export whose AD profile is inconsistent with its callees.

---

## Cross-cutting tracks (run in parallel with M1-M9)

- **Upstream-tracking watch.** A standing task that monitors chelis monorepo phases D1, D3, D5, and the LaCaDiLE theorems (AdjointTyping, higher-order AD, linearity-AD). **Owner:** the orchestrator (the human running the agent team), not an agent — these are project-level dependencies that need human judgment on when to trigger an M10 packet. **Triggers beyond cadence:** any GitHub event on `Chelis-Lang/chelis` matching `phase D1`, `phase D3`, `phase D5`, or `LaCaDiLE` should ping the orchestrator. Cadence-only check otherwise. When a theorem closes, the orchestrator dispatches the corresponding M10 packet.
- **Skill-set sync.** Per the Scaffolding Drift Rule, when upstream chelis changes a shared skill (`redteam-exec`, `spec-sync`, `phase-gate`, `backend-numerics`, `example-corpus`, `cli-surface`), mirror into Shoals in the same change set. Owner: whichever agent / human is doing the change.
- **Documentation cadence.** README.md and SKILL.md regenerate at each milestone exit. The `README.md` "Modules" table reflects newly-shipped surface; SKILL.md API tables carry the AD profile and mode-disclosure annotations.

## Effort characterization

Bounded but substantial — volume, not novelty. Each work packet is a function or small file with established formulas; the integration work (composition, AD threading, property honesty) is the cost concentration. Parallelization fan-out is real: M1, M4, M5, M7 each support 5-7 packets running in parallel. M2 has the longest dependency chain (M2.4a → M2.4b → M2.5); M10 packets are unblocked individually as theorems land upstream. No calendar estimates per the standing user instruction.
