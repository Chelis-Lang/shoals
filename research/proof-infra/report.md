# C Proof and Shoals: Reachability Map and Demonstrations

A research report on what C Proof can actually prove about real financial and economic
models, with the small set of demonstrations the map says are real.

Compiler: SMT-enabled chelis 0.7.27 (`/home/jeff/Documents/scratch/chelis/target/release/chelis`).
All results are reproducible from `RUNBOOK.md`; raw evidence is in `runs/`.

---

## 1. Executive summary

C Proof's verification stack is real and shipped: `chelis prove` runs three tiers,
Tier A (type), Tier B (SMT via cvc5 over the reals), Tier C (fuzz). The central question
was whether "proven" is a real pillar for finance and economics. The answer from the
experiments:

- **"Proven" is real, but it is strongest on economic and dynamic-programming structure,
  not on option Greeks.** Nine economic properties (Markov simplex preservation, Bellman
  monotonicity / boundedness / contraction, asset-pricing positivity and monotonicity)
  reach the SMT tier with no caveat. On the derivatives side three structural properties
  reach the SMT tier (upper bound `C<=S`, put-call parity, delta in `[0,1]`), but only as
  a **composite claim**: the structure is proven given a contract on the transcendental,
  and that contract is separately validated on the real implementation. No derivatives
  green proves the shipped pricer end to end.
- **Opaque-invariant abstraction works** and is the only path from synthetic green to
  green on something a quant recognizes. The decisive subtlety: put-call parity is not a
  free identity under abstraction, it needs the reflection invariant `N(-x)=1-N(x)`; and
  non-negativity and the intrinsic bound are not provable from local invariants on
  `N(d1)`, `N(d2)` at all.
- **End-to-end AD produces the full Greek set** through a real Black-Scholes body and
  validates against the oracle. Contrary to the going-in assumption, the transcendental is
  not the blocker: `grad` differentiates the normal-CDF path because `erf` is a library
  function of differentiable primitives. The blockers are elsewhere (host-lane list
  combinators; an f64 capture bug).
- **The counterexample tier catches business-wrong models** that are type-safe and run
  cleanly, returning a concrete violating assignment whose bindings name the error.

The positioning consequence is in Section 8.

---

## 2. The verification stack (ground truth)

`chelis prove [PATH] --tier auto|smt-only|fuzz-only|type-only [--smt-timeout ms] [--samples N --seed S] [--json]`

- **Tier A (type):** dimension / effect / linearity, structural, no runtime cost.
- **Tier B (SMT):** lowers the predicate to **cvc5** over the **reals** (`QF_NRA` /
  `QF_NRAT`). Reasoning is over the reals; **no IEEE-float soundness is claimed.** (The
  spec records this as `arith_model:"real"` on derived-obligation records; our probes are
  `@property` records, which do not carry the field, so we do not present it as an emitted
  artifact.)
- **Tier C (fuzz):** seeded sampling with preconditions and invariant rejection-sampling;
  returns the first deterministic counterexample (bindings as JSON; shrinking deferred).
- `auto` escalates A to B to C. JSON status is one of passed / failed / unsupported /
  error; `proof_tier` is smt or fuzz.

**Decisive fragment fact.** cvc5-lowerable intrinsics are `exp, sqrt, sin, cos, abs, min,
max`. **`log` and `erf` are NOT lowerable** (cvc5 has no LOG kind; erf is not
whitelisted), so they route to Tier C. Shoals computes `N(d)` via `erfc` and uses `log`
in every `d1`, so the real pricing bodies cannot be discharged directly. **Abstraction is
mandatory, not optional.**

Two harness facts shaped the method: `chelis prove` type-checks a file in isolation and
does not resolve package imports, so structural proofs use self-contained probes; numeric
validation that needs real Nautilus/Shoals code runs in a sub-package via `reef build` +
`chelis test`.

---

## 3. What a Tier-B green means (scoping discipline)

