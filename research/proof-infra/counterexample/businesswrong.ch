module Research.Counterexample.Businesswrong
-- Track D: well-typed models that run cleanly but are business-wrong. The fuzz tier
-- returns a concrete counterexample whose bindings explain the business error. Binders
-- are raw f32 clamped inside the model (no bounded preconditions) so the generator does
-- not starve. Each wrong model is paired with a corrected control that passes.
-- Run wrong:    chelis prove counterexample/businesswrong.ch --only d1_*  --tier fuzz-only --samples 500 --seed 0 --json
-- Run controls: --only *_fixed
def nn(x: f32) -> f32 = if lt(x, cast(0.0, f32)) then cast(0.0, f32) else x
def clamp01(x: f32) -> f32 = if lt(x, cast(0.0, f32)) then cast(0.0, f32) else if gt(x, cast(1.0, f32)) then cast(1.0, f32) else x
-- D1: discount factor allowed above 1 (wrong-sign linear discount). For a positive rate
-- over positive time it returns MORE than face value (negative implied rate).
def disc_wrong(r: f32, t: f32) -> f32 = add(cast(1.0, f32), mul(nn(r), nn(t)))
@property d1_discount_le_one forall(r: f32, t: f32):
  lte(disc_wrong(r, t), cast(1.0, f32))
-- D1 control: correct rational discount 1/(1+r t) <= 1 for r,t >= 0.
def disc_right(r: f32, t: f32) -> f32 = div(cast(1.0, f32), add(cast(1.0, f32), mul(nn(r), nn(t))))
@property d1_discount_le_one_fixed forall(r: f32, t: f32):
  lte(disc_right(r, t), cast(1.0, f32))
-- D2: Euler step of a mean-reverting variance can go negative (Feller-condition
-- violation): v_next = v + kappa(theta - v) dt - shock. A negative variance is
-- nonsensical (imaginary volatility).
def var_next_wrong(v: f32, kappa: f32, theta: f32, dt: f32, shock: f32) -> f32 = sub(add(nn(v), mul(mul(nn(kappa), sub(nn(theta), nn(v))), nn(dt))), nn(shock))
@property d2_variance_nonneg forall(v: f32, kappa: f32, theta: f32, dt: f32, shock: f32):
  gte(var_next_wrong(v, kappa, theta, dt, shock), cast(0.0, f32))
-- D2 control: full-truncation scheme max(0, .) keeps variance nonnegative.
def var_next_fixed(v: f32, kappa: f32, theta: f32, dt: f32, shock: f32) -> f32 = nn(var_next_wrong(v, kappa, theta, dt, shock))
@property d2_variance_nonneg_fixed forall(v: f32, kappa: f32, theta: f32, dt: f32, shock: f32):
  gte(var_next_fixed(v, kappa, theta, dt, shock), cast(0.0, f32))
-- D3: a call priced ABOVE spot (sign bug: + instead of -). Buying the stock and selling
-- this call locks in riskless profit (static arbitrage). Violates C <= S.
def call_wrong(s: f32, k: f32, nd1: f32, nd2: f32, disc: f32) -> f32 = add(mul(nn(s), clamp01(nd1)), mul(mul(nn(k), clamp01(disc)), clamp01(nd2)))
@property d3_call_le_spot forall(s: f32, k: f32, nd1: f32, nd2: f32, disc: f32):
  lte(call_wrong(s, k, nd1, nd2, disc), nn(s))
-- D3 control: the correct Black-Scholes structure (minus) respects C <= S.
def call_right(s: f32, k: f32, nd1: f32, nd2: f32, disc: f32) -> f32 = sub(mul(nn(s), clamp01(nd1)), mul(mul(nn(k), clamp01(disc)), clamp01(nd2)))
@property d3_call_le_spot_fixed forall(s: f32, k: f32, nd1: f32, nd2: f32, disc: f32):
  lte(call_right(s, k, nd1, nd2, disc), nn(s))
