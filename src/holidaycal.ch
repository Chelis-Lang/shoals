module Shoals.HolidayCal
import Std.Time (Date, date, add_days, day_of_week, DayOfWeek)
export (Calendar, is_holiday, is_business_day, hc_nyc_calendar, hc_ldn_calendar, joint_calendar, weekend_only_calendar, empty_calendar, easter_sunday_gregorian, good_friday, easter_monday, hc_nyc_calendar_year, hc_ldn_calendar_year, hc_nyc_calendar_multi, hc_ldn_calendar_multi)
type Calendar =
  | Calendar { name: string, holidays: List[Date] }
def empty_calendar(name: string) -> Calendar = Calendar { name: name, holidays: [] }
def weekend_only_calendar() -> Calendar = Calendar { name: "weekend", holidays: [] }
def date_eq(a: Date, b: Date) -> bool = and(eq(a.year, b.year), and(eq(a.month, b.month), eq(a.day, b.day)))
def list_contains_date(holidays: List[Date], d: Date) -> bool = fold(fn (acc: bool, h: Date) -> or(acc, date_eq(h, d)), false, holidays)
def is_weekend(d: Date) -> bool = {
  match day_of_week(d) with {
    | Saturday => true
    | Sunday => true
    | Monday => false
    | Tuesday => false
    | Wednesday => false
    | Thursday => false
    | Friday => false
  }
}
def is_holiday(cal: Calendar, d: Date) -> bool = {
  match cal with {
    | Calendar { name: _, holidays: hs } => list_contains_date(hs, d)
  }
}
def is_business_day(cal: Calendar, d: Date) -> bool = and(not(is_weekend(d)), not(is_holiday(cal, d)))
def easter_sunday_gregorian(year: int64) -> Date = {
  a = mod(year, cast(19, int64))
  b = div(year, cast(100, int64))
  c = mod(year, cast(100, int64))
  d = div(b, cast(4, int64))
  e = mod(b, cast(4, int64))
  f = div(add(b, cast(8, int64)), cast(25, int64))
  g = div(sub(add(b, cast(1, int64)), f), cast(3, int64))
  h_val = mod(add(sub(add(mul(cast(19, int64), a), b), d), sub(cast(15, int64), g)), cast(30, int64))
  i = div(c, cast(4, int64))
  k = mod(c, cast(4, int64))
  l = mod(add(sub(add(cast(32, int64), mul(cast(2, int64), e)), h_val), sub(mul(cast(2, int64), i), k)), cast(7, int64))
  m = div(add(a, add(mul(cast(11, int64), h_val), mul(cast(22, int64), l))), cast(451, int64))
  month_total = div(add(add(h_val, l), sub(cast(114, int64), mul(cast(7, int64), m))), cast(31, int64))
  day_total = add(mod(add(add(h_val, l), sub(cast(114, int64), mul(cast(7, int64), m))), cast(31, int64)), cast(1, int64))
  date(year, month_total, day_total)
}
def good_friday(year: int64) -> Date = add_days(easter_sunday_gregorian(year), cast(-2, int64))
def easter_monday(year: int64) -> Date = add_days(easter_sunday_gregorian(year), cast(1, int64))
def hc_nyc_calendar_year(year: int64) -> Calendar = Calendar { name: "nyc", holidays: [date(year, cast(1, int64), cast(1, int64)), date(year, cast(7, int64), cast(4, int64)), date(year, cast(12, int64), cast(25, int64))] }
def hc_ldn_calendar_year(year: int64) -> Calendar = Calendar { name: "ldn", holidays: [date(year, cast(1, int64), cast(1, int64)), good_friday(year), easter_monday(year), date(year, cast(12, int64), cast(25, int64)), date(year, cast(12, int64), cast(26, int64))] }
def concat_holidays(years: List[int64], gen: int64 -> List[Date]) -> List[Date] = {
  fold(fn (acc: List[Date], y: int64) -> {
    yhol = gen(y)
    fold(fn (acc2: List[Date], d: Date) -> if list_contains_date(acc2, d) then acc2 else append(acc2, d), acc, yhol)
  }, [], years)
}
def hc_nyc_calendar_multi(years: List[int64]) -> Calendar = {
  gen = fn (y: int64) -> {
    match hc_nyc_calendar_year(y) with {
      | Calendar { name: _, holidays: hs } => hs
    }
  }
  Calendar { name: "nyc-multi", holidays: concat_holidays(years, gen) }
}
def hc_ldn_calendar_multi(years: List[int64]) -> Calendar = {
  gen = fn (y: int64) -> {
    match hc_ldn_calendar_year(y) with {
      | Calendar { name: _, holidays: hs } => hs
    }
  }
  Calendar { name: "ldn-multi", holidays: concat_holidays(years, gen) }
}
def hc_nyc_calendar() -> Calendar = Calendar { name: "nyc", holidays: [date(cast(2025, int64), cast(1, int64), cast(1, int64)), date(cast(2025, int64), cast(1, int64), cast(20, int64)), date(cast(2025, int64), cast(2, int64), cast(17, int64)), date(cast(2025, int64), cast(5, int64), cast(26, int64)), date(cast(2025, int64), cast(6, int64), cast(19, int64)), date(cast(2025, int64), cast(7, int64), cast(4, int64)), date(cast(2025, int64), cast(9, int64), cast(1, int64)), date(cast(2025, int64), cast(10, int64), cast(13, int64)), date(cast(2025, int64), cast(11, int64), cast(11, int64)), date(cast(2025, int64), cast(11, int64), cast(27, int64)), date(cast(2025, int64), cast(12, int64), cast(25, int64))] }
def hc_ldn_calendar() -> Calendar = Calendar { name: "ldn", holidays: [date(cast(2025, int64), cast(1, int64), cast(1, int64)), good_friday(cast(2025, int64)), easter_monday(cast(2025, int64)), date(cast(2025, int64), cast(5, int64), cast(5, int64)), date(cast(2025, int64), cast(5, int64), cast(26, int64)), date(cast(2025, int64), cast(8, int64), cast(25, int64)), date(cast(2025, int64), cast(12, int64), cast(25, int64)), date(cast(2025, int64), cast(12, int64), cast(26, int64))] }
def merge_holidays(a: List[Date], b: List[Date]) -> List[Date] = fold(fn (acc: List[Date], d: Date) -> if list_contains_date(acc, d) then acc else append(acc, d), a, b)
def joint_calendar(left: Calendar, right: Calendar) -> Calendar = {
  match left with {
    | Calendar { name: ln, holidays: lh } => match right with {
    | Calendar { name: rn, holidays: rh } => Calendar { name: ln, holidays: merge_holidays(lh, rh) }
  }
  }
}
