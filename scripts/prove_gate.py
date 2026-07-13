#!/usr/bin/env python3
"""Keystone canon self-audit gate for Shoals (contract WI-6).

Expected-tier-driven off docs/cnote-import-surface.json, run against the PINNED
RELEASE binary. For every manifest invariant:

  1. Satisfying control holds at exactly its expected_tier_per_pin[pin] -- tier
     drift in EITHER direction fails (better-than-expected => "run the
     de-narrowing motion"). Tier is classified from proof_tier + qualifiers,
     NEVER from the composite_verdict string (contract rule; verdict strings
     may demote, never promote).
  2. Anti-vacuity, TWO layers:
     (a) syntactic (fast necessary condition): the prover-emitted GOAL string
         names the output fn (direct) or the abstracted contract symbol
         (structural). dependency_edges is NOT used -- it is [] across import
         boundaries. This alone is FORGEABLE (a canceling call f(x)-f(x)<c or
         reflexive f(x)==f(x) names the fn but is model-independent).
     (b) metamorphic (the real bar): re-prove the goal with the referenced body
         (direct lane) or abstracted contract (structural lane) SUBSTITUTED by
         several alternatives, and require the outcome to flip under AT LEAST
         ONE -- only a goal whose truth depends on the model survives. A
         self-test runs the same core on committed metamorphic/ forge fixtures
         (canceling + reflexive rejected, a legit green survives).
  3. Violating control breaks with a real IN-DOMAIN witness: status matches the
     declared expectation (failed / unsupported), a counterexample is present
     (when failed), and the counterexample satisfies the manifest's structured
     preconditions (evaluated in python).
  4. Non-vacuity witnesses (`*_guards_satisfiable`) REFUTE at SMT (cvc5
     exhibits a guard-satisfying model).
  5. Defective-model invariants: the goal is DISPROVED with an in-domain
     witness that re-executes at f32 (in_region_defect).

An honesty self-test runs FIRST: the tier classifier must reject verdict
strings wearing a clean mask (a fuzz pass carrying a proven-looking
composite_verdict classifies as fuzz_validated, never proven).

Stdlib-only. Resolves the binary env-first (CHELIS_SMT_BIN / CHELIS_BIN) then
the pin-derived ~/.local/share/chelis/<pin>/ then PATH. Fuzz sample count is
FUZZ_SAMPLES (default from the manifest run_samples); CI dials it down and the
full-sample sweep runs in nightly.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
MANIFEST = REPO / "docs" / "cnote-import-surface.json"
SMT_TIMEOUT_MS = "20000"
DEFAULT_FUZZ_SAMPLES = 25
FUZZ_SEED = "0"

# Contract sec 1 tier vocabulary.
TIERS = {"proven", "proven_modulo_contract", "sound_approximate",
         "fuzz_validated", "disproved", "unknown", "error"}
# Tiers that must carry a tier_upgrade_trigger (below the proven ceiling).
BELOW_PROVEN = {"proven_modulo_contract", "sound_approximate", "fuzz_validated"}
# Name lint: honest vocabulary only (no convergence/limit claims) over canon files.
BANNED_NAME_SUBSTR = ("converge", "stationary", "fixed_point", "ergodic",
                      "limit", "iterat")


def fail(msg: str) -> None:
    print(f"  FAIL: {msg}")


def resolve_bin() -> str:
    for env in ("CHELIS_SMT_BIN", "CHELIS_BIN"):
        v = os.environ.get(env)
        if v and Path(v).expanduser().is_file():
            return str(Path(v).expanduser())
    pin = re.search(r'compiler\s*=\s*"=([0-9.]+)"',
                    (REPO / "reef.toml").read_text()).group(1)
    for rel in ("bin/chelis", "chelis"):
        p = Path.home() / ".local/share/chelis" / pin / rel
        if p.is_file():
            return str(p)
    import shutil
    found = shutil.which("chelis")
    if found:
        return found
    sys.exit("error: no chelis binary (set CHELIS_SMT_BIN or install the pin)")


def classify_tier(rec: dict) -> str:
    """Achieved contract tier from proof_tier + qualifiers + status ONLY.
    composite_verdict is deliberately ignored (it may demote, never promote)."""
    status = rec.get("status")
    tier = rec.get("proof_tier")
    quals = set(rec.get("qualifiers") or [])
    if status == "passed":
        if tier == "smt":
            # A fuzz-discharged contract riding an SMT structural proof is
            # proven_modulo_contract (composites: qualifiers [real_arithmetic, fuzz]).
            return "proven_modulo_contract" if "fuzz" in quals else "proven"
        if tier == "fuzz":
            return "fuzz_validated"
        return "unknown"
    if status == "failed":
        return "disproved"
    if status in ("unsupported", "error"):
        return "unknown" if status == "unsupported" else "error"
    return "unknown"


def honesty_self_test() -> bool:
    """The classifier must key on proof_tier+qualifiers, never composite_verdict."""
    cases = [
        ({"status": "passed", "proof_tier": "smt", "qualifiers": ["real_arithmetic"],
          "composite_verdict": "proven_modulo_real_arithmetic"}, "proven"),
        ({"status": "passed", "proof_tier": "smt", "qualifiers": ["real_arithmetic", "fuzz"],
          "composite_verdict": "proven_modulo_fuzz_validated_contract"}, "proven_modulo_contract"),
        ({"status": "passed", "proof_tier": "fuzz", "qualifiers": ["fuzz", "fuzz_base"],
          "composite_verdict": "fuzz_validated"}, "fuzz_validated"),
        # The adversarial case: a fuzz pass wearing a proven-looking verdict
        # string must classify as fuzz_validated, NOT proven.
        ({"status": "passed", "proof_tier": "fuzz", "qualifiers": ["fuzz"],
          "composite_verdict": "proven_modulo_real_arithmetic"}, "fuzz_validated"),
        ({"status": "failed", "proof_tier": "smt", "qualifiers": ["real_arithmetic"],
          "composite_verdict": "disproved_modulo_real_arithmetic"}, "disproved"),
        ({"status": "unsupported", "proof_tier": None, "qualifiers": [],
          "composite_verdict": "unsupported"}, "unknown"),
    ]
    ok = True
    for rec, want in cases:
        got = classify_tier(rec)
        if got != want:
            fail(f"honesty self-test: classify({rec['composite_verdict']}"
                 f"/{rec['proof_tier']}) = {got}, expected {want}")
            ok = False
    print(f"  honesty self-test: {'PASS' if ok else 'FAIL'} "
          f"({len(cases)} cases, composite_verdict ignored)")
    return ok


def run_prove(binary: str, file: str, fuzz: bool, samples: int) -> dict:
    """Run prove on one canon file; return {property_name: record}."""
    cmd = [binary, "prove", file, "--json"]
    if fuzz:
        # fuzz-only, NOT auto: the transcendental pricers cannot lower to SMT
        # (chelis#434), and --tier auto burns an unbounded SMT-lowering attempt
        # (no --smt-timeout applies to the auto escalation) BEFORE degrading to
        # fuzz. fuzz-only samples directly. Cost is still ~17s per accepted
        # sample (p08), so the satisfying controls dominate: keep the nightly
        # sample budget (FUZZ_SAMPLES) small and measured.
        cmd += ["--tier", "fuzz-only", "--samples", str(samples), "--seed", FUZZ_SEED]
    else:
        cmd += ["--tier", "smt-only", "--smt-timeout", SMT_TIMEOUT_MS]
    out = subprocess.run(cmd, cwd=REPO, capture_output=True, text=True)
    recs: dict[str, dict] = {}
    for line in out.stdout.splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue
        if obj.get("kind") == "property" and "name" in obj and "status" in obj:
            recs[obj["name"]] = obj
        elif obj.get("kind") == "summary":
            for name, s in (obj.get("summary") or {}).items():
                recs.setdefault(name, {**s, "name": name})
    return recs


def smt_value(v: str) -> float | None:
    """Parse an SMT/fuzz counterexample scalar: '1.0', '(/ 1 2)', '(- 3)'."""
    v = v.strip()
    m = re.fullmatch(r"\(/ (-?[\d.]+) (-?[\d.]+)\)", v)
    if m:
        return float(m.group(1)) / float(m.group(2))
    m = re.fullmatch(r"\(- ([\d.]+)\)", v)
    if m:
        return -float(m.group(1))
    try:
        return float(v)
    except ValueError:
        return None


def precondition_holds(pc: dict, env: dict) -> bool | None:
    lhs = env.get(pc["lhs"])
    rhs_spec = pc["rhs"]
    if "const" in rhs_spec:
        rhs = float(rhs_spec["const"])
    else:
        rhs = env.get(rhs_spec["input"])
    if lhs is None or rhs is None:
        return None
    op = pc["op"]
    return {"gt": lhs > rhs, "gte": lhs >= rhs, "lt": lhs < rhs,
            "lte": lhs <= rhs}[op]


def witness_in_domain(cx: dict, preconditions: list) -> tuple[bool, str]:
    env = {}
    for k, v in (cx or {}).items():
        f = smt_value(v) if isinstance(v, str) else v
        if f is not None:
            env[k] = f
    for pc in preconditions:
        r = precondition_holds(pc, env)
        if r is None:
            return False, f"cannot evaluate precondition {pc['lhs']} (missing witness value)"
        if not r:
            return False, f"witness violates precondition {pc['lhs']} {pc['op']} {pc['rhs']}"
    return True, "in-domain"


def goal_names_ref(goal: str, invariant: dict) -> bool:
    """Anti-vacuity via the goal string (dependency_edges are [] across imports).

    Match the output fn at a CALL SITE (`fn(`), not as a bare substring, so a fn
    name that is a prefix of another (tr_crr_call_2step vs
    tr_crr_call_2step_nodisc) does not false-match its sibling."""
    goal = goal or ""
    if invariant["binding"]["references_output_fn"] == "structural":
        return re.search(r"normal_cdf\s*\(", goal) is not None
    fn = invariant.get("_output_fn", "")
    return bool(fn) and re.search(rf"{re.escape(fn)}\s*\(", goal) is not None


def check_control(recs, name, want_status, label) -> tuple[bool, dict | None]:
    rec = recs.get(name)
    if rec is None:
        fail(f"{label}: property `{name}` not found in prover output")
        return False, None
    st = rec.get("status")
    if want_status == "failed":
        ok = st == "failed"
    elif want_status == "unsupported":
        ok = st in ("unsupported", "error")
    else:
        ok = st == want_status
    if not ok:
        fail(f"{label}: `{name}` status={st}, expected {want_status}")
    return ok, rec


def check_instantiation(recs, inv, inst, pin, output_fn) -> bool:
    ok = True
    exp_tier = inv["expected_tier_per_pin"].get(pin)
    controls = inst["controls"]
    inv_with_fn = {**inv, "_output_fn": output_fn}

    # Defective-model invariants have only a violating control (the break).
    if inv.get("defective_model"):
        vg = controls["violating"]
        okc, rec = check_control(recs, vg["name"], "failed", "defect")
        ok = okc and ok
        if rec:
            got = classify_tier(rec)
            if got != exp_tier:
                fail(f"defect `{vg['name']}` tier {got} != expected {exp_tier}")
                ok = False
            cx = rec.get("counterexample")
            if not cx:
                fail(f"defect `{vg['name']}` has no counterexample")
                ok = False
            else:
                ind, why = witness_in_domain(cx, inst.get("preconditions", []))
                if not ind:
                    fail(f"defect witness not in-domain: {why}")
                    ok = False
                else:
                    print(f"    defect `{vg['name']}`: disproved, in-domain arbitrage witness {cx}")
        return ok

    # Satisfying control: exact expected tier + anti-vacuity goal ref.
    sg = controls["satisfying"]
    okc, rec = check_control(recs, sg["name"], "passed", "satisfying")
    ok = okc and ok
    if rec:
        got = classify_tier(rec)
        if got != exp_tier:
            fail(f"TIER DRIFT: `{sg['name']}` achieved {got}, expected {exp_tier} "
                 f"(either direction fails -- run the de-narrowing motion)")
            ok = False
        if not goal_names_ref(rec.get("goal", ""), inv_with_fn):
            fail(f"anti-vacuity: goal for `{sg['name']}` does not name the "
                 f"output fn / contract symbol (goal={rec.get('goal','')[:80]})")
            ok = False

    # Violating control: flips, with an in-domain witness.
    vg = controls["violating"]
    okc, vrec = check_control(recs, vg["name"], vg["expected"], "violating")
    ok = okc and ok
    if vrec and vg["expected"] == "failed":
        cx = vrec.get("counterexample")
        if vg.get("witness_required") and not cx:
            fail(f"violating `{vg['name']}` requires a witness but has none")
            ok = False
        elif cx:
            ind, why = witness_in_domain(cx, inst.get("preconditions", []))
            # fuzz counterexamples are in-domain f32 by construction; SMT ones
            # are checked against the structured preconditions.
            if not ind and vrec.get("proof_tier") != "fuzz":
                fail(f"violating `{vg['name']}` witness not in-domain: {why}")
                ok = False
    return ok


def check_non_vacuity(recs, inv) -> bool:
    nv = inv.get("non_vacuity_witness")
    if not nv:
        return True
    rec = recs.get(nv)
    if rec is None:
        fail(f"non-vacuity `{nv}` not found")
        return False
    if rec.get("status") != "failed":
        fail(f"non-vacuity `{nv}`: status={rec.get('status')}, must REFUTE "
             "(cvc5 exhibits a guard-satisfying model)")
        return False
    return True


# --- Metamorphic anti-vacuity ------------------------------------------------
# A syntactic "the goal names the output fn" check is forgeable: a canceling
# call f(x)-f(x)<c or a reflexive f(x)==f(x) textually names the fn but its
# truth is INDEPENDENT of the model body. The real bar is metamorphic: re-prove
# the goal with the referenced body (direct lane) or abstracted contract
# (structural lane) SUBSTITUTED by several alternatives and require the outcome
# to CHANGE under AT LEAST ONE. A single substitution is unsound (F=const-0
# makes monotonicity F(s2)>=F(s1) trivially true -> false-positive); the
# >=1-of-several rule fixes it. Substitutions use PLAIN forms -- `cast(...)`
# does not lower to SMT, so a cast-wrapped body wrongly reads `unsupported`.
FORGE_DIR = REPO / "metamorphic"
STRUCT_CONTRACT_SUBS = ["2.0", "0.3"]  # constants VIOLATING the normal_cdf contract


def outcome(tier: str) -> str:
    """Coarse metamorphic outcome. proven_modulo_contract collapses to `proved`
    so a structural substitution (which drops the modulo-contract qualifier)
    only counts as a flip when it changes proved<->disproved, not merely the
    qualifier."""
    if tier in ("proven", "proven_modulo_contract"):
        return "proved"
    if tier == "disproved":
        return "disproved"
    return "other"


def prove_standalone(binary: str, source: str) -> str:
    """Prove a self-contained scratch .ch OUTSIDE the repo (package
    auto-detection changes prove semantics); return the single property's
    classified tier, or 'error' if it did not type-check / emit a record."""
    import tempfile
    with tempfile.TemporaryDirectory() as td:
        f = Path(td) / "forge.ch"
        f.write_text(source)
        out = subprocess.run(
            [binary, "prove", str(f), "--json", "--tier", "smt-only",
             "--smt-timeout", SMT_TIMEOUT_MS],
            cwd=td, capture_output=True, text=True)
        for line in out.stdout.splitlines():
            line = line.strip()
            if not line.startswith("{"):
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue
            if obj.get("kind") == "property":
                return classify_tier(obj)
        return "error"


def extract_property_block(pfile: Path, name: str) -> str | None:
    """The `@property NAME ...:` header line plus its indented continuation
    (goal, `with contract`). Stops at the first non-indented line."""
    lines = pfile.read_text().splitlines()
    out: list[str] = []
    started = False
    for ln in lines:
        if not started:
            if re.match(rf"@property\s+{re.escape(name)}\b", ln):
                started = True
                out.append(ln)
            continue
        if ln[:1] in (" ", "\t"):
            out.append(ln)
        else:
            break
    return "\n".join(out) if started else None


def _first_param(sig: str) -> str:
    m = re.search(r"\(\s*(\w+)\s*:", sig)
    return m.group(1) if m else ""


def _ret_type(sig: str) -> str:
    m = re.search(r"->\s*(\w+)", sig)
    return m.group(1) if m else "f32"


def _params(sig: str) -> list[tuple[str, str]]:
    """[(name, type), ...] from a signature's parameter list (return excluded)."""
    return re.findall(r"(\w+)\s*:\s*(\w+)", sig.split("->")[0])


