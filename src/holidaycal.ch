module Shoals.HolidayCal
import Std.Time (Date, date, day_of_week, DayOfWeek)
export (Calendar, is_holiday, is_business_day, nyc_calendar, ldn_calendar, joint_calendar, weekend_only_calendar, empty_calendar)
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
def nyc_calendar() -> Calendar = Calendar { name: "nyc", holidays: [date(cast(2025, int64), cast(1, int64), cast(1, int64)), date(cast(2025, int64), cast(1, int64), cast(20, int64)), date(cast(2025, int64), cast(2, int64), cast(17, int64)), date(cast(2025, int64), cast(5, int64), cast(26, int64)), date(cast(2025, int64), cast(6, int64), cast(19, int64)), date(cast(2025, int64), cast(7, int64), cast(4, int64)), date(cast(2025, int64), cast(9, int64), cast(1, int64)), date(cast(2025, int64), cast(10, int64), cast(13, int64)), date(cast(2025, int64), cast(11, int64), cast(11, int64)), date(cast(2025, int64), cast(11, int64), cast(27, int64)), date(cast(2025, int64), cast(12, int64), cast(25, int64))] }
def ldn_calendar() -> Calendar = Calendar { name: "ldn", holidays: [date(cast(2025, int64), cast(1, int64), cast(1, int64)), date(cast(2025, int64), cast(4, int64), cast(18, int64)), date(cast(2025, int64), cast(4, int64), cast(21, int64)), date(cast(2025, int64), cast(5, int64), cast(5, int64)), date(cast(2025, int64), cast(5, int64), cast(26, int64)), date(cast(2025, int64), cast(8, int64), cast(25, int64)), date(cast(2025, int64), cast(12, int64), cast(25, int64)), date(cast(2025, int64), cast(12, int64), cast(26, int64))] }
def merge_holidays(a: List[Date], b: List[Date]) -> List[Date] = fold(fn (acc: List[Date], d: Date) -> if list_contains_date(acc, d) then acc else append(acc, d), a, b)
def joint_calendar(left: Calendar, right: Calendar) -> Calendar = {
  match left with {
    | Calendar { name: ln, holidays: lh } => match right with {
    | Calendar { name: rn, holidays: rh } => Calendar { name: ln, holidays: merge_holidays(lh, rh) }
  }
  }
}
