module Shoals.Tests.CurvesBootstrapIft
import Std.Test (assert_close, assert_true)
import Shoals.Curves (Instrument, deposit, zero_coupon, cur_par_swap, bootstrap_multi, bootstrap_grad_at_solution, bootstrap_grad_diagonal, fd_bump_pillar_rate)
def abs_f32(x: f32) -> f32 = if lt(x, cast(0.0, f32)) then neg(x) else x
def rel_err(a: f32, b: f32) -> f32 = {
  denom = if lt(abs_f32(b), cast(1e-6, f32)) then cast(1e-6, f32) else abs_f32(b)
  div(abs_f32(sub(a, b)), denom)
}
def test_grad_zero_coupon_matches_analytic() -> unit ! { Test } = {
  zc = zero_coupon(cast(2.0, f32), cast(0.9, f32))
  grads = bootstrap_grad_at_solution([zc])
  g0 = index(grads, cast(0, i64))
  expected = neg(div(cast(1.0, f32), mul(cast(2.0, f32), cast(0.9, f32))))
  assert_close(g0, expected, cast(0.0001, f32), "zero-coupon IFT grad = -1/(t*p) at solution")
}
def test_grad_deposit_matches_analytic() -> unit ! { Test } = {
  d = deposit(cast(1.0, f32), cast(0.05, f32))
  grads = bootstrap_grad_at_solution([d])
  g0 = index(grads, cast(0, i64))
  expected = div(cast(1.0, f32), add(cast(1.0, f32), mul(cast(0.05, f32), cast(1.0, f32))))
  assert_close(g0, expected, cast(0.0001, f32), "deposit IFT grad = 1/(1+r*t)")
}
def test_grad_par_swap_single_pillar() -> unit ! { Test } = {
  ps = cur_par_swap(cast(1.0, f32), cast(0.05, f32), cast(1, i64))
  grads = bootstrap_grad_at_solution([ps])
  g0 = index(grads, cast(0, i64))
  out = bootstrap_multi([ps])
  z_solved = index(out.1, cast(0, i64))
  e_neg_zt = exp(neg(mul(z_solved, cast(1.0, f32))))
  dF_dr = e_neg_zt
  dF_dz = neg(mul(cast(1.0, f32), mul(cast(1.05, f32), e_neg_zt)))
  expected = neg(div(dF_dr, dF_dz))
  assert_close(g0, expected, cast(0.0001, f32), "1y par-swap IFT grad matches -dF/dr / dF/dz")
}
def test_grad_well_conditioned_vs_fd() -> unit ! { Test } = {
  insts = [zero_coupon(cast(1.0, f32), cast(0.95, f32)), zero_coupon(cast(2.0, f32), cast(0.9, f32)), zero_coupon(cast(3.0, f32), cast(0.85, f32))]
  grads = bootstrap_grad_at_solution(insts)
  g0 = index(grads, cast(0, i64))
  fd0 = fd_bump_pillar_rate(index(insts, cast(0, i64)), [], [], cast(0.0001, f32))
  err = rel_err(g0, fd0)
  assert_true(lt(err, cast(0.01, f32)), "well-conditioned: IFT-FD agree within 1% on pillar 0")
}
def test_grad_well_conditioned_three_pillars_fd_agreement() -> unit ! { Test } = {
  insts = [zero_coupon(cast(1.0, f32), cast(0.95, f32)), zero_coupon(cast(2.0, f32), cast(0.9, f32)), zero_coupon(cast(3.0, f32), cast(0.85, f32))]
  grads = bootstrap_grad_at_solution(insts)
  g2 = index(grads, cast(2, i64))
  out = bootstrap_multi(insts)
  ts2 = [index(out.0, cast(0, i64)), index(out.0, cast(1, i64))]
  rs2 = [index(out.1, cast(0, i64)), index(out.1, cast(1, i64))]
  fd2 = fd_bump_pillar_rate(index(insts, cast(2, i64)), ts2, rs2, cast(0.0001, f32))
  err = rel_err(g2, fd2)
  assert_true(lt(err, cast(0.02, f32)), "well-conditioned: IFT-FD agree within 2% on pillar 2 (same f32+brent precision floor as the FD-step-size probe)")
}
def test_grad_near_collinear_finite_and_bounded() -> unit ! { Test } = {
  insts = [zero_coupon(cast(1.0, f32), cast(0.95, f32)), zero_coupon(cast(1.001, f32), cast(0.949, f32))]
  grads = bootstrap_grad_at_solution(insts)
  g0 = index(grads, cast(0, i64))
  g1 = index(grads, cast(1, i64))
  finite0 = lt(abs_f32(g0), cast(1000.0, f32))
  finite1 = lt(abs_f32(g1), cast(1000.0, f32))
  _ = assert_true(finite0, "near-collinear: pillar 0 IFT diagonal sensitivity is finite")
  assert_true(finite1, "near-collinear: pillar 1 IFT diagonal sensitivity is finite")
}
def test_grad_fd_step_size_stability() -> unit ! { Test } = {
  inst = zero_coupon(cast(2.0, f32), cast(0.9, f32))
  ift_grad = bootstrap_grad_diagonal(inst, [], [], div(neg(log(cast(0.9, f32))), cast(2.0, f32)))
  fd_e2 = fd_bump_pillar_rate(inst, [], [], cast(0.01, f32))
  fd_e4 = fd_bump_pillar_rate(inst, [], [], cast(0.0001, f32))
  fd_e6 = fd_bump_pillar_rate(inst, [], [], cast(1e-6, f32))
  err_e4 = rel_err(ift_grad, fd_e4)
  spread = sub(if gt(fd_e2, fd_e6) then fd_e2 else fd_e6, if lt(fd_e2, fd_e6) then fd_e2 else fd_e6)
  _ = assert_true(lt(err_e4, cast(0.02, f32)), "IFT is stable: matches FD@1e-4 within 2% (f32 + brent-1e-7 precision floor on a 2-step finite-difference of a brent-solved scalar)")
  assert_true(lt(abs_f32(spread), cast(10.0, f32)), "FD across coarse/fine steps stays in a reasonable range (no NaN/Inf)")
}
def test_grad_at_parameter_lower_bound_finite() -> unit ! { Test } = {
  d_zero_rate = deposit(cast(1.0, f32), cast(0.0, f32))
  grads = bootstrap_grad_at_solution([d_zero_rate])
  g0 = index(grads, cast(0, i64))
  expected = div(cast(1.0, f32), cast(1.0, f32))
  _ = assert_close(g0, expected, cast(0.0001, f32), "deposit at r=0 lower bound: IFT diag is 1/(1+0*t) = 1")
  assert_true(lt(abs_f32(g0), cast(100.0, f32)), "parameter-at-bound: gradient stays bounded")
}
def test_grad_high_rate_within_bracket() -> unit ! { Test } = {
  d = deposit(cast(1.0, f32), cast(2.0, f32))
  grads = bootstrap_grad_at_solution([d])
  g0 = index(grads, cast(0, i64))
  expected = div(cast(1.0, f32), add(cast(1.0, f32), mul(cast(2.0, f32), cast(1.0, f32))))
  _ = assert_close(g0, expected, cast(0.001, f32), "200% deposit lands inside [-0.5, 2.0] brent bracket (implied zero ~110%) and gradient is analytic")
  assert_true(eq(g0, g0), "gradient is finite (not NaN) under high-but-in-bracket stress")
}
def test_grad_out_of_bracket_propagates_nan_observably() -> unit ! { Test } = {
  d = deposit(cast(1.0, f32), cast(50.0, f32))
  grads = bootstrap_grad_at_solution([d])
  g0 = index(grads, cast(0, i64))
  is_nan = if eq(g0, g0) then false else true
  is_zero = eq(g0, cast(0.0, f32))
  assert_true(if is_nan then true else is_zero, "deposit r=5000% (implied zero ~log(51)≈3.93 outside [-0.5, 2.0]) returns observably degenerate value (NaN or 0); silent garbage is prevented because the caller can test eq(g, g)")
}
def test_grad_pathological_pillar_returns_finite_or_documented() -> unit ! { Test } = {
  -- Duplicate tenors now fail loudly (tests_neg/curves/bootstrap_duplicate_tenor_neg.ch),
  -- so the pathological case here is extreme but valid spacing: 0.01y then 50y.
  zc1 = zero_coupon(cast(0.01, f32), cast(0.9996, f32))
  zc2 = zero_coupon(cast(50.0, f32), cast(0.1, f32))
  grads = bootstrap_grad_at_solution([zc1, zc2])
  g0 = index(grads, cast(0, i64))
  g1 = index(grads, cast(1, i64))
  exp_g0 = neg(div(cast(1.0, f32), mul(cast(0.01, f32), cast(0.9996, f32))))
  exp_g1 = neg(div(cast(1.0, f32), mul(cast(50.0, f32), cast(0.1, f32))))
  _ = assert_true(lt(abs_f32(div(sub(g0, exp_g0), exp_g0)), cast(0.001, f32)), "extreme spacing pillar 0 (0.01y): diagonal IFT matches analytic within 0.1%")
  assert_close(g1, exp_g1, cast(0.0001, f32), "extreme spacing pillar 1 (50y): diagonal IFT matches analytic (no silent garbage)")
}
