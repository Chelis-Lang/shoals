module Research.Derivatives.Reachability
-- Track A: SMT-reachability map for Black-Scholes structural properties under
-- opaque-invariant abstraction. Each transcendental OUTPUT is abstracted as a
-- bounded free parameter carrying its true contract:
--   nd1 = N(d1), nd2 = N(d2)     in [0,1]   (CDF range)
--   nd1c = N(-d1), nd2c = N(-d2) in [0,1]   (CDF range)
--   disc = exp(-r t)             in (0,1]   (discount factor)
--   s (spot) >= 0, k (strike) >= 0
-- Abstracted bodies (exactly the Shoals.Pricing structure, transcendentals lifted):
--   C = s*nd1 - k*disc*nd2
--   P = k*disc*nd2c - s*nd1c
-- Reflection invariant of the normal CDF: N(-x) = 1 - N(x), i.e. nd1c = 1-nd1.
-- Run: chelis prove <file> --tier smt-only --json --smt-timeout 20000
-- ===========================================================================
-- PROVEN candidates
-- ===========================================================================
-- A-UB: upper bound C <= S. From ranges alone (k,disc,nd2 >= 0 ; nd1 <= 1).
-- Polynomial goal (products s*nd1, k*disc*nd2). Transcendental-free.
@property a_upper_bound forall(s: f32, k: f32, nd1: f32, nd2: f32, disc: f32) where s >= 0.0, k >= 0.0, nd1 >= 0.0, nd1 <= 1.0, nd2 >= 0.0, nd2 <= 1.0, disc >= 0.0, disc <= 1.0:
  (((s * nd1) - (k * (disc * nd2))) <= s)
-- A-PAR: put-call parity C - P = S - K*disc, WITH the reflection invariant.
@property a_parity_reflection forall(s: f32, k: f32, nd1: f32, nd2: f32, nd1c: f32, nd2c: f32, disc: f32) where s >= 0.0, k >= 0.0, disc >= 0.0, disc <= 1.0, nd1 >= 0.0, nd1 <= 1.0, nd2 >= 0.0, nd2 <= 1.0, nd1c == (1.0 - nd1), nd2c == (1.0 - nd2):
  ((((s * nd1) - (k * (disc * nd2))) - ((k * (disc * nd2c)) - (s * nd1c))) == (s - (k * disc)))
-- A-DELTA: delta = N(d1) is in [0,1] (non-negative => monotone increasing in spot;
-- bounded by 1). The structural sign/bound of the Greek. Links Track B (B5).
@property a_delta_bounds forall(nd1: f32) where nd1 >= 0.0, nd1 <= 1.0:
  ((nd1 >= 0.0) && (nd1 <= 1.0))
-- ===========================================================================
-- REFUTED / negative-space candidates (naive abstraction is too coarse)
-- ===========================================================================
-- A-PAR-NAIVE: parity WITHOUT reflection (nd1c,nd2c independent in [0,1]). Refuted:
-- shows parity is not a free algebraic identity; it needs N(-x)=1-N(x).
@property a_parity_naive forall(s: f32, k: f32, nd1: f32, nd2: f32, nd1c: f32, nd2c: f32, disc: f32) where s >= 0.0, k >= 0.0, disc >= 0.0, disc <= 1.0, nd1 >= 0.0, nd1 <= 1.0, nd2 >= 0.0, nd2 <= 1.0, nd1c >= 0.0, nd1c <= 1.0, nd2c >= 0.0, nd2c <= 1.0:
  ((((s * nd1) - (k * (disc * nd2))) - ((k * (disc * nd2c)) - (s * nd1c))) == (s - (k * disc)))
-- A-NN-NAIVE: non-negativity C >= 0 with nd1,nd2 independent. Refuted
-- (counterexample family: nd1=0, nd2=1, s,k,disc>0).
@property a_nonneg_naive forall(s: f32, k: f32, nd1: f32, nd2: f32, disc: f32) where s >= 0.0, k >= 0.0, nd1 >= 0.0, nd1 <= 1.0, nd2 >= 0.0, nd2 <= 1.0, disc >= 0.0, disc <= 1.0:
  (((s * nd1) - (k * (disc * nd2))) >= 0.0)
-- A-NN-MONO: non-negativity WITH the sound monotonicity coupling nd1 >= nd2
-- (true because d1 = d2 + sigma*sqrt(t) >= d2 and N is increasing). Still refuted:
-- monotone coupling alone does not rescue non-negativity (e.g. s small, k*disc large,
-- nd1=nd2=1 gives C = s - k*disc < 0). Demonstrates the needed coupling is the
-- abstracted-away moneyness structure, not a local invariant on N.
@property a_nonneg_monotone forall(s: f32, k: f32, nd1: f32, nd2: f32, disc: f32) where s >= 0.0, k >= 0.0, nd1 >= 0.0, nd1 <= 1.0, nd2 >= 0.0, nd2 <= 1.0, disc >= 0.0, disc <= 1.0, nd1 >= nd2:
  (((s * nd1) - (k * (disc * nd2))) >= 0.0)
