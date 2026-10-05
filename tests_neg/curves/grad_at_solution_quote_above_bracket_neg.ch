module Shoals.TestsNeg.GradAtSolutionQuoteAboveBracket
import Std.Test (assert_true)
import Shoals.Curves (deposit, bootstrap_grad_at_solution)
-- Negative (shoals#79): the bracket miss reached through
-- `bootstrap_grad_at_solution` rather than `bootstrap_multi`, and with a
-- deposit rather than a par swap. A 1y deposit at 5000% implies a zero rate of
-- about log(51) = 3.93, outside the `[-0.5, 2.0]` bracket.
--
-- This replaces `test_grad_out_of_bracket_propagates_nan_observably` in
-- `tests/curves_bootstrap_ift.ch`, which took the same input and asserted the
-- sentinel this issue decides against: "returns observably degenerate value
-- (NaN or 0); silent garbage is prevented because the caller can test
-- eq(g, g)". Its in-bracket parity case, `test_grad_high_rate_within_bracket`
-- (a 200% deposit, implied zero about 110%), is unchanged and still passes.
def test_neg_grad_at_solution_rejects_quote_above_bracket() -> unit ! { Test } = {
  g = index(bootstrap_grad_at_solution([deposit(cast(1.0, f32), cast(50.0, f32))]), cast(0, i64))
  assert_true(eq(g, g), "should not reach here")
}
