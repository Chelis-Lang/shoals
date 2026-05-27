module Shoals.Csa
export (csa_collateralized_exposure, csa_collateralized_exposure_path)
def csa_collateralized_exposure(exposure: f32, threshold: f32, mta: f32, independent_amount: f32, haircut: f32) -> f32 = {
  zero_f = cast(0.0, f32)
  one_f = cast(1.0, f32)
  if lte(exposure, threshold) then exposure else {
    required = sub(exposure, threshold)
    if lt(required, mta) then exposure else {
      transferred = mul(required, sub(one_f, haircut))
      effective = exposure |> sub(transferred) |> sub(independent_amount)
      if gt(effective, zero_f) then effective else zero_f
    }
  }
}
def csa_collateralized_exposure_path[n](exposures: tensor[n, f32], threshold: f32, mta: f32, independent_amount: f32, haircut: f32) -> tensor[n, f32] = {
  exposures_l = to_list(exposures)
  to_tensor(map(fn (e: f32) -> csa_collateralized_exposure(e, threshold, mta, independent_amount, haircut), exposures_l))
}
