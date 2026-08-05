module Research.Economic.Reachability
-- Track C: economic / dynamic-programming structural properties. These are
-- polynomial/linear in their parameters with NO transcendental to abstract, so an
-- economic green is structurally more complete than a derivatives green: there is no
-- asserted contract on a transcendental, only exact algebraic invariants
-- (row-stochasticity, discount in [0,1]).
-- Run: chelis prove economic/reachability.ch --tier smt-only --json --smt-timeout 20000
-- ===========================================================================
-- Markov chains: a row-stochastic matrix maps the probability simplex to itself.
-- The stationary distribution is a fixed point of this map, so simplex-preservation
-- is the core structural invariant.
-- ===========================================================================
-- C-SIMPLEX-2: 2-state. P rows (p00,p01),(p10,p11) stochastic; pi=(x0,x1) on simplex.
-- q = pi*P. Prove q nonneg and sums to 1. Parametric over all valid P, pi.
@property c_simplex_preserve_2 forall(p00: f32, p01: f32, p10: f32, p11: f32, x0: f32, x1: f32) where p00 >= 0.0, p01 >= 0.0, p10 >= 0.0, p11 >= 0.0, (p00 + p01) == 1.0, (p10 + p11) == 1.0, x0 >= 0.0, x1 >= 0.0, (x0 + x1) == 1.0:
  (((((x0 * p00) + (x1 * p10)) >= 0.0) && (((x0 * p01) + (x1 * p11)) >= 0.0)) && ((((x0 * p00) + (x1 * p10)) + ((x0 * p01) + (x1 * p11))) == 1.0))
-- C-SIMPLEX-3: 3-state, the sum-preservation half (the structural identity). Shows it
-- scales past 2 states. q_j = sum_i x_i p_ij; sum_j q_j = sum_i x_i (sum_j p_ij) = 1.
@property c_simplex_sum_3 forall(p00: f32, p01: f32, p02: f32, p10: f32, p11: f32, p12: f32, p20: f32, p21: f32, p22: f32, x0: f32, x1: f32, x2: f32) where p00 >= 0.0, p01 >= 0.0, p02 >= 0.0, (p00 + (p01 + p02)) == 1.0, p10 >= 0.0, p11 >= 0.0, p12 >= 0.0, (p10 + (p11 + p12)) == 1.0, p20 >= 0.0, p21 >= 0.0, p22 >= 0.0, (p20 + (p21 + p22)) == 1.0, x0 >= 0.0, x1 >= 0.0, x2 >= 0.0, (x0 + (x1 + x2)) == 1.0:
  ((((x0 * p00) + ((x1 * p10) + (x2 * p20))) + (((x0 * p01) + ((x1 * p11) + (x2 * p21))) + ((x0 * p02) + ((x1 * p12) + (x2 * p22))))) == 1.0)
-- C-SIMPLEX-EDGE (C4): drop the row-sum constraints. The sum-preservation property
-- must be REFUTED, proving the green depends on row-stochasticity.
@property c_simplex_no_rowsum_edge forall(p00: f32, p01: f32, p10: f32, p11: f32, x0: f32, x1: f32) where p00 >= 0.0, p01 >= 0.0, p10 >= 0.0, p11 >= 0.0, x0 >= 0.0, x1 >= 0.0, (x0 + x1) == 1.0:
  ((((x0 * p00) + (x1 * p10)) + ((x0 * p01) + (x1 * p11))) == 1.0)
-- ===========================================================================
-- Value-function iteration: the Bellman operator (TV)(s) = r(s) + beta * sum P(s,s')V(s')
-- ===========================================================================
-- C-BELLMAN-MONO: monotonicity. V <= W pointwise => TV <= TW pointwise (state 0 shown;
-- r0 cancels). Needs beta>=0 and row-stochastic P.
@property c_bellman_monotone forall(beta: f32, p0: f32, p1: f32, v0: f32, v1: f32, w0: f32, w1: f32) where beta >= 0.0, beta <= 1.0, p0 >= 0.0, p1 >= 0.0, (p0 + p1) == 1.0, v0 <= w0, v1 <= w1:
  ((beta * ((p0 * v0) + (p1 * v1))) <= (beta * ((p0 * w0) + (p1 * w1))))
