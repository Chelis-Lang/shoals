#!/usr/bin/env python3
"""Audit version-pin consistency and workaround-citation staleness for Shoals.

Two modes (downstream shell repo contract §2 pin hygiene, §4 staleness audit):

  --pins-only   Offline, deterministic. Assert the reef.toml compiler pin equals
                the literal CHELIS_TAG / CHELIS_VERSION env pins in EVERY
                toolchain-installing workflow. This is the blocking CI guard
                (the `hard-rule-guard` job); it never touches the network.

  (default)     Pins check, then a citation-staleness scan: collect every
                `chelis#NNN` citation in the repo and ask GitHub whether each is
                CLOSED upstream. A CLOSED issue still cited outside
                `docs/UPSTREAM_BUGS.md` §Archived is stale (exit 1) — the
                default failure state the contract names. This is a pin-bump
                checklist step, not per-PR CI.

Offline tolerance: if `gh` is missing or a call fails (no network / no auth),
the staleness scan prints a warning and SKIPS the upstream-state check. It never
fails closed on the network — a stale citation is caught at the next online run.

Stdlib-only, per the repo scripting policy (AGENTS.md). Run from anywhere in the
tree; the repo root is found by walking up to the reef.toml.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

CHELIS_REPO = "Chelis-Lang/chelis"


def find_repo_root() -> Path:
    d = Path.cwd()
    while d != d.parent:
        if (d / "reef.toml").exists():
            return d
        d = d.parent
    sys.exit("error: cannot find repo root (no reef.toml)")


def read_reef_pin(root: Path) -> str:
    text = (root / "reef.toml").read_text()
    m = re.search(r'compiler\s*=\s*"=([^"]+)"', text)
    if not m:
        sys.exit("error: cannot parse compiler pin from reef.toml")
    return m.group(1)


# A workflow "installs the chelis toolchain" if it downloads the released chelis
# tarball (inline or via the shared composite action) or builds chelis from
# source. Contract §2 requires every such workflow to carry a matching literal
# CHELIS_TAG / CHELIS_VERSION env pair, guarded offline. These markers identify
# those workflows from their text without running them; a workflow with no chelis
# install (nothing to pin) is correctly exempt. A composite action
# (`./.github/actions/install-chelis`) hides the raw `gh release download` /
# `repository:` strings behind the action file, so the action reference itself is
# a marker — otherwise env-pin enforcement would silently skip those workflows.
# Kept identical to economoist's guard (Scaffolding Drift Rule: shells share one
# shape) even where a marker matches no current shoals workflow.
TOOLCHAIN_INSTALL_MARKERS = (
    "gh release download",          # download the published chelis tarball
    "actions/install-chelis",       # install the release tarball via the composite action
    "repository: Chelis-Lang/chelis",  # checkout chelis source to build it
    "cargo build --release -p chelis-cli",  # build chelis from source
)


def installs_toolchain(text: str) -> bool:
    return any(marker in text for marker in TOOLCHAIN_INSTALL_MARKERS)


def workflow_files(root: Path) -> list[Path]:
    wf_dir = root / ".github" / "workflows"
    if not wf_dir.exists():
        sys.exit(f"error: {wf_dir} not found")
    return sorted(wf_dir.glob("*.yml")) + sorted(wf_dir.glob("*.yaml"))


def read_workflow_pins(text: str) -> dict[str, str]:
    """The literal CHELIS_TAG / CHELIS_VERSION env pins in one workflow, keyed by
    env NAME and normalized to the bare version (a `v` prefix and surrounding
    quotes are stripped) for comparison with the reef.toml pin.

    Only literal `NAME: <value>` forms are read (the YAML env block). Runtime
    `echo "NAME=..." >> $GITHUB_ENV` derivations are deliberately ignored: the
    guard runs offline and cannot evaluate them — that reef-derived-only gap is
    exactly what a drifting literal pin would hide, so the literal must exist.
    """
    pins: dict[str, str] = {}
    for m in re.finditer(r'CHELIS_TAG:\s*["\']?v?([\d.]+)', text):
        pins["CHELIS_TAG"] = m.group(1)
    for m in re.finditer(r'CHELIS_VERSION:\s*["\']?v?([\d.]+)', text):
        pins["CHELIS_VERSION"] = m.group(1)
    return pins


def check_pins(root: Path) -> bool:
    reef_pin = read_reef_pin(root)
    ok = True
    guarded: list[str] = []
    for wf in workflow_files(root):
        text = wf.read_text()
        pins = read_workflow_pins(text)
        toolchain = installs_toolchain(text)

        if toolchain:
            for required in ("CHELIS_TAG", "CHELIS_VERSION"):
                if required not in pins:
                    print(f"MISSING: {wf.name} installs the chelis toolchain but "
                          f"has no literal {required} env pin")
                    ok = False
            guarded.append(wf.name)

        # Any literal pin present (toolchain-installing or not) must match reef.
        for name, val in pins.items():
            if val != reef_pin:
                print(f"MISMATCH: reef.toml={reef_pin} but {wf.name}:{name}={val}")
                ok = False

    if not guarded:
        print("WARNING: no toolchain-installing workflow found to guard")
        ok = False

    if ok:
        print(f"All chelis pins consistent: {reef_pin}")
        print(f"Guarded toolchain workflows ({len(guarded)}): {', '.join(guarded)}")
    return ok


SCAN_EXTS = ("*.rs", "*.ch", "*.py", "*.md")
SKIP_DIRS = {".git", "target", "node_modules", "__pycache__", "dist", ".gate-tmp"}
CITATION = re.compile(r"chelis#(\d+)")


def collect_citations(root: Path) -> dict[str, list[str]]:
    """Map `chelis#NNN` -> sorted 'relpath:line' sites across the repo."""
    citations: dict[str, list[str]] = {}
    for ext in SCAN_EXTS:
        for f in root.rglob(ext):
            if SKIP_DIRS.intersection(f.parts):
                continue
            try:
                lines = f.read_text().splitlines()
            except (UnicodeDecodeError, PermissionError):
                continue
            for lineno, line in enumerate(lines, start=1):
                for m in CITATION.finditer(line):
                    site = f"{f.relative_to(root)}:{lineno}"
                    citations.setdefault(m.group(0), []).append(site)
    return citations


ACTIVE_SECTIONS = ("Actively blocking", "Tracking", "Parked")
ENTRY_HEADER = re.compile(r"^\s*-\s+\*\*")  # a bullet whose text opens with bold


def upstream_bug_subjects(root: Path) -> tuple[set[str], set[str]]:
    """Classify the chelis#NNN issues that are the SUBJECT of an UPSTREAM_BUGS
    entry — i.e. cited in that entry's bold header line — by section.

    Returns (active_subjects, archived_subjects). An entry's subject is the
    issue its section asserts a status about; body citations (context, fix
    provenance like "fixed by chelis#445", "post-chelis#449") are deliberately
    NOT subjects, so referencing a closed fix inside a live entry does not
    false-flag. A CLOSED issue that is an *active* subject is the real staleness
    the contract targets: a §Tracking/§Parked/§Actively-blocking entry for an
    issue that is already resolved upstream.
    """
    doc = root / "docs" / "UPSTREAM_BUGS.md"
    if not doc.exists():
        return set(), set()
    active: set[str] = set()
    archived: set[str] = set()
    section = None
    for line in doc.read_text().splitlines():
        h = re.match(r"^##\s+(.*?)\s*$", line)
        if h:
            section = h.group(1)
            continue
        if section is None or not ENTRY_HEADER.match(line):
            continue
        header_issues = set(CITATION.findall(line))
        if any(section.startswith(s) for s in ACTIVE_SECTIONS):
            active |= header_issues
        elif section.startswith("Archived"):
            archived |= header_issues
    return active, archived


def gh_issue_state(number: str) -> str | None:
    """Upstream state of chelis#<number>: 'OPEN', 'CLOSED', or None if the
    lookup could not be performed (gh missing, no auth, no network). Never
    raises — offline tolerance is the point."""
    if shutil.which("gh") is None:
        return None
    try:
        out = subprocess.run(
            ["gh", "issue", "view", number, "-R", CHELIS_REPO, "--json", "state"],
            capture_output=True, text=True, timeout=20,
        )
    except (subprocess.SubprocessError, OSError):
        return None
    if out.returncode != 0:
        return None
    try:
        return json.loads(out.stdout)["state"].upper()
    except (json.JSONDecodeError, KeyError, AttributeError):
        return None


def scan_citations(root: Path) -> bool:
    citations = collect_citations(root)
    if not citations:
        print("\nNo chelis#NNN citations found.")
        return True

    active_subjects, archived_subjects = upstream_bug_subjects(root)
    print(f"\nFound {len(citations)} distinct chelis# citation(s); "
          "checking upstream state:")

    if shutil.which("gh") is None:
        print("  WARNING: `gh` not on PATH — skipping upstream-state check "
              "(offline-tolerant; re-run online to catch stale citations).")

    ok = True
    for cit in sorted(citations, key=lambda c: int(c.split("#")[1])):
        number = cit.split("#")[1]
        sites = citations[cit]
        state = gh_issue_state(number)
        if number in active_subjects:
            role = "active-subject"
        elif number in archived_subjects:
            role = "archived-subject"
        else:
            role = "reference"
        if state is None:
            print(f"  {cit}: state UNKNOWN (offline) [{role}] — {len(sites)} site(s)")
            continue
        print(f"  {cit}: {state} [{role}] — {len(sites)} site(s)")
        if state in ("CLOSED", "MERGED") and role == "active-subject":
            ok = False
            print(f"    STALE: {cit} is CLOSED upstream but is the subject of an "
                  "ACTIVE docs/UPSTREAM_BUGS.md entry (§Actively blocking / "
                  "§Tracking / §Parked). Re-probe it per-surface; if truly "
                  "resolved, retire the workaround and move the entry to "
                  "§Archived (or re-cite the live residue issue). Sites:")
            for s in sites[:10]:
                print(f"      - {s}")
        elif state == "OPEN" and role == "archived-subject":
            print(f"    NOTE: {cit} is an §Archived subject but still OPEN upstream "
                  "— confirm it should not move back to §Tracking.")

    if ok:
        print("\nNo stale citations (no CLOSED-upstream issue is the subject of an "
              "active UPSTREAM_BUGS entry).")
    return ok


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Audit Shoals version pins and workaround-citation staleness.")
    parser.add_argument("--pins-only", action="store_true",
                        help="Only check pin consistency (offline CI guard).")
    args = parser.parse_args()

    root = find_repo_root()
    ok = check_pins(root)
    if not args.pins_only:
        ok = scan_citations(root) and ok

    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
