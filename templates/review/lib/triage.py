#!/usr/bin/env python3
"""Triage review findings — terminal or browser, same data.

    triage.py            terminal
    triage.py --web      browser
    triage.py <project>  a project you are not standing in

Findings are local and disposable. They live in

    ~/.claude/projects/<project-path-with-slashes-as-dashes>/review/findings.json

and never inside the project: a review leaves no artifact in the repository and
nothing to clean up afterwards. Override the location with `--file <path>`.

Schema
------
    {"project": str,                       # shown as the title
     "root":    str,                       # the project directory — required:
                                           #   every code link resolves against it
     "groups":   [{"id", "title"}],
     "findings": [{"id", "group", "title", "decision", "where", ...}]}

Required on a finding: `id`, `group`, `title`, `decision`, `where`. Optional:
`see`, `why`, `fix`, `call`, `refs` — absent ones are skipped, not blanked.
Nothing else is read; a field this list does not name is carried through the
file and never shown. `decision` is the user's answer and the only thing
written back: null, "fix", "skip" or "discuss".

`where` is the location in `path/File.kt:42` form; several files and several
lines per file are fine (`A.kt:12, 30, B.kt:9`). Each one becomes a link that
opens the real file from disk, so a finding never carries a copy of the code.
Paths may be repo-relative or bare filenames.
"""

import json
import os
import re
import subprocess
import sys
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, urlparse

FIX, SKIP, DISCUSS = "fix", "skip", "discuss"
DECISIONS = (FIX, SKIP, DISCUSS)
BOX = {FIX: "[x]", SKIP: "[-]", DISCUSS: "[?]"}
SECTIONS = [("What you would see", "see"), ("Why", "why"),
            ("Fix", "fix"), ("My call", "call")]
NOISE = {".git", "build", ".gradle", "node_modules", "DerivedData", "Pods", ".idea"}


# ──────────────────────────────── locating ────────────────────────────────

def flag(argv, name):
    if name not in argv:
        return None
    i = argv.index(name) + 1
    if i >= len(argv):
        sys.exit(f"{name} needs a value")
    return argv[i]


def git_root(start):
    d = os.path.abspath(start)
    while True:
        if os.path.exists(os.path.join(d, ".git")):
            return d
        parent = os.path.dirname(d)
        if parent == d:
            return None
        d = parent


def store_for(root):
    slug = os.path.abspath(root).replace(os.sep, "-")
    return os.path.expanduser(f"~/.claude/projects/{slug}/review/findings.json")


def known_stores():
    base = os.path.expanduser("~/.claude/projects")
    out = []
    for name in sorted(os.listdir(base)) if os.path.isdir(base) else []:
        path = os.path.join(base, name, "review", "findings.json")
        if not os.path.exists(path):
            continue
        try:
            with open(path, encoding="utf-8") as f:
                root = json.load(f).get("root") or ""
        except Exception:
            root = ""
        # The slug is one-way — `/a/my-app` and `/a/my/app` collapse to the same
        # string — so never read a path back out of it. The file says where it
        # belongs, or we show the slug as the raw label it is.
        out.append((path, root or name))
    return out


def find_store(start):
    """The nearest existing store at or above `start` — so a subdirectory, and a
    submodule, both find the project they are part of."""
    d = os.path.abspath(start)
    while True:
        path = store_for(d)
        if os.path.exists(path):
            return path
        parent = os.path.dirname(d)
        if parent == d:
            return None
        d = parent


def store_target(start):
    """Where this project's findings go. Writer and reader must ask the same
    question, or `--where` names a file the tool would never open."""
    return find_store(start) or store_for(git_root(start) or start)


def locate(argv):
    """Outside any reviewed project, fall back to the only review there is."""
    given = flag(argv, "--file")
    if given:
        return os.path.abspath(given)

    where = next((a for a in argv[1:] if not a.startswith("-")), None)
    start = os.path.abspath(os.path.expanduser(where)) if where else os.getcwd()
    if where and os.path.isfile(start):
        return start

    found = find_store(start)
    if found:
        return found

    stores = known_stores()
    if len(stores) == 1 and not where:
        print(f"Not inside a reviewed project — opening the only review there is:"
              f"\n  {stores[0][1]}\n", flush=True)
        return stores[0][0]
    lines = [f"No findings for {start}", f"  expected: {store_for(start)}"]
    if stores:
        lines.append("\nReviews that exist — pass one as an argument:")
        lines += [f"  {root}" for _, root in stores]
    else:
        lines.append("Run a review first, or pass --file <path>.")
    sys.exit("\n".join(lines))


