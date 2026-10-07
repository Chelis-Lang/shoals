# Currency-tagged money

Module: `Shoals.CurrencyTag`.

This module carries a currency tag at runtime on a monetary amount,
provides constructors for the three supported currencies, a non-negative
money wrapper, currency conversion, and same-currency addition and
subtraction. Adding or subtracting amounts in different currencies fails
rather than silently mixing units.

## Types

```chelis
type Currency =
  | USD
  | GBP
  | EUR

type Money =
  | Money { amount: f32, currency: Currency }

type NonNegativeMoney =
  | NonNegativeMoney { money: Money }
```

A `Money` is an amount tagged with a currency. A `NonNegativeMoney` wraps a
`Money` whose amount has been clamped at zero.

## Constructors and accessors

```chelis
def usd(amount: f32) -> Money
def gbp(amount: f32) -> Money
def eur(amount: f32) -> Money
def money_value(m: Money) -> f32
def money_currency(m: Money) -> Currency
```

`usd`, `gbp`, and `eur` construct money in the respective currency.
`money_value` reads the amount and `money_currency` the currency tag. For example:

```chelis
m = usd(cast(12.5, f32))
v = money_value(m)  // v == 12.5
```

## Non-negative money

```chelis
def money_non_negative(m: Money) -> NonNegativeMoney
def money_non_negative_value(m: NonNegativeMoney) -> f32
def money_non_negative_currency(m: NonNegativeMoney) -> Currency
```

`money_non_negative` clamps a money's amount at zero and wraps it, keeping
the currency. `money_non_negative_value` and `money_non_negative_currency`
read the wrapped amount and currency. For example:

```chelis
checked = money_non_negative(eur(cast(-0.01, f32)))
v = money_non_negative_value(checked)  // v == 0.0
```

## Conversion and arithmetic

```chelis
def convert(m: Money, target: Currency, rate: f32) -> Money
def money_add(lhs: Money, rhs: Money) -> Money
def money_sub(lhs: Money, rhs: Money) -> Money
```

`convert` multiplies the amount by `rate` and retags it with the target
currency. `money_add` and `money_sub` add and subtract two amounts when they
carry the same currency, keeping that currency; a mismatch fails. For example:

```chelis
converted = convert(usd(cast(100.0, f32)), GBP, cast(0.8, f32))
v = money_value(converted)  // v == 80.0

total = money_add(usd(cast(10.0, f32)), usd(cast(2.5, f32)))
t = money_value(total)  // t == 12.5
```

Subtraction may produce a negative amount; use `money_non_negative` if you
need to floor it at zero.