A Tier-B green proves the financial **structure given a contract on the transcendental.
It does not prove the shipped pricing function.** Because `erf`/`log` are not lowerable,
the link between the opaque symbol `nd1` and the real `N(d1)` is asserted, not
machine-checked. Every derivatives green is therefore stated as a **composite**:

> structure proven at Tier B for any `N` satisfying its contract, AND the contract
> (`0<=N<=1`, reflection `N(-x)=1-N(x)`, `0<=disc<=1`) separately validated on the real
> implementation at Tier C.

Three integrity checks gate every smt-proven green, so a badge cannot be vacuous or rest
on a false premise:

1. **Soundness dependence:** swapping a sound invariant for an unsound variant must flip
   the result.
2. **Joint satisfiability:** cvc5 must find a model for the invariant set alone
   (`forall(...) where <invariants>: false` returns `failed` with a witness), the SMT
   analog of `samples>0`. A contradictory premise set would prove anything vacuously.
3. **Transcendental-free goal:** after abstraction the goal must be polynomial in the
   bounded symbols (decidable real arithmetic), never carrying a residual `exp`/`sqrt`/
   `log` that would rely on cvc5's heuristic transcendental extension.

A cvc5 `unknown` or timeout is recorded as **unsupported (solver capacity)**, never as a
refutation. Only a concrete counterexample is a refutation.

---

## 4. Track A: derivatives reachability map

Abstraction: each transcendental output is a bounded free parameter carrying its true
contract. `nd1=N(d1)`, `nd2=N(d2)`, `nd1c=N(-d1)`, `nd2c=N(-d2)` in `[0,1]`;
`disc=exp(-r t)` in `[0,1]`; `s,k>=0`. Abstracted bodies are exactly the `Shoals.Pricing`
structure with transcendentals lifted: `C = s*nd1 - k*disc*nd2`,
`P = k*disc*nd2c - s*nd1c`. Evidence: `runs/trackA_*.ndjson|txt`,
`derivatives/RESULTS.md`.

| property | bucket | invariants (all sound) |
|---|---|---|
| upper bound `C<=S` | **smt-proven** | ranges of nd1,nd2,disc; s,k>=0 |
| put-call parity `C-P=S-K·disc` | **smt-proven** | ranges + reflection nd1c=1-nd1, nd2c=1-nd2 |
| delta `N(d1) in [0,1]` (monotone in spot) | **smt-proven** | range of nd1 |
| non-negativity `C>=0` | smt-refuted | ranges only (cex nd1=0,nd2=1) |
| non-negativity + monotone coupling nd1>=nd2 | smt-refuted | monotone coupling insufficient |
| intrinsic lower bound `C>=S-K·disc` | smt-refuted | needs the moneyness coupling |
| strike convexity (butterfly>=0) | smt-refuted | needs a density-convexity coupling |

**Composite headline.** Upper bound and parity are the first finance structural
properties to reach green via sound abstraction. The contracts they rest on are validated
on the real implementation (`0.5*erfc(-x/sqrt2)`, `exp(-r t)`): the `contract/`
sub-package grid tests pass 3/3 (range, reflection, disc range,
`runs/trackA_contract_test.ndjson`), and the oracle confirms the real `n_cdf` is
numerically correct vs scipy (Section 7).

**Integrity.** The three consistency witnesses (`a_sat_*`) all return `failed`
(satisfiable, non-vacuous); both soundness-dependence probes (`nd1<=2`, `nd1c=1-2·nd1`)
flip a proven green to `failed`; every proven goal is transcendental-free. No structural
probe timed out at 20s. The capacity bucket is demonstrated by the SAME true goal being
`passed` at 20000ms and `unsupported` (exit 2), never `failed`, at 1ms
(`runs/trackA_capacity_smt.txt`). cvc5's transcendental extension did prove `exp(x)>=1+x`
and sqrt-monotonicity here, which is why the structural greens are kept transcendental-free
by construction rather than relying on it.

