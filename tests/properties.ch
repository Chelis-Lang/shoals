module Shoals.Tests.Properties
import Std.Test (assert_close)
import Shoals.Properties.Pricing (matches_textbook_reference, matches_textbook_reference_put, put_call_parity_holds, call_bounded_by_spot, mc_matches_textbook_mc_reference)
import Shoals.Properties.Greeks (fd_delta_in_unit_range_for_call, fd_delta_matches_analytic)
def to01(b: bool) -> f32 = if b then cast(1.0, f32) else cast(0.0, f32)
def test_matches_textbook_atm_call() -> unit ! { Test } = {
  ok = matches_textbook_reference(cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32))
  assert_close(to01(ok), cast(1.0, f32), cast(0.001, f32), "ATM call agrees with textbook ref (S=100,K=100)")
}
def test_matches_textbook_otm_call() -> unit ! { Test } = {
  ok = matches_textbook_reference(cast(80.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32))
  assert_close(to01(ok), cast(1.0, f32), cast(0.001, f32), "OTM call agrees (S=80,K=100)")
}
def test_matches_textbook_itm_call() -> unit ! { Test } = {
  ok = matches_textbook_reference(cast(120.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32))
  assert_close(to01(ok), cast(1.0, f32), cast(0.001, f32), "ITM call agrees (S=120,K=100)")
}
def test_matches_textbook_low_vol() -> unit ! { Test } = {
  ok = matches_textbook_reference(cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.15, f32), cast(0.25, f32))
  assert_close(to01(ok), cast(1.0, f32), cast(0.001, f32), "low-vol short-T call agrees (sigma=0.15,T=0.25)")
}
def test_matches_textbook_high_vol() -> unit ! { Test } = {
  ok = matches_textbook_reference(cast(100.0, f32), cast(100.0, f32), cast(0.02, f32), cast(0.3, f32), cast(1.0, f32))
  assert_close(to01(ok), cast(1.0, f32), cast(0.001, f32), "high-vol low-rate call agrees (sigma=0.30,r=0.02)")
}
def test_matches_textbook_low_strike_call() -> unit ! { Test } = {
  ok = matches_textbook_reference(cast(100.0, f32), cast(90.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32))
  assert_close(to01(ok), cast(1.0, f32), cast(0.001, f32), "low-strike call agrees (K=90)")
}
def test_matches_textbook_high_strike_call() -> unit ! { Test } = {
  ok = matches_textbook_reference(cast(100.0, f32), cast(110.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32))
  assert_close(to01(ok), cast(1.0, f32), cast(0.001, f32), "high-strike call agrees (K=110)")
}
def test_matches_textbook_put_atm() -> unit ! { Test } = {
  ok = matches_textbook_reference_put(cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32))
  assert_close(to01(ok), cast(1.0, f32), cast(0.001, f32), "ATM put agrees with textbook ref")
}
def test_matches_textbook_put_otm() -> unit ! { Test } = {
  ok = matches_textbook_reference_put(cast(80.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32))
  assert_close(to01(ok), cast(1.0, f32), cast(0.001, f32), "OTM put agrees (S=80)")
}
def test_matches_textbook_put_itm() -> unit ! { Test } = {
  ok = matches_textbook_reference_put(cast(120.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32))
  assert_close(to01(ok), cast(1.0, f32), cast(0.001, f32), "ITM put agrees (S=120)")
}
def test_property_parity_grid_lowsigma() -> unit ! { Test } = {
  ok = put_call_parity_holds(cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.15, f32), cast(0.25, f32))
  assert_close(to01(ok), cast(1.0, f32), cast(0.001, f32), "parity holds at sigma=0.15, T=0.25")
}
def test_property_parity_grid_highsigma() -> unit ! { Test } = {
  ok = put_call_parity_holds(cast(120.0, f32), cast(110.0, f32), cast(0.02, f32), cast(0.3, f32), cast(1.0, f32))
  assert_close(to01(ok), cast(1.0, f32), cast(0.001, f32), "parity holds at S=120,K=110,sigma=0.30")
}
def test_call_bounded_grid_otm() -> unit ! { Test } = {
  ok = call_bounded_by_spot(cast(80.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32))
  assert_close(to01(ok), cast(1.0, f32), cast(0.001, f32), "call bounded by spot OTM")
}
def test_call_bounded_grid_itm() -> unit ! { Test } = {
  ok = call_bounded_by_spot(cast(150.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32))
  assert_close(to01(ok), cast(1.0, f32), cast(0.001, f32), "call bounded by spot ITM")
}
def test_fd_delta_in_unit_range_atm() -> unit ! { Test } = {
  ok = fd_delta_in_unit_range_for_call(cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32))
  assert_close(to01(ok), cast(1.0, f32), cast(0.001, f32), "FD call delta in [0,1] at ATM")
}
def test_fd_delta_matches_analytic_atm() -> unit ! { Test } = {
  ok = fd_delta_matches_analytic(cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32))
  assert_close(to01(ok), cast(1.0, f32), cast(0.001, f32), "FD call delta matches N(d1) within 5e-3 at ATM")
}
def test_fd_delta_matches_analytic_itm() -> unit ! { Test } = {
  ok = fd_delta_matches_analytic(cast(120.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32))
  assert_close(to01(ok), cast(1.0, f32), cast(0.001, f32), "FD call delta matches N(d1) ITM (S=120)")
}
def test_fd_delta_matches_analytic_otm() -> unit ! { Test } = {
  ok = fd_delta_matches_analytic(cast(80.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32))
  assert_close(to01(ok), cast(1.0, f32), cast(0.001, f32), "FD call delta matches N(d1) OTM (S=80)")
}
def test_mc_matches_textbook_mc_reference() -> unit ! { Test } = {
  template = to_tensor(map(fn (i: int64) -> cast(0.0, f32), range(cast(0, int64), cast(2000, int64))))
  ok = mc_matches_textbook_mc_reference(template, cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32))
  assert_close(to01(ok), cast(1.0, f32), cast(0.001, f32), "optimized MC agrees with scalar textbook MC reference within 5%")
}
