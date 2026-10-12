# Clarabel QP step for bounded calibration

## Target

`Shoals.ModelFit.lm_bounded_nparam` builds a damped normal matrix, solves an
unconstrained linear system with `Nautilus.LinAlg.cg_solve`, and clamps the
resulting parameters into their bounds. `Shoals.ModelFitClarabel` uses
`Clarabel.Qp.solve` for the **bounded quadratic step** inside that iteration.
The nonlinear model evaluation, loss comparison, damping update, and stopping
rule remain Shoals decisions.

The additive `Shoals.ModelFitClarabel` module implements this subproblem with
an `f64` solver call. Its `lm_bounded_nparam` entry point uses the step in
a bounded Levenberg-Marquardt fit. The existing `f32` entry point remains an
independent API. The module requires a provider-enabled Chelis toolchain and
the source-bound `chelis-clarabel` Reef package.

## Quadratic subproblem

At parameters `theta`, let `r = observed - model(theta, features)`, let `J`
be the finite-difference Jacobian of the model prediction, and let `W` be
the diagonal matrix of nonnegative weights. Shoals constructs

```
g = Jᵀ W r
H = Jᵀ W J + lambda D
D[i,i] = max((Jᵀ W J)[i,i], 1e-7)
```

The step `d` minimizes `0.5 dᵀ H d - gᵀ d` subject to
`lo <= theta + d <= hi`. For the Clarabel API, use `P = H`, `q = -g`,
`A = [I; -I]`, `b = [hi - theta; theta - lo]`, and
`[NonnegativeCone(2*n)]`. This gives `A d + s = b` with `s >= 0`.
Finite `theta`, bounds, residuals, Jacobian entries, and weights are required;
each weight is nonnegative, each lower bound is at most its upper bound, and
`lambda` is positive. These conditions make the constructed `H` symmetric
positive definite in exact arithmetic when `n > 0`, including rank-deficient
Jacobians. The implementation builds the floating-point matrix symmetrically
and validates it before the provider's symmetric-input check; mathematical
symmetry alone does not ensure its stored entries are bitwise symmetric. A
numerical rejection is an explicit subproblem failure. An empty parameter
vector is rejected before making a solver call.

The change is observable even for a small convex step. For
`H = [[2, 1], [1, 2]]`, `g = [-1, 1]`, `theta = [0, 0]`, and bounds
`[0, 2]` on both components, the unconstrained step is `[-1, 1]`.
Clamping it gives `[0, 1]`; the bound-constrained QP gives `[0, 0.5]`.
The coupled-step test checks the constrained result.

## API and execution boundary

`solve_bounded_step` exposes the `f64` QP result and keeps `Solved` distinct
from `Stopped`. `lm_bounded_nparam` computes its model prediction and
finite-difference Jacobian in `f64`; it does not widen an `f32` Jacobian.
Its result distinguishes convergence, outer iteration limit, stopped solver,
and numerical failure.

On `Solved`, the fit checks the primal and diagnostics for finiteness and
checks bound violations against a caller-visible tolerance. It projects only
violations within that tolerance, reports the largest projection size in the
fit result, and evaluates the actual nonlinear weighted loss before accepting
an iterate. A projected point is a distinct value from
Clarabel's primal and carries no exact optimizer claim.
On `Stopped`, preserve the last accepted iterate and return the solver status;
neither a candidate vector nor a hidden `cg_solve` fallback counts as a
successful step. The outer fit result must distinguish loss convergence,
iteration limit, and subproblem failure.

`chelis-clarabel` binds the provider to its dependency-owned `solve` source.
Shoals depends on the published package without copying or editing its
`src/qp.ch`. The consuming toolchain carries the `clarabel-provider` feature
for evaluator and compiled-C calls. The generic QP step builds through C;
the calibration function currently requires evaluator execution because
compiled C cannot pass its model callback through helper calls (chelis#879).

## Proof boundary

`clarabel.qp.ideal_optimality` is an opt-in, exact-real assumption tied to a
specific `Solved` call. The proof example constructs a fixed-size symbolic
positive semidefinite QP, applies its primal step through Shoals's
`apply_two_parameter_step`, and proves that the resulting quadratic quality is at least
that of a feasible baseline. The reversed claim is a refuted control. This
is a downstream property of a direct solver call, not a general proof about
the iterative fit. The proof lowerer does not resolve the generic
`solve_bounded_step` wrapper to one solver call; proving the full fit requires
further compiler support. The report must state
`proven_modulo_asserted_axiom` and
`real_arithmetic`. Claims about returned floating-point parameters require
a separate checked error bound; neither `Solved` nor requested tolerances
provide one by themselves. Differentiating through the solver is separate.

## Executable examples

`demos/clarabelmodelfit.ch` evaluates a coupled bounded QP step and fits an
affine model using `lm_bounded_nparam`. `demos/clarabelstep.ch` checks
interior, active lower and upper, coupled, and stopped QP results through
compiled C. Both return `main = true` when their checks pass:

```sh
chelis eval --file demos/clarabelmodelfit.ch
chelis build --target c --output target/clarabelstep demos/clarabelstep.ch
target/clarabelstep/clarabelstep
```

`properties/clarabelmodelfit.ch` calls the dependency-owned solver and then
uses `Shoals.ModelFitClarabel.apply_two_parameter_step` on its returned primal. In the
`Solved` branch it states that the quadratic quality after the step is at
least the quality after any feasible baseline step, for all supported
fixed-size inputs. The proof depends on `clarabel.qp.ideal_optimality`; it is
conditional exact-real reasoning, not a numerical guarantee about the actual
`f64` output. `tests/clarabel_proof_reversed.ch` reverses that inequality as a
negative control.

```sh
chelis prove properties/clarabelmodelfit.ch --tier smt-only --json
chelis prove tests/clarabel_proof_reversed.ch --tier smt-only --json
```

The first report must contain `proven_modulo_asserted_axiom` and
`real_arithmetic`. The reversed control must not prove.

## Cutover acceptance

1. Publish a Chelis toolchain containing the native provider and a matching
   source-bound `chelis-clarabel` package. Verify the feature-bearing release
   artifact on the target platforms, then update Shoals's compiler pin and
   workflow pins through its pin-bump checklist.
2. Test the QP step through the evaluator and compiled C for an
   interior solution, an active lower bound, an active upper bound, and the
   coupled two-parameter example above. Exercise a `Stopped` status and
   reject negative weights, reversed bounds, nonfinite inputs, and invalid
   damping. Keep the legacy `f32` path callable for comparison.
3. Test the `f64` calibration entry point against independent affine and
   nonlinear references, including rank-deficient and ill-conditioned
   Jacobians. Validate accepted iterates, true weighted losses, bounds, and
   termination statuses in the evaluator. Compiled-C fit parity awaits
   chelis#879; compiled-C QP-step parity remains required here.
4. Record the dependency resolution and nonuser CI cost before routing the
   new API into ordinary Shoals package builds. Only a later reviewed change
   can replace the existing `f32` default or retire its tests and callers.
