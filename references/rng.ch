module Shoals.References.Rng
export (sobol_second_moment, halton_second_moment, mean_of_dim)
def mean_of_dim[total](points_flat: tensor[total, f32], dim_idx: i64, n_points: i64, n_dims: i64) -> f32 = {
  vals = to_list(points_flat)
  idxs = 0
    |> (fn (__chelis_pipe) -> (cast(__chelis_pipe, i64) |> range(n_points)))
  acc = fold(fn (state: f32, i: i64) -> {
    flat_idx = i |> mul(n_dims) |> add(dim_idx)
    add(state, index(vals, flat_idx))
  }, cast(0.0, f32), idxs)
  div(acc, cast(n_points, f32))
}
def sobol_second_moment[total](points_flat: tensor[total, f32], dim_idx: i64, n_points: i64, n_dims: i64) -> f32 = {
  vals = to_list(points_flat)
  idxs = 0
    |> (fn (__chelis_pipe) -> (cast(__chelis_pipe, i64) |> range(n_points)))
  acc = fold(fn (state: f32, i: i64) -> {
    flat_idx = i |> mul(n_dims) |> add(dim_idx)
    v = index(vals, flat_idx)
    add(state, mul(v, v))
  }, cast(0.0, f32), idxs)
  div(acc, cast(n_points, f32))
}
def halton_second_moment[total](points_flat: tensor[total, f32], dim_idx: i64, n_points: i64, n_dims: i64) -> f32 = sobol_second_moment(points_flat, dim_idx, n_points, n_dims)
