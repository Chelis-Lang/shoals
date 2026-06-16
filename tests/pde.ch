module Shoals.Tests.Pde
import Std.Test (assert_close)
import Shoals.Pde (pde_thomas_solve)
def pde_t_at(xs: List[f32], i: int64) -> f32 = index(xs, cast(i, int64))
def test_thomas_solve_spd_tridiagonal_exact() -> unit ! { Test } = {
  lower = [cast(0.0, f32), cast(1.0, f32), cast(1.0, f32)]
  diag = [cast(2.0, f32), cast(2.0, f32), cast(2.0, f32)]
  upper = [cast(1.0, f32), cast(1.0, f32), cast(0.0, f32)]
  b_vec = [cast(4.0, f32), cast(8.0, f32), cast(8.0, f32)]
  x = pde_thomas_solve(lower, diag, upper, b_vec, cast(3, int64))
  _ = assert_close(pde_t_at(x, cast(0, int64)), cast(1.0, f32), cast(0.00001, f32), "Thomas solve: x0 = 1 for the SPD tridiagonal [[2,1,0],[1,2,1],[0,1,2]] x = [4,8,8]")
  _ = assert_close(pde_t_at(x, cast(1, int64)), cast(2.0, f32), cast(0.00001, f32), "Thomas solve: x1 = 2")
  assert_close(pde_t_at(x, cast(2, int64)), cast(3.0, f32), cast(0.00001, f32), "Thomas solve: x2 = 3")
}
def test_thomas_solve_negative_offdiag_exact() -> unit ! { Test } = {
  lower = [cast(0.0, f32), neg(cast(1.0, f32)), neg(cast(1.0, f32))]
  diag = [cast(3.0, f32), cast(3.0, f32), cast(3.0, f32)]
  upper = [neg(cast(1.0, f32)), neg(cast(1.0, f32)), cast(0.0, f32)]
  b_vec = [cast(2.0, f32), cast(1.0, f32), cast(2.0, f32)]
  x = pde_thomas_solve(lower, diag, upper, b_vec, cast(3, int64))
  _ = assert_close(pde_t_at(x, cast(0, int64)), cast(1.0, f32), cast(0.00001, f32), "Thomas solve: x = [1,1,1] for [[3,-1,0],[-1,3,-1],[0,-1,3]] x = [2,1,2] (diagonally dominant, CN operator shape)")
  _ = assert_close(pde_t_at(x, cast(1, int64)), cast(1.0, f32), cast(0.00001, f32), "Thomas solve: x1 = 1")
  assert_close(pde_t_at(x, cast(2, int64)), cast(1.0, f32), cast(0.00001, f32), "Thomas solve: x2 = 1")
}
def test_thomas_solve_diagonal_identity() -> unit ! { Test } = {
  lower = [cast(0.0, f32), cast(0.0, f32)]
  diag = [cast(5.0, f32), cast(4.0, f32)]
  upper = [cast(0.0, f32), cast(0.0, f32)]
  b_vec = [cast(15.0, f32), cast(8.0, f32)]
  x = pde_thomas_solve(lower, diag, upper, b_vec, cast(2, int64))
  _ = assert_close(pde_t_at(x, cast(0, int64)), cast(3.0, f32), cast(0.00001, f32), "Thomas solve degenerates to elementwise b/diag when off-diagonals are zero: x0 = 15/5 = 3")
  assert_close(pde_t_at(x, cast(1, int64)), cast(2.0, f32), cast(0.00001, f32), "x1 = 8/4 = 2")
}
