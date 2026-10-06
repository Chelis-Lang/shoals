# Tenors and schedules

Modules: `Shoals.Tenor`, `Shoals.Schedule`.

A tenor is a calendar period, so a month is a month and not thirty days.
Money-market tenors such as overnight are counted in business days instead.
A schedule steps from a fixed anchor by whole tenors and can then roll each
date in a business calendar. Dates and periods come from `Std.Datetime`, and
business-day rules from `Std.Datetime.Business`.

## Calendar tenors

```chelis
type Tenor    // opaque: a positive Std.Datetime.Period

def tenor_days(n: i64) -> Tenor
def tenor_weeks(n: i64) -> Tenor
def tenor_months(n: i64) -> Tenor
def tenor_years(n: i64) -> Tenor
def tenor_period(t: Tenor) -> Period
def tenor_apply(t: Tenor, reference: Date, overflow: DayOverflow) -> Date
def parse_tenor(text: string) -> Tenor
def try_parse_tenor(text: string) -> Option[Tenor]
```

A week is seven days and a year is twelve months. Each constructor fails
with a domain error for a count below 1. `tenor_apply` adds the period with
`Std.Datetime.date_add_period` and takes the caller's `DayOverflow` policy,
because a month step from the 31st has no day-31 answer in a shorter month:
`ClampToMonthEnd` moves to the month's last day and `RejectInvalidDay` fails.

`parse_tenor` accepts exactly one or more ASCII digits with a value of at
least 1 followed by `D`, `W`, `M`, or `Y`, such as `3M` or `10Y`. It fails on
anything else, including a sign, a space, a lowercase unit, and `ON`, `TN`,
or `SN`, which are not calendar tenors. `try_parse_tenor` returns `None`
instead of failing.

From `tests/tenor.ch`:

```chelis
tenor_apply(tenor_months(3i64), date(2025i64, 6i64, 15i64), RejectInvalidDay)
// 2025-09-15, 92 days later
tenor_apply(tenor_months(1i64), date(2025i64, 1i64, 31i64), ClampToMonthEnd)
// 2025-02-28
tenor_apply(tenor_years(1i64), date(2024i64, 2i64, 29i64), ClampToMonthEnd)
// 2025-02-28
```

## Business-day tenors and spot lags

```chelis
type BusinessDayTenor =
  | BusinessDayTenor { lag: i64, length: i64 }

def overnight() -> BusinessDayTenor            // lag 0, length 1
def tomorrow_next() -> BusinessDayTenor        // lag 1, length 1
def spot_next(spot_days: i64) -> BusinessDayTenor  // lag spot_days, length 1
def business_day_tenor_dates(t: BusinessDayTenor, trade: Date, calendar: BusinessCalendar, start: NonBusinessStart) -> (Date, Date)

type SpotLag
def two_calendar_lag(days: i64, count_calendar: BusinessCalendar, adjust_calendar: BusinessCalendar, roll: BusinessDayRoll) -> SpotLag
def lagged_date(lag: SpotLag, trade: Date) -> Date
```

ON, TN, and SN are a lag and a length in business days: the period starts
`lag` business days after the trade date and ends `length` business days
after its start. `business_day_tenor_dates` returns the start and end in the
given calendar; `start` states what a non-business trade date does, either
`RejectNonBusinessStart` or `RollStartForward`. Spot-next starts at spot, so
the caller states the spot lag. Over the 4 July 2025 holiday in
`us_federal()`, overnight from 3 July runs to 7 July.

A spot lag follows the two-calendar form of OpenGamma Strata's
`DaysAdjustment`: `lagged_date` counts `days` business days in
`count_calendar`, then rolls the result in `adjust_calendar`. Counting from
a non-business trade date, the first step lands on the next business day.
From `tests/tenor.ch`, two Japanese bank days from 2 July 2025 reach 4 July,
which the US federal roll moves to 7 July; from 30 December 2025 the Japanese
year-end closures move the count to 6 January 2026, where a US count reaches
2 January. A negative lag fails, and so does a date outside either
calendar's horizon.

The examples use `us_federal()`, the US federal government calendar, as a
calendar with known closures; it is not a USD settlement calendar (see
[Holiday calendars](calendars.md)).

## Schedules

```chelis
type StubConvention =
  | NoStub
  | ShortInitial
  | LongInitial
  | ShortFinal
  | LongFinal

def schedule_unadjusted(start: Date, end: Date, tenor: Tenor, stub: StubConvention, end_of_month: bool, overflow: DayOverflow) -> List[Date]
def schedule(start: Date, end: Date, tenor: Tenor, stub: StubConvention, end_of_month: bool, overflow: DayOverflow, calendar: BusinessCalendar, roll: BusinessDayRoll) -> List[Date]
```

`schedule_unadjusted` returns the dates from `start` to `end` inclusive,
strictly increasing. Each date is the anchor plus k whole tenors, never the
previous date plus one tenor, so a day of month clamped in February does not
drift into the following months. A final stub anchors at `start` and an
initial stub at `end`. A short stub keeps the irregular period on its own; a
long stub merges it into the neighbouring regular period. `NoStub` requires
the tenor to divide the span exactly and fails otherwise. With
`end_of_month` true, a month-end anchor and a whole-month tenor keep every
date on its month end, and the month end decides the day, so `overflow`
has nothing to decide. Otherwise `overflow` applies only to the dates the
schedule emits. The schedule first selects its dates as whole-tenor steps
from the anchor, locating them by clamping, then applies `overflow` once to
each selected step. Under `RejectInvalidDay` an emitted date on a nonexistent
day fails, while a step past the end, or a step a long stub merges away, that
would land on one does not.
Whether the tenor divides the span is judged under the same policy, so the
period from 30 December to 28 February is two regular months when clamped
and a stub when rejected. A start that is not before the end fails.

`schedule` rolls each date of the unadjusted schedule in `calendar` under
`roll`. It fails if two dates roll onto the same business day, rather than
silently dropping one, or if a date lies outside the calendar's horizon.

From `tests/schedule.ch`:

```chelis
schedule_unadjusted(date(2025i64, 1i64, 31i64), date(2025i64, 5i64, 31i64), tenor_months(1i64), NoStub, false, ClampToMonthEnd)
// 31 Jan, 28 Feb, 31 Mar, 30 Apr, 31 May

schedule_unadjusted(date(2025i64, 1i64, 15i64), date(2025i64, 12i64, 31i64), tenor_months(3i64), ShortInitial, false, ClampToMonthEnd)
// 15 Jan, then 31 Mar, 30 Jun, 30 Sep, 31 Dec anchored at the end

schedule(date(2025i64, 5i64, 4i64), date(2025i64, 8i64, 4i64), tenor_months(1i64), NoStub, false, ClampToMonthEnd, us_federal(), Following)
// 5 May, 4 Jun, 7 Jul, 4 Aug: Sunday 4 May and the 4 July holiday roll forward
```

## Removed tenor API

`TenorUnit`, `tenor`, `days_n`, `weeks_n`, `months_n`, `years_n`,
`days_per_unit`, `tenor_to_days`, and `parse_unit_suffix` are removed: they measured a month as
30 days and a year as 365. Use `tenor_days`, `tenor_weeks`, `tenor_months`,
and `tenor_years`, and `tenor_period` where a `Period` is needed. The
calendar-day `overnight()`, `tomorrow_next()`, and `spot_next()` tenors and
the `ON`, `TN`, and `SN` spellings of `parse_tenor` are replaced by the
business-day tenors above. `tenor_apply` now takes a `DayOverflow`.
