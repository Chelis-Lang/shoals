module ProofInfraAd.Step1blocker
-- STEP 1: reproduce the known blocker.
--
-- The shipped Shoals body (src/pricing.ch:35-42 `call_prices`) computes
-- per-spot prices via a HOST-LANE list combinator:
--     spots_l = to_list(copy(spots))
--     to_tensor(map(fn (s: f32) -> bs_call_scalar(s, ...), spots_l))
-- and then `deltas_call` wraps `grad` around the `sum` of that.
--
-- This mirrors that exact shape with a trivial per-element body (square),
-- so the ONLY thing under test is `grad` over `to_list`/`map`/`to_tensor`,
-- not the transcendental. If grad rejects this, the blocker is the host-lane
-- combinator, independent of erf/erfc.
def host_total[n](xs: tensor[n, f32]) -> f32 = {
  xs_l = to_list(copy(xs))
  prices = to_tensor(map(fn (x: f32) -> mul(x, x), xs_l))
  tensor_to_scalar(sum(prices, 0))
}
def grad_through_host[n](xs: tensor[n, f32]) -> tensor[n, f32] = {
  obj = fn (xv: tensor[n, f32]) -> host_total(xv)
  grad(obj, wrt=xv)(xs)
}
