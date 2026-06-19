module Research.Derivatives.Capacity

-- Probes to characterize the smt-unsupported (solver capacity) bucket and the
-- reliability boundary between clean-polynomial goals and residual-transcendental
-- goals. A cvc5 unknown/timeout is NOT a refutation.

-- CAP-EXP: a TRUE fact (convexity of exp) whose goal carries a residual
-- transcendental exp. Forces cvc5 into the transcendental extension (QF_NRAT),
-- which is heuristic. Outcome characterizes reliability, not structure.
@property cap_exp_above_tangent forall(x: f32)
  where x >= 0.0, x <= 1.0:
  exp(x) >= (1.0 + x)

-- CAP-SQRT: a TRUE fact with residual sqrt. sqrt is in the lowerable set; tests
-- whether even a "supported" transcendental stays reliable.
@property cap_sqrt_monotone forall(x: f32, y: f32)
  where x >= 0.0, y >= 0.0, x <= y:
  sqrt(x) <= sqrt(y)

-- CAP-POLY: the SAME clean polynomial upper bound as a_upper_bound. Run this file
-- BOTH with --smt-timeout 20000 (expect passed) and with --smt-timeout 1 (expect
-- the solver to be unable to decide => unsupported, NOT failed). Demonstrates that
-- a timeout is a capacity verdict, not a refutation: the label must change with the
-- budget while the truth does not.
@property cap_poly_upper_bound forall(s: f32, k: f32, nd1: f32, nd2: f32, disc: f32)
  where s >= 0.0, k >= 0.0, nd1 >= 0.0, nd1 <= 1.0, nd2 >= 0.0, nd2 <= 1.0, disc >= 0.0, disc <= 1.0:
  ((s * nd1) - (k * (disc * nd2))) <= s
