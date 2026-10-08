# Python interop manual gate

Verifies that a Shoals-shaped tensor program round-trips through the
`chelis-python` binding (`bindings/python/chelis/` in the chelis
monorepo). This is the v0.1.0 commercial-pitch claim — that
Shoals-style pricing functions are callable from Python — reduced to
its smallest reproducible artifact.

## What it proves

- `chelis.check(source)` accepts a Shoals-shaped `def loss(...)
  -> tensor[f32]` and reports `score == 1.0`.
- `chelis.eval(source, bindings)` evaluates the program against
  numpy float32 inputs and returns a numerically correct discounted
  call payoff (matches a Python reference within 1e-3 absolute).
- An all-out-of-the-money sanity case yields exactly `0.0`.

## What it does NOT prove

- Multi-module reef packages are not linked through the binding —
  `Shoals.Pricing.bs_call_scalar` cannot be evaluated end-to-end here. The
  harness inlines the discounted-payoff arithmetic shape.
- The entrypoint name must be `loss` — this is a property of the
  binding's EvalResult contract, not of Shoals.

## Setup (one-time)

The chelis monorepo's Python binding builds against a venv. From
the chelis checkout:

```sh
cd /path/to/chelis
python3 -m venv py/.venv
py/.venv/bin/pip install -e bindings/python
py/.venv/bin/pip install numpy
```

## Run

From a Shoals checkout:

```sh
cd /path/to/shoals
/path/to/chelis/py/.venv/bin/python manual-gates/python_interop/test_call_price.py
```

Substitute `/path/to/chelis` with your local chelis checkout.

## Expected output

```
  check: score=1.0 typed_nodes=147
  eval: discounted mean payoff = 11.414753 (expected 11.414753)
  eval: all-OTM payoff = 0.0 (expected 0.0)
PASS: chelis Python binding evaluates a Shoals-shaped program
```

A non-zero exit code or a missing `PASS` line indicates regression.

## Pinned versions

- `chelis-python` from chelis monorepo at `0.7.19` or compatible.
  (Last functional verification was under chelis 0.7.6; re-verifying
  under 0.7.19 is an M1+ task per `docs/plan-quant-surface.md`.)
- `numpy` (any reasonably recent release; the harness uses only
  `np.array(..., dtype=np.float32)`).

## Status

Manual gate. Not invoked by `chelis test tests/` and not run on
every push. Run locally when choosing to refresh the
"callable from Python" evidence, recording the exact pinned versions.
It is an optional tool, not a push, merge, or release blocker.
