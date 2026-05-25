# Changelog

All notable changes to this project are documented here. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Upstream

- `Chelis-Lang/chelis` PRs [#234](https://github.com/Chelis-Lang/chelis/pull/234) (rule removal) and [#235](https://github.com/Chelis-Lang/chelis/pull/235) (release-bump) landed; chelis `v0.7.17` cut. The `module-pascal-components` (§6.3) lint rule and its `KNOWN_SINGLE_WORDS` allowlist are now **deleted upstream**, not just demoted to advisory — confirmed by smoke-test against the released `v0.7.17` linux tarball: rule absent from `chelis lint --list`; module declarations `Probes.Calendar` and `Probes.Calibration` lint clean with zero findings.
- The v0.8.1 tactical renames (`Shoals.Calendar` → `Shoals.HolidayCal`, `Shoals.Calibration` → `Shoals.ModelFit`) remain in effect for v0.8.1 because Shoals still pins compiler `=0.7.11` (matching nautilus 0.7.13 / coral 0.7.13). The rename revert is queued for the next dep cascade pass: once nautilus and coral bump their compiler pin past 0.7.11, Shoals will follow and the original module names can return as a near-mechanical refactor. The function-level renames (`date_roll_*`, `md_bar_*`, `vs_*`) are per-rule §7.1 lint compliance and stay regardless.

## [0.8.1] — unreleased

Lint-clean pass. Surface and behavior unchanged; only style /
naming changes plus a gate-step addition. All 201 tests continue to
pass.

### Changed

- **`chelis lint --check` wired into the local + CI gate.** Step 2
  of `scripts/run_local_gate.py` (renumbered to 4 steps) and a new
  `chelis lint --check` step in `.github/workflows/ci.yml` block on
  any lint violation. Going forward, prefer-pipe-operator,
  redundant-linearity-call, prefix-namespace, module-pascal, and
  related lint guidance from `crates/chelis-lint/` is enforced on
  every PR.
- **Module renames** (per `module-pascal-components` §6.3 lint —
  long single-word module names that aren't on the upstream
  recognized-single-word allowlist):
  - `Shoals.Calendar` → `Shoals.HolidayCal` (file
    `src/calendar.ch` → `src/holidaycal.ch`; tests file likewise).
  - `Shoals.Calibration` → `Shoals.ModelFit` (file
    `src/calibration.ch` → `src/modelfit.ch`).
  Each rename preserves all exported function names; the only
  source-incompatible delta is the module-path import.
- **Function renames** (per `prefix-namespace` §7.1 lint — function
  prefixes must match the module's domain shorthand or be a
  registered `MODEL_NAMESPACE_PREFIXES` model marker per §7.1.1):
  - `Shoals.Date`: `roll_following`, `roll_modified_following`,
    `roll_preceding` → `date_roll_following`,
    `date_roll_modified_following`, `date_roll_preceding`.
  - `Shoals.MarketData`: `bar_open`, `bar_high`, `bar_low`,
    `bar_close`, `bar_volume` → `md_bar_open`, `md_bar_high`,
    `md_bar_low`, `md_bar_close`, `md_bar_volume`.
  - `Shoals.VolSurface`: `svi_total_variance`, `svi_implied_vol`,
    `svi_shift_atm`, `svi_shift_skew` → `vs_total_variance`,
    `vs_implied_vol`, `vs_shift_atm`, `vs_shift_skew`. (`svi_` is a
    legitimate model namespace per spec §7.1.1; a future upstream
    addition to chelis-lint's `MODEL_NAMESPACE_PREFIXES` would
    allow restoring the model-prefixed names.)
  - Properties renamed in lockstep: `svi_total_variance_nonneg_for_atm`
    → `vs_total_variance_nonneg_for_atm`, `bar_*` → `md_bar_*`, etc.
- **`src/orderbook.ch` idiomatic-rewrite**: pipe-operator (`|>`)
  introduced at the `insert_desc` / `insert_asc` / `bid_ask_spread`
  / `best_bid` / `best_ask` sites; extracted `nan_f32()` helper for
  the previously-inlined `div(cast(0.0, f32), cast(0.0, f32))`
  NaN-generator to keep the pipe form clean.
- **Auto-fixable `prefer-pipe-operator` and `redundant-linearity-call`
  warnings cleared across `src/calibration.ch`, `src/xva.ch`,
  `references/date.ch`, `references/vasicek.ch`** via `chelis lint
  --fix`. The fix was followed by `chelis fmt --inplace` to settle
  the formatter on the new canonical form.

### Note on the upstream allowlist gap

`Calendar` and `Calibration` are correct English single words that
should plausibly be in the chelis-lint `KNOWN_SINGLE_WORDS` table
under `chelis/crates/chelis-lint/src/rules/module_pascal_components.rs`.
Adding them upstream (along with a §6.3 nomenclature-spec cross-ref)
is the cleaner long-term fix and would allow restoring the original
names. The local rename is a tactical change to make
`chelis lint --check` pass under the current 0.7.11 binary; the
file layout and module-path rename apply only at the import-statement
level (no behavioral change).

### Verification

- `python3 scripts/run_local_gate.py` — exits 0 across all four
  steps (fmt-check, lint-check, reef-build, test).
- `chelis lint --check src/ properties/ references/ tests/
  manual-gates/` — zero findings of any severity.
- `chelis test tests/ --timeout 120 --jobs auto` — 201 passed, 0
  failed (unchanged from v0.8.0).

## [0.8.0] — unreleased

Bundles the M8 calibration and M9 extended-risk slices. Concludes
the M0-M9 sweep on Shoals's planned milestone surface; M10
(verified-AD typing migration) is upstream-gated and not part of
this release.

### Added — M8 calibration

- `Shoals.Calibration` module (`src/calibration.ch`):
  - `clamp_to_bounds(x, lo, hi)` — bound projection for constrained
    optimization steps.
  - `weighted_squared_residuals(observed, predicted, weights)` and
    `weighted_absolute_residuals` — per-point WLS and WL1 residual
    contributions, returned as a tensor for downstream aggregation.
  - `vega_weighted_squared_residuals(observed, predicted, vegas)` —
    standard vega-weighted variant for vol-surface calibration;
    weights are `1/vega²` (zero-vega protected by branching to
    zero weight).
  - `sse_loss(residuals)` — sum-of-residuals scalar loss.
  - `lm_bounded_step_scalar(jtj, jtr, lambda, current, lo, hi)` —
    single-parameter Levenberg-Marquardt update with damping
    `(jtj + lambda)` and bound projection on the proposed step.
    Returns the clamped new parameter value.
- `tests/calibration.ch` — 13 tests covering bound clamping, WLS /
  WL1 zero-residual / known-value identities, vega-weighting puts
  more weight on low-vega points, LM step direction (negative
  J^T r moves up; positive moves down), bound clamping under
  large proposals, damping attenuation.

### Added — M9 extended risk

- `Shoals.RiskExt` module (`src/riskext.ch`):
  - `mc_var(losses, confidence)`, `mc_expected_shortfall(losses,
    confidence)` — alias to historical quantile / tail-mean from
    `Shoals.Risk`. The M9 distinction is intentional (these
    accept MC-simulated path losses, not historical observations)
    even though the closed-form computation is the same on a
    quantile basis.
  - `expected_shortfall_frtb_975(losses)` — the Basel FRTB-IMA
    97.5% expected shortfall, the standard regulatory tail measure.
  - `scenario_pnl_grid(base_value, scenario_shifts,
    pnl_per_unit_shift)` — produces a per-scenario PnL tensor for
    a linear sensitivity model. Used for stress-test reporting.
  - `kupiec_pof_statistic_simple(num_violations, total_observations,
    expected_rate)` — proportion-of-failures likelihood-ratio
    statistic, the standard regulatory backtest. Returns the LR
    test statistic (chi-squared under H0; degree 1).
- `tests/riskext.ch` — 9 tests covering VaR / ES on a 0..100 loss
  vector with known quantile, FRTB-975 ES matches explicit ES
  call, ES at 100% confidence collapses to max loss, scenario PnL
  grid linearity, Kupiec POF statistic is 0 when observed equals
  expected, Kupiec POF > 5 when 20/100 vs expected 5%, VaR
  monotone in confidence, ES ≥ VaR (coherence).

### Deferred — M8 continuation

- **BFGS with bounds** — bounded vector-parameter optimizer; the
  current LM helper handles single-parameter only.
- **SQP** for nonlinear constraints (vol-surface no-arbitrage).
- **Multi-target combinator** — fit one model to many products at
  once with shared parameters.
- **Sequential pipeline** — chain curves → surfaces → exotic params
  with IFT-threaded gradient flow at each optimum.
- **Full vectorized LM** — extending `Nautilus.CurveFit.lm_scalar_1param`
  to multi-parameter with bound handling.

### Deferred — M9 continuation

- **Christoffersen conditional-coverage test** — extends Kupiec POF
  with serial-dependence checks.
- **Acerbi-Szekely ES backtest** — direct ES backtest from a
  realized-loss series and an ES forecast series.
- **Sensitivity-based VaR** (delta-gamma approximation) — requires
  the M6.3 bucket-sensitivity surface.
- **250-day rolling FRTB-IMA zone classifier** (green / yellow /
  amber / red zones based on backtest exceptions).

### AD verification status

- `Shoals.Calibration.clamp_to_bounds`, `sse_loss`,
  `lm_bounded_step_scalar` are `AD: composed` over pure arithmetic.
  The LM step's `clamp_to_bounds` branch is on a constant threshold
  (`lo`, `hi`) so gradient is well-defined almost-everywhere;
  non-smooth at the bound boundary, marked alpha with a doc-string
  warning.
- `Shoals.Calibration.weighted_squared_residuals`,
  `weighted_absolute_residuals`, `vega_weighted_squared_residuals`
  are `AD: unproven-primitive` — each uses host-lane `to_list` +
  `map` over a list combinator (same pattern as `Shoals.Xva`
  aggregators and `Shoals.RiskExt.scenario_pnl_grid`).
  Functional behavior FD-cross-checked through the test suite;
  composed-AD label requires the same chelis upstream gating as the
  existing pricing-body grad path.
- `Shoals.RiskExt`:
  - `mc_var`, `mc_expected_shortfall`,
    `expected_shortfall_frtb_975`: `AD: unproven-primitive` (depend
    on Nautilus `quantile_vec` whose AD status is unproven
    upstream).
  - `scenario_pnl_grid`: `AD: unproven-primitive` (uses host-lane
    `to_list` + `map`).
  - `kupiec_pof_statistic_simple`: `AD: composed` (pure arithmetic
    with constant-threshold branches; non-smooth at violations =
    0 and observed_rate = 1 — alpha at those degenerate cases).

### Verification

- `python3 scripts/run_local_gate.py` — exits 0.
- `chelis test tests/ --timeout 120 --jobs auto` — 201 passed, 0
  failed (was 179 at end of M7; +13 from `tests/calibration.ch` + 9
  from `tests/riskext.ch`).

## [0.7.0] — unreleased

M7 XVA core slice. Adds `Shoals.Xva` module with the basic
exposure-aggregation, default-modeling, and CVA / DVA computation
surface. Constant-hazard / constant-discount-rate baseline; full
stochastic versions are M7-continuation.

### Added

- `Shoals.Xva` module (`src/xva.ch`):
  - **Default modeling:**
    `survival_probability_constant_hazard(hazard, t) = exp(-hazard*t)`,
    `default_probability_in_interval(hazard, t_start, t_end) = S(t_start) - S(t_end)`,
    `discount_factor_constant_rate(r, t) = exp(-r*t)`.
  - **Exposure aggregation:** `expected_positive_exposure(exposures)`
    averages `max(x, 0)` across paths; `expected_negative_exposure`
    averages `min(x, 0)`. `netted_exposure_2_deals(deal_a, deal_b)`
    sums pointwise per-path exposures.
  - **CVA aggregator:** `cva_constant_hazard(time_grid, epe,
    hazard, recovery, discount_rate)` integrates discounted EPE
    times default-probability-in-interval times loss-given-default
    over a discrete time grid. Standard form
    `CVA ≈ LGD * sum_i EPE(t_i) * df(t_i) * [S(t_{i-1}) - S(t_i)]`.
    First interval is `[0, t_0]`.
  - **DVA aggregator:** `dva_constant_hazard(time_grid, ene,
    hazard_own, recovery_own, discount_rate)` — same shape with
    own-default hazard and `-ene` as the positive payout.
- `tests/xva.ch` — 14 tests covering survival monotonicity, default
  probability decomposition, EPE / ENE positivity / negativity
  invariants, netting linearity, CVA edge cases (zero hazard /
  full recovery / zero EPE → CVA = 0), CVA monotone-in-hazard, DVA
  positive when ENE is negative.

### Deferred

- **Stochastic hazard** (term-structure of survival probabilities
  from CDS quotes) — needs the curve-bootstrap M2-continuation.
- **FVA, KVA** — funding-valuation and capital-valuation
  adjustments are sister aggregators to CVA / DVA; bounded
  extension once funding-spread and regulatory-capital input
  shapes are decided.
- **Wrong-way risk** — correlated default × exposure paths require
  joint MC simulation against a credit-equity correlation model;
  M7-continuation.
- **Multi-CSA netting** — CSA threshold / MTA / IA / collateral
  haircut models; bounded.
- **Stochastic recovery** — current recovery rate is deterministic;
  beta-distributed recovery is a bounded extension.

### AD verification status

- `survival_probability_constant_hazard`,
  `default_probability_in_interval`,
  `discount_factor_constant_rate`: `AD: composed` (pure
  arithmetic over `exp` + `mul` + `neg`).
- `expected_positive_exposure`, `expected_negative_exposure`,
  `netted_exposure_2_deals`, `cva_constant_hazard`,
  `dva_constant_hazard`: `AD: unproven-primitive` (each uses
  host-lane `to_list` + `map` / `fold` over a list combinator).
  Functional behavior FD-cross-checked through the test suite;
  composed-AD label requires the same chelis upstream gating as
  the existing pricing-body grad path.

### Verification

- `python3 scripts/run_local_gate.py` — exits 0.
- `chelis test tests/ --timeout 120 --jobs auto` — 179 passed, 0
  failed (was 165 at end of M6; +14 from `tests/xva.ch`).

## [0.6.0] — unreleased

M6 Greeks-discipline slice. Adds `Shoals.Greeks` module covering
first-order Greek constructors (delta, vega, rho, theta — call and
put each), second-order constructors (gamma, vanna, volga) marked
alpha + FD-checked, analytic-Greek references for cross-check, and
the pathwise-vs-likelihood-ratio dispatch on a smooth-call and
digital-call example.

### Added

- `Shoals.Greeks` module (`src/greeks.ch`):
  - **First-order via central FD over Black-Scholes**: `fd_delta_call`,
    `fd_delta_put`, `fd_vega_call`, `fd_vega_put`, `fd_rho_call`,
    `fd_rho_put`, `fd_theta_call`, `fd_theta_put`. Theta returns the
    conventional sign (negative for long calls/puts at long T).
  - **Second-order via FD**: `fd_gamma_call` (second central diff in
    spot), `fd_volga_call` (second in vol), `fd_vanna_call` (mixed
    first/first via nested deltas).
  - **Analytic-Greek references** for cross-check: `analytic_delta_call`,
    `analytic_delta_put`, `analytic_vega_call`, `analytic_gamma_call`
    using the standard `N(d1)` / `S*phi(d1)*sqrt(t)` /
    `phi(d1)/(S*sigma*sqrt(t))` formulas.
  - **Pathwise vs LR dispatch** (single-path constructors illustrating
    the M6.4 pattern):
    - `pathwise_smooth_call_terminal_delta(s_terminal, k, df, s0)` —
      pathwise delta for a smooth European call on one MC path
      (returns `df * s_terminal/s0` when ITM, 0 otherwise).
    - `lr_digital_call_delta(s_terminal, k, s0, sigma, t, df)` —
      likelihood-ratio (score-function) delta for a digital call on
      one MC path. Used where the payoff has a discontinuity (the
      indicator is not pathwise-differentiable; LR routes via the
      log-density score).
- `tests/greeks.ch` — 17 tests covering FD-vs-analytic agreement at
  ATM, sign invariants (delta range, theta sign, rho signs,
  vega ≥ 0), put-call parity on delta (`delta_c - delta_p == 1`),
  pathwise / LR identities on single-path inputs.

### Deferred

- **Bucket sensitivities** (M6.3): `curve_delta` returning
  `Curve[Differentiable[f32]]`, `surface_vega` returning
  `Surface[Differentiable[f32]]`. Verified label gates on upstream
  linearity-AD theorem; functional implementation depends on the
  curve-shape-preserving AD that doesn't compose cleanly out of the
  current `grad` primitive in chelis 0.7.11.
- **`grad`-derived Greeks** (the AD-composed alternative to FD): the
  Shoals pricing body uses host-lane `to_list` + `map` +
  `to_tensor`; whether that composes through `grad` end-to-end under
  chelis 0.7.11 is unverified — same condition as the M0/M3 hedges
  document. FD-derived Greeks ship as the load-bearing surface.
- **vmap-over-portfolio** Greek aggregator (single function applied
  to a portfolio of pricers) — needs a portfolio-type abstraction
  that depends on the calibration module (M8).

### AD verification status

- `n_pdf`, `n_cdf`, `analytic_*`, `pathwise_smooth_call_terminal_delta`,
  `lr_digital_call_delta` are `AD: composed` (pure arithmetic over
  `erfc`, `log`, `exp`, `sqrt`).
- `fd_*` Greek constructors are `AD: unproven-primitive` — each is a
  central-difference quotient that itself can be composed but
  inherits the unproven-leaf status of the underlying `bs_call_scalar`
  / `bs_put_scalar` (those rely on `erfc` which is `unproven-primitive`
  in Nautilus).
- Second-order Greeks (`fd_gamma_call`, `fd_volga_call`, `fd_vanna_call`)
  ship as alpha; verified-AD label requires upstream higher-order
  AD per spec §3.4.

### Verification

- `python3 scripts/run_local_gate.py` — exits 0.
- `chelis test tests/ --timeout 120 --jobs auto` — 165 passed, 0
  failed (was 148 at end of M5; +17 from `tests/greeks.ch`).

## [0.5.0] — unreleased

M5 closed-form pricer slice. Adds a new `Shoals.PricingExtended`
module with the standard non-Black-Scholes closed-form pricers used
across rates / FX / multi-asset desks.

### Added

- `Shoals.PricingExtended` module (file `src/pricingextended.ch`):
  - `n_cdf_ext`, `n_pdf_ext` — Phi and phi for the standard normal.
  - **Bachelier** (normal-distributed underlying — standard for
    negative-rate environments): `bachelier_call(f, k, sigma, t,
    df)`, `bachelier_put(f, k, sigma, t, df)`.
  - **Black** (forward-priced — standard for caplets, swaptions):
    `black_call(f, k, sigma, t, df)`, `black_put(f, k, sigma, t,
    df)`. Reduces to Black-Scholes when `f = s*exp(r*t)` and
    `df = exp(-r*t)`.
  - **Garman-Kohlhagen** (FX with domestic + foreign rates):
    `garman_kohlhagen_call(s, k, r_d, r_f, sigma, t)`,
    `garman_kohlhagen_put(s, k, r_d, r_f, sigma, t)`. Reduces to
    Black-Scholes when `r_f = 0`.
  - **Margrabe exchange option** (option on the spread between two
    assets): `margrabe_exchange_call(s1, s2, sigma1, sigma2, rho,
    t)`. Handles the degenerate-vol case (`variance < 1e-10`,
    e.g. `rho=1, sigma1=sigma2`) by returning intrinsic.
- `tests/pricingextended.ch` (11 tests): Phi/phi at zero, Bachelier
  ATM identity (`sigma*phi(0)`), Bachelier put-call parity, Black
  reduces to BS when `f=s*exp(r*t)`, Black put-call parity, GK
  reduces to BS at `r_f=0`, GK put-call parity, Margrabe reduces to
  BS at `sigma2≈0`, Margrabe positivity, Margrabe degenerate-vol
  intrinsic.

### Deferred

- **Tree methods** (CRR / Tian / Jarrow-Rudd binomial; trinomial) —
  American exercise via backward induction; AD-through-early-exercise
  gates on chelis D1 (control-flow AD).
- **PDE methods** (Crank-Nicolson + Rannacher; 2-D ADI) — adjoint-PDE
  AD approach pinned in spec §2.10; substantial own implementation.
- **Longstaff-Schwartz** for American MC — IFT-through-regression AD
  approach pinned in spec §2.10.
- **Fourier methods** (Heston char-fn + Carr-Madan FFT) — depends on
  complex-arithmetic surface that isn't in chelis-std yet.
- **Margrabe-Stulz** (stochastic correlation extension).

### AD verification status

- All new exports are `AD: composed` (pure arithmetic over `erfc`,
  `log`, `exp`, `sqrt`). The Margrabe degenerate-vol branch is a
  `Discrete` decision (`if lt(variance, 1e-10)`) that does not break
  AD-composition because the variance threshold is a constant.

### Verification

- `python3 scripts/run_local_gate.py` — exits 0.
- `chelis test tests/ --timeout 120 --jobs auto` — 148 passed, 0
  failed (was 137 at end of M4; +11 from `tests/pricingextended.ch`).

## [0.4.0] — unreleased

M4 SDE-zoo slice. Lands Merton jump-diffusion (lognormal jumps with
compensated drift) and 2-asset correlated GBM via a hand-rolled 2x2
Cholesky helper.

### Added

- `Shoals.Stochastic.merton_compensated_drift(mu, sigma, lambda,
  jump_mean, jump_vol)` — Merton-style compensated drift accounting
  for the expected jump contribution. AD: composed.
- `Shoals.Stochastic.merton_jump_terminal(template_diff, template_jump,
  s0, mu, sigma, lambda, jump_mean, jump_vol, t)` — terminal-value
  generator with one aggregate-jump Gaussian per path. Aggregate
  variance is the correct compound-Poisson variance under
  deterministic-N approximation: `λt * (jump_vol² + jump_mean²)`
  (law of total variance is dropped, treating the jump count at its
  mean λt; the per-jump variance term `jump_mean²` is included).
  Mean drift is exact via Merton compensated drift. AD: unsupported
  (runs over `Random` effect; gated on upstream effect-AD per spec
  §3.2).
- `Shoals.Stochastic.cholesky_2x2_lower(sigma_xx, sigma_xy, sigma_yy)
  -> (L11, L21, L22)` — 2x2 Cholesky factor; standalone helper that
  avoids Nautilus.LinAlg dependency for the 2D case. AD: composed.
- `Shoals.Stochastic.correlated_gbm_terminal_2d(template_x,
  template_y, s0_x, s0_y, mu_x, mu_y, sigma_x, sigma_y, rho, t)` —
  2-asset correlated GBM terminal-value generator using
  `rho * Z_x + sqrt(1 - rho^2) * Z_y` correlation injection. Returns
  a `(tensor[n, f32], tensor[n, f32])` tuple. **`|rho| > 1` is
  silently clamped**: when `1 - rho^2 < 0`, the implementation
  substitutes `sqrt(...) = 0`, producing perfectly comonotonic
  paths. Callers should validate `rho` is in `[-1, 1]` before
  invoking; documented as a known limitation. AD: unsupported (runs
  over `Random` effect; gated on upstream effect-AD per spec §3.2).
- `tests/stochastic_extended.ch` — 9 tests covering Merton drift
  identities, Cholesky 2x2 closed-form algebra, round-trip recovery
  of the covariance matrix, MC terminal-mean checks for both Merton
  and correlated 2-asset GBM at 5% relative tolerance / 5000 paths.

### Deferred

- **Heston QE (Andersen)** — substantial own implementation with two
  conditional regimes (quadratic-Gaussian vs exponential) based on
  `psi = m^2 / s2`; the next priority continuation per spec §2.9
  and the M4.1 acceptance gate `phase3l_shoals_oracle_heston_qe`.
- **SABR path simulation** — pairs with the Hagan analytic from M3
  vol surfaces; deferred to a continuation.
- **Hull-White 1F/2F** — Gaussian short-rate with closed-form bond
  pricing as reference; bounded implementation.
- **Libor Market Model** — shifted-lognormal drift correction.
- **HJM framework** — no-arbitrage drift condition.
- **Kou double-exponential jumps** — Merton-shape extension once a
  pos/neg jump regime distinction is available.
- **N-dim Cholesky** — the 2x2 helper here is a stand-in for the
  general case that lives in Nautilus.LinAlg as a follow-up.

### AD verification status

- `merton_compensated_drift` and `cholesky_2x2_lower` are
  `AD: composed` — pure arithmetic over verified primitives, no
  effects.
- `merton_jump_terminal` and `correlated_gbm_terminal_2d` are
  `AD: unsupported` — both run over the `Random` effect (via
  `normal_sample`). Per `spec/shoals_quant_surface.md` §3.2 and the
  plan's M4 acceptance criterion (every process's path-generation
  function lands as `unsupported` until effect-AD upstream lands).
  Functional behavior FD-cross-checked; verified-AD label flips when
  chelis D3 (effect-AD) closes upstream.

