module Shoals.Properties.JumpMoments
import Shoals.Stochastic (merton_sampler_log_jump_moment, sto_kou_compensator, sto_kou_jump_sample, sto_kou_sampler_log_jump_moment, sto_kou_jump_terminal)
def moment_abs(x: f32) -> f32 = if lt(x, 0.0) then neg(x) else x
-- shoals#146: finite unused upward rates preserve the exact downward law.
@property kou_downward_compensator forall(eta_up: f32, eta_dn: f32) where eta_up >= -2.0, eta_up <= 2.0, eta_dn >= 1.0, eta_dn <= 8.0:
  (sto_kou_compensator(0.0, eta_up, eta_dn) == ((eta_dn / (eta_dn + 1.0)) - 1.0))
@property kou_downward_compensator_corrupted forall(eta_up: f32, eta_dn: f32) where eta_up >= -2.0, eta_up <= 2.0, eta_dn >= 1.0, eta_dn <= 8.0:
  ((sto_kou_compensator(0.0, eta_up, eta_dn) + 0.1) == ((eta_dn / (eta_dn + 1.0)) - 1.0))
@property kou_downward_sample forall(u: f32, e: f32) where u >= 0.0, u <= 1.0, e >= 0.0, e <= 5.0:
  (sto_kou_jump_sample(0.0, 0.0, 3.0, u, e) == -((e / 3.0)))
@property kou_downward_sample_corrupted forall(u: f32, e: f32) where u >= 0.0, u <= 1.0, e >= 0.0, e <= 5.0:
  ((sto_kou_jump_sample(0.0, 0.0, 3.0, u, e) + 0.1) == -((e / 3.0)))
@property kou_downward_moment forall(lambda_jump: f32) where lambda_jump >= 0.0, lambda_jump <= 4.0:
  (sto_kou_sampler_log_jump_moment(lambda_jump, 0.0, 0.0, 3.0, 1.0) == sto_kou_sampler_log_jump_moment(lambda_jump, 0.0, 2.0, 3.0, 1.0))
@property kou_downward_moment_corrupted forall(lambda_jump: f32) where lambda_jump >= 0.0, lambda_jump <= 4.0:
  ((sto_kou_sampler_log_jump_moment(lambda_jump, 0.0, 0.0, 3.0, 1.0) + 0.1) == sto_kou_sampler_log_jump_moment(lambda_jump, 0.0, 2.0, 3.0, 1.0))
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
def probe_prices(eta_up: f32) -> List[f32] = to_list(sto_kou_jump_terminal(key_from_seed(9i64), to_tensor([0.0f32, 0.0f32]), to_tensor([0.0f32, 0.0f32]), 100.0f32, 0.05f32, 0.2f32, 2.0f32, 0.0f32, eta_up, 3.0f32, 1.0f32))
@property kou_terminal_placeholder_identity forall(eta_up: f32) where eta_up >= -2.0, eta_up <= 2.0:
  {
    actual = probe_prices(eta_up)
    reference = probe_prices(2.0)
    and((len(actual) == 2i64), fold(fn (ok: bool, pair: (f32, f32)) -> and(ok, eq(pair.0, pair.1)), true, zip(actual, reference)))
  }
@property kou_terminal_placeholder_identity_corrupted forall(eta_up: f32) where eta_up >= -2.0, eta_up <= 2.0:
  {
    actual = map(fn (x: f32) -> add(x, 1.0f32), probe_prices(eta_up))
    reference = probe_prices(2.0)
    and((len(actual) == 2i64), fold(fn (ok: bool, pair: (f32, f32)) -> and(ok, eq(pair.0, pair.1)), true, zip(actual, reference)))
  }
