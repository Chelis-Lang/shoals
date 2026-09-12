# Track B: AD Greeks end-to-end — RESULTS

Goal: establish whether Chelis automatic differentiation (`grad`) can produce
the full option Greek set through a real Black-Scholes pricing body, validated
against an oracle.

> Dated run record. The `erf64` numbers below were measured against the A&S
> kernel; shoals#61 replaced it with Cody's approximation, so the recorded
> `grad(erf64)` residuals and the "same A&S coefficients as
> `Nautilus.Special.erf`" statements no longer describe the shipped body.
> Measured at that head: `grad(erf64)(0.5)` is within 8.5e-14 of analytic and
> `grad(n_cdf64)(0.5)` within 5.6e-17, not the A&S-era residuals recorded here.

Compiler: SMT-enabled chelis **0.7.27**
(`/home/jeff/Documents/scratch/chelis/target/release/chelis`).
All numbers below are reproduced by the captured command outputs in
`research/proof-infra/runs/trackB_*` and the scripts in this directory
(`harness.py`, `surface.py`, `calibrate.py`). Nothing under `src/`,
`properties/`, `references/`, `tests/`, `tests-manual/`, or `reef.toml` was
modified.

Self-contained sub-package: `research/proof-infra/ad/` (`reef.toml`,
`module_prefix = ProofInfraAd`, dependency `nautilus = 0.7.26`). Modules:
`bs.ch` (f64 Black-Scholes body), `greeks.ch` (AD Greeks), `step1blocker.ch`
(the host-lane reproduction). The Python harnesses drive `chelis eval` on
self-contained inline f64 expressions that inline the same body, which is how
the numeric tables are produced.

---

## STEP 0 — AD feasibility verdict (decisive)

**Verdict: `grad` CAN differentiate the normal-CDF path. The transcendental is
NOT a blocker.**

Evidence chain:

1. `erf`/`erfc` are **not** RISC primitives and have **no** adjoint rule.
   The elementwise-unary adjoint table
   (`chelis/spec/05-risc-primitives.md:89-100`) lists only
   `neg, recip, exp, log, sin, cos, tan, atan, sqrt, abs, floor, ceil`.
   `grep -i erf spec/05-risc-primitives.md` → no hit in the primitive set.
   So `erf` must be a *library function* of differentiable primitives.

2. It is. Nautilus `erf` (the 0.7.26 source, `src/special.ch:15-37`) is the
   Abramowitz–Stegun 7.1.26 rational approximation built from
   `add, mul, div, sub, neg, exp, cast` plus two `if` branches
   (small-|x| linearization and a sign fold). `erfc(x) = 1 - erf(x)`
   (`special.ch:38`). Every op has an adjoint rule.

3. `if`/`then`/`else` on a float result lowers to **differentiable masked
   arithmetic** `mask*then + (1-mask)*else`
   (`chelis/crates/chelis-ir/src/lower.rs:7443-7522`, `lower_if`). The mask is
   `cmplt`-based (zero gradient through the mask itself, per spec
   06 §2.7), but both branches are evaluated and the gradient flows through
   the active branch — standard "AD through select". So the branchy erf is
   fully differentiable a.e.

4. Empirical confirmation: `grad(erf64)(0.5) = 0.8787826714` vs analytic
   `2/√π·e^{-0.25} = 0.8787825789…` (agree to the A&S floor), and
   `grad(n_cdf64)(0.5) = 0.35206586` vs analytic φ(0.5)=0.35206533.
   (`runs/trackB_step0_erf_grad.txt`.)

Second-order AD (`grad(grad)`) is likewise supported through this path
(spec 05 §5 "Second-order derivatives"; `grad(grad)(x³)=6x` verified; gamma
below).

---

## STEP 1 — the known blocker, reproduced

The shipped Shoals `call_prices` (`src/pricing.ch:35-42`) prices per-spot via a
**host-lane list combinator**: `to_tensor(map(fn s -> bs_call_scalar(s,…),
to_list(copy(spots))))`, and `deltas_call` wraps `grad` around its `sum`.

Minimal reproduction (square body, only the combinator under test):

```
$ chelis eval 'grad(fn xv -> sum(to_tensor(map(square, to_list(copy(xv))))))(...)'
error: host runtime could not lower `grad(...)` for evaluation:
       `sum` axis 0 is out of range for an operand of rank 0
```