### Verification

- `python3 scripts/run_local_gate.py` — exits 0.
- `chelis test tests/ --timeout 120 --jobs auto` — 137 passed, 0
  failed (was 128 at end of M3; +9 from `tests/stochastic_extended.ch`).

## [0.3.0] — unreleased

M3 vol-surface slice. Lands the SVI parameterization, implied-vol
solver via bisection, and shift operations.

### Added

- **`Shoals.VolSurface`** module:
  - **SVI parameterization** (Gatheral 5-parameter): `SVI { a, b,
    rho, m, sigma }`. `svi_total_variance(p, k)` returns `a + b*(rho*(k-m) + sqrt((k-m)^2 + sigma^2))`. `svi_implied_vol(p, k, t) = sqrt(max(w, 0)/t)`.
  - **Surface shifts**: `svi_shift_atm` (delta on `a`),
    `svi_shift_skew` (delta on `rho`), `parallel_shift_atm_iv(p,
    delta_iv, t)` (lifts ATM implied vol by exactly `delta_iv` —
    computes the correct `delta_a` for `IV_new^2 * t - IV_old^2 * t`),
    `smile_shift_skew_wing` (delta on `b`). All differentiable in
    their shift parameter.
  - **Implied vol solver via bisection**: `implied_vol_from_call(spot, strike, r, t, target_price)` inverts Black-Scholes via bracketing on `[1e-4, 5.0]` with 60 iterations and `1e-6` tolerance. Calls `Shoals.Pricing.bs_call_scalar`. Returns NaN sentinel (`is_iv_solver_failed(iv)` test) when the bracket does not contain a root (target above/below the achievable Black-Scholes price range under the search bounds). The public `bracket_brackets_root` predicate exposes the same check for callers that want to validate ahead of time.
