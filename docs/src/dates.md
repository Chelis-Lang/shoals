# Dates and day counts

Module: `Shoals.Date`.

This module computes year fractions under the standard day-count
conventions, detects weekends, rolls a date to a business day under the
following / modified-following / preceding rules against a holiday
calendar, and generates a schedule of dates stepped by a number of months.
The date type itself comes from `Std.Time`, constructed with
`date(year, month, day)`.

## Day-count conventions

```chelis
type DayCount =
  | Act360
  | Act365
  | ThirtyThreeSixty
  | ActActIsda
  | ActActIcma { period_start: Date, period_end: Date, frequency: i64 }

def year_fraction(start: Date, end: Date, convention: DayCount) -> f64
```

`year_fraction` returns the year fraction between two dates under the chosen
convention. `Act360` divides actual days by 360, `Act365` divides by 365, and
`ThirtyThreeSixty` is the 30/360 bond-basis count.

`ActActIsda` splits the interval at calendar-year boundaries and divides each
segment by the length of the year it falls in, so a day in a leap year weighs
1/366 and a day in an ordinary year 1/365. A whole calendar year is therefore
exactly 1.0 whether or not it is a leap year. A reversed interval returns the
negated fraction.

`ActActIcma` measures accrued days against the full coupon period, scaled by
the coupon frequency, so a regular full period is exactly `1/frequency`
whatever its actual day count. ICMA is not computable from `(start, end)`
alone, so the convention **carries** the enclosing coupon period and the
frequency. That is deliberate: it makes an ICMA request with *no* period
unrepresentable rather than a runtime error. A frequency below 1, or a coupon
period that does not end after it starts, traps.

It does **not** make every invalid ICMA request unrepresentable, and the
difference matters. `year_fraction` validates the coupon period and the
frequency; it does **not** check that `start` and `end` lie within that period.
`year_fraction` does not check that `start` and `end` lie within that period,
and **the magnitude of the result carries no information about whether they
did.** An invalid accrual returns a number, not an error, and no bound on that
number distinguishes it from a valid one — so no assertion on the result is a
substitute for passing a correct accrual range. Keeping the accrual inside the
period is the caller's responsibility.

Some measured examples, which are illustrations and not an exhaustive list of
the ways this goes wrong: an accrual lying wholly outside the period and shorter
than it returns a small positive fraction (0.0852); one longer than the period
returns a value above `1/frequency` (1.5027); a reversed accrual returns a
negative; a partial overlap returns a plausible interior value (0.2527); and a
period whose length contradicts its declared frequency — an annual period
declared `frequency: 2` — returns 0.5 for a whole calendar year.

From `tests/date.ch`:

```chelis
// The ISDA 2006 worked example: 61 days of a 365-day year
// plus 121 days of a 366-day year.
start = date(cast(2003, i64), cast(11, i64), cast(1, i64))
end = date(cast(2004, i64), cast(5, i64), cast(1, i64))
yf = year_fraction(start, end, ActActIsda)
// yf == 61/365 + 121/366 == 0.49772438056740775

// A full semi-annual ICMA period is exactly one half.
convention = ActActIcma { period_start: start, period_end: end, frequency: cast(2, i64) }
half = year_fraction(start, end, convention)  // half == 0.5
```

`year_fraction` returns `f64`. The ACT/ACT conventions are checked against an
independently derived proleptic-Gregorian calendar in
`references/date.ch`, not against the subject's own day arithmetic.

## Weekends and business-day rolling

```chelis
def is_weekend(d: Date) -> bool
def date_roll_following(d: Date, cal: Calendar) -> Date
def date_roll_modified_following(d: Date, cal: Calendar) -> Date
def date_roll_preceding(d: Date, cal: Calendar) -> Date
def add_business_days(d: Date, n: i64, cal: Calendar) -> Date
```

`is_weekend` reports whether a date falls on Saturday or Sunday. Every roll
takes the `Shoals.HolidayCal.Calendar` it rolls against and treats a date as a
business day only when it is neither a weekend nor a holiday in that calendar.
`date_roll_following` advances to the next business day, `date_roll_preceding`
retreats to the previous one, and `date_roll_modified_following` rolls forward
unless that crosses into the next month, in which case it rolls back.
`add_business_days` steps forward `n` days, skipping non-business days.

Pass `weekend_only_calendar()` for weekend-only behavior:

```chelis
sat = date(cast(2025, i64), cast(1, i64), cast(4, i64))
rolled = date_roll_following(sat, weekend_only_calendar())
// rolled is Monday 2025-01-06

// 2025-07-04 is a Friday and a NYC holiday.
independence_day = date(cast(2025, i64), cast(7, i64), cast(4, i64))
date_roll_following(independence_day, hc_nyc_calendar())
// Monday 2025-07-07
date_roll_following(independence_day, weekend_only_calendar())
// unchanged: a weekend-only calendar does not see it
```

These rolls took a `weekend_only: bool` before shoals#87, and both of its
branches were identical, so no caller could reach a holiday calendar from this
module. The flag was replaced rather than fixed in place:
`weekend_only_calendar()` expresses the old behavior exactly, and a `Calendar`
parameter has no way to be silently ignored.

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
Neither generator rolls its stops against a holiday calendar; compose one of
the rolls above over the result when settlement dates are needed.
