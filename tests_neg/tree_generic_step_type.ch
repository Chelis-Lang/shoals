module Shoals.Negative.TreeGenericStepType
import Shoals.Trees (tr_binom_european_call_generic)
answer = tr_binom_european_call_generic(150.0f32, 100.0f32, 0.0f32, 0.0f32, 0.25f32, 0.5f32, 2.0f32)
