module Shoals.Tests.Date
import Std.Test (assert_eq, assert_true)
import Std.Datetime (Date, date)
import Shoreleave.UsFederal (us_federal)
-- `us_federal` is the US federal government calendar, used here as a calendar
-- with known closures; it is not a USD settlement calendar.
import Shoals.Date (DayCount, ActualOver360, ActualOver365Fixed, ActualActualIsda, ActualActualIcma, ThirtyEOver360, ThirtyEOver360Isda, ThirtyOver360Us, Business252, YearFraction, year_fraction, year_fraction_numerator, year_fraction_denominator, year_fraction_to_f64, year_fraction_to_f32)
import Shoals.Properties.Date (actual_matches_reference, isda_matches_reference, icma_matches_reference, whole_isda_year_is_exactly_one, additive_under_isda)
-- Every expected value is an exact rational in lowest terms. The ACT/ACT
-- values are the worked examples of ISDA's 1999 "EMU and market conventions"
-- paper on ACT/ACT; the 30/360 values follow the ISDA 2006 4.16(f)-(h)
-- definitions and agree with QuantLib 1.43's Thirty360 BondBasis, USA,
-- European and German conventions on 20000 sampled date pairs.
def ratio(start: Date, end: Date, convention: DayCount) -> (i64, i64) = {
  f = year_fraction(start, end, convention)
  (year_fraction_numerator(f), year_fraction_denominator(f))
}
def d(y: i64, m: i64, day: i64) -> Date = date(y, m, day)
def test_act_360_one_year() -> unit ! { Test } = assert_eq(ratio(d(2025i64, 1i64, 1i64), d(2026i64, 1i64, 1i64), ActualOver360), (73i64, 72i64), "ACT/360 over 365 days is 365/360")
def test_act_365_fixed_one_leap_year() -> unit ! { Test } = assert_eq(ratio(d(2024i64, 1i64, 1i64), d(2025i64, 1i64, 1i64), ActualOver365Fixed), (366i64, 365i64), "ACT/365 Fixed does not divide a leap year by 366")
def test_act_act_isda_emu_example_across_a_leap_year() -> unit ! { Test } = assert_eq(ratio(d(2003i64, 11i64, 1i64), d(2004i64, 5i64, 1i64), ActualActualIsda), (66491i64, 133590i64), "61/365 + 121/366")
def test_act_act_isda_emu_example_inside_an_ordinary_year() -> unit ! { Test } = assert_eq(ratio(d(1999i64, 2i64, 1i64), d(1999i64, 7i64, 1i64), ActualActualIsda), (30i64, 73i64), "150/365")
def test_act_act_isda_emu_example_into_a_leap_year() -> unit ! { Test } = assert_eq(ratio(d(1999i64, 7i64, 30i64), d(2000i64, 1i64, 30i64), ActualActualIsda), (13463i64, 26718i64), "155/365 + 29/366")
def test_act_act_isda_inside_a_leap_year() -> unit ! { Test } = assert_eq(ratio(d(2000i64, 1i64, 30i64), d(2000i64, 6i64, 30i64), ActualActualIsda), (76i64, 183i64), "152/366")
def test_act_act_isda_century_non_leap() -> unit ! { Test } = assert_eq(ratio(d(1899i64, 11i64, 1i64), d(1900i64, 5i64, 1i64), ActualActualIsda), (181i64, 365i64), "1900 is not a leap year: 61/365 + 120/365")
def test_act_act_isda_zero_interval_is_zero() -> unit ! { Test } = assert_eq(ratio(d(2025i64, 3i64, 1i64), d(2025i64, 3i64, 1i64), ActualActualIsda), (0i64, 1i64), "an empty accrual is 0/1")
def icma(rs: Date, re: Date, f: i64) -> DayCount = ActualActualIcma { reference_start: rs, reference_end: re, frequency: f }
def test_act_act_icma_emu_example_full_semi_annual_period() -> unit ! { Test } = assert_eq(ratio(d(2003i64, 11i64, 1i64), d(2004i64, 5i64, 1i64), icma(d(2003i64, 11i64, 1i64), d(2004i64, 5i64, 1i64), 2i64)), (1i64, 2i64), "a full regular semi-annual period is exactly 1/2")
def test_act_act_icma_emu_example_annual_period() -> unit ! { Test } = assert_eq(ratio(d(1999i64, 2i64, 1i64), d(1999i64, 7i64, 1i64), icma(d(1998i64, 7i64, 1i64), d(1999i64, 7i64, 1i64), 1i64)), (30i64, 73i64), "150 days of a 365-day annual period")
def test_act_act_icma_mid_period_accrual() -> unit ! { Test } = assert_eq(ratio(d(2004i64, 2i64, 1i64), d(2004i64, 5i64, 1i64), icma(d(2003i64, 11i64, 1i64), d(2004i64, 5i64, 1i64), 2i64)), (45i64, 182i64), "90 days over 2 x 182")
def test_act_act_icma_accrual_on_the_period_bounds_is_accepted() -> unit ! { Test } = assert_eq(ratio(d(2000i64, 1i64, 30i64), d(2000i64, 6i64, 30i64), icma(d(2000i64, 1i64, 30i64), d(2000i64, 7i64, 30i64), 2i64)), (38i64, 91i64), "152 days over 2 x 182")
def test_thirty_e_360_february_end_to_march_31() -> unit ! { Test } = assert_eq(ratio(d(2007i64, 2i64, 28i64), d(2007i64, 3i64, 31i64), ThirtyEOver360), (4i64, 45i64), "30E/360 keeps 28 February and caps 31 at 30: 32/360")
def test_thirty_e_360_isda_february_end_counts_30() -> unit ! { Test } = assert_eq(ratio(d(2007i64, 2i64, 28i64), d(2007i64, 3i64, 31i64), ThirtyEOver360Isda { maturity: d(2030i64, 1i64, 1i64) }), (1i64, 12i64), "30E/360 ISDA counts a February month-end start as 30: 30/360")
def test_thirty_e_360_isda_maturity_keeps_february_end() -> unit ! { Test } = {
  _ = assert_eq(ratio(d(2008i64, 2i64, 29i64), d(2009i64, 2i64, 28i64), ThirtyEOver360Isda { maturity: d(2009i64, 2i64, 28i64) }), (179i64, 180i64), "a February month-end maturity keeps its day: 358/360")
  assert_eq(ratio(d(2008i64, 2i64, 29i64), d(2009i64, 2i64, 28i64), ThirtyEOver360Isda { maturity: d(2030i64, 1i64, 1i64) }), (1i64, 1i64), "a February month-end that is not the maturity counts 30: 360/360")
}
def test_thirty_us_end_of_month_flag_decides_february() -> unit ! { Test } = {
  _ = assert_eq(ratio(d(2008i64, 2i64, 29i64), d(2009i64, 2i64, 28i64), ThirtyOver360Us { end_of_month: true }), (1i64, 1i64), "with the flag both February month-ends count 30")
  assert_eq(ratio(d(2008i64, 2i64, 29i64), d(2009i64, 2i64, 28i64), ThirtyOver360Us { end_of_month: false }), (359i64, 360i64), "without the flag the days stand: 359/360")
}
def test_thirty_us_31st_after_february_end() -> unit ! { Test } = {
  _ = assert_eq(ratio(d(2007i64, 2i64, 28i64), d(2007i64, 3i64, 31i64), ThirtyOver360Us { end_of_month: true }), (1i64, 12i64), "the flag makes the start 30, so the 31st counts 30")
  assert_eq(ratio(d(2007i64, 2i64, 28i64), d(2007i64, 3i64, 31i64), ThirtyOver360Us { end_of_month: false }), (11i64, 120i64), "without the flag a start of 28 leaves the 31st: 33/360")
}
def test_thirty_conventions_agree_mid_month() -> unit ! { Test } = {
  a = d(2007i64, 1i64, 15i64)
  b = d(2007i64, 1i64, 30i64)
  _ = assert_eq(ratio(a, b, ThirtyEOver360), (1i64, 24i64), "15/360")
  _ = assert_eq(ratio(a, b, ThirtyEOver360Isda { maturity: b }), (1i64, 24i64), "15/360")
  assert_eq(ratio(a, b, ThirtyOver360Us { end_of_month: true }), (1i64, 24i64), "15/360")
}
-- BUS/252 against Shoreleave's US federal calendar. QuantLib 1.43's Business252
-- over UnitedStates(FederalReserve) agrees on July 2025 (4) but counts 250 days
-- in 2025 and 5 over the year end: that calendar lacks the 2025 federal
-- closures Shoreleave lists from OPM (9 January, 24 and 26 December).
def test_bus_252_skips_a_holiday() -> unit ! { Test } = assert_eq(ratio(d(2025i64, 7i64, 1i64), d(2025i64, 7i64, 8i64), Business252 { calendar: us_federal() }), (1i64, 63i64), "July 1, 2, 3 and 7 are business days: 4/252")
def test_bus_252_one_year() -> unit ! { Test } = assert_eq(ratio(d(2025i64, 1i64, 1i64), d(2026i64, 1i64, 1i64), Business252 { calendar: us_federal() }), (247i64, 252i64), "261 weekdays less 14 weekday closures: 247/252")
def test_bus_252_across_year_end() -> unit ! { Test } = assert_eq(ratio(d(2025i64, 12i64, 24i64), d(2026i64, 1i64, 2i64), Business252 { calendar: us_federal() }), (1i64, 84i64), "December 29, 30 and 31; 24 and 26 December are federal closures: 3/252")
-- One correctly rounded conversion per float dtype.
def test_to_f64_is_the_nearest_double() -> unit ! { Test } = assert_eq(year_fraction_to_f64(year_fraction(d(2003i64, 11i64, 1i64), d(2004i64, 5i64, 1i64), ActualActualIsda)), 0.49772438056740775f64, "66491/133590 to the nearest f64")
def test_to_f32_is_the_nearest_float() -> unit ! { Test } = assert_eq(year_fraction_to_f32(year_fraction(d(2003i64, 11i64, 1i64), d(2004i64, 5i64, 1i64), ActualActualIsda)), 0.49772438f32, "66491/133590 to the nearest f32")
def test_to_f64_of_a_third() -> unit ! { Test } = assert_eq(year_fraction_to_f64(year_fraction(d(2025i64, 1i64, 1i64), d(2025i64, 5i64, 1i64), ThirtyEOver360)), 0.3333333333333333f64, "120/360 = 1/3")
-- The property surface, driven at concrete inputs.
def test_property_actual_matches_reference() -> unit ! { Test } = {
  _ = assert_true(actual_matches_reference(d(1899i64, 11i64, 1i64), d(1900i64, 5i64, 1i64)), "century non-leap")
  assert_true(actual_matches_reference(d(1950i64, 3i64, 15i64), d(2041i64, 9i64, 9i64)), "long span")
}
def test_property_isda_matches_reference() -> unit ! { Test } = {
  _ = assert_true(isda_matches_reference(d(2025i64, 12i64, 31i64), d(2026i64, 1i64, 1i64)), "one-day head stub")
  _ = assert_true(isda_matches_reference(d(1999i64, 11i64, 1i64), d(2001i64, 3i64, 1i64)), "across the quadricentennial leap year")
  assert_true(isda_matches_reference(d(1950i64, 3i64, 15i64), d(2041i64, 9i64, 9i64)), "long span")
}
def test_property_icma_matches_reference() -> unit ! { Test } = assert_true(icma_matches_reference(d(2004i64, 1i64, 15i64), d(2004i64, 3i64, 1i64), d(2003i64, 11i64, 1i64), d(2004i64, 5i64, 1i64), 2i64), "strict interior accrual")
def test_property_whole_isda_year_is_one() -> unit ! { Test } = {
  _ = assert_true(whole_isda_year_is_exactly_one(2025i64), "ordinary")
  _ = assert_true(whole_isda_year_is_exactly_one(2024i64), "leap")
  _ = assert_true(whole_isda_year_is_exactly_one(1900i64), "century non-leap")
  assert_true(whole_isda_year_is_exactly_one(2000i64), "quadricentennial")
}
def test_property_additive_under_isda() -> unit ! { Test } = assert_true(additive_under_isda(d(2003i64, 11i64, 1i64), d(2004i64, 2i64, 29i64), d(2006i64, 7i64, 4i64)), "split at a leap day")