def direct_alt_bodies(sig: str) -> list[tuple[str, str]]:
    """(label, body) alternatives substituted for the output fn body. The
    affine trio -- identity-of-first-param, negated-first-param, a distinct
    constant -- discriminates single-call and first-param-relational goals
    (nonneg, monotone-in-spot, the intrinsic lower bound), but it CANNOT flip
    three shapes the model-free canon adds, so the goal would read spuriously
    vacuous:
      * an upper bound `F <= s` -- every affine body (s, neg(s), 0) is <= s
        under the guards, so none flips;
      * a relation that varies a NON-first parameter (bull spread / strike
        monotonicity) -- an affine body depends only on the first param, so both
        strike-calls collapse to the same value and the goal is reflexive;
      * a convexity/butterfly second difference -- the butterfly of ANY affine
        body is identically zero, so convexity can never flip under the trio.
    The sum-based triple below closes all three: a body that depends on EVERY
    parameter linearly flips upper-bound and non-first-param relations, and its
    concave square `neg(sum^2)` flips convexity. This is a strict STRENGTHENING
    of the metamorphic check (more discriminating substitutions -> harder to
    forge); a truly model-independent goal still flips under none of them. Added
    only for the all-f32 case, which every finance model satisfies: `cast(...)`
    does not lower to SMT, so a mixed-type sum would read `unsupported` and give
    a spurious non-flip. The forge_legit_convex self-test fixture locks the
    `neg_sq_sum` capability (a real convexity green survives)."""
    params = _params(sig)
    p0 = params[0][0] if params else _first_param(sig)
    ret = _ret_type(sig)
    const = "0.0" if ret == "f32" else f"cast(0.0, {ret})"
    alts = [("identity", p0), ("negated", f"neg({p0})"), ("constant", const)]
    if ret == "f32" and params and all(t == "f32" for _, t in params):
        names = [n for n, _ in params]
        s = names[0]
        for n in names[1:]:
            s = f"add({s}, {n})"
        alts += [("sum", s), ("neg_sum", f"neg({s})"),
                 ("neg_sq_sum", f"neg(mul({s}, {s}))")]
    return alts


