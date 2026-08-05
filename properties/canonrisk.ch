module Shoals.Properties.CanonRisk
import Shoals.Risk (parametric_var, parametric_cvar)
-- Active parametric risk-measure coherence properties over the real VaR/CVaR
-- functions in src/risk.ch. Their inverse-normal-CDF bodies are characterized
-- honestly at fuzz_validated: the release gate requires 25 accepted
-- constraint-directed samples at each seed 0, 1, and 2. Compiler-owned graph
-- edges bind both parametric_var and parametric_cvar where the goal uses both;
-- source-text attribution is never accepted. The distinct empirical-quantile
-- family lives in canonriskhistorical.ch.
--
-- The @property surface quantifies over scalar f32 values that are then packed
-- into a fixed 3-element tensor inside the goal body. This is the smallest size
-- that exercises the mean/std/quantile structure non-trivially.
-- ===========================================================================
-- (1) VaR MONOTONICITY IN CONFIDENCE: VaR at a higher confidence level is at
-- least as large as VaR at a lower confidence level. This is the quantile
-- monotonicity property: if alpha2 > alpha1, then the alpha2-quantile >= the
-- alpha1-quantile. For parametric VaR (Gaussian): VaR = mu + sigma*z(alpha),
-- and z is the inverse normal CDF which is monotone. Corrupted twin: claims
-- VaR DECREASES with confidence.
@property var_monotone_in_confidence forall(x1: f32, x2: f32, x3: f32, alpha1: f32, alpha2: f32) where alpha1 > 0.5, alpha2 > alpha1, alpha2 < 1.0:
  {
    losses = to_tensor([x1, x2, x3])
    (parametric_var(copy(losses), alpha2) >= parametric_var(losses, alpha1))
  }
@property var_monotone_in_confidence_corrupted forall(x1: f32, x2: f32, x3: f32, alpha1: f32, alpha2: f32) where alpha1 > 0.5, alpha2 > alpha1, alpha2 < 1.0:
  {
    losses = to_tensor([x1, x2, x3])
    (parametric_var(copy(losses), alpha2) <= parametric_var(losses, alpha1))
  }
@property var_monotone_guards_satisfiable forall(x1: f32, x2: f32, x3: f32, alpha1: f32, alpha2: f32) where alpha1 > 0.5, alpha2 > alpha1, alpha2 < 1.0:
  false
-- ===========================================================================
-- (2) CVaR DOMINANCE: Expected Shortfall (CVaR) is at least as large as VaR
-- at the same confidence level. This is a fundamental coherence property:
-- CVaR = E[L | L >= VaR(alpha)] >= VaR(alpha). For the parametric (Gaussian)
-- case: CVaR = mu + sigma * phi(z) / (1-alpha) >= mu + sigma * z = VaR,
-- because phi(z)/(1-alpha) >= z for z = Phi^{-1}(alpha) with alpha > 0.5.
-- Corrupted twin: claims CVaR < VaR.
@property cvar_dominates_var forall(x1: f32, x2: f32, x3: f32, alpha: f32) where alpha > 0.5, alpha < 1.0:
  {
    losses = to_tensor([x1, x2, x3])
    (parametric_cvar(copy(losses), alpha) >= parametric_var(losses, alpha))
  }
@property cvar_dominates_var_corrupted forall(x1: f32, x2: f32, x3: f32, alpha: f32) where alpha > 0.5, alpha < 1.0:
  {
    losses = to_tensor([x1, x2, x3])
    (parametric_cvar(copy(losses), alpha) < parametric_var(losses, alpha))
  }
@property cvar_dominance_guards_satisfiable forall(x1: f32, x2: f32, x3: f32, alpha: f32) where alpha > 0.5, alpha < 1.0:
  false
-- ===========================================================================
-- (3) VaR NON-NEGATIVITY (positive-mean portfolio at high confidence): for a
-- portfolio with strictly positive mean losses and confidence > 0.5, the
-- parametric VaR is strictly positive. This encodes "a portfolio that loses
-- money on average has positive risk at any reasonable confidence level."
-- Mathematically: VaR = mu + sigma*z(alpha). For mu > 0, sigma >= 0, and
-- alpha > 0.5 (so z > 0), VaR > 0. Corrupted twin: claims VaR <= 0 for a
-- positive-mean loss distribution at high confidence.
@property var_nonneg_positive_mean forall(x1: f32, x2: f32, x3: f32, alpha: f32) where x1 > 0.0, x2 > 0.0, x3 > 0.0, alpha > 0.5, alpha < 1.0:
  {
    losses = to_tensor([x1, x2, x3])
    (parametric_var(losses, alpha) > 0.0)
  }
@property var_nonneg_positive_mean_corrupted forall(x1: f32, x2: f32, x3: f32, alpha: f32) where x1 > 0.0, x2 > 0.0, x3 > 0.0, alpha > 0.5, alpha < 1.0:
  {
    losses = to_tensor([x1, x2, x3])
    (parametric_var(losses, alpha) <= 0.0)
  }
@property var_nonneg_guards_satisfiable forall(x1: f32, x2: f32, x3: f32, alpha: f32) where x1 > 0.0, x2 > 0.0, x3 > 0.0, alpha > 0.5, alpha < 1.0:
  false
