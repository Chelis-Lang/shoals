module Shoals.HolidayCal
import Std.Datetime (Date, date, date_add_days, date_weekday, date_year, date_month, date_day, Weekday, Monday, Tuesday, Wednesday, Thursday, Friday, Saturday, Sunday)
export (Calendar, is_holiday, is_business_day, hc_nyc_calendar, hc_ldn_calendar, joint_calendar, weekend_only_calendar, empty_calendar, easter_sunday_gregorian, good_friday, easter_monday, hc_nyc_calendar_year, hc_ldn_calendar_year, hc_nyc_calendar_multi, hc_ldn_calendar_multi, hc_tyo_is_holiday, hc_syd_is_holiday, hc_fra_is_holiday, hc_hkg_is_holiday)
type Calendar =
  | Calendar { name: string, holidays: List[Date] }
def empty_calendar(name: string) -> Calendar = Calendar { name, holidays: [] }
def weekend_only_calendar() -> Calendar = Calendar { name: "weekend", holidays: [] }
def date_eq(a: Date, b: Date) -> bool = and(eq(date_year(a), date_year(b)), and(eq(date_month(a), date_month(b)), eq(date_day(a), date_day(b))))
def list_contains_date(holidays: List[Date], d: Date) -> bool = fold(fn (acc: bool, h: Date) -> or(acc, date_eq(h, d)), false, holidays)
def is_weekend(d: Date) -> bool =
  match date_weekday(d) with {
    | Saturday => true
    | Sunday => true
    | Monday => false
    | Tuesday => false
    | Wednesday => false
    | Thursday => false
    | Friday => false
  }
def is_holiday(cal: Calendar, d: Date) -> bool =
  match cal with {
    | Calendar { name: _, holidays: hs } => list_contains_date(hs, d)
  }
def is_business_day(cal: Calendar, d: Date) -> bool = and(not(is_weekend(d)), not(is_holiday(cal, d)))
def easter_sunday_gregorian(year: i64) -> Date = {
  a = mod(year, cast(19, i64))
  b = floor_div(year, cast(100, i64))
  c = mod(year, cast(100, i64))
  d = floor_div(b, cast(4, i64))
  e = mod(b, cast(4, i64))
  f = floor_div(add(b, cast(8, i64)), cast(25, i64))
  g = floor_div(sub(add(b, cast(1, i64)), f), cast(3, i64))
  h_val = mod(add(sub(add(mul(cast(19, i64), a), b), d), sub(cast(15, i64), g)), cast(30, i64))
  i = floor_div(c, cast(4, i64))
  k = mod(c, cast(4, i64))
  l = mod(add(sub(add(cast(32, i64), mul(cast(2, i64), e)), h_val), sub(mul(cast(2, i64), i), k)), cast(7, i64))
  m = floor_div(add(a, add(mul(cast(11, i64), h_val), mul(cast(22, i64), l))), cast(451, i64))
  month_total = floor_div(add(add(h_val, l), sub(cast(114, i64), mul(cast(7, i64), m))), cast(31, i64))
  day_total = add(mod(add(add(h_val, l), sub(cast(114, i64), mul(cast(7, i64), m))), cast(31, i64)), cast(1, i64))
  date(year, month_total, day_total)
}
def good_friday(year: i64) -> Date = date_add_days(easter_sunday_gregorian(year), cast(-2, i64))
def easter_monday(year: i64) -> Date = date_add_days(easter_sunday_gregorian(year), cast(1, i64))
def hc_nyc_calendar_year(year: i64) -> Calendar = Calendar { name: "nyc", holidays: [date(year, cast(1, i64), cast(1, i64)), date(year, cast(7, i64), cast(4, i64)), date(year, cast(12, i64), cast(25, i64))] }
def hc_ldn_calendar_year(year: i64) -> Calendar = Calendar { name: "ldn", holidays: [date(year, cast(1, i64), cast(1, i64)), good_friday(year), easter_monday(year), date(year, cast(12, i64), cast(25, i64)), date(year, cast(12, i64), cast(26, i64))] }
def concat_holidays(years: List[i64], gen: i64 -> List[Date]) -> List[Date] =
  fold(fn (acc: List[Date], y: i64) -> {
    yhol = gen(y)
    fold(fn (acc2: List[Date], d: Date) -> if list_contains_date(acc2, d) then acc2 else append(acc2, d), acc, yhol)
  }, [], years)
