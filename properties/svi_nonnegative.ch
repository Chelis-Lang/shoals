module Shoals.Properties.Svi_nonnegative
import Shoals.VolSurface (SVI, vs_total_variance)
-- Gatheral and Jacquier, Arbitrage-free SVI volatility surfaces, section 3.1:
-- raw SVI has nonnegative total variance at every log-strike when
-- a + b*sigma*sqrt(1-rho^2) >= 0, b >= 0, |rho| < 1, sigma > 0.
-- This calls the exported Shoals function with its exported SVI record.
-- The proof target is exact-real algebra on the f32 source expression.
@property svi_total_variance_nonnegative forall(a: f32, b: f32, rho: f32, m: f32, sigma: f32, k: f32) where b >= 0.0, rho > -1.0, rho < 1.0, sigma > 0.0, (a + ((b * sigma) * sqrt((1.0 - (rho * rho))))) >= 0.0:
  (vs_total_variance(SVI { a, b, rho, m, sigma }, k) >= 0.0)
-- Dropping the minimum-variance guard admits b=0 and a<0.
@property svi_without_minimum_guard_wrong forall(a: f32, b: f32, rho: f32, m: f32, sigma: f32, k: f32) where b >= 0.0, rho > -1.0, rho < 1.0, sigma > 0.0:
  (vs_total_variance(SVI { a, b, rho, m, sigma }, k) >= 0.0)
@property svi_minimum_guards_satisfiable forall(a: f32, b: f32, rho: f32, m: f32, sigma: f32, k: f32) where b >= 0.0, rho > -1.0, rho < 1.0, sigma > 0.0, (a + ((b * sigma) * sqrt((1.0 - (rho * rho))))) >= 0.0:
  false