The `to_list`/`map`/`to_tensor` round-trip yields a rank-0 placeholder that
`grad` cannot reduce over. **Contrast** — identical math on the pure tensor
lane differentiates fine:

```
$ chelis eval 'grad(fn xv -> sum(mul(xv, xv)))(to_tensor([1,2,3]))'
tensor(shape=[3], data=[2.0, 4.0, 6.0])
```

So the blocker is the host-lane combinator, **independent of erf/erfc**.
(`runs/trackB_step1_blocker.txt`.)

---

## STEP 1.5 — a SECOND, separately-found compiler blocker: grad + f64 free-variable capture

While authoring the grad-able body, `grad` failed when a closure **captured a
free f64 variable** from an enclosing ordinary-function scope:

```
$ chelis eval '(fn (s: f64, k: f64) -> grad((fn (x: f64) -> mul(x, k)), wrt=x)(s))(3.0, 7.0)'
error: ... backward DAG failed verification:
       binary op at node 2 has mismatched precisions: F64 vs F32 ...
```

Characterization (minimal repros captured in `runs/trackB_capture_bug.txt`):

* f64 captured free var under grad → "mismatched precisions F64 vs F32".
* f32 captured free var under grad → "missing required input k".
* f64 constant **inlined** inside the grad'd lambda → works (`d/dx(7x)=7`).
* The spec-blessed form — `grad(named_fn, wrt=P)(args…)` passing every arg
  explicitly, or a lambda with non-diff args inlined as literals — works.

This matches spec 06 §2.10, which only blesses the explicit-parameter
`jac_row` wrapper pattern. Upshot for the harness: build Greek expressions with
all non-differentiated arguments inlined as literals (no capture across a grad
boundary). Nested `grad(grad(named_fn, wrt=..), wrt=..)` additionally is **not
lowered by the host evaluator** ("grad is not supported by IR evaluation yet")
— second-order Greeks must use the nested-lambda + inlined-literal form.

---

## STEP 2 — grad-able f64 Black-Scholes body

`bs.ch` / inline `BS_CALL`: a pure-scalar-`f64` Black-Scholes call/put using
only differentiable ops, with `n_cdf(x) = 0.5·erfc(-x/√2)` (the exact
Shoals/`references` expression) and `erf` = the same A&S coefficients as
Nautilus, in f64. No `to_list`/`map`/`fold`. Forward check:
`BS_CALL(100,100,0.05,0.2,1) = 10.45057542` (textbook ATM call).

In the host evaluator a scalar `f64` is a rank-0 tensor and
`grad(f, wrt=x)` differentiates it directly (the spec's "host lane has no AD"
caveat in 06 §2.10 is about `chelis build --target c`; the **evaluator** does
scalar AD). This is the key enabler: the whole Greek set is reachable without
any tensor-shape/broadcast plumbing.

---

## STEP 3 — validation (tight, precision-derived, no fixed percent)

Grid: S ∈ {80,100,120} (OTM/ATM/ITM, K=100), r ∈ {0.01,0.05},
σ ∈ {0.15,0.30}, t ∈ {0.25,2.0} → 24 cells. Run in f64.
(`runs/trackB_grid.json`, produced by `harness.py`.)

Two independent comparisons (this separation is the main rigor point):

### (a) AD vs finite differences of the *same chelis body* — isolates the AD chain rule
Central differences of `BS_CALL`, step **tuned** per Greek (swept; reported step
is the one nearest the truncation/round-off floor). At S=100,r=0.05,σ=0.2,t=1:

| Greek | order | AD value | best tuned-FD | |AD − FD| | FD step |
|---|---|---|---|---|---|
| delta | 1 | 0.6368358224 | 0.6368358223 | 8.3e-11 | h=1e-5·S |
| vega  | 1 | 37.52387193 | 37.52387194 | 1.9e-9 | h=1e-5·σ |
| rho   | 1 | 53.23300682 | 53.23300682 | 3.4e-9 | h=5e-6 |
| theta | 1 | −6.414037534 | −6.414037535 | 1.1e-9 | h=1e-5·t |
| gamma | 2 | 0.0187633763 | 0.0187633708 | 5.5e-9 | h=0.1·S |
| volga | 2 | 9.851781846 | 9.851792271 | 1.0e-5 | h swept |
| vanna | 2 (mixed) | −0.281479472 | −0.281291427 | 1.9e-4 | 4-pt stencil |

