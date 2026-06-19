#!/usr/bin/env python3
"""Task 1: QuantEcon as empirical oracle for the Track C SMT-proven invariants.

Track C proved, structurally (over parametric families), at the SMT tier:
  - Markov: a row-stochastic matrix maps the probability simplex to itself
    (entries stay >=0, total mass stays 1); the stationary distribution is a
    fixed point (pi @ P == pi).
  - Bellman operator (T V) = r + beta * P V: monotonicity (V<=W => TV<=TW),
    boundedness, and contraction with modulus beta
    (||TV-TW||_inf <= beta ||V-W||_inf).
  - Asset pricing: PV of a nonneg dividend stream is nonneg/monotone; Gordon
    growth p=d/(r-g)>0 and monotone in d for d>0, r>g.

This script confirms those invariants hold *empirically* on real QuantEcon models,
so the SMT abstraction is faithful to the canonical models. A FAIL here would mean
the abstraction diverges from the textbook model the engine claims to compute.

Tolerances are derived from float64 conditioning, stated per check.
"""
import json
import sys

import numpy as np
import quantecon as qe

RNG = np.random.default_rng(20260619)

# float64 unit roundoff
EPS = np.finfo(np.float64).eps  # ~2.22e-16

results = []  # list of dicts: {check, oracle, measured, tol, verdict, note}


def record(check, oracle, measured, tol, verdict, note=""):
    results.append({
        "check": check, "oracle": oracle, "measured": float(measured),
        "tol": float(tol), "verdict": verdict, "note": note,
    })
    status = verdict
    print(f"[{status:>4}] {check}")
    print(f"        oracle={oracle}  measured={measured:.3e}  tol={tol:.3e}")
    if note:
        print(f"        note: {note}")


def random_stochastic(n):
    """Random row-stochastic n x n matrix (Dirichlet rows: exactly nonneg, rows sum 1)."""
    P = RNG.dirichlet(np.ones(n), size=n)
    return P


