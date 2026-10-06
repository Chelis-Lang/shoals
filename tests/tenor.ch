module Shoals.Tests.Tenor
import Std.Test (assert_eq, assert_true)
import Std.Datetime (Date, date, period, ClampToMonthEnd, RejectInvalidDay)
import Std.Datetime.Business (Following, ModifiedFollowing, RejectNonBusinessStart, RollStartForward)
import Shoreleave.UsFederal (us_federal)
import Shoreleave.JapanBank (japan_bank)
import Shoals.Tenor (Tenor, tenor_days, tenor_weeks, tenor_months, tenor_years, tenor_period, tenor_apply, parse_tenor, try_parse_tenor, overnight, tomorrow_next, spot_next, business_day_tenor_dates, two_calendar_lag, lagged_date)
def d(y: i64, m: i64, day: i64) -> Date = date(y, m, day)
-- A month is a calendar month, not 30 days, and a year is twelve months.
def test_months_are_calendar_months() -> unit ! { Test } = {
  _ = assert_eq(tenor_apply(tenor_months(3i64), d(2025i64, 6i64, 15i64), RejectInvalidDay), d(2025i64, 9i64, 15i64), "3M from 15 June is 15 September (92 days, not 90)")
  assert_eq(tenor_apply(tenor_years(1i64), d(2024i64, 3i64, 1i64), RejectInvalidDay), d(2025i64, 3i64, 1i64), "1Y from 1 March 2024 is 365 days, not a fixed count")
}
def test_month_end_needs_the_overflow_policy() -> unit ! { Test } = assert_eq(tenor_apply(tenor_months(1i64), d(2025i64, 1i64, 31i64), ClampToMonthEnd), d(2025i64, 2i64, 28i64), "ClampToMonthEnd moves 31 January + 1M to 28 February")
def test_leap_day_plus_one_year() -> unit ! { Test } = assert_eq(tenor_apply(tenor_years(1i64), d(2024i64, 2i64, 29i64), ClampToMonthEnd), d(2025i64, 2i64, 28i64), "29 February + 1Y clamps to 28 February")
def test_days_and_weeks_are_days() -> unit ! { Test } = {
  _ = assert_eq(tenor_period(tenor_weeks(2i64)), period(0i64, 14i64), "2W is 14 days")
  assert_eq(tenor_apply(tenor_days(7i64), d(2025i64, 12i64, 28i64), RejectInvalidDay), d(2026i64, 1i64, 4i64), "7D crosses the year")
}
def test_parse_tenor_units() -> unit ! { Test } = {
  _ = assert_eq(tenor_period(parse_tenor("3M")), period(3i64, 0i64), "3M")
  _ = assert_eq(tenor_period(parse_tenor("30Y")), period(360i64, 0i64), "30Y is 360 months")
  _ = assert_eq(tenor_period(parse_tenor("2W")), period(0i64, 14i64), "2W")
  assert_eq(tenor_period(parse_tenor("7D")), period(0i64, 7i64), "7D")
}
def is_none(x: Option[Tenor]) -> bool =
  match x with {
    | None => true
    | Some(_) => false
  }
def test_try_parse_tenor_rejects_lax_spellings() -> unit ! { Test } = {
  _ = assert_true(is_none(try_parse_tenor("+3M")), "a sign is not a digit")
  _ = assert_true(is_none(try_parse_tenor(" 3M")), "a space is not a digit")
  _ = assert_true(is_none(try_parse_tenor("-3M")), "a negative count is not a tenor")
  _ = assert_true(is_none(try_parse_tenor("0M")), "a zero count is not a tenor")
  _ = assert_true(is_none(try_parse_tenor("ON")), "ON is a business-day tenor, not a period")
  assert_true(is_none(try_parse_tenor("3X")), "X is not a unit")
}
-- ON, TN and SN in US federal business days from Thursday 3 July 2025; the
-- 4 July holiday and the weekend lie inside them.
def test_overnight_spans_the_holiday_weekend() -> unit ! { Test } = assert_eq(business_day_tenor_dates(overnight(), d(2025i64, 7i64, 3i64), us_federal(), RejectNonBusinessStart), (d(2025i64, 7i64, 3i64), d(2025i64, 7i64, 7i64)), "ON runs from 3 to 7 July")
def test_tomorrow_next_starts_one_business_day_later() -> unit ! { Test } = assert_eq(business_day_tenor_dates(tomorrow_next(), d(2025i64, 7i64, 3i64), us_federal(), RejectNonBusinessStart), (d(2025i64, 7i64, 7i64), d(2025i64, 7i64, 8i64)), "TN runs from 7 to 8 July")
def test_spot_next_starts_at_spot() -> unit ! { Test } = assert_eq(business_day_tenor_dates(spot_next(2i64), d(2025i64, 7i64, 3i64), us_federal(), RejectNonBusinessStart), (d(2025i64, 7i64, 8i64), d(2025i64, 7i64, 9i64)), "SN at T+2 runs from 8 to 9 July")
def test_business_day_tenor_from_a_holiday_rolls_forward() -> unit ! { Test } = assert_eq(business_day_tenor_dates(overnight(), d(2025i64, 7i64, 4i64), us_federal(), RollStartForward), (d(2025i64, 7i64, 7i64), d(2025i64, 7i64, 8i64)), "ON traded on the 4 July holiday starts on 7 July")
-- Two-calendar spot: count two Japanese bank days, then roll in US federal.
-- From Wednesday 2 July 2025 the count lands on 4 July, a US holiday, so the
-- roll moves it to 7 July. From Tuesday 30 December the Japanese closures
-- (31 December to 3 January) push the count to 6 January, where counting in
-- US federal days would give 2 January.
def test_spot_counts_in_one_calendar_and_rolls_in_another() -> unit ! { Test } = {
  lag = two_calendar_lag(2i64, japan_bank(), us_federal(), Following)
  _ = assert_eq(lagged_date(lag, d(2025i64, 7i64, 2i64)), d(2025i64, 7i64, 7i64), "Japanese count reaches 4 July; the US roll moves it to 7 July")
  _ = assert_eq(lagged_date(lag, d(2025i64, 12i64, 30i64)), d(2026i64, 1i64, 6i64), "Japanese year-end closures move the count to 6 January")
  assert_eq(lagged_date(two_calendar_lag(2i64, us_federal(), us_federal(), Following), d(2025i64, 12i64, 30i64)), d(2026i64, 1i64, 2i64), "a US count from 30 December reaches 2 January")
}
def test_spot_from_a_weekend_counts_the_next_business_day_first() -> unit ! { Test } = assert_eq(lagged_date(two_calendar_lag(2i64, us_federal(), us_federal(), ModifiedFollowing), d(2025i64, 7i64, 5i64)), d(2025i64, 7i64, 8i64), "from Saturday 5 July, T+1 is Monday 7 and T+2 Tuesday 8")