**Derivation of the bound.** Central FD has error
≈ (h²/6)·f''' (truncation) + (ε·|f|)/h (round-off), minimized at
h* ∼ (ε)^{1/3} with floor ∼ ε^{2/3}|f| (ε = f64 machine eps ≈ 2.2e-16,
ε^{2/3} ≈ 3.7e-11). First-order results sit at 1e-9–1e-11 — i.e. **AD equals
the true derivative of the body down to the FD floor.** Second-order central
differences have floor ∼ √ε·|f''| (gamma/volga) and the 4-point mixed stencil
∼ ε^{1/2} amplified by the cross step (vanna), explaining the 1e-9/1e-5/1e-4
floors respectively. The gamma step-sweep is monotone toward AD as h↓
(`runs/trackB_grid.json` fd.gamma.sweep), confirming AD is the limit, not an
artifact.

### (b) AD vs analytic textbook oracle (same n_cdf / pdf) — isolates the erf-model error
Max over the 24-cell grid:

| Greek | max abs err | max rel err | worst cell |
|---|---|---|---|
| delta | 3.5e-7 | 1.9e-4 | S=80,σ=.15,t=.25 (deep OTM, short) |
| vega  | 4.3e-5 | 1.8e-4 | S=80,σ=.15,t=.25 |
| rho   | 7.1e-6 | 2.0e-4 | S=80,σ=.15,t=.25 |
| theta | 1.3e-5 | 1.8e-4 | S=80,σ=.15,t=.25 |
| gamma | 1.4e-4 | 2.6e-3 | S=100,σ=.15,t=.25 |
| vanna | 5.6e-4 | 5.1e-2 (on a 0.011 value) | S=100,σ=.15,t=.25 |
| volga | 1.1e-2 | 5.1e-2 (on a −0.039 value) | S=120,σ=.15,t=2 |

These are LARGER than (a) because the oracle's gamma/vega/etc. use the exact
closed-form pdf `e^{-x²/2}/√(2π)`, while the AD path differentiates the **A&S
rational erf approximation** whose derivative deviates from the true gaussian
by ~1e-4 in the tail; second differentiation amplifies it. This is a property
of the erf MODEL (a Nautilus/Shoals modelling choice), not of AD.

### (c) Fidelity to a true-erf reference and to Shoals' algebra
`BS_CALL` (A&S erf) vs Python `math.erf` BS differs by ~1e-5 in *price* across
4 ITM/ATM/OTM/short cells (`runs/trackB_fidelity.txt`) — exactly the A&S
approximation error. The body's algebra is byte-identical to
`references/blackscholes.ch` (same `n_cdf = 0.5·erfc(-x/√2)`, same d1/d2, same
call formula) and the same A&S coefficients as `Nautilus.Special.erf`; the only
difference is f32→f64 widening of the literals.

**Per-Greek scorecard** (derivable / validated / precision-derived bound):

| Greek | AD? | validated (AD vs FD of same body) | erf-model bound (AD vs analytic) |
|---|---|---|---|
| delta | yes (`grad`) | 8.3e-11 abs (≈ ε^{2/3} FD floor) | 1.9e-4 rel |
| vega  | yes (`grad`) | 1.9e-9 abs | 1.8e-4 rel |
| rho   | yes (`grad`) | 3.4e-9 abs | 2.0e-4 rel |
| theta | yes (`grad`, = −dC/dt) | 1.1e-9 abs | 1.8e-4 rel |
| gamma | yes (`grad(grad)`) | 5.5e-9 abs (≈ √ε FD floor) | 2.6e-3 rel |
| volga | yes (`grad(grad)`) | 1.0e-5 abs | 5.1e-2 rel (small denom) |
| vanna | yes (`grad(grad)`, cross) | 1.9e-4 abs (mixed-stencil floor) | 5.1e-2 rel (small denom) |

---

## STEP 4a — sensitivity surface via vmap(grad)

`surface.py`: AD delta over a 5-spot × 4-vol grid (S∈{70,85,100,115,130},
σ∈{0.10,0.20,0.30,0.40}, K=100,r=0.05,t=1). Each vol row is **one
`vmap(grad(price_of_spot))` call** returning the per-spot delta vector in a
single batched evaluation — a true vmap-of-grad, not a Python map over scalar
grad calls. (`runs/trackB_surface.json`.)

* 20/20 cells validated vs independent true-erf analytic delta N(d1):
  **max abs err 5.3e-6, max rel err 2.7e-4** (the A&S erf floor, identical to
  scalar AD — so vmap composes with grad without loss).
* Structural check: delta strictly increasing in spot in **every** vol row;
  surface steepens as σ→0 (toward the digital limit), flattens as σ grows.

`vmap(grad(...))` is supported in the host evaluator when the per-example
function takes a **tensor** element (verified: `vmap(grad(sum(row²)))` →
per-row 2·row). `vmap` of a bare scalar `f64` function is a type error, so the
batched variable is carried as a 1-vector and read with `tensor_to_scalar(sum(row,0))`.

## STEP 4b — AD calibration of a 2-parameter vol model

`calibrate.py`: fit a linear-in-log-moneyness vol curve
`sigma(K) = a + b·ln(K/S)` priced through the chelis BS body. Synthetic target
prices are generated at 5 strikes {80,90,100,110,120} from KNOWN (a*, b*);
(a, b) are then recovered from those quotes by **Adam gradient descent on the
sum of squared price errors**, where d/d(a,b) is computed by chelis AD (`grad`,
non-fit quantities inlined as literals — the no-capture form). 6 random seeds,
random starts offset from truth. (`runs/trackB_calibration.json`.)

| | a (vol level) | b (skew slope) | final loss |
|---|---|---|---|
| max recovery err | 1.3e-6 | 6.0e-6 | 1.4e-8 |
| mean recovery err | 6.9e-7 | 2.3e-6 | — |

Per-seed recovery (|fit − true|), all converged:

| seed | a* → a_fit | a_err | b* → b_fit | b_err | final loss |
|---|---|---|---|---|---|
| 0 | 0.2305 → 0.2305 | 4.7e-7 | −0.0790 → −0.0790 | 2.0e-6 | 1.8e-9 |
| 1 | 0.1827 → 0.1827 | 9.7e-8 | −0.0362 → −0.0362 | 8.5e-7 | 1.2e-10 |
| 2 | 0.1644 → 0.1644 | 1.0e-6 | −0.1047 → −0.1047 | 3.2e-6 | 5.9e-9 |
| 3 | 0.2397 → 0.2397 | 1.2e-6 | −0.0231 → −0.0231 | 6.0e-6 | 1.4e-8 |
| 4 | 0.2678 → 0.2678 | 1.3e-6 | −0.0210 → −0.0210 | 1.2e-6 | 1.0e-8 |
| 5 | 0.1828 → 0.1828 | 5.2e-8 | −0.0638 → −0.0638 | 5.0e-7 | 3.6e-11 |

All 6 seeds converge; both parameters recovered to ~1e-6 (skew slope `b` is
identified by the price spread across strikes, the vol level `a` by overall
price). Plain GD with a hand-tuned lr=1e-4 also recovers (a≈0.220, b≈0.078 for
the smoke case), but Adam removes the per-seed lr sensitivity caused by the
poorly-scaled raw price-error gradient (gradient magnitude ∼ 2·Σresid·vega ∼
O(100s)). This is a genuine end-to-end AD calibration: the optimizer never sees
an analytic gradient — only `grad` of the chelis pricing body.

---

## STEP 1.6 — runtime representation quirk: grad scalar output is a rank-0 tensor

A grad scalar output is statically typed `f64` but is a **rank-0 tensor at
runtime**. This breaks composition with scalar-only ops:

* `to_tensor([grad(...)(x), …])` → "to_tensor expects numeric or bool list
  elements, got Tensor(... shape: [])" — the value is correct
  (0.6368358223564237) but can't be packed.
* `lt(grad(...)(x), bound)` yields a **Bool tensor**, which `assert_true` /
  `and` / `if` reject ("expected bool arg … got Tensor(… precision: Bool)").

Consequence: package-level Greeks in `src/greeks.ch` (which use the supported
`grad(bs_call, wrt=P)(args…)` form) **compute the correct values**
(`runs/trackB_package_greeks.txt` shows delta 0.6368358224, vega 37.52387193,
rho 53.23300682, dC/dt 6.41403753 — all matching the validated grid), but they
cannot be asserted through `Std.Test` in `chelis test` nor packed via
`to_tensor`. The working validation path is inline `chelis eval`, which prints
the rank-0 tensor directly. This is why the numeric tables are produced by the
Python harness over `chelis eval`, not by a `chelis test` suite.

---

## What AD reaches today vs what is blocked upstream

**AD reaches (validated):** the full first-order Greek set (delta, vega, rho,
theta) via `grad`, and the second-order set (gamma, volga, vanna) via nested
grad — all through a real Black-Scholes body whose normal CDF is the exact
Shoals expression over the Nautilus A&S erf. AD agrees with finite differences
of the same body to the FD precision floor (1e-9 first-order, 1e-5/1e-4
second-order). One vmap(grad) delta surface and one 6-seed AD calibration both
succeed.

**Blocked upstream (with evidence):**

1. `grad` through the shipped host-lane `to_list`/`map`/`to_tensor` pricing body
   (`src/pricing.ch:35-42`): host runtime cannot lower — "`sum` axis 0 is out
   of range for an operand of rank 0". The pure-tensor/pure-scalar lane is the
   workaround. (`runs/trackB_step1_blocker.txt`.)

2. `grad` of a closure that **captures a free f64 variable** from an enclosing
   ordinary-function scope: backward-DAG verification fails with "mismatched
   precisions F64 vs F32" (f64) / "missing required input" (f32). Must pass all
   args explicitly via `grad(named_fn, wrt=P)`, or inline non-diff args as
   literals. (`runs/trackB_capture_bug.txt`; minimal repro
   `grad((fn x -> mul(x, k)), wrt=x)` with captured `k`.)

3. Nested `grad(grad(named_fn, wrt=..), wrt=..)` is **not lowered by the host
   evaluator** ("grad is not supported by IR evaluation yet; use
   `chelis build --target c`"). Second-order Greeks must use the
   nested-lambda + inlined-literal form. (`runs/trackB_capture_bug.txt` (5).)

4. Grad scalar outputs are rank-0 tensors that don't interoperate with
   `to_tensor` / `Std.Test` scalar-bool assertions (STEP 1.6).

5. `vmap` of a bare scalar `f64` function is a type error
   (`f64 vs tensor[…]`); the per-example function must take a tensor element,
   so the batched variable is carried as a 1-vector and read with
   `tensor_to_scalar(sum(row,0))`. Not a blocker — a calling-convention
   constraint. (`surface.py`.)

6. `chelis build --target c` rejects `src/greeks.ch`'s grad forms too, but for
   a DIFFERENT reason than the host evaluator: "their body applies/binds `grad`
   in a position the host lane can't resolve (inline `grad(f)(x)`)", and the
   suggested workaround requires the differentiated function to use **only pure
   tensor ops (sum, add, mul, einsum)**. The scalar-`f64` BS body (with `if`
   and the erf rational) does not fit the C-target tensor-lane AD pattern.
   (`runs/trackB_ctarget_greeks.txt`.)

**Two AD lanes, different constraints.** The **host evaluator** (`chelis eval`)
supports inline scalar-`f64` `grad`/`grad(grad)` — this is the lane that makes
the whole scalar Greek set reachable and is how every number here was produced.
`chelis build --target c` supports a separate **tensor-lane** AD that wants the
`grad(local, wrt=(arg))` pure-tensor-op pattern (spec/06 §2.10) and does not
accept the scalar/inline form. A production Greek pipeline targeting C would
need the body rewritten into the pure-tensor-lane pattern; the host evaluator
already differentiates the scalar body as-is.

Net: the transcendental / normal-CDF path that the brief flagged as the
suspected hard blocker is **fully differentiable**; the real friction is in the
host-lane combinators, closure capture, host-side nested-grad lowering, and the
rank-0-tensor scalar representation — all worked around in this track, with
items 1–4 being concrete upstream issues worth filing.
