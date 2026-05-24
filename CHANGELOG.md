# Changelog

All notable changes to this project are documented here. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.2.0] — unreleased

M2 yield-curve slice. Extends `Shoals.Curves` with parametric forms,
extended interpolation, curve-kind metadata, and the standard
sensitivity-operation shape (parallel shift, key-rate shift, twist,
butterfly).

### Added

- **Curve kind discriminator.** `CurveKind = Ois | Ibor | Sofr |
  Sonia | Estr | Custom { label }`. Constructors `ois()`, `ibor()`,
  `sofr()`, `sonia()`, `estr()`, `custom_curve(label)`. Carried as a
  field on `YieldCurve`; preserved through every transformation.
  AD profile: `unsupported` (`Discrete`).
- **`yield_curve_tagged`** — alternative constructor that takes a
  `CurveKind`. `yield_curve_from_pillars` preserved for backward
  compatibility, defaults to `Custom { label: "untagged" }`.
- **`curve_kind`** — extracts the discriminator from a curve.
- **Curve operations:** `parallel_shift(curve, delta)`,
  `key_rate_shift(curve, pillar_idx, delta)`, `twist(curve,
  short_delta, long_delta)`, `butterfly(curve, wing_delta,
  body_delta)`, `scale_rates(curve, factor)`. Each is differentiable
  in its scaling parameters and preserves the curve kind. AD profile:
  `composed` over arithmetic.
- **`log_linear_rate_at`** — interpolates in log-space (standard for
  discount-factor curves). AD profile: `composed`.
- **`nss_rate(beta0, beta1, beta2, beta3, tau1, tau2, t)`** —
  Nelson-Siegel-Svensson parametric form for the instantaneous
  forward / zero rate. Six-parameter family that captures level,
  slope, curvature, and a second hump. AD profile: `composed`.
- **`tests/curves_ops.ch`** — 13 tests covering the new ops, curve
  kinds, log-linear interpolation, NSS limits (`t=0` and `t→∞`), and
  custom-label preservation.
- **`properties/curves.ch`** — `parallel_shift_uniformly_lifts`,
  `parallel_shift_zero_is_identity`, `twist_at_midpoint_is_average`,
  `key_rate_shift_localized`, `scale_rates_linear`.

### Changed

- `YieldCurve[n]` gained a `kind: CurveKind` field. The previous
  `yield_curve_from_pillars` constructor signature is preserved
  (defaults `kind` to `Custom { label: "untagged" }`); existing
  curves tests (4) still pass without modification.

### Deferred to a future milestone

- **Multi-instrument bootstrap** (deposits + FRAs + futures + swaps)
  with implicit-differentiation gradient through the solve. The
  existing `bootstrap_zero_from_par` covers the single-curve
  integer-year-spaced case; multi-instrument joint calibration via
  an IFT-hooked solver lands at a continuation milestone.
- **Cross-currency basis curves** — a `CurveBasis` type relating two
  curves under a basis swap is a sibling-shell follow-up.
- **Lint script** for the doc-string AD-profile convention (M2.5).

### AD verification status

- All new exports ship at `alpha`.
- `parallel_shift`, `key_rate_shift`, `twist`, `butterfly`,
  `scale_rates`, `log_linear_rate_at`, `nss_rate`, `discount_factor`
  are `AD: composed` over arithmetic + the underlying interpolator.
- `CurveKind` constructors and `curve_kind` are `AD: unsupported`
  (`Discrete` carriers).

### Verification

- `python3 scripts/run_local_gate.py` — exits 0.
- `chelis test tests/ --timeout 120 --jobs auto` — 112 passed, 0
  failed (was 99 at end of M1 red-team fix-up; +13 from
  `tests/curves_ops.ch`).

## [0.1.0] — unreleased

M1 foundations slice. Lands the substrate that subsequent milestones
build on: dates, calendars, tenors, market-data record types, and a
slice of the distributions surface.

### Added

- **`Shoals.Date`** — day-count conventions (`Act360`, `Act365`,
  `ThirtyThreeSixty`, `ActAct`), `year_fraction`, weekend detection,
  business-day rolling (`roll_following`,
  `roll_modified_following`, `roll_preceding`), tenor-stepped
  schedule generation. Built on `Std.Time`. M1-slice scope: holiday
  calendars are integrated separately via `Shoals.Calendar`; the
  `weekend_only` parameter on roll/business-day functions is a
  forward-compatible no-op until that integration lands at a future
  milestone. AD profile: `year_fraction` is `composed` over
  arithmetic; the rest are `unsupported` (`Discrete`).
- **`Shoals.Calendar`** — `Calendar { name, holidays }` records,
  `nyc_calendar()` and `ldn_calendar()` with 2025 holiday tables,
  `joint_calendar` combinator (holiday union), `weekend_only_calendar`,
  `empty_calendar`, `is_holiday`, `is_business_day`. Holiday tables
  are 2025-only at M1; multi-year + algorithmic generation lands at
  a future milestone. AD profile: all `unsupported` (`Discrete`).