**Negative-space finding (a result, not a failure).** Non-negativity and the intrinsic
bound are not provable from local invariants on `N(d1)`, `N(d2)`: they require the
relationship between `d1`, `d2` and the moneyness (`s` vs `k·disc`), which is exactly the
transcendental structure the value-level abstraction discards. Even the sound monotonicity
coupling `nd1>=nd2` does not rescue them. Strike convexity needs a density-convexity
coupling not expressible at the value level. These are honest "unsupported via value-level
abstraction" results.

---

## 5. Track B: end-to-end AD for the Greek set

Self-contained f64 Black-Scholes body (`ad/` sub-package, dependency nautilus 0.7.26),
same algebraic structure as `references/blackscholes.ch` (an f64 reimplementation; `erf`
uses the same Abramowitz-Stegun coefficients as Nautilus, since the package symbol is
f32-only). Evidence: `runs/trackB_*`,
`ad/RESULTS.md`.

**AD feasibility (decisive).** `grad` CAN differentiate the normal-CDF path. `erf` is not
a RISC primitive but Nautilus implements it as the Abramowitz-Stegun rational
approximation built from differentiable primitives (`add/mul/div/sub/neg/exp`) and `if`
branches that lower to differentiable masked arithmetic. So the transcendental is not the
AD blocker. Confirmed empirically: `grad(erf)(0.5)` and `grad(n_cdf)(0.5)=phi(0.5)` match
analytic.

**Two real blockers found (honest infra findings).**
- The shipped `Shoals.Pricing` body prices per-spot via a host-lane list combinator
  (`to_tensor(map(..., to_list(copy(spots))))`); `grad` cannot lower it
  (`sum` over a rank-0 placeholder). Identical math on the pure tensor lane differentiates
  fine. The blocker is the combinator, independent of erf.
- `grad` fails when a closure captures a free f64 variable across the grad boundary
  ("mismatched precisions F64 vs F32"), and nested `grad(grad(named_fn))` is not lowered
  by the host evaluator. Workaround: inline non-differentiated args as literals; use the
  nested-lambda form for second order. Both are documented with minimal repros.

**Greek validation (two independent comparisons).** Grid of 24 cells
(S in {80,100,120}, r in {.01,.05}, sigma in {.15,.30}, t in {.25,2.0}), f64.

| Greek | via | AD vs FD of same body (isolates AD) | AD vs analytic oracle (isolates erf model) |
|---|---|---|---|
| delta | grad | 8.3e-11 abs (≈ eps^{2/3} FD floor) | 1.9e-4 rel |
| vega | grad | 1.9e-9 abs | 1.8e-4 rel |
| rho | grad | 3.4e-9 abs | 2.0e-4 rel |
| theta | grad | 1.1e-9 abs | 1.8e-4 rel |
| gamma | grad(grad) | 5.5e-9 abs (≈ sqrt(eps) FD floor) | 2.6e-3 rel |
| volga | grad(grad) | 1.0e-5 abs | 5.1e-2 rel (small denom) |
| vanna | grad(grad), cross | 1.9e-4 abs (mixed-stencil floor) | 5.1e-2 rel (small denom) |

The FD comparison sits at the central-difference round-off floor, so **AD equals the true
derivative of the body**. The larger oracle gap is the A&S erf approximation's derivative
deviating from the exact gaussian (a modelling choice in Nautilus, not an AD error),
amplified by second differentiation. Bounds are derived from f64 machine epsilon, not
fixed percents.

**Sensitivity surface (vmap of grad).** AD delta over a 5-spot x 4-vol grid, each vol row
one `vmap(grad(...))` call (true batched grad, not a Python loop). 20/20 cells validated
vs analytic N(d1) (max abs 5.3e-6, max rel 2.7e-4): vmap composes with grad without loss.
Delta strictly increasing in spot in every row; surface steepens as sigma to 0.

