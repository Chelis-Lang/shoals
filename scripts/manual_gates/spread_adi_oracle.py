#!/usr/bin/env python3
"""Independent spread references, domain refinement, and numerical controls.

Owning spec: spec/shoals_quant_surface.md section 2.10 (PDE methods).
Run .venv/bin/python scripts/manual_gates/spread_adi_oracle.py; exit 0 means
an empty failure list. This is an opt-in local check and does not run in CI. --reference-only
checks the independent numerical oracle without invoking Chelis.

The reference conditions on the second GBM's standard normal variate. The
first terminal log price then has mean m and variance v; its conditional call
expectation against H=S2+K is exp(m+v/2)*Phi((m+v-log(H))/sqrt(v)) minus
H*Phi((m-log(H))/sqrt(v)). Composite Simpson integrates this expectation over
[-12,12], independently of the finite-difference algorithm. Exchange values
are also checked against Margrabe, and doubled integration resolution must
agree. No Monte Carlo golden, Kirk approximation, or PDE transcription enters
the oracle.

Large refinements compile and execute the official native C backend; the
small mixed-operator prices also agree with the evaluator. This keeps the
manual matrix outside the optional evaluator budget.

Private-driver probes copy the current PDE module body verbatim into isolated
temporary programs so the public export list stays unchanged. Both healthy
and mutated copies execute; a compiler failure is never accepted as a killed
numerical mutation. Original tracked sources are never modified.
"""

from __future__ import annotations

import argparse
import ast
import json
import math
import re
import struct
import subprocess
import tempfile
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
CASES = {
    "documented_spread": ((100, 95, 5, .05, 0, 0, .2, .3, .5, 1), 10.211500827214174),
    "negative_correlation": ((100, 95, 5, .05, .02, .01, .2, .3, -.7, 1), 17.07359432723349),
    "negative_rate_yields": ((100, 110, 8, -.02, .04, .01, .25, .35, .6, 2), 6.296768243316105),
    "high_volatility": ((100, 95, 5, .03, 0, 0, .6, .5, .8, 2), 20.221735902624737),
}


def normal_cdf(z: float) -> float:
    return .5 * math.erfc(-z / math.sqrt(2))


def conditional_price(params: tuple[float, ...], intervals: int = 4096) -> float:
    if intervals < 2 or intervals % 2:
        raise ValueError("Simpson integration requires a positive even interval count")
    s1, s2, strike, rate, q1, q2, sigma1, sigma2, rho, horizon = params
    if horizon == 0:
        return max(s1 - s2 - strike, 0)
    variance = sigma1 * sigma1 * horizon * (1 - rho * rho)
    sd = math.sqrt(variance)
    mean0 = math.log(s1) + (rate - q1 - .5 * sigma1 * sigma1) * horizon
    sqrt_t = math.sqrt(horizon)

    def integrand(z: float) -> float:
        asset2 = s2 * math.exp((rate - q2 - .5 * sigma2 * sigma2) * horizon + sigma2 * sqrt_t * z)
        threshold = asset2 + strike
        mean = mean0 + rho * sigma1 * sqrt_t * z
        forward1 = math.exp(mean + .5 * variance)
        if threshold <= 0:
            payoff = forward1 - threshold
        elif sd == 0:
            payoff = max(forward1 - threshold, 0)
        else:
            d2 = (mean - math.log(threshold)) / sd
            payoff = forward1 * normal_cdf(d2 + sd) - threshold * normal_cdf(d2)
        return payoff * math.exp(-.5 * z * z) / math.sqrt(2 * math.pi)

    step = 24 / intervals
    weighted = math.fsum((1 if i in (0, intervals) else 4 if i % 2 else 2) * integrand(-12 + i * step)
                         for i in range(intervals + 1))
    return math.exp(-rate * horizon) * step * weighted / 3


def exchange_price(params: tuple[float, ...]) -> float:
    s1, s2, _, _, q1, q2, sigma1, sigma2, rho, horizon = params
    forward1, forward2 = s1 * math.exp(-q1 * horizon), s2 * math.exp(-q2 * horizon)
    sd = math.sqrt((sigma1 * sigma1 + sigma2 * sigma2 - 2 * rho * sigma1 * sigma2) * horizon)
    if sd == 0:
        return max(forward1 - forward2, 0)
    d1 = math.log(forward1 / forward2) / sd + .5 * sd
    return forward1 * normal_cdf(d1) - forward2 * normal_cdf(d1 - sd)


