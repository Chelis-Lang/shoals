#!/usr/bin/env python3
"""STEP 4a: AD delta sensitivity surface over a spot x vol grid via vmap(grad).

For each vol sigma (outer loop) we issue ONE `vmap(grad(price_of_spot))` call
that returns the per-spot delta vector in a single batched evaluation -- a true
vmap-of-grad, not a Python map over scalar grad calls. Every surface cell is
validated against the independent true-erf analytic delta N(d1).
"""
import subprocess
import re
import math
import json

import harness as h

CHELIS = h.CHELIS
_num_re = re.compile(r"data=\[([^\]]*)\]")


def eval_vec(expr):
    o = subprocess.run([CHELIS, "eval", expr], capture_output=True, text=True)
    m = _num_re.search(o.stdout)
    if not m:
        raise RuntimeError(o.stderr.strip()[:400] + "\n" + expr[:200])
    return [float(x) for x in m.group(1).split(",")]


def true_delta(s, k, r, sg, t):
    d1 = (math.log(s / k) + (r + 0.5 * sg * sg) * t) / (sg * math.sqrt(t))
    return 0.5 * math.erfc(-d1 / math.sqrt(2))


def vmap_delta_row(spots, k, r, sg, t):
    """One vmap(grad) call: per-spot delta at fixed (k,r,sg,t)."""
    fn = (f"(fn (row: tensor[1, f64]) -> "
          f"{h.BS_CALL}(tensor_to_scalar(sum(row, 0)), {h.lit(k)}, {h.lit(r)}, {h.lit(sg)}, {h.lit(t)}))")
    batch = "to_tensor([" + ", ".join(f"[{h.lit(s)}]" for s in spots) + "])"
    expr = f"vmap(grad({fn}, wrt=row), axis=0)({batch})"
    return eval_vec(expr)  # flat [d0, d1, ...] (shape [n,1])


def main():
    spots = [70.0, 85.0, 100.0, 115.0, 130.0]
    vols = [0.10, 0.20, 0.30, 0.40]
    K, r, t = 100.0, 0.05, 1.0

    surface = []
    max_abs = 0.0
    max_rel = 0.0
    for sg in vols:
        ad_row = vmap_delta_row(spots, K, r, sg, t)
        row = []
        for s, ad in zip(spots, ad_row):
            tv = true_delta(s, K, r, sg, t)
            ae = abs(ad - tv)
            re_ = ae / max(abs(tv), 1e-12)
            max_abs = max(max_abs, ae)
            max_rel = max(max_rel, re_)
            row.append({"S": s, "sigma": sg, "ad_delta": ad, "true_delta": tv,
                        "abs_err": ae, "rel_err": re_})
        surface.append(row)

    # monotonicity check: delta strictly increasing in spot for each vol row
    mono_ok = all(
        all(surface[i][j]["ad_delta"] < surface[i][j + 1]["ad_delta"]
            for j in range(len(spots) - 1))
        for i in range(len(vols))
    )

    print(json.dumps({
        "grid": {"spots": spots, "vols": vols, "K": K, "r": r, "t": t},
        "max_abs_err_vs_true_delta": max_abs,
        "max_rel_err_vs_true_delta": max_rel,
        "delta_increasing_in_spot_all_rows": mono_ok,
        "method": "vmap(grad(price)) one batched call per vol row",
        "surface": surface,
    }, indent=2))


if __name__ == "__main__":
    main()
