#!/usr/bin/env python3
"""STEP 4b: AD calibration of a 2-parameter vol model by gradient descent.

Model: a linear-in-log-moneyness volatility curve
    sigma(K) = a + b * ln(K / S)
priced through the chelis Black-Scholes body. Synthetic target prices are
generated from KNOWN (a*, b*) at several strikes; we then recover (a, b) from
those quotes by gradient descent, where the loss gradient d/d(a,b) of the
sum of squared price errors is computed by chelis AD (`grad`, wrt the live
parameter, non-fit quantities inlined as literals -- the supported no-capture
form). Recovery is run over multiple random seeds; we report the parameter
recovery-error distribution and convergence.

Everything differentiable is computed by chelis; Python only does the GD
bookkeeping and random target generation.
"""
import subprocess
import re
import math
import json
import random

import harness as h

CHELIS = h.CHELIS
_num_re = re.compile(r"data=\[([^\]]*)\]")

S, r, t = 100.0, 0.03, 1.0
STRIKES = [80.0, 90.0, 100.0, 110.0, 120.0]


def cval(expr):
    o = subprocess.run([CHELIS, "eval", expr], capture_output=True, text=True)
    txt = o.stdout.strip()
    m = _num_re.search(txt)
    if m:
        return float(m.group(1).split(",")[0])
    try:
        return float(txt)
    except ValueError:
        raise RuntimeError(o.stderr.strip()[:400] + "\nEXPR " + expr[:200])


def sigma_expr(a_lit, b_lit, k):
    # a + b*ln(K/S)
    lm = math.log(k / S)
    return f"add({a_lit}, mul({b_lit}, {h.lit(lm)}))"


def price(a, b, k):
    """chelis BS price with sigma = a + b ln(K/S)."""
    sig = sigma_expr(h.lit(a), h.lit(b), k)
    expr = f"{h.BS_CALL}({h.lit(S)}, {h.lit(k)}, {h.lit(r)}, {sig}, {h.lit(t)})"
    return cval(expr)


def total_loss_grad(a, b, targets):
    """d/da and d/db of sum_k (price(a,b,k) - target_k)^2, each via chelis grad.

    For the gradient wrt `a` the parameter `a` is the live grad variable and `b`
    is an inlined literal (and vice-versa) -- the no-capture form that the grad
    transform accepts.
    """
    # gradient wrt a: live var = av, b literal
    terms_a = []
    terms_b = []
    for k, tgt in zip(STRIKES, targets):
        lm = math.log(k / S)
        # sigma = av + b*lm  (av live)
        sig_a = f"add(av, mul({h.lit(b)}, {h.lit(lm)}))"
        terms_a.append(
            f"(fn (e: f64) -> mul(e, e))(sub({h.BS_CALL}({h.lit(S)}, {h.lit(k)}, {h.lit(r)}, {sig_a}, {h.lit(t)}), {h.lit(tgt)}))")
        sig_b = f"add({h.lit(a)}, mul(bv, {h.lit(lm)}))"
        terms_b.append(
            f"(fn (e: f64) -> mul(e, e))(sub({h.BS_CALL}({h.lit(S)}, {h.lit(k)}, {h.lit(r)}, {sig_b}, {h.lit(t)}), {h.lit(tgt)}))")

    def fold_add(terms):
        acc = terms[0]
        for x in terms[1:]:
            acc = f"add({acc}, {x})"
        return acc

    ga = cval(f"grad((fn (av: f64) -> {fold_add(terms_a)}), wrt=av)({h.lit(a)})")
    gb = cval(f"grad((fn (bv: f64) -> {fold_add(terms_b)}), wrt=bv)({h.lit(b)})")
    return ga, gb


def loss_value(a, b, targets):
    return sum((price(a, b, k) - tgt) ** 2 for k, tgt in zip(STRIKES, targets))


def calibrate(targets, a0, b0, lr=5e-3, iters=200):
    """Adam on (a, b) using chelis AD gradients. Adam normalizes per-parameter
    step magnitude, so it is robust to the large/poorly-scaled raw price-error
    gradient without per-seed lr tuning."""
    a, b = a0, b0
    ma = va = mb = vb = 0.0
    b1, b2, eps = 0.9, 0.999, 1e-8
    hist = []
    for i in range(1, iters + 1):
        ga, gb = total_loss_grad(a, b, targets)
        ma = b1 * ma + (1 - b1) * ga
        mb = b1 * mb + (1 - b1) * gb
        va = b2 * va + (1 - b2) * ga * ga
        vb = b2 * vb + (1 - b2) * gb * gb
        ma_h = ma / (1 - b1 ** i); va_h = va / (1 - b2 ** i)
        mb_h = mb / (1 - b1 ** i); vb_h = vb / (1 - b2 ** i)
        a -= lr * ma_h / (math.sqrt(va_h) + eps)
        b -= lr * mb_h / (math.sqrt(vb_h) + eps)
        if i % 25 == 0 or i == iters:
            hist.append({"iter": i, "a": a, "b": b, "loss": loss_value(a, b, targets)})
    return a, b, hist


def main():
    rng = random.Random(20260619)
    runs = []
    for seed in range(6):
        # known true params (a* ~ ATM vol level, b* ~ skew slope)
        a_true = rng.uniform(0.15, 0.30)
        b_true = rng.uniform(-0.15, -0.02)  # typical downward equity skew
        targets = [price(a_true, b_true, k) for k in STRIKES]

        # random start away from truth
        a0 = a_true + rng.uniform(-0.08, 0.08)
        b0 = b_true + rng.uniform(-0.08, 0.08)

        a_fit, b_fit, hist = calibrate(targets, a0, b0)
        runs.append({
            "seed": seed,
            "a_true": a_true, "b_true": b_true,
            "a0": a0, "b0": b0,
            "a_fit": a_fit, "b_fit": b_fit,
            "a_err": abs(a_fit - a_true), "b_err": abs(b_fit - b_true),
            "final_loss": hist[-1]["loss"],
            "convergence": hist,
        })

    a_errs = [x["a_err"] for x in runs]
    b_errs = [x["b_err"] for x in runs]
    losses = [x["final_loss"] for x in runs]
    summary = {
        "n_seeds": len(runs),
        "a_err_max": max(a_errs), "a_err_mean": sum(a_errs) / len(a_errs),
        "b_err_max": max(b_errs), "b_err_mean": sum(b_errs) / len(b_errs),
        "final_loss_max": max(losses),
        "model": "sigma(K) = a + b*ln(K/S), priced via chelis BS, AD gradient descent",
    }
    print(json.dumps({"summary": summary, "runs": runs}, indent=2))


if __name__ == "__main__":
    main()
