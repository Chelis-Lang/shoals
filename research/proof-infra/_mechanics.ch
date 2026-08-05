module Research.Mechanics
-- (1) Consistency witness pattern (A5): invariants are jointly SATISFIABLE iff
-- `where <invariants>: false` is REFUTED (a model exists). Expect: failed.
@property consistency_satisfiable forall(s: f32, k: f32, nd1: f32, nd2: f32, disc: f32) where s >= 0.0, k >= 0.0, nd1 >= 0.0, nd1 <= 1.0, nd2 >= 0.0, nd2 <= 1.0, disc >= 0.0, disc <= 1.0:
  false
-- (2) Contradictory invariant set: `where <contradiction>: false` should VACUOUSLY
-- pass (no model). Expect: passed. This is what the consistency check must catch.
@property consistency_contradictory forall(nd1: f32) where nd1 >= 0.5, nd1 <= 0.3:
  false
-- (3) Put-call parity WITH reflection invariant nd1c = 1-nd1, nd2c = 1-nd2.
-- C - P = s*nd1 - k*disc*nd2 - (k*disc*nd2c - s*nd1c)
--       = s*(nd1+nd1c) - k*disc*(nd2+nd2c) = s - k*disc  (given reflection).
-- Expect: passed (smt).
@property parity_with_reflection forall(s: f32, k: f32, nd1: f32, nd2: f32, nd1c: f32, nd2c: f32, disc: f32) where s >= 0.0, k >= 0.0, disc >= 0.0, disc <= 1.0, nd1 >= 0.0, nd1 <= 1.0, nd2 >= 0.0, nd2 <= 1.0, nd1c == (1.0 - nd1), nd2c == (1.0 - nd2):
  ((((s * nd1) - (k * (disc * nd2))) - ((k * (disc * nd2c)) - (s * nd1c))) == (s - (k * disc)))
-- (4) Put-call parity WITHOUT reflection (nd1c,nd2c free in [0,1]): should be REFUTED.
@property parity_naive forall(s: f32, k: f32, nd1: f32, nd2: f32, nd1c: f32, nd2c: f32, disc: f32) where s >= 0.0, k >= 0.0, disc >= 0.0, disc <= 1.0, nd1 >= 0.0, nd1 <= 1.0, nd2 >= 0.0, nd2 <= 1.0, nd1c >= 0.0, nd1c <= 1.0, nd2c >= 0.0, nd2c <= 1.0:
  ((((s * nd1) - (k * (disc * nd2))) - ((k * (disc * nd2c)) - (s * nd1c))) == (s - (k * disc)))
-- (5) Naive non-negativity C >= 0 with nd1,nd2 independent: should be REFUTED
-- (counterexample nd1=0, nd2=1). Confirms the negative-space result.
@property nonneg_naive forall(s: f32, k: f32, nd1: f32, nd2: f32, disc: f32) where s >= 0.0, k >= 0.0, nd1 >= 0.0, nd1 <= 1.0, nd2 >= 0.0, nd2 <= 1.0, disc >= 0.0, disc <= 1.0:
  (((s * nd1) - (k * (disc * nd2))) >= 0.0)
