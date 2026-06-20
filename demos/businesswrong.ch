module Shoals.Demos.Businesswrong
-- Business-wrong demos: well-typed models that compile and run cleanly but encode a
-- financial error. The fuzz tier returns a concrete counterexample whose bindings explain
-- the business mistake. Binders are raw f32 clamped inside each model (no bounded
-- preconditions) so the generator does not starve. Each wrong model is paired with a
-- corrected control that passes.
--   wrong:    chelis prove demos/businesswrong.ch --tier fuzz-only --samples 500 --seed 0 --json
--   controls: same invocation; the *_fixed properties report passed.
def nn(x: f32) -> f32 = if lt(x, cast(0.0, f32)) then cast(0.0, f32) else x
def clamp01(x: f32) -> f32 = {
  zero = cast(0.0, f32)
  one = cast(1.0, f32)
  below = lt(x, zero)
  above = gt(x, one)
  if below then zero else if above then one else x
}
-- discount_le_one: discount factor allowed above 1 (wrong-sign linear discount). For a
-- positive rate over positive time it returns MORE than face value (negative implied rate).
def discount_wrong(r: f32, t: f32) -> f32 = {
  one = cast(1.0, f32)
  rr = nn(r)
  tt = nn(t)
  rt = mul(rr, tt)
  add(one, rt)
}
@property discount_le_one forall(r: f32, t: f32):
  {
    one = cast(1.0, f32)
    factor = discount_wrong(r, t)
    lte(factor, one)
  }
-- discount_le_one_fixed: correct rational discount 1/(1+r t) <= 1 for r,t >= 0.
def discount_right(r: f32, t: f32) -> f32 = {
  one = cast(1.0, f32)
  rr = nn(r)
  tt = nn(t)
  rt = mul(rr, tt)
  denom = add(one, rt)
  div(one, denom)
}
@property discount_le_one_fixed forall(r: f32, t: f32):
  {
    one = cast(1.0, f32)
    factor = discount_right(r, t)
    lte(factor, one)
  }
-- variance_nonneg: Euler step of a mean-reverting variance can go negative (Feller-condition
-- violation): v_next = v + kappa(theta - v) dt - shock. A negative variance is nonsensical
-- (imaginary volatility).
def var_next_wrong(v: f32, kappa: f32, theta: f32, dt: f32, shock: f32) -> f32 = {
  vv = nn(v)
  kk = nn(kappa)
  th = nn(theta)
  dd = nn(dt)
  sh = nn(shock)
  gap = sub(th, vv)
  drift_rate = mul(kk, gap)
  drift = mul(drift_rate, dd)
  mean_rev = add(vv, drift)
  sub(mean_rev, sh)
}
@property variance_nonneg forall(v: f32, kappa: f32, theta: f32, dt: f32, shock: f32):
  {
    zero = cast(0.0, f32)
    v_next = var_next_wrong(v, kappa, theta, dt, shock)
    gte(v_next, zero)
  }
-- variance_nonneg_fixed: full-truncation scheme max(0, .) keeps variance nonnegative.
def var_next_fixed(v: f32, kappa: f32, theta: f32, dt: f32, shock: f32) -> f32 = {
  raw = var_next_wrong(v, kappa, theta, dt, shock)
  nn(raw)
}
@property variance_nonneg_fixed forall(v: f32, kappa: f32, theta: f32, dt: f32, shock: f32):
  {
    zero = cast(0.0, f32)
    v_next = var_next_fixed(v, kappa, theta, dt, shock)
    gte(v_next, zero)
  }
-- call_le_spot: a call priced ABOVE spot (sign bug: + instead of -). Buying the stock and
-- selling this call locks in riskless profit (static arbitrage). Violates C <= S.
def call_wrong(s: f32, k: f32, nd1: f32, nd2: f32, disc: f32) -> f32 = {
  ss = nn(s)
  kk = nn(k)
  n1 = clamp01(nd1)
  n2 = clamp01(nd2)
  df = clamp01(disc)
  spot_leg = mul(ss, n1)
  strike_pv = mul(kk, df)
  strike_leg = mul(strike_pv, n2)
  add(spot_leg, strike_leg)
}
@property call_le_spot forall(s: f32, k: f32, nd1: f32, nd2: f32, disc: f32):
  {
    ss = nn(s)
    price = call_wrong(s, k, nd1, nd2, disc)
    lte(price, ss)
  }
-- call_le_spot_fixed: the correct Black-Scholes structure (minus) respects C <= S.
def call_right(s: f32, k: f32, nd1: f32, nd2: f32, disc: f32) -> f32 = {
  ss = nn(s)
  kk = nn(k)
  n1 = clamp01(nd1)
  n2 = clamp01(nd2)
  df = clamp01(disc)
  spot_leg = mul(ss, n1)
  strike_pv = mul(kk, df)
  strike_leg = mul(strike_pv, n2)
  sub(spot_leg, strike_leg)
}
@property call_le_spot_fixed forall(s: f32, k: f32, nd1: f32, nd2: f32, disc: f32):
  {
    ss = nn(s)
    price = call_right(s, k, nd1, nd2, disc)
    lte(price, ss)
  }