- **`tests/volsurface.ch`** (16 tests): SVI variance flatness, ATM
  level, OTM > ATM for smile, IV round-trip at three configurations
  (ATM 1y, ITM 6m, OTM 2y), `parallel_shift_atm_iv` lifts ATM IV by
  exactly the requested delta, IV solver returns NaN on unbracketed
  targets, `bracket_brackets_root` discriminates valid/invalid
  brackets.
- **`properties/volsurface.ch`** (3 properties): non-negative ATM
  variance, IV matches `sqrt(variance/t)`, BS round-trip within
  `1e-3`.

### Deferred to a future milestone

- **SABR (Hagan analytic)** — uses incomplete elliptic / Bessel-like
  functions whose composition we want to keep in Nautilus.Special;
  scope for an M3-continuation.
- **Dupire local volatility** — requires upstream higher-order AD per
  spec §3.4. Evaluating the formula is bounded engineering;
  differentiating through it is the gated piece.
- **Cubic-in-log-moneyness × time interpolation** — straightforward
  extension over the existing `Nautilus.Interpolation` surface;
  scope for an M3-continuation.

### AD verification status

- All new exports ship at `alpha`.
- `svi_total_variance`, `svi_implied_vol`, `svi_shift_*`,
  `parallel_shift_vol`, `smile_shift_vol` are `AD: composed` over
  arithmetic + `sqrt`.
