module Shoals.Properties.JumpMoments
import Shoals.Stochastic (merton_sampler_log_jump_moment, sto_kou_sampler_log_jump_moment)
def moment_abs(x: f32) -> f32 = if lt(x, 0.0) then neg(x) else x
@property merton_zero_intensity forall(t: f32) where t >= 0.0, t < 4.0:
  (moment_abs(merton_sampler_log_jump_moment(0.0, 0.1, 0.2, t)) < 1e-6)
@property kou_zero_horizon forall(lambda_jump: f32) where lambda_jump >= 0.0, lambda_jump < 4.0:
  (moment_abs(sto_kou_sampler_log_jump_moment(lambda_jump, 0.5, 3.0, 4.0, 0.0)) < 1e-6)
@property merton_matches_poisson_moment forall(lambda_jump: f32) where lambda_jump >= 0.0, lambda_jump < 4.0:
  (moment_abs((merton_sampler_log_jump_moment(lambda_jump, 0.1, 0.2, 1.0) - (lambda_jump * (exp(0.12) - 1.0)))) < 0.00001)
@property kou_matches_poisson_moment forall(lambda_jump: f32) where lambda_jump >= 0.0, lambda_jump < 4.0:
  (moment_abs((sto_kou_sampler_log_jump_moment(lambda_jump, 0.5, 3.0, 4.0, 1.0) - (lambda_jump * 0.15))) < 0.00001)
@property merton_zero_intensity_corrupted forall(t: f32) where t >= 0.0, t < 4.0:
  (moment_abs((merton_sampler_log_jump_moment(0.0, 0.1, 0.2, t) + 0.1)) < 1e-6)
@property kou_zero_horizon_corrupted forall(lambda_jump: f32) where lambda_jump >= 0.0, lambda_jump < 4.0:
  (moment_abs((sto_kou_sampler_log_jump_moment(lambda_jump, 0.5, 3.0, 4.0, 0.0) + 0.1)) < 1e-6)
@property merton_matches_poisson_moment_corrupted forall(lambda_jump: f32) where lambda_jump >= 0.0, lambda_jump < 4.0:
  (moment_abs(((merton_sampler_log_jump_moment(lambda_jump, 0.1, 0.2, 1.0) + 0.1) - (lambda_jump * (exp(0.12) - 1.0)))) < 0.00001)
@property kou_matches_poisson_moment_corrupted forall(lambda_jump: f32) where lambda_jump >= 0.0, lambda_jump < 4.0:
  (moment_abs(((sto_kou_sampler_log_jump_moment(lambda_jump, 0.5, 3.0, 4.0, 1.0) + 0.1) - (lambda_jump * 0.15))) < 0.00001)
