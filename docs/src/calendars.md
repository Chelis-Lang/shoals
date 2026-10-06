# Holiday calendars

Shoals has no holiday-calendar module of its own. A business calendar is a
`Std.Datetime.Business.BusinessCalendar`, and the market calendars come from
the Shoreleave package. A Shoals function that needs a calendar, such as the
`Business252` day count, a business-day tenor, a spot lag, or an adjusted
schedule, takes a `BusinessCalendar` argument; pass the Shoreleave calendar
whose market and observance rules match the transaction.

Chelis does not re-export an imported name, so import the calendar from its
Shoreleave module directly:

```chelis
import Std.Datetime.Business (Following, business_day_roll)
import Shoreleave.UsFederal (us_federal)

rolled = business_day_roll(us_federal(), date(2025i64, 7i64, 4i64), Following)
// Monday 2025-07-07: 4 July is a US federal holiday
```

## Which calendar to use

| Market | Shoreleave calendar | Module | Published horizon |
|---|---|---|---|
| New York bank and settlement | `us_federal()` | `Shoreleave.UsFederal` | 2021–2030 |
| New York Stock Exchange | `nyse()` | `Shoreleave.Nyse` | 2026–2028 |
| US bond market | `sifma()` | `Shoreleave.Sifma` | 2026–2027 |
| London | `england_and_wales()` | `Shoreleave.EnglandAndWales` | 2019–2028 |
| Tokyo | `japan_bank()` | `Shoreleave.JapanBank` | 1990–2027 |
| Sydney | `new_south_wales()` | `Shoreleave.NewSouthWales` | 2026–2027 |
| Hong Kong | `hong_kong()` | `Shoreleave.HongKong` | 2025–2027 |
| Euro settlement | `target()` | `Shoreleave.Target` | 2026–2028 |

Each calendar keeps its source's holiday data, weekmask, and finite horizon.
A business-day query outside the horizon fails with a domain error, and the
`try_` form in `Std.Datetime.Business` returns `None`; no calendar answers
for a year its data does not cover. Each module also has
`<name>_projected(until_year)`, which extends the published dates with the
calendar's rules through `until_year`, and `try_<name>_projected`.

The calendars name their own markets. Japan Bank includes bank-only closures
such as 2 January. New South Wales public holidays do not include an August
bank holiday. Hong Kong has a Monday-to-Saturday business week. There is no
Frankfurt exchange calendar: TARGET is the euro settlement calendar and stays
open on German public holidays such as 3 October.

## Replacing the removed `Shoals.HolidayCal`

`Shoals.HolidayCal` held fixed local holiday lists and rules with known gaps,
for example a New York list that closed on Columbus Day and stayed open on
Good Friday, and a London rule without the May and August bank holidays. It
is removed, and each old calendar maps to a Shoreleave calendar:

| Removed | Replacement |
|---|---|
| `hc_nyc_calendar`, `hc_nyc_calendar_year`, `hc_nyc_calendar_multi` | `us_federal()` for bank and settlement dates, `nyse()` for the exchange, `sifma()` for bonds |
| `hc_ldn_calendar`, `hc_ldn_calendar_year`, `hc_ldn_calendar_multi` | `england_and_wales()` |
| `hc_tyo_is_holiday`, `hc_tyo_holidays_year` | `japan_bank()` |
| `hc_syd_is_holiday`, `hc_syd_holidays_year` | `new_south_wales()` |
| `hc_hkg_is_holiday`, `hc_hkg_holidays_year` | `hong_kong()` |
| `hc_fra_is_holiday`, `hc_fra_holidays_year` | `target()`; there is no Frankfurt exchange calendar |
| the `hc_*_published()` wrappers | the Shoreleave constructor itself |
| `Calendar`, `empty_calendar`, `weekend_only_calendar`, `as_business_calendar` | a Shoreleave calendar, or `Std.Datetime.Business.business_calendar(weekmask, holidays, valid_from, valid_until)` for the caller's own data and horizon |
| `joint_calendar` | `Std.Datetime.Business.business_in_all` (a business day in both) |
| `is_holiday`, `is_business_day` | `Std.Datetime.Business.is_business_day` and `try_is_business_day` |
| `easter_sunday_gregorian`, `good_friday`, `easter_monday` | `Std.Datetime.easter_sunday_gregorian`; `Shoreleave.Rules.good_friday` and `easter_monday` |

`Shoals.Date` also lost its weekend predicate and business-day rolls; see
[Dates and day counts](dates.md#removed-date-helpers).