def hc_nyc_calendar_multi(years: List[i64]) -> Calendar = {
  gen = fn (y: i64) -> match hc_nyc_calendar_year(y) with {
    | Calendar { name: _, holidays: hs } => hs
  }
  Calendar { name: "nyc-multi", holidays: concat_holidays(years, gen) }
}
def hc_ldn_calendar_multi(years: List[i64]) -> Calendar = {
  gen = fn (y: i64) -> match hc_ldn_calendar_year(y) with {
    | Calendar { name: _, holidays: hs } => hs
  }
  Calendar { name: "ldn-multi", holidays: concat_holidays(years, gen) }
}
def hc_nyc_calendar() -> Calendar = Calendar { name: "nyc", holidays: [date(cast(2025, i64), cast(1, i64), cast(1, i64)), date(cast(2025, i64), cast(1, i64), cast(20, i64)), date(cast(2025, i64), cast(2, i64), cast(17, i64)), date(cast(2025, i64), cast(5, i64), cast(26, i64)), date(cast(2025, i64), cast(6, i64), cast(19, i64)), date(cast(2025, i64), cast(7, i64), cast(4, i64)), date(cast(2025, i64), cast(9, i64), cast(1, i64)), date(cast(2025, i64), cast(10, i64), cast(13, i64)), date(cast(2025, i64), cast(11, i64), cast(11, i64)), date(cast(2025, i64), cast(11, i64), cast(27, i64)), date(cast(2025, i64), cast(12, i64), cast(25, i64))] }
def hc_ldn_calendar() -> Calendar = Calendar { name: "ldn", holidays: [date(cast(2025, i64), cast(1, i64), cast(1, i64)), good_friday(cast(2025, i64)), easter_monday(cast(2025, i64)), date(cast(2025, i64), cast(5, i64), cast(5, i64)), date(cast(2025, i64), cast(5, i64), cast(26, i64)), date(cast(2025, i64), cast(8, i64), cast(25, i64)), date(cast(2025, i64), cast(12, i64), cast(25, i64)), date(cast(2025, i64), cast(12, i64), cast(26, i64))] }
def merge_holidays(a: List[Date], b: List[Date]) -> List[Date] = fold(fn (acc: List[Date], d: Date) -> if list_contains_date(acc, d) then acc else append(acc, d), a, b)
def joint_calendar(left: Calendar, right: Calendar) -> Calendar =
  match left with {
    | Calendar { name: ln, holidays: lh } => match right with {
    | Calendar { name: rn, holidays: rh } => Calendar { name: ln, holidays: merge_holidays(lh, rh) }
  }
  }
export (hc_tyo_holidays_year, hc_syd_holidays_year, hc_fra_holidays_year, hc_hkg_holidays_year, hc_tyo_is_holiday, hc_syd_is_holiday, hc_fra_is_holiday, hc_hkg_is_holiday)
def hc_dow_to_int(d: Date) -> i64 =
  match date_weekday(d) with {
    | Monday => cast(0, i64)
    | Tuesday => cast(1, i64)
    | Wednesday => cast(2, i64)
    | Thursday => cast(3, i64)
    | Friday => cast(4, i64)
    | Saturday => cast(5, i64)
    | Sunday => cast(6, i64)
  }
