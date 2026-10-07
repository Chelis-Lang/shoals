module Shoals.Stochastic
import Nautilus.Distributions (normal_sample, uniform_sample, exponential_sample)
import Nautilus.Special (log_gamma)
export (gbm_path, gbm_terminal, gbm_paths_antithetic_terminal_mean, merton_jump_terminal, merton_compensated_drift, merton_sampler_log_jump_moment, correlated_gbm_terminal_2d, cholesky_2x2_lower, heston_qe_step, heston_qe_terminal, heston_qe_paths_terminal, sto_kou_compensator, sto_kou_jump_sample, sto_kou_sampler_log_jump_moment, sto_kou_jump_terminal)
-- Every path sampler in this module turns its time horizon into `sqrt(t)` and
-- into a log drift proportional to t, so a horizon that is not finite and
-- non-negative yields NaN for every path with no diagnostic. That is a
-- precondition of the DIFFUSION, which is why it is checked here and not in
-- merton_jump_slots or sto_kou_jump_slots: those guard `lambda * t` as a
-- Poisson rate, and `0.0 * -1.0` is `-0.0`, whose sign bit is set but which
-- compares `>= 0.0` as true in IEEE 754. A jump-count guard therefore cannot
-- see a negative horizon at lambda = 0, and it should not have to -- at
-- lambda = 0 there is no Poisson law to be negative, and the NaN comes from
-- `sqrt(t)` on the diffusion side regardless of the jump parameters.
--
-- The general lesson is to guard the INPUT, not a derived
-- product: `lambda * t` destroys the sign information the guard needs, while
-- `gte(t, 0.0)` rejects `t = -1` cleanly. (No issue number is cited here on
-- purpose: in this repository a `shoals#NNN` token in `src/` denotes a LIVE
-- narrowing that `reef conform audit` row 9 requires be covered by a
-- tests_blocked/ probe or a docs/UPSTREAM_BUGS.md entry. This guard is a fix,
-- not a workaround, so citing it here would assert a limitation that does not
-- exist. The provenance lives in the commit, the CHANGELOG, docs/book/src/
-- stochastic.md, and the tests_neg/stochastic/ rationales.) Within this module the two
-- `gte(rate, zero)` clauses are the only guards keying on a product's sign,
-- and in the nine guarded samplers below, where the horizon IS checked
-- upstream, the only remaining routes to a `-0.0` rate are a zero horizon or
-- a zero lambda, both of which have the correct zero-jump answer. The two
-- exported `*_sampler_log_jump_moment` functions are NOT so guarded, so a
-- negative horizon reaches their `-0.0` rate directly; measured, they return
-- 0.0 there, which is the right zero-jump answer.
--
-- `-0.0` stays ADMITTED, deliberately: `gte(-0.0, 0.0)` is true, `sqrt(-0.0)`
-- is `-0.0`, and the terminal value is s0 to within the log/exp round trip.
-- A zero horizon is a legitimate input, and refusing it would narrow the
-- surface for a sign bit that changes no answer.
--
-- Non-finiteness uses this module's `sub(x, x) == 0` idiom rather than an
-- ordering comparison, for count_params_finite's reason: `gte(nan, 0.0)` is
-- false, so a NaN horizon would otherwise report the negative-horizon cause.
-- `+inf` is refused on a measured ground and not for tidiness: the log drift
-- and `sigma * sqrt(t)` are then both `+inf`, so `drift + vol_sqrt_t * z` is
-- `inf - inf` = NaN for every negative draw and `+inf` for every positive one.
-- Measured at s0 = 100, mu = 0.05, sigma = 0.2, n = 8, seed 7 on the
-- pre-guard tree: 3 NaN and 5 `+inf`. That is why this branch's diagnostic
-- says "no path value would be usable" rather than naming NaN -- unlike a
-- negative horizon, which really is NaN at every path. The fixtures under
-- tests_neg/stochastic/ pin both diagnostics.
def horizon_finite(t: f32) -> bool = eq(sub(t, t), cast(0.0, f32))
-- The checked horizon, RETURNED rather than asserted, so that every caller has
-- to consume the value. A `_ = check(t)` binding would be dead and could be
-- eliminated before it reached the evaluated graph; threading the return value
-- is what puts the guard in the dataflow of every sampler below.
--
-- That is a DEFENSIVE choice, not a demonstrated necessity, and the
-- distinction is measured: a discarded `_ = checked_horizon(t)` with raw `t`
-- downstream was observed to still fire in the evaluator lane, which is the
-- lane every test here runs in. No gate stage lowers these samplers, so the
-- hazard is untested rather than refuted. Threading costs nothing and does not
-- depend on which lane evaluates the binding, so it stays.
def checked_horizon(t: f32) -> f32 = if not(horizon_finite(t)) then fail("Shoals.Stochastic: the time horizon must be finite; a non-finite horizon makes the log drift and sigma * sqrt(t) non-finite, so no path value would be usable") else if not(gte(t, cast(0.0, f32))) then fail("Shoals.Stochastic: the time horizon must be non-negative; sqrt of a negative horizon is NaN, so every path value would be NaN") else t
-- The step count is a SEPARATE precondition, one parameter over from the
-- horizon, and checked_horizon above cannot see it: `t = 1.0` is perfectly
-- legal, and it is `n_steps` that decides whether a discretisation exists at
-- all. With `n_steps <= 0` the step range is empty, so the fold over it
-- returns its initial state `(log_s0, v0, v0)` unevaluated and the sampler
-- returns `exp(log_s0)` -- s0 to within the log/exp round trip -- for a
-- horizon over which the process really did evolve. Measured at s0 = 100,
-- v0 = 0.04, t = 1.0, seed 7 on the unguarded tree: `n_steps = 0` and
-- `n_steps = -8` both returned 100.00001 for the terminal spot and 0.04 for
-- the terminal variance, while `n_steps = 64` returned 146.3306.
--
-- A finiteness check on `dt` would NOT see this, which is the horizon guard's
-- own lesson arriving from the other side. `dt = t / n_steps` is `+inf` at
-- `n_steps = 0` and NaN at `t = 0, n_steps = 0`, but at `n_steps <= 0` it has
-- no consumer that ever runs, so nothing surfaces it. Guard the INPUT, not
-- the derived value: there the derived value was a product that destroyed a
-- sign, here it is a quotient whose non-finiteness is unreachable.
--
-- Zero and negative are refused TOGETHER but on different warrants, and the
-- fixtures separate them so the zero decision can be revisited without
-- disturbing the negative one. A negative step count is not a quantity; there
-- is nothing to decide. A zero step count carries an identity argument -- "no
-- steps, so no evolution, so s0" -- and that argument is REJECTED here.
-- `n_steps` is a RESOLUTION parameter, not a modelled quantity: zero
-- resolution is unspecified rather than degenerate, and `s0` is the terminal
-- spot of a Heston process over a positive horizon only on an event of
-- probability zero. `n_steps = 1` is a crude discretisation and still draws;
-- `n_steps = 0` draws nothing.
--
-- This is the one axis on which the step count differs from the horizon, and
-- the difference is the reason `t = 0` stays admitted while `n_steps = 0` does
-- not: at `t = 0` s0 IS the right answer, which
-- test_zero_horizon_is_admitted_by_every_sampler pins at n_steps = 8.
-- Refusing `n_steps < 1` therefore takes away no reachable correct answer -- a
-- caller who wants s0 passes `t = 0` with any valid step count and still gets
-- it. Measured: `t = 0` returns 100.00001 at n_steps 1, 8 and 64 alike.
--
-- The integer domain makes this boundary exactly pinnable, unlike the
-- horizon's. 1 is the extremal admitted value and 0 the extremal refused one,
-- with nothing between them, so a positive case at `n_steps = 1` kills every
-- upward threshold shift and a fixture at `n_steps = 0` kills every downward
-- one. The horizon needed a negative min subnormal for the same job; here no
-- subnormal argument exists or is needed.
--
-- Returned rather than asserted, for checked_horizon's reason: every use of
-- the step count consumes the checked value, so the guard is in the dataflow
-- rather than in a binding that could be eliminated before it is evaluated.
def checked_step_count(n_steps: i64) -> i64 = if lt(n_steps, cast(1, i64)) then fail(string_concat("Shoals.Stochastic: the step count must be at least 1, got ", string_concat(to_string(n_steps), "; with no steps the evolution loop never runs, so the sampler would return s0 and v0 unchanged for a horizon it did not simulate"))) else n_steps
def gbm_path[n](rng_key: key, template: tensor[n, f32], s0: f32, mu: f32, sigma: f32, t: f32) -> tensor[n, f32] = {
  z = normal_sample(rng_key, template, cast(0.0, f32), cast(1.0, f32))
  n_i = numel(copy(z))
  t_ok = checked_horizon(t)
  dt = div(t_ok, cast(n_i, f32))
  sqrt_dt = sqrt(dt)
  half_sigma_sq = mul(cast(0.5, f32), mul(sigma, sigma))
  drift = mul(sub(mu, half_sigma_sq), dt)
  log_incs = to_tensor(map(fn (zi: f32) -> add(drift, mul(sigma, mul(sqrt_dt, zi))), to_list(z)))
  log_path = cumsum(log_incs, 0)
  log_s0 = log(s0)
  to_tensor(map(fn (lp: f32) -> exp(add(log_s0, lp)), to_list(log_path)))
}
def gbm_terminal[n](rng_key: key, template: tensor[n, f32], s0: f32, mu: f32, sigma: f32, t: f32) -> tensor[n, f32] = {
  z = normal_sample(rng_key, template, cast(0.0, f32), cast(1.0, f32))
  t_ok = checked_horizon(t)
  half_sigma_sq = mul(cast(0.5, f32), mul(sigma, sigma))
  drift = mul(sub(mu, half_sigma_sq), t_ok)
  vol_sqrt_t = mul(sigma, sqrt(t_ok))
  log_s0 = log(s0)
  to_tensor(map(fn (zi: f32) -> exp(add(log_s0, add(drift, mul(vol_sqrt_t, zi)))), to_list(z)))
}
def gbm_paths_antithetic_terminal_mean[n](rng_key: key, template: tensor[n, f32], s0: f32, mu: f32, sigma: f32, t: f32) -> f32 = {
  z = normal_sample(rng_key, template, cast(0.0, f32), cast(1.0, f32))
  t_ok = checked_horizon(t)
  half_sigma_sq = mul(cast(0.5, f32), mul(sigma, sigma))
  drift = mul(sub(mu, half_sigma_sq), t_ok)
  vol_sqrt_t = mul(sigma, sqrt(t_ok))
  log_s0 = log(s0)
  zs = to_list(z)
  pairs = to_tensor(map(fn (zi: f32) -> {
    plus = exp(add(log_s0, add(drift, mul(vol_sqrt_t, zi))))
    minus = exp(add(log_s0, add(drift, mul(vol_sqrt_t, neg(zi)))))
    mul(cast(0.5, f32), add(plus, minus))
  }, zs))
  n_f = cast(numel(copy(pairs)), f32)
  div(tensor_to_scalar(sum(pairs, 0)), n_f)
}
def merton_compensated_drift(mu: f32, sigma: f32, lambda: f32, jump_mean: f32, jump_vol: f32) -> f32 = {
  half_sigma_sq = mul(cast(0.5, f32), mul(sigma, sigma))
  half_jump_vol_sq = mul(cast(0.5, f32), mul(jump_vol, jump_vol))
  expected_jump = sub(exp(add(jump_mean, half_jump_vol_sq)), cast(1.0, f32))
  sub(sub(mu, half_sigma_sq), mul(lambda, expected_jump))
}
-- Shared jump-count machinery for the two compound Poisson samplers in this
-- module. Both draw a jump count N over an enumerated slot table, and both
-- compensate the log drift with log E[exp(J)] = log E[w^N] for a per-model
-- jump multiplier w = E[exp(Y)]. Only w and the guard diagnostics differ.
-- Keeping the table in ONE place is the point rather than a tidiness
-- preference: both samplers have shipped the same defect -- a drift
-- compensating a law the sampler did not draw -- and a second copy of this
-- arithmetic is a second chance to desync. The fixtures under
-- tests_neg/stochastic/ and the oracles in tests/stochastic_extended.ch carry
-- the issue numbers for both.
--
-- The slot bound for a rate and a log jump multiplier. Sized on the
-- EXPONENTIALLY TILTED mean rate * w rather than on rate, because the quantity
-- that has to converge is E[w^N], whose terms peak at that tilted mean. Seven
-- standard deviations plus twelve absolute slots put the truncated Poisson tail
-- below 1e-10 across the admitted intensity range, which is three orders below
-- f32 resolution. The bound is a cost knob, not a correctness one -- the
-- renormalization in count_table makes the mean identity hold at any slot
-- count -- and the moment tests in tests/stochastic_extended.ch are what prove
-- it adequate at the parameter points they name.
def count_slot_bound(rate: f32, log_w: f32) -> f32 = {
  zero = cast(0.0, f32)
  one = cast(1.0, f32)
  tilt = exp(log_w)
  tilted = if eq(rate, zero) then zero else mul(rate, if lt(tilt, one) then one else tilt)
  add(add(tilted, mul(cast(7.0, f32), sqrt(tilted))), cast(12.0, f32))
}
-- The largest slot table either sampler will materialize per call. A cost
-- bound, not a model bound; the fixtures under tests_neg/stochastic/ record
-- that attempting the table past it is non-terminating in practice.
def count_slot_cap() -> f32 = cast(4096.0, f32)
-- True exactly when both table parameters are finite. `sub(x, x) == 0` is the
-- instrument on purpose, and an ordering comparison is the wrong one: both
-- `gte(nan, 0.0)` and `lte(nan, 4096.0)` are false, so a NaN parameter slips
-- past a lower bound and trips an upper one while naming the wrong cause.
-- tests_neg/stochastic/merton_nonfinite_jump_mean_neg records the measurement
-- that established this, and its Kou counterpart reaches the same guard by a
-- different route: a divergent E[exp(Y)] rather than a non-finite input.
def count_params_finite(rate: f32, log_w: f32) -> bool = eq(add(sub(rate, rate), sub(log_w, log_w)), cast(0.0, f32))
-- log P(N = k) for N ~ Poisson(rate), computed in log space on purpose.
-- The caller multiplies this by w^k, which overflows f32 for large k exactly
-- where the probability underflows, so the product has to be formed as a
-- single exp of a sum rather than from a materialized pmf value. The SUM of
-- those products needs the same care and is an easy thing to miss: it is about
-- exp(rate * (w - 1)), which leaves f32 above 88.72 and underflows below
-- -103.28 while every individual term is still perfectly representable.
-- count_table therefore reduces it as a shifted log-sum-exp, never in
-- linear space.
def count_log_pmf(k: i64, rate: f32) -> f32 = {
  zero = cast(0.0, f32)
  one = cast(1.0, f32)
  kf = cast(k, f32)
  if eq(rate, zero) then if eq(kf, zero) then zero else log(zero) else sub(sub(mul(kf, log(rate)), rate), log_gamma(add(kf, one)))
}
-- The jump-count law a sampler draws from, as one table so that the sampler
-- and the compensator cannot read different numbers. The triple is
-- (cumulative count distribution over the enumerated slots, the mass those
-- slots carry, log E[exp(J)] for the aggregate log jump J). The enumerated
-- mass is one minus the truncated Poisson tail, and BOTH the count draw and
-- the log moment divide by it, so each describes the same renormalized law
-- bit for bit. That is the invariant this module owes its callers: the drift
-- compensates the distribution that was sampled, not a closed form standing
-- beside it. The tests that pin it are named in the moment functions below.
def count_table(rate: f32, log_w: f32, slot_count: i64) -> (List[f32], f32, f32) = {
  log_pmf_l = map(fn (k: i64) -> count_log_pmf(k, rate), range(cast(0, i64), slot_count))
  log_tilted_l = map(fn (lp: (f32, i64)) -> add(lp.0, mul(cast(lp.1, f32), log_w)), zip(log_pmf_l, range(cast(0, i64), slot_count)))
  peak = fold(fn (acc: f32, term: f32) -> if gt(term, acc) then term else acc, log(cast(0.0, f32)), log_tilted_l)
  shifted = to_tensor(map(fn (term: f32) -> exp(sub(term, peak)), log_tilted_l))
  cdf_l = to_list(cumsum(to_tensor(map(fn (lp: f32) -> exp(lp), log_pmf_l)), 0))
  enumerated_mass = index(cdf_l, sub(slot_count, cast(1, i64)))
  (cdf_l, enumerated_mass, sub(add(log(tensor_to_scalar(sum(shifted, 0))), peak), log(enumerated_mass)))
}
-- Number of Poisson jump counts the MERTON sampler enumerates, i.e. the
-- support {0, ..., slots - 1} of merton_count_table. The bound arithmetic
-- is count_slot_bound's; what lives here is Merton's jump multiplier
-- w = exp(jump_mean + 0.5 * jump_vol^2) and Merton's three diagnostics, whose
-- exact text is pinned by the fixtures under tests_neg/stochastic/.
def merton_jump_slots(lambda: f32, jump_mean: f32, jump_vol: f32, t: f32) -> i64 = {
  zero = cast(0.0, f32)
  rate = mul(lambda, t)
  log_tilt = add(jump_mean, mul(cast(0.5, f32), mul(jump_vol, jump_vol)))
  raw = count_slot_bound(rate, log_tilt)
  if not(count_params_finite(rate, log_tilt)) then fail("Shoals.Stochastic: merton jump parameters must be finite; lambda * t and jump_mean + 0.5 * jump_vol^2 must both be representable") else if not(gte(rate, zero)) then fail("Shoals.Stochastic: merton jump rate lambda * t must be finite and non-negative") else if not(lte(raw, count_slot_cap())) then fail("Shoals.Stochastic: merton jump intensity is too large to enumerate the jump count exactly; lambda * t * exp(jump_mean + 0.5 * jump_vol^2) must leave the slot bound at or below 4096") else cast_trunc(raw, i64)
}
-- Merton's jump-count table: count_table at Merton's rate and jump
-- multiplier. J | N ~ Normal(N * jump_mean, N * jump_vol^2), so
-- w = exp(jump_mean + 0.5 * jump_vol^2).
def merton_count_table(lambda: f32, jump_mean: f32, jump_vol: f32, t: f32) -> (List[f32], f32, f32) = count_table(mul(lambda, t), add(jump_mean, mul(cast(0.5, f32), mul(jump_vol, jump_vol))), merton_jump_slots(lambda, jump_mean, jump_vol, t))
-- log E[exp(J)] for the aggregate log jump J that merton_jump_terminal draws:
-- J | N ~ Normal(N * jump_mean, N * jump_vol^2) with N the enumerated jump
-- count, so E[exp(J)] = E[w^N] with w = exp(jump_mean + 0.5 * jump_vol^2).
-- merton_jump_terminal subtracts exactly this number from the log drift, which
-- is why its terminal mean is s0 * exp(mu * t) by construction rather than by a
-- closed form that can desync from the sampler. It converges to
-- merton_compensated_drift's jump term, lambda * t * (w - 1), and
-- tests/stochastic_extended.ch pins that agreement.
def merton_sampler_log_jump_moment(lambda: f32, jump_mean: f32, jump_vol: f32, t: f32) -> f32 = merton_count_table(lambda, jump_mean, jump_vol, t).2
-- Merton jump-diffusion terminal values. The aggregate log jump is drawn as a
-- genuine compound Poisson sum: one uniform picks the jump count N from the
-- enumerated Poisson law, and the N lognormal jumps are aggregated exactly as
-- Normal(N * jump_mean, N * jump_vol^2). The log drift subtracts
-- merton_sampler_log_jump_moment for that same law, so the terminal mean is
-- s0 * exp(mu * t). The jumps_template draws supply the aggregate jump noise;
-- the uniform count draws are generated internally at the template length.
def merton_jump_terminal[n](rng_key: key, template: tensor[n, f32], jumps_template: tensor[n, f32], s0: f32, mu: f32, sigma: f32, lambda: f32, jump_mean: f32, jump_vol: f32, t: f32) -> tensor[n, f32] = {
  zero = cast(0.0, f32)
  one = cast(1.0, f32)
  t_ok = checked_horizon(t)
  (rng_draw_0, rng_tail_0) = split_key(rng_key)
  (rng_draw_1, rng_draw_2) = split_key(rng_tail_0)
  n_paths = numel(copy(template))
  z_diff = normal_sample(rng_draw_0, template, zero, one)
  z_jumps = normal_sample(rng_draw_1, jumps_template, zero, one)
  counts_template = to_tensor(map(fn (i: i64) -> zero, range(cast(0, i64), n_paths)))
  u_counts = uniform_sample(rng_draw_2, counts_template, zero, one)
  counts = merton_count_table(lambda, jump_mean, jump_vol, t_ok)
  enumerated_mass = counts.1
  cdf_norm = to_tensor(map(fn (c: f32) -> div(c, enumerated_mass), counts.0))
  one_i = cast(1, i64)
  path_extent = shape(u_counts, cast(0, i32))
  slot_extent = shape(cdf_norm, cast(0, i32))
  u_grid = expand(reshape(u_counts, [path_extent, one_i]), 1, slot_extent)
  cdf_grid = expand(reshape(cdf_norm, [one_i, slot_extent]), 0, path_extent)
  n_jumps_t = sum(cast(gt(u_grid, cdf_grid), f32), 1)
  half_sigma_sq = mul(cast(0.5, f32), mul(sigma, sigma))
  drift = sub(mul(sub(mu, half_sigma_sq), t_ok), counts.2)
  vol_sqrt_t = mul(sigma, sqrt(t_ok))
  log_s0 = log(s0)
  draws = zip(zip(to_list(z_diff), to_list(z_jumps)), to_list(n_jumps_t))
  to_tensor(map(fn (entry: ((f32, f32), f32)) -> {
    normals = entry.0
    n_jumps = entry.1
    log_jump = add(mul(n_jumps, jump_mean), mul(mul(sqrt(n_jumps), jump_vol), normals.1))
    log_diffuse = add(drift, mul(vol_sqrt_t, normals.0))
    exp(add(log_s0, add(log_diffuse, log_jump)))
  }, draws))
}
def cholesky_2x2_lower(sigma_xx: f32, sigma_xy: f32, sigma_yy: f32) -> (f32, f32, f32) = {
  l11 = sqrt(sigma_xx)
  l21 = div(sigma_xy, l11)
  l22 = sqrt(sub(sigma_yy, mul(l21, l21)))
  (l11, l21, l22)
}
def correlated_gbm_terminal_2d[n](rng_key: key, template_x: tensor[n, f32], template_y: tensor[n, f32], s0_x: f32, s0_y: f32, mu_x: f32, mu_y: f32, sigma_x: f32, sigma_y: f32, rho: f32, t: f32) -> (tensor[n, f32], tensor[n, f32]) = {
  t_ok = checked_horizon(t)
  (rng_draw_0, rng_draw_1) = split_key(rng_key)
  zx = normal_sample(rng_draw_0, template_x, cast(0.0, f32), cast(1.0, f32))
  zy_indep = normal_sample(rng_draw_1, template_y, cast(0.0, f32), cast(1.0, f32))
  log_s0_x = log(s0_x)
  log_s0_y = log(s0_y)
  drift_x = mul(sub(mu_x, mul(cast(0.5, f32), mul(sigma_x, sigma_x))), t_ok)
  drift_y = mul(sub(mu_y, mul(cast(0.5, f32), mul(sigma_y, sigma_y))), t_ok)
  vol_x_sqrt_t = mul(sigma_x, sqrt(t_ok))
  vol_y_sqrt_t = mul(sigma_y, sqrt(t_ok))
  one_minus_rho_sq = sub(cast(1.0, f32), mul(rho, rho))
  sqrt_one_minus_rho_sq = if lt(one_minus_rho_sq, cast(0.0, f32)) then cast(0.0, f32) else sqrt(one_minus_rho_sq)
  zx_l = to_list(zx)
  zy_l = to_list(zy_indep)
  pairs = zip(zx_l, zy_l)
  x_path = to_tensor(map(fn (e: (f32, f32)) -> exp(add(log_s0_x, add(drift_x, mul(vol_x_sqrt_t, e.0)))), pairs))
  y_path = to_tensor(map(fn (e: (f32, f32)) -> {
    z_corr = add(mul(rho, e.0), mul(sqrt_one_minus_rho_sq, e.1))
    exp(add(log_s0_y, add(drift_y, mul(vol_y_sqrt_t, z_corr))))
  }, pairs))
  (x_path, y_path)
}
def heston_qe_step(log_s: f32, v: f32, min_v: f32, mu: f32, kappa: f32, theta: f32, sigma: f32, rho: f32, dt: f32, z_v: f32, z_indep: f32, u: f32) -> (f32, f32, f32) = {
  one = cast(1.0, f32)
  two = cast(2.0, f32)
  half = cast(0.5, f32)
  psi_c = cast(1.5, f32)
  zero = cast(0.0, f32)
  dt_ok = checked_horizon(dt)
  e_kdt = exp(neg(mul(kappa, dt_ok)))
  one_minus_e = sub(one, e_kdt)
  m = add(theta, mul(sub(v, theta), e_kdt))
  sigma_sq = mul(sigma, sigma)
  s2_a = mul(div(mul(v, mul(sigma_sq, e_kdt)), kappa), one_minus_e)
  s2_b = mul(div(mul(theta, sigma_sq), mul(two, kappa)), mul(one_minus_e, one_minus_e))
  s2 = add(s2_a, s2_b)
  tiny = cast(1e-12, f32)
  m_abs = if lt(m, zero) then neg(m) else m
  s2_abs = if lt(s2, zero) then neg(s2) else s2
  v_next = if lt(m_abs, tiny) then zero else if lt(s2_abs, tiny) then if lt(m, zero) then zero else m else {
    m_safe = if lt(m, tiny) then tiny else m
    psi = div(s2, mul(m_safe, m_safe))
    if lte(psi, psi_c) then {
      two_over_psi = div(two, psi)
      two_over_psi_minus_one = sub(two_over_psi, one)
      two_over_psi_minus_one_safe = if lt(two_over_psi_minus_one, zero) then zero else two_over_psi_minus_one
      b2 = add(two_over_psi_minus_one_safe, mul(sqrt(two_over_psi), sqrt(two_over_psi_minus_one_safe)))
      a = div(m, add(one, b2))
      inner = add(sqrt(b2), z_v)
      mul(a, mul(inner, inner))
    } else {
      p = div(sub(psi, one), add(psi, one))
      beta = div(sub(one, p), m_safe)
      if lte(u, p) then zero else {
        one_minus_p = sub(one, p)
        one_minus_u = sub(one, u)
        one_minus_u_safe = if lt(one_minus_u, tiny) then tiny else one_minus_u
        mul(div(one, beta), log(div(one_minus_p, one_minus_u_safe)))
      }
    }
  }
  v_next_pos = if lt(v_next, zero) then zero else v_next
  one_minus_rho_sq = sub(one, mul(rho, rho))
  sqrt_one_minus_rho_sq = if lt(one_minus_rho_sq, zero) then zero else sqrt(one_minus_rho_sq)
  z1 = add(mul(rho, z_v), mul(sqrt_one_minus_rho_sq, z_indep))
  v_pos = if lt(v, zero) then zero else v
  log_s_next = add(log_s, add(mul(sub(mu, mul(half, v_pos)), dt_ok), mul(sqrt(mul(v_pos, dt_ok)), z1)))
  new_min = if lt(v_next_pos, min_v) then v_next_pos else min_v
  (log_s_next, v_next_pos, new_min)
}
def heston_qe_terminal(rng_key: key, s0: f32, v0: f32, mu: f32, kappa: f32, theta: f32, sigma: f32, rho: f32, t: f32, n_steps: i64) -> (f32, f32, f32) = {
  (rng_draw_0, rng_tail_0) = split_key(rng_key)
  (rng_draw_1, rng_draw_2) = split_key(rng_tail_0)
  n_ok = checked_step_count(n_steps)
  template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), n_ok)))
  z_v_t = normal_sample(rng_draw_0, copy(template), cast(0.0, f32), cast(1.0, f32))
  z_ind_t = normal_sample(rng_draw_1, copy(template), cast(0.0, f32), cast(1.0, f32))
  u_t = uniform_sample(rng_draw_2, template, cast(0.0, f32), cast(1.0, f32))
  z_v_l = to_list(z_v_t)
  z_ind_l = to_list(z_ind_t)
  u_l = to_list(u_t)
  dt = div(checked_horizon(t), cast(n_ok, f32))
  log_s0 = log(s0)
  init_state = (log_s0, v0, v0)
  idxs = range(cast(0, i64), n_ok)
  final_state = fold(fn (state: (f32, f32, f32), i: i64) -> {
    log_s = state.0
    v = state.1
    min_v = state.2
    z_v = index(z_v_l, i)
    z_indep = index(z_ind_l, i)
    u = index(u_l, i)
    heston_qe_step(log_s, v, min_v, mu, kappa, theta, sigma, rho, dt, z_v, z_indep, u)
  }, init_state, idxs)
  (exp(final_state.0), final_state.1, final_state.2)
}
def heston_qe_paths_terminal[n](rng_key: key, paths_template: tensor[n, f32], s0: f32, v0: f32, mu: f32, kappa: f32, theta: f32, sigma: f32, rho: f32, t: f32, n_steps: i64) -> (tensor[n, f32], tensor[n, f32], tensor[n, f32]) = {
  (rng_draw_0, rng_tail_0) = split_key(rng_key)
  (rng_draw_1, rng_draw_2) = split_key(rng_tail_0)
  n_paths = numel(copy(paths_template))
  n_ok = checked_step_count(n_steps)
  total = mul(n_paths, n_ok)
  big_template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), total)))
  z_v_t = normal_sample(rng_draw_0, copy(big_template), cast(0.0, f32), cast(1.0, f32))
  z_ind_t = normal_sample(rng_draw_1, copy(big_template), cast(0.0, f32), cast(1.0, f32))
  u_t = uniform_sample(rng_draw_2, big_template, cast(0.0, f32), cast(1.0, f32))
  z_v_l = to_list(z_v_t)
  z_ind_l = to_list(z_ind_t)
  u_l = to_list(u_t)
  dt = div(checked_horizon(t), cast(n_ok, f32))
  log_s0 = log(s0)
  path_idxs = range(cast(0, i64), n_paths)
  results = map(fn (p: i64) -> {
    base = mul(p, n_ok)
    init_state = (log_s0, v0, v0)
    step_idxs = range(cast(0, i64), n_ok)
    final = fold(fn (state: (f32, f32, f32), i: i64) -> {
      log_s = state.0
      v = state.1
      min_v = state.2
      k = add(base, i)
      z_v = index(z_v_l, k)
      z_indep = index(z_ind_l, k)
      u = index(u_l, k)
      heston_qe_step(log_s, v, min_v, mu, kappa, theta, sigma, rho, dt, z_v, z_indep, u)
    }, init_state, step_idxs)
    (exp(final.0), final.1, final.2)
  }, path_idxs)
  s_t = to_tensor(map(fn (r: (f32, f32, f32)) -> r.0, results))
  v_t = to_tensor(map(fn (r: (f32, f32, f32)) -> r.1, results))
  min_v = to_tensor(map(fn (r: (f32, f32, f32)) -> r.2, results))
  (s_t, v_t, min_v)
}
def sto_kou_compensator(p: f32, eta_up: f32, eta_dn: f32) -> f32 = {
  one = cast(1.0, f32)
  if lte(eta_up, one) then div(sub(cast(0.0, f32), cast(0.0, f32)), cast(0.0, f32)) else {
    up_term = mul(p, div(eta_up, sub(eta_up, one)))
    dn_term = mul(sub(one, p), div(eta_dn, add(eta_dn, one)))
    sub(add(up_term, dn_term), one)
  }
}
def sto_kou_jump_sample(p: f32, eta_up: f32, eta_dn: f32, u_branch: f32, e_size: f32) -> f32 = if lt(u_branch, p) then div(e_size, eta_up) else neg(div(e_size, eta_dn))
-- Number of Poisson jump counts the KOU sampler enumerates. Kou's jump
-- multiplier is w = E[exp(Y)] = 1 + sto_kou_compensator(p, eta_up, eta_dn),
-- so log_w is the log of that compensated multiplier rather than a Gaussian
-- log moment. That one substitution is the entire Kou/Merton difference in the
-- count machinery; the jump SIZE law is where the two models really diverge.
--
-- Kou's eta_up > 1 requirement arrives here as a NON-FINITE log_w rather than
-- as its own guard: eta_up <= 1 makes E[exp(Y)] divergent, sto_kou_compensator
-- returns its NaN sentinel, and count_params_finite rejects it. This sampler
-- previously multiplied that NaN straight into its drift and returned NaN for
-- every terminal value -- a wrong answer dressed as an answer, which is the
-- failure mode this repository files bugs about. See
-- tests_neg/stochastic/kou_divergent_jump_multiplier_neg.expect.
def sto_kou_jump_slots(lambda_jump: f32, p: f32, eta_up: f32, eta_dn: f32, t: f32) -> i64 = {
  zero = cast(0.0, f32)
  rate = mul(lambda_jump, t)
  log_w = log(add(cast(1.0, f32), sto_kou_compensator(p, eta_up, eta_dn)))
  raw = count_slot_bound(rate, log_w)
  if not(count_params_finite(rate, log_w)) then fail("Shoals.Stochastic: kou jump parameters must be finite; lambda_jump * t must be representable and the jump multiplier 1 + sto_kou_compensator(p, eta_up, eta_dn) must be finite and positive, which requires eta_up > 1") else if not(gte(rate, zero)) then fail("Shoals.Stochastic: kou jump rate lambda_jump * t must be finite and non-negative") else if not(lte(raw, count_slot_cap())) then fail("Shoals.Stochastic: kou jump intensity is too large to enumerate the jump count exactly; lambda_jump * t * (1 + sto_kou_compensator(p, eta_up, eta_dn)) must leave the slot bound at or below 4096") else cast_trunc(raw, i64)
}
-- Kou's jump-count table: count_table at Kou's rate and jump multiplier.
def sto_kou_count_table(lambda_jump: f32, p: f32, eta_up: f32, eta_dn: f32, t: f32) -> (List[f32], f32, f32) = count_table(mul(lambda_jump, t), log(add(cast(1.0, f32), sto_kou_compensator(p, eta_up, eta_dn))), sto_kou_jump_slots(lambda_jump, p, eta_up, eta_dn, t))
-- log E[exp(J)] for the aggregate log jump J that sto_kou_jump_terminal draws:
-- J is the sum of N iid double-exponential jumps with N the enumerated jump
-- count, so E[exp(J)] = E[w^N] with w = 1 + sto_kou_compensator(...).
-- sto_kou_jump_terminal subtracts exactly this number from the log drift,
-- which is why its terminal mean is s0 * exp(mu * t) by construction rather
-- than by a closed form standing beside the sampler.
--
-- For an UNTRUNCATED Poisson count this equals lambda_jump * t * zeta exactly,
-- because E[w^N] = exp(rate * (w - 1)) and zeta = w - 1. That identity is why
-- the thinned-count defect was a SAMPLER defect and not a compensator one: the
-- closed form was always correct for a Poisson count, and the previous sampler
-- drew a Binomial(n_max, rate / n_max) count instead. What this function adds
-- over the closed form is the enumeration correction, so the mean identity
-- survives truncation at any slot count. tests/stochastic_extended.ch pins
-- both legs:
-- agreement with lambda_jump * t * zeta where the Poisson law is enumerated
-- essentially completely, and disagreement with the thinned-count moment
-- log(1 + q * zeta) * n_max that the previous sampler actually realized.
def sto_kou_sampler_log_jump_moment(lambda_jump: f32, p: f32, eta_up: f32, eta_dn: f32, t: f32) -> f32 = sto_kou_count_table(lambda_jump, p, eta_up, eta_dn, t).2
-- Kou jump-diffusion terminal values. The aggregate log jump is a genuine
-- compound Poisson sum: one uniform picks the jump count N from the enumerated
-- Poisson law, and the first N of the per-path pre-drawn double-exponential
-- jumps are added. The log drift subtracts sto_kou_sampler_log_jump_moment for
-- that same law, so the terminal mean is s0 * exp(mu * t).
--
-- The count was previously drawn by thinning a fixed slot budget
-- n_max = trunc(5 * lambda_jump * t + 1) at probability rate / n_max, which is
-- Binomial(n_max, rate / n_max) and not Poisson(rate). Two consequences, both
-- now pinned by tests: below rate = 0.2 the budget was exactly ONE slot, so a
-- second jump was impossible where Poisson puts up to 1.5e-2 of its mass; and
-- the count variance was rate * (1 - rate / n_max) rather than rate at EVERY
-- parameter, a deficit the slot budget's 5x ratio bounds at 20% and does not
-- shrink away. The slot array survives as the jump-size budget. What changed
-- is that the count law is now the law the drift compensates.
def sto_kou_jump_terminal[n](rng_key: key, paths_template: tensor[n, f32], jumps_template: tensor[n, f32], s0: f32, mu: f32, sigma: f32, lambda_jump: f32, p: f32, eta_up: f32, eta_dn: f32, t: f32) -> tensor[n, f32] = {
  zero = cast(0.0, f32)
  one = cast(1.0, f32)
  t_ok = checked_horizon(t)
  (rng_draw_0, rng_tail_0) = split_key(rng_key)
  (rng_draw_1, rng_tail_1) = split_key(rng_tail_0)
  (rng_draw_2, rng_draw_3) = split_key(rng_tail_1)
  _ = jumps_template
  n_paths = numel(copy(paths_template))
  counts = sto_kou_count_table(lambda_jump, p, eta_up, eta_dn, t_ok)
  enumerated_mass = counts.1
  cdf_norm = to_tensor(map(fn (c: f32) -> div(c, enumerated_mass), counts.0))
  one_i = cast(1, i64)
  slot_count = shape(cdf_norm, cast(0, i32))
  total = mul(n_paths, slot_count)
  big_template = to_tensor(map(fn (i: i64) -> zero, range(cast(0, i64), total)))
  counts_template = to_tensor(map(fn (i: i64) -> zero, range(cast(0, i64), n_paths)))
  z_diff = normal_sample(rng_draw_0, copy(paths_template), zero, one)
  u_branch_t = uniform_sample(rng_draw_1, copy(big_template), zero, one)
  u_counts = uniform_sample(rng_draw_2, counts_template, zero, one)
  e_size_t = exponential_sample(rng_draw_3, big_template, one)
  path_extent = shape(u_counts, cast(0, i32))
  u_grid = expand(reshape(u_counts, [path_extent, one_i]), 1, slot_count)
  cdf_grid = expand(reshape(cdf_norm, [one_i, slot_count]), 0, path_extent)
  n_jumps_t = sum(cast(gt(u_grid, cdf_grid), f32), 1)
  z_diff_l = to_list(z_diff)
  u_branch_l = to_list(u_branch_t)
  e_size_l = to_list(e_size_t)
  n_jumps_l = to_list(n_jumps_t)
  drift = sub(mul(sub(mu, mul(cast(0.5, f32), mul(sigma, sigma))), t_ok), counts.2)
  vol_sqrt_t = mul(sigma, sqrt(t_ok))
  log_s0 = log(s0)
  path_idxs = range(cast(0, i64), n_paths)
  to_tensor(map(fn (path_i: i64) -> {
    base = mul(path_i, slot_count)
    n_jumps = index(n_jumps_l, path_i)
    slot_idxs = range(cast(0, i64), slot_count)
    jump_sum = fold(fn (acc: f32, j: i64) -> {
      k = add(base, j)
      u_b = index(u_branch_l, k)
      e_s = index(e_size_l, k)
      jump_val = sto_kou_jump_sample(p, eta_up, eta_dn, u_b, e_s)
      contrib = if lt(cast(j, f32), n_jumps) then jump_val else zero
      add(acc, contrib)
    }, zero, slot_idxs)
    z_i = index(z_diff_l, path_i)
    log_diffuse = add(drift, mul(vol_sqrt_t, z_i))
    exp(add(log_s0, add(log_diffuse, jump_sum)))
  }, path_idxs))
}
