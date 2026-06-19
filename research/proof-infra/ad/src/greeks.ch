module ProofInfraAd.Greeks

import ProofInfraAd.Bs (bs_call)

-- AD Greeks over the f64 scalar Black-Scholes body.
--
-- IMPORTANT (capture bug, see RESULTS.md "STEP 1.5"): `grad` cannot
-- differentiate a closure that CAPTURES a free f64 variable from an enclosing
-- function scope -- the backward DAG fails verification with
-- "mismatched precisions F64 vs F32". The earlier closure form
--     grad((fn (x: f64) -> bs_call(x, k, r, sigma, t)), wrt=x)(s)
-- captures k,r,sigma,t and is REJECTED. The supported form is to differentiate
-- the NAMED multi-arg `bs_call` directly with `wrt` selecting the live
-- parameter and every argument passed explicitly (spec/06 §2.10 pattern).

-- delta = dC/dS
def ad_delta_call(s: f64, k: f64, r: f64, sigma: f64, t: f64) -> f64 =
  grad(bs_call, wrt=s)(s, k, r, sigma, t)

-- vega = dC/dsigma
def ad_vega_call(s: f64, k: f64, r: f64, sigma: f64, t: f64) -> f64 =
  grad(bs_call, wrt=sigma)(s, k, r, sigma, t)

-- rho = dC/dr
def ad_rho_call(s: f64, k: f64, r: f64, sigma: f64, t: f64) -> f64 =
  grad(bs_call, wrt=r)(s, k, r, sigma, t)

-- theta = -dC/dt  (textbook sign; AD computes the calendar-time derivative)
def ad_theta_call(s: f64, k: f64, r: f64, sigma: f64, t: f64) -> f64 =
  neg(grad(bs_call, wrt=t)(s, k, r, sigma, t))

-- gamma = d2C/dS2 via grad-of-grad on the named body. Both passes select wrt=s
-- and pass all args explicitly (no capture).
def ad_gamma_call(s: f64, k: f64, r: f64, sigma: f64, t: f64) -> f64 =
  grad(grad(bs_call, wrt=s), wrt=s)(s, k, r, sigma, t)