def reference_checks() -> tuple[dict, list[str]]:
    observations, failures = {}, []
    for name, (params, expected) in CASES.items():
        coarse, fine = conditional_price(params), conditional_price(params, 8192)
        observations[name] = {"reference": fine, "resolution_delta": abs(fine - coarse)}
        if abs(fine - coarse) > 1e-8 or abs(fine - expected) > 1e-8:
            failures.append(f"{name}: independent integration drifted")
    for rho in (-.9, -.8, 0, .5, .9):
        params = (100, 100, 0, .05, .02, .01, .2, .3, rho, 1)
        if abs(conditional_price(params, 8192) - exchange_price(params)) > 1e-8:
            failures.append(f"conditional integration disagrees with Margrabe at rho={rho}")
    return observations, failures


def decode(value: dict):
    kind, payload = value["type"], value["value"]
    if kind == "scalar":
        if payload["dtype"] != "f32":
            raise ValueError("unexpected scalar dtype")
        return struct.unpack(">f", bytes.fromhex(payload["bits"]))[0]
    if kind in ("tuple", "list"):
        return [decode(item) for item in payload]
    if kind == "bool":
        return payload
    raise ValueError(f"unsupported probe value {kind}")


def evaluate(source: str, probe: str, label: str):
    with tempfile.TemporaryDirectory(prefix="shoals-spread-adi-") as scratch:
        path = Path(scratch) / "probe.ch"
        path.write_text(source + "\n" + probe + "\n")
        subprocess.run(["chelis", "fmt", "--inplace", str(path)], check=True, capture_output=True, text=True)
        done = subprocess.run(["chelis", "eval", "--file", str(path), "--json", "--timeout", "1500"],
                              capture_output=True, text=True, timeout=1650)
        if done.returncode:
            raise RuntimeError(f"{label} failed to execute: {done.stderr[-2000:]}")
        record = json.loads(done.stdout)
        if record.get("schema_version") != 4:
            raise ValueError("unrecognized evaluator schema")
        roots = [root for root in record["roots"] if root.get("name") == "probe" or root.get("name", "").startswith("probe.")]
        if len(roots) == 1 and roots[0]["name"] == "probe":
            result = decode(roots[0]["value"])
        else:
            by_name = {root["name"]: root for root in roots}
            if not roots or len(by_name) != len(roots) or set(by_name) != {f"probe.{i}" for i in range(len(roots))}:
                raise ValueError("probe missing, duplicated, or malformed")
            result = [decode(by_name[f"probe.{i}"]["value"]) for i in range(len(roots))]
        print(f"{label}: {result}", flush=True)
        return result



def numeric_native_value(value):
    if isinstance(value, (tuple, list)):
        return [numeric_native_value(item) for item in value]
    if type(value) not in (int, float) or not math.isfinite(value):
        raise ValueError("native probe must contain finite numeric values")
    return value


def decode_native(stdout: str):
    roots = {}
    for line in stdout.splitlines():
        name, separator, value = line.partition(" = ")
        if separator and (name == "probe" or name.startswith("probe.")):
            if name in roots:
                raise ValueError("duplicated native probe")
            roots[name] = numeric_native_value(ast.literal_eval(value))
    if set(roots) == {"probe"}:
        return roots["probe"]
    if not roots or set(roots) != {f"probe.{i}" for i in range(len(roots))}:
        raise ValueError("native probe missing or malformed")
    return [roots[f"probe.{i}"] for i in range(len(roots))]


