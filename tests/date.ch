module Shoals.Tests.Date
import Std.Test (assert_close)
import Std.Datetime (Date, date, date_days_until, date_lte)
import Shoals.Date (DayCount, Act360, Act365, ThirtyThreeSixty, ActActIsda, ActActIcma, year_fraction)
import Shoals.Properties.Date (year_fraction_matches_textbook, whole_isda_year_is_exactly_one, isda_reverses_under_swap)
def to01(b: bool) -> f32 = if b then cast(1.0, f32) else cast(0.0, f32)
def to01_f64(b: bool) -> f64 = if b then cast(1.0, f64) else cast(0.0, f64)
def tight64() -> f64 = cast(1e-12, f64)
def same_date(actual: Date, expected: Date) -> f32 = cast(date_days_until(actual, expected), f32)
def test_act_360_one_year() -> unit ! { Test } = {
  start = date(cast(2025, i64), cast(1, i64), cast(1, i64))
  end = date(cast(2026, i64), cast(1, i64), cast(1, i64))
  yf = year_fraction(start, end, Act360)
  expected = div(cast(365.0, f64), cast(360.0, f64))
  assert_close(yf, expected, cast(0.0001, f64), "Act/360 one year == 365/360")
}
def test_act_365_one_year() -> unit ! { Test } = {
  start = date(cast(2025, i64), cast(1, i64), cast(1, i64))
  end = date(cast(2026, i64), cast(1, i64), cast(1, i64))
  yf = year_fraction(start, end, Act365)
  assert_close(yf, cast(1.0, f64), cast(1e-9, f64), "Act/365 one year == 1.0")
}
def test_thirty_360_half_year() -> unit ! { Test } = {
  start = date(cast(2025, i64), cast(1, i64), cast(15, i64))
  end = date(cast(2025, i64), cast(7, i64), cast(15, i64))
  yf = year_fraction(start, end, ThirtyThreeSixty)
  assert_close(yf, cast(0.5, f64), cast(1e-9, f64), "30/360 six months == 0.5")
}
-- The ISDA 2006 worked example: 2003-11-01 to 2004-05-01 is 61 days of a
-- 365-day year plus 121 days of a 366-day year, so 61/365 + 121/366.
def test_act_act_isda_worked_example() -> unit ! { Test } = {
  start = date(cast(2003, i64), cast(11, i64), cast(1, i64))
  end = date(cast(2004, i64), cast(5, i64), cast(1, i64))
  yf = year_fraction(start, end, ActActIsda)
  expected = add(div(cast(61.0, f64), cast(365.0, f64)), div(cast(121.0, f64), cast(366.0, f64)))
  assert_close(yf, expected, tight64(), "ACT/ACT ISDA 2003-11-01..2004-05-01 == 61/365 + 121/366")
}
-- The regression test for the defect itself: the replaced implementation was
-- days/365.25, which on this interval gives 182/365.25 = 0.49829. ISDA gives
-- 0.49772. Asserting only the ISDA value would also pass if someone reinstated
-- a slightly different approximation, so assert the distance from the old one.
def test_act_act_isda_is_not_the_365_25_approximation() -> unit ! { Test } = {
  start = date(cast(2003, i64), cast(11, i64), cast(1, i64))
  end = date(cast(2004, i64), cast(5, i64), cast(1, i64))
  yf = year_fraction(start, end, ActActIsda)
  approximation = div(cast(182.0, f64), cast(365.25, f64))
  gap = if lt(yf, approximation) then sub(approximation, yf) else sub(yf, approximation)
  assert_close(to01_f64(gt(gap, cast(0.0001, f64))), cast(1.0, f64), tight64(), "ACT/ACT ISDA differs measurably from the days/365.25 approximation it replaced")
}
-- Red-team F2/X4. A calendar-year segment of exactly ONE day is the boundary of
-- the per-year split, and the suite's shortest interval was two days inside a
-- single year, so a mutation widening the "skip empty segment" guard from
-- `span < 1` to `span < 2` silently returned 0.0 here and nothing caught it.
def test_act_act_isda_one_day_segment_at_a_year_boundary() -> unit ! { Test } = {
  start = date(cast(2024, i64), cast(12, i64), cast(31, i64))
  end = date(cast(2025, i64), cast(1, i64), cast(1, i64))
  expected = div(cast(1.0, f64), cast(366.0, f64))
  assert_close(year_fraction(start, end, ActActIsda), expected, tight64(), "2024-12-31..2025-01-01 is one leap-year day == 1/366")
}
def test_act_act_isda_one_day_segment_each_side_of_a_boundary() -> unit ! { Test } = {
  start = date(cast(2023, i64), cast(12, i64), cast(31, i64))
  end = date(cast(2024, i64), cast(1, i64), cast(2, i64))
  expected = add(div(cast(1.0, f64), cast(365.0, f64)), div(cast(1.0, f64), cast(366.0, f64)))
  assert_close(year_fraction(start, end, ActActIsda), expected, tight64(), "2023-12-31..2024-01-02 is 1/365 + 1/366, one day in each year")
}
def test_act_act_isda_whole_non_leap_year_is_one() -> unit ! { Test } = {
  start = date(cast(2025, i64), cast(1, i64), cast(1, i64))
  end = date(cast(2026, i64), cast(1, i64), cast(1, i64))
  assert_close(year_fraction(start, end, ActActIsda), cast(1.0, f64), tight64(), "ACT/ACT ISDA over 2025 == exactly 1.0")
}
-- The leap year is where days/365.25 was visibly wrong: 366/365.25 = 1.00205.
def test_act_act_isda_whole_leap_year_is_one() -> unit ! { Test } = {
  start = date(cast(2024, i64), cast(1, i64), cast(1, i64))
  end = date(cast(2025, i64), cast(1, i64), cast(1, i64))
  assert_close(year_fraction(start, end, ActActIsda), cast(1.0, f64), tight64(), "ACT/ACT ISDA over leap year 2024 == exactly 1.0, not 366/365.25")
}
def test_act_act_isda_five_years_spanning_a_leap() -> unit ! { Test } = {
  start = date(cast(2020, i64), cast(1, i64), cast(1, i64))
  end = date(cast(2025, i64), cast(1, i64), cast(1, i64))
  assert_close(year_fraction(start, end, ActActIsda), cast(5.0, f64), tight64(), "ACT/ACT ISDA over 2020..2025 == exactly 5.0")
}
def test_act_act_isda_weights_the_leap_day_by_366() -> unit ! { Test } = {
  start = date(cast(2024, i64), cast(2, i64), cast(28, i64))
  end = date(cast(2024, i64), cast(3, i64), cast(1, i64))
  expected = div(cast(2.0, f64), cast(366.0, f64))
  assert_close(year_fraction(start, end, ActActIsda), expected, tight64(), "Feb-28..Mar-01 in 2024 is 2 days weighted 1/366")
}
def test_act_act_isda_reversed_interval_negates() -> unit ! { Test } = {
  start = date(cast(2003, i64), cast(11, i64), cast(1, i64))
  end = date(cast(2004, i64), cast(5, i64), cast(1, i64))
  forward = year_fraction(start, end, ActActIsda)
  backward = year_fraction(end, start, ActActIsda)
  assert_close(add(forward, backward), cast(0.0, f64), tight64(), "ACT/ACT ISDA reversed interval is the negation")
}
def test_act_act_isda_zero_interval_is_zero() -> unit ! { Test } = {
  d = date(cast(2024, i64), cast(2, i64), cast(29, i64))
  assert_close(year_fraction(d, d, ActActIsda), cast(0.0, f64), tight64(), "ACT/ACT ISDA of an empty interval is 0")
}
-- ACT/ACT ICMA: a regular full coupon period is exactly 1/frequency whatever its
-- actual day count, which is the property that distinguishes it from ISDA.
def test_act_act_icma_full_semi_annual_period_is_half() -> unit ! { Test } = {
  period_start = date(cast(2003, i64), cast(11, i64), cast(1, i64))
  period_end = date(cast(2004, i64), cast(5, i64), cast(1, i64))
  convention = ActActIcma { period_start, period_end, frequency: cast(2, i64) }
  assert_close(year_fraction(period_start, period_end, convention), cast(0.5, f64), tight64(), "a full semi-annual ICMA period is exactly 0.5")
}
def test_act_act_icma_full_annual_period_is_one() -> unit ! { Test } = {
  period_start = date(cast(2024, i64), cast(3, i64), cast(15, i64))
  period_end = date(cast(2025, i64), cast(3, i64), cast(15, i64))
  convention = ActActIcma { period_start, period_end, frequency: cast(1, i64) }
  assert_close(year_fraction(period_start, period_end, convention), cast(1.0, f64), tight64(), "a full annual ICMA period is exactly 1.0")
}
def test_act_act_icma_short_first_period() -> unit ! { Test } = {
  period_start = date(cast(2003, i64), cast(11, i64), cast(1, i64))
  period_end = date(cast(2004, i64), cast(5, i64), cast(1, i64))
  convention = ActActIcma { period_start, period_end, frequency: cast(2, i64) }
  settle = date(cast(2004, i64), cast(2, i64), cast(1, i64))
  expected = div(cast(92.0, f64), mul(cast(2.0, f64), cast(182.0, f64)))
  assert_close(year_fraction(period_start, settle, convention), expected, tight64(), "92 of 182 days at semi-annual frequency == 92/364")
}
-- ISDA and ICMA must not agree on this interval, or the ICMA leg could be
-- satisfied by an implementation that silently routed to ISDA.
def test_act_act_icma_differs_from_isda_on_the_same_interval() -> unit ! { Test } = {
  period_start = date(cast(2003, i64), cast(11, i64), cast(1, i64))
  period_end = date(cast(2004, i64), cast(5, i64), cast(1, i64))
  convention = ActActIcma { period_start, period_end, frequency: cast(2, i64) }
  icma = year_fraction(period_start, period_end, convention)
  isda = year_fraction(period_start, period_end, ActActIsda)
  gap = if lt(icma, isda) then sub(isda, icma) else sub(icma, isda)
  assert_close(to01_f64(gt(gap, cast(0.0001, f64))), cast(1.0, f64), tight64(), "ICMA and ISDA disagree on 2003-11-01..2004-05-01")
}
-- Red-team round 2, F7. THE CROSS-CHECK HAD NO REACH. Before this matrix,
-- `year_fraction_matches_textbook` ran at exactly two hand-picked multi-year
-- six-month spans, so the independent reference never reached the same-year
-- branch at all, and every same-year ISDA assertion in this file sat in a LEAP
-- year. Forcing the same-year denominator to 366 therefore passed all 53 tests
-- while returning 181/366 instead of 181/365 for an ordinary-year accrual --
-- the single commonest ACT/ACT ISDA input there is.
--
-- The lesson is about the probe, not the line: a two-valued function mutated in
-- ONE direction only tests the value that happens to be covered. The earlier
-- probe forced that denominator to 365, which the leap-year test catches, so it
-- read as coverage.
--
-- So this is a matrix over {same-year, multi-year} x {ordinary, leap, century
-- non-leap, quadricentennial} x {1 day, degenerate stub, whole year, long span},
-- driven through the independent reference rather than against hand-computed
-- decimals. Adding one more hand-picked case would have closed the instance and
-- left the class open.
def isda_agrees(ys: i64, ms: i64, ds: i64, ye: i64, me: i64, de: i64) -> bool = year_fraction_matches_textbook(date(ys, ms, ds), date(ye, me, de), ActActIsda)
def all_true(xs: List[bool]) -> bool = fold(fn (acc: bool, x: bool) -> and(acc, x), true, xs)
def matrix_holds(xs: List[bool], label: string) -> unit ! { Test } = assert_close(to01_f64(all_true(xs)), cast(1.0, f64), tight64(), label)
def test_isda_matrix_same_year_ordinary() -> unit ! { Test } = matrix_holds([isda_agrees(cast(2025, i64), cast(1, i64), cast(1, i64), cast(2025, i64), cast(7, i64), cast(1, i64)), isda_agrees(cast(2025, i64), cast(3, i64), cast(1, i64), cast(2025, i64), cast(3, i64), cast(2, i64)), isda_agrees(cast(2025, i64), cast(1, i64), cast(1, i64), cast(2025, i64), cast(12, i64), cast(31, i64))], "same-year branch, ordinary year: part-year, one day, almost-whole-year")
def test_isda_matrix_same_year_leap() -> unit ! { Test } = matrix_holds([isda_agrees(cast(2024, i64), cast(1, i64), cast(1, i64), cast(2024, i64), cast(7, i64), cast(1, i64)), isda_agrees(cast(2024, i64), cast(2, i64), cast(28, i64), cast(2024, i64), cast(2, i64), cast(29, i64)), isda_agrees(cast(2024, i64), cast(2, i64), cast(29, i64), cast(2024, i64), cast(3, i64), cast(1, i64))], "same-year branch, leap year: part-year, the leap day itself, the day after")
def test_isda_matrix_same_year_century_non_leap() -> unit ! { Test } = matrix_holds([isda_agrees(cast(1900, i64), cast(1, i64), cast(1, i64), cast(1900, i64), cast(7, i64), cast(1, i64)), isda_agrees(cast(1900, i64), cast(2, i64), cast(28, i64), cast(1900, i64), cast(3, i64), cast(1, i64))], "same-year branch, 1900 century non-leap: part-year and the Feb/Mar boundary")
def test_isda_matrix_same_year_quadricentennial() -> unit ! { Test } = matrix_holds([isda_agrees(cast(2000, i64), cast(1, i64), cast(1, i64), cast(2000, i64), cast(7, i64), cast(1, i64)), isda_agrees(cast(2000, i64), cast(2, i64), cast(28, i64), cast(2000, i64), cast(2, i64), cast(29, i64))], "same-year branch, 2000 quadricentennial leap: part-year and the leap day")
def test_isda_matrix_adjacent_years() -> unit ! { Test } = matrix_holds([isda_agrees(cast(2025, i64), cast(12, i64), cast(31, i64), cast(2026, i64), cast(1, i64), cast(1, i64)), isda_agrees(cast(2023, i64), cast(12, i64), cast(31, i64), cast(2024, i64), cast(1, i64), cast(2, i64)), isda_agrees(cast(2024, i64), cast(12, i64), cast(31, i64), cast(2025, i64), cast(1, i64), cast(1, i64))], "multi-year branch with interior == 0, in all three leap orderings")
def test_isda_matrix_degenerate_stubs() -> unit ! { Test } = matrix_holds([isda_agrees(cast(2024, i64), cast(1, i64), cast(1, i64), cast(2025, i64), cast(6, i64), cast(15, i64)), isda_agrees(cast(2023, i64), cast(6, i64), cast(15, i64), cast(2025, i64), cast(1, i64), cast(1, i64)), isda_agrees(cast(2020, i64), cast(1, i64), cast(1, i64), cast(2025, i64), cast(1, i64), cast(1, i64))], "multi-year branch: zero head stub, zero tail stub, both stubs zero")
def test_isda_matrix_across_century_boundaries() -> unit ! { Test } = matrix_holds([isda_agrees(cast(1899, i64), cast(11, i64), cast(1, i64), cast(1900, i64), cast(5, i64), cast(1, i64)), isda_agrees(cast(1999, i64), cast(11, i64), cast(1, i64), cast(2000, i64), cast(5, i64), cast(1, i64)), isda_agrees(cast(2099, i64), cast(11, i64), cast(1, i64), cast(2100, i64), cast(5, i64), cast(1, i64))], "multi-year branch across 1900, 2000 and 2100 year boundaries")
def test_isda_matrix_long_span_and_reversed() -> unit ! { Test } = matrix_holds([isda_agrees(cast(1950, i64), cast(3, i64), cast(15, i64), cast(2050, i64), cast(9, i64), cast(20, i64)), isda_agrees(cast(2025, i64), cast(7, i64), cast(1, i64), cast(2025, i64), cast(1, i64), cast(1, i64)), isda_agrees(cast(2004, i64), cast(5, i64), cast(1, i64), cast(2003, i64), cast(11, i64), cast(1, i64))], "multi-year 100-year span, plus reversed intervals on both branches")
-- The exact value for the case F7 named, stated as a decimal rather than routed
-- through the reference, so the matrix and this assertion fail independently.
def test_act_act_isda_same_year_ordinary_exact() -> unit ! { Test } = {
  start = date(cast(2025, i64), cast(1, i64), cast(1, i64))
  end = date(cast(2025, i64), cast(7, i64), cast(1, i64))
  expected = div(cast(181.0, f64), cast(365.0, f64))
  assert_close(year_fraction(start, end, ActActIsda), expected, tight64(), "2025-01-01..2025-07-01 is 181 days of an ordinary year == 181/365, not 181/366")
}
-- Red-team round 3, F10. THE SAME CLASS AS F7, IN THE LEG THE F7 MATRIX DID NOT
-- COVER. ICMA's accrual range has two independently varying endpoints, and every
-- ICMA assertion in this file passed `period_start` as the accrual start. So
-- replacing `date_days_until(start, end)` with `date_days_until(period_start, end)` --
-- ignoring the caller's accrual start entirely -- passed all 62 tests. The END
-- axis was pinned, because one test varies it; the START axis was constant
-- everywhere, including inside the independent-reference property, whose driver
-- also passed `period_start`, so both sides moved together.
--
-- A mid-period accrual is the input that separates them, and it is ordinary
-- accrued interest between two settlement dates inside a coupon period:
-- 2004-02-01..2004-05-01 against the 2003-11-01..2004-05-01 period is 90/364,
-- where the mutant gives 182/364 -- a factor of two.
--
-- So the accrual start and end now vary independently of the period bounds:
-- whole period, prefix, suffix, strict interior, zero-length interior and
-- reversed interior, across three frequencies.
def coupon_start() -> Date = date(cast(2003, i64), cast(11, i64), cast(1, i64))
def coupon_end() -> Date = date(cast(2004, i64), cast(5, i64), cast(1, i64))
def coupon_conv(freq: i64) -> DayCount = ActActIcma { period_start: coupon_start(), period_end: coupon_end(), frequency: freq }
def coupon_agrees(sy: i64, sm: i64, sd: i64, ey: i64, em: i64, ed: i64, freq: i64) -> bool = year_fraction_matches_textbook(date(sy, sm, sd), date(ey, em, ed), coupon_conv(freq))
def test_icma_matrix_accrual_start_varies() -> unit ! { Test } = matrix_holds([coupon_agrees(cast(2003, i64), cast(11, i64), cast(1, i64), cast(2004, i64), cast(5, i64), cast(1, i64), cast(2, i64)), coupon_agrees(cast(2003, i64), cast(11, i64), cast(1, i64), cast(2004, i64), cast(2, i64), cast(1, i64), cast(2, i64)), coupon_agrees(cast(2004, i64), cast(2, i64), cast(1, i64), cast(2004, i64), cast(5, i64), cast(1, i64), cast(2, i64)), coupon_agrees(cast(2003, i64), cast(12, i64), cast(1, i64), cast(2004, i64), cast(3, i64), cast(1, i64), cast(2, i64))], "ICMA accrual: whole period, prefix, SUFFIX (start varies), strict interior")
def test_icma_matrix_degenerate_and_reversed_accrual() -> unit ! { Test } = matrix_holds([coupon_agrees(cast(2004, i64), cast(2, i64), cast(1, i64), cast(2004, i64), cast(2, i64), cast(1, i64), cast(2, i64)), coupon_agrees(cast(2004, i64), cast(3, i64), cast(1, i64), cast(2003, i64), cast(12, i64), cast(1, i64), cast(2, i64))], "ICMA accrual: zero-length interior, and reversed interior")
def test_icma_matrix_frequency_varies() -> unit ! { Test } = matrix_holds([coupon_agrees(cast(2003, i64), cast(11, i64), cast(1, i64), cast(2004, i64), cast(5, i64), cast(1, i64), cast(1, i64)), coupon_agrees(cast(2004, i64), cast(2, i64), cast(1, i64), cast(2004, i64), cast(5, i64), cast(1, i64), cast(1, i64)), coupon_agrees(cast(2004, i64), cast(2, i64), cast(1, i64), cast(2004, i64), cast(5, i64), cast(1, i64), cast(4, i64))], "ICMA frequency 1 and 4, with the accrual start both at and inside the period start")
-- Exact decimals for the two cases that separate the start axis, stated here
-- rather than routed through the reference so this and the matrix fail
-- independently. 2004 is a leap year: Feb 1 -> May 1 is 29+31+30 = 90 days.
def test_act_act_icma_mid_period_accrual_exact() -> unit ! { Test } = {
  settle = date(cast(2004, i64), cast(2, i64), cast(1, i64))
  expected = div(cast(90.0, f64), mul(cast(2.0, f64), cast(182.0, f64)))
  assert_close(year_fraction(settle, coupon_end(), coupon_conv(cast(2, i64))), expected, tight64(), "accrual 2004-02-01..2004-05-01 inside a 182-day period is 90/364, not 182/364")
}
def test_act_act_icma_strict_interior_accrual_exact() -> unit ! { Test } = {
  from = date(cast(2003, i64), cast(12, i64), cast(1, i64))
  to = date(cast(2004, i64), cast(3, i64), cast(1, i64))
  expected = div(cast(91.0, f64), mul(cast(2.0, f64), cast(182.0, f64)))
  assert_close(year_fraction(from, to, coupon_conv(cast(2, i64))), expected, tight64(), "a strictly interior 91-day accrual is 91/364 == 0.25 exactly")
}
-- F16: every ICMA case lay inside or on its coupon period, so the documented
-- no-validation contract drove nothing -- an implementation that clamped the
-- accrual to the period, or trapped on an out-of-period accrual, passed. This
-- pins that an accrual extending past the period end returns the un-clamped
-- value: 2003-11-01..2004-11-01 is 366 days against a 182-day period.
def test_act_act_icma_accrual_past_the_period_end_is_not_clamped() -> unit ! { Test } = {
  far = date(cast(2004, i64), cast(11, i64), cast(1, i64))
  expected = div(cast(366.0, f64), mul(cast(2.0, f64), cast(182.0, f64)))
  assert_close(year_fraction(coupon_start(), far, coupon_conv(cast(2, i64))), expected, tight64(), "an accrual running past the period end returns 366/364, neither clamped nor trapped")
}
-- F17: `tests_neg/` pins that a zero-length and a reversed coupon period TRAP,
-- but nothing pinned that the accepting boundary is accepted, so narrowing the
-- guard from `span < 1` to `span <= 1` passed both oracles. A one-day period at
-- frequency 1 accrues its whole length.
def test_act_act_icma_one_day_coupon_period_is_accepted() -> unit ! { Test } = {
  from = date(cast(2004, i64), cast(2, i64), cast(1, i64))
  to = date(cast(2004, i64), cast(2, i64), cast(2, i64))
  conv = ActActIcma { period_start: from, period_end: to, frequency: cast(1, i64) }
  assert_close(year_fraction(from, to, conv), cast(1.0, f64), tight64(), "a one-day coupon period is accepted, not rejected by the period guard")
}
-- The matrices fold their cases with `all_true`, so this pins that the fold is
-- conjunctive. A disjunctive fold would make every matrix test vacuous while
-- leaving the whole suite green.
def test_matrix_oracle_is_conjunctive() -> unit ! { Test } = assert_close(to01_f64(all_true([true, false, true])), cast(0.0, f64), tight64(), "all_true is conjunctive: one false case must sink the group")
-- The property surface in `properties/` is compiled but called by nothing, so
-- these drive it at concrete inputs. An uncalled property is not coverage.
def test_property_isda_matches_independent_calendar() -> unit ! { Test } = {
  start = date(cast(2003, i64), cast(11, i64), cast(1, i64))
  end = date(cast(2004, i64), cast(5, i64), cast(1, i64))
  assert_close(to01_f64(year_fraction_matches_textbook(start, end, ActActIsda)), cast(1.0, f64), tight64(), "ACT/ACT ISDA agrees with the independent ordinal reference")
}
def test_property_icma_matches_independent_calendar() -> unit ! { Test } = {
  period_start = date(cast(2003, i64), cast(11, i64), cast(1, i64))
  period_end = date(cast(2004, i64), cast(5, i64), cast(1, i64))
  convention = ActActIcma { period_start, period_end, frequency: cast(2, i64) }
  settle = date(cast(2004, i64), cast(2, i64), cast(1, i64))
  assert_close(to01_f64(year_fraction_matches_textbook(period_start, settle, convention)), cast(1.0, f64), tight64(), "ACT/ACT ICMA agrees with the independent ordinal reference")
}
-- 1899-11-01 to 1900-05-01 is 61 days of 1899 plus 120 days of 1900, both
-- ordinary years, so 181/365. Two things make this case load-bearing rather
-- than decorative. It is the only subject-vs-reference comparison here that
-- reaches a nonzero century term in the reference's ordinal: for every year in
-- 2000..2099 that term is identically zero, so a reference with the Gregorian
-- century rule deleted agrees with a correct one everywhere else in this file.
-- And 1900 is the century non-leap, so a denominator of 366 would also show up.
def test_act_act_isda_across_a_century_non_leap() -> unit ! { Test } = {
  start = date(cast(1899, i64), cast(11, i64), cast(1, i64))
  end = date(cast(1900, i64), cast(5, i64), cast(1, i64))
  expected = div(cast(181.0, f64), cast(365.0, f64))
  assert_close(year_fraction(start, end, ActActIsda), expected, tight64(), "1899-11-01..1900-05-01 == 181/365 (1900 is not a leap year)")
}
def test_property_isda_matches_independent_calendar_across_a_century() -> unit ! { Test } = {
  start = date(cast(1899, i64), cast(11, i64), cast(1, i64))
  end = date(cast(1900, i64), cast(5, i64), cast(1, i64))
  assert_close(to01_f64(year_fraction_matches_textbook(start, end, ActActIsda)), cast(1.0, f64), tight64(), "subject and independent reference agree where the ordinal's century term is live")
}
def test_property_whole_isda_year_non_leap() -> unit ! { Test } = assert_close(to01_f64(whole_isda_year_is_exactly_one(cast(2025, i64))), cast(1.0, f64), tight64(), "2025 is exactly one ISDA year")
def test_property_whole_isda_year_leap() -> unit ! { Test } = assert_close(to01_f64(whole_isda_year_is_exactly_one(cast(2024, i64))), cast(1.0, f64), tight64(), "2024 is exactly one ISDA year")
def test_property_whole_isda_year_century_non_leap() -> unit ! { Test } = assert_close(to01_f64(whole_isda_year_is_exactly_one(cast(1900, i64))), cast(1.0, f64), tight64(), "1900 is exactly one ISDA year (century non-leap)")
def test_property_whole_isda_year_quadricentennial() -> unit ! { Test } = assert_close(to01_f64(whole_isda_year_is_exactly_one(cast(2000, i64))), cast(1.0, f64), tight64(), "2000 is exactly one ISDA year (quadricentennial leap)")
def test_property_isda_reverses_under_swap() -> unit ! { Test } = {
  start = date(cast(2019, i64), cast(6, i64), cast(10, i64))
  end = date(cast(2024, i64), cast(3, i64), cast(2, i64))
  assert_close(to01_f64(isda_reverses_under_swap(start, end)), cast(1.0, f64), tight64(), "ISDA negates under argument swap across a leap year")
}