- **`Shoals.Tenor`** — `Tenor { count, unit }` with `TenorUnit ∈ {Day,
  Week, Month, Year, Overnight, TomorrowNext, SpotNext}`,
  constructors (`days_n`, `weeks_n`, `months_n`, `years_n`,
  `overnight`, `tomorrow_next`, `spot_next`, `tenor`),
  `tenor_to_days`, `tenor_apply`. M1-slice scope: string parsing
  (`"3M"`, `"1Y"`, `"30Y"`, `"ON"`) is **deferred** pending an
  available `Std.String` primitive import path — calls landed in
  the agent's first attempt as `unbound variable: char_at`. The
  programmatic constructor surface covers the same payoffs without
  the parser dependency.
- **`Shoals.MarketData`** — `Side`, `Quote`, `Bar`, `Snapshot` record
  types with constructors and accessors; `snapshot_lookup` does
  linear scan over the quote list. AD profile: all `unsupported`
  (carrier types for non-differentiable metadata).
- **`Shoals.Distributions`** — `lognormal_pdf`, `lognormal_cdf`
  composed over `Nautilus.Distributions.normal_*` + arithmetic;
  `student_t_pdf` composed over `Nautilus.Special.log_gamma` +
  arithmetic; `student_t_cdf_approx` (Fisher-Cornish scale-only
  approximation — accuracy ~2.3% at `nu=5, x=2.0`, suitable for
  tail-region screening; marked `alpha`); `bvn_pdf` (bivariate
  normal density, no Cholesky needed). AD profile: all four are
  `composed`. Full N-dim multivariate normal via Cholesky and the
  remaining 7 distributions (gamma, beta, chi-squared, exponential,
  Poisson, uniform — pdf/cdf/inv_cdf/sample for each) are deferred
  to M1-continuation.
- **`references/{date,distributions}.ch`, `properties/{date,
  distributions,tenor,marketdata}.ch`** — textbook references and
  property functions per the trust-stack convention.
- **`tests/{calendar,date,distributions,marketdata,tenor}.ch`** — 48
  new tests covering the M1 surface.

### Changed

- `reef.toml`: `version` 0.0.1 → 0.1.0 (M1 ladder per
  `docs/plan-quant-surface.md`).
- File-naming convention: `Shoals.MarketData` lives in
  `src/marketdata.ch` (single-token lowercase per the chelis
  module-↔-file-path discipline observed in `src/orderbook.ch`).

### Deferred to M1-continuation

- **`Shoals.Rng`** — Sobol/Halton low-discrepancy sequences. The
  Joe-Kuo direction-number table is a 21201-entry data file that
  needs its own engineering pass; not in scope for the M1 first
  ship.
- **`Shoals.Date` schedule month-stepping** uses 30-day approximation
  per spec; calendar-aware month-stepping is a future M2 candidate.
- **`Shoals.Distributions`** remaining 7 univariate families and
  N-dim Cholesky-based MVN.
- **`Shoals.Tenor` string parsing** pending `Std.String` import
  resolution (`char_at` / `string_len` / `string_slice` / `to_int`
  primitives surface needs to be located in chelis-std).

### AD verification status

- All M1 exports ship at `alpha` stability.
- `year_fraction`, `lognormal_pdf`, `lognormal_cdf`, `student_t_pdf`,
  `student_t_cdf_approx`, `bvn_pdf` are tagged `AD: composed`
  (composition over verified Nautilus/chelis-std primitives) —
  promotion to verified-AD-stable label gates on the upstream
  AdjointTyping theorem closing per `spec/shoals_quant_surface.md`
  §3.2.
- Date/Calendar/Tenor/MarketData exports are tagged
  `AD: unsupported` (`Discrete` carriers; type-system rejection of
  `grad(..., wrt=date)` lands via doc-string + lint convention
  pre-D5).

### Verification

- `python3 scripts/run_local_gate.py` — exits 0.
- `chelis test tests/ --timeout 120 --jobs auto` — 96 passed, 0
  failed (was 48 at M0; +48 new tests in M1).

## [0.0.1] — unreleased

Version-track reset and dep cascade. Shoals's package version is now
on its own independent track; the prior 0.7.x labelling was
inherited from chelis's compiler version and overstated maturity.
Future minor bumps reflect Shoals's own milestone progression, not
the compiler pin.

### Changed

- `reef.toml`:
  - `version`: `0.7.6` → `0.0.1` (track reset; Shoals is pre-foundations).
  - `compiler`: `=0.7.6` → `=0.7.11` (matches the compiler pin
    declared by nautilus 0.7.13 / coral 0.7.13).
  - `nautilus`: `0.7.6` → `0.7.13`.
  - `coral`: `0.7.6` → `0.7.13`.
- `chelis-std` stays at `0.3.0` (compiler-bundled; only changes when
  a release moves it).
- Reformatted `src/curves.ch`, `src/orderbook.ch`, `tests/orderbook.ch`
  to the canonical formatter shape under chelis 0.7.11 (multi-line
  match expressions). No semantic change.