def _strip_contract(prop_block: str) -> str:
    return "\n".join(ln for ln in prop_block.splitlines() if "with contract" not in ln)


def metamorphic_flips(binary: str, prop_block: str, orig_out: str,
                      structural: bool, fn: str = "", sig: str = "") -> tuple[bool, list]:
    """Re-prove the goal under several substitutions; return (flipped, results).
    flipped == some alternative's outcome differs from the original."""
    results = []
    if structural:
        body = _strip_contract(prop_block)
        for c in STRUCT_CONTRACT_SUBS:
            src = f"module Forge\ndef normal_cdf(x: f32) -> f32 = {c}\n{body}\n"
            t = prove_standalone(binary, src)
            results.append((f"normal_cdf={c}", t, outcome(t)))
    else:
        for label, alt in direct_alt_bodies(sig):
            src = f"module Forge\ndef {fn}{sig} = {alt}\n{prop_block}\n"
            t = prove_standalone(binary, src)
            results.append((f"{label}({alt})", t, outcome(t)))
    flipped = any(o != orig_out for _, _, o in results)
    return flipped, results


def check_metamorphic(inv: dict, models: dict, binary: str) -> bool:
    """Anti-vacuity by metamorphic substitution (supersedes the syntactic
    goal-names-fn check for real F-dependence)."""
    binding = inv["binding"]
    if inv.get("defective_model"):
        ctrl_name = inv["controls"]["violating"]["name"]
        orig_out = "disproved"
    else:
        ctrl_name = inv["controls"]["satisfying"]["name"]
        orig_out = "proved"
    prop_block = extract_property_block(REPO / inv["property"]["file"], ctrl_name)
    if prop_block is None:
        fail(f"metamorphic: property `{ctrl_name}` not found for {inv['id']}")
        return False
    structural = binding["references_output_fn"] == "structural"
    if structural:
        flipped, results = metamorphic_flips(binary, prop_block, orig_out, True)
        lane = "contract"
    else:
        # Model-free invariants set target_model: null; the body substituted is
        # the anchor model's output fn.
        model = models[inv.get("target_model") or inv.get("anchor_model")]
        flipped, results = metamorphic_flips(
            binary, prop_block, orig_out, False,
            fn=model["output_fn"], sig=model["sig"])
        lane = "body"
    if not flipped:
        fail(f"metamorphic VACUITY: {inv['id']} [{lane}] goal outcome "
             f"'{orig_out}' is INVARIANT under every substitution "
             f"{[(l, o) for l, _, o in results]} -- its truth is independent of "
             "the model (a canceling/reflexive forge would pass a syntactic check)")
        return False
    flips = [l for l, _, o in results if o != orig_out]
    print(f"    metamorphic [{lane}] `{ctrl_name}`: orig={orig_out}; "
          f"outcome flips under {flips}")
    return True


