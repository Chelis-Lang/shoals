# Holiday calendars

Module: `Shoals.HolidayCal`.

This module represents a named calendar as a list of holiday dates, ships
2025 New York and London lists, combines calendars, and reports whether a
date is a holiday or a business day. Dates come from `Std.Datetime`.
It also exposes Shoreleave's published market and public-holiday calendars
for horizon-checked settlement dates.

For New York settlement, the source-backed calendars are
`hc_us_federal_published()` and `hc_nyse_published()`; for London settlement,
it is `hc_england_wales_published()`. For Tokyo, Sydney, Frankfurt, and Hong
Kong they are `hc_japan_bank_published()`, `hc_new_south_wales_published()`,
`hc_target_published()`, and `hc_hong_kong_published()`. The local
`hc_nyc_*` and `hc_ldn_*` constructors and the `hc_tyo_*`, `hc_syd_*`,
`hc_fra_*`, and `hc_hkg_*` predicates are fixed legacy lists and rules with
known gaps and limited coverage; see
[Local lists and their gaps](#local-lists-and-their-gaps).

## The Calendar type

```chelis
type Calendar =
  | Calendar { name: string, holidays: List[Date], valid_from: Date, valid_until: Date }

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

A `Calendar` carries the dates its holiday list covers, `valid_from` through
`valid_until`. Business-day answers exist only inside that coverage.
`empty_calendar` and `weekend_only_calendar` carry no holiday dates and state
that no date is a holiday, so they cover the full `Std.Datetime.Date` range and
under them only weekends are non-business. `hc_nyc_calendar` and
`hc_ldn_calendar` carry 2025 New York and London holiday lists and cover 2025.
`hc_nyc_calendar_year` and `hc_ldn_calendar_year` cover their one year. The
multi-year constructors cover the first through the last listed year; the
years may come in any order, but they must form an unbroken run, and an empty
list or a missing year fails with a domain error. These constructors generate
smaller lists from fixed rules; they are not complete bank-holiday calendars.
`joint_calendar` merges the holiday lists of two calendars, keeping the left
calendar's name, so a date that is a holiday in either is a holiday in the
joint calendar. Its coverage is the intersection of the two, because a
business-day answer needs both calendars' data.

`as_business_calendar` gives a local calendar a Monday-to-Friday business
week and its coverage as the horizon. Business-day queries and rolls then use
`Std.Datetime.Business`: a query outside the coverage fails with a domain
error, and the `try_` form returns `None`. A 2025 list does not answer for
2030 or 1900. Coverage that is empty, such as a joint calendar of two
disjoint years, fails when the calendar is adapted. The adapter keeps only the
holidays inside the coverage and normalizes weekend holidays out of its
business-day representation; `is_holiday` still reports membership in the
original list, including holidays that fall on a weekend or outside the
coverage.

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
that the Shoals Sydney rule lists. TARGET remains open on German public
holidays such as 3 October that the Shoals Frankfurt predicate lists. Hong Kong's published
calendar has a Monday-to-Saturday business week. Choose the calendar whose
market and observance rules match the transaction.

## Predicates

```chelis
def is_holiday(cal: Calendar, d: Date) -> bool
def is_business_day(cal: Calendar, d: Date) -> bool
```

`is_holiday` reports whether a date is in the calendar's holiday list.
`is_business_day` reports whether a date is neither a weekend nor a holiday;
it fails with a domain error for a date outside the calendar's coverage.
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

## Local lists and their gaps

The local lists and rules are kept as they are. Each has known gaps, and the
published calendar named here is the source-backed choice for settlement:

- New York: `hc_nyc_calendar()` is a 2025 US federal holiday list, so it
  closes on Columbus Day and Veterans Day and stays open on Good Friday.
  `hc_nyc_calendar_year` lists only 1 January, 4 July, and 25 December, with
  no weekend observance. Use `hc_us_federal_published()` or
  `hc_nyse_published()`.
- London: `hc_ldn_calendar()` is a 2025 list. `hc_ldn_calendar_year` lists
  1 January, Good Friday, Easter Monday, and 25 and 26 December, without the
  May and August bank holidays or substitute days. Use
  `hc_england_wales_published()`.
- Tokyo: `hc_tyo_is_holiday` lists national holidays without substitute
  holidays or bank-only closures, and its equinox dates are tabulated for
  2025–2030 only. Use `hc_japan_bank_published()`.
- Sydney: `hc_syd_is_holiday` lists an August bank holiday that is not a New
  South Wales public holiday. Use `hc_new_south_wales_published()`.
- Frankfurt: `hc_fra_is_holiday` lists the German nationwide public holidays,
  so it is neither the TARGET calendar nor a Frankfurt exchange calendar. Use
  `hc_target_published()` for euro settlement.
- Hong Kong: `hc_hkg_is_holiday` covers 2025–2030 and returns false outside
  it, has no substitute days, and models no business week. Use
  `hc_hong_kong_published()`.