def hc_nth_weekday_of_month(year: i64, month: i64, target_dow: i64, n: i64) -> Date = {
  first = date(year, month, cast(1, i64))
  first_dow = hc_dow_to_int(first)
  offset_to_target = mod(add(sub(target_dow, first_dow), cast(7, i64)), cast(7, i64))
  base = date_add_days(first, offset_to_target)
  date_add_days(base, mul(sub(n, cast(1, i64)), cast(7, i64)))
}
def hc_observed_mon_if_weekend(d: Date) -> Date = {
  wd = hc_dow_to_int(d)
  if eq(wd, cast(5, i64)) then date_add_days(d, cast(2, i64)) else if eq(wd, cast(6, i64)) then date_add_days(d, cast(1, i64)) else d
}
def hc_triple(d: Date) -> (i64, i64, i64) = (date_year(d), date_month(d), date_day(d))
def hc_triple_eq(a: (i64, i64, i64), y: i64, m: i64, d: i64) -> bool = and(eq(a.0, y), and(eq(a.1, m), eq(a.2, d)))
def hc_list_contains_triple(xs: List[(i64, i64, i64)], y: i64, m: i64, d: i64) -> bool = fold(fn (acc: bool, t: (i64, i64, i64)) -> or(acc, hc_triple_eq(t, y, m, d)), false, xs)
def hc_vernal_equinox_day(year: i64) -> i64 = if eq(year, cast(2025, i64)) then cast(20, i64) else if eq(year, cast(2026, i64)) then cast(20, i64) else if eq(year, cast(2027, i64)) then cast(21, i64) else if eq(year, cast(2028, i64)) then cast(20, i64) else if eq(year, cast(2029, i64)) then cast(20, i64) else if eq(year, cast(2030, i64)) then cast(20, i64) else cast(20, i64)
def hc_autumnal_equinox_day(year: i64) -> i64 = if eq(year, cast(2025, i64)) then cast(23, i64) else if eq(year, cast(2026, i64)) then cast(23, i64) else if eq(year, cast(2027, i64)) then cast(23, i64) else if eq(year, cast(2028, i64)) then cast(22, i64) else if eq(year, cast(2029, i64)) then cast(23, i64) else if eq(year, cast(2030, i64)) then cast(23, i64) else cast(23, i64)
def hc_tyo_holidays_year(year: i64) -> List[(i64, i64, i64)] = {
  jan_1 = (year, cast(1, i64), cast(1, i64))
  coming_of_age = hc_triple(hc_nth_weekday_of_month(year, cast(1, i64), cast(0, i64), cast(2, i64)))
  national_foundation = (year, cast(2, i64), cast(11, i64))
  emperor_birthday = (year, cast(2, i64), cast(23, i64))
  vernal_eq = (year, cast(3, i64), hc_vernal_equinox_day(year))
  showa_day = (year, cast(4, i64), cast(29, i64))
  constitution = (year, cast(5, i64), cast(3, i64))
  greenery = (year, cast(5, i64), cast(4, i64))
  childrens = (year, cast(5, i64), cast(5, i64))
  marine = hc_triple(hc_nth_weekday_of_month(year, cast(7, i64), cast(0, i64), cast(3, i64)))
  mountain = (year, cast(8, i64), cast(11, i64))
  respect_aged = hc_triple(hc_nth_weekday_of_month(year, cast(9, i64), cast(0, i64), cast(3, i64)))
  autumnal_eq = (year, cast(9, i64), hc_autumnal_equinox_day(year))
  sports = hc_triple(hc_nth_weekday_of_month(year, cast(10, i64), cast(0, i64), cast(2, i64)))
  culture = (year, cast(11, i64), cast(3, i64))
  labor_thanks = (year, cast(11, i64), cast(23, i64))
  [jan_1, coming_of_age, national_foundation, emperor_birthday, vernal_eq, showa_day, constitution, greenery, childrens, marine, mountain, respect_aged, autumnal_eq, sports, culture, labor_thanks]
}
def hc_syd_holidays_year(year: i64) -> List[(i64, i64, i64)] = {
  new_year = hc_triple(hc_observed_mon_if_weekend(date(year, cast(1, i64), cast(1, i64))))
  australia = hc_triple(hc_observed_mon_if_weekend(date(year, cast(1, i64), cast(26, i64))))
  good_fri = hc_triple(good_friday(year))
  east_mon = hc_triple(easter_monday(year))
  anzac = (year, cast(4, i64), cast(25, i64))
  queens = hc_triple(hc_nth_weekday_of_month(year, cast(6, i64), cast(0, i64), cast(2, i64)))
  bank_hol = hc_triple(hc_nth_weekday_of_month(year, cast(8, i64), cast(0, i64), cast(1, i64)))
  labour = hc_triple(hc_nth_weekday_of_month(year, cast(10, i64), cast(0, i64), cast(1, i64)))
  christmas = hc_triple(hc_observed_mon_if_weekend(date(year, cast(12, i64), cast(25, i64))))
  boxing = hc_triple(hc_observed_mon_if_weekend(date(year, cast(12, i64), cast(26, i64))))
  [new_year, australia, good_fri, east_mon, anzac, queens, bank_hol, labour, christmas, boxing]
}
def hc_fra_holidays_year(year: i64) -> List[(i64, i64, i64)] = {
  new_year = (year, cast(1, i64), cast(1, i64))
  good_fri = hc_triple(good_friday(year))
  east_mon = hc_triple(easter_monday(year))
  labour = (year, cast(5, i64), cast(1, i64))
  ascension = hc_triple(date_add_days(easter_sunday_gregorian(year), cast(39, i64)))
  whit_mon = hc_triple(date_add_days(easter_sunday_gregorian(year), cast(50, i64)))
  unity = (year, cast(10, i64), cast(3, i64))
  christmas = (year, cast(12, i64), cast(25, i64))
  boxing = (year, cast(12, i64), cast(26, i64))
  [new_year, good_fri, east_mon, labour, ascension, whit_mon, unity, christmas, boxing]
}
def hc_lunar_new_year_first(year: i64) -> (i64, i64, i64) = if eq(year, cast(2025, i64)) then (cast(2025, i64), cast(1, i64), cast(29, i64)) else if eq(year, cast(2026, i64)) then (cast(2026, i64), cast(2, i64), cast(17, i64)) else if eq(year, cast(2027, i64)) then (cast(2027, i64), cast(2, i64), cast(6, i64)) else if eq(year, cast(2028, i64)) then (cast(2028, i64), cast(1, i64), cast(26, i64)) else if eq(year, cast(2029, i64)) then (cast(2029, i64), cast(2, i64), cast(13, i64)) else if eq(year, cast(2030, i64)) then (cast(2030, i64), cast(2, i64), cast(3, i64)) else (cast(-1, i64), cast(-1, i64), cast(-1, i64))
def hc_hkg_lookup_year_supported(year: i64) -> bool = if lt(year, cast(2025, i64)) then false else if gt(year, cast(2030, i64)) then false else true
def hc_ching_ming(year: i64) -> (i64, i64, i64) = if eq(year, cast(2025, i64)) then (cast(2025, i64), cast(4, i64), cast(4, i64)) else if eq(year, cast(2026, i64)) then (cast(2026, i64), cast(4, i64), cast(5, i64)) else if eq(year, cast(2027, i64)) then (cast(2027, i64), cast(4, i64), cast(5, i64)) else if eq(year, cast(2028, i64)) then (cast(2028, i64), cast(4, i64), cast(4, i64)) else if eq(year, cast(2029, i64)) then (cast(2029, i64), cast(4, i64), cast(4, i64)) else if eq(year, cast(2030, i64)) then (cast(2030, i64), cast(4, i64), cast(5, i64)) else (year, cast(4, i64), cast(5, i64))
def hc_buddha_birthday(year: i64) -> (i64, i64, i64) = if eq(year, cast(2025, i64)) then (cast(2025, i64), cast(5, i64), cast(5, i64)) else if eq(year, cast(2026, i64)) then (cast(2026, i64), cast(5, i64), cast(24, i64)) else if eq(year, cast(2027, i64)) then (cast(2027, i64), cast(5, i64), cast(13, i64)) else if eq(year, cast(2028, i64)) then (cast(2028, i64), cast(5, i64), cast(2, i64)) else if eq(year, cast(2029, i64)) then (cast(2029, i64), cast(5, i64), cast(20, i64)) else if eq(year, cast(2030, i64)) then (cast(2030, i64), cast(5, i64), cast(9, i64)) else (year, cast(5, i64), cast(8, i64))
def hc_dragon_boat(year: i64) -> (i64, i64, i64) = if eq(year, cast(2025, i64)) then (cast(2025, i64), cast(5, i64), cast(31, i64)) else if eq(year, cast(2026, i64)) then (cast(2026, i64), cast(6, i64), cast(19, i64)) else if eq(year, cast(2027, i64)) then (cast(2027, i64), cast(6, i64), cast(9, i64)) else if eq(year, cast(2028, i64)) then (cast(2028, i64), cast(5, i64), cast(28, i64)) else if eq(year, cast(2029, i64)) then (cast(2029, i64), cast(6, i64), cast(16, i64)) else if eq(year, cast(2030, i64)) then (cast(2030, i64), cast(6, i64), cast(5, i64)) else (year, cast(6, i64), cast(1, i64))
def hc_mid_autumn_day_after(year: i64) -> (i64, i64, i64) = if eq(year, cast(2025, i64)) then (cast(2025, i64), cast(10, i64), cast(7, i64)) else if eq(year, cast(2026, i64)) then (cast(2026, i64), cast(9, i64), cast(26, i64)) else if eq(year, cast(2027, i64)) then (cast(2027, i64), cast(9, i64), cast(16, i64)) else if eq(year, cast(2028, i64)) then (cast(2028, i64), cast(10, i64), cast(4, i64)) else if eq(year, cast(2029, i64)) then (cast(2029, i64), cast(9, i64), cast(23, i64)) else if eq(year, cast(2030, i64)) then (cast(2030, i64), cast(9, i64), cast(13, i64)) else (year, cast(9, i64), cast(15, i64))
def hc_chung_yeung(year: i64) -> (i64, i64, i64) = if eq(year, cast(2025, i64)) then (cast(2025, i64), cast(10, i64), cast(29, i64)) else if eq(year, cast(2026, i64)) then (cast(2026, i64), cast(10, i64), cast(18, i64)) else if eq(year, cast(2027, i64)) then (cast(2027, i64), cast(10, i64), cast(8, i64)) else if eq(year, cast(2028, i64)) then (cast(2028, i64), cast(10, i64), cast(26, i64)) else if eq(year, cast(2029, i64)) then (cast(2029, i64), cast(10, i64), cast(16, i64)) else if eq(year, cast(2030, i64)) then (cast(2030, i64), cast(10, i64), cast(5, i64)) else (year, cast(10, i64), cast(1, i64))
def hc_triple_add_days(t: (i64, i64, i64), n: i64) -> (i64, i64, i64) = hc_triple(date_add_days(date(t.0, t.1, t.2), n))
def hc_hkg_holidays_year(year: i64) -> List[(i64, i64, i64)] = {
  new_year = (year, cast(1, i64), cast(1, i64))
  lny_1 = hc_lunar_new_year_first(year)
  lny_2 = hc_triple_add_days(lny_1, cast(1, i64))
  lny_3 = hc_triple_add_days(lny_1, cast(2, i64))
  good_fri = hc_triple(good_friday(year))
  east_mon = hc_triple(easter_monday(year))
  ching_ming = hc_ching_ming(year)
  labour = (year, cast(5, i64), cast(1, i64))
  buddha = hc_buddha_birthday(year)
  dragon = hc_dragon_boat(year)
  hksar = (year, cast(7, i64), cast(1, i64))
  mid_autumn = hc_mid_autumn_day_after(year)
  national = (year, cast(10, i64), cast(1, i64))
  chung_yeung = hc_chung_yeung(year)
  christmas = (year, cast(12, i64), cast(25, i64))
  boxing = (year, cast(12, i64), cast(26, i64))
  [new_year, lny_1, lny_2, lny_3, good_fri, east_mon, ching_ming, labour, buddha, dragon, hksar, mid_autumn, national, chung_yeung, christmas, boxing]
}
def hc_tyo_is_holiday(y: i64, m: i64, d: i64) -> bool = hc_list_contains_triple(hc_tyo_holidays_year(y), y, m, d)
def hc_syd_is_holiday(y: i64, m: i64, d: i64) -> bool = hc_list_contains_triple(hc_syd_holidays_year(y), y, m, d)
def hc_fra_is_holiday(y: i64, m: i64, d: i64) -> bool = hc_list_contains_triple(hc_fra_holidays_year(y), y, m, d)
def hc_hkg_is_holiday(y: i64, m: i64, d: i64) -> bool = if hc_hkg_lookup_year_supported(y) then hc_list_contains_triple(hc_hkg_holidays_year(y), y, m, d) else false
