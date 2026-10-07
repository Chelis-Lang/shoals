#!/usr/bin/env python3
"""Check the book's Chelis examples against this checkout with the pinned compiler.

The book (docs/book/src) is rendered from the chelis.ch docs. Its ```chelis
blocks come in three shapes, and each is checked:

- Signature blocks: `def name(...) -> T` lines without a body. Each one that
  names a Shoals function must equal that function's declaration in this
  checkout (`src/`, `properties/`, `references/`, `demos/`), whitespace
  normalized. Signatures of functions from other packages are counted as
  skipped.
- Fragments: statements such as `px = bs_call_scalar(...)  // 10.450583`.
  Each block is evaluated with `chelis eval --file` in a generated file that
  imports the names the block uses and prepends the earlier statements on the
  same page that define names the block reads (a fragment may continue its
  page). The block must evaluate without error. A trailing `// N` comment
  (also `// x == N`, `// x ~ N` and `// [a, b, ...]`) is the value shown to
  the reader, and the evaluated value must contain those numbers: to the
  digits shown for `~`, and to the last digit shown (half a unit) otherwise.
  Comments that start with words are explanations and are not compared.
- Complete programs (a block that carries its own `import` lines) are
  evaluated as written. When a ```text block follows a chelis block, it is the
  real output: stdout for a program that succeeds, the error for one that
  fails.

Blocks that declare `@property` or `type` items are compiled with
`chelis check` instead of evaluated. Blocks that cannot be evaluated on their
own (they read a name the page never defines) are skipped and counted.

A failure means the site page is wrong, or the API changed without a book
update: fix the chelis.ch page and re-render the book.

Usage: check_book_examples.py [--chelis PATH] [--page NAME] [--keep]
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
BOOK = REPO / "docs" / "book" / "src"
WORK = REPO / ".gate-tmp" / "book-examples"
SOURCE_DIRS = ("src", "properties", "references", "demos")
FENCE = re.compile(r"^```(\S*)\s*$")
IDENT = re.compile(r"\b[A-Za-z_][A-Za-z0-9_]*\b")
NUMBER = re.compile(r"-?(?:\d+\.\d+|\d+)(?:[eE][-+]?\d+)?|-?inf|NaN")
NUM_TOKEN = re.compile(r"^(-?(?:\d+\.\d+|\d+)(?:[eE][-+]?\d+)?)(?=$|[,;:)\]]|\s+[(=~])")
KEYWORDS = {
    "def", "type", "if", "then", "else", "match", "with", "fn", "let", "true", "false",
    "import", "module", "forall", "export", "and", "or", "not", "in",
}


@dataclass
class Stmt:
    text: str  # Chelis text with `//` comments removed
    comment: str  # trailing comment text, if any
    binds: str | None  # name bound at top level, if any
    line: int


@dataclass
class Block:
    page: str
    line: int
    lines: list[str]
    expected: str | None  # a following ```text block
    stmts: list[Stmt] = field(default_factory=list)


def read_blocks(page: Path) -> list[Block]:
    lines = page.read_text().splitlines()
    raw: list[tuple[int, str, list[str]]] = []
    i = 0
    while i < len(lines):
        m = FENCE.match(lines[i])
        if m:
            j = i + 1
            while j < len(lines) and not lines[j].startswith("```"):
                j += 1
            raw.append((i + 1, m.group(1), lines[i + 1:j]))
            i = j
        i += 1
    out = []
    for k, (line, lang, body) in enumerate(raw):
        if lang != "chelis":
            continue
        expected = None
        if k + 1 < len(raw) and raw[k + 1][1] == "text":
            # a text block is this block's output when it follows directly or
            # the prose between them says to run `chelis eval`; otherwise it
            # illustrates something else (an error message, say)
            between = lines[line + len(body) + 1:raw[k + 1][0] - 1]
            if all(not s.strip() for s in between) or "chelis eval" in " ".join(between):
                expected = "\n".join(raw[k + 1][2])
        out.append(Block(page.name, line, body, expected))
    return out


def split_comment(line: str) -> tuple[str, str]:
    in_str = False
    for i, ch in enumerate(line):
        if ch == '"':
            in_str = not in_str
        elif not in_str and line.startswith("//", i):
            return line[:i].rstrip(), line[i + 2:].strip()
    return line.rstrip(), ""


def statements(block: Block) -> list[Stmt]:
    stmts: list[Stmt] = []
    buf: list[str] = []
    comments: list[str] = []
    depth = 0
    start = block.line
    for n, raw in enumerate(block.lines):
        code, comment = split_comment(raw)
        if not buf and not code.strip():
            if comment and stmts:
                # a comment-only line annotates the statement above it
                stmts[-1].comment = (stmts[-1].comment + " " + comment).strip() if stmts[-1].comment else comment
            continue
        if not buf:
            start = block.line + 1 + n
        buf.append(code)
        if comment:
            comments.append(comment)
        depth += sum(code.count(c) for c in "([{") - sum(code.count(c) for c in ")]}")
        nxt = block.lines[n + 1] if n + 1 < len(block.lines) else ""
        continues = depth > 0 or nxt.startswith(("  ", "|")) and not nxt.startswith("  //")
        if not continues:
            text = "\n".join(buf)
            m = re.match(r"^([a-z_][A-Za-z0-9_]*)\s*=(?!=)", text)
            stmts.append(Stmt(text, " ".join(comments), m.group(1) if m else None, start))
            buf, comments, depth = [], [], 0
    if buf:
        stmts.append(Stmt("\n".join(buf), " ".join(comments), None, start))
    return stmts


def module_exports() -> tuple[dict[str, str], dict[str, str]]:
    """name -> module for every exported name, and name -> declaration header."""
    names: dict[str, str] = {}
    headers: dict[str, str] = {}
    for d in SOURCE_DIRS:
        for path in sorted((REPO / d).rglob("*.ch")):
            text = path.read_text()
            mod = re.search(r"^module\s+([\w.]+)", text, re.M)
            exp = re.search(r"^export\s*\(([^)]*)\)", text, re.M | re.S)
            if not mod or not exp:
                continue
            exported = {e.strip() for e in exp.group(1).split(",") if e.strip()}
            for e in exported:
                names.setdefault(e, mod.group(1))
            for m in re.finditer(r"^def\s+(\w+)(.*?)\s=\s", text, re.M):
                if m.group(1) in exported:
                    headers.setdefault(m.group(1), normalize(f"def {m.group(1)}{m.group(2)}"))
    # names the book uses from Std, Nautilus and Shoreleave, learned from the
    # import lines of this repository's own tests and sources
    for d in ("tests", "tests-manual", *SOURCE_DIRS):
        for path in sorted((REPO / d).rglob("*.ch")):
            for m in re.finditer(r"^import\s+([\w.]+)\s*\(([^)]*)\)", path.read_text(), re.M):
                for e in m.group(2).split(","):
                    e = e.strip()
                    if e and not m.group(1).startswith("Shoals.Tests"):
                        names.setdefault(e, m.group(1))
    return names, headers


def normalize(sig: str) -> str:
    return re.sub(r"\s+", " ", sig).replace("( ", "(").replace(" )", ")").strip()


def resolve_chelis(explicit: str | None) -> str:
    if explicit:
        return explicit
    found = shutil.which("chelis")
    if not found:
        sys.exit("check_book_examples: chelis not found on PATH")
    return found


def imports_for(text: str, names: dict[str, str], defined: set[str]) -> list[str]:
    used = {w for w in IDENT.findall(re.sub(r'"[^"]*"', "", text))} - KEYWORDS - defined
    by_mod: dict[str, set[str]] = {}
    for w in used:
        if w in names:
            by_mod.setdefault(names[w], set()).add(w)
    return [f"import {m} ({', '.join(sorted(ws))})" for m, ws in sorted(by_mod.items())]


def numbers(text: str) -> list[float]:
    return [float(x) if x not in ("inf", "-inf", "NaN") else float(x.replace("NaN", "nan")) for x in NUMBER.findall(text)]


def expected_numbers(comment: str) -> tuple[list[str], str] | None:
    """The numbers a trailing comment shows, and the comparison kind."""
    c = comment.strip()
    m = re.match(r"^[a-z_][\w.]*\s*(==|~)\s*(.*)$", c)
    kind = "exact"
    if m:
        kind = "approx" if m.group(1) == "~" else "exact"
        c = m.group(2)
    if c.startswith("["):
        end = c.find("]")
        inner = c[1:end] if end > 0 else ""
        toks = [t.strip() for t in inner.split(",")]
        if toks and all(NUM_TOKEN.match(t) and NUM_TOKEN.match(t).group(1) == t for t in toks):
            return toks, kind
        return None
    t = NUM_TOKEN.match(c)
    if t:
        return [t.group(1)], kind
    return None


def tolerance(tok: str, kind: str) -> float:
    decimals = len(tok.split(".")[1].split("e")[0].split("E")[0]) if "." in tok else 0
    unit = 10.0 ** -decimals
    return unit if kind == "approx" else unit / 2 + 1e-7 * abs(float(tok))


def matches(got: list[float], want: list[str], kind: str) -> bool:
    w = [float(t) for t in want]
    for s in range(len(got) - len(w) + 1):
        if all(abs(got[s + i] - w[i]) <= tolerance(want[i], kind) for i in range(len(w))):
            return True
    return False


def parse_eval(stdout: str) -> dict[str, str]:
    values: dict[str, str] = {}
    for line in stdout.splitlines():
        m = re.match(r"^(\w+) = (.*)$", line)
        if m:
            values[m.group(1)] = m.group(2)
    return values


class Checker:
    def __init__(self, chelis: str, names: dict[str, str], headers: dict[str, str]):
        self.chelis = chelis
        self.names = names
        self.headers = headers
        self.failures: list[str] = []
        self.counts = {"signatures": 0, "signatures skipped": 0, "fragments": 0,
                       "programs": 0, "compiled": 0, "values": 0, "outputs": 0, "skipped": 0}
        self.serial = 0

    def run(self, args: list[str]) -> subprocess.CompletedProcess[str]:
        return subprocess.run([self.chelis, *args], cwd=REPO, capture_output=True, text=True)

    def write(self, text: str) -> Path:
        self.serial += 1
        path = WORK / f"example_{self.serial}.ch"
        path.write_text(text)
        # generated files are formatted rather than exempted from the style gate
        self.run(["fmt", "--inplace", str(path.relative_to(REPO))])
        return path

    def check_signatures(self, block: Block) -> None:
        for st in block.stmts:
            m = re.match(r"^def\s+(\w+)", st.text)
            if not m:
                continue
            if m.group(1) not in self.headers:
                self.counts["signatures skipped"] += 1
                continue
            self.counts["signatures"] += 1
            if normalize(st.text) != self.headers[m.group(1)]:
                self.failures.append(
                    f"{block.page}:{st.line}: signature differs from the source\n  book:   {normalize(st.text)}\n"
                    f"  source: {self.headers[m.group(1)]}")

    def check_block(self, block: Block, earlier: list[Stmt]) -> None:
        stmts = block.stmts
        if not stmts:
            return
        if all(s.text.startswith(("def ", "type ")) for s in stmts) and not any(
                s.text.startswith("def ") and re.search(r"\s=\s", s.text) for s in stmts):
            self.check_signatures(block)
            return
        text = "\n".join(s.text for s in stmts)
        if re.search(r"(?m)^(import|module)\s", text):
            self.counts["programs"] += 1
            self.evaluate(block, text, program=True)
            return
        if re.search(r"(?m)^(@property|type)\b", text):
            self.counts["compiled"] += 1
            defined = {m.group(1) for m in re.finditer(r"(?m)^def\s+(\w+)", text)}
            src = "\n".join(imports_for(text, self.names, defined)) + "\n" + text + "\n"
            path = self.write(src)
            r = self.run(["check", str(path.relative_to(REPO))])
            try:
                score = json.loads(r.stdout[r.stdout.index("{"):]).get("score")
            except ValueError:
                score = None
            if score != 1:
                self.failures.append(f"{block.page}:{block.line}: `chelis check` score {score}\n{r.stdout[-800:]}{r.stderr[-800:]}")
            return

        # a fragment: pull in the earlier statements on this page it reads
        own = {s.binds for s in stmts if s.binds} | {m.group(1) for s in stmts for m in [re.match(r"^def\s+(\w+)", s.text)] if m}
        needed: list[Stmt] = []
        want = set(IDENT.findall(re.sub(r'"[^"]*"', "", text))) - own
        for st in reversed(earlier):
            name = st.binds or (re.match(r"^def\s+(\w+)", st.text).group(1) if st.text.startswith("def ") and re.search(r"\s=\s", st.text) else None)
            if name and name in want and name not in {n.binds for n in needed}:
                needed.insert(0, st)
                want |= set(IDENT.findall(st.text)) - {name}
                want.discard(name)
        clash = {s.binds for s in needed if s.binds} & {s.binds for s in stmts if s.binds}
        context = []
        for s in needed:
            text_c = s.text
            for name in clash:
                text_c = re.sub(rf"\b{name}\b", f"{name}_from_page", text_c)
            context.append(text_c)
        body: list[str] = context
        targets: list[tuple[str, Stmt]] = []
        for i, st in enumerate(stmts):
            if st.binds or st.text.startswith("def "):
                body.append(st.text)
                if st.binds:
                    targets.append((st.binds, st))
            else:
                name = f"example_value_{i}"
                body.append(f"{name} = {st.text}")
                targets.append((name, st))
        program = "\n".join(body)
        defined = {s.binds for s in needed + stmts if s.binds}
        defined |= {m.group(1) for m in re.finditer(r"(?m)^def\s+(\w+)", program)}
        defined |= {n for n, _ in targets}
        defined |= {f"{n}_from_page" for n in clash}
        free = re.sub(r"\b[A-Za-z_]\w*\s*:(?!:)", " ", re.sub(r'"[^"]*"', "", program))
        unknown = sorted(w for w in set(IDENT.findall(free)) - KEYWORDS - defined - set(self.names)
                         if w[0].islower() and w not in BUILTINS and not re.match(r"^\d", w))
        if unknown:
            self.counts["skipped"] += 1
            print(f"skip {block.page}:{block.line}: reads names the page does not define: {', '.join(unknown)}")
            return
        self.counts["fragments"] += 1
        src = "\n".join(imports_for(program, self.names, defined)) + "\n" + program + "\n"
        values = self.evaluate(block, src, program=False)
        if values is None:
            return
        shown: list[tuple[str, Stmt, tuple[list[str], str]]] = []
        target_names = {n for n, _ in targets}
        for name, st in targets:
            if not st.comment:
                continue
            pairs = re.findall(r"\b([a-z_]\w*)\s*(?:==|~)\s*([^,;]+)", st.comment)
            if len(pairs) > 1 and all(p[0] in target_names for p in pairs):
                for other, value in pairs:
                    exp = expected_numbers(f"{other} == {value}" if "~" not in st.comment else f"{other} ~ {value}")
                    if exp:
                        shown.append((other, st, exp))
                continue
            exp = expected_numbers(st.comment)
            if exp:
                shown.append((name, st, exp))
        for name, st, exp in shown:
            self.counts["values"] += 1
            got = values.get(name)
            if got is None or not matches(numbers(got), *exp):
                self.failures.append(
                    f"{block.page}:{st.line}: `{name}` evaluates to {got}, the book shows `// {st.comment}`")

    def evaluate(self, block: Block, src: str, program: bool) -> dict[str, str] | None:
        if program:
            src = re.sub(r"(?m)^module\s+.*\n", "", src)
            src = "\n".join(split_comment(line)[0] for line in src.splitlines()) + "\n"
        path = self.write(src)
        r = self.run(["eval", "--timeout", "600", "--file", str(path.relative_to(REPO))])
        if block.expected is not None:
            self.counts["outputs"] += 1
            want = block.expected.strip()
            got = r.stdout.strip() if r.returncode == 0 else r.stderr.strip()
            if (r.returncode == 0 and got != want) or (r.returncode != 0 and want not in got):
                self.failures.append(f"{block.page}:{block.line}: output differs\n--- book\n{want}\n--- actual\n{got[-1500:]}")
            return parse_eval(r.stdout) if r.returncode == 0 else None
        if r.returncode != 0:
            self.failures.append(f"{block.page}:{block.line}: `chelis eval` failed\n{src}\n{r.stderr.strip()[-1500:]}")
            return None
        return parse_eval(r.stdout)


# Chelis built-ins the fragments call without an import.
BUILTINS = {
    "cast", "to_tensor", "to_list", "map", "range", "reshape", "copy", "index", "add", "sub", "mul", "div",
    "exp", "log", "sqrt", "neg", "abs", "lt", "lte", "gt", "gte", "eq", "max", "min", "sum", "mean",
    "key_from_seed", "split", "len", "fold", "zeros", "Some", "None", "f32", "f64", "i64", "i32", "bool",
    "string", "key", "tensor", "List", "Option", "pow", "cast_trunc", "concat", "fail",
    "i64", "f32", "fn", "x", "i", "m", "t", "_",
}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--chelis", help="chelis binary (default: chelis on PATH, the pinned toolchain in CI)")
    ap.add_argument("--page", action="append", help="only check this page (repeatable)")
    ap.add_argument("--keep", action="store_true", help="keep the generated example files")
    args = ap.parse_args()

    names, headers = module_exports()
    checker = Checker(resolve_chelis(args.chelis), names, headers)
    shutil.rmtree(WORK, ignore_errors=True)
    WORK.mkdir(parents=True)
    total = 0
    try:
        for page in sorted(BOOK.glob("*.md")):
            if args.page and page.name not in args.page and page.stem not in args.page:
                continue
            earlier: list[Stmt] = []
            for block in read_blocks(page):
                block.stmts = statements(block)
                total += 1
                checker.check_block(block, earlier)
                earlier += [s for s in block.stmts if s.binds or (s.text.startswith("def ") and re.search(r"\s=\s", s.text))]
    finally:
        if not args.keep:
            shutil.rmtree(WORK, ignore_errors=True)
    if total == 0:
        sys.exit(f"check_book_examples: no chelis examples found under {BOOK.relative_to(REPO)}")
    for f in checker.failures:
        print(f"FAIL {f}\n")
    c = checker.counts
    print(f"book-examples: {total} blocks; {c['signatures']} signatures matched against the source "
          f"({c['signatures skipped']} from other packages skipped); {c['fragments']} fragments and "
          f"{c['programs']} programs evaluated, {c['compiled']} compiled; {c['values']} shown values and "
          f"{c['outputs']} shown outputs compared; {c['skipped']} blocks skipped; {len(checker.failures)} failures")
    return 1 if checker.failures else 0


if __name__ == "__main__":
    sys.exit(main())
