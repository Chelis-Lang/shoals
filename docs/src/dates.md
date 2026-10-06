# Dates and day counts

Module: `Shoals.Date`.

This module computes year fractions under named day-count conventions. A
year fraction is an exact rational; converting it to a float is a separate,
correctly rounded step. Dates, calendar arithmetic, and business-day rules
come from `Std.Datetime` and `Std.Datetime.Business`, and market calendars
from Shoreleave (see [Holiday calendars](calendars.md)).

## Day-count conventions

```chelis
type DayCount =
  | ActualOver360
  | ActualOver365Fixed
  | ActualActualIsda
  | ActualActualIcma { reference_start: Date, reference_end: Date, frequency: i64 }
  | ThirtyEOver360
  | ThirtyEOver360Isda { maturity: Date }
  | ThirtyOver360Us { end_of_month: bool }
  | Business252 { calendar: BusinessCalendar }

def year_fraction(start: Date, end: Date, convention: DayCount) -> YearFraction
```

Each convention has one published definition, and its name says which.
Names that libraries use for different rules, such as "ACT/365" or
"30/360 ISDA", are not conventions here. An input a convention needs beyond
the two dates is a field of its variant, so the convention cannot be
requested without it.

| Variant | Convention | Definition |
|---|---|---|
| `ActualOver360` | ACT/360 | actual days / 360 |
| `ActualOver365Fixed` | ACT/365 Fixed | actual days / 365 |
| `ActualActualIsda` | ACT/ACT ISDA (ISDA 2006 §4.16(b)) | the days in each calendar year over that year's length, summed |
| `ActualActualIcma` | ACT/ACT ICMA (ICMA Rule 251) | accrued days / (frequency × days in the reference coupon period) |
| `ThirtyEOver360` | 30E/360, the Eurobond basis (ISDA 2006 §4.16(g)) | a day 31 counts as 30 |
| `ThirtyEOver360Isda` | 30E/360 ISDA (ISDA 2006 §4.16(h)) | a month-end day counts as 30, except an end date on the last day of February that is the maturity |
| `ThirtyOver360Us` | 30/360 US (SIFMA) | with `end_of_month`, February month-ends count as 30; then a 31 after a 30 or 31 counts 30; then a start 31 counts 30 |
| `Business252` | BUS/252 | business days of `calendar` in `[start, end)` / 252 |

Every convention measures a forward accrual. An end before the start fails
with a domain error rather than returning a negated fraction; equal dates
give zero. ACT/ACT ICMA fails when the frequency is below 1, when the
reference period is empty, and when the accrual leaves the reference period,
since an accrual outside it belongs to a different coupon period. BUS/252
fails when an accrual date lies outside the calendar's horizon.

ACT/ACT AFB is not provided: its treatment of 29 February in a period
longer than a year is disputed between sources.

From `tests/date.ch`, with the expected values as exact fractions:

```chelis
// ISDA's worked example: 61 days of a 365-day year
// plus 121 days of a 366-day year.
f = year_fraction(date(2003i64, 11i64, 1i64), date(2004i64, 5i64, 1i64), ActualActualIsda)
// year_fraction_numerator(f) == 66491, year_fraction_denominator(f) == 133590

// A full regular semi-annual ICMA period is exactly one half.
icma = ActualActualIcma { reference_start: date(2003i64, 11i64, 1i64), reference_end: date(2004i64, 5i64, 1i64), frequency: 2i64 }
half = year_fraction(date(2003i64, 11i64, 1i64), date(2004i64, 5i64, 1i64), icma)  // 1/2

// 1 to 8 July 2025 has four business days in the US federal government
// calendar: 4/252 = 1/63.
bus = year_fraction(date(2025i64, 7i64, 1i64), date(2025i64, 7i64, 8i64), Business252 { calendar: us_federal() })
```

## Year fractions and float conversion

```chelis
type YearFraction    // opaque

def year_fraction_numerator(f: YearFraction) -> i64
def year_fraction_denominator(f: YearFraction) -> i64
def year_fraction_to_f64(f: YearFraction) -> f64
def year_fraction_to_f32(f: YearFraction) -> f32
```

A `YearFraction` is a rational in lowest terms with a positive denominator.
It is opaque, so every value comes from `year_fraction` and is reduced.

`year_fraction_to_f64` returns the f64 nearest the exact fraction. It fails
when the numerator's magnitude or the denominator exceeds 2^53, where the
integer-to-float casts would no longer be exact. `year_fraction_to_f32`
returns the f32 nearest the exact fraction. It rounds the f64 quotient a
second time, which the comment in `src/date.ch` proves correct whenever the
denominator is below 2^29 and the magnitude below 2^24, and it fails outside
those bounds rather than risk a double rounding. Every convention stays
inside both bounds for ordinary inputs; only an ACT/ACT ICMA frequency in the
millions reaches them.

## Removed date helpers

The generic date helpers Shoals used to carry are removed in favour of the
standard library:

| Removed | Replacement |
|---|---|
| `Act360`, `Act365`, `ThirtyThreeSixty`, `ActActIsda`, `ActActIcma` | `ActualOver360`, `ActualOver365Fixed`, `ThirtyEOver360` (what `ThirtyThreeSixty` computed), `ActualActualIsda`, `ActualActualIcma` |
| `year_fraction(...) -> f64` | `year_fraction(...) -> YearFraction`, then `year_fraction_to_f64` or `year_fraction_to_f32` |
| `is_weekend` | `Std.Datetime.date_weekday`, or `Std.Datetime.Business.is_business_day` against a calendar |
| `date_roll_following`, `date_roll_preceding`, `date_roll_modified_following` and their `*_published` forms | `Std.Datetime.Business.business_day_roll(calendar, d, Following / Preceding / ModifiedFollowing)` |
| `add_business_days` | `Std.Datetime.Business.business_day_offset(calendar, d, n, start)`, where `start` states what a non-business start date does |
| `add_months` | `Std.Datetime.date_add_months(d, n, overflow)` with an explicit `DayOverflow` |
| `days_in_month` | `Std.Datetime.days_in_month` |
| `schedule_from_tenor`, `schedule_from_tenor_calendar` | `Shoals.Schedule.schedule_unadjusted` and `schedule`; see [Tenors and schedules](tenors.md) |
