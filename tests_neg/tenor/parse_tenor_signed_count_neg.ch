module Shoals.TestsNeg.TenorParseSignedCount
import Std.Test (assert_eq)
import Std.Datetime (period)
import Shoals.Tenor (parse_tenor, tenor_period)
-- A sign is not a digit, so "+3M" is not a tenor.
def test_neg_parse_tenor_rejects_a_sign() -> unit ! { Test } = assert_eq(tenor_period(parse_tenor("+3M")), period(3i64, 0i64), "a signed count must fail")