# ───────────────────────────────── source ─────────────────────────────────

def index_files(root):
    """basename → [repo-relative paths], so a bare filename still resolves."""
    out = {}
    try:
        r = subprocess.run(["git", "ls-files", "-co", "--exclude-standard"],
                           cwd=root, capture_output=True, text=True, timeout=15)
        names = [n for n in r.stdout.split("\n") if n]
    except Exception:
        names = []
    if not names:
        names = []
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = [d for d in dirnames if d not in NOISE]
            for f in filenames:
                names.append(os.path.relpath(os.path.join(dirpath, f), root))
    for n in names:
        out.setdefault(os.path.basename(n), []).append(n)
    return out


REF = re.compile(r"([\w./+-]+)((?::\d+(?:-\d+)?(?:\s*,\s*\d+(?:-\d+)?)*)?)")
EXT = re.compile(r"\.[A-Za-z]\w*$")   # a name is a file if it has one, or a line


def resolve(root, index, path):
    if os.path.isfile(os.path.join(root, path)):
        return path
    hits = index.get(os.path.basename(path), [])
    exact = [h for h in hits if h == path or h.endswith("/" + path)]
    hits = exact or hits
    return min(hits, key=len) if hits else None


def locations(item, root, index):
    """(resolved refs, names that looked like files but matched nothing).

    The second list is why a finding never loses a location silently: a path
    the regex mangles or a file that has moved shows up as unresolved instead
    of just not being there."""
    out, missing, seen = [], [], set()

    def line_of(value):
        """`42`, `"42"`, `"L42"`, `"42-50"` and nonsense all have to survive:
        the file is machine-written and never validated, and one bad field must
        cost its own line number, not every location in the review."""
        digits = re.match(r"\D*(\d+)", str(value if value is not None else ""))
        return int(digits.group(1)) if digits else 0

    def add(path, line):
        rel = resolve(root, index, path)
        if not rel:
            if path not in missing:
                missing.append(path)
        elif (rel, line) not in seen:
            seen.add((rel, line))
            out.append({"path": rel, "line": line})

    for r in item.get("refs") or []:
        add(r.get("path", ""), line_of(r.get("line")))
    for m in REF.finditer(item.get("where") or ""):
        name, spans = m.group(1), [s for s in m.group(2).lstrip(":").split(",") if s.strip()]
        if not spans and not EXT.search(name):
            continue          # prose, or a directory — not a claim about a file
        for line in [int(s.split("-")[0]) for s in spans] or [0]:
            add(name, line)
    return out, missing


def read_source(root, rel, cap=6000):
    """(lines, total). Lines are capped; total is the real length, so a caller
    never reports a truncated file as a whole one. (None, 0) if unreadable or
    outside the project."""
    base = os.path.realpath(root)
    full = os.path.realpath(os.path.join(base, rel))
    if full != base and not full.startswith(base + os.sep):
        return None, 0
    try:
        with open(full, encoding="utf-8", errors="replace") as f:
            all_lines = f.read().split("\n")
    except OSError:
        return None, 0
    return all_lines[:cap], len(all_lines)


# ───────────────────────────────── document ────────────────────────────────

