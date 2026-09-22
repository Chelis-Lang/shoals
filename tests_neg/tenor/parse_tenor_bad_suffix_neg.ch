module Shoals.TestsNeg.ParseTenorBadSuffix
import Std.Test (assert_eq)
import Shoals.Tenor (Tenor, parse_tenor, tenor_to_days)
-- Negative: `parse_tenor` on an unknown unit suffix must reject with a
-- diagnostic naming the function and the accepted suffix set
-- (src/tenor.ch). The text is a runtime value, so a runtime `fail` is the
-- right shape; too-short strings route through the sibling length guard.
def test_neg_parse_tenor_rejects_unknown_suffix() -> unit ! { Test } = {
  t = parse_tenor("3Q")
  assert_eq(tenor_to_days(t), cast(0, i64), "should not reach here")
}
