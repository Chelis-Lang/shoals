module Shoals.Tenor
import Std.Time (Date, add_days)
export (TenorUnit, Tenor, tenor, tenor_to_days, tenor_apply, days_per_unit, overnight, tomorrow_next, spot_next, days_n, weeks_n, months_n, years_n)
type TenorUnit =
  | Day
  | Week
  | Month
  | Year
  | Overnight
  | TomorrowNext
  | SpotNext
type Tenor =
  | Tenor { count: int64, unit: TenorUnit }
def days_per_unit(unit: TenorUnit) -> int64 = {
  match unit with {
    | Day => cast(1, int64)
    | Week => cast(7, int64)
    | Month => cast(30, int64)
    | Year => cast(365, int64)
    | Overnight => cast(1, int64)
    | TomorrowNext => cast(2, int64)
    | SpotNext => cast(3, int64)
  }
}
def tenor(count: int64, unit: TenorUnit) -> Tenor = Tenor { count: count, unit: unit }
def overnight() -> Tenor = Tenor { count: cast(1, int64), unit: Overnight }
def tomorrow_next() -> Tenor = Tenor { count: cast(1, int64), unit: TomorrowNext }
def spot_next() -> Tenor = Tenor { count: cast(1, int64), unit: SpotNext }
def days_n(n: int64) -> Tenor = Tenor { count: n, unit: Day }
def weeks_n(n: int64) -> Tenor = Tenor { count: n, unit: Week }
def months_n(n: int64) -> Tenor = Tenor { count: n, unit: Month }
def years_n(n: int64) -> Tenor = Tenor { count: n, unit: Year }
def tenor_to_days(t: Tenor) -> int64 = {
  match t with {
    | Tenor { count: c, unit: u } => mul(c, days_per_unit(u))
  }
}
def tenor_apply(t: Tenor, reference: Date) -> Date = add_days(reference, tenor_to_days(t))