class Doc:
    def __init__(self, store):
        self.store = store
        with open(store, encoding="utf-8") as f:
            self.doc = json.load(f)
        self.findings = self.doc.get("findings") or []
        self.groups = {g["id"]: g for g in self.doc.get("groups") or []}
        self.root = self._root()
        self.index = index_files(self.root)
        self.baseline = self._decisions()
        self._source = {}

    def source(self, rel):
        """`read_source`, remembered. The terminal redraws the whole detail pane
        on every keystroke, so without this an open file is re-read and re-split
        from disk each time an arrow key repeats."""
        if rel not in self._source:
            self._source[rel] = read_source(self.root, rel)
        return self._source[rel]

    def _decisions(self):
        return {x.get("id"): x.get("decision") for x in self.findings}

    def _root(self):
        if self.doc.get("root") and os.path.isdir(self.doc["root"]):
            return self.doc["root"]
        here = git_root(os.getcwd()) or os.getcwd()
        if store_for(here) == self.store:
            return here            # standing in the project this file describes
        sys.exit(f'{self.store} has no usable "root", and it is not the store\n'
                 f'for {here}. Every code link would resolve against the wrong\n'
                 f'tree. Add "root": "/path/to/project" to the file.')

    def title(self, gid):
        return (self.groups.get(gid) or {}).get("title", gid)

    def counts(self):
        d = [x.get("decision") for x in self.findings]
        return (d.count(FIX), d.count(SKIP), d.count(DISCUSS),
                sum(1 for v in d if v not in DECISIONS))

    def toggle(self, fid, value):
        for x in self.findings:
            if x.get("id") == fid:
                x["decision"] = None if x.get("decision") == value else value
                return

    def set(self, fid, value):
        for x in self.findings:
            if x.get("id") == fid:
                x["decision"] = value
                return True
        return False

    def save(self):
        """Write back only the decisions this session changed, merged onto what
        is on disk now. Two open copies of the tool, or a stale one quit hours
        later, then cannot silently undo each other's answers."""
        mine = {k: v for k, v in self._decisions().items() if v != self.baseline.get(k)}
        if not mine and os.path.exists(self.store):
            return
        try:
            with open(self.store, encoding="utf-8") as f:
                disk = json.load(f)
        except Exception:
            disk = self.doc
        for x in disk.get("findings") or []:
            if x.get("id") in mine:
                x["decision"] = mine[x["id"]]
        tmp = self.store + ".tmp"
        os.makedirs(os.path.dirname(self.store), exist_ok=True)
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(disk, f, ensure_ascii=False, indent=2)
            f.write("\n")
        os.replace(tmp, self.store)
        # Adopt what was actually written, or every count we report afterwards
        # describes a file that no longer says that — including the tally handed
        # back to Claude.
        self.doc = disk
        self.findings = disk.get("findings") or []
        self.baseline = self._decisions()


#  Set by whoever launched us. When Claude did, this process *is* the channel
#  back: Finish stops the server, the command Claude is waiting on returns, and
#  the summary below is what it reads. Launched from your own shell, there is no
#  such channel and the tool can only tell you to go say so.
WAITING = os.environ.get("TRIAGE_CALLER") == "claude"


def closing_words(doc, headline=True):
    fx, sk, di, un = doc.counts()
    tally = f"fix {fx} · discuss {di} · skip {sk}" + (f" · undecided {un}" if un else "")
    out = ["", "Review closed — " + tally] if headline else [tally]
    out += [f"Decisions are in {doc.store}", ""]
    if WAITING:
        out.append("Claude was waiting on this process and has the result now.")
        out.append("You can close the page.")
    elif fx or di:
        out.append("Tell Claude the triage is done. It reads the file and starts on")
        out.append("the `fix` ones; each `discuss` comes back to you as a question.")
    elif un:
        out.append("Nothing decided yet — reopen when you want to finish.")
    else:
        out.append("Nothing to do: everything was skipped.")
    return "\n".join(out)


# ──────────────────────────────── terminal ────────────────────────────────

