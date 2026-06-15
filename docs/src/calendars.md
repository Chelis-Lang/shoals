# Holiday calendars

Module: `Shoals.HolidayCal`.

This module represents a named calendar as a list of holiday dates, ships
the 2025 New York and London tables, combines two calendars into a joint
calendar, and reports whether a date is a holiday or a business day. Dates
come from `Std.Time`.

## The Calendar type

```chelis
type Calendar =
  | Calendar { name: string, holidays: List[Date] }

def empty_calendar(name: string) -> Calendar
def weekend_only_calendar() -> Calendar
def nyc_calendar() -> Calendar
def ldn_calendar() -> Calendar
def joint_calendar(left: Calendar, right: Calendar) -> Calendar
```

`empty_calendar` and `weekend_only_calendar` carry no holiday dates, so
under them only weekends are non-business. `nyc_calendar` and `ldn_calendar`
carry the 2025 New York and London bank holiday tables. `joint_calendar`
merges the holiday lists of two calendars, keeping the left calendar's name,
so a date that is a holiday in either is a holiday in the joint calendar.

## Predicates

```chelis
def is_holiday(cal: Calendar, d: Date) -> bool
def is_business_day(cal: Calendar, d: Date) -> bool
```

`is_holiday` reports whether a date is in the calendar's holiday list.
`is_business_day` reports whether a date is neither a weekend nor a holiday.
From `tests/holidaycal.ch`:

```chelis
cal = nyc_calendar()
ny = is_holiday(cal, date(cast(2025, int64), cast(1, int64), cast(1, int64)))   // true
wed = is_business_day(cal, date(cast(2025, int64), cast(8, int64), cast(13, int64)))  // true
```

A joint New York and London calendar treats both US Independence Day and UK
Boxing Day as holidays:

```chelis
joint = joint_calendar(nyc_calendar(), ldn_calendar())
july4 = is_holiday(joint, date(cast(2025, int64), cast(7, int64), cast(4, int64)))   // true
boxing = is_holiday(joint, date(cast(2025, int64), cast(12, int64), cast(26, int64))) // true
```
