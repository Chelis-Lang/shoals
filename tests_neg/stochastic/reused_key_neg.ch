module Shoals.Tests_Neg.Stochastic.ReusedKeyNeg
import Shoals.Stochastic (gbm_terminal)
def reused(template: tensor[3, f32]) -> tensor[3, f32] = {
  k = key_from_seed(42i64)
  _ = gbm_terminal(k, copy(template), 100.0f32, 0.05f32, 0.2f32, 1.0f32)
  gbm_terminal(k, template, 100.0f32, 0.05f32, 0.2f32, 1.0f32)
}
