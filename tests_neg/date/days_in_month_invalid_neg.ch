module Shoals.TestsNeg.DateInvalidMonth
import Std.Test (assert_eq)
import Shoals.Date (days_in_month)
def test_neg_days_in_month_rejects_invalid_month() -> unit ! { Test } = assert_eq(days_in_month(2025i64, 13i64), 28i64, "an invalid month must fail")
