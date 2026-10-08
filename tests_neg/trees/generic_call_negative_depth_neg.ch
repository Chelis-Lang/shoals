module Shoals.TestsNeg.TreesGenericCallNegativeDepth
import Std.Test (assert_true)
import Shoals.Trees (tr_binom_european_call_generic)
-- Negative: a negative lattice depth is not a quantity. The terminal layer is
-- built over `n_steps + 1` nodes, so a negative depth leaves it empty and the
-- backward induction has no node to read. tr_checked_lattice_depth refuses at
-- the entry.
--
-- This entry point takes `log_u`, `log_d`, `p` and `disc` already computed, so
-- unlike the pricers it never divides the horizon by the step count. That is
-- why it refuses only a NEGATIVE depth: `n_steps = 0` names a well-defined
-- one-node lattice whose price is the intrinsic value, which is a documented
-- and correct answer and is pinned positively in tests/step_count_parity.ch.
--
-- Before the guard this failed with `index 0 out of bounds for list of len 0`,
-- which names an index rather than the precondition a caller violated, so
-- here the guard replaces a leaked internal error rather than adding a
-- diagnostic to a silent wrong answer.
def test_neg_trees_generic_call_negative_depth() -> unit ! { Test } = {
  price = tr_binom_european_call_generic(cast(100.0, f32), cast(90.0, f32), cast(0.025, f32), cast(-0.025, f32), cast(0.5, f32), cast(0.99, f32), cast(-8, i64))
  assert_true(gt(price, cast(1e30, f32)), "should not reach here: unguarded this leaked an index error from the empty terminal layer")
}