def evaluate_native(source: str, probe: str, label: str):
    with tempfile.TemporaryDirectory(prefix="shoals-spread-adi-native-") as scratch:
        path = Path(scratch) / "probe.ch"
        path.write_text(source + "\n" + probe + "\n")
        subprocess.run(["chelis", "fmt", "--inplace", str(path)], check=True, capture_output=True, text=True)
        output = Path(scratch) / "compiled"
        start = time.monotonic()
        built = subprocess.run(["chelis", "build", str(path), "--target", "c", "-o", str(output)],
                               capture_output=True, text=True, timeout=120)
        if built.returncode:
            raise RuntimeError(f"{label} failed to compile: {built.stderr[-2000:]}")
        done = subprocess.run([str(output / path.stem)], capture_output=True, text=True, timeout=1500)
        if done.returncode:
            raise RuntimeError(f"{label} failed to execute: {done.stderr[-2000:]}")
        result = decode_native(done.stdout)
        print(f"{label}: {result} ({time.monotonic() - start:.3f}s including build)", flush=True)
        return result


def refinement_checks(source: str) -> tuple[dict, list[str]]:
    # Native execution keeps the large matrix outside the optional evaluator
    # budget. All calls still execute the current Surf implementation, and
    # evaluator/native agreement is checked separately on both mixed-term signs.
    probe = """def documented_price(n_x: i64, n_t: i64) -> f32 = pde_spread_option_adi(100.0f32, 95.0f32, 5.0f32, 0.05f32, 0.0f32, 0.0f32, 0.2f32, 0.3f32, 0.5f32, 1.0f32, n_x, n_x, n_t)
probe = [documented_price(41i64, 50i64), documented_price(81i64, 100i64), documented_price(161i64, 200i64), documented_price(161i64, 25i64), documented_price(161i64, 50i64), documented_price(161i64, 100i64), pde_spread_option_adi(100.0f32, 95.0f32, 5.0f32, 0.05f32, 0.02f32, 0.01f32, 0.2f32, 0.3f32, -0.7f32, 1.0f32, 161i64, 161i64, 200i64), pde_spread_option_adi(100.0f32, 110.0f32, 8.0f32, -0.02f32, 0.04f32, 0.01f32, 0.25f32, 0.35f32, 0.6f32, 2.0f32, 121i64, 161i64, 200i64), pde_spread_option_adi(100.0f32, 95.0f32, 5.0f32, 0.03f32, 0.0f32, 0.0f32, 0.6f32, 0.5f32, 0.8f32, 2.0f32, 161i64, 161i64, 200i64), pde_spread_option_adi(100.0f32, 100.0f32, 0.0f32, 0.0f32, 0.0f32, 0.0f32, 0.2f32, 0.2f32, 0.9f32, 1.0f32, 321i64, 321i64, 400i64), pde_spread_option_adi(100.0f32, 100.0f32, 0.0f32, 0.0f32, 0.0f32, 0.0f32, 0.2f32, 0.2f32, -0.9f32, 1.0f32, 81i64, 81i64, 100i64)]"""
    prices = evaluate_native(source, probe, "native mesh/time/reference matrix")
    if len(prices) != 11:
        raise ValueError("native refinement price vector has the wrong length")
    failures = []
    exact = CASES["documented_spread"][1]
    errors = [abs(px - exact) for px in prices[:3]]
    for grid, error, tolerance in zip((41, 81, 161), errors, (.10, .03, .01)):
        if error > tolerance:
            failures.append(f"{grid}x{grid} spread reference error {error} exceeds {tolerance}")
    if errors[1] >= .5 * errors[0] or errors[2] >= .5 * errors[1]:
        failures.append("fixed documented spread mesh errors did not shrink under refinement")
    time_prices = [*prices[3:6], prices[2]]
    increments = [abs(b - a) for a, b in zip(time_prices, time_prices[1:])]
    if increments[1] >= .6 * increments[0] + .0002 or increments[2] >= .6 * increments[1] + .0002:
        failures.append("fixed-mesh time-refinement increments did not shrink beyond f32 allowance")
    for name, px, tolerance in zip(("negative_correlation", "negative_rate_yields", "high_volatility"), prices[6:9], (.02, .02, .12)):
        if abs(px - CASES[name][1]) > tolerance:
            failures.append(f"{name} native independent-reference error exceeds {tolerance}")
    # Small effective exchange volatility at high positive correlation needs
    # a finer spatial grid for the same 0.03 accuracy tolerance.
    for rho, px in zip((.9, -.9), prices[9:]):
        params = (100, 100, 0, 0, 0, 0, .2, .2, rho, 1)
        if abs(px - exchange_price(params)) > .03:
            failures.append(f"near-endpoint correlation {rho} exchange error exceeds 0.03")
    return {"mesh_prices": prices[:3], "mesh_errors": errors,
            "time_prices": time_prices, "time_increments": increments,
            "stress_prices": prices[6:9], "near_endpoint_prices": prices[9:]}, failures


