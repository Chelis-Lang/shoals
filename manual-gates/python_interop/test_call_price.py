"""Phase 3l Python-FFI gate: evaluate a Shoals-shaped Black-Scholes
payoff from Python via the chelis package.

Mirrors `bindings/python/tests/manual_phase3b.py` (the existing
chelis-python manual gate) but parameterizes on a Shoals-shaped
European-call discounted payoff. The full BS analytic price needs
`Nautilus.Special.erfc` from a multi-module reef package, which the
Python binding does not (yet) link; this harness restricts to the
subset of vector tensor ops that the binding's evaluator supports
(elementwise sub/relu/mul, axis-0 mean), which is enough to run
the discounted-payoff form of `Shoals.Pricing.bs_call_scalar`'s
intrinsic Monte-Carlo expectation.

Entrypoint name MUST be `loss` for the binding to expose it as a
named root; this matches `manual_phase3b.py` and is a property of
the binding's eval JSON contract, not of Shoals.

PASS criterion: discounted mean payoff matches a Python reference
to within 1e-3 absolute.
"""

from __future__ import annotations

import math

import chelis
import numpy as np


# Discounted European call payoff at maturity, vectorized over a
# tensor of terminal prices. The full BS analytic form (with
# N(d1)/N(d2) via erfc) lives in Shoals; this harness only needs
# to demonstrate that a Shoals-shaped tensor expression round-trips
# through the chelis Python binding.
#
# Naming: `loss` is required by the binding to surface a named
# root in EvalResult; the body is a textbook discounted call
# payoff `mean(relu(S_T - K) * disc)`.
PROGRAM = """def loss(
  st: tensor[5, f32],
  k_vec: tensor[5, f32],
  disc_vec: tensor[5, f32]
) -> tensor[f32] = mean(mul(relu(sub(st, k_vec)), disc_vec), 0)
"""


def main() -> None:
    # 1. Type-check the program through the Python binding.
    check = chelis.check(PROGRAM)
    assert isinstance(check, chelis.CheckResult), type(check)
    assert check.score == 1.0, f"check failed, score={check.score}"
    print(f"  check: score=1.0 typed_nodes={check.typed_nodes}")

    # 2. Evaluate at S_T in {90,100,110,120,130}, K=100, r=0.05, T=1.
    #    Discount factor exp(-0.05) ~ 0.95123.
    rate = 0.05
    maturity = 1.0
    disc = math.exp(-rate * maturity)
    st_values = [90.0, 100.0, 110.0, 120.0, 130.0]
    strike = 100.0

    bindings = {
        "st": np.array(st_values, dtype=np.float32),
        "k_vec": np.array([strike] * 5, dtype=np.float32),
        "disc_vec": np.array([disc] * 5, dtype=np.float32),
    }
    result = chelis.eval(PROGRAM, bindings)
    assert isinstance(result, chelis.EvalResult)
    root = next(r for r in result.roots if r.name == "loss")
    actual = root.value.data[0]
    expected = sum(max(s - strike, 0.0) for s in st_values) / len(st_values) * disc
    assert abs(actual - expected) < 1e-3, f"got {actual}, want {expected}"
    print(f"  eval: discounted mean payoff = {actual:.6f} (expected {expected:.6f})")

    # 3. All-OTM sanity: every S_T < K, mean payoff must be exactly 0.
    bindings_otm = {
        "st": np.array([80.0, 85.0, 90.0, 92.0, 95.0], dtype=np.float32),
        "k_vec": np.array([strike] * 5, dtype=np.float32),
        "disc_vec": np.array([disc] * 5, dtype=np.float32),
    }
    result_otm = chelis.eval(PROGRAM, bindings_otm)
    payoff_otm = next(r for r in result_otm.roots if r.name == "loss").value.data[0]
    assert payoff_otm == 0.0, f"all-OTM payoff should be 0, got {payoff_otm}"
    print(f"  eval: all-OTM payoff = {payoff_otm} (expected 0.0)")

    print("PASS: chelis Python binding evaluates a Shoals-shaped program")


if __name__ == "__main__":
    main()
