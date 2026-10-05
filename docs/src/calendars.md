# Holiday calendars

Module: `Shoals.HolidayCal`.

This module represents a named calendar as a list of holiday dates, ships
2025 New York and London lists, combines calendars, and reports whether a
date is a holiday or a business day. Dates come from `Std.Datetime`.
It also exposes Shoreleave's published market and public-holiday calendars
for horizon-checked settlement dates.

## The Calendar type

```chelis
type Calendar =
  | Calendar { name: string, holidays: List[Date] }

def empty_calendar(name: string) -> Calendar
def weekend_only_calendar() -> Calendar
def hc_nyc_calendar() -> Calendar
def hc_ldn_calendar() -> Calendar
def hc_nyc_calendar_year(year: i64) -> Calendar
def hc_ldn_calendar_year(year: i64) -> Calendar
def hc_nyc_calendar_multi(years: List[i64]) -> Calendar
def hc_ldn_calendar_multi(years: List[i64]) -> Calendar
def joint_calendar(left: Calendar, right: Calendar) -> Calendar
def as_business_calendar(cal: Calendar) -> BusinessCalendar
```

`empty_calendar` and `weekend_only_calendar` carry no holiday dates, so
under them only weekends are non-business. `hc_nyc_calendar` and `hc_ldn_calendar`
carry 2025 New York and London holiday lists. The year and multi-year
constructors generate smaller lists from fixed rules; they are not complete
bank-holiday calendars. `joint_calendar`
merges the holiday lists of two calendars, keeping the left calendar's name,
so a date that is a holiday in either is a holiday in the joint calendar.
`as_business_calendar` gives a local calendar a Monday-to-Friday business
week over the full `Std.Datetime.Date` range. Business-day queries and rolls
then use `Std.Datetime.Business`. The adapter normalizes weekend holidays out
of its business-day representation; `is_holiday` still reports membership in
the original list, including holidays that fall on a weekend.

## Published calendars

```chelis
def hc_us_federal_published() -> BusinessCalendar
def hc_england_wales_published() -> BusinessCalendar
def hc_japan_bank_published() -> BusinessCalendar
def hc_new_south_wales_published() -> BusinessCalendar
def hc_hong_kong_published() -> BusinessCalendar
def hc_target_published() -> BusinessCalendar
def hc_nyse_published() -> BusinessCalendar
```

These constructors return the published calendars from Shoreleave 0.1.0.
They use `Std.Datetime.Business.BusinessCalendar`, which keeps its source's
holiday data, weekmask, and finite date horizon. A query outside that horizon
fails with a domain error; the corresponding `try_` operation returns `None`.
The supported horizons are US federal 2021–2030, England and Wales 2019–2028,
Japan Bank 1990–2027, New South Wales 2026–2027, Hong Kong 2025–2027,
TARGET 2026–2028, and NYSE 2026–2028.
Use the published calendars with `Std.Datetime.Business` operations or the
published-calendar rolls in `Shoals.Date`. The `Calendar` constructors above
retain their own fixed lists and rules.

The published calendars name their own markets. Japan Bank includes bank-only
closures such as 2 January; the Shoals Tokyo predicate lists national
holidays. New South Wales public holidays exclude the August bank holiday
that the Shoals Sydney rule lists. TARGET remains open on regional German
holidays that the Shoals Frankfurt predicate lists. Hong Kong's published
calendar has a Monday-to-Saturday business week. Choose the calendar whose
market and observance rules match the transaction.

## Predicates

```chelis
def is_holiday(cal: Calendar, d: Date) -> bool
def is_business_day(cal: Calendar, d: Date) -> bool
```

`is_holiday` reports whether a date is in the calendar's holiday list.
`is_business_day` reports whether a date is neither a weekend nor a holiday.
From `tests/holidaycal.ch`:

```chelis
cal = hc_nyc_calendar()
ny = is_holiday(cal, date(cast(2025, i64), cast(1, i64), cast(1, i64)))   // true
wed = is_business_day(cal, date(cast(2025, i64), cast(8, i64), cast(13, i64)))  // true
```

A joint New York and London calendar treats both US Independence Day and UK
Boxing Day as holidays:

```chelis
joint = joint_calendar(hc_nyc_calendar(), hc_ldn_calendar())
july4 = is_holiday(joint, date(cast(2025, i64), cast(7, i64), cast(4, i64)))   // true
boxing = is_holiday(joint, date(cast(2025, i64), cast(12, i64), cast(26, i64))) // true
```


## International holiday predicates

`hc_tyo_is_holiday`, `hc_syd_is_holiday`, `hc_fra_is_holiday`, and
`hc_hkg_is_holiday` accept year, month, and day as `i64` values. Each checks
membership in its annual holiday list. They do not exclude weekends.
Hong Kong's lookup supports 2025–2030 and returns false for other years.
The regional rules are limited; check [Scope and limitations](scope.md)
before using them for settlement.
