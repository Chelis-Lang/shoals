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
import Std.Datetime (date)
import Std.Datetime.Business (Following, business_day_roll)
import Shoreleave.UsFederal (us_federal)

rolled = business_day_roll(us_federal(), date(2025i64, 7i64, 4i64), Following)
-- Monday 2025-07-07: 4 July is a US federal holiday
```

## Which calendar to use

| Market | Shoreleave calendar | Module | Published horizon |
|---|---|---|---|
| US federal government holidays and closures | `us_federal()` | `Shoreleave.UsFederal` | 2021-2030 |
| New York Stock Exchange | `nyse()` | `Shoreleave.Nyse` | 2026-2028 |
| US bond market | `sifma()` | `Shoreleave.Sifma` | 2026-2027 |
| London | `england_and_wales()` | `Shoreleave.EnglandAndWales` | 2019-2028 |
| Tokyo | `japan_bank()` | `Shoreleave.JapanBank` | 1990-2027 |
| Sydney | `new_south_wales()` | `Shoreleave.NewSouthWales` | 2026-2027 |
| Hong Kong | `hong_kong()` | `Shoreleave.HongKong` | 2025-2027 |
| Euro settlement | `target()` | `Shoreleave.Target` | 2026-2028 |

Each calendar keeps its source's holiday data, weekmask, and finite horizon.
A business-day query outside the horizon fails with a domain error, and the
`try_` form in `Std.Datetime.Business` returns `None`; no calendar answers
for a year its data does not cover.

The calendars name their own markets. Japan Bank includes bank-only closures
such as 2 January. New South Wales public holidays do not include an August
bank holiday. Hong Kong has a Monday-to-Saturday business week. There is no
Frankfurt exchange calendar: TARGET is the euro settlement calendar and stays
open on German public holidays such as 3 October.

Shoreleave 0.1.2 has no Federal Reserve or USD settlement calendar.
`us_federal()` is the federal government's calendar: the legal holidays plus
executive-order closures of federal agencies, such as 24 and 26 December
2025, when the Federal Reserve Banks and Fedwire stayed open. `sifma()` and
`nyse()` are not substitutes either; both close on Good Friday, for example.

## Extending a calendar past its published horizon

```chelis
def us_federal_projected(until_year: i64) -> BusinessCalendar
def try_us_federal_projected(until_year: i64) -> Option[BusinessCalendar]
```

Every module has this pair, named after its calendar (`nyse_projected`,
`target_projected`, and so on). The result keeps the published holidays and
adds the dates the calendar's observance rules generate for each year after
the published horizon, through 31 December of `until_year`. The horizon
starts where the published one starts. Rules produce only the recurring
holidays: a one-off closure such as a federal executive order is never
projected.

`until_year` must end after the published horizon and must not exceed the
last year the rules are stated for: 2099 for `japan_bank`, 9998 for the
others. Outside that range `<name>_projected` fails with a domain error
naming the bound, and `try_<name>_projected` returns `None`. For example,
`try_us_federal_projected(2029i64)` returns `None` because the published
calendar already runs to 2030, and `us_federal_projected(2029i64)` fails
with:

```text
us_federal_projected: domain: until_year 2029 does not extend the published horizon, which ends in 2030; use the published calendar
```

`us_federal_projected(2035i64)` reports 4 July 2035 as a holiday.