def property_corner_checks(source: str) -> tuple[dict, list[str]]:
    # Execute the exact property helper, not a parallel grid-selection copy.
    helpers = (REPO / "properties/pde.ch").read_text().split("@property", 1)[0]
    helpers = re.sub(r"^(?:module|import) .*\n", "", helpers, flags=re.M)
    points = (-.8, .5, .5000000596046448, .8)
    calls = ", ".join(f"spread_property_price(4.0f32, {rho!r}f32)" for rho in points)
    prices = evaluate_native(source + "\n" + helpers, f"probe = [{calls}]", "property corner and mesh-branch boundary")
    if len(prices) != len(points):
        raise ValueError("property corner vector has the wrong length")
    failures, errors = [], []
    for rho, px in zip(points, prices):
        exact = exchange_price((4, 4, 0, 0, 0, 0, .2, .2, rho, 1))
        error = abs(px - exact)
        errors.append(error)
        if error >= .004 * 4:
            failures.append(f"property corner rho={rho} exceeds unchanged 0.004*spot tolerance")
    return {"property_corner_correlations": points, "property_corner_prices": prices,
            "property_corner_errors": errors}, failures

def runtime_checks() -> tuple[dict, list[str]]:
    source = (REPO / "src/pde.ch").read_text()
    source = re.sub(r"^(?:module|export) .*\n", "", source, flags=re.M)
    failures, observations = [], {}
    corners, corner_failures = property_corner_checks(source)
    observations.update(corners)
    failures.extend(corner_failures)
    domain_probe = """def domain_probe(width_scale: f32) -> (f32, f32) = {
  w1 = pde_adi_log_half_width(0.2f32, 0.05f32, 0.0f32, 1.0f32)
  w2 = pde_adi_log_half_width(0.3f32, 0.05f32, 0.0f32, 1.0f32)
  base = pde_adi_spread_driver(100.0f32, 95.0f32, 5.0f32, 0.05f32, 0.0f32, 0.0f32, 0.2f32, 0.3f32, 0.5f32, 1.0f32, 81i64, 81i64, 100i64, w1, w2)
  wider = pde_adi_spread_driver(100.0f32, 95.0f32, 5.0f32, 0.05f32, 0.0f32, 0.0f32, 0.2f32, 0.3f32, 0.5f32, 1.0f32, 121i64, 121i64, 100i64, mul(width_scale, w1), mul(width_scale, w2))
  (base, wider)
}
probe = domain_probe(1.5f32)"""
    prices = evaluate_native(source, domain_probe, "same-spacing domain refinement")
    observations["domain_prices"] = prices
    if not all(math.isfinite(x) for x in prices) or abs(prices[0] - prices[1]) > .002:
        failures.append("domain refinement moved the center price beyond 0.002")

    mixed_probe = "probe = [pde_spread_option_adi(100.0f32, 100.0f32, 0.0f32, 0.0f32, 0.0f32, 0.0f32, 0.2f32, 0.2f32, 0.5f32, 1.0f32, 21i64, 21i64, 20i64), pde_spread_option_adi(100.0f32, 100.0f32, 0.0f32, 0.0f32, 0.0f32, 0.0f32, 0.2f32, 0.2f32, -0.8f32, 1.0f32, 21i64, 21i64, 20i64)]"
    needle = "cross_coef = mul(rho, mul(sigma1, sigma2))"
    if source.count(needle) != 1:
        raise ValueError("mixed-operator mutation must match exactly one coefficient")
    mutant = source.replace(needle, "cross_coef = mul(0.5f32, mul(rho, mul(sigma1, sigma2)))")
    healthy = evaluate_native(source, mixed_probe, "healthy mixed operator")
    interpreted = evaluate(source, mixed_probe, "evaluator mixed operator")
    if len(interpreted) != 2 or any(abs(a - b) > .0002 for a, b in zip(healthy, interpreted)):
        failures.append("both-sign mixed prices disagree between evaluator and native C")
    corrupted = evaluate_native(mutant, mixed_probe, "halved mixed operator control")
    observations["mixed_prices"] = [healthy, corrupted]
    for i, (target, tolerance) in enumerate(((7.965567455405798, .15), (15.048450763496524, .4))):
        if not math.isfinite(healthy[i]) or not math.isfinite(corrupted[i]) or abs(healthy[i] - target) > tolerance or abs(corrupted[i] - target) <= tolerance:
            failures.append(f"mixed-operator oracle did not separate healthy and halved correlation at sign {i}")

    boundary_probe = "probe = index(index(pde_adi_boundary_grid([110.0f32], [95.0f32], 5.0f32, 0.05f32, 0.02f32, 0.01f32, 1.0f32), 0i64), 0i64)"
    needle = "disc_k = mul(k, exp(neg(mul(r, tau))))"
    if source.count(needle) != 1:
        raise ValueError("boundary mutation must match exactly one discount")
    mutant = source.replace(needle, "disc_k = k")
    healthy = evaluate(source, boundary_probe, "healthy time-dependent boundary")
    corrupted = evaluate(mutant, boundary_probe, "undiscounted strike boundary control")
    expected = max(110 * math.exp(-.02) - 95 * math.exp(-.01) - 5 * math.exp(-.05), 0)
    observations["boundary_values"] = [healthy, corrupted]
    if abs(healthy - expected) > .00002 or abs(corrupted - expected) <= .1:
        failures.append("boundary oracle did not reject undiscounted strike")

    # A manufactured 3x4 state makes stage boundaries observable directly:
    # distant edges in a real pricing domain cannot expose every timing bug.
    stage_probe = """def stage_probe(dt: f32) -> List[f32] = {
  v = [[1.0f32, 2.0f32, 3.0f32, 4.0f32], [5.0f32, 6.0f32, 7.0f32, 8.0f32], [9.0f32, 10.0f32, 11.0f32, 12.0f32]]
  boundary = [[13.0f32, 14.0f32, 15.0f32, 16.0f32], [17.0f32, 18.0f32, 19.0f32, 20.0f32], [21.0f32, 22.0f32, 23.0f32, 24.0f32]]
  grid = pde_adi_step(v, (0.1f32, -0.3f32, 0.1f32), (0.1f32, -0.3f32, 0.1f32), 0.1f32, 1.0f32, 1.0f32, 3i64, 4i64, boundary, dt, false)
  [index(index(grid, 0i64), 1i64), index(index(grid, 2i64), 2i64), index(index(grid, 1i64), 0i64), index(index(grid, 1i64), 3i64)]
}
probe = stage_probe(0.1f32)"""
    setter = re.search(r"def pde_adi_set_boundary\([^\n]*\n.*?(?=\n-- Craig-Sneyd)", source, re.S)
    if not setter:
        raise ValueError("stage-boundary mutation site not found")
    signature = setter.group().split(" =", 1)[0]
    mutant = source[:setter.start()] + signature + " = v\n" + source[setter.end():]
    healthy = evaluate(source, stage_probe, "healthy rectangular stage perimeter")
    corrupted = evaluate(mutant, stage_probe, "omitted stage-perimeter control")
    observations["stage_perimeters"] = [healthy, corrupted]
    if healthy != [14, 23, 17, 20] or corrupted == healthy or not all(math.isfinite(x) for x in corrupted):
        failures.append("stage-perimeter oracle did not reject omitted updates")
    refinement, refinement_failures = refinement_checks(source)
    observations.update(refinement)
    failures.extend(refinement_failures)
    return observations, failures


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reference-only", action="store_true")
    args = parser.parse_args()
    observations, failures = reference_checks()
    if not args.reference_only:
        runtime, runtime_failures = runtime_checks()
        observations.update(runtime)
        failures.extend(runtime_failures)
    print(json.dumps({"observations": observations, "failures": failures}, indent=2))
    return bool(failures)


if __name__ == "__main__":
    raise SystemExit(main())
