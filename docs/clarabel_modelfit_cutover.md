# Clarabel QP step for bounded calibration

## Target

`Shoals.ModelFit.lm_bounded_nparam` builds a damped normal matrix, solves an
unconstrained linear system with `Nautilus.LinAlg.cg_solve`, and clamps the
resulting parameters into their bounds. The candidate cutover uses
`Clarabel.Qp.solve` for the **bounded quadratic step** inside that iteration.
The nonlinear model evaluation, loss comparison, damping update, and stopping
rule remain Shoals decisions.

This is a prospective integration. `reef.toml` pins a published Chelis
toolchain that predates the native Clarabel provider. The Shoals package and
its tests continue to use the pinned toolchain until a compatible provider
binary and the source-bound `chelis-clarabel` package are published. This
document adds no runtime dependency or exported function.

## Quadratic subproblem

At parameters `theta`, let `r = observed - model(theta, features)`, let `J`
be the finite-difference Jacobian of the model prediction, and let `W` be
the diagonal matrix of nonnegative weights. Shoals constructs

```
g = Jᵀ W r
H = Jᵀ W J + lambda D
D[i,i] = max((Jᵀ W J)[i,i], 1e-7)
```

The proposed step `d` minimizes `0.5 dᵀ H d - gᵀ d` subject to
`lo <= theta + d <= hi`. For the Clarabel API, use `P = H`, `q = -g`,
`A = [I; -I]`, `b = [hi - theta; theta - lo]`, and
`[NonnegativeCone(2*n)]`. This gives `A d + s = b` with `s >= 0`.
Finite `theta`, bounds, residuals, Jacobian entries, and weights are required;
each weight is nonnegative, each lower bound is at most its upper bound, and
`lambda` is positive. These conditions make the constructed `H` symmetric
positive definite in exact arithmetic when `n > 0`, including rank-deficient
Jacobians. Build the floating-point matrix symmetrically and validate it
before the provider's symmetric-input check; mathematical symmetry alone does
not ensure its stored entries are bitwise symmetric. A numerical rejection is
an explicit subproblem failure. An empty parameter vector needs an explicit
zero-dimensional case rather than a solver call whose cone partition is
ambiguous.

The change is observable even for a small convex step. For
`H = [[2, 1], [1, 2]]`, `g = [-1, 1]`, `theta = [0, 0]`, and bounds
`[0, 2]` on both components, the unconstrained step is `[-1, 1]`.
Clamping it gives `[0, 1]`; the bound-constrained QP gives `[0, 0.5]`.
The implementation must compare against the constrained result, not assert
that the two algorithms are interchangeable.

## API and execution boundary

The first live implementation is an additive `f64` step API with an explicit
result that distinguishes a usable `Solved` primal from every `Stopped`
status. It must not change the existing `f32` `lm_bounded_nparam` signature
or silently convert an `f64` result back to `f32`. A later `f64` calibration
entry point can use the step after its model callback, Jacobian construction,
and callers have an explicit precision contract. Merely widening the current
`f32` Jacobian after it is computed does not make the model calculation
`f64` accurate.

On `Solved`, check the primal and diagnostics for finiteness and check bound
violations against a caller-visible tolerance. Project only violations
within that tolerance, report the projection size, and evaluate the actual
nonlinear weighted loss before accepting an iterate. A projected point is a
distinct value from Clarabel's primal and carries no exact optimizer claim.
On `Stopped`, preserve the last accepted iterate and return the solver status;
neither a candidate vector nor a hidden `cg_solve` fallback counts as a
successful step. The outer fit result must distinguish loss convergence,
iteration limit, and subproblem failure.

`chelis-clarabel` binds the provider to its dependency-owned `solve` source.
Shoals must depend on the published package without copying or editing its
`src/qp.ch`. The consuming toolchain must carry the `clarabel-provider`
feature for evaluator and compiled-C calls. An optional pilot package in this
repository can exercise the new path before the main Shoals manifest takes
the dependency; its build and test route must use the released toolchain and
must leave unrelated Shoals CI paths on their existing fast route.

## Proof boundary

`clarabel.qp.ideal_optimality` is an opt-in, exact-real assumption tied to a
specific `Solved` call. Chelis's first lowering covers fixed literal QP
data with zero and nonnegative cones. A calibration step constructs `H`, `g`,
and bounds from runtime inputs, so the ideal contract does not presently
prove general calibration results. A literal two-parameter witness can test
the proof path and must report `proven_modulo_asserted_axiom` with
`real_arithmetic`. Claims about returned floating-point parameters need a
separate checked error bound; neither `Solved` nor requested tolerances
provide one by themselves. Differentiating through the solver is a separate
piece of work.

## Cutover acceptance

1. Publish a Chelis toolchain containing the native provider and a matching
   source-bound `chelis-clarabel` package. Verify the feature-bearing release
   artifact on the target platforms, then update Shoals's compiler pin and
   workflow pins through its pin-bump checklist.
2. Add an isolated QP-step pilot with evaluator and compiled-C tests for an
   interior solution, an active lower bound, an active upper bound, and the
   coupled two-parameter example above. Exercise a `Stopped` status and
   reject negative weights, reversed bounds, nonfinite inputs, and invalid
   damping. Keep the legacy `f32` path callable for comparison.
3. Add a `f64` calibration entry point using that step. Compare accepted
   iterates, true weighted losses, bounds, and termination statuses against
   an independent reference on affine and nonlinear models, including
   rank-deficient and ill-conditioned Jacobians. Run the same witnesses in
   the evaluator and compiled C.
4. Record the dependency resolution and nonuser CI cost before routing the
   new API into ordinary Shoals package builds. Only a later reviewed change
   can replace the existing `f32` default or retire its tests and callers.
