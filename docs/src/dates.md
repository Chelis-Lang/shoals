# Dates and day counts

Module: `Shoals.Date`.

This module computes year fractions under the standard day-count
conventions, detects weekends, rolls a date to a business day under the
following / modified-following / preceding rules, and generates a schedule
of dates stepped by a number of months. The date type itself comes from
`Std.Time`, constructed with `date(year, month, day)`.

## Day-count conventions

```chelis
type DayCount =
  | Act360
  | Act365
  | ThirtyThreeSixty
  | ActAct

def year_fraction(start: Date, end: Date, convention: DayCount) -> f32
```

`year_fraction` returns the year fraction between two dates under the chosen
convention. `Act360` divides actual days by 360, `Act365` divides by 365,
`ThirtyThreeSixty` is the 30/360 bond-basis count, and `ActAct` divides
actual days by 365.25. From `tests/date.ch`:

```chelis
start = date(cast(2025, i64), cast(1, i64), cast(1, i64))
end = date(cast(2026, i64), cast(1, i64), cast(1, i64))
yf = year_fraction(start, end, Act365)  // yf == 1.0

half = year_fraction(
  date(cast(2025, i64), cast(1, i64), cast(15, i64)),
  date(cast(2025, i64), cast(7, i64), cast(15, i64)),
  ThirtyThreeSixty
)  // half == 0.5
```

## Weekends and business-day rolling

```chelis
def is_weekend(d: Date) -> bool
def date_roll_following(d: Date, weekend_only: bool) -> Date
def date_roll_modified_following(d: Date, weekend_only: bool) -> Date
def date_roll_preceding(d: Date, weekend_only: bool) -> Date
def add_business_days(d: Date, n: i64, weekend_only: bool) -> Date
```

`is_weekend` reports whether a date falls on Saturday or Sunday.
`date_roll_following` advances a weekend date forward to the next weekday,
`date_roll_preceding` retreats it to the previous weekday, and
`date_roll_modified_following` rolls forward unless that crosses into the
next month, in which case it rolls back. `add_business_days` steps forward
`n` days, skipping weekends. From `tests/date.ch`, a Saturday rolls to the
following Monday:

```chelis
sat = date(cast(2025, i64), cast(1, i64), cast(4, i64))
rolled = date_roll_following(sat, true)
// rolled is Monday 2025-01-06
```

Both values of `weekend_only` currently give weekend-only behavior; this
module does not consult a holiday list. Check holidays separately with
`Shoals.HolidayCal.is_business_day`.

## Schedule generation

```chelis
def schedule_from_tenor(start: Date, end: Date, step_months: i64) -> List[Date]
def days_in_month(year: i64, month: i64) -> i64
def add_months(d: Date, n: i64) -> Date
def schedule_from_tenor_calendar(start: Date, end: Date, step_months: i64) -> List[Date]
```

`schedule_from_tenor` returns a list of dates from `start`, stepped by
`step_months` months, up to and including the last stop at or before `end`.
The first entry is the start date and the schedule is strictly increasing.
From `tests/date.ch`, a quarterly schedule across 2025 has five stops:

```chelis
dates = schedule_from_tenor(
  date(cast(2025, i64), cast(1, i64), cast(1, i64)),
  date(cast(2025, i64), cast(12, i64), cast(31, i64)),
  cast(3, i64)
)
// len(dates) == 5
```

`schedule_from_tenor` treats a month as 30 days. For month-of-year
stepping, `add_months` caps the day at the destination month's end, and
`schedule_from_tenor_calendar` builds a schedule using that operation.
Neither generator rolls dates against a holiday calendar.