**AD calibration.** A 2-parameter vol model `sigma(K) = a + b·ln(K/S)`, priced through the
chelis Black-Scholes body, recovered from 5-strike synthetic quotes by Adam gradient
descent on AD gradients. Over 6 random seeds all runs converge: parameter recovery error
max `a`=1.3e-6, max `b`=6.0e-6, final loss max 1.4e-8 (`runs/trackB_calibration.json`).
This is the engine doing real quant work (fit, not just price) on AD gradients, recovered
to f64 precision across seeds rather than a single case.

**Pairing with Track A (B5).** For delta the AD-derived value is paired with the Track A
Tier-B proof that its sign is non-negative across the abstracted domain (delta = N(d1) in
[0,1]). The number and the proof of its sign come from the two capabilities together.

---

## 6. Track C: economic-model reachability

Self-contained probes; all goals polynomial/linear with NO transcendental, so these
greens carry no contract caveat. Evidence: `runs/trackC_reachability_smt.ndjson`,
`economic/RESULTS.md`.

| property | meaning | bucket |
|---|---|---|
| `c_simplex_preserve_2` | 2-state stochastic matrix maps the simplex to itself | smt-proven |
| `c_simplex_sum_3` | 3-state row-stochastic preserves total mass = 1 | smt-proven |
| `c_bellman_monotone` | V<=W => TV<=TW | smt-proven |
| `c_bellman_bounded` | r,V bounded => TV bounded | smt-proven |
| `c_bellman_contraction` | -beta·d <= TV0-TW0 <= beta·d (modulus beta) | smt-proven |
| `c_pv_positive` | PV of a nonneg dividend stream >= 0 | smt-proven |
| `c_pv_monotone` | PV monotone in dividends | smt-proven |
| `c_gordon_positive` | p=d/(r-g) > 0 for d>0, r>g (cvc5 handles division) | smt-proven |
| `c_gordon_monotone` | Gordon price monotone in dividend | smt-proven |
| `c_simplex_no_rowsum_edge` | sum-preservation WITHOUT row-stochasticity | smt-refuted (edge) |

Integrity: the edge probe refutes when row-stochasticity is dropped; the soundness probe
(`rows sum to 1.5`) flips sum-preservation to `failed`; the consistency witnesses are
satisfiable; every goal is transcendental-free. The QuantEcon cross-check (Section 7)
confirms these invariants hold on canonical models including QuantEcon's own `DiscreteDP`.

**The asymmetry.** Nine economic properties are proven with no transcendental contract,
versus three derivatives properties that each need a separately-validated contract on `N`.
An economic green is structurally more complete than a derivatives green.

---

## 7. Oracle backbone (QuantEcon and scipy)

No property was proven about a model the engine computes wrong. Evidence:
`oracle/RESULTS.md`, `runs/oracle_*`. Versions: python 3.11.14, quantecon 0.11.2,
numpy 2.4.6, scipy 1.17.1, chelis 0.7.27. Tolerances derived from f64 eps.

- **Track C empirical oracle (14/14 PASS):** on 7 QuantEcon Markov chains (including a
  4-state two-recurrent-class chain) the stationary distributions are nonneg, sum to 1,
  and are fixed points to 1.11e-16; simplex preservation holds over 20000 random points;
  Bellman monotonicity and the contraction modulus hold over 30,000 random pairs each (5
  betas x 3 state-sizes x 2000); QuantEcon's own `DiscreteDP` value iteration matches the closed
  form to 4.71e-13; Gordon and PV positivity/monotonicity hold over large sweeps.
- **Honest methodology finding:** the contraction modulus measured as a naive
  successive-difference ratio initially exceeded beta in the convergence tail (float64
  catastrophic cancellation, not an invariant violation). The theorem
  `||TA-TB||<=beta||A-B||` holds exactly over the 30,000 random pairs; the artifact was
  resolved by measuring `||beta·P·y||/||y||` directly with a cancellation floor.
