module Shoals.Tests.HolidaycalIntl
import Std.Test (assert_true, assert_false, assert_eq)
import Std.Datetime (date)
import Std.Datetime.Business (try_is_business_day)
import Shoals.HolidayCal (hc_tyo_is_holiday, hc_syd_is_holiday, hc_fra_is_holiday, hc_hkg_is_holiday, hc_japan_bank_published, hc_new_south_wales_published, hc_hong_kong_published, hc_target_published, hc_nyse_published)
def hc_eq_bool(a: bool, b: bool) -> bool = or(and(a, b), and(not(a), not(b)))
def test_tyo_coming_of_age_day_2026() -> unit ! { Test } = assert_true(hc_tyo_is_holiday(cast(2026, i64), cast(1, i64), cast(12, i64)), "TYO: 2026-01-12 is Coming-of-Age Day (2nd Mon of Jan)")
def test_japan_bank_includes_bank_closure_outside_tyo_list() -> unit ! { Test } = {
  _ = assert_false(hc_tyo_is_holiday(2026i64, 1i64, 2i64), "TYO national-holiday list omits the bank-only January 2 closure")
  assert_eq(try_is_business_day(hc_japan_bank_published(), date(2026i64, 1i64, 2i64)), Some(false), "Japan Bank closes January 2")
}
def test_nsw_august_bank_holiday_is_not_a_public_holiday() -> unit ! { Test } = {
  _ = assert_true(hc_syd_is_holiday(2026i64, 8i64, 3i64), "Shoals Sydney rule lists the August bank holiday")
  assert_eq(try_is_business_day(hc_new_south_wales_published(), date(2026i64, 8i64, 3i64)), Some(true), "NSW public-holiday calendar stays open")
}
def test_target_does_not_use_frankfurt_regional_holidays() -> unit ! { Test } = {
  _ = assert_true(hc_fra_is_holiday(2028i64, 10i64, 3i64), "Frankfurt list observes German Unity Day")
  assert_eq(try_is_business_day(hc_target_published(), date(2028i64, 10i64, 3i64)), Some(true), "TARGET stays open on German Unity Day")
}
def test_hong_kong_and_nyse_published_business_week() -> unit ! { Test } = {
  _ = assert_eq(try_is_business_day(hc_hong_kong_published(), date(2026i64, 1i64, 3i64)), Some(true), "Hong Kong has a Monday-to-Saturday business week")
  assert_eq(try_is_business_day(hc_nyse_published(), date(2026i64, 1i64, 3i64)), Some(false), "NYSE closes on Saturday")
}
def test_syd_australia_day_2025() -> unit ! { Test } = assert_true(hc_syd_is_holiday(cast(2025, i64), cast(1, i64), cast(27, i64)), "SYD: 2025-01-27 is observed Australia Day (Jan 26 is Sunday)")
def test_fra_tag_der_deutschen_einheit_2025() -> unit ! { Test } = assert_true(hc_fra_is_holiday(cast(2025, i64), cast(10, i64), cast(3, i64)), "FRA: 2025-10-03 is German Unity Day")
def test_hkg_lunar_new_year_2025() -> unit ! { Test } = assert_true(hc_hkg_is_holiday(cast(2025, i64), cast(1, i64), cast(29, i64)), "HKG: 2025-01-29 is Lunar New Year (first day)")
def test_calendars_disagree_on_christmas_eve_dec_24() -> unit ! { Test } = {
  tyo_24 = hc_tyo_is_holiday(cast(2025, i64), cast(12, i64), cast(24, i64))
  tyo_25 = hc_tyo_is_holiday(cast(2025, i64), cast(12, i64), cast(25, i64))
  syd_25 = hc_syd_is_holiday(cast(2025, i64), cast(12, i64), cast(25, i64))
  fra_25 = hc_fra_is_holiday(cast(2025, i64), cast(12, i64), cast(25, i64))
  disagree_tyo_vs_syd = not(hc_eq_bool(tyo_25, syd_25))
  disagree_tyo_vs_fra = not(hc_eq_bool(tyo_25, fra_25))
  _ = assert_false(tyo_24, "TYO does not observe Dec 24")
  _ = assert_false(tyo_25, "TYO does not observe Dec 25 (no Christmas in Japan public holidays)")
  _ = assert_true(syd_25, "SYD observes Dec 25 (Christmas)")
  _ = assert_true(fra_25, "FRA observes Dec 25 (Christmas)")
  _ = assert_true(disagree_tyo_vs_syd, "TYO and SYD disagree on 2025-12-25")
  assert_true(disagree_tyo_vs_fra, "TYO and FRA disagree on 2025-12-25")
}
