Shoals completes its cut-over to Std.Datetime and Shoreleave (shoals#104,
stage S6 of chelis#2858). Generic date arithmetic and business-day rules now
come from `Std.Datetime` and `Std.Datetime.Business`, market calendars from
Shoreleave, and Shoals keeps only the finance layer: exact day counts,
tenors, and schedules.

Breaking: `Shoals.HolidayCal` is removed with its fixed local lists. Use the
Shoreleave calendar for the market: `hc_nyc_*` becomes
`Shoreleave.UsFederal.us_federal` for bank and settlement dates,
`Shoreleave.Nyse.nyse` for the exchange, or `Shoreleave.Sifma.sifma` for
bonds; `hc_ldn_*` becomes `Shoreleave.EnglandAndWales.england_and_wales`;
`hc_tyo_*` becomes `Shoreleave.JapanBank.japan_bank`; `hc_syd_*` becomes
`Shoreleave.NewSouthWales.new_south_wales`; `hc_hkg_*` becomes
`Shoreleave.HongKong.hong_kong`; and `hc_fra_*` becomes
`Shoreleave.Target.target` (there is no Frankfurt exchange calendar). The
`hc_*_published` wrappers are replaced by those constructors. `Calendar`,
`empty_calendar`, `weekend_only_calendar`, and `as_business_calendar` are
replaced by `Std.Datetime.Business.BusinessCalendar` and `business_calendar`;
`joint_calendar` by `business_in_all`; `is_holiday` and `is_business_day` by
`Std.Datetime.Business.is_business_day`; and the Easter helpers by
`Std.Datetime.easter_sunday_gregorian` and `Shoreleave.Rules`.

Breaking: `Shoals.Date` drops `is_weekend`, `add_months`, `days_in_month`,
`add_business_days`, the `date_roll_*` rolls and their `*_published` forms,
and `schedule_from_tenor` and `schedule_from_tenor_calendar`. Use
`Std.Datetime.date_weekday`, `date_add_months` with an explicit
`DayOverflow`, `days_in_month`, `Std.Datetime.Business.business_day_offset`
with an explicit `NonBusinessStart`, `business_day_roll`, and
`Shoals.Schedule`.

Breaking: `year_fraction` returns an exact `YearFraction` rational, converted
by `year_fraction_to_f64` or `year_fraction_to_f32` with one correct
rounding. Conventions have unambiguous names: `Act360` is `ActualOver360`,
`Act365` is `ActualOver365Fixed`, `ThirtyThreeSixty` (which computed 30E/360)
is `ThirtyEOver360`, `ActActIsda` is `ActualActualIsda`, and `ActActIcma` is
`ActualActualIcma` with required `reference_start`, `reference_end`, and
`frequency`. New conventions take their extra inputs as required fields:
`ThirtyEOver360Isda { maturity }`, `ThirtyOver360Us { end_of_month }`, and
`Business252 { calendar }`. A reversed interval, and an ICMA accrual outside
its reference period, fail with a domain error.

Breaking: `Shoals.Tenor` builds a tenor on `Std.Datetime.Period`, so a month
is a calendar month and `tenor_apply` takes a `DayOverflow`. `TenorUnit`,
`tenor`, `days_n`, `weeks_n`, `months_n`, `years_n`, `days_per_unit`,
`tenor_to_days`, and `parse_unit_suffix` are replaced by `tenor_days`,
`tenor_weeks`, `tenor_months`, `tenor_years`, and `tenor_period`. ON, TN,
and SN are business-day tenors (`overnight`, `tomorrow_next`,
`spot_next(spot_days)`, `business_day_tenor_dates`), and `parse_tenor` no
longer accepts them. `two_calendar_lag` and `lagged_date` give a spot lag
that counts in one calendar and rolls in another. The new `Shoals.Schedule`
steps from a fixed anchor with explicit stub, end-of-month, overflow,
calendar, and roll arguments.
