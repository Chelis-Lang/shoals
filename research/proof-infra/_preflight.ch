module Research.Preflight
-- PF1: a trivial true linear property should discharge at the SMT tier.
@property pf1_commutes forall(x: f32, y: f32) where x >= 0.0, x <= 1.0, y >= 0.0, y <= 1.0:
  ((x + y) == (y + x))
-- PF2: a false property should be refuted with a concrete counterexample.
@property pf2_all_nonneg forall(x: f32):
  (x >= 0.0)
-- Track A headline canary: abstracted Black-Scholes call upper bound C <= S.
-- C = s*N(d1) - k*disc*N(d2), with the transcendental outputs abstracted as
-- bounded free parameters carrying their true ranges. Goal is polynomial in the
-- bounded symbols; should be smt-proven from ranges alone.
@property a_call_upper_bound forall(s: f32, k: f32, nd1: f32, nd2: f32, disc: f32) where s >= 0.0, k >= 0.0, nd1 >= 0.0, nd1 <= 1.0, nd2 >= 0.0, nd2 <= 1.0, disc >= 0.0, disc <= 1.0:
  (((s * nd1) - (k * (disc * nd2))) <= s)