-- C-BELLMAN-BOUNDED: if r in [rlo,rhi] and V in [vlo,vhi], then TV in
-- [rlo + beta*vlo, rhi + beta*vhi].
@property c_bellman_bounded forall(beta: f32, p0: f32, p1: f32, r: f32, v0: f32, v1: f32, rlo: f32, rhi: f32, vlo: f32, vhi: f32) where beta >= 0.0, beta <= 1.0, p0 >= 0.0, p1 >= 0.0, (p0 + p1) == 1.0, r >= rlo, r <= rhi, v0 >= vlo, v0 <= vhi, v1 >= vlo, v1 <= vhi:
  (((r + (beta * ((p0 * v0) + (p1 * v1)))) >= (rlo + (beta * vlo))) && ((r + (beta * ((p0 * v0) + (p1 * v1)))) <= (rhi + (beta * vhi))))
-- C-BELLMAN-CONTRACTION: ||TV - TW||_inf <= beta * ||V - W||_inf. With per-state bound
-- -d <= v_i - w_i <= d, prove -beta*d <= (TV0 - TW0) <= beta*d (abs-free formulation).
@property c_bellman_contraction forall(beta: f32, p0: f32, p1: f32, v0: f32, v1: f32, w0: f32, w1: f32, d: f32) where beta >= 0.0, beta <= 1.0, p0 >= 0.0, p1 >= 0.0, (p0 + p1) == 1.0, d >= 0.0, (v0 - w0) <= d, (w0 - v0) <= d, (v1 - w1) <= d, (w1 - v1) <= d:
  (((beta * ((p0 * (v0 - w0)) + (p1 * (v1 - w1)))) <= (beta * d)) && ((beta * ((p0 * (v0 - w0)) + (p1 * (v1 - w1)))) >= (0.0 - (beta * d))))
-- ===========================================================================
-- Simple asset pricing
-- ===========================================================================
-- C-PV-POS: present value of a finite nonneg dividend stream is nonneg.
@property c_pv_positive forall(beta: f32, d0: f32, d1: f32, d2: f32) where beta >= 0.0, beta <= 1.0, d0 >= 0.0, d1 >= 0.0, d2 >= 0.0:
  (((d0 + (beta * d1)) + ((beta * beta) * d2)) >= 0.0)
-- C-PV-MONO: PV is monotone in dividends.
@property c_pv_monotone forall(beta: f32, d0: f32, d1: f32, d2: f32, e0: f32, e1: f32, e2: f32) where beta >= 0.0, beta <= 1.0, d0 <= e0, d1 <= e1, d2 <= e2, d0 >= 0.0, d1 >= 0.0, d2 >= 0.0:
  (((d0 + (beta * d1)) + ((beta * beta) * d2)) <= ((e0 + (beta * e1)) + ((beta * beta) * e2)))
-- C-GORDON-POS: Gordon growth price positivity. p = d/(r-g), d>0, r>g => p>0.
@property c_gordon_positive forall(d: f32, r: f32, g: f32, p: f32) where d > 0.0, r > g, p == (d / (r - g)):
  (p > 0.0)
-- C-GORDON-MONO: price monotone increasing in dividend (r,g fixed, r>g).
@property c_gordon_monotone forall(d1: f32, d2: f32, r: f32, g: f32, p1: f32, p2: f32) where r > g, d1 >= 0.0, d1 <= d2, p1 == (d1 / (r - g)), p2 == (d2 / (r - g)):
  (p1 <= p2)
-- ===========================================================================
-- A5 consistency witnesses (expect failed = invariant set satisfiable)
-- ===========================================================================
@property c_sat_simplex forall(p00: f32, p01: f32, p10: f32, p11: f32, x0: f32, x1: f32) where p00 >= 0.0, p01 >= 0.0, p10 >= 0.0, p11 >= 0.0, (p00 + p01) == 1.0, (p10 + p11) == 1.0, x0 >= 0.0, x1 >= 0.0, (x0 + x1) == 1.0:
  false
@property c_sat_bellman forall(beta: f32, p0: f32, p1: f32, v0: f32, v1: f32, w0: f32, w1: f32) where beta >= 0.0, beta <= 1.0, p0 >= 0.0, p1 >= 0.0, (p0 + p1) == 1.0, v0 <= w0, v1 <= w1:
  false
-- ===========================================================================
-- A4 soundness-dependence: an UNSOUND row sum (1.5) must flip simplex-sum to failed.
-- ===========================================================================
@property c_simplex_unsound_rowsum forall(p00: f32, p01: f32, p10: f32, p11: f32, x0: f32, x1: f32) where p00 >= 0.0, p01 >= 0.0, p10 >= 0.0, p11 >= 0.0, (p00 + p01) == 1.5, (p10 + p11) == 1.5, x0 >= 0.0, x1 >= 0.0, (x0 + x1) == 1.0:
  ((((x0 * p00) + (x1 * p10)) + ((x0 * p01) + (x1 * p11))) == 1.0)
