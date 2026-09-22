module Shoals.Properties.Rng
import Shoals.Rng (sobol_points, halton_points)
import Shoals.References.Rng (sobol_second_moment)
def abs_f32(x: f32) -> f32 = if lt(x, cast(0.0, f32)) then neg(x) else x
def all_in_unit_interval(points_flat: List[f32]) -> bool = fold(fn (acc: bool, v: f32) -> and(acc, and(gte(v, cast(0.0, f32)), lt(v, cast(1.0, f32)))), true, points_flat)
def sobol_points_in_unit_interval(n_points: i64, n_dims: i64) -> bool = {
  pts = sobol_points(n_points, n_dims)
  all_in_unit_interval(to_list(pts))
}
def halton_points_in_unit_interval(n_points: i64, n_dims: i64) -> bool = {
  pts = halton_points(n_points, n_dims)
  all_in_unit_interval(to_list(pts))
}
def sobol_second_moment_near_one_third(n_points: i64, n_dims: i64, dim_idx: i64, tol: f32) -> bool = {
  pts = sobol_points(n_points, n_dims)
  m2 = sobol_second_moment(pts, dim_idx, n_points, n_dims)
  lt(abs_f32(sub(m2, div(cast(1.0, f32), cast(3.0, f32)))), tol)
}
