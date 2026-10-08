module Shoals.Tests.LsmHeavy
import Std.Test (assert_true)
import Shoals.Lsm (lsm_american_put)
-- Replicated 8 x 4000-path accuracy is measured natively by
-- scripts/check_lsm_accuracy.py; this evaluator regression pins the report.
def test_lsm_issue152_fifty_dates_no_price_collapse() -> unit ! { Test } = {
  paths = to_tensor(map(fn (i: i64) -> 0f32, range(0i64, 2000i64)))
  price = lsm_american_put(key_from_seed(21i64), paths, 100f32, 100f32, 0.05f32, 0.2f32, 1f32, 50i64)
  assert_true(and(gt(price, 5.3f32), lt(price, 6.9f32)), "shoals#152 seed-21 reproducer no longer collapses to 2.4734879; this bounded regression is not an exact European lower-bound or grid-monotonicity claim")
}
