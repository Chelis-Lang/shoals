module Shoals.Properties.CanonRiskHistorical
import Shoals.Risk (historical_var, historical_cvar)
-- Historical coherence is observed separately from the Gaussian parametric
-- family. The compiler-reported graph must attribute every control directly
-- to historical_var / historical_cvar; no source-text dependency inference is
-- accepted by the release gate.
@property historical_var_monotone_in_confidence forall(x1: f32, x2: f32, x3: f32, alpha1: f32, alpha2: f32) where (alpha1 >= 0.0), (alpha2 > alpha1), (alpha2 <= 1.0):
  {
    losses = to_tensor([x1, x2, x3])
    (historical_var(copy(losses), alpha1) <= historical_var(losses, alpha2))
  }
@property historical_var_monotone_in_confidence_corrupted forall(x1: f32, x2: f32, x3: f32, alpha1: f32, alpha2: f32) where (alpha1 >= 0.0), (alpha2 > alpha1), (alpha2 <= 1.0):
  {
    losses = to_tensor([x1, x2, x3])
    (historical_var(copy(losses), alpha2) < historical_var(losses, alpha1))
  }
@property historical_cvar_dominates_var forall(x1: f32, x2: f32, x3: f32, alpha: f32) where (alpha > 0.5), (alpha < 1.0):
  {
    losses = to_tensor([x1, x2, x3])
    (historical_cvar(copy(losses), alpha) >= historical_var(losses, alpha))
  }
@property historical_cvar_dominates_var_corrupted forall(x1: f32, x2: f32, x3: f32, alpha: f32) where (alpha > 0.5), (alpha < 1.0):
  {
    losses = to_tensor([x1, x2, x3])
    (historical_cvar(copy(losses), alpha) < historical_var(losses, alpha))
  }
@property historical_var_nonneg_positive_losses forall(x1: f32, x2: f32, x3: f32, alpha: f32) where (x1 > 0.0), (x2 > 0.0), (x3 > 0.0), (alpha >= 0.0), (alpha <= 1.0):
  {
    losses = to_tensor([x1, x2, x3])
    (historical_var(losses, alpha) > 0.0)
  }
@property historical_var_nonneg_positive_losses_corrupted forall(x1: f32, x2: f32, x3: f32, alpha: f32) where (x1 > 0.0), (x2 > 0.0), (x3 > 0.0), (alpha >= 0.0), (alpha <= 1.0):
  {
    losses = to_tensor([x1, x2, x3])
    (historical_var(losses, alpha) <= 0.0)
  }
