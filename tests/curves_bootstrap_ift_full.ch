module Shoals.Tests.CurvesBootstrapIftFull
import Std.Test (assert_close, assert_true)
import Shoals.Curves (Instrument, Deposit, ZeroCoupon, ParSwap, deposit, zero_coupon, cur_par_swap, bootstrap_multi, bootstrap_grad_at_solution, bootstrap_grad_full_jacobian, instrument_validate)
def cbif_abs_f32(x: f32) -> f32 = if lt(x, cast(0.0, f32)) then neg(x) else x
def cbif_rel_err(a: f32, b: f32) -> f32 = {
  denom = if lt(cbif_abs_f32(b), cast(1e-6, f32)) then cast(1e-6, f32) else cbif_abs_f32(b)
  div(cbif_abs_f32(sub(a, b)), denom)
}
def cbif_template_5() -> tensor[5, f32] = to_tensor([cast(0.0, f32), cast(0.0, f32), cast(0.0, f32), cast(0.0, f32), cast(0.0, f32)])
def cbif_template_3() -> tensor[3, f32] = to_tensor([cast(0.0, f32), cast(0.0, f32), cast(0.0, f32)])
def cbif_template_2() -> tensor[2, f32] = to_tensor([cast(0.0, f32), cast(0.0, f32)])
def cbif_bump_jth(instruments: List[Instrument], j: i64, step: f32) -> List[Instrument] = {
  idxs = range(cast(0, i64), cast(len(instruments), i64))
  pairs = zip(idxs, instruments)
  map(fn (entry: (i64, Instrument)) -> {
    i = entry.0
    inst = entry.1
    if eq(i, j) then match inst with {
      | Deposit { tenor: t, rate: r } => deposit(t, add(r, step))
      | ZeroCoupon { tenor: t, price: p } => zero_coupon(t, add(p, step))
      | ParSwap { tenor: t, par_rate: r, payments_per_year: f } => cur_par_swap(t, add(r, step), f)
    } else inst
  }, pairs)
}
def cbif_fd_column(instruments: List[Instrument], j: i64, step: f32) -> List[f32] = {
  down = bootstrap_multi(cbif_bump_jth(instruments, j, neg(step))).1
  up = bootstrap_multi(cbif_bump_jth(instruments, j, step)).1
  pairs = zip(down, up)
  map(fn (e: (f32, f32)) -> div(sub(e.1, e.0), mul(cast(2.0, f32), step)), pairs)
}
def test_full_jacobian_diagonal_only_for_zero_coupons() -> unit ! { Test } = {
  insts = [zero_coupon(cast(1.0, f32), cast(0.95, f32)), zero_coupon(cast(2.0, f32), cast(0.9, f32)), zero_coupon(cast(3.0, f32), cast(0.85, f32))]
  jac = bootstrap_grad_full_jacobian(copy(cbif_template_3()), insts)
  flat = to_list(reshape(jac, [cast(9, i64)]))
  off_diag_idxs = [cast(1, i64), cast(2, i64), cast(3, i64), cast(5, i64), cast(6, i64), cast(7, i64)]
  off_diag_max = fold(fn (acc: f32, k: i64) -> {
    v = cbif_abs_f32(index(flat, k))
    if gt(v, acc) then v else acc
  }, cast(0.0, f32), off_diag_idxs)
  assert_true(lt(off_diag_max, cast(1e-6, f32)), "all-zero-coupon Jacobian: off-diagonal entries are zero (residuals are pillar-local)")
}
def test_full_jacobian_par_swap_off_diagonal_nonzero() -> unit ! { Test } = {
  insts = [deposit(cast(1.0, f32), cast(0.05, f32)), cur_par_swap(cast(2.0, f32), cast(0.04, f32), cast(1, i64))]
  jac = bootstrap_grad_full_jacobian(copy(cbif_template_2()), insts)
  flat = to_list(reshape(jac, [cast(4, i64)]))
  j_10 = index(flat, cast(2, i64))
  j_01 = index(flat, cast(1, i64))
  j_00 = index(flat, cast(0, i64))
  j_11 = index(flat, cast(3, i64))
  is_finite_10 = eq(j_10, j_10)
  is_nonzero_10 = gt(cbif_abs_f32(j_10), cast(0.001, f32))
  is_zero_01 = lt(cbif_abs_f32(j_01), cast(1e-6, f32))
  _ = assert_true(is_finite_10, "J[1, 0] = dz_1/dx_0 is finite for deposit+par-swap")
  _ = assert_true(is_nonzero_10, "J[1, 0] = dz_1/dx_0 is non-trivially non-zero (the par-swap fixed leg discounts its 1y coupon at pillar 0)")
  _ = assert_true(is_zero_01, "J[0, 1] = dz_0/dx_1 is zero (deposit pillar 0 does not depend on later par-swap rate)")
  _ = assert_true(lt(j_10, cast(0.0, f32)), "J[1, 0] sign: raising deposit rate raises z_0, lowers the 1y coupon discount factor, lowers required z_1 (negative)")
  _ = assert_close(j_00, div(cast(1.0, f32), cast(1.05, f32)), cast(0.001, f32), "J[0, 0] = 1/(1+r*t) for deposit pillar")
  assert_true(gt(j_11, cast(0.0, f32)), "J[1, 1] > 0 (raising par_rate raises implied z_1 in this regime)")
}
def cbif_entry_ok(api_val: f32, fd_val: f32, rel_tol: f32, abs_tol: f32) -> bool = {
  abs_diff = cbif_abs_f32(sub(api_val, fd_val))
  if lt(abs_diff, abs_tol) then true else lt(cbif_rel_err(api_val, fd_val), rel_tol)
}
def test_full_jacobian_matches_fd_bump() -> unit ! { Test } = {
  insts = [zero_coupon(cast(0.5, f32), cast(0.98, f32)), deposit(cast(1.0, f32), cast(0.04, f32)), cur_par_swap(cast(2.0, f32), cast(0.045, f32), cast(1, i64)), cur_par_swap(cast(3.0, f32), cast(0.05, f32), cast(1, i64)), cur_par_swap(cast(5.0, f32), cast(0.055, f32), cast(1, i64))]
  jac = bootstrap_grad_full_jacobian(copy(cbif_template_5()), insts)
  flat = to_list(reshape(jac, [cast(25, i64)]))
  step = cast(0.01, f32)
  col_idxs = range(cast(0, i64), cast(5, i64))
  per_col_ok = map(fn (j: i64) -> {
    fd_col = cbif_fd_column(insts, j, step)
    row_idxs = range(cast(0, i64), cast(5, i64))
    per_row_ok = map(fn (i: i64) -> {
      flat_idx = add(mul(i, cast(5, i64)), j)
      api_val = index(flat, flat_idx)
      fd_val = index(fd_col, i)
      cbif_entry_ok(api_val, fd_val, cast(0.02, f32), cast(0.0001, f32))
    }, row_idxs)
    fold(fn (acc: bool, b: bool) -> if acc then b else false, true, per_row_ok)
  }, col_idxs)
  all_ok = fold(fn (acc: bool, b: bool) -> if acc then b else false, true, per_col_ok)
  assert_true(all_ok, "well-conditioned 5-instrument bootstrap (0.5y zero-coupon, 1y deposit, 2y/3y/5y annual swaps): full IFT Jacobian agrees with a central-difference FD Jacobian within 2% relative or 1e-4 absolute per entry (FD step = 1e-2; central differences keep truncation error near 1e-4 while brent-1e-7 + f32 noise stays near 1e-5, whereas a forward step small enough to bound truncation is swamped by that noise on the off-diagonal entries)")
}
def test_full_jacobian_diagonal_matches_diagonal_helper() -> unit ! { Test } = {
  insts = [zero_coupon(cast(0.5, f32), cast(0.98, f32)), deposit(cast(1.0, f32), cast(0.04, f32)), cur_par_swap(cast(2.0, f32), cast(0.045, f32), cast(1, i64)), cur_par_swap(cast(3.0, f32), cast(0.05, f32), cast(1, i64)), cur_par_swap(cast(5.0, f32), cast(0.055, f32), cast(1, i64))]
  jac = bootstrap_grad_full_jacobian(copy(cbif_template_5()), insts)
  diag_list = bootstrap_grad_at_solution(insts)
  flat = to_list(reshape(jac, [cast(25, i64)]))
  row_idxs = range(cast(0, i64), cast(5, i64))
  per_row_ok = map(fn (i: i64) -> {
    flat_idx = add(mul(i, cast(5, i64)), i)
    full_diag = index(flat, flat_idx)
    helper_diag = index(diag_list, i)
    lt(cbif_abs_f32(sub(full_diag, helper_diag)), cast(0.0001, f32))
  }, row_idxs)
  all_ok = fold(fn (acc: bool, b: bool) -> if acc then b else false, true, per_row_ok)
  assert_true(all_ok, "full Jacobian diagonal entries match bootstrap_grad_at_solution within 1e-4 on a 5-instrument curve")
}
def test_instrument_validate_rejects_negative_tenor() -> unit ! { Test } = {
  bad_dep = deposit(cast(-0.5, f32), cast(0.05, f32))
  bad_zc_tenor = zero_coupon(cast(-1.0, f32), cast(0.9, f32))
  bad_ps_tenor = cur_par_swap(cast(-2.0, f32), cast(0.04, f32), cast(1, i64))
  _ = assert_true(if instrument_validate(bad_dep) then false else true, "deposit with negative tenor is invalid")
  _ = assert_true(if instrument_validate(bad_zc_tenor) then false else true, "zero-coupon with negative tenor is invalid")
  assert_true(if instrument_validate(bad_ps_tenor) then false else true, "par-swap with negative tenor is invalid")
}
def test_instrument_validate_rejects_bad_zero_coupon_price() -> unit ! { Test } = {
  zc_neg = zero_coupon(cast(1.0, f32), cast(-0.1, f32))
  zc_zero = zero_coupon(cast(1.0, f32), cast(0.0, f32))
  zc_above_one = zero_coupon(cast(1.0, f32), cast(1.5, f32))
  zc_ok = zero_coupon(cast(1.0, f32), cast(0.95, f32))
  _ = assert_true(if instrument_validate(zc_neg) then false else true, "zero-coupon with negative price is invalid")
  _ = assert_true(if instrument_validate(zc_zero) then false else true, "zero-coupon with zero price is invalid (would imply infinite zero rate)")
  _ = assert_true(if instrument_validate(zc_above_one) then false else true, "zero-coupon with price > 1 is invalid (implies negative zero rate beyond design)")
  assert_true(instrument_validate(zc_ok), "zero-coupon with price 0.95 is valid")
}
def test_instrument_validate_rejects_deposit_rate_below_minus_one() -> unit ! { Test } = {
  bad = deposit(cast(1.0, f32), cast(-1.0, f32))
  worse = deposit(cast(1.0, f32), cast(-1.5, f32))
  ok = deposit(cast(1.0, f32), cast(-0.5, f32))
  _ = assert_true(if instrument_validate(bad) then false else true, "deposit with r = -1 is invalid (1+r*t = 0)")
  _ = assert_true(if instrument_validate(worse) then false else true, "deposit with r < -1 is invalid (1+r*t < 0)")
  assert_true(instrument_validate(ok), "deposit with r = -0.5 (mildly negative) is valid")
}
-- Positive counterpart to the three new
-- `tests_neg/curves/full_jacobian_*_neg.ch` cases (shoals#79). It replaces
-- `test_full_jacobian_returns_nan_for_invalid_input`, which asserted the
-- sentinel those cases now reject; this pins that the length-matched,
-- valid-instrument call the guard has to let through still returns the same
-- finite Jacobian it did before the guard existed.
def test_full_jacobian_accepts_matching_template_and_valid_instruments() -> unit ! { Test } = {
  insts = [zero_coupon(cast(1.0, f32), cast(0.95, f32)), zero_coupon(cast(2.0, f32), cast(0.9, f32))]
  jac = bootstrap_grad_full_jacobian(copy(cbif_template_2()), insts)
  flat = to_list(reshape(jac, [cast(4, i64)]))
  all_finite = fold(fn (acc: bool, k: i64) -> {
    v = index(flat, k)
    if acc then eq(v, v) else false
  }, true, range(cast(0, i64), cast(4, i64)))
  _ = assert_true(all_finite, "a two-wide template with two valid instruments returns a finite Jacobian")
  _ = assert_close(index(flat, cast(0, i64)), neg(div(cast(1.0, f32), mul(cast(1.0, f32), cast(0.95, f32)))), cast(0.001, f32), "J[0, 0] = -1/(t*p) for the 1y zero-coupon pillar")
  assert_close(index(flat, cast(3, i64)), neg(div(cast(1.0, f32), mul(cast(2.0, f32), cast(0.9, f32)))), cast(0.001, f32), "J[1, 1] = -1/(t*p) for the 2y zero-coupon pillar")
}
def test_instrument_validate_zc_price_boundary() -> unit ! { Test } = {
  _ = assert_true(instrument_validate(zero_coupon(cast(1.0, f32), cast(1.0, f32))), "ZC at exactly price=1.0 is accepted (z=0 is in brent bracket)")
  _ = assert_true(not(instrument_validate(zero_coupon(cast(1.0, f32), cast(1.0001, f32)))), "ZC at price>1 is rejected")
  assert_true(instrument_validate(zero_coupon(cast(1.0, f32), cast(0.001, f32))), "ZC at very small positive price is accepted")
}
def test_instrument_validate_deposit_rate_boundary() -> unit ! { Test } = {
  _ = assert_true(not(instrument_validate(deposit(cast(1.0, f32), cast(-1.0, f32)))), "Deposit at r=-1 rejected (boundary)")
  assert_true(instrument_validate(deposit(cast(1.0, f32), cast(-0.999, f32))), "Deposit at r=-0.999 accepted")
}
def test_full_jacobian_matches_float64_reference() -> unit ! { Test } = {
  insts = [zero_coupon(cast(0.5, f32), cast(0.98, f32)), deposit(cast(1.0, f32), cast(0.04, f32)), cur_par_swap(cast(2.0, f32), cast(0.045, f32), cast(1, i64)), cur_par_swap(cast(3.0, f32), cast(0.05, f32), cast(1, i64)), cur_par_swap(cast(5.0, f32), cast(0.055, f32), cast(1, i64))]
  flat = to_list(reshape(bootstrap_grad_full_jacobian(copy(cbif_template_5()), insts), [cast(25, i64)]))
  -- Row-major dz_i/dquote_j from an independent float64 model of the
  -- schedule-aware bootstrap (fixed leg over annual coupon dates, zero rates
  -- linear between pillars) whose analytic Jacobian agrees with a 1e-6
  -- float64 finite difference to five decimals.
  expected = [cast(-2.04082, f32), cast(0.0, f32), cast(0.0, f32), cast(0.0, f32), cast(0.0, f32), cast(0.0, f32), cast(0.96154, f32), cast(0.0, f32), cast(0.0, f32), cast(0.0, f32), cast(0.0, f32), cast(-0.02174, f32), cast(0.98098, f32), cast(0.0, f32), cast(0.0, f32), cast(0.0, f32), cast(-0.01627, f32), cast(-0.03304, f32), cast(1.00796, f32), cast(0.0, f32), cast(0.0, f32), cast(-0.01092, f32), cast(-0.02216, f32), cast(-0.05683, f32), cast(1.04954, f32)]
  worst = fold(fn (acc: f32, k: i64) -> {
    d = cbif_abs_f32(sub(index(flat, k), index(expected, k)))
    if gt(d, acc) then d else acc
  }, cast(0.0, f32), range(cast(0, i64), cast(25, i64)))
  assert_true(lt(worst, cast(0.0001, f32)), "full IFT Jacobian matches the float64 reference within 1e-4 per entry, including the off-diagonal coupon-schedule coupling that the one-coupon-per-pillar rule got wrong")
}
def test_full_jacobian_non_annual_matches_float64_reference() -> unit ! { Test } = {
  insts = [deposit(cast(0.5, f32), cast(0.04, f32)), cur_par_swap(cast(1.0, f32), cast(0.042, f32), cast(2, i64)), cur_par_swap(cast(2.0, f32), cast(0.044, f32), cast(2, i64)), cur_par_swap(cast(3.0, f32), cast(0.046, f32), cast(4, i64))]
  template = to_tensor([cast(0.0, f32), cast(0.0, f32), cast(0.0, f32), cast(0.0, f32)])
  flat = to_list(reshape(bootstrap_grad_full_jacobian(template, insts), [cast(16, i64)]))
  -- Row-major dz_i/dquote_j for a 0.5y deposit and 1y/2y semiannual plus 3y
  -- quarterly swaps, from the independent float64 model (analytic Jacobian
  -- within 1.4e-10 of a 1e-6 central difference). Accrual is not 1 here, so
  -- the entries pin the coupon accrual inside the swap derivatives.
  expected = [cast(0.98039, f32), cast(0.0, f32), cast(0.0, f32), cast(0.0, f32), cast(-0.0103, f32), cast(0.99022, f32), cast(0.0, f32), cast(0.0, f32), cast(-0.0054, f32), cast(-0.01918, f32), cast(1.00439, f32), cast(0.0, f32), cast(-0.00431, f32), cast(-0.01349, f32), cast(-0.03143, f32), cast(1.04182, f32)]
  worst = fold(fn (acc: f32, k: i64) -> {
    d = cbif_abs_f32(sub(index(flat, k), index(expected, k)))
    if gt(d, acc) then d else acc
  }, cast(0.0, f32), range(cast(0, i64), cast(16, i64)))
  assert_true(lt(worst, cast(0.0001, f32)), "semiannual/quarterly full IFT Jacobian matches the float64 reference within 1e-4 per entry")
}
def test_instrument_validate_rejects_nonfinite_quotes() -> unit ! { Test } = {
  nan_q = div(cast(0.0, f32), cast(0.0, f32))
  inf_q = div(cast(1.0, f32), cast(0.0, f32))
  -- shoals#79: every bound in `instrument_validate` is an ordered comparison,
  -- and all of them are false against NaN, so each of these was accepted and
  -- then bootstrapped to a silent NaN pillar. Only the par-swap *tenor* was
  -- checked, by `cur_whole_periods`' own guard.
  _ = assert_true(not(instrument_validate(deposit(cast(1.0, f32), nan_q))), "a NaN deposit rate is invalid")
  _ = assert_true(not(instrument_validate(deposit(nan_q, cast(0.04, f32)))), "a NaN deposit tenor is invalid")
  _ = assert_true(not(instrument_validate(deposit(cast(1.0, f32), inf_q))), "an infinite deposit rate is invalid")
  _ = assert_true(not(instrument_validate(zero_coupon(cast(1.0, f32), nan_q))), "a NaN zero-coupon price is invalid")
  _ = assert_true(not(instrument_validate(zero_coupon(nan_q, cast(0.95, f32)))), "a NaN zero-coupon tenor is invalid")
  _ = assert_true(not(instrument_validate(zero_coupon(cast(1.0, f32), inf_q))), "an infinite zero-coupon price is invalid")
  _ = assert_true(not(instrument_validate(cur_par_swap(cast(2.0, f32), nan_q, cast(1, i64)))), "a NaN par-swap rate is invalid")
  assert_true(not(instrument_validate(cur_par_swap(cast(2.0, f32), inf_q, cast(1, i64)))), "an infinite par-swap rate is invalid")
}
def test_instrument_validate_accepts_finite_quotes_at_the_same_shapes() -> unit ! { Test } = {
  -- The parity side of the rejections above: the finiteness test must not
  -- reject anything the module accepted before shoals#79.
  _ = assert_true(instrument_validate(deposit(cast(1.0, f32), cast(0.04, f32))), "a finite deposit is valid")
  _ = assert_true(instrument_validate(zero_coupon(cast(1.0, f32), cast(0.95, f32))), "a finite zero-coupon is valid")
  assert_true(instrument_validate(cur_par_swap(cast(2.0, f32), cast(0.045, f32), cast(1, i64))), "a finite par swap is valid")
}
def test_instrument_validate_deposit_discount_factor_must_be_positive() -> unit ! { Test } = {
  -- shoals#79: `rate > -1` is the positive-discount-factor condition only at a
  -- one-year tenor. `deposit(2.0, -0.6)` gives `1 + rate * tenor = -0.2`, so
  -- `log(df)` was NaN and the pillar came back NaN with no diagnostic.
  _ = assert_true(not(instrument_validate(deposit(cast(2.0, f32), neg(cast(0.6, f32))))), "a 2y deposit at -60% implies a negative discount factor and is invalid")
  _ = assert_true(not(instrument_validate(deposit(cast(2.0, f32), neg(cast(0.5, f32))))), "a 2y deposit at -50% implies a zero discount factor and is invalid")
  -- Both bounds are kept, so the predicate narrows in both directions and
  -- widens in neither: the tenor-aware bound alone would newly accept a rate
  -- below -1 at a tenor under a year.
  _ = assert_true(not(instrument_validate(deposit(cast(0.5, f32), neg(cast(1.5, f32))))), "a 6m deposit at -150% stays invalid even though 1 + rate * tenor is positive")
  _ = assert_true(instrument_validate(deposit(cast(2.0, f32), neg(cast(0.4, f32)))), "a 2y deposit at -40% keeps a positive discount factor and is valid")
  assert_true(instrument_validate(deposit(cast(10.0, f32), cast(0.05, f32))), "a long-dated deposit at a positive rate is valid")
}
