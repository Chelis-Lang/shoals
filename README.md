# Shoals

Quantitative-finance shell for the
[Chelis](https://github.com/Chelis-Lang/chelis) programming language.
Ships as a reef package under the `Shoals` module prefix.

## Status

v0.2.0. The full Phase 3l module shape is in place: pricing,
risk, curves, stochastic, and orderbook. Every public function carries
the `alpha` stability label per the cross-cutting Chelis convention.
Promotion to `stable` waits until the Phase 3l acceptance oracle in
the Chelis monorepo is wired and green.

## Modules

| Module | Contents | Status |
|---|---|---|
| `Shoals.Pricing` | Black-Scholes call/put (closed form), call/put price tensors, MC engine with `Random` effect, finite-difference Greek checks; grad-derived Greeks are an alpha runtime path | alpha |
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
properties (put-call parity, call-bounded-by-spot, finite-difference
delta/vega smoke, MC-reproducibility, bull/butterfly-spread
no-arbitrage). Status: mixed. The compiler v0.6.1 does not yet
parse `@property` annotations and ships no `chelis fuzz` subcommand;
the property bodies are written as plain `def name(...) -> bool`
ready to flip to `@property` when the tool ships. See
`spec/phase3l.md` and the upstream `chelis_fuzz_spec.md` for the
plan. `Shoals.Pricing` still exposes grad-derived Greek functions, but
the default executable test suite uses finite differences because
Shoals's full pricing body is not yet IR-lowerable by host-runtime
`grad`.

## Toolchain

Pinned to `chelis v0.6.1` in `reef.toml`:

```toml
[package]
compiler = "=0.6.1"
```

Dependencies resolve via the local Reef registry (`~/.chelis/reef/`):

* `chelis-std` 0.2.0 — standard library
* `nautilus`   0.6.1 — distributions, special functions, stats,
  interpolation
* `coral`      0.6.1 — dataframe runtime (transitively required for
  the same `nautilus` minor version)

## Build

```sh
# compiler-owned package gate
chelis reef build

# run the in-tree runtime test suite explicitly
chelis test tests/ --timeout 120

# canonical-formatter parseability gate (single file at a time today)
chelis fmt --check src/pricing.ch
```

`chelis fmt` accepts only one file per invocation in v0.6.1; CI loops
over the directory in Python. See `.github/workflows/ci.yml` and
`scripts/run_local_gate.py`.

The default test tier uses 20 000 Monte-Carlo paths and 2 % tolerance
for convergence assertions. The longer `--timeout 120` is required
because the host evaluator runs the 20K MC sample loop in ~60 s. It is
not part of the default PR gate; invoke it as a runtime/manual check
when changing pricing, stochastic, or property behavior.

### Manual rigor gate

The spec-rigor 100 000-path tier lives at
`manual-gates/mc_rigorous.ch` and is **not** walked by
`chelis test tests/`. Invoke it explicitly:

```sh
chelis test manual-gates/mc_rigorous.ch --timeout 900
```

The rigor tier asserts 1 % MC convergence and 2 % terminal-variance
agreement at 100K paths. **Currently not runnable on the chelis v0.6.1
host evaluator** — 100K-path MC simulation in the interpreted host
evaluator does not complete in reasonable wall-clock (>30 min and not
terminating, measured 2026-05-01 on AMD Ryzen AI Max+ 395). The
gate becomes practical once Shoals can compile to native code via
`chelis build` AOT; until then the spec rigor at 100K paths is
deferred. See `chelis/spec/upstream-bugs/host-eval-perf-mc-rigor.md`.
The default-tier 20K-path tests in `tests/` exercise the same
correctness invariants at lower rigor and are an explicit local/runtime
gate, not part of every PR push.

## Acceptance gate

Default PR/repo-local gate: `scripts/run_local_gate.py` and CI run
`chelis fmt --check` over repository `.ch` sources and `chelis reef
build`. `chelis reef build` is the compiler-owned package oracle: it
resolves the Reef manifest, lowers the package, and rejects stale source
or dependency wiring without duplicating semantic module checks in
repository scripts.

Runtime/manual gate: `chelis test tests/ --timeout 120`. Expected
success condition: all 47 tests pass. This covers pricing correctness,
finite-difference Greeks (in-unit-range and matches-N(d1) checks), MC
convergence (20K paths, 2 % tolerance) and reproducibility, parametric
and historical VaR/CVaR, yield-curve interpolation and bootstrap
round-trip, GBM path positivity, full-path bit-exact reproducibility,
terminal-mean and terminal-variance theorems, and order-book invariants.
Properties under `properties/` are exercised through
`tests/properties.ch` (textbook call/put agreement,
finite-difference-delta smoke, and optimized-vs-textbook-MC
properties). Grad-vs-textbook Greek runtime properties are deferred
until the full pricing body is IR-lowerable under host-runtime `grad`.

Phase oracle: the Chelis-monorepo-side
`cargo test -p chelis-cli --test phase3l_shoals_oracle phase3l_shoals_oracle -- --ignored --exact --nocapture`
is a manual gate and is not exercised from this repo. The Shoals
default PR scope ends at `chelis reef build` going green; runtime tests
remain available as the explicit manual gate above.

## Known limitations in v0.3.1

1. **`@property` is design-only.** Compiler v0.6.1 does not parse the
   annotation; the property bodies are plain `def`s that flip to
   `@property` when `chelis fuzz` ships. See above.
2. **`chelis manifest` is design-only.** The MC reproducibility
   contract is enforced by the `Random` effect (the compiler refuses
   unseeded random ops at type-check time). The JSON manifest artifact
   for CI is a Chelis-side follow-up.
3. **MC convergence runtime tests are manual/local.** The 20 000-path
   test uses 2 % tolerance and needs `chelis test tests/ --timeout 120`
   because it takes ~60 s under the v0.6.1 host evaluator. The 100
   000-path / 1 % spec-rigor tier lives at `manual-gates/mc_rigorous.ch`
   and is invoked explicitly (see "Manual rigor gate" above). The
   default PR gate stops at compiler/package validation instead of
   spending CI time in the Shoals host-runtime evaluator.
4. **Single-curve bootstrap only.** `bootstrap_zero_from_par`
   handles the integer-year-spaced case (one coupon per pillar). A
   multi-curve / non-uniform-spacing variant is a v0.2 candidate.
5. **`erfc` direct routing.** Per Chelis architecture, special
   functions live in `Nautilus.Special`. As of `nautilus 0.6.1`
   Shoals routes Black-Scholes through `Nautilus.Special.erfc`
   directly (computing `0.5 * erfc(-x / sqrt(2))` for the standard
   normal CDF), bypassing the higher-level distribution wrapper. No
   shell-private special functions are shipped.

### Layout (canonical, since v0.1.0)

Per the trust stack spec, `properties/` and `references/` are top-level
directories alongside `src/`. Shoals v0.1.0 shipped at the canonical layout
following the chelis-reef v0.4.1 multi-source-roots fix
(`6b58030 feat(reef): multi-source-roots — additional_sources in reef.toml;
bump v0.4.1`). The reef.toml declares
`additional_sources = ["properties", "references"]`. v0.3.1 carries the
canonical layout forward and pins chelis 0.6.1, nautilus 0.6.1, and
coral 0.6.1.

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
