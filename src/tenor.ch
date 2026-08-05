module Shoals.Tenor
import Std.Time (Date, add_days)
export (TenorUnit, Tenor, tenor, tenor_to_days, tenor_apply, days_per_unit, overnight, tomorrow_next, spot_next, days_n, weeks_n, months_n, years_n, parse_tenor, parse_unit_suffix)
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
def days_per_unit(unit: TenorUnit) -> int64 =
  match unit with {
    | Day => cast(1, int64)
    | Week => cast(7, int64)
    | Month => cast(30, int64)
    | Year => cast(365, int64)
    | Overnight => cast(1, int64)
    | TomorrowNext => cast(2, int64)
    | SpotNext => cast(3, int64)
  }
def tenor(count: int64, unit: TenorUnit) -> Tenor = Tenor { count, unit }
def overnight() -> Tenor = Tenor { count: cast(1, int64), unit: Overnight }
def tomorrow_next() -> Tenor = Tenor { count: cast(1, int64), unit: TomorrowNext }
def spot_next() -> Tenor = Tenor { count: cast(1, int64), unit: SpotNext }
def days_n(n: int64) -> Tenor = Tenor { count: n, unit: Day }
def weeks_n(n: int64) -> Tenor = Tenor { count: n, unit: Week }
def months_n(n: int64) -> Tenor = Tenor { count: n, unit: Month }
def years_n(n: int64) -> Tenor = Tenor { count: n, unit: Year }
def tenor_to_days(t: Tenor) -> int64 =
  match t with {
    | Tenor { count: c, unit: u } => mul(c, days_per_unit(u))
  }
def tenor_apply(t: Tenor, reference: Date) -> Date = add_days(reference, tenor_to_days(t))
def char_at(text: string, idx: int64) -> string = string_slice(text, idx, cast(1, int64))
def parse_unit_suffix(suffix: string) -> TenorUnit = if eq(suffix, "D") then Day else if eq(suffix, "W") then Week else if eq(suffix, "M") then Month else if eq(suffix, "Y") then Year else fail("Shoals.Tenor.parse_tenor: unknown unit suffix (expected D/W/M/Y)")
def parse_tenor(text: string) -> Tenor =
  if eq(text, "ON") then Tenor { count: cast(1, int64), unit: Overnight } else if eq(text, "TN") then Tenor { count: cast(1, int64), unit: TomorrowNext } else if eq(text, "SN") then Tenor { count: cast(1, int64), unit: SpotNext } else {
    len = string_len(text)
    if lt(len, cast(2, int64)) then fail("Shoals.Tenor.parse_tenor: tenor must be at least 2 chars (e.g. 3M, 1Y, ON)") else {
      suffix = char_at(text, sub(len, cast(1, int64)))
      digits = string_slice(text, cast(0, int64), sub(len, cast(1, int64)))
      unit = parse_unit_suffix(suffix)
      match to_int(digits) with {
        | Some(n) => Tenor { count: n, unit }
        | None => fail("Shoals.Tenor.parse_tenor: count is not an integer")
      }
    }
  }