- **Track A normal-CDF backbone (PASS):** the chelis `n_cdf` is not just in-range but
  numerically correct vs scipy `ndtr`, max abs error 1.22e-7 (≈2 ulp) over 53 grid points,
  within the derived 8-ulp f32 bound; tails saturate to exactly 0 and 1. The contract the
  Track A greens assume is faithful to the canonical normal CDF.

---

## 8. Positioning finding

Where "proven" is real and on what:

- **Lead with economic and dynamic-programming structure.** Markov simplex preservation,
  the stationary distribution as a fixed point, Bellman monotonicity / boundedness /
  contraction, and asset-pricing positivity and monotonicity are genuinely SMT-proven over
  parametric families, with no transcendental contract and no float caveat beyond the
  reals-vs-IEEE gap that every Tier-B result carries. This is the strongest, cleanest
  "proven" story, and it is QuantEcon's home territory.
- **Derivatives "proven" is real but must be scoped.** Upper bound `C<=S`, put-call parity
  (with reflection), and delta sign/bounds are proven as composites: structure at Tier B
  plus a fuzz-validated contract on `N`. Lead with the composite, never with "Black-Scholes
  proven."
- **Where green is out of reach, lead with the other pillars.** Non-negativity, the
  intrinsic bound, and strike convexity are unsupported via value-level abstraction; for
  these the honest story is the AD-validated Greek set, dimension and shape safety, and the
  counterexample view that catches business-wrong models. End-to-end AD pays off
  regardless of the proof outcome, and it pairs with the prover: here is the Greek, and
  here is the proof its sign is right across the domain.

---

## 9. Infrastructure findings and caveats

- Tier B proofs are over the reals (QF_NRA / QF_NRAT), not IEEE float; no float-level
  soundness is claimed.
- `log` and `erf` are not cvc5-lowerable, which is why the opaque-symbol link is
  asserted-and-fuzz-validated rather than machine-checked.
- Clean polynomial goals are reliable; residual-transcendental goals rely on cvc5's
  heuristic extension (it succeeded on the cases tried, but the structural greens avoid it
  by construction).
- Five distinct AD blockers were found and captured (all worth filing upstream): (1) `grad`
  through the shipped host-lane `to_list`/`map`/`to_tensor` pricing body fails ("sum axis 0
  out of range for a rank-0 operand"); (2) `grad` of a closure capturing a free f64
  variable fails backward-DAG verification ("mismatched precisions F64 vs F32"); (3) nested
  `grad(grad(named_fn))` is not host-lowerable; (4) grad scalar outputs are rank-0 tensors
  that cannot be packed by `to_tensor` or asserted via `Std.Test`, so package-level Greeks
  compute correctly but cannot be `chelis test`-asserted (validated via `chelis eval`); (5)
  `chelis build --target c` wants the tensor-lane `grad(local, wrt=(arg))` form, a
  different lane from the host evaluator's scalar-f64 grad. AD of the Greek set works today
  via the pure-scalar-f64 body with non-differentiated args inlined. The clear graduation
  candidate: a tensor-lane, grad-able Black-Scholes body would make the shipped Greeks
  AD-derived and oracle-clean on both lanes.
- The SMT-enabled compiler is an optional build (`--features smt`, cvc5 linked via
  `cvc5-rs`); the stock 0.7.21 on PATH is not SMT-enabled.

---

## 10. Reproduction

See `RUNBOOK.md` for the exact binary and per-track commands. Every claimed result has a
captured record under `runs/`. Research probes live under `research/proof-infra/`
(`derivatives/`, `ad/`, `economic/`, `counterexample/`, `contract/`, `oracle/`); none of
the shipped Shoals surface (`src/`, `properties/`, `references/`, `tests/`, `reef.toml`)
was modified.