def parse_fixture(path: Path) -> tuple[str, str, str]:
    """(fn, sig, property-block) from a self-contained forge fixture .ch."""
    text = path.read_text()
    dm = re.search(r"def\s+(\w+)\s*(\(.*?\)\s*->\s*\w+)\s*=", text)
    pm = re.search(r"@property\s+(\w+)", text)
    fn, sig = dm.group(1), dm.group(2).strip()
    return fn, sig, extract_property_block(path, pm.group(1))


def metamorphic_self_test(binary: str) -> bool:
    """The metamorphic check must REJECT vacuous greens (canceling, reflexive:
    no substitution flips) and SURVIVE a legit green (a substitution flips).
    Runs the same core on the committed forge fixtures under metamorphic/."""
    expect = {  # fixture stem -> should the outcome flip under substitution?
        "forge_canceling": False,     # f(x)-f(x)<c: invariant -> REJECT
        "forge_reflexive": False,     # f(x)==f(x): invariant -> REJECT
        "forge_legit_monotone": True,  # f(x2)>=f(x1): flips under neg -> SURVIVE
        "forge_legit_convex": True,   # butterfly>=0: flips under neg_sq_sum -> SURVIVE
    }
    ok = True
    for stem, should_flip in expect.items():
        path = FORGE_DIR / f"{stem}.ch"
        if not path.is_file():
            fail(f"metamorphic self-test: fixture {path.relative_to(REPO)} missing")
            ok = False
            continue
        fn, sig, block = parse_fixture(path)
        flipped, results = metamorphic_flips(binary, block, "proved", False, fn=fn, sig=sig)
        if flipped != should_flip:
            fail(f"metamorphic self-test: {stem} flipped={flipped}, expected "
                 f"{should_flip} (results {[(l, o) for l, _, o in results]})")
            ok = False
    print(f"  metamorphic self-test: {'PASS' if ok else 'FAIL'} "
          "(canceling+reflexive rejected, legit green survives)")
    return ok


