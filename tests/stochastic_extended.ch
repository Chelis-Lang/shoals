module Shoals.Tests.StochasticExtended
import Std.Test (assert_close, assert_true)
import Nautilus.Stats (mean_vec, std_vec)
import Shoals.Stochastic (merton_compensated_drift, merton_sampler_log_jump_moment, merton_jump_terminal, cholesky_2x2_lower, correlated_gbm_terminal_2d)
def test_merton_compensated_drift_zero_lambda_equals_gbm() -> unit ! { Test } = {
  d = merton_compensated_drift(cast(0.05, f32), cast(0.2, f32), cast(0.0, f32), cast(-0.1, f32), cast(0.1, f32))
  expected = sub(cast(0.05, f32), mul(cast(0.5, f32), mul(cast(0.2, f32), cast(0.2, f32))))
  assert_close(d, expected, cast(1e-6, f32), "lambda=0 reduces Merton drift to GBM drift")
}
def test_merton_compensated_drift_subtracts_expected_jump_contribution() -> unit ! { Test } = {
  d = merton_compensated_drift(cast(0.05, f32), cast(0.2, f32), cast(1.0, f32), cast(0.0, f32), cast(0.1, f32))
  half_sigma_sq = mul(cast(0.5, f32), mul(cast(0.2, f32), cast(0.2, f32)))
  half_jump_vol_sq = mul(cast(0.5, f32), mul(cast(0.1, f32), cast(0.1, f32)))
  expected_jump = sub(exp(add(cast(0.0, f32), half_jump_vol_sq)), cast(1.0, f32))
  expected_d = sub(sub(cast(0.05, f32), half_sigma_sq), mul(cast(1.0, f32), expected_jump))
  assert_close(d, expected_d, cast(1e-6, f32), "lambda=1 subtracts E[exp(J)-1]")
}
def test_cholesky_2x2_identity() -> unit ! { Test } = {
  out = cholesky_2x2_lower(cast(1.0, f32), cast(0.0, f32), cast(1.0, f32))
  _ = assert_close(out.0, cast(1.0, f32), cast(1e-6, f32), "L11 = 1")
  _ = assert_close(out.1, cast(0.0, f32), cast(1e-6, f32), "L21 = 0")
  assert_close(out.2, cast(1.0, f32), cast(1e-6, f32), "L22 = 1")
}
def test_cholesky_2x2_correlated() -> unit ! { Test } = {
  out = cholesky_2x2_lower(cast(4.0, f32), cast(2.0, f32), cast(3.0, f32))
  _ = assert_close(out.0, cast(2.0, f32), cast(1e-6, f32), "L11 = sqrt(4) = 2")
  _ = assert_close(out.1, cast(1.0, f32), cast(1e-6, f32), "L21 = 2/2 = 1")
  assert_close(out.2, sqrt(cast(2.0, f32)), cast(1e-6, f32), "L22 = sqrt(3 - 1) = sqrt(2)")
}
def test_cholesky_round_trip_recovers_covariance() -> unit ! { Test } = {
  sigma_xx = cast(0.04, f32)
  sigma_xy = cast(0.012, f32)
  sigma_yy = cast(0.09, f32)
  out = cholesky_2x2_lower(sigma_xx, sigma_xy, sigma_yy)
  recon_xx = mul(out.0, out.0)
  recon_xy = mul(out.0, out.1)
  recon_yy = add(mul(out.1, out.1), mul(out.2, out.2))
  _ = assert_close(recon_xx, sigma_xx, cast(1e-6, f32), "L L^T [0,0] = Sigma_xx")
  _ = assert_close(recon_xy, sigma_xy, cast(1e-6, f32), "L L^T [1,0] = Sigma_xy")
  assert_close(recon_yy, sigma_yy, cast(1e-6, f32), "L L^T [1,1] = Sigma_yy")
}
def test_merton_terminal_positive_paths() -> unit ! { Test } = {
  template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(2000, i64))))
  jumps_template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(2000, i64))))
  paths = merton_jump_terminal(key_from_seed(11i64), template, jumps_template, cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(0.3, f32), cast(-0.1, f32), cast(0.15, f32), cast(1.0, f32))
  paths_l = to_list(paths)
  init = true
  all_pos = fold(fn (acc: bool, p: f32) -> and(acc, gt(p, cast(0.0, f32))), init, paths_l)
  assert_true(all_pos, "all Merton-jump terminal values are positive")
}
def test_merton_terminal_mean_near_s0_exp_mu_t() -> unit ! { Test } = {
  template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(5000, i64))))
  jumps_template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(5000, i64))))
  paths = merton_jump_terminal(key_from_seed(7i64), template, jumps_template, cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(0.3, f32), cast(-0.1, f32), cast(0.15, f32), cast(1.0, f32))
  m = mean_vec(paths)
  expected = mul(cast(100.0, f32), exp(cast(0.05, f32)))
  rel_err = div(sub(m, expected), expected)
  abs_err = if lt(rel_err, cast(0.0, f32)) then neg(rel_err) else rel_err
  assert_true(lt(abs_err, cast(0.02, f32)), "Merton terminal mean within 2% of S0*exp(mu*t) for compensated drift")
}
def test_correlated_gbm_2d_marginals() -> unit ! { Test } = {
  template_x = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(5000, i64))))
  template_y = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(5000, i64))))
  out = correlated_gbm_terminal_2d(key_from_seed(13i64), template_x, template_y, cast(100.0, f32), cast(50.0, f32), cast(0.04, f32), cast(0.06, f32), cast(0.2, f32), cast(0.3, f32), cast(0.5, f32), cast(1.0, f32))
  m_x = mean_vec(out.0)
  m_y = mean_vec(out.1)
  exp_x = mul(cast(100.0, f32), exp(cast(0.04, f32)))
  exp_y = mul(cast(50.0, f32), exp(cast(0.06, f32)))
  rel_err_x = div(sub(m_x, exp_x), exp_x)
  rel_err_y = div(sub(m_y, exp_y), exp_y)
  abs_x = if lt(rel_err_x, cast(0.0, f32)) then neg(rel_err_x) else rel_err_x
  abs_y = if lt(rel_err_y, cast(0.0, f32)) then neg(rel_err_y) else rel_err_y
  _ = assert_true(lt(abs_x, cast(0.05, f32)), "X marginal mean within 5%")
  assert_true(lt(abs_y, cast(0.05, f32)), "Y marginal mean within 5%")
}
def test_correlated_gbm_2d_rho_zero_positive_dispersion() -> unit ! { Test } = {
  template_x = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(100, i64))))
  template_y = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(100, i64))))
  out = correlated_gbm_terminal_2d(key_from_seed(17i64), template_x, template_y, cast(100.0, f32), cast(100.0, f32), cast(0.0, f32), cast(0.0, f32), cast(0.2, f32), cast(0.2, f32), cast(0.0, f32), cast(1.0, f32))
  s_x = std_vec(out.0, cast(1, i64))
  assert_true(gt(s_x, cast(0.0, f32)), "X has positive dispersion under rho=0")
}
-- Helper: |got / want - 1|. Used for the shoals#98 oracles, where every claim
-- is about a RELATIVE agreement and the quantities span four decades.
def merton_rel_gap(got: f32, want: f32) -> f32 = {
  r = div(sub(got, want), want)
  if lt(r, cast(0.0, f32)) then neg(r) else r
}
-- Helper: lambda * t * (exp(jump_mean + 0.5 * jump_vol^2) - 1), the
-- compound-Poisson jump compensator written out independently of the module so
-- the oracle below does not check the implementation against itself.
def merton_closed_log_jump_moment(lambda: f32, jump_mean: f32, jump_vol: f32, t: f32) -> f32 = {
  w = exp(add(jump_mean, mul(cast(0.5, f32), mul(jump_vol, jump_vol))))
  mul(mul(lambda, t), sub(w, cast(1.0, f32)))
}
-- shoals#98's zero-noise oracle. merton_jump_terminal subtracts
-- merton_sampler_log_jump_moment from the log drift, so E[S_t] = s0*exp(mu*t)
-- holds for whatever law the sampler draws. This test is what proves that law
-- is the COMPOUND POISSON one the Merton compensator names, rather than any
-- truncation that happens to be mean-consistent with itself: the enumerated
-- moment has to equal the closed form at every intensity. It is also the only
-- check on the slot bound in merton_jump_slots, which is otherwise a free knob.
def test_merton_sampler_log_jump_moment_matches_compound_poisson_compensator() -> unit ! { Test } = {
  tol = cast(0.00001, f32)
  one = cast(1.0, f32)
  low = merton_rel_gap(merton_sampler_log_jump_moment(cast(0.3, f32), cast(-0.1, f32), cast(0.15, f32), one), merton_closed_log_jump_moment(cast(0.3, f32), cast(-0.1, f32), cast(0.15, f32), one))
  mid = merton_rel_gap(merton_sampler_log_jump_moment(cast(4.0, f32), cast(0.5, f32), cast(0.2, f32), one), merton_closed_log_jump_moment(cast(4.0, f32), cast(0.5, f32), cast(0.2, f32), one))
  up = merton_rel_gap(merton_sampler_log_jump_moment(cast(6.0, f32), cast(0.4, f32), cast(0.2, f32), one), merton_closed_log_jump_moment(cast(6.0, f32), cast(0.4, f32), cast(0.2, f32), one))
  down = merton_rel_gap(merton_sampler_log_jump_moment(cast(6.0, f32), cast(-0.4, f32), cast(0.2, f32), one), merton_closed_log_jump_moment(cast(6.0, f32), cast(-0.4, f32), cast(0.2, f32), one))
  high = merton_rel_gap(merton_sampler_log_jump_moment(cast(20.0, f32), cast(0.5, f32), cast(0.2, f32), one), merton_closed_log_jump_moment(cast(20.0, f32), cast(0.5, f32), cast(0.2, f32), one))
  _ = assert_true(lt(low, tol), "enumerated jump moment matches the compensator at lambda*t = 0.3")
  _ = assert_true(lt(mid, tol), "enumerated jump moment matches the compensator at lambda*t = 4")
  _ = assert_true(lt(up, tol), "enumerated jump moment matches the compensator at a positive jump mean")
  _ = assert_true(lt(down, tol), "enumerated jump moment matches the compensator at a negative jump mean")
  assert_true(lt(high, tol), "enumerated jump moment matches the compensator at lambda*t = 20")
}
-- The reduction has to survive the f32 EXPONENT range, not just the slot
-- bound. Every individual term exp(log p_k + k * log w) is representable
-- wherever the slot bound admits it, but their sum is about
-- exp(lambda * t * (w - 1)), which leaves f32 above 88.72 and underflows below
-- -103.28. Summing in linear space therefore returned +-inf here, and an
-- infinite compensator makes exp(drift) zero or infinite on EVERY path with no
-- diagnostic. These three points were measured at +-inf before the shifted
-- log-sum-exp reduction; two sit inside the intensity band the tests above
-- already covered, so the slot bound and the intensity range were never the
-- discriminating variable -- the jump SIZE is.
def test_merton_sampler_log_jump_moment_survives_the_f32_exponent_range() -> unit ! { Test } = {
  tol = cast(0.00001, f32)
  one = cast(1.0, f32)
  wide = merton_rel_gap(merton_sampler_log_jump_moment(one, cast(0.0, f32), cast(3.2, f32), one), merton_closed_log_jump_moment(one, cast(0.0, f32), cast(3.2, f32), one))
  tall = merton_rel_gap(merton_sampler_log_jump_moment(cast(55.0, f32), one, cast(0.2, f32), one), merton_closed_log_jump_moment(cast(55.0, f32), one, cast(0.2, f32), one))
  deep = merton_rel_gap(merton_sampler_log_jump_moment(cast(300.0, f32), cast(-0.5, f32), cast(0.0, f32), one), merton_closed_log_jump_moment(cast(300.0, f32), cast(-0.5, f32), cast(0.0, f32), one))
  _ = assert_true(lt(wide, tol), "jump moment stays finite past the f32 overflow point on a wide jump_vol")
  _ = assert_true(lt(tall, tol), "jump moment stays finite past the f32 overflow point on a large jump_mean")
  assert_true(lt(deep, tol), "jump moment stays finite past the f32 UNDERFLOW point on a negative jump_mean")
}
-- The consequence the test above protects, asserted on the prices themselves:
-- at lambda*t = 1000 an infinite compensator silently returned 0.0 for every
-- path. Terminal values must be strictly positive and finite. This is the
-- positivity claim test_merton_terminal_positive_paths makes, carried into the
-- region where it actually failed -- that test only reaches lambda = 0.3.
def test_merton_terminal_prices_stay_positive_at_high_intensity() -> unit ! { Test } = {
  template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(64, i64))))
  jumps_template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(64, i64))))
  paths = merton_jump_terminal(key_from_seed(7i64), template, jumps_template, cast(100.0, f32), cast(0.0, f32), cast(0.0, f32), cast(1000.0, f32), cast(0.0953, f32), cast(0.0, f32), cast(1.0, f32))
  usable = fold(fn (acc: bool, v: f32) -> and(acc, and(gt(v, cast(0.0, f32)), eq(sub(v, v), cast(0.0, f32)))), true, to_list(paths))
  assert_true(usable, "every Merton terminal value at lambda*t = 1000 is positive and finite")
}
-- Negative parity for the oracle above: it must not pass by returning zero.
-- At zero intensity the moment is exactly zero because the only enumerated
-- count is zero; at any positive intensity with a negative jump mean it is
-- strictly negative, so a stub that answered zero everywhere fails here.
def test_merton_sampler_log_jump_moment_vanishes_only_at_zero_intensity() -> unit ! { Test } = {
  idle = merton_sampler_log_jump_moment(cast(0.0, f32), cast(0.5, f32), cast(0.2, f32), cast(1.0, f32))
  idle_t = merton_sampler_log_jump_moment(cast(4.0, f32), cast(0.5, f32), cast(0.2, f32), cast(0.0, f32))
  shrinking = merton_sampler_log_jump_moment(cast(0.3, f32), cast(-0.1, f32), cast(0.15, f32), cast(1.0, f32))
  growing = merton_sampler_log_jump_moment(cast(4.0, f32), cast(0.5, f32), cast(0.2, f32), cast(1.0, f32))
  _ = assert_close(idle, cast(0.0, f32), cast(0.0, f32), "zero jump rate gives an exactly zero jump moment")
  _ = assert_close(idle_t, cast(0.0, f32), cast(0.0, f32), "zero horizon gives an exactly zero jump moment")
  _ = assert_true(lt(shrinking, cast(0.0, f32)), "a negative jump mean gives a strictly negative jump moment")
  assert_true(gt(growing, cast(0.0, f32)), "a positive jump mean gives a strictly positive jump moment")
}
-- The two exported compensators describe one model. merton_compensated_drift
-- is the closed-form Merton log drift; the sampler subtracts the enumerated
-- jump moment instead, because that is exact for the law it draws. This pins
-- that the substitution is not a change of model: the two log drifts agree.
def test_merton_compensated_drift_agrees_with_sampler_log_drift() -> unit ! { Test } = {
  mu = cast(0.05, f32)
  sigma = cast(0.2, f32)
  t = cast(1.0, f32)
  closed = mul(merton_compensated_drift(mu, sigma, cast(4.0, f32), cast(0.5, f32), cast(0.2, f32)), t)
  sampled = sub(mul(sub(mu, mul(cast(0.5, f32), mul(sigma, sigma))), t), merton_sampler_log_jump_moment(cast(4.0, f32), cast(0.5, f32), cast(0.2, f32), t))
  assert_true(lt(merton_rel_gap(sampled, closed), cast(0.00001, f32)), "the sampler log drift equals merton_compensated_drift * t")
}
-- shoals#98's named parameter point. The pre-fix sampler drew one Gaussian for
-- the aggregate log jump while the drift compensated a compound Poisson, and
-- the two have different exponential moments: its exact expectation here is
-- 0.8623 against the advertised 1.0, a 13.8% shortfall, and it measured
-- no sample size reduces. The sample standard deviation here is near 2.6, so
-- the standard error at twenty thousand draws is under 2% and the 7% bound is
-- more than three standard errors wide while still excluding the defect by a
-- factor of two. Per-seed figures are deliberately not quoted: they move with
-- the sampling API and the pin, and the exact expectation above does not.
def test_merton_terminal_mean_matches_s0_exp_mu_t_at_high_intensity() -> unit ! { Test } = {
  template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(20000, i64))))
  jumps_template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(20000, i64))))
  paths = merton_jump_terminal(key_from_seed(7i64), template, jumps_template, cast(1.0, f32), cast(0.0, f32), cast(0.0, f32), cast(4.0, f32), cast(0.5, f32), cast(0.2, f32), cast(1.0, f32))
  assert_true(lt(merton_rel_gap(mean_vec(paths), cast(1.0, f32)), cast(0.07, f32)), "Merton terminal mean is s0*exp(mu*t) at lambda=4, jump_mean=0.5, jump_vol=0.2")
}
-- Both signs of the jump mean, as shoals#98 asks. The pre-fix bias is signed:
-- its leading term is -lambda*t*jump_mean*jump_vol^2/2, so a positive jump mean
-- makes the mean too LOW and a negative one makes it too HIGH, each by about a
-- tenth. A single-sign test would have been satisfied by any downward
-- correction, which is why both signs are pinned separately.
def test_merton_terminal_mean_matches_s0_exp_mu_t_with_positive_jump_mean() -> unit ! { Test } = {
  template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(20000, i64))))
  jumps_template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(20000, i64))))
  paths = merton_jump_terminal(key_from_seed(29i64), template, jumps_template, cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(6.0, f32), cast(0.4, f32), cast(0.2, f32), cast(1.0, f32))
  expected = mul(cast(100.0, f32), exp(cast(0.05, f32)))
  assert_true(lt(merton_rel_gap(mean_vec(paths), expected), cast(0.07, f32)), "Merton terminal mean is s0*exp(mu*t) at a positive jump mean")
}
def test_merton_terminal_mean_matches_s0_exp_mu_t_with_negative_jump_mean() -> unit ! { Test } = {
  template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(20000, i64))))
  jumps_template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(20000, i64))))
  paths = merton_jump_terminal(key_from_seed(29i64), template, jumps_template, cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(6.0, f32), cast(-0.4, f32), cast(0.2, f32), cast(1.0, f32))
  expected = mul(cast(100.0, f32), exp(cast(0.05, f32)))
  assert_true(lt(merton_rel_gap(mean_vec(paths), expected), cast(0.04, f32)), "Merton terminal mean is s0*exp(mu*t) at a negative jump mean")
}
-- Zero jump rate, as shoals#98 asks, as a DETERMINISTIC claim rather than a
-- mean within a band: with no diffusion and no jumps every path is the forward
-- exactly, whatever the jump-size parameters say. The second leg is its
-- negative parity -- the same call at a positive rate must spread the paths,
-- so a sampler that collapsed every path to the forward would fail here.
def test_merton_terminal_zero_jump_rate_is_the_forward() -> unit ! { Test } = {
  template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(2000, i64))))
  jumps_template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(2000, i64))))
  idle = merton_jump_terminal(key_from_seed(5i64), template, jumps_template, cast(100.0, f32), cast(0.05, f32), cast(0.0, f32), cast(0.0, f32), cast(0.5, f32), cast(0.2, f32), cast(1.0, f32))
  forward = mul(cast(100.0, f32), exp(cast(0.05, f32)))
  worst = fold(fn (acc: f32, p: f32) -> {
    g = merton_rel_gap(p, forward)
    if gt(g, acc) then g else acc
  }, cast(0.0, f32), to_list(idle))
  live_template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(2000, i64))))
  live_jumps = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(2000, i64))))
  live = merton_jump_terminal(key_from_seed(5i64), live_template, live_jumps, cast(100.0, f32), cast(0.05, f32), cast(0.0, f32), cast(4.0, f32), cast(0.5, f32), cast(0.2, f32), cast(1.0, f32))
  spread = fold(fn (acc: f32, p: f32) -> {
    g = merton_rel_gap(p, forward)
    if gt(g, acc) then g else acc
  }, cast(0.0, f32), to_list(live))
  _ = assert_true(lt(worst, cast(0.00001, f32)), "at lambda=0 and sigma=0 every Merton path is exactly s0*exp(mu*t)")
  assert_true(gt(spread, cast(0.1, f32)), "at lambda=4 the same call does spread the paths")
}
-- The jumps are real. With no diffusion and no jump-size dispersion the log
-- return is the compensator plus an INTEGER multiple of jump_mean, so the
-- implied jump count is recoverable per path and must come out integral. The
-- pre-fix sampler put a continuous Gaussian in that slot, so its implied
-- counts were non-integral with probability one: this is the test that
-- separates "a compound Poisson jump count" from "a moment-matched Gaussian
-- aggregate", which the mean tests above cannot do on their own because the
-- Gaussian aggregate matched the first two moments of the count by design.
-- The second leg keeps a degenerate always-zero count from passing.
def test_merton_terminal_draws_integral_jump_counts() -> unit ! { Test } = {
  template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(4000, i64))))
  jumps_template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(4000, i64))))
  paths = merton_jump_terminal(key_from_seed(21i64), template, jumps_template, cast(1.0, f32), cast(0.0, f32), cast(0.0, f32), cast(4.0, f32), cast(0.5, f32), cast(0.0, f32), cast(1.0, f32))
  drift = merton_compensated_drift(cast(0.0, f32), cast(0.0, f32), cast(4.0, f32), cast(0.5, f32), cast(0.0, f32))
  implied = map(fn (p: f32) -> div(sub(log(p), drift), cast(0.5, f32)), to_list(paths))
  worst = fold(fn (acc: f32, c: f32) -> {
    rounded = cast(cast_trunc(add(c, cast(0.5, f32)), i64), f32)
    gap = sub(c, rounded)
    gap_abs = if lt(gap, cast(0.0, f32)) then neg(gap) else gap
    if gt(gap_abs, acc) then gap_abs else acc
  }, cast(0.0, f32), implied)
  highest = fold(fn (acc: f32, c: f32) -> if gt(c, acc) then c else acc, cast(0.0, f32), implied)
  _ = assert_true(lt(worst, cast(0.001, f32)), "every implied Merton jump count is an integer")
  assert_true(gt(highest, cast(3.5, f32)), "the implied jump counts reach at least four jumps")
}
