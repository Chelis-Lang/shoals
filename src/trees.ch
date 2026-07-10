module Shoals.Trees
export (tr_crr_european_call, tr_crr_european_put, tr_crr_american_call, tr_crr_american_put, tr_tian_european_call, tr_tian_european_put, tr_jr_european_call, tr_jr_european_put, tr_trinomial_european_call, tr_trinomial_american_put, tr_crr_call_2step, tr_crr_call_2step_nodisc)
-- Closed-form 2-step CRR European call: the fully expanded binomial value with
-- move factors u/d, risk-neutral probability q, and per-step discount as GUARDED
-- INPUTS. Pure arithmetic + ITE (relu), no transcendentals, so the pricing
-- structure lowers to cvc5 -- shoals' genuine proven-over-reals model lane
-- (dischargeability probe p14; properties in Shoals.Properties.CanonTrees).
-- General-depth CRR needs induction over the lattice and is held out (no chelis
-- induction tier at 0.14.0; re-probe on an induction/fixed-point capability).
def relu(x: f32) -> f32 = if (x >= 0.0) then x else 0.0
def tr_crr_call_2step(s: f32, k: f32, u: f32, d: f32, q: f32, disc: f32) -> f32 = ((disc * disc) * ((((q * q) * relu((((s * u) * u) - k))) + (((2.0 * q) * (1.0 - q)) * relu((((s * u) * d) - k)))) + (((1.0 - q) * (1.0 - q)) * relu((((s * d) * d) - k)))))
-- DEFECTIVE pricer (manifest `defective: true`): the same 2-step CRR call with
-- the discount factor DROPPED -- it prices the raw risk-neutral expected payoff
-- instead of its present value, a real and common finance bug (forgetting to
-- discount). It conforms to the european_call_fixed_depth kind but VIOLATES the
-- no-arbitrage upper bound C <= s inside the valid input region (when the
-- risk-neutral growth exceeds 1 and the option is in the money the undiscounted
-- expected payoff can exceed spot), i.e. it admits arbitrage: a quant would sell
-- this "call" for more than the underlying. The break is polynomial, so cvc5
-- refutes C <= s with a concrete in-domain counterexample that re-executes at
-- f32 (dischargeability lane: proven-over-reals refutation, in_region_defect).
def tr_crr_call_2step_nodisc(s: f32, k: f32, u: f32, d: f32, q: f32) -> f32 = ((((q * q) * relu((((s * u) * u) - k))) + (((2.0 * q) * (1.0 - q)) * relu((((s * u) * d) - k)))) + (((1.0 - q) * (1.0 - q)) * relu((((s * d) * d) - k))))
def tr_zero() -> f32 = cast(0.0, f32)
def tr_one() -> f32 = cast(1.0, f32)
def tr_half() -> f32 = cast(0.5, f32)
def tr_f_two() -> f32 = cast(2.0, f32)
def tr_f_three() -> f32 = cast(3.0, f32)
def tr_f_six() -> f32 = cast(6.0, f32)
def tr_f_twelve() -> f32 = cast(12.0, f32)
def tr_i0() -> int64 = cast(0, int64)
def tr_i1() -> int64 = cast(1, int64)
def tr_i2() -> int64 = cast(2, int64)
def tr_max(a: f32, b: f32) -> f32 = if gt(a, b) then a else b
def tr_sigma_floor() -> f32 = cast(0.001, f32)
def tr_deterministic_call(s0: f32, k: f32, r: f32, q: f32, t: f32) -> f32 = {
  fwd = mul(s0, exp(mul(neg(q), t)))
  disc_k = mul(k, exp(mul(neg(r), t)))
  fwd |> sub(disc_k) |> tr_max(tr_zero())
}
def tr_deterministic_put(s0: f32, k: f32, r: f32, q: f32, t: f32) -> f32 = {
  fwd = mul(s0, exp(mul(neg(q), t)))
  disc_k = mul(k, exp(mul(neg(r), t)))
  disc_k |> sub(fwd) |> tr_max(tr_zero())
}
def tr_pow_ud(log_u: f32, log_d: f32, j: int64, n: int64) -> f32 = exp(add(mul(cast(j, f32), log_u), mul(cast(sub(n, j), f32), log_d)))
def tr_binom_terminal_call(s0: f32, k: f32, log_u: f32, log_d: f32, n: int64) -> List[f32] = {
  idxs = range(tr_i0(), add(n, tr_i1()))
  map(fn (j: int64) -> {
    s = mul(s0, tr_pow_ud(log_u, log_d, j, n))
    s |> sub(k) |> tr_max(tr_zero())
  }, idxs)
}
def tr_binom_terminal_put(s0: f32, k: f32, log_u: f32, log_d: f32, n: int64) -> List[f32] = {
  idxs = range(tr_i0(), add(n, tr_i1()))
  map(fn (j: int64) -> {
    s = mul(s0, tr_pow_ud(log_u, log_d, j, n))
    k |> sub(s) |> tr_max(tr_zero())
  }, idxs)
}
def tr_binom_back_european(vs: List[f32], i_to: int64, disc: f32, p: f32) -> List[f32] = {
  one_minus_p = sub(tr_one(), p)
  new_idxs = range(tr_i0(), add(i_to, tr_i1()))
  map(fn (j: int64) -> {
    v_dn = index(vs, j)
    v_up = index(vs, add(j, tr_i1()))
    mul(disc, p |> mul(v_up) |> add(mul(one_minus_p, v_dn)))
  }, new_idxs)
}
def tr_binom_back_american_call(vs: List[f32], i_to: int64, s0: f32, k: f32, log_u: f32, log_d: f32, disc: f32, p: f32) -> List[f32] = {
  one_minus_p = sub(tr_one(), p)
  new_idxs = range(tr_i0(), add(i_to, tr_i1()))
  map(fn (j: int64) -> {
    v_dn = index(vs, j)
    v_up = index(vs, add(j, tr_i1()))
    cont = mul(disc, p |> mul(v_up) |> add(mul(one_minus_p, v_dn)))
    s = mul(s0, tr_pow_ud(log_u, log_d, j, i_to))
    exer = s |> sub(k) |> tr_max(tr_zero())
    tr_max(exer, cont)
  }, new_idxs)
}
def tr_binom_back_american_put(vs: List[f32], i_to: int64, s0: f32, k: f32, log_u: f32, log_d: f32, disc: f32, p: f32) -> List[f32] = {
  one_minus_p = sub(tr_one(), p)
  new_idxs = range(tr_i0(), add(i_to, tr_i1()))
  map(fn (j: int64) -> {
    v_dn = index(vs, j)
    v_up = index(vs, add(j, tr_i1()))
    cont = mul(disc, p |> mul(v_up) |> add(mul(one_minus_p, v_dn)))
    s = mul(s0, tr_pow_ud(log_u, log_d, j, i_to))
    exer = k |> sub(s) |> tr_max(tr_zero())
    tr_max(exer, cont)
  }, new_idxs)
}
def tr_crr_params(r: f32, q: f32, sigma: f32, dt: f32) -> (f32, f32, f32, f32) = {
  sqrt_dt = sqrt(dt)
  log_u = mul(sigma, sqrt_dt)
  log_d = neg(log_u)
  u = exp(log_u)
  d = exp(log_d)
  growth = exp(mul(sub(r, q), dt))
  p = growth |> sub(d) |> div(sub(u, d))
  disc = exp(neg(mul(r, dt)))
  (log_u, log_d, p, disc)
}
def tr_tian_params(r: f32, q: f32, sigma: f32, dt: f32) -> (f32, f32, f32, f32) = {
  m_grow = exp(mul(sub(r, q), dt))
  v_var = exp(mul(mul(sigma, sigma), dt))
  v_sq = mul(v_var, v_var)
  inner = v_sq |> add(mul(tr_f_two(), v_var)) |> sub(tr_f_three())
  inner_safe = if lt(inner, tr_zero()) then tr_zero() else inner
  root = sqrt(inner_safe)
  v_plus_one = add(v_var, tr_one())
  u = m_grow |> mul(v_var) |> mul(mul(tr_half(), add(v_plus_one, root)))
  d = m_grow |> mul(v_var) |> mul(mul(tr_half(), sub(v_plus_one, root)))
  log_u = log(u)
  log_d = log(d)
  p = m_grow |> sub(d) |> div(sub(u, d))
  disc = exp(neg(mul(r, dt)))
  (log_u, log_d, p, disc)
}
def tr_jr_params(r: f32, q: f32, sigma: f32, dt: f32) -> (f32, f32, f32, f32) = {
  half_sig_sq = mul(tr_half(), mul(sigma, sigma))
  drift = mul(sub(sub(r, q), half_sig_sq), dt)
  diff = mul(sigma, sqrt(dt))
  log_u = add(drift, diff)
  log_d = sub(drift, diff)
  p = tr_half()
  disc = exp(neg(mul(r, dt)))
  (log_u, log_d, p, disc)
}
def tr_binom_european_call_generic(s0: f32, k: f32, log_u: f32, log_d: f32, p: f32, disc: f32, n_steps: int64) -> f32 = {
  terminal = tr_binom_terminal_call(s0, k, log_u, log_d, n_steps)
  step_idxs = range(tr_i0(), n_steps)
  final_vs = fold(fn (vs: List[f32], s: int64) -> {
    i_to = n_steps |> sub(s) |> sub(tr_i1())
    tr_binom_back_european(vs, i_to, disc, p)
  }, terminal, step_idxs)
  index(final_vs, tr_i0())
}
def tr_binom_european_put_generic(s0: f32, k: f32, log_u: f32, log_d: f32, p: f32, disc: f32, n_steps: int64) -> f32 = {
  terminal = tr_binom_terminal_put(s0, k, log_u, log_d, n_steps)
  step_idxs = range(tr_i0(), n_steps)
  final_vs = fold(fn (vs: List[f32], s: int64) -> {
    i_to = n_steps |> sub(s) |> sub(tr_i1())
    tr_binom_back_european(vs, i_to, disc, p)
  }, terminal, step_idxs)
  index(final_vs, tr_i0())
}
def tr_crr_european_call(s0: f32, k: f32, r: f32, q: f32, sigma: f32, t: f32, n_steps: int64) -> f32 = {
  if lt(sigma, tr_sigma_floor()) then tr_deterministic_call(s0, k, r, q, t) else {
    dt = div(t, cast(n_steps, f32))
    params = tr_crr_params(r, q, sigma, dt)
    tr_binom_european_call_generic(s0, k, params.0, params.1, params.2, params.3, n_steps)
  }
}
def tr_crr_european_put(s0: f32, k: f32, r: f32, q: f32, sigma: f32, t: f32, n_steps: int64) -> f32 = {
  if lt(sigma, tr_sigma_floor()) then tr_deterministic_put(s0, k, r, q, t) else {
    dt = div(t, cast(n_steps, f32))
    params = tr_crr_params(r, q, sigma, dt)
    tr_binom_european_put_generic(s0, k, params.0, params.1, params.2, params.3, n_steps)
  }
}
def tr_crr_american_call(s0: f32, k: f32, r: f32, q: f32, sigma: f32, t: f32, n_steps: int64) -> f32 = {
  if lt(sigma, tr_sigma_floor()) then tr_deterministic_call(s0, k, r, q, t) else {
    dt = div(t, cast(n_steps, f32))
    params = tr_crr_params(r, q, sigma, dt)
    log_u = params.0
    log_d = params.1
    p = params.2
    disc = params.3
    terminal = tr_binom_terminal_call(s0, k, log_u, log_d, n_steps)
    step_idxs = range(tr_i0(), n_steps)
    final_vs = fold(fn (vs: List[f32], s: int64) -> {
      i_to = n_steps |> sub(s) |> sub(tr_i1())
      tr_binom_back_american_call(vs, i_to, s0, k, log_u, log_d, disc, p)
    }, terminal, step_idxs)
    index(final_vs, tr_i0())
  }
}
def tr_crr_american_put(s0: f32, k: f32, r: f32, q: f32, sigma: f32, t: f32, n_steps: int64) -> f32 = {
  if lt(sigma, tr_sigma_floor()) then tr_deterministic_put(s0, k, r, q, t) else {
    dt = div(t, cast(n_steps, f32))
    params = tr_crr_params(r, q, sigma, dt)
    log_u = params.0
    log_d = params.1
    p = params.2
    disc = params.3
    terminal = tr_binom_terminal_put(s0, k, log_u, log_d, n_steps)
    step_idxs = range(tr_i0(), n_steps)
    final_vs = fold(fn (vs: List[f32], s: int64) -> {
      i_to = n_steps |> sub(s) |> sub(tr_i1())
      tr_binom_back_american_put(vs, i_to, s0, k, log_u, log_d, disc, p)
    }, terminal, step_idxs)
    index(final_vs, tr_i0())
  }
}
def tr_tian_european_call(s0: f32, k: f32, r: f32, q: f32, sigma: f32, t: f32, n_steps: int64) -> f32 = {
  if lt(sigma, tr_sigma_floor()) then tr_deterministic_call(s0, k, r, q, t) else {
    dt = div(t, cast(n_steps, f32))
    params = tr_tian_params(r, q, sigma, dt)
    tr_binom_european_call_generic(s0, k, params.0, params.1, params.2, params.3, n_steps)
  }
}
def tr_tian_european_put(s0: f32, k: f32, r: f32, q: f32, sigma: f32, t: f32, n_steps: int64) -> f32 = {
  if lt(sigma, tr_sigma_floor()) then tr_deterministic_put(s0, k, r, q, t) else {
    dt = div(t, cast(n_steps, f32))
    params = tr_tian_params(r, q, sigma, dt)
    tr_binom_european_put_generic(s0, k, params.0, params.1, params.2, params.3, n_steps)
  }
}
def tr_jr_european_call(s0: f32, k: f32, r: f32, q: f32, sigma: f32, t: f32, n_steps: int64) -> f32 = {
  if lt(sigma, tr_sigma_floor()) then tr_deterministic_call(s0, k, r, q, t) else {
    dt = div(t, cast(n_steps, f32))
    params = tr_jr_params(r, q, sigma, dt)
    tr_binom_european_call_generic(s0, k, params.0, params.1, params.2, params.3, n_steps)
  }
}
def tr_jr_european_put(s0: f32, k: f32, r: f32, q: f32, sigma: f32, t: f32, n_steps: int64) -> f32 = {
  if lt(sigma, tr_sigma_floor()) then tr_deterministic_put(s0, k, r, q, t) else {
    dt = div(t, cast(n_steps, f32))
    params = tr_jr_params(r, q, sigma, dt)
    tr_binom_european_put_generic(s0, k, params.0, params.1, params.2, params.3, n_steps)
  }
}
def tr_tri_params(r: f32, q: f32, sigma: f32, dt: f32) -> (f32, f32, f32, f32, f32) = {
  three = tr_f_three()
  sqrt_3dt = three |> mul(dt) |> sqrt
  log_u = mul(sigma, sqrt_3dt)
  half_sig_sq = mul(tr_half(), mul(sigma, sigma))
  drift_adj = r |> sub(q) |> sub(half_sig_sq)
  sqrt_dt_12 = dt |> div(tr_f_twelve()) |> sqrt
  p_skew = drift_adj |> mul(sqrt_dt_12) |> div(sigma)
  one_sixth = div(tr_one(), tr_f_six())
  p_u = add(one_sixth, p_skew)
  p_d = sub(one_sixth, p_skew)
  p_m = div(tr_f_two(), three)
  disc = exp(neg(mul(r, dt)))
  (log_u, p_u, p_m, p_d, disc)
}
def tr_tri_terminal_call(s0: f32, k: f32, log_u: f32, n: int64) -> List[f32] = {
  n_f = cast(n, f32)
  size = add(mul(tr_i2(), n), tr_i1())
  idxs = range(tr_i0(), size)
  map(fn (kx: int64) -> {
    j_f = kx |> fn (__chelis_pipe) -> cast(__chelis_pipe, f32) |> sub(n_f)
    s = mul(s0, j_f |> mul(log_u) |> exp)
    s |> sub(k) |> tr_max(tr_zero())
  }, idxs)
}
def tr_tri_terminal_put(s0: f32, k: f32, log_u: f32, n: int64) -> List[f32] = {
  n_f = cast(n, f32)
  size = add(mul(tr_i2(), n), tr_i1())
  idxs = range(tr_i0(), size)
  map(fn (kx: int64) -> {
    j_f = kx |> fn (__chelis_pipe) -> cast(__chelis_pipe, f32) |> sub(n_f)
    s = mul(s0, j_f |> mul(log_u) |> exp)
    k |> sub(s) |> tr_max(tr_zero())
  }, idxs)
}
def tr_tri_back_european(vs: List[f32], i_to: int64, disc: f32, p_u: f32, p_m: f32, p_d: f32) -> List[f32] = {
  new_size = add(mul(tr_i2(), i_to), tr_i1())
  new_idxs = range(tr_i0(), new_size)
  map(fn (kx: int64) -> {
    v_d = index(vs, kx)
    v_m = index(vs, add(kx, tr_i1()))
    v_u = index(vs, add(kx, tr_i2()))
    mul(disc, p_u |> mul(v_u) |> add(add(mul(p_m, v_m), mul(p_d, v_d))))
  }, new_idxs)
}
def tr_tri_back_american_put(vs: List[f32], i_to: int64, s0: f32, k: f32, log_u: f32, disc: f32, p_u: f32, p_m: f32, p_d: f32) -> List[f32] = {
  i_to_f = cast(i_to, f32)
  new_size = add(mul(tr_i2(), i_to), tr_i1())
  new_idxs = range(tr_i0(), new_size)
  map(fn (kx: int64) -> {
    v_d = index(vs, kx)
    v_m = index(vs, add(kx, tr_i1()))
    v_u = index(vs, add(kx, tr_i2()))
    cont = mul(disc, p_u |> mul(v_u) |> add(add(mul(p_m, v_m), mul(p_d, v_d))))
    j_f = kx |> fn (__chelis_pipe) -> cast(__chelis_pipe, f32) |> sub(i_to_f)
    s = mul(s0, j_f |> mul(log_u) |> exp)
    exer = k |> sub(s) |> tr_max(tr_zero())
    tr_max(exer, cont)
  }, new_idxs)
}
def tr_trinomial_european_call(s0: f32, k: f32, r: f32, q: f32, sigma: f32, t: f32, n_steps: int64) -> f32 = {
  if lt(sigma, tr_sigma_floor()) then tr_deterministic_call(s0, k, r, q, t) else {
    dt = div(t, cast(n_steps, f32))
    params = tr_tri_params(r, q, sigma, dt)
    log_u = params.0
    p_u = params.1
    p_m = params.2
    p_d = params.3
    disc = params.4
    terminal = tr_tri_terminal_call(s0, k, log_u, n_steps)
    step_idxs = range(tr_i0(), n_steps)
    final_vs = fold(fn (vs: List[f32], s: int64) -> {
      i_to = n_steps |> sub(s) |> sub(tr_i1())
      tr_tri_back_european(vs, i_to, disc, p_u, p_m, p_d)
    }, terminal, step_idxs)
    index(final_vs, tr_i0())
  }
}
def tr_trinomial_american_put(s0: f32, k: f32, r: f32, q: f32, sigma: f32, t: f32, n_steps: int64) -> f32 = {
  if lt(sigma, tr_sigma_floor()) then tr_deterministic_put(s0, k, r, q, t) else {
    dt = div(t, cast(n_steps, f32))
    params = tr_tri_params(r, q, sigma, dt)
    log_u = params.0
    p_u = params.1
    p_m = params.2
    p_d = params.3
    disc = params.4
    terminal = tr_tri_terminal_put(s0, k, log_u, n_steps)
    step_idxs = range(tr_i0(), n_steps)
    final_vs = fold(fn (vs: List[f32], s: int64) -> {
      i_to = n_steps |> sub(s) |> sub(tr_i1())
      tr_tri_back_american_put(vs, i_to, s0, k, log_u, disc, p_u, p_m, p_d)
    }, terminal, step_idxs)
    index(final_vs, tr_i0())
  }
}