# ---------------------------------------------------------------------------
# 1. Markov: stationary distribution on the simplex, and simplex preservation.
# ---------------------------------------------------------------------------
def check_markov():
    print("\n=== 1. Markov chains (quantecon.MarkovChain) ===")

    # Concrete, irreducible chains plus random ones (incl. multi-recurrent-class).
    concrete = []
    # 3-state irreducible
    concrete.append(np.array([
        [0.7, 0.2, 0.1],
        [0.1, 0.6, 0.3],
        [0.2, 0.3, 0.5],
    ]))
    # 4-state irreducible
    concrete.append(np.array([
        [0.5, 0.2, 0.2, 0.1],
        [0.1, 0.5, 0.3, 0.1],
        [0.2, 0.1, 0.6, 0.1],
        [0.25, 0.25, 0.25, 0.25],
    ]))
    # 4-state with TWO recurrent classes => multiple stationary dists (tests the
    # "stationary distributions are *each* on the simplex" claim, not just one).
    concrete.append(np.array([
        [0.6, 0.4, 0.0, 0.0],
        [0.3, 0.7, 0.0, 0.0],
        [0.0, 0.0, 0.5, 0.5],
        [0.0, 0.0, 0.2, 0.8],
    ]))
    matrices = concrete + [random_stochastic(n) for n in (3, 3, 4, 5)]

    # Tolerance derivation:
    #  - nonnegativity: stationary entries are eigenvector components; tiny negative
    #    values (-eps scale) can appear from the eigen-solve. Allow STAT_NEG_TOL.
    #  - simplex sum / fixed point: pi@P == pi and sum(pi)==1 are linear identities;
    #    error accumulates as O(n) multiply-adds, each ~eps relative. Bound by a
    #    modest multiple of n*eps. With n<=5 and pi entries O(1), use 50*eps.
    STAT_NEG_TOL = 1e3 * EPS         # ~2.2e-13: how negative a "0" entry may be
    SUM_TOL = 50 * EPS               # ~1.1e-14
    FIXED_TOL = 1e3 * EPS            # ~2.2e-13: ||pi@P - pi||_inf

    max_neg = 0.0          # most-negative stationary entry (want >= -STAT_NEG_TOL)
    max_sum_err = 0.0      # |sum(pi) - 1|
    max_fixed_err = 0.0    # ||pi @ P - pi||_inf

    for P in matrices:
        mc = qe.MarkovChain(P)
        stat = mc.stationary_distributions  # shape (k, n), one row per recurrent class
        for pi in stat:
            max_neg = min(max_neg, pi.min())
            max_sum_err = max(max_sum_err, abs(pi.sum() - 1.0))
            max_fixed_err = max(max_fixed_err, np.max(np.abs(pi @ P - pi)))

    record("markov_stationary_nonneg",
           f"quantecon.MarkovChain.stationary_distributions ({len(matrices)} chains)",
           -max_neg, STAT_NEG_TOL,
           "PASS" if -max_neg <= STAT_NEG_TOL else "FAIL",
           note="most-negative stationary entry; invariant: entries >= 0")
    record("markov_stationary_sums_to_1",
           "quantecon.MarkovChain.stationary_distributions",
           max_sum_err, SUM_TOL,
           "PASS" if max_sum_err <= SUM_TOL else "FAIL",
           note="max |sum(pi) - 1|; invariant: total mass = 1")
    record("markov_fixed_point",
           "quantecon.MarkovChain.stationary_distributions",
           max_fixed_err, FIXED_TOL,
           "PASS" if max_fixed_err <= FIXED_TOL else "FAIL",
           note="max ||pi @ P - pi||_inf; invariant: stationary dist is a fixed point")

    # Simplex *preservation* directly: take many random simplex points, push through P,
    # confirm image is on the simplex (>=0, sum 1). This is the exact Track C claim
    # c_simplex_preserve / c_simplex_sum, on a real quantecon chain.
    PRES_NEG_TOL = 0.0     # Dirichlet point @ stochastic P is EXACTLY nonneg in exact
    # arithmetic; in float64, nonneg of a convex combo of nonnegs is exact (no
    # subtraction), so the only slack is the sum identity.
    PRES_SUM_TOL = 50 * EPS
    P = matrices[0]
    n = P.shape[0]
    worst_pres_neg = 0.0
    worst_pres_sum = 0.0
    for _ in range(20000):
        x = RNG.dirichlet(np.ones(n))
        q = x @ P
        worst_pres_neg = min(worst_pres_neg, q.min())
        worst_pres_sum = max(worst_pres_sum, abs(q.sum() - 1.0))
    record("markov_simplex_preservation",
           f"quantecon chain, 20000 random simplex points",
           max(-worst_pres_neg, 0.0), 10 * EPS,
           "PASS" if (-worst_pres_neg) <= 10 * EPS else "FAIL",
           note="min image entry (nonneg); convex combo of nonnegs stays >= 0")
    record("markov_simplex_preservation_sum",
           "quantecon chain, 20000 random simplex points",
           worst_pres_sum, PRES_SUM_TOL,
           "PASS" if worst_pres_sum <= PRES_SUM_TOL else "FAIL",
           note="max |sum(x@P) - 1|; total mass preserved")


