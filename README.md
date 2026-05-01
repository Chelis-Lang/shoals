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

The reference implementations under `references/` ship the
textbook-formula versions of Black-Scholes (call, put, all five
first-order Greeks), Vasicek (zero-bond pricing, conditional-rate
moments), historical VaR/CVaR, and vanilla Monte Carlo. They are the
ground-truth oracles that `Shoals.Pricing`, `Shoals.Risk`, and
`Shoals.Stochastic` must agree with under the property gate.

## Properties

`properties/` ships function bodies for the canonical finance
properties (put-call parity, call-bounded-by-spot, FD-delta-in-[0,1],
vega non-negative, MC-reproducibility, bull/butterfly-spread
no-arbitrage). Status: design-only. The compiler v0.4.1 does not yet
parse `@property` annotations and ships no `chelis fuzz` subcommand;
the property bodies are written as plain `def name(...) -> bool`
ready to flip to `@property` when the tool ships. See
`spec/phase3l.md` and the upstream `chelis_fuzz_spec.md` for the
plan.

## Toolchain

Pinned to `chelis v0.4.1` in `reef.toml`:

```toml
[package]
compiler = "=0.4.1"
```

Dependencies resolve via the local Reef registry (`~/.chelis/reef/`):

* `chelis-std` 0.1.0 — standard library
* `nautilus`   0.4.0 — distributions, special functions, stats,
  interpolation
* `coral`      0.4.0 — dataframe runtime (transitively required for
  the same `nautilus` minor version)

## Build

```sh
# type-check a single module
chelis check src/pricing.ch

# run the in-tree test suite (default tier; ~3-4 min wall-clock)
chelis test tests/ --timeout 120

# canonical-formatter parseability gate (single file at a time today)
chelis fmt --check src/pricing.ch
```

`chelis fmt` accepts only one file per invocation in v0.4.1; CI loops
over the directory in a shell `for` loop. See `.github/workflows/ci.yml`.

The default test tier uses 20 000 Monte-Carlo paths and 2 % tolerance
for convergence assertions. The longer `--timeout 120` is required
because the host evaluator runs the 20K MC sample loop in ~60 s.

### Manual rigor gate

The spec-rigor 100 000-path tier lives at
`manual-gates/mc_rigorous.ch` and is **not** walked by
`chelis test tests/`. Invoke it explicitly:

```sh
chelis test manual-gates/mc_rigorous.ch --timeout 900
```

The rigor tier asserts 1 % MC convergence and 2 % terminal-variance
agreement at 100K paths. **Currently not runnable on the chelis v0.4.1
host evaluator** — 100K-path MC simulation in the interpreted host
evaluator does not complete in reasonable wall-clock (>30 min and not
terminating, measured 2026-05-01 on AMD Ryzen AI Max+ 395). The
gate becomes practical once Shoals can compile to native code via
`chelis build` AOT; until then the spec rigor at 100K paths is
deferred. See `chelis/spec/upstream-bugs/host-eval-perf-mc-rigor.md`.
The default-tier 20K-path tests in `tests/` exercise the same
correctness invariants at lower rigor and run as part of every push.

## Acceptance gate

Repo-local: every test under `tests/` passes via
`chelis test tests/ --timeout 120`. There are 47 tests covering
pricing correctness, finite-difference Greeks (in-unit-range and
matches-N(d1) checks), MC convergence (20K paths, 2 % tolerance) and
reproducibility, parametric and historical VaR/CVaR, yield-curve
interpolation and bootstrap round-trip, GBM path positivity, full-path
bit-exact reproducibility, terminal-mean and terminal-variance
theorems, and order-book invariants. Properties under
`properties/` are exercised through `tests/properties.ch` (14 grid
cases for textbook-call/put agreement plus the new FD-delta-vs-N(d1)
and optimized-vs-textbook-MC properties).

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
2. **`@property` is design-only.** Compiler v0.4.1 does not parse the
   annotation; the property bodies are plain `def`s that flip to
   `@property` when `chelis fuzz` ships. See above.
3. **`chelis manifest` is design-only.** The MC reproducibility
   contract is enforced by the `Random` effect (the compiler refuses
   unseeded random ops at type-check time). The JSON manifest artifact
   for CI is a Chelis-side follow-up.
4. **MC convergence test uses 20 000 paths at 2 % tolerance.** Default
   `chelis test` timeout is 30 s; the suite is invoked with
   `--timeout 120` because the 20K MC test takes ~60 s under the v0.4.1
   host evaluator. The 100 000-path / 1 % spec-rigor tier lives at
   `manual-gates/mc_rigorous.ch` and is invoked explicitly (see
   "Manual rigor gate" above). The reproducibility test (which is the
   regulatory-critical one) uses 5 000 paths and runs in well under
   the default budget.
5. **Single-curve bootstrap only.** `bootstrap_zero_from_par`
   handles the integer-year-spaced case (one coupon per pillar). A
   multi-curve / non-uniform-spacing variant is a v0.2 candidate.
6. **`erfc` direct routing.** Per Chelis architecture, special
   functions live in `Nautilus.Special`. As of `nautilus 0.4.0`
   Shoals routes Black-Scholes through `Nautilus.Special.erfc`
   directly (computing `0.5 * erfc(-x / sqrt(2))` for the standard
   normal CDF), bypassing the higher-level distribution wrapper. No
   shell-private special functions are shipped.

### Layout (canonical, since v0.1.0)

Per the trust stack spec, `properties/` and `references/` are top-level
directories alongside `src/`. Shoals v0.1.0 ships at the canonical layout
following the chelis-reef v0.4.1 multi-source-roots fix
(`6b58030 feat(reef): multi-source-roots — additional_sources in reef.toml;
bump v0.4.1`). The reef.toml declares
`additional_sources = ["properties", "references"]`. Shoals v0.1.0-alpha
shipped with these directories under `src/` as a workaround pending the
reef fix; v0.1.0 migrates to the canonical layout.

## Python interop

The Chelis monorepo ships a `chelis-python` package
(`bindings/python/chelis/`) that wraps the in-process evaluator and
exposes `chelis.check(...)` and `chelis.eval(source, bindings)` to
Python. v0.1.0-alpha verifies a Shoals-shaped program round-trips
through that surface.

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
