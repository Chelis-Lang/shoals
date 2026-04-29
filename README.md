# Shoals

Quantitative-finance shell for the
[Chelis](https://github.com/Chelis-Lang/chelis) programming language.
Ships as a reef package under the `Shoals` module prefix.

## Status

v0.1.0-alpha. The full Phase 3l module shape is in place: pricing,
risk, curves, stochastic, and orderbook. Every public function carries
the `alpha` stability label per the cross-cutting Chelis convention.
Promotion to `stable` waits until the Phase 3l acceptance oracle in
the Chelis monorepo is wired and green.

## Modules

| Module | Contents | Status |
|---|---|---|
| `Shoals.Pricing` | Black-Scholes call/put (closed form), call/put price tensors, MC engine with `Random` effect, Greeks via `grad` (deltas, vega) | alpha |
| `Shoals.Risk` | Parametric VaR + CVaR (Gaussian), historical VaR + CVaR (empirical-quantile + tail-mean), empirical loss quantiles | alpha |
| `Shoals.Curves` | Linear and cubic-spline yield-curve interpolation, discount factors, single-curve par-bond bootstrap | alpha |
| `Shoals.Stochastic` | GBM path generation (log-Euler), terminal draws, antithetic-variates terminal-mean estimator | alpha |
| `Shoals.Orderbook` | Limit order book (price-priority sorted lists), best bid/ask, bid-ask spread, VWAP, side quantities | alpha |

The reference implementations under `src/references/` ship the
textbook-formula versions of Black-Scholes (call, put, all five
first-order Greeks), Vasicek (zero-bond pricing, conditional-rate
moments), historical VaR/CVaR, and vanilla Monte Carlo. They are the
ground-truth oracles that `Shoals.Pricing`, `Shoals.Risk`, and
`Shoals.Stochastic` must agree with under the property gate.

## Properties

`src/properties/` ships function bodies for the canonical finance
properties (put-call parity, call-bounded-by-spot, FD-delta-in-[0,1],
vega non-negative, MC-reproducibility, bull/butterfly-spread
no-arbitrage). Status: design-only. The compiler v0.4.0 does not yet
parse `@property` annotations and ships no `chelis fuzz` subcommand;
the property bodies are written as plain `def name(...) -> bool`
ready to flip to `@property` when the tool ships. See
`spec/phase3l.md` and the upstream `chelis_fuzz_spec.md` for the
plan.

## Toolchain

Pinned to `chelis v0.4.0` in `reef.toml`:

```toml
[package]
compiler = "=0.4.0"
```

Dependencies resolve via the local Reef registry (`~/.chelis/reef/`):

* `chelis-std` 0.1.0 — standard library
* `nautilus`   0.3.x — distributions, special functions, stats,
  interpolation
* `coral`      0.4.0 — dataframe runtime (transitively required for
  the same `nautilus` minor version)

## Build

```sh
# type-check a single module
chelis check src/pricing.ch

# run the in-tree test suite (28 tests)
chelis test tests/

# canonical-formatter parseability gate (single file at a time today)
chelis fmt --check src/pricing.ch
```

`chelis fmt` accepts only one file per invocation in v0.4.0; CI loops
over the directory in a shell `for` loop. See `.github/workflows/ci.yml`.

## Acceptance gate

Repo-local: every test under `tests/` passes via
`chelis test tests/`. There are 28 tests covering pricing
correctness, finite-difference Greeks, MC reproducibility, parametric
and historical VaR/CVaR, yield-curve interpolation and bootstrap
round-trip, GBM path positivity and terminal-mean theorem, and
order-book invariants.

Phase oracle: the Chelis-monorepo-side
`cargo test -p chelis-cli phase3l_shoals_oracle -- --exact` is a
follow-up and is not exercised from this repo. The Shoals scope ends
at `chelis test tests/` going green.

## Known limitations in v0.1.0-alpha

1. **Greeks via `grad` are typed-only in the host runtime.** Reverse-
   mode AD compiles correctly through `Shoals.Pricing.deltas_call`,
   `deltas_put`, and `vegas_call` (verified by `chelis check`), but
   the host runtime backing `chelis test` does not execute `grad`.
   The corresponding numerical tests use central finite differences
   to verify the analytical reference until Phase 5 host-scalar AD
   ships. Compiled-C-backend Greeks are exercised in the
   `chelis-cli` test harness upstream.
2. **`@property` is design-only.** Compiler v0.4.0 does not parse the
   annotation; the property bodies are plain `def`s that flip to
   `@property` when `chelis fuzz` ships. See above.
3. **`chelis manifest` is design-only.** The MC reproducibility
   contract is enforced by the `Random` effect (the compiler refuses
   unseeded random ops at type-check time). The JSON manifest artifact
   for CI is a Chelis-side follow-up.
4. **MC convergence test uses 2 000 paths.** Default `chelis test`
   timeout is 30 s; 20 000-path runs are deferred to a manual gate.
   The reproducibility test (which is the regulatory-critical one)
   uses 5 000 paths and runs in well under the budget.
5. **Single-curve bootstrap only.** `bootstrap_zero_from_par`
   handles the integer-year-spaced case (one coupon per pillar). A
   multi-curve / non-uniform-spacing variant is a v0.2 candidate.
6. **`erfc` and bare `gamma`.** Per Chelis architecture, special
   functions live in `Nautilus.Special`. The currently published
   `Nautilus 0.3.3` available in the local registry exports `erf`,
   `erfinv`, `log_gamma`, `digamma`, `beta`, `lbeta`, `trigamma`,
   `bessel_*`, `airy_*`, `ellipk`, `ellipe`. Shoals routes Black-
   Scholes through `Nautilus.Distributions.normal_cdf`, which wraps
   `erf` internally; no shell-private special functions are shipped.

## Python FFI

The Chelis monorepo ships a `chelis-python` crate with an integration
test under `crates/chelis-python/tests/manual_phase3b.rs` that
exercises the full Python -> Chelis -> Python tensor round-trip via
`chelis.eval(...)`. That manual gate is `#[ignore]`d behind a
`py/.venv` setup and is invoked via:

```sh
cd /path/to/chelis
cargo test -p chelis-python -- --ignored manual_phase3b
```

It is not parameterized by Shoals: the test embeds its own loss
program. Running it on a Shoals-shaped pricing function (e.g.
`Shoals.Pricing.bs_call_scalar`) is a follow-up that lives upstream
in the `chelis-python` crate, not in this shell. v0.1.0-alpha
documents the gate path here and defers the Shoals-flavored run to
the chelis-side bindings work.

## License

MIT