# ---------------------------------------------------------------------------
# 2. Bellman operator: monotonicity, contraction modulus, convergence.
# ---------------------------------------------------------------------------
def check_bellman():
    print("\n=== 2. Bellman operator (finite MDP value iteration) ===")

    # Build a small finite MDP. We use a hand-rolled (deterministic-reward, stochastic
    # transition) operator T V = r + beta * P V with a row-stochastic P, matching the
    # exact Track C operator. We ALSO validate against quantecon.DiscreteDP's value
    # iteration for convergence.
    betas = [0.5, 0.8, 0.9, 0.95, 0.99]

    worst_mono_violation = 0.0   # how much TV exceeded TW where V<=W (want ~0)
    worst_contraction_ratio = -np.inf  # max measured ratio - beta (want <= 0)

    for beta in betas:
        for n in (3, 4, 6):
            P = random_stochastic(n)
            r = RNG.normal(size=n)

            def T(V):
                return r + beta * (P @ V)

            # (a) Monotonicity: random ordered pairs V <= W => TV <= TW.
            for _ in range(2000):
                V = RNG.normal(size=n)
                gap = RNG.exponential(scale=1.0, size=n)  # >= 0
                W = V + gap                                # W >= V pointwise
                diff = T(V) - T(W)                         # want <= 0
                worst_mono_violation = max(worst_mono_violation, float(diff.max()))

            # (b) Contraction modulus: ||T A - T B||_inf / ||A - B||_inf <= beta.
            for _ in range(2000):
                A = RNG.normal(size=n)
                B = RNG.normal(size=n)
                denom = np.max(np.abs(A - B))
                if denom < 1e-9:
                    continue
                ratio = np.max(np.abs(T(A) - T(B))) / denom
                worst_contraction_ratio = max(worst_contraction_ratio,
                                              float(ratio - beta))

    # Tolerance derivation:
    #  - monotonicity: TV-TW = beta*P*(V-W) <= 0 exactly when V<=W (P,beta>=0). In
    #    float64 the only error is rounding of the matvec, ~ n*eps*scale. Scale O(10),
    #    n<=6 => bound ~ 1e-12. Use MONO_TOL.
    #  - contraction: the ratio can equal beta exactly (e.g. constant difference vector
    #    is an eigenvector of the stochastic averaging with eigenvalue 1), so
    #    ratio - beta should be <= rounding. Use CONTR_TOL.
    MONO_TOL = 1e-12
    CONTR_TOL = 1e-12
    record("bellman_monotonicity",
           "hand-rolled finite MDP (row-stochastic P), 2000 ordered pairs x betas",
           worst_mono_violation, MONO_TOL,
           "PASS" if worst_mono_violation <= MONO_TOL else "FAIL",
           note="max (TV-TW) over V<=W; invariant: TV<=TW")
    record("bellman_contraction_modulus",
           "hand-rolled finite MDP, 2000 random pairs x betas",
           max(worst_contraction_ratio, 0.0), CONTR_TOL,
           "PASS" if worst_contraction_ratio <= CONTR_TOL else "FAIL",
           note="max (ratio - beta); invariant: contraction ratio <= beta")

    # (c) Convergence of value iteration + per-iteration contraction ratio trace,
    #     cross-checked against quantecon.DiscreteDP.
    #
    # IMPORTANT measurement note (recorded in RESULTS as a methodology finding):
    # The naive "successive-difference ratio" ||V_{k+1}-V_k||/||V_k-V_{k-1}|| is NOT a
    # faithful estimate of the contraction modulus near convergence: V_{k+1}-V_k is a
    # difference of two nearly-equal vectors, so once ||V_k-V_{k-1}|| approaches the
    # float64 cancellation floor (~eps*||V||) the ratio is dominated by rounding noise
    # and can read slightly above beta. The THEOREM being checked is
    # ||T A - T B||_inf <= beta ||A-B||_inf, which equals ||beta P y||/||y|| for
    # y = V_k - V_{k-1}; we measure THAT directly from the iterate differences and only
    # while ||y|| is safely above the cancellation floor. (The unguarded ratio is also
    # reported below for transparency.)
    print("\n--- value iteration convergence (per-beta contraction trace) ---")
    worst_iter_ratio_excess = -np.inf       # guarded: ||beta P y|| / ||y||
    worst_naive_ratio_excess = -np.inf      # unguarded successive-diff (artifact trace)
    worst_vi_residual_norm = 0.0            # ||V_VI - V*|| normalized by the bound
    for beta in betas:
        n = 5
        P = random_stochastic(n)
        r = RNG.normal(size=n)

        def T(V):
            return r + beta * (P @ V)

        # fixed point closed form: V* = (I - beta P)^-1 r
        Vstar = np.linalg.solve(np.eye(n) - beta * P, r)

        V = np.zeros(n)
        prev_y = None
        delta_stop = 1e-12
        cancel_floor = None
        guarded_ratios = []
        naive_ratios = []
        for k in range(100000):
            Vn = T(V)
            y = Vn - V                      # = beta P (V - V_prev) = T V - T V_prev
            delta = np.max(np.abs(y))
            cancel_floor = 64 * EPS * max(np.max(np.abs(Vn)), 1.0)
            if prev_y is not None:
                den = np.max(np.abs(prev_y))
                if den > cancel_floor:
                    # guarded, faithful contraction estimate: ||beta P prev_y||/||prev_y||
                    guarded_ratios.append(
                        np.max(np.abs(beta * (P @ prev_y))) / den)
                    # naive successive-difference ratio (the artifact)
                    naive_ratios.append(delta / den)
            prev_y = y
            V = Vn
            if delta < delta_stop:
                break

        residual = np.max(np.abs(V - Vstar))
        # Stopping-rule bound: ||V_K - V*||_inf <= delta_stop * beta/(1-beta).
        vi_bound = delta_stop * beta / (1.0 - beta)
        worst_vi_residual_norm = max(worst_vi_residual_norm,
                                     float(residual / vi_bound))
        g_ratio = max(guarded_ratios) if guarded_ratios else 0.0
        n_ratio = max(naive_ratios) if naive_ratios else 0.0
        worst_iter_ratio_excess = max(worst_iter_ratio_excess, float(g_ratio - beta))
        worst_naive_ratio_excess = max(worst_naive_ratio_excess, float(n_ratio - beta))
        print(f"  beta={beta:.2f}  guarded ||bP y||/||y|| max={g_ratio:.6f} "
              f"(<= beta? {'yes' if g_ratio <= beta + 1e-9 else 'NO'})  "
              f"| naive succ-diff max={n_ratio:.6f}  "
              f"| VI residual={residual:.3e} (bound {vi_bound:.3e})")

    record("bellman_vi_iter_contraction",
           "value-iteration iterate-difference contraction ||bP y||/||y|| (5-state)",
           max(worst_iter_ratio_excess, 0.0), 1e-9,
           "PASS" if worst_iter_ratio_excess <= 1e-9 else "FAIL",
           note="max over iters/betas of (ratio - beta) for the faithful estimate; "
                "each VI step contracts by <= beta. (Naive succ-diff ratio excess = "
                f"{worst_naive_ratio_excess:.3e}, a float64 cancellation artifact, not "
                "an invariant violation -- see RESULTS methodology note.)")
    record("bellman_vi_convergence",
           "value iteration vs closed-form (I-beta P)^-1 r, normalized by stop-rule bound",
           worst_vi_residual_norm, 1.0,
           "PASS" if worst_vi_residual_norm <= 1.0 else "FAIL",
           note="||V_VI - V*||_inf / (delta_stop*beta/(1-beta)); VI converges to the "
                "Bellman fixed point within its a-priori stopping-rule bound")

    # Cross-check with quantecon.DiscreteDP: build a 1-action-per-state DP whose
    # value iteration must converge; confirm QE's VI matches the closed form too.
    print("\n--- quantecon.DiscreteDP cross-check ---")
    n = 4
    beta = 0.9
    P = random_stochastic(n)
    r = RNG.normal(size=n)
    # DiscreteDP with a single action: R shape (n_states, n_actions), Q shape (s,a,s')
    R = r.reshape(n, 1)
    Q = P.reshape(n, 1, n)
    ddp = qe.markov.DiscreteDP(R, Q, beta)
    res = ddp.solve(method="value_iteration", v_init=np.zeros(n), epsilon=1e-12,
                    max_iter=100000)
    Vstar = np.linalg.solve(np.eye(n) - beta * P, r)
    qe_residual = float(np.max(np.abs(res.v - Vstar)))
    # QE's VI stops at a Bellman-error epsilon; the value error is bounded by
    # eps*beta/(1-beta). Use that as the tolerance.
    ddp_tol = 1e-12 * beta / (1 - beta) + 1e-9
    record("bellman_quantecon_discretedp",
           "quantecon.markov.DiscreteDP value_iteration vs closed form",
           qe_residual, ddp_tol,
           "PASS" if qe_residual <= ddp_tol else "FAIL",
           note="||DiscreteDP.v - V*||_inf; QE's own VI lands at the fixed point")


