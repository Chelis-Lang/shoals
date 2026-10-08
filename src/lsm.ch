module Shoals.Lsm
import Nautilus.Distributions (normal_sample)
export (lsm_put_payoff, lsm_polynomial_regression, lsm_american_put)
def lsm_put_payoff(s: f32, k: f32) -> f32 = {
  diff = sub(k, s)
  if gt(diff, 0f32) then diff else 0f32
}
def lsm_finite_f32(x: f32) -> bool = lte(abs(cast(x, f64)), 3.4028234663852886e38f64)
def lsm_dot(xs: List[f64], ys: List[f64]) -> f64 = fold(fn (acc: f64, pair: (f64, f64)) -> add(acc, mul(pair.0, pair.1)), 0f64, zip(xs, ys))
def lsm_sub_projection(v: List[f64], q: List[f64], coefficient: f64) -> List[f64] = map(fn (pair: (f64, f64)) -> sub(pair.0, mul(coefficient, pair.1)), zip(v, q))
-- Two modified Gram-Schmidt passes. The returned projection sums belong to
-- R; a zero q1 removes the linear direction in a rank-deficient fit.
def lsm_orthogonalize(v: List[f64], q0: List[f64], q1: List[f64]) -> (List[f64], f64, f64) = {
  r0 = lsm_dot(q0, v)
  v0 = lsm_sub_projection(v, q0, r0)
  r1 = lsm_dot(q1, v0)
  v1 = lsm_sub_projection(v0, q1, r1)
  correction0 = lsm_dot(q0, v1)
  v2 = lsm_sub_projection(v1, q0, correction0)
  correction1 = lsm_dot(q1, v2)
  (lsm_sub_projection(v2, q1, correction1), add(r0, correction0), add(r1, correction1))
}
-- Raw f32 moments around S=100 and matrix inversion destroy
-- continuation. Fit normalized columns directly in f64; never form X'X.
-- Result is (center, scale, c0, c1, c2), evaluated at u=(x-center)/scale.
-- Rank uses 64 * epsilon(f64), relative to the unprojected column norm.
def lsm_normalized_fit(pairs: List[(f64, f64)]) -> (f64, f64, f64, f64, f64) = {
  n = len(pairs)
  finite = fold(fn (ok: bool, pair: (f64, f64)) -> and(ok, and(lte(abs(pair.0), 1.7976931348623157e308f64), lte(abs(pair.1), 1.7976931348623157e308f64))), true, pairs)
  if eq(n, 0i64) then fail("Shoals.Lsm: regression requires nonempty observations") else if not(finite) then fail("Shoals.Lsm: regression observations must be finite") else {
    xs = map(fn (pair: (f64, f64)) -> pair.0, pairs)
    ys = map(fn (pair: (f64, f64)) -> pair.1, pairs)
    nf = cast(n, f64)
    center = div(fold(fn (acc: f64, x: f64) -> add(acc, x), 0f64, xs), nf)
    centered = map(fn (x: f64) -> sub(x, center), xs)
    spread = fold(fn (acc: f64, x: f64) -> if gt(abs(x), acc) then abs(x) else acc, 0f64, centered)
    scale = if gt(spread, 0f64) then spread else 1f64
    us = map(fn (x: f64) -> div(x, scale), centered)
    us2 = map(fn (u: f64) -> mul(u, u), us)
    r00 = sqrt(nf)
    q0 = map(fn (x: f64) -> div(1f64, r00), xs)
    zeros = map(fn (x: f64) -> 0f64, xs)
    linear = lsm_orthogonalize(us, q0, zeros)
    r11 = sqrt(lsm_dot(linear.0, linear.0))
    rank_tolerance = 1.4210854715202004e-14f64
    linear_ok = gt(r11, mul(rank_tolerance, sqrt(lsm_dot(us, us))))
    linear_denominator = if linear_ok then r11 else 1f64
    q1 = map(fn (x: f64) -> if linear_ok then div(x, linear_denominator) else 0f64, linear.0)
    quadratic = lsm_orthogonalize(us2, q0, q1)
    r22 = sqrt(lsm_dot(quadratic.0, quadratic.0))
    quadratic_ok = and(linear_ok, gt(r22, mul(rank_tolerance, sqrt(lsm_dot(us2, us2)))))
    quadratic_denominator = if quadratic_ok then r22 else 1f64
    q2 = map(fn (x: f64) -> if quadratic_ok then div(x, quadratic_denominator) else 0f64, quadratic.0)
    c2 = if quadratic_ok then div(lsm_dot(q2, ys), quadratic_denominator) else 0f64
    c1 = if linear_ok then div(sub(lsm_dot(q1, ys), mul(quadratic.2, c2)), linear_denominator) else 0f64
    c0 = div(sub(sub(lsm_dot(q0, ys), mul(linear.1, c1)), mul(quadratic.1, c2)), r00)
    (center, scale, c0, c1, c2)
  }
}
def lsm_fit_value(fit: (f64, f64, f64, f64, f64), x: f32) -> f64 = {
  u = div(sub(cast(x, f64), fit.0), fit.1)
  add(fit.2, mul(u, add(fit.3, mul(u, fit.4))))
}
def lsm_polynomial_regression[k](xs: tensor[k, f32], ys: tensor[k, f32]) -> (f32, f32, f32) = {
  pairs = map(fn (pair: (f32, f32)) -> (cast(pair.0, f64), cast(pair.1, f64)), zip(to_list(xs), to_list(ys)))
  fit = lsm_normalized_fit(pairs)
  b2 = div(div(fit.4, fit.1), fit.1)
  linear = div(fit.3, fit.1)
  b1 = sub(linear, mul(mul(2f64, fit.0), b2))
  b0 = add(sub(fit.2, mul(fit.0, linear)), mul(mul(fit.0, fit.0), b2))
  limit = 3.4028234663852886e38f64
  if and(lte(abs(b0), limit), and(lte(abs(b1), limit), lte(abs(b2), limit))) then (cast(b0, f32), cast(b1, f32), cast(b2, f32)) else fail("Shoals.Lsm: regression coefficients must be representable as finite f32")
}
def lsm_chunk_list_to_lists(flat: List[f32], chunk_size: i64) -> List[List[f32]] = {
  acc_state = fold(fn (state: (List[List[f32]], List[f32], i64), v: f32) -> {
    completed = state.0
    cur = state.1
    cnt = state.2
    next_cnt = add(cnt, cast(1, i64))
    cur_next = append(cur, v)
    if eq(next_cnt, chunk_size) then (append(completed, cur_next), [], cast(0, i64)) else (completed, cur_next, next_cnt)
  }, ([], [], cast(0, i64)), flat)
  acc_state.0
}
-- One row per date, one column per path. Permute materializes the reordered
-- data before reshape; the deterministic non-square test pins that identity.
def lsm_step_spots[z](z_t: tensor[z, f32], s0: f32, r: f32, sigma: f32, dt: f32, n_paths: i64, n_steps: i64) -> List[List[f32]] = {
  drift = mul(sub(r, mul(0.5f32, mul(sigma, sigma))), dt)
  log_inc_flat = to_tensor(map(fn (zi: f32) -> add(drift, mul(sigma, mul(sqrt(dt), zi))), to_list(z_t)))
  log_inc_2d = reshape(log_inc_flat, [n_paths, n_steps])
  log_cumsum_2d = cumsum(log_inc_2d, 1)
  log_cumsum_t = permute(log_cumsum_2d, 1, 0)
  flat = to_list(reshape(log_cumsum_t, [mul(n_paths, n_steps)]))
  spots = map(fn (v: f32) -> exp(add(log(s0), v)), flat)
  finite = fold(fn (ok: bool, x: f32) -> and(ok, lsm_finite_f32(x)), true, spots)
  if finite then lsm_chunk_list_to_lists(spots, n_paths) else fail("Shoals.Lsm: simulated spots must be finite")
}
-- Each path carries one cash flow and its exercise date, never a fitted
-- continuation value. Keep dates integral and discount the realized flow.
def lsm_stopping_state(s_per_step: List[List[f32]], k: f32, r: f32, dt: f32, n_steps: i64) -> List[(f64, i64)] = {
  terminal = index(s_per_step, sub(n_steps, 1i64))
  init = map(fn (s: f32) -> (cast(lsm_put_payoff(s, k), f64), n_steps), terminal)
  back_steps = map(fn (i: i64) -> sub(sub(n_steps, 2i64), i), range(0i64, sub(n_steps, 1i64)))
  fold(fn (state: List[(f64, i64)], j: i64) -> {
    now = add(j, 1i64)
    triples = map(fn (entry: ((f64, i64), f32)) -> {
      old = entry.0
      spot = entry.1
      discount = exp(neg(mul(cast(r, f64), mul(cast(dt, f64), cast(sub(old.1, now), f64)))))
      (spot, lsm_put_payoff(spot, k), mul(discount, old.0))
    }, zip(state, index(s_per_step, j)))
    itm = fold(fn (acc: List[(f64, f64)], triple: (f32, f32, f64)) -> if gt(triple.1, 0f32) then append(acc, (cast(triple.0, f64), triple.2)) else acc, [], triples)
    if eq(len(itm), 0i64) then state else {
      fit = lsm_normalized_fit(itm)
      map(fn (entry: ((f64, i64), (f32, f32, f64))) -> {
        old = entry.0
        triple = entry.1
        if and(gt(triple.1, 0f32), gt(cast(triple.1, f64), lsm_fit_value(fit, triple.0))) then (cast(triple.1, f64), now) else old
      }, zip(state, triples))
    }
  }, init, back_steps)
}
def lsm_american_put[n](rng_key: key, paths_template: tensor[n, f32], s0: f32, k: f32, r: f32, sigma: f32, t: f32, n_steps: i64) -> f32 = {
  n_paths = numel(paths_template)
  finite = and(lsm_finite_f32(s0), and(lsm_finite_f32(k), and(lsm_finite_f32(r), and(lsm_finite_f32(sigma), lsm_finite_f32(t)))))
  if eq(n_paths, 0i64) then fail("Shoals.Lsm: path template must be nonempty") else if not(finite) then fail("Shoals.Lsm: pricing parameters must be finite") else if not(and(gt(s0, 0f32), gt(k, 0f32))) then fail("Shoals.Lsm: spot and strike must be positive") else if lt(sigma, 0f32) then fail("Shoals.Lsm: volatility must be non-negative") else if lt(t, 0f32) then fail("Shoals.Lsm: horizon must be non-negative") else if lt(n_steps, 1i64) then fail("Shoals.Lsm: time steps must be at least one") else if eq(t, 0f32) then lsm_put_payoff(s0, k) else {
    total_z = mul(n_paths, n_steps)
    z_template = to_tensor(map(fn (i: i64) -> 0f32, range(0i64, total_z)))
    z_t = normal_sample(rng_key, z_template, 0f32, 1f32)
    dt = div(t, cast(n_steps, f32))
    s_per_step = lsm_step_spots(z_t, s0, r, sigma, dt, n_paths, n_steps)
    final_state = lsm_stopping_state(s_per_step, k, r, dt, n_steps)
    total = fold(fn (acc: f64, entry: (f64, i64)) -> {
      discount = exp(neg(mul(cast(r, f64), mul(cast(dt, f64), cast(entry.1, f64)))))
      add(acc, mul(discount, entry.0))
    }, 0f64, final_state)
    continuation = div(total, cast(n_paths, f64))
    price = if gt(cast(lsm_put_payoff(s0, k), f64), continuation) then cast(lsm_put_payoff(s0, k), f64) else continuation
    if lte(abs(price), 3.4028234663852886e38f64) then cast(price, f32) else fail("Shoals.Lsm: price must be representable as finite f32")
  }
}
