module Shoals.Properties.Tenor
import Std.Datetime (Date, date_add_days, date_days_until)
import Shoals.Tenor (Tenor, TenorUnit, tenor, tenor_to_days, tenor_apply, days_n, weeks_n, months_n, years_n)
def tenor_apply_advances_by_tenor_to_days(ref: Date, t: Tenor) -> bool = {
  shifted = tenor_apply(t, ref)
  delta = date_days_until(ref, shifted)
  eq(delta, tenor_to_days(t))
}
def days_then_weeks_equals_compound(ref: Date, n_days: i64, n_weeks: i64) -> bool = {
  via_compose = tenor_apply(weeks_n(n_weeks), tenor_apply(days_n(n_days), ref))
  via_sum = date_add_days(ref, add(n_days, mul(n_weeks, cast(7, i64))))
  eq(date_days_until(via_compose, via_sum), cast(0, i64))
}
def tenor_to_days_nonneg_for_positive_count(unit: TenorUnit, n: i64) -> bool = if lt(n, cast(0, i64)) then true else gte(tenor_to_days(tenor(n, unit)), cast(0, i64))