# ---------------------------------------------------------------------------
# 3. Gordon growth: positivity and monotonicity over a parameter sweep, r>g.
# ---------------------------------------------------------------------------
def check_gordon():
    print("\n=== 3. Gordon growth (p = d/(r-g), r>g) ===")
    ds = np.linspace(0.1, 100.0, 60)
    rs = np.linspace(0.02, 0.20, 40)
    gaps = np.linspace(0.001, 0.10, 40)  # r - g > 0

    min_price = np.inf
    worst_mono_viol = 0.0   # if d1<=d2 but p1>p2 (want 0)
    n_checked = 0
    for r in rs:
        for gap in gaps:
            g = r - gap  # ensures r > g
            prices = ds / (r - g)
            min_price = min(min_price, float(prices.min()))
            # monotone increasing in d (r,g fixed): diffs >= 0
            dp = np.diff(prices)
            worst_mono_viol = max(worst_mono_viol, float(max(-dp.min(), 0.0)))
            n_checked += len(ds)

    # Tolerance: prices are exact positive quotients of positives; positivity is exact.
    # Monotonicity diff is (d2-d1)/(r-g) > 0 exactly; rounding only. Use tiny bound.
    record("gordon_positivity",
           f"parameter sweep r in [.02,.20], r-g in [.001,.10], d in [.1,100] "
           f"({n_checked} points)",
           max(-min_price, 0.0), 0.0,
           "PASS" if min_price > 0.0 else "FAIL",
           note=f"min price over sweep = {min_price:.4e}; invariant: p>0 for d>0,r>g")
    record("gordon_monotonicity",
           "Gordon price vs dividend, r,g fixed, over the sweep",
           worst_mono_viol, 1e-12,
           "PASS" if worst_mono_viol <= 1e-12 else "FAIL",
           note="max monotonicity violation (p decreasing in d); invariant: p nondecreasing in d")

    # PV of a finite nonneg dividend stream: nonneg + monotone (Track C c_pv_*).
    print("\n--- present value of finite nonneg dividend streams ---")
    min_pv = np.inf
    worst_pv_mono = 0.0
    for _ in range(20000):
        beta = RNG.uniform(0.0, 1.0)
        d = RNG.exponential(scale=1.0, size=8)  # nonneg dividends
        powers = beta ** np.arange(8)
        pv = float(d @ powers)
        min_pv = min(min_pv, pv)
        e = d + RNG.exponential(scale=1.0, size=8)  # e >= d
        pv_e = float(e @ powers)
        worst_pv_mono = max(worst_pv_mono, float(max(pv - pv_e, 0.0)))
    record("pv_positivity",
           "20000 random (beta in [0,1], 8 nonneg dividends)",
           max(-min_pv, 0.0), 0.0,
           "PASS" if min_pv >= 0.0 else "FAIL",
           note=f"min PV = {min_pv:.4e}; invariant: PV of nonneg stream >= 0")
    record("pv_monotonicity",
           "20000 random streams with e >= d",
           worst_pv_mono, 1e-9,
           "PASS" if worst_pv_mono <= 1e-9 else "FAIL",
           note="max (PV(d)-PV(e)) for e>=d; invariant: PV monotone in dividends")


def main():
    print("QuantEcon empirical oracle for Track C SMT-proven invariants")
    print(f"numpy float64 eps = {EPS:.3e}")
    check_markov()
    check_bellman()
    check_gordon()

    print("\n" + "=" * 70)
    print("SUMMARY")
    n_pass = sum(1 for r in results if r["verdict"] == "PASS")
    n_fail = sum(1 for r in results if r["verdict"] == "FAIL")
    for r in results:
        print(f"  [{r['verdict']:>4}] {r['check']:<32} "
              f"measured={r['measured']:.3e} tol={r['tol']:.3e}")
    print(f"\n{n_pass} PASS, {n_fail} FAIL")
    # machine-readable
    print(json.dumps({"task": "econ_oracle", "n_pass": n_pass, "n_fail": n_fail,
                      "results": results}))
    sys.exit(0 if n_fail == 0 else 2)


if __name__ == "__main__":
    main()