def run_tui(doc):
    import curses
    import textwrap

    if not doc.findings:
        print(f"No findings in {doc.store}")
        return

    def main(scr):
        curses.curs_set(0)
        curses.use_default_colors()
        for i, c in enumerate((curses.COLOR_GREEN, curses.COLOR_YELLOW,
                               curses.COLOR_CYAN, curses.COLOR_MAGENTA,
                               curses.COLOR_BLUE), 1):
            curses.init_pair(i, c, -1)
        GREEN, DIM, CYAN, MAGENTA, BLUE = (curses.color_pair(i) for i in range(1, 6))
        BOLD, REV = curses.A_BOLD, curses.A_REVERSE
        TONE = {FIX: GREEN, SKIP: DIM, DISCUSS: BLUE}

        pane, sel, scroll, opened = "list", 0, 0, {}

        def put(y, x, text, attr=0, width=None):
            room = (width if width is not None else scr.getmaxyx()[1] - x) - 1
            if room > 0:
                try:
                    scr.addnstr(y, x, text, room, attr)
                except curses.error:
                    pass

        def list_rows():
            rows, cur = [], object()
            for i, x in enumerate(doc.findings):
                if x.get("group") != cur:
                    cur = x.get("group")
                    rows.append((None, doc.title(cur).upper(), DIM | BOLD))
                mark = BOX.get(x.get("decision"), "[ ]")
                rows.append((i, f" {mark} {x.get('id', ''):<5}{x.get('title', '')}",
                             TONE.get(x.get("decision"), 0)))
            return rows

        def detail_rows(width):
            item = doc.findings[sel]
            rows = [(item.get("title", ""), BOLD), ("", 0)]
            for label, key in SECTIONS:
                val = (item.get(key) or "").strip()
                if not val:
                    continue
                rows.append((label.upper(), MAGENTA | BOLD))
                for para in val.split("\n"):
                    for line in textwrap.wrap(para, max(20, width - 2)) or [""]:
                        rows.append((line, 0))
                rows.append(("", 0))
            refs, missing = locations(item, doc.root, doc.index)
            if refs:
                rows.append(("CODE", MAGENTA | BOLD))
                for n, r in enumerate(refs, 1):
                    loc = f"{r['path']}:{r['line']}" if r["line"] else r["path"]
                    key = (sel, n)
                    rows.append((f"[{n}] {'▾' if key in opened else '▸'} {loc}", CYAN))
                    if key not in opened:
                        continue
                    src, total = doc.source(r["path"])
                    if src is None:
                        rows.append(("     (cannot read this file)", DIM))
                        continue
                    lo, hi = opened[key]
                    if lo > len(src):     # past the read cap — a backwards range
                        rows.append((f"     line {r['line']} is past the first "  # renders
                                     f"{len(src)} lines, all that was read "      # nothing
                                     f"({total} in the file)", DIM))
                        continue
                    lo, hi = max(1, lo), min(len(src), hi)
                    gut = len(str(hi))
                    for ln in range(lo, hi + 1):
                        text = src[ln - 1].replace("\t", "    ")[:width - gut - 4]
                        hit = ln == r["line"]
                        rows.append((f" {ln:>{gut}} {'▸' if hit else '│'} {text}",
                                     (CYAN | BOLD) if hit else DIM))
                    cut = "" if total <= len(src) else f", only the first {len(src)} read"
                    rows.append((f"     + {lo}–{hi} of {total}{cut}", DIM))
                rows.append(("", 0))
            if missing:
                rows.append(("NOT FOUND", MAGENTA | BOLD))
                for name in missing:
                    rows.append((f"  {name} — no such file in the project", DIM))
                rows.append(("", 0))
            elif not refs:
                rows.append((f"({item.get('where', 'no location')})", DIM))
            return rows

        while True:
            scr.erase()
            h, w = scr.getmaxyx()
            lw = max(26, min(48, w * 38 // 100))
            rw = w - lw - 1
            item = doc.findings[sel]

            rows = list_rows()
            here = next((k for k, r in enumerate(rows) if r[0] == sel), 0)
            top = max(0, min(here - (h - 2) // 2, len(rows) - (h - 1)))
            for i, (idx, line, attr) in enumerate(rows[top:top + h - 1]):
                on = idx == sel
                put(i, 0, line.ljust(lw), attr | (REV if on and pane == "list" else
                                                  (BOLD if on else 0)), lw)

            body = detail_rows(rw)
            scroll = max(0, min(scroll, max(0, len(body) - (h - 1))))
            for i, (line, attr) in enumerate(body[scroll:scroll + h - 1]):
                put(i, lw + 1, line, attr, rw + 1)

            for y in range(h - 1):
                put(y, lw, "│", DIM, 2)

            fx, sk, di, un = doc.counts()
            name = doc.doc.get("project") or ""
            left = (f" {name} │" if name else "")
            left += f" fix {fx} · skip {sk} · discuss {di} · undecided {un} "
            keys = (" ↑↓ pick · → text · f fix · s skip · d discuss · q finish "
                    if pane == "list" else
                    " ↑↓ scroll · ← list · 1-9 code · f fix · s skip · d discuss · q finish ")
            put(h - 1, 0, (left + keys).ljust(w - 1), REV, w)
            scr.refresh()

            k = scr.getch()
            if k in (ord("q"), 27):
                break
            elif k in (ord("f"), ord("s"), ord("d")):
                doc.toggle(item["id"], {"f": FIX, "s": SKIP, "d": DISCUSS}[chr(k)])
            elif k == curses.KEY_RIGHT:
                pane = "detail"
            elif k == curses.KEY_LEFT:
                pane = "list"
            elif ord("1") <= k <= ord("9"):
                n, key = k - ord("0"), (sel, k - ord("0"))
                refs, _ = locations(item, doc.root, doc.index)
                if n <= len(refs):
                    if key in opened:
                        del opened[key]
                    else:
                        anchor = refs[n - 1]["line"] or 1
                        opened[key] = [anchor - 10, anchor + 14]
                    pane = "detail"
            elif k == ord("+"):
                for key in opened:
                    opened[key] = [opened[key][0] - 20, opened[key][1] + 20]
            elif k in (curses.KEY_DOWN, curses.KEY_UP, curses.KEY_NPAGE, curses.KEY_PPAGE):
                step = {curses.KEY_DOWN: 1, curses.KEY_UP: -1,
                        curses.KEY_NPAGE: h - 3, curses.KEY_PPAGE: -(h - 3)}[k]
                if pane == "detail":
                    scroll += step
                else:
                    moved = max(0, min(len(doc.findings) - 1, sel + step))
                    if moved != sel:
                        sel, scroll = moved, 0

    try:
        curses.wrapper(main)          # Ctrl+C is the ordinary way out of a
    except KeyboardInterrupt:         # curses app, and it must not cost an
        pass                          # hour of answers.
    finally:
        doc.save()
    print(closing_words(doc))


# ────────────────────────────────── web ──────────────────────────────────

PAGE = """<!doctype html><html><head><meta charset="utf-8">
<title>Review triage</title>
<style>
*{box-sizing:border-box}
body{margin:0;font:15px/1.6 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;
background:#faf9f7;color:#1a1a19}
@media(prefers-color-scheme:dark){body{background:#1a1a19;color:#e8e7e3}}
main{display:grid;grid-template-columns:minmax(280px,360px) 1fr;height:100vh}
#left{display:flex;flex-direction:column;border-right:1px solid rgba(128,128,128,.25);
min-height:0}
#list{overflow-y:auto;padding:10px 8px;flex:1}
.grp{font-size:11px;letter-spacing:.08em;text-transform:uppercase;opacity:.5;padding:14px 10px 6px}
.it{padding:9px 10px;border-radius:7px;cursor:pointer;display:flex;gap:9px;align-items:flex-start}
.it:hover{background:rgba(128,128,128,.1)}
.it.on{background:rgba(120,120,255,.16)}
.bx{flex:0 0 auto;font-family:ui-monospace,monospace;font-size:13px;opacity:.75}
.it.fix .bx{color:#1a9e75;opacity:1}
.it.discuss .bx{color:#4a80e0;opacity:1}
.it.skip{opacity:.45}
.tt{font-size:13.5px}
#bar{border-top:1px solid rgba(128,128,128,.25);padding:12px 14px;display:flex;
gap:10px;align-items:center;flex-wrap:wrap}
#stat_{font-size:12.5px;opacity:.65;flex:1;min-width:120px}
#pane{overflow-y:auto;padding:28px 34px 60px}
#pane h2{font-size:19px;font-weight:500;margin:0 0 16px}
.lbl{font-size:11px;letter-spacing:.08em;text-transform:uppercase;opacity:.5;margin:22px 0 5px}
p{margin:0 0 10px;white-space:pre-wrap}
.acts{display:flex;gap:9px;margin:0 0 10px}
button{font:inherit;font-size:14px;padding:8px 18px;border-radius:7px;cursor:pointer;
border:1px solid rgba(128,128,128,.4);background:transparent;color:inherit}
button:hover{background:rgba(128,128,128,.14)}
button.act{border-color:#1a9e75;color:#1a9e75}
button.act.d{border-color:#4a80e0;color:#4a80e0}
#fin{padding:7px 16px;font-size:13.5px}
#fin.ready{border-color:#1a9e75;color:#1a9e75;font-weight:500}
.ref{display:block;width:100%;text-align:left;font-family:ui-monospace,monospace;
font-size:12.5px;padding:7px 11px;margin:0 0 6px;border-radius:7px}
.ref .ar{opacity:.5;margin-right:7px}
.src{border:1px solid rgba(128,128,128,.3);border-radius:8px;overflow:hidden;margin:0 0 14px}
.src .bar2{display:flex;gap:10px;align-items:center;padding:6px 11px;font-size:12px;
background:rgba(128,128,128,.12);font-family:ui-monospace,monospace}
.src .bar2 button{padding:2px 9px;font-size:11.5px;border-radius:5px}
.src .bar2 .sp{margin-left:auto;opacity:.55}
.code{overflow-x:auto;font:12.5px/1.55 ui-monospace,SFMono-Regular,Menlo,monospace}
.code table{border-collapse:collapse;width:100%}
.code td{padding:0 12px 0 0;white-space:pre;vertical-align:top}
.code td.n{text-align:right;padding:0 12px;width:1%;opacity:.4;user-select:none;
position:sticky;left:0;background:inherit}
.code tr.hit{background:rgba(255,196,0,.16)}
.code tr.hit td.n{background:rgba(255,196,0,.16);opacity:.85;font-weight:600}
.k{color:#a626a4}.s{color:#1a9e75}.c{opacity:.5;font-style:italic}
@media(prefers-color-scheme:dark){.k{color:#c678dd}.s{color:#98c379}}
.gone{font-family:ui-monospace,monospace;font-size:12.5px;padding:7px 11px;
margin:0 0 6px;border-radius:7px;opacity:.55}
.hint{font-size:12.5px;opacity:.5;margin-top:26px}
#over{position:fixed;inset:0;background:inherit;display:none;place-items:center;padding:40px}
#over.on{display:grid}
#over div{max-width:560px}
#over h3{font-size:20px;font-weight:500;margin:0 0 6px}
#over code{font-family:ui-monospace,monospace;font-size:12.5px;opacity:.7}
</style></head><body>
<main>
  <div id="left"><div id="list"></div>
    <div id="bar"><span id="stat_"></span>
      <button id="fin" onclick="finish()"></button></div></div>
  <div id="pane"></div>
</main>
<div id="over"><div id="overtext"></div></div>
<script>
const D = __DATA__;
let sel = 0;
let done = false;           // set by Finish — the server is gone after that
const open = {};            // "id|path|line" -> {from, to}
const cache = {};           // path -> [lines]
const G = Object.fromEntries((D.groups||[]).map(g => [g.id, g.title]));
const esc = s => String(s).replace(/[&<>"']/g,
  c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const KW = "fun|val|var|class|object|interface|import|package|return|if|else|when|for|while|do|"
  + "private|internal|public|protected|override|open|abstract|suspend|data|sealed|enum|const|"
  + "lateinit|companion|init|by|is|in|as|null|true|false|this|super|try|catch|finally|throw|"
  + "typealias|operator|inline|expect|actual|func|let|struct|extension|protocol|guard|self|"
  + "def|from|not|and|or|async|await|static|final|new|void|int|String";
const RX = new RegExp('("(?:[^"\\\\\\n]|\\\\.)*"|//[^\\n]*|#[^\\n]*|/\\\\*[\\\\s\\\\S]*?\\\\*/)|\\\\b(' + KW + ')\\\\b', 'g');
// code lands in a <td>, where quotes are harmless — and keeping them literal is
// what lets the string rule below still match.
const escCode = s => String(s).replace(/[&<>]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;'}[c]));
const hl = s => escCode(s).replace(RX, (m, lit) =>
  lit ? `<span class="${lit[0] === '/' || lit[0] === '#' ? 'c' : 's'}">${m}</span>`
      : `<span class="k">${m}</span>`);
fin.textContent = D._waiting ? 'Done → back to Claude' : 'Finish review';
// Two projects triaged in two tabs are the same page without this.
if (D.project) document.title = D.project + ' — review triage';

function stat(){
  const n = v => D.findings.filter(x => x.decision === v).length;
  const f = n('fix'), s = n('skip'), d = n('discuss');
  const left = D.findings.length - f - s - d;
  stat_.textContent = `fix ${f} · skip ${s} · discuss ${d} · undecided ${left}`;
  fin.className = left ? '' : 'ready';
}
function drawList(){
  let h = '', g = null;
  D.findings.forEach((x, i) => {
    if (x.group !== g){ g = x.group; h += `<div class="grp">${esc(G[g] || g)}</div>`; }
    const box = {fix:'[x]', skip:'[-]', discuss:'[?]'}[x.decision] || '[ ]';
    h += `<div class="it ${x.decision || ''} ${i === sel ? 'on' : ''}" data-i="${i}">
      <span class="bx">${box}</span><span class="tt">${esc(x.id)} · ${esc(x.title)}</span></div>`;
  });
  list.innerHTML = h;
  list.querySelectorAll('.it').forEach(e =>
    e.onclick = () => { sel = +e.dataset.i; draw(); });
  const on = list.querySelector('.it.on');
  if (on) on.scrollIntoView({block:'nearest'});
}
function table(lines, from, to, hit){
  let rows = '';
  for (let n = from; n <= to; n++)
    rows += `<tr class="${n === hit ? 'hit' : ''}"><td class="n">${n}</td>`
          + `<td>${hl(lines[n-1] ?? '')}</td></tr>`;
  return `<div class="code"><table>${rows}</table></div>`;
}
function drawSrc(j){
  const box = document.getElementById('src_' + sel + '_' + j);
  if (!box) return;
  const r = D.findings[sel].refs[j], w = open[key(j)], got = cache[r.path];
  if (!got){ box.innerHTML = `<div class="bar2">${esc(r.path)} — not readable</div>`; return; }
  if (w.from > got.lines.length){    // past the read cap: an empty table under a
    box.innerHTML = `<div class="bar2">${esc(r.path)} — line ${r.line} is past `
      + `the first ${got.lines.length} lines, which is all that was read `
      + `(${got.total} in the file)</div>`;   // backwards range says nothing
    return;
  }
  const from = Math.max(1, w.from), to = Math.min(got.lines.length, w.to);
  const cut = got.total > got.lines.length ? `, only the first ${got.lines.length} read` : '';
  box.innerHTML = `<div class="bar2">
      <button data-grow="${j}" data-dir="-1">▲ 20</button>
      <button data-grow="${j}" data-dir="1">▼ 20</button>
      <span>${esc(r.path)}</span>
      <span class="sp">${from}–${to} of ${got.total}${cut}</span></div>`
    + table(got.lines, from, to, r.line);
  box.querySelectorAll('[data-grow]').forEach(e => e.onclick = () => {
    const g = open[key(+e.dataset.grow)];
    if (+e.dataset.dir < 0) g.from -= 20; else g.to += 20;
    drawSrc(+e.dataset.grow);
  });
}
const key = j => sel + '|' + j;
async function toggleRef(j){
  if (open[key(j)]){ delete open[key(j)]; drawPane(); return; }
  const r = D.findings[sel].refs[j];
  const c = Math.max(1, r.line || 1);
  open[key(j)] = {from: c - 12, to: c + 12};
  if (!cache[r.path]){
    const got = await fetch('/file?path=' + encodeURIComponent(r.path));
    cache[r.path] = got.ok ? await got.json() : null;
  }
  drawPane();
}
function drawPane(){
  const x = D.findings[sel];
  const sec = (l, v) => v && String(v).trim()
    ? `<div class="lbl">${l}</div><p>${esc(v)}</p>` : '';
  let refs = '';
  (x.refs || []).forEach((r, j) => {
    const loc = r.line ? `${r.path}:${r.line}` : r.path;
    refs += `<button class="ref" data-ref="${j}">`
          + `<span class="ar">${open[key(j)] ? '▾' : '▸'}</span>${esc(loc)}</button>`
          + (open[key(j)] ? `<div class="src" id="src_${sel}_${j}"></div>` : '');
  });
  (x.missing || []).forEach(name => {
    refs += `<div class="gone">${esc(name)} — no such file in the project</div>`;
  });
  const b = (v, l, c) => `<button class="${x.decision === v ? 'act ' + c : ''}"`
                       + ` onclick="setD('${v}')">${l}</button>`;
  pane.innerHTML = `<h2>${esc(x.id)} · ${esc(x.title)}</h2>
    <div class="acts">${b('fix','Fix','')}${b('skip','Skip','')}${b('discuss','Discuss','d')}</div>
    ${sec('What you would see', x.see)}${sec('Why', x.why)}
    ${refs ? '<div class="lbl">Code</div>' + refs : sec('Where', x.where)}
    ${sec('Fix', x.fix)}${sec('My call', x.call)}
    <div class="hint">↑↓ move · F fix · S skip · D discuss · click a location to read the file</div>`;
  pane.querySelectorAll('[data-ref]').forEach(e =>
    e.onclick = () => toggleRef(+e.dataset.ref));
  (x.refs || []).forEach((r, j) => { if (open[key(j)]) drawSrc(j); });
}
function draw(){ drawList(); drawPane(); stat(); }
function setD(v){
  if (done) return;
  const x = D.findings[sel];
  x.decision = x.decision === v ? null : v;
  draw();
  fetch('/save', {method:'POST', headers:{'Content-Type':'application/json'},
                  body: JSON.stringify({id: x.id, decision: x.decision})});
}
async function finish(){
  done = true;              // the server is about to stop: nothing after this
  const r = await fetch('/done', {method:'POST'});   // can still be saved, so
  overtext.innerHTML = `<h3>${D._waiting ? 'Back to Claude' : 'Review closed'}</h3>`
                     + `<p>${esc(await r.text())}</p>`;   // stop accepting answers
  over.className = 'on';
}
onkeydown = e => {
  if (done) return;
  // Cmd+F is find, Cmd+S is save, Cmd+D is bookmark — in a tool for reading
  // code in a browser they are certain to be pressed, and a bare `f` test
  // would answer the finding on the way past.
  if (e.metaKey || e.ctrlKey || e.altKey) return;
  if (e.key === 'ArrowDown'){ sel = Math.min(sel + 1, D.findings.length - 1); draw(); e.preventDefault(); }
  else if (e.key === 'ArrowUp'){ sel = Math.max(sel - 1, 0); draw(); e.preventDefault(); }
  else if (e.key.toLowerCase() === 'f'){ setD('fix'); }
  else if (e.key.toLowerCase() === 's'){ setD('skip'); }
  else if (e.key.toLowerCase() === 'd'){ setD('discuss'); }
};
draw();
</script></body></html>"""


def payload(doc):
    out = dict(doc.doc, _waiting=WAITING)
    out["findings"] = [dict(x, **dict(zip(("refs", "missing"),
                                          locations(x, doc.root, doc.index))))
                       for x in doc.findings]
    text = json.dumps(out, ensure_ascii=False)
    for ch in ("<", " ", " "):   # `</script>` and JS line breaks
        text = text.replace(ch, "\\u%04x" % ord(ch))
    return text


def run_web(doc, port=8731):
    class H(BaseHTTPRequestHandler):
        def log_message(self, *a):
            pass

        def reply(self, code, body, ctype):
            self.send_response(code)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def local(self):
            """Only our own loopback name. Without this, a hostile page can
            point a DNS name at 127.0.0.1 and read the project's source."""
            host = (self.headers.get("Host") or "").rsplit(":", 1)[0].strip("[]")
            if host in ("127.0.0.1", "localhost", "::1"):
                return True
            self.send_error(403)
            return False

        def ours(self):
            """`local` is not enough for a write: the browser puts our own Host
            on a cross-site form post too, so any open tab could POST /done and
            end the review — handing Claude a tally that reads as a finished
            triage. These two headers are what distinguishes our own page."""
            site = self.headers.get("Sec-Fetch-Site")
            origin = self.headers.get("Origin")
            mine = f"http://127.0.0.1:{self.server.server_port}"
            if (site is None or site == "same-origin") and origin in (None, mine):
                return True
            self.send_error(403)
            return False

        def do_GET(self):
            if not self.local():
                return
            url = urlparse(self.path)
            if url.path == "/":
                return self.reply(200, PAGE.replace("__DATA__", payload(doc)).encode(),
                                  "text/html; charset=utf-8")
            if url.path == "/file":
                rel = (parse_qs(url.query).get("path") or [""])[0]
                lines, total = read_source(doc.root, rel)
                if lines is None:
                    return self.send_error(404)
                return self.reply(200, json.dumps(
                    {"path": rel, "lines": lines, "total": total}).encode(),
                    "application/json")
            self.send_error(404)

        def do_POST(self):
            if not self.local() or not self.ours():
                return
            path = urlparse(self.path).path
            if path == "/done":
                words = closing_words(doc, headline=False).strip()
                self.reply(200, words.encode(), "text/plain; charset=utf-8")
                threading.Thread(target=server.shutdown, daemon=True).start()
                return
            if path != "/save":
                return self.send_error(404)
            size = int(self.headers.get("Content-Length") or 0)
            if not 0 < size <= 4096:
                return self.send_error(400)
            try:
                change = json.loads(self.rfile.read(size))
                fid, value = change["id"], change["decision"]
                assert value is None or value in DECISIONS
            except Exception:
                return self.send_error(400)
            if not doc.set(fid, value):    # the page owns the toggle, not the server
                return self.send_error(404)
            doc.save()
            self.send_response(204)
            self.end_headers()

    for p in range(port, port + 20):
        try:
            server = HTTPServer(("127.0.0.1", p), H)
            break
        except OSError:
            continue
    else:
        sys.exit(f"Ports {port}–{port + 19} are all busy.")

    import webbrowser
    url = f"http://127.0.0.1:{server.server_port}/"
    print(f"{url}\n{doc.store}\n"
          + ("Waiting — this exits when you press Done in the page."
             if WAITING else
             "Press Finish review in the page when you are done (or Ctrl+C)."), flush=True)
    webbrowser.open(url)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    print(closing_words(doc))


if __name__ == "__main__":
    if "--where" in sys.argv:
        # The one place that knows the slug rule. Whoever writes findings asks
        # here instead of building the path themselves and missing by a dash.
        target = next((a for a in sys.argv[1:] if not a.startswith("-")), None)
        base = os.path.abspath(os.path.expanduser(target)) if target else os.getcwd()
        print(store_target(base))
        sys.exit(0)
    document = Doc(locate(sys.argv))
    if "--web" in sys.argv:
        run_web(document)
    else:
        run_tui(document)