- `implied_vol_from_call` is `AD: unproven-primitive` — the
  bisection loop is the leaf and AD through iterative root-finds
  needs the upstream IFT hook for verified status. Functionally
  correct (round-trips to 1e-3 in three configurations); FD
  cross-check covers the alpha label until upstream lands.

### Verification

- `python3 scripts/run_local_gate.py` — exits 0.
- `chelis test tests/ --timeout 120 --jobs auto` — 128 passed, 0
  failed (was 112 at end of M2; +16 from `tests/volsurface.ch`).

### Red-team fix-ups landed before commit

- `parallel_shift_vol` (had a wrong formula `delta_a = 2*b*shift`)
  renamed to `parallel_shift_atm_iv(p, delta_iv, t)` and the formula
  rewritten to lift ATM implied vol by exactly the requested delta
  (`delta_a = (IV+delta)^2 * t - IV^2 * t`). New test verifies the
  invariant on a smile surface.
- `implied_vol_bisect` was silently pinning at `vol_hi` for
  unbracketed targets. Now validates `bracket_brackets_root` at
  entry and returns NaN sentinel on failure; `is_iv_solver_failed`
  predicate exposed for callers. Two new tests cover this.
- `smile_shift_vol` renamed to `smile_shift_skew_wing` for clarity
  (it shifts `b`, the smile-wing parameter, not the smile per se).

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
