module Shoals.Tests.CurrencyTag
import Std.Test (assert_close, assert_true)
import Shoals.CurrencyTag (Currency, usd, gbp, eur, money_value, money_currency, money_non_negative, money_non_negative_value, money_non_negative_currency, convert, money_add, money_sub)
def is_usd(c: Currency) -> bool = {
  match c with {
    | USD => true
    | GBP => false
    | EUR => false
  }
}
def is_gbp(c: Currency) -> bool = {
  match c with {
    | USD => false
    | GBP => true
    | EUR => false
  }
}
def is_eur(c: Currency) -> bool = {
  match c with {
    | USD => false
    | GBP => false
    | EUR => true
  }
}
def test_usd_constructor_value_and_currency() -> unit ! { Test } = {
  m = usd(cast(12.5, f32))
  _ = assert_close(money_value(m), cast(12.5, f32), cast(0.000001, f32), "usd preserves amount")
  assert_true(is_usd(money_currency(m)), "usd tags currency")
}
def test_gbp_and_eur_constructors_tag_currency() -> unit ! { Test } = {
  sterling = gbp(cast(7.0, f32))
  euros = eur(cast(8.0, f32))
  _ = assert_true(is_gbp(money_currency(sterling)), "gbp tags currency")
  assert_true(is_eur(money_currency(euros)), "eur tags currency")
}
def test_non_negative_money_clamps_negative() -> unit ! { Test } = {
  checked = money_non_negative(eur(cast(-0.01, f32)))
  _ = assert_close(money_non_negative_value(checked), cast(0.0, f32), cast(0.000001, f32), "negative money is clamped")
  assert_true(is_eur(money_non_negative_currency(checked)), "clamp preserves currency")
}
def test_convert_changes_currency_and_scales_value() -> unit ! { Test } = {
  converted = convert(usd(cast(100.0, f32)), GBP, cast(0.8, f32))
  _ = assert_close(money_value(converted), cast(80.0, f32), cast(0.000001, f32), "convert scales by rate")
  assert_true(is_gbp(money_currency(converted)), "convert sets target currency")
}
def test_money_add_same_currency() -> unit ! { Test } = {
  total = money_add(usd(cast(10.0, f32)), usd(cast(2.5, f32)))
  _ = assert_close(money_value(total), cast(12.5, f32), cast(0.000001, f32), "same-currency add")
  assert_true(is_usd(money_currency(total)), "addition keeps currency")
}
def test_money_sub_same_currency() -> unit ! { Test } = {
  diff = money_sub(eur(cast(10.0, f32)), eur(cast(12.5, f32)))
  _ = assert_close(money_value(diff), cast(-2.5, f32), cast(0.000001, f32), "same-currency subtraction may be negative")
  assert_true(is_eur(money_currency(diff)), "subtraction keeps currency")
}
