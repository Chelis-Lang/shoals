# Package verification manifest

Maintainer note, not part of the user book: this describes the frozen
invariant surface that C Note vendors (see the Characterization Contract in
`AGENTS.md`).

Shoals publishes a machine-readable invariant manifest alongside its Reef
package. Its source in this checkout is
[`cnote-import-surface.json`](cnote-import-surface.json).
The `pkg_version` and `chelis_pin` fields identify the package and compiler
version; `reef.toml` declares this checkout's compiler and dependency versions.
Compare those versions when checking a particular release.

The manifest names models, the properties checked for them, the expected verification method, and the dependencies that the compiler must attribute to each check. The expected method is a requirement for the release gate, not a claim that every mathematical input has been proved. A `fuzz_validated` result covers accepted samples under declared seeds and constraints. Some small arithmetic models have SMT-backed results. Certified-box and global differentiation claims are separate from the sampled automatic-differentiation comparisons.

## Pricing and Greeks

`Shoals.Pricing` exports scalar and tensor Black-Scholes prices, a tensor-valued f64 entry for verification, seeded Monte Carlo pricing, and automatic-differentiation Greeks. The call Greeks are compared on selected inputs with finite differences of `bs_call_scalar`. The scalar pricer and `bs_call_wire_f64` use different normal-CDF approximations, so agreement tests give bounds rather than identity. For the API and numerical limits, see [Pricing](src/pricing.md) and [Scope and limitations](src/scope.md).

The composite property checks under `Shoals.Properties.Composites` use contracts on `Std.Contracts.normal_cdf`. Their structural result applies to that contracted f32 CDF. The shipped pricer uses its own f64 CDF; `tests/composites_binding.ch` compares representative prices. That comparison does not turn the structural result into a global theorem about the shipped pricer.

## Risk and demonstrations

The manifest separates parametric Gaussian and historical empirical-quantile VaR/expected-shortfall checks. Each family has sampled confidence-monotonicity, dominance, and positive-loss properties. `properties/` contains the checkable predicates and `demos/` contains wrong models and controls. See [Property specifications](src/properties.md) and [Counterexample demos](src/demos.md) for interpretation.

For the exact release method, constraints, dependency edges, and test inputs, inspect the manifest and the targeted checks in `scripts/prove_gate.py`. Do not infer a stronger result from a green test than its recorded method supports.
