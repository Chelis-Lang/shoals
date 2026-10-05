module Shoals.Tests_Neg.Stochastic.KeylessGbmNeg
import Shoals.Stochastic (gbm_terminal)
def keyless(template: tensor[3, f32]) -> tensor[3, f32] = gbm_terminal(template, 100.0f32, 0.05f32, 0.2f32, 1.0f32)