-- A-INTR-NAIVE: intrinsic lower bound C >= S - K*disc. Refuted under value
-- abstraction (needs the same moneyness coupling).
@property a_intrinsic_naive forall(s: f32, k: f32, nd1: f32, nd2: f32, disc: f32) where s >= 0.0, k >= 0.0, nd1 >= 0.0, nd1 <= 1.0, nd2 >= 0.0, nd2 <= 1.0, disc >= 0.0, disc <= 1.0:
  (((s * nd1) - (k * (disc * nd2))) >= (s - (k * disc)))
-- ===========================================================================
-- SECOND-ORDER: strike convexity (no-arbitrage butterfly >= 0)
-- Three equally spaced strikes k1<k2<k3, k2=(k1+k3)/2, common spot/disc.
-- C_i = s*nd1_i - k_i*disc*nd2_i. Butterfly = C1 - 2*C2 + C3 >= 0.
-- Tests whether a second-order sign property is expressible/provable under
-- abstraction. Without a density-convexity coupling among the nd2_i it is refuted;
-- higher variable count + degree may instead exhaust the solver (capacity).
-- ===========================================================================
@property a_strike_convex_naive forall(s: f32, disc: f32, k1: f32, k3: f32, nd1a: f32, nd1b: f32, nd1c2: f32, nd2a: f32, nd2b: f32, nd2c2: f32) where s >= 0.0, disc >= 0.0, disc <= 1.0, k1 >= 0.0, k3 >= k1, nd1a >= 0.0, nd1a <= 1.0, nd1b >= 0.0, nd1b <= 1.0, nd1c2 >= 0.0, nd1c2 <= 1.0, nd2a >= 0.0, nd2a <= 1.0, nd2b >= 0.0, nd2b <= 1.0, nd2c2 >= 0.0, nd2c2 <= 1.0:
  (((((s * nd1a) - (k1 * (disc * nd2a))) - (2.0 * ((s * nd1b) - (((k1 + k3) * 0.5) * (disc * nd2b))))) + ((s * nd1c2) - (k3 * (disc * nd2c2)))) >= 0.0)
-- ===========================================================================
-- A5 CONSISTENCY WITNESSES: invariant set is jointly SATISFIABLE iff
-- `where <invariants>: false` is REFUTED (a model exists). Expect: failed.
-- (A contradictory premise set would instead vacuously pass.)
-- ===========================================================================
@property a_sat_upper_bound forall(s: f32, k: f32, nd1: f32, nd2: f32, disc: f32) where s >= 0.0, k >= 0.0, nd1 >= 0.0, nd1 <= 1.0, nd2 >= 0.0, nd2 <= 1.0, disc >= 0.0, disc <= 1.0:
  false
@property a_sat_parity forall(s: f32, k: f32, nd1: f32, nd2: f32, nd1c: f32, nd2c: f32, disc: f32) where s >= 0.0, k >= 0.0, disc >= 0.0, disc <= 1.0, nd1 >= 0.0, nd1 <= 1.0, nd2 >= 0.0, nd2 <= 1.0, nd1c == (1.0 - nd1), nd2c == (1.0 - nd2):
  false
@property a_sat_delta forall(nd1: f32) where nd1 >= 0.0, nd1 <= 1.0:
  false
-- ===========================================================================
-- A4 SOUNDNESS-DEPENDENCE: replacing a sound invariant with an UNSOUND variant
-- must FLIP a proven green to refuted.
-- ===========================================================================
-- Upper bound but with the UNSOUND range nd1 <= 2.0 (false for a CDF). Expect: failed.
@property a_upper_bound_unsound forall(s: f32, k: f32, nd1: f32, nd2: f32, disc: f32) where s >= 0.0, k >= 0.0, nd1 >= 0.0, nd1 <= 2.0, nd2 >= 0.0, nd2 <= 1.0, disc >= 0.0, disc <= 1.0:
  (((s * nd1) - (k * (disc * nd2))) <= s)
-- Parity but with the UNSOUND reflection nd1c = 1 - 2*nd1. Expect: failed.
@property a_parity_unsound_reflection forall(s: f32, k: f32, nd1: f32, nd2: f32, nd1c: f32, nd2c: f32, disc: f32) where s >= 0.0, k >= 0.0, disc >= 0.0, disc <= 1.0, nd1 >= 0.0, nd1 <= 1.0, nd2 >= 0.0, nd2 <= 1.0, nd1c == (1.0 - (2.0 * nd1)), nd2c == (1.0 - nd2):
  ((((s * nd1) - (k * (disc * nd2))) - ((k * (disc * nd2c)) - (s * nd1c))) == (s - (k * disc)))
