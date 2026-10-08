module Shoals.Tests.StepCountParity
import Std.Test (assert_close)
import Shoals.HullWhite (hw1f_path, hw2f_path)
import Shoals.SabrPaths (sabr_path_terminal, sabr_paths_terminal)
import Shoals.LiborMarketModel (lmm_path)
import Shoals.Trees (tr_crr_european_call, tr_crr_european_put, tr_crr_american_call, tr_crr_american_put, tr_trinomial_european_call, tr_trinomial_american_put, tr_binom_european_call_generic)
-- Positive parity for the step-count guards outside Shoals.Stochastic, whose
-- own parity case lives in tests/stochastic.ch beside the horizon's.
--
-- `n_steps = 1` is the EXTREMAL admitted value, and on an integer domain that
-- makes the boundary exactly pinnable in both directions: a tests_neg fixture
-- at `n_steps = 0` kills every threshold shifted down, and these cases kill
-- every threshold shifted up, with nothing between the two to leave
-- uncovered. No subnormal argument exists or is needed, unlike the horizon
-- guard's, which required the negative min subnormal to close its family.
--
-- Each row asserts TWO properties, and the first cannot substitute for the
-- second. That `n_steps = 1` is ADMITTED is what a `lt(n_steps, 2)` mutant
-- breaks, and no negative fixture can see that mutant: a guard which refuses
-- a valid input passes every fixture under tests_neg/ while being wrong. That
-- `n_steps = 1` actually COMPUTES, rather than returning the degenerate value
-- the guard refuses, is what distinguishes a real one-step discretisation
-- from the empty-fold identity -- without it a mutant that admitted
-- `n_steps = 1` and then skipped the evolution would still pass.
--
-- Every threshold below sits comfortably inside a MEASURED margin rather than
-- being chosen for roundness, and the measured value is named in each
-- message. The thresholds are deliberately not the measured values
-- themselves: these samplers draw, so pinning an exact draw would make the
-- file a hostage of the RNG rather than a test of the guard.
def tpl8() -> tensor[8, f32] = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(8, i64))))
def fwd3() -> tensor[3, f32] = to_tensor([cast(0.03, f32), cast(0.035, f32), cast(0.04, f32)])
def tau3() -> tensor[3, f32] = to_tensor([cast(0.5, f32), cast(0.5, f32), cast(0.5, f32)])
def vol3() -> tensor[3, f32] = to_tensor([cast(0.2, f32), cast(0.2, f32), cast(0.2, f32)])
def corr3() -> tensor[3, 3, f32] = reshape(to_tensor([cast(1.0, f32), cast(0.9, f32), cast(0.8, f32), cast(0.9, f32), cast(1.0, f32), cast(0.9, f32), cast(0.8, f32), cast(0.9, f32), cast(1.0, f32)]), [cast(3, i64), cast(3, i64)])
def one_step() -> i64 = cast(1, i64)
def abs_f32(x: f32) -> f32 = if lt(x, cast(0.0, f32)) then neg(x) else x
def moved_past(value: f32, degenerate: f32, margin: f32) -> f32 = if gt(abs_f32(sub(value, degenerate)), margin) then cast(1.0, f32) else cast(0.0, f32)
def tol() -> f32 = cast(0.001, f32)
def yes() -> f32 = cast(1.0, f32)
def test_one_step_is_admitted_by_every_path_sampler() -> unit ! { Test } = {
  hw1 = tensor_to_scalar(sum(hw1f_path(key_from_seed(7i64), tpl8(), cast(0.03, f32), cast(0.1, f32), cast(0.03, f32), cast(0.01, f32), cast(1.0, f32), one_step()), 0))
  _ = assert_close(moved_past(hw1, cast(0.24, f32), cast(0.005, f32)), yes(), tol(), "hw1f_path at n_steps = 1 must be admitted and must evolve off 8*r0 = 0.24; measured 0.25435907, a move of 0.0144")
  hw2 = tensor_to_scalar(sum(hw2f_path(key_from_seed(7i64), tpl8(), cast(0.02, f32), cast(0.01, f32), cast(0.1, f32), cast(0.2, f32), cast(0.01, f32), cast(0.005, f32), cast(-0.3, f32), cast(1.0, f32), one_step()).0, 0))
  _ = assert_close(moved_past(hw2, cast(0.16, f32), cast(0.01, f32)), yes(), tol(), "hw2f_path at n_steps = 1 must be admitted and must evolve off 8*x0 = 0.16; measured 0.11728811, a move of 0.0427")
  sabr_one = sabr_path_terminal(key_from_seed(7i64), cast(100.0, f32), cast(0.2, f32), cast(0.5, f32), cast(-0.3, f32), cast(0.4, f32), cast(1.0, f32), one_step()).0
  _ = assert_close(moved_past(sabr_one, cast(100.0, f32), cast(0.5, f32)), yes(), tol(), "sabr_path_terminal at n_steps = 1 must be admitted and must evolve off f0 = 100.0; measured 97.57341, a move of 2.43")
  sabr_many = tensor_to_scalar(sum(sabr_paths_terminal(key_from_seed(7i64), tpl8(), cast(100.0, f32), cast(0.2, f32), cast(0.5, f32), cast(-0.3, f32), cast(0.4, f32), cast(1.0, f32), one_step()).0, 0))
  _ = assert_close(moved_past(sabr_many, cast(800.0, f32), cast(1.0, f32)), yes(), tol(), "sabr_paths_terminal at n_steps = 1 must be admitted and must evolve off 8*f0 = 800.0; measured 794.1997, a move of 5.80")
  lmm = tensor_to_scalar(sum(lmm_path(key_from_seed(7i64), tpl8(), fwd3(), tau3(), vol3(), corr3(), cast(1.0, f32), one_step(), cast(0, i64)), 0))
  assert_close(moved_past(lmm, cast(0.24, f32), cast(0.005, f32)), yes(), tol(), "lmm_path at n_steps = 1 must be admitted and must evolve off 8*0.03 = 0.24; measured 0.21946523, a move of 0.0205")
}
def test_one_step_is_admitted_by_every_lattice_pricer() -> unit ! { Test } = {
  s0 = cast(100.0, f32)
  r = cast(0.05, f32)
  q = cast(0.0, f32)
  vol = cast(0.2, f32)
  t = cast(1.0, f32)
  itm_call = cast(90.0, f32)
  itm_put = cast(110.0, f32)
  zero = cast(0.0, f32)
  margin = cast(0.5, f32)
  _ = assert_close(moved_past(tr_crr_european_call(s0, itm_call, r, q, vol, t, one_step()), zero, margin), yes(), tol(), "tr_crr_european_call at n_steps = 1 must be admitted and must price above the flat 0.0 the guard refuses; measured 17.655567")
  _ = assert_close(moved_past(tr_crr_european_put(s0, itm_put, r, q, vol, t, one_step()), zero, margin), yes(), tol(), "tr_crr_european_put at n_steps = 1 must be admitted and must price above the flat 0.0 the guard refuses; measured 11.304237")
  _ = assert_close(moved_past(tr_crr_american_call(s0, itm_call, r, q, vol, t, one_step()), zero, margin), yes(), tol(), "tr_crr_american_call at n_steps = 1 must be admitted and must price above the flat 0.0 the guard refuses; measured 17.655567")
  _ = assert_close(moved_past(tr_crr_american_put(s0, itm_put, r, q, vol, t, one_step()), zero, margin), yes(), tol(), "tr_crr_american_put at n_steps = 1 must be admitted and must price above the flat 0.0 the guard refuses; measured 11.304237")
  _ = assert_close(moved_past(tr_trinomial_european_call(s0, itm_call, r, q, vol, t, one_step()), zero, margin), yes(), tol(), "tr_trinomial_european_call at n_steps = 1 must be admitted and must price above the flat 0.0 the guard refuses; measured 16.607182")
  _ = assert_close(moved_past(tr_trinomial_american_put(s0, itm_put, r, q, vol, t, one_step()), zero, margin), yes(), tol(), "tr_trinomial_american_put at n_steps = 1 must be admitted and must price above the flat 0.0 the guard refuses; measured 10.950728")
  assert_close(moved_past(tr_binom_european_call_generic(s0, s0, cast(0.025, f32), cast(-0.025, f32), cast(0.5, f32), cast(0.99, f32), one_step()), zero, margin), yes(), tol(), "tr_binom_european_call_generic at n_steps = 1 must be admitted and must price above the flat 0.0 the guard refuses; measured 1.253101")
}
-- The sub-floor-volatility rows, which pin the ONE placement decision in this
-- change set that is not uniform.
--
-- Every Shoals.Trees pricer short-circuits a sigma below tr_sigma_floor() to
-- tr_deterministic_call/put, which takes no step count at all and whose
-- answer is therefore independent of it. The guard is placed where `n_steps`
-- ENTERS the computation -- inside each pricer's stochastic branch -- rather
-- than at the pricer's entry, precisely so that path keeps working. Measured
-- at sigma = 1e-9, s0 = 100, t = 1.0: tr_crr_european_call returned
-- 14.389351 at K = 90 and tr_crr_american_put returned 4.6352386 at K = 110,
-- identically at n_steps 0, 64 and -8.
--
-- Without these rows the sub-floor behaviour is defended by nothing, and the
-- obvious "tidying" refactor -- hoisting the guard to each pricer's entry for
-- uniformity -- would silently refuse three correct answers per pricer while
-- leaving every tests_neg fixture green. That is the same shape as a guard
-- written `gt(t, 0.0)` passing every negative horizon fixture while refusing
-- a valid zero horizon.
def test_sub_floor_volatility_prices_at_any_step_count() -> unit ! { Test } = {
  s0 = cast(100.0, f32)
  r = cast(0.05, f32)
  q = cast(0.0, f32)
  flat = cast(1e-9, f32)
  t = cast(1.0, f32)
  price_tol = cast(0.001, f32)
  zero_steps = cast(0, i64)
  neg_steps = cast(-8, i64)
  _ = assert_close(tr_crr_european_call(s0, cast(90.0, f32), r, q, flat, t, zero_steps), cast(14.389351, f32), price_tol, "a sub-floor volatility must still price at n_steps = 0: that path never reads the step count")
  _ = assert_close(tr_crr_european_call(s0, cast(90.0, f32), r, q, flat, t, neg_steps), cast(14.389351, f32), price_tol, "a sub-floor volatility must still price at n_steps = -8: the deterministic answer is independent of the step count")
  _ = assert_close(tr_crr_american_put(s0, cast(110.0, f32), r, q, flat, t, zero_steps), cast(4.6352386, f32), price_tol, "a sub-floor volatility must still price the American put at n_steps = 0")
  assert_close(tr_trinomial_european_call(s0, cast(90.0, f32), r, q, flat, t, zero_steps), cast(14.389351, f32), price_tol, "a sub-floor volatility must still price the trinomial call at n_steps = 0")
}
-- The zero-depth rows, which pin a documented answer an earlier revision of
-- this change destroyed.
--
-- `tr_binom_european_call_generic` takes its log-moves, up probability and
-- discount factor already computed, so it never forms `dt = t / n_steps` and
-- a depth of zero is not a division by zero for it. The terminal layer is
-- then the single node `s0` and the price is the intrinsic value. That is the
-- documented contract, and it is correct: measured at s0 = 100, log_u = 0.025,
-- log_d = -0.025, p = 0.5, disc = 0.99, a depth of zero returns exactly the
-- intrinsic at each strike.
--
-- A first revision of this change applied the pricers' `n_steps < 1` check
-- here too, on the mistaken reading that the pricers' flat 0.0 came from a
-- zero-step backward induction rather than from a non-finite `dt`. It
-- refused all three answers below. Nothing in the negative fixture set could
-- see that, because refusing MORE never fails a test that expects a refusal;
-- only a positive case can. These rows are that case, and the strikes are
-- deliberately off the money: at K = 100 = s0 the intrinsic is 0.0, which a
-- broken implementation returning a flat zero also produces, so an
-- at-the-money row would pass either way.
def test_zero_depth_generic_returns_the_intrinsic() -> unit ! { Test } = {
  s0 = cast(100.0, f32)
  up = cast(0.025, f32)
  down = cast(-0.025, f32)
  prob = cast(0.5, f32)
  disc = cast(0.99, f32)
  depth = cast(0, i64)
  exact = cast(0.0001, f32)
  _ = assert_close(tr_binom_european_call_generic(s0, cast(90.0, f32), up, down, prob, disc, depth), cast(10.0, f32), exact, "a zero-depth generic lattice must return the intrinsic 10.0 at K = 90, not a flat zero")
  _ = assert_close(tr_binom_european_call_generic(s0, cast(110.0, f32), up, down, prob, disc, depth), cast(0.0, f32), exact, "a zero-depth generic lattice must return the intrinsic 0.0 at K = 110")
  assert_close(tr_binom_european_call_generic(s0, s0, up, down, prob, disc, depth), cast(0.0, f32), exact, "a zero-depth generic lattice must return the intrinsic 0.0 at K = s0; this row alone cannot distinguish a correct answer from a flat zero, which is why the two above are off the money")
}