def name_lint(files: list[Path]) -> bool:
    ok = True
    for f in files:
        for m in re.finditer(r"@property\s+(\w+)", f.read_text()):
            nm = m.group(1).lower()
            for bad in BANNED_NAME_SUBSTR:
                if bad in nm:
                    fail(f"name lint: `{m.group(1)}` in {f.name} contains "
                         f"banned term '{bad}' (honest vocabulary only)")
                    ok = False
    return ok


def main() -> None:
    manifest = json.loads(MANIFEST.read_text())
    pin = manifest["chelis_pin"]
    models = {m["id"]: m for m in manifest["models"]}
    binary = resolve_bin()
    samples = int(os.environ.get("FUZZ_SAMPLES", DEFAULT_FUZZ_SAMPLES))
    # The active canon carries NO fuzz_validated invariants at 0.14.0: the real
    # transcendental pricers cannot be fuzzed within any budget (one fuzz sample
    # of one positivity property did not complete in 200s -- chelis#434 / p08),
    # so the direct-pricer positivity invariant is deferred/unverified in the
    # manifest. This fuzz-lane machinery (fuzz-only, gated() below) stays dormant
    # and ready: when a run demonstrates the tier, move the invariant back into
    # `invariants` and run with PROVE_GATE_FUZZ=1.
    include_fuzz = os.environ.get("PROVE_GATE_FUZZ") == "1"
    print(f"prove_gate: binary={binary} pin={pin} fuzz_samples={samples} "
          f"fuzz_lane={'on' if include_fuzz else 'off (nightly)'}")

    def gated(inv: dict) -> bool:
        return include_fuzz or inv["expected_tier_per_pin"].get(pin) != "fuzz_validated"

    ok = honesty_self_test()
    ok = metamorphic_self_test(binary) and ok

    canon_files = [REPO / "properties" / "canonpricing.ch",
                   REPO / "properties" / "canontrees.ch",
                   REPO / "properties" / "canonfixedincome.ch"]
    ok = name_lint([f for f in canon_files if f.exists()]) and ok

    # Group invariants by property file; a file is a fuzz lane if any of its
    # invariants expects fuzz_validated.
    gated_invs = [inv for inv in manifest["invariants"] if gated(inv)]
    by_file: dict[str, list] = {}
    for inv in gated_invs:
        by_file.setdefault(inv["property"]["file"], []).append(inv)
        for inst in inv.get("also_instantiated_for", []):
            by_file.setdefault(inst["property"]["file"], []).append(inv)

    fuzz_files = {inv["property"]["file"] for inv in gated_invs
                  if inv["expected_tier_per_pin"].get(pin) == "fuzz_validated"}
    for inv in gated_invs:
        for inst in inv.get("also_instantiated_for", []):
            if inv["expected_tier_per_pin"].get(pin) == "fuzz_validated":
                fuzz_files.add(inst["property"]["file"])

    recs_by_file = {}
    for fname in sorted(by_file):
        is_fuzz = fname in fuzz_files
        print(f"\n== proving {fname} ({'fuzz' if is_fuzz else 'smt-only'}) ==")
        recs_by_file[fname] = run_prove(binary, fname, is_fuzz, samples)

    skipped = [inv["id"] for inv in manifest["invariants"] if not gated(inv)]
    if skipped:
        print(f"\n== fuzz lane deferred to nightly (PROVE_GATE_FUZZ=1): "
              f"{', '.join(skipped)} ==")

    print("\n== verifying invariants ==")
    for inv in gated_invs:
        exp = inv["expected_tier_per_pin"].get(pin)
        if exp is None:
            fail(f"{inv['id']}: no expected_tier_per_pin entry for pin {pin} "
                 "(stale for this pin)")
            ok = False
            continue
        if exp in BELOW_PROVEN and not inv.get("tier_upgrade_trigger"):
            fail(f"{inv['id']}: expected tier {exp} is below-proven but carries "
                 "no tier_upgrade_trigger")
            ok = False
        # Model-free (kind-scoped) invariants set target_model: null and name the
        # proving-ground model in anchor_model; model-pinned ones use target_model.
        anchor = inv.get("target_model") or inv.get("anchor_model")
        output_fn = models[anchor]["output_fn"]
        recs = recs_by_file[inv["property"]["file"]]
        print(f"  [{inv['id']}] expected {exp}")
        i_ok = check_instantiation(recs, inv,
                                   {"controls": inv["controls"],
                                    "preconditions": inv.get("preconditions", [])},
                                   pin, output_fn)
        i_ok = check_non_vacuity(recs, inv) and i_ok
        # Metamorphic anti-vacuity (SMT lanes): substitute the model body /
        # abstracted contract and require the outcome to flip. The syntactic
        # goal_names_ref check above is a fast necessary condition; this is the
        # real one. (Fuzz-tier invariants -- none active -- are out of scope.)
        if exp != "fuzz_validated":
            i_ok = check_metamorphic(inv, models, binary) and i_ok
        for inst in inv.get("also_instantiated_for", []):
            of = models[inst["target_model"]]["output_fn"]
            irecs = recs_by_file[inst["property"]["file"]]
            print(f"    also-instantiated: {inst['target_model']}")
            i_ok = check_instantiation(irecs, inv, inst, pin, of) and i_ok
        ok = i_ok and ok

    print()
    if ok:
        print("PASS: shoals prove_gate green")
        sys.exit(0)
    print("FAIL: shoals prove_gate")
    sys.exit(1)


if __name__ == "__main__":
    main()