### Upstream status

- The `grad-eval-host-runtime` upstream bug closed 2026-05-07
  (chelis commit `412fa61`); the host runtime now supports `grad`
  via delegation to the C backend's lowering machinery. The Shoals
  deferral hedges in `properties/greeks.ch`, `README.md`, and
  `spec/phase3l.md` were tied to a two-part condition: (a) host
  runtime supports `grad` — now resolved; (b) Shoals's pricing body
  (which uses `to_list` + `map` over a host-lane list combinator)
  lowers cleanly under host-runtime `grad` — not verified at M0 and
  remains the gating condition. The hedge text is left intact at M0;
  re-evaluation belongs to a future milestone that actually
  exercises a grad-derived Greek property.
- `phase5_host_scalar_ad.md` remains a future performance
  optimisation, not a correctness blocker.

### Plan-scope context

This release implements **M0** of `docs/plan-quant-surface.md`. It
ships no new functional surface; subsequent milestones (M1+) build
out distributions, dates, calendars, tenors, multi-curve, vol
surfaces, advanced SDE, the pricer zoo, Greeks discipline, XVA,
calibration, and advanced risk per `spec/shoals_quant_surface.md`.

## [0.7.6] — 2026-05-11

Compiler and dependency alignment release. Tracks chelis 0.7.6,
chelis-std 0.3.0, nautilus 0.7.6, and coral 0.7.6. CI now consumes
released Chelis artifacts only, installs released Nautilus and Coral
packages, and runs the native Shoals suite as
`chelis test tests/ --timeout 120 --jobs auto`.

Validation recorded in `docs/testing_cutover_0.7.6.json`:

- `chelis test tests/ --timeout 120 --jobs auto`: 48 passed, 0 failed, 1:04.89
- `chelis test tests/ --timeout 120 --jobs 1`: 48 passed, 0 failed, 1:25.44

### Changed

- Replaced the stale blanket host-runtime AD limitation with scoped
  documentation: Shoals keeps executable Greek coverage on finite
  differences, while `Shoals.Pricing`'s grad-derived Greeks remain a
  deferred runtime path until the full pricing body is IR-lowerable by
  host-runtime `grad`.
- Scoped the default Shoals CI/local gate to formatter checks,
  `chelis reef build`, and the node-local runtime suite.

## [0.3.1] — 2026-05-06

Compiler-pin alignment release. Tracks chelis 0.6.0 → 0.6.1
(bootstrap-list patch), nautilus 0.6.0 → 0.6.1, and coral 0.6.0 →
0.6.1 (companion alignments). No source changes from 0.3.0 — only
version + pin bumps.

## [0.3.0] — 2026-05-06

Naming-convention release. Aligns shoals with the recorded style
guide in `chelis/spec/01-nomenclature.md`. Track-forward for
chelis 0.6.0 / chelis-std 0.2.0 / nautilus 0.6.0 / coral 0.6.0.

### Changed — `Nautilus.SDE` → `Nautilus.Sde` reference update

Two references in `spec/phase3l.md` updated from `Nautilus.SDE` to
`Nautilus.Sde` per nautilus's §6.2 Title-case-not-ALL-CAPS rename.
No other shoals source files referenced the renamed surfaces.

### Style guide — §7.1.1 model/algorithm sub-namespace prefixes recognized

The `bs_*` (Black-Scholes pricing), `mc_*` (Monte-Carlo pricing),
`gbm_*` (geometric Brownian motion), and `fd_*` (finite-difference
numerical method) prefixes used in `Shoals.Pricing`, `Shoals.Stochastic`,
and `Shoals.Properties.Greeks` are now formally recognized as §7.1.1
model/algorithm sub-namespaces in `chelis/spec/01-nomenclature.md`.
The chelis-lint `MODEL_NAMESPACE_PREFIXES` allowlist accepts them.
The closer-read step from the original cleanup brief settled on
"Outcome A" — keep the prefixes as load-bearing model-discrimination,
not as helper-marker violations.

(That phrasing — "load-bearing" — is the kind shoals's Black-Scholes
trader would find compelling. The author of these conventions
prefers more concrete framing: dropping the prefixes would conflate
distinct mathematical objects in a single function-name namespace.
Either phrasing leads to the same call.)

### Changed — pin bumps for the upstream rename chain

`reef.toml`:
- `compiler = "=0.5.0"` → `"=0.6.0"`
- `chelis-std = { version = "0.1.0" }` → `{ version = "0.2.0" }`
- `nautilus = { version = "0.5.0" }` → `{ version = "0.6.0" }`
- `coral = { version = "0.5.0" }` → `{ version = "0.6.0" }`

All four pins must move together — partial bumps fail the gate
because shoals's callers reach into the renamed surfaces in coral
and the renamed-module imports in nautilus.

### Style guide

Adheres to `chelis/spec/01-nomenclature.md`. Local `STYLE.md` is a
one-line pointer at the central guide.
