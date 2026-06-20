module ProofInfraContract.Tests.ContractTest
import Std.Test (assert_true, assert_close)
import ProofInfraContract.Contract (n_cdf)

def abs_f32(x: f32) -> f32 = if lt(x, cast(0.0, f32)) then neg(x) else x

def in_unit(x: f32) -> bool = and(gte(x, cast(0.0, f32)), lte(x, cast(1.0, f32)))

-- Contract 1: N(x) in [0,1] across a wide grid (real n_cdf = 0.5*erfc(-x/sqrt2)).
def test_n_cdf_range_grid() -> unit ! { Test } = {
  ok = and(and(and(in_unit(n_cdf(cast(-8.0, f32))), in_unit(n_cdf(cast(-3.0, f32)))),
               and(in_unit(n_cdf(cast(-1.0, f32))), in_unit(n_cdf(cast(-0.25, f32))))),
           and(and(in_unit(n_cdf(cast(0.0, f32))), in_unit(n_cdf(cast(0.25, f32)))),
               and(and(in_unit(n_cdf(cast(1.0, f32))), in_unit(n_cdf(cast(3.0, f32)))),
                   in_unit(n_cdf(cast(8.0, f32))))))
  assert_true(ok, "real n_cdf in [0,1] across grid")
}

-- Contract 2: reflection N(-x) = 1 - N(x) to f32 tolerance, across a grid.
def refl_ok(x: f32) -> bool =
  lt(abs_f32(sub(n_cdf(neg(x)), sub(cast(1.0, f32), n_cdf(x)))), cast(0.00001, f32))

def test_n_cdf_reflection_grid() -> unit ! { Test } = {
  ok = and(and(refl_ok(cast(0.25, f32)), refl_ok(cast(1.0, f32))),
           and(refl_ok(cast(2.0, f32)), refl_ok(cast(3.5, f32))))
  assert_true(ok, "real n_cdf reflection N(-x)=1-N(x)")
}

-- Contract 3: disc = exp(-r t) in [0,1] for r,t >= 0 (non-strict, matching what the
-- Track A greens assume; the strict lower bound 0<disc fails in f32 by underflow).
def disc(r: f32, t: f32) -> f32 = exp(neg(mul(r, t)))

def test_disc_range_grid() -> unit ! { Test } = {
  ok = and(and(in_unit(disc(cast(0.05, f32), cast(1.0, f32))),
               in_unit(disc(cast(0.1, f32), cast(5.0, f32)))),
           and(in_unit(disc(cast(0.0, f32), cast(1.0, f32))),
               in_unit(disc(cast(0.2, f32), cast(10.0, f32)))))
  assert_true(ok, "real disc in [0,1] across grid")
}
