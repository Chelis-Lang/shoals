#!/usr/bin/env python3
"""Generate a chelis test file that forces each n_cdf(x_i) value to surface in the
failure message (assert_close against a sentinel always fails, printing `got <value>`).

We then parse those values back and compare to scipy's canonical normal CDF.

Grid is symmetric and covers the tails plus the central region where erfc loses
the most relative precision when its argument is large in magnitude.
"""
import sys


def fmt(x: float) -> str:
    # Emit a literal chelis can parse as f32 with full round-trip precision.
    return repr(float(x))


def main() -> None:
    # Symmetric grid: dense in [-4,4], plus deep tails to probe saturation to 0/1.
    grid = []
    x = -6.0
    while x <= 6.0001:
        grid.append(round(x, 4))
        x += 0.25
    # explicit deep tails
    grid = [-8.0, -7.0] + grid + [7.0, 8.0]
    # de-dup preserving order
    seen = set()
    uniq = []
    for g in grid:
        if g not in seen:
            seen.add(g)
            uniq.append(g)
    grid = uniq

    lines = []
    lines.append("module ProofInfraContract.Tests.NcdfProbeTest")
    lines.append("import Std.Test (assert_close)")
    lines.append("import ProofInfraContract.Contract (n_cdf)")
    lines.append("")
    # One test per grid point. The sentinel guarantees a FAIL, whose message
    # carries the exact f32 value chelis computed for n_cdf(x_i).
    for i, g in enumerate(grid):
        tag = f"x_{i:03d}"
        lines.append(
            f"def test_{tag}() -> unit ! {{ Test }} = {{"
        )
        lines.append(
            f"  assert_close(n_cdf(cast({fmt(g)}, f32)), cast(-999.0, f32), "
            f"cast(0.0000001, f32), \"PROBE {tag} x={fmt(g)}\")"
        )
        lines.append("}")
    out = "\n".join(lines) + "\n"
    sys.stdout.write(out)
    # Also emit the grid as a sidecar for the comparison step.
    with open(sys.argv[1], "w") as f:
        for i, g in enumerate(grid):
            f.write(f"x_{i:03d}\t{repr(float(g))}\n")


if __name__ == "__main__":
    main()
