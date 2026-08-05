module Shoals.TestsNeg.MoneyAddMismatch
import Std.Test (assert_close)
import Shoals.CurrencyTag (Currency, Money, usd, gbp, money_add, money_value)
-- Negative: `money_add` on mixed currencies must reject with a diagnostic
-- naming the operation (src/currencytag.ch). The currency tags are runtime
-- values, so a runtime `fail` (not a static catch) is the right shape --
-- this guard is what Whale's bankroll code depends on to never silently
-- add USD to GBP.
def test_neg_money_add_rejects_currency_mismatch() -> unit ! { Test } = {
  total = money_add(usd(cast(10.0, f32)), gbp(cast(5.0, f32)))
  assert_close(money_value(total), cast(0.0, f32), cast(1e-6, f32), "should not reach here")
}
