module Shoals.Tests.RiskextFrtbZone
import Std.Test (assert_true)
import Shoals.RiskExt (re_frtb_ima_zone_at_day, re_frtb_ima_zone_rolling)
def test_frtb_zone_at_day_boundaries() -> unit ! { Test } = {
  z0 = re_frtb_ima_zone_at_day(cast(0, i64))
  z4 = re_frtb_ima_zone_at_day(cast(4, i64))
  z5 = re_frtb_ima_zone_at_day(cast(5, i64))
  z9 = re_frtb_ima_zone_at_day(cast(9, i64))
  z10 = re_frtb_ima_zone_at_day(cast(10, i64))
  z15 = re_frtb_ima_zone_at_day(cast(15, i64))
  _ = assert_true(eq(z0, cast(0, i64)), "k=0 -> Green (0)")
  _ = assert_true(eq(z4, cast(0, i64)), "k=4 -> Green (0)")
  _ = assert_true(eq(z5, cast(1, i64)), "k=5 -> Yellow (1)")
  _ = assert_true(eq(z9, cast(1, i64)), "k=9 -> Yellow (1)")
  _ = assert_true(eq(z10, cast(2, i64)), "k=10 -> Red (2)")
  assert_true(eq(z15, cast(2, i64)), "k=15 -> Red (2)")
}
def test_frtb_zone_rolling_all_green() -> unit ! { Test } = {
  idxs = range(cast(0, i64), cast(250, i64))
  losses = to_tensor(map(fn (i: i64) -> cast(0.0, f32), idxs))
  vars_f = to_tensor(map(fn (i: i64) -> cast(1.0, f32), idxs))
  zones = re_frtb_ima_zone_rolling(losses, vars_f)
  zones_l = to_list(zones)
  all_green = fold(fn (acc: bool, z: i64) -> if acc then eq(z, cast(0, i64)) else false, true, zones_l)
  assert_true(all_green, "all zero exceptions -> all Green")
}
def test_frtb_zone_rolling_threshold_at_5() -> unit ! { Test } = {
  idxs = range(cast(0, i64), cast(250, i64))
  losses = to_tensor(map(fn (i: i64) -> if eq(mod(i, cast(50, i64)), cast(0, i64)) then cast(2.0, f32) else cast(0.0, f32), idxs))
  vars_f = to_tensor(map(fn (i: i64) -> cast(1.0, f32), idxs))
  zones = re_frtb_ima_zone_rolling(losses, vars_f)
  zones_l = to_list(zones)
  z_at_249 = index(zones_l, cast(0, i64))
  assert_true(eq(z_at_249, cast(1, i64)), "exactly 5 exceptions in 250-day window -> Yellow (1)")
}
def test_frtb_zone_rolling_threshold_at_10() -> unit ! { Test } = {
  idxs = range(cast(0, i64), cast(250, i64))
  losses = to_tensor(map(fn (i: i64) -> if eq(mod(i, cast(25, i64)), cast(0, i64)) then cast(2.0, f32) else cast(0.0, f32), idxs))
  vars_f = to_tensor(map(fn (i: i64) -> cast(1.0, f32), idxs))
  zones = re_frtb_ima_zone_rolling(losses, vars_f)
  zones_l = to_list(zones)
  z_at_249 = index(zones_l, cast(0, i64))
  assert_true(eq(z_at_249, cast(2, i64)), "exactly 10 exceptions in 250-day window -> Red (2)")
}
def test_frtb_zone_rolling_window_slides() -> unit ! { Test } = {
  idxs = range(cast(0, i64), cast(251, i64))
  losses = to_tensor(map(fn (i: i64) -> if lt(i, cast(4, i64)) then cast(2.0, f32) else cast(0.0, f32), idxs))
  vars_f = to_tensor(map(fn (i: i64) -> cast(1.0, f32), idxs))
  zones = re_frtb_ima_zone_rolling(losses, vars_f)
  zones_l = to_list(zones)
  z_day_249 = index(zones_l, cast(0, i64))
  z_day_250 = index(zones_l, cast(1, i64))
  n_out = len(zones_l)
  _ = assert_true(eq(n_out, cast(2, i64)), "251-day series -> 2 zone entries")
  _ = assert_true(eq(z_day_249, cast(0, i64)), "day 249: 4 exceptions in window -> Green (0)")
  assert_true(eq(z_day_250, cast(0, i64)), "day 250: 3 exceptions in window (1st slid out) -> Green (0)")
}
