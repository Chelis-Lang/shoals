module Shoals.TestsNeg.HestonTerminalZeroStepCount
import Std.Test (assert_true)
import Shoals.Stochastic (heston_qe_terminal)
-- Negative: a zero step count is not a discretisation. The step range is
-- empty, so the evolution fold returns its initial state and this sampler
-- returned `exp(log(s0))` -- s0 to within the round trip -- for a one-year
-- horizon it never simulated. checked_step_count refuses at the entry.
--
-- The horizon guard cannot reach this and should not: `t = 1.0` is a
-- perfectly legal horizon. A finiteness check on the derived `dt` is not a
-- substitute either, though for a narrower reason than it looks: adding one
-- CREATES a consumer for `dt`, so it does catch `n_steps = 0`, where `dt` is
-- `+inf`. It misses a negative count, where `t / -8` is finite.
--
-- This file pins the ZERO case on its own, separately from the negative one,
-- because the two refusals rest on different warrants. A negative step count
-- is not a quantity. A zero step count carries an identity argument -- "no
-- steps, so no evolution, so s0" -- which is rejected on the ground that
-- `n_steps` is a resolution parameter rather than a modelled quantity, and
-- that `s0` is the terminal spot of a Heston process over a positive horizon
-- only on an event of probability zero. Keeping the cases in separate files
-- means that decision can be revisited without disturbing the negative one.
--
-- The assertion below is one that s0 ALSO fails, so deleting the guard does
-- not make this file pass by accident: it would then fail on the assertion
-- rather than on the refusal, and `--expect neg` checks the diagnostic text
-- rather than merely that something failed.
def test_neg_heston_terminal_zero_step_count() -> unit ! { Test } = {
  out = heston_qe_terminal(key_from_seed(7i64), cast(100.0, f32), cast(0.04, f32), cast(0.05, f32), cast(1.5, f32), cast(0.04, f32), cast(0.3, f32), cast(-0.5, f32), cast(1.0, f32), cast(0, i64))
  assert_true(gt(out.0, cast(1e30, f32)), "should not reach here: unguarded this returned 100.00001, the initial spot, for a one-year horizon")
}
