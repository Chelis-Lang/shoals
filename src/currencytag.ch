module Shoals.CurrencyTag
export (Currency, Money, NonNegativeMoney, usd, gbp, eur, money_value, money_currency, money_non_negative, money_non_negative_value, money_non_negative_currency, convert, money_add, money_sub)
type Currency =
  | USD
  | GBP
  | EUR
type Money =
  | Money { amount: f32, currency: Currency }
type NonNegativeMoney =
  | NonNegativeMoney { money: Money }
def clamp_non_negative(amount: f32) -> f32 = if lt(amount, cast(0.0, f32)) then cast(0.0, f32) else amount
def usd(amount: f32) -> Money = Money { amount, currency: USD }
def gbp(amount: f32) -> Money = Money { amount, currency: GBP }
def eur(amount: f32) -> Money = Money { amount, currency: EUR }
def money_value(m: Money) -> f32 =
  match m with {
    | Money { amount, currency: _ } => amount
  }
def money_currency(m: Money) -> Currency =
  match m with {
    | Money { amount: _, currency } => currency
  }
def money_non_negative(m: Money) -> NonNegativeMoney = NonNegativeMoney { money: Money { amount: money_value(m) |> clamp_non_negative, currency: money_currency(m) } }
def money_non_negative_value(m: NonNegativeMoney) -> f32 =
  match m with {
    | NonNegativeMoney { money } => money_value(money)
  }
def money_non_negative_currency(m: NonNegativeMoney) -> Currency =
  match m with {
    | NonNegativeMoney { money } => money_currency(money)
  }
def convert(m: Money, target: Currency, rate: f32) -> Money = Money { amount: money_value(m) |> mul(rate), currency: target }
def money_add(lhs: Money, rhs: Money) -> Money = {
  lhs_currency = money_currency(lhs)
  rhs_currency = money_currency(rhs)
  lhs_amount = money_value(lhs)
  rhs_amount = money_value(rhs)
  if same_currency(lhs_currency, rhs_currency) then Money { amount: lhs_amount |> add(rhs_amount), currency: lhs_currency } else fail("money_add: currency mismatch")
}
def money_sub(lhs: Money, rhs: Money) -> Money = {
  lhs_currency = money_currency(lhs)
  rhs_currency = money_currency(rhs)
  lhs_amount = money_value(lhs)
  rhs_amount = money_value(rhs)
  if same_currency(lhs_currency, rhs_currency) then Money { amount: lhs_amount |> sub(rhs_amount), currency: lhs_currency } else fail("money_sub: currency mismatch")
}
def same_currency(lhs: Currency, rhs: Currency) -> bool =
  match lhs with {
    | USD => match rhs with {
    | USD => true
    | GBP => false
    | EUR => false
  }
    | GBP => match rhs with {
    | USD => false
    | GBP => true
    | EUR => false
  }
    | EUR => match rhs with {
    | USD => false
    | GBP => false
    | EUR => true
  }
  }
