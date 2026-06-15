# Tenors

Module: `Shoals.Tenor`.

This module represents a tenor as a count and a unit, provides constructors
for the common units including the overnight family, converts a tenor to a
number of days, and advances a date by a tenor. Dates come from `Std.Time`.

## Types

```chelis
type TenorUnit =
  | Day
  | Week
  | Month
  | Year
  | Overnight
  | TomorrowNext
  | SpotNext

type Tenor =
  | Tenor { count: int64, unit: TenorUnit }
```

A `Tenor` is a `count` and a `TenorUnit`. The units include calendar steps
(day, week, month, year) and the three overnight settlement steps: overnight,
tomorrow-next, and spot-next.

## Constructors

```chelis
def tenor(count: int64, unit: TenorUnit) -> Tenor
def days_n(n: int64) -> Tenor
def weeks_n(n: int64) -> Tenor
def months_n(n: int64) -> Tenor
def years_n(n: int64) -> Tenor
def overnight() -> Tenor
def tomorrow_next() -> Tenor
def spot_next() -> Tenor
```

`tenor` is the general constructor; `days_n`, `weeks_n`, `months_n`, and
`years_n` build a tenor of `n` of the corresponding unit; and `overnight`,
`tomorrow_next`, and `spot_next` build the three settlement tenors. A
negative count expresses a step into the past.

## Conversion and application

```chelis
def days_per_unit(unit: TenorUnit) -> int64
def tenor_to_days(t: Tenor) -> int64
def tenor_apply(t: Tenor, reference: Date) -> Date
```

`days_per_unit` returns the day count of a single unit: a day is one, a week
seven, a month thirty, a year three hundred sixty-five, overnight one,
tomorrow-next two, and spot-next three. `tenor_to_days` multiplies the count
by the unit's day count. `tenor_apply` advances a reference date by the
tenor's day count.

From `tests/tenor.ch`, three months is ninety days and advances a reference
date by ninety days:

```chelis
d = tenor_to_days(months_n(cast(3, int64)))  // d == 90

ref = date(cast(2025, int64), cast(6, int64), cast(15, int64))
shifted = tenor_apply(months_n(cast(3, int64)), ref)
// days_between(ref, shifted) == 90
```

Months and years use the fixed thirty-day and three-hundred-sixty-five-day
approximations, so tenor arithmetic is calendar-day arithmetic, not
calendar-aware month stepping. Parsing a tenor from a string is not part of
this surface; see [Scope and limitations](scope.md).
