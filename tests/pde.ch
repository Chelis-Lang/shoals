module Shoals.Tests.Pde
import Std.Test (assert_close)
import Shoals.Pde (pde_thomas_solve, pde_spread_option_adi)
def pde_t_at(xs: List[f32], i: i64) -> f32 = index(xs, cast(i, i64))
def test_thomas_solve_spd_tridiagonal_exact() -> unit ! { Test } = {
  lower = [cast(0.0, f32), cast(1.0, f32), cast(1.0, f32)]
  diag = [cast(2.0, f32), cast(2.0, f32), cast(2.0, f32)]
  upper = [cast(1.0, f32), cast(1.0, f32), cast(0.0, f32)]
  b_vec = [cast(4.0, f32), cast(8.0, f32), cast(8.0, f32)]
  x = pde_thomas_solve(lower, diag, upper, b_vec, cast(3, i64))
  _ = assert_close(pde_t_at(x, cast(0, i64)), cast(1.0, f32), cast(0.00001, f32), "Thomas solve: x0 = 1 for the SPD tridiagonal [[2,1,0],[1,2,1],[0,1,2]] x = [4,8,8]")
  _ = assert_close(pde_t_at(x, cast(1, i64)), cast(2.0, f32), cast(0.00001, f32), "Thomas solve: x1 = 2")
  assert_close(pde_t_at(x, cast(2, i64)), cast(3.0, f32), cast(0.00001, f32), "Thomas solve: x2 = 3")
}
def test_thomas_solve_negative_offdiag_exact() -> unit ! { Test } = {
  lower = [cast(0.0, f32), neg(cast(1.0, f32)), neg(cast(1.0, f32))]
  diag = [cast(3.0, f32), cast(3.0, f32), cast(3.0, f32)]
  upper = [neg(cast(1.0, f32)), neg(cast(1.0, f32)), cast(0.0, f32)]
  b_vec = [cast(2.0, f32), cast(1.0, f32), cast(2.0, f32)]
  x = pde_thomas_solve(lower, diag, upper, b_vec, cast(3, i64))
  _ = assert_close(pde_t_at(x, cast(0, i64)), cast(1.0, f32), cast(0.00001, f32), "Thomas solve: x = [1,1,1] for [[3,-1,0],[-1,3,-1],[0,-1,3]] x = [2,1,2] (diagonally dominant, CN operator shape)")
  _ = assert_close(pde_t_at(x, cast(1, i64)), cast(1.0, f32), cast(0.00001, f32), "Thomas solve: x1 = 1")
  assert_close(pde_t_at(x, cast(2, i64)), cast(1.0, f32), cast(0.00001, f32), "Thomas solve: x2 = 1")
}
def test_thomas_solve_diagonal_identity() -> unit ! { Test } = {
  lower = [cast(0.0, f32), cast(0.0, f32)]
  diag = [cast(5.0, f32), cast(4.0, f32)]
  upper = [cast(0.0, f32), cast(0.0, f32)]
  b_vec = [cast(15.0, f32), cast(8.0, f32)]
  x = pde_thomas_solve(lower, diag, upper, b_vec, cast(2, i64))
  _ = assert_close(pde_t_at(x, cast(0, i64)), cast(3.0, f32), cast(0.00001, f32), "Thomas solve degenerates to elementwise b/diag when off-diagonals are zero: x0 = 15/5 = 3")
  assert_close(pde_t_at(x, cast(1, i64)), cast(2.0, f32), cast(0.00001, f32), "x1 = 8/4 = 2")
}
-- Independent Margrabe values; rho=0 would miss a halved mixed derivative.
def test_spread_adi_positive_correlation_exchange() -> unit ! { Test } = {
  px = pde_spread_option_adi(100.0f32, 100.0f32, 0.0f32, 0.0f32, 0.0f32, 0.0f32, 0.2f32, 0.2f32, 0.5f32, 1.0f32, 21i64, 21i64, 20i64)
  assert_close(px, 7.9655675f32, 0.15f32, "Correlated exchange must use the full rho*sigma1*sigma2 mixed derivative")
}
def test_spread_adi_negative_correlation_exchange() -> unit ! { Test } = {
  px = pde_spread_option_adi(100.0f32, 100.0f32, 0.0f32, 0.0f32, 0.0f32, 0.0f32, 0.2f32, 0.2f32, -0.8f32, 1.0f32, 31i64, 31i64, 40i64)
  assert_close(px, 15.048451f32, 0.15f32, "Negative correlation increases exchange-option volatility")
}
def test_spread_adi_expiry_exact() -> unit ! { Test } = {
  px = pde_spread_option_adi(110.0f32, 95.0f32, 5.0f32, 0.05f32, 0.02f32, 0.01f32, 0.2f32, 0.3f32, 0.5f32, 0.0f32, 3i64, 3i64, 1i64)
  assert_close(px, 10.0f32, 1e-6f32, "At expiry return intrinsic directly without log-grid roundoff")
}
def test_spread_adi_positive_correlation_property_corner() -> unit ! { Test } = {
  px = pde_spread_option_adi(4.0f32, 4.0f32, 0.0f32, 0.0f32, 0.0f32, 0.0f32, 0.2f32, 0.2f32, 0.8f32, 1.0f32, 31i64, 31i64, 20i64)
  assert_close(px, 0.201716115396f32, 0.016f32, "The property-domain positive-correlation corner needs the finer fixed budget")
}
