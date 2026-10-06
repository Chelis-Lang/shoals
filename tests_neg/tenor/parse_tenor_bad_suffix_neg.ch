module Shoals.TestsNeg.TenorParseBadSuffix
import Std.Test (assert_eq)
import Std.Datetime (period)
import Shoals.Tenor (parse_tenor, tenor_period)
-- X is not a tenor unit; the trapping parser names the accepted grammar.
def test_neg_parse_tenor_rejects_unknown_suffix() -> unit ! { Test } = assert_eq(tenor_period(parse_tenor("3X")), period(3i64, 0i64), "an unknown unit must fail")
