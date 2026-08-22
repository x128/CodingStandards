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
     "lang":    "en" | "ru",                # what the findings are written in;
                                           #   the screen speaks it too
     "findings": [{"id", "title", "where", "options", "decision", ...}]}

Required on a finding: `id`, `title`, `where`, `options`, `decision`. The list
has no headings and no sections: findings are read in the order they are
written, so write them in the order they should be read.
Optional: `see`, `why`, `fix`, `refs` — absent ones are skipped, not blanked.
Nothing else is read; a field this list does not name is carried through the
file and never shown.

`options` is what can be done about this finding, written by whoever found it:

    [{"id": "fix-now",
      "do": "Fix it now: add a night theme and let the system pick the colour",
      "why": "Twenty lines, and it fits in the task being done. But it gets
              rewritten anyway once T-002 lays out the screens."},
     {"id": "note-in-t002",
      "do": "Leave it, and write into task T-002 that the screen flashes white
             on launch",
      "why": "T-002 rewrites launch and touches these files, so it gets fixed
              there for free. Unwritten, it is forgotten and found again in six
              months.",
      "advised": true}]

`do` is the button, and it is a sentence: what happens when it is pressed,
spelled out for someone who has not read the code. Never a category — "defer",
"later", "wontfix" name a bucket, not an act. Never a compression either: three
words that stand for a sentence read as noise, and an option nobody can read is
a finding thrown away. `why` is the price and what it costs later. `advised`
marks the recommendation and nothing more: there is no default answer and no
key that takes one blind.

One option is drawn as a plain button — no number, no card, no column, and its
key is `f`, not `1`: numbering a list of one asks the reader to pick one out of
one. A choice of one is not a choice, it is an action, so `do` is the act
itself — "Fix it", "Add it to git" — and the fix is described in `fix`, a
section of prose above the buttons. That heading carries no verb of its own, so
whatever verb the button uses, the two never contradict each other:

    {"fix": "Back on the file screen is not intercepted, so the system closes
             the app. Put the handler back in navigation, so Back returns to
             the list the file was opened from.",
     "options": [{"id": "fix", "do": "Fix it"}]}

With several options there is no `fix` section: each one carries its own words,
and a paragraph above them would say the same thing twice.

Skip and Discuss are always available and are never options: nothing gets done
about the finding either way. They are buttons like any other, and never rows in
the table — two real choices must look like two, not like four.

Writing "A, or else B" into a single option is the one mistake that matters:
that is two options, and collapsing them hands the choice back to the reviewer
silently, with the file recording an answer the user never gave.

`decision` and `note` are the user's, and the only things written back:
`decision` is an option's `id`, or "skip", or "discuss", or null; `note` is free
text they can leave with any answer, and it comes back with the triage — the
placeholder says so, because a box labelled "note" answers neither who reads it
nor why. It is not on screen until there is a reason for it: Discuss opens it,
"add a comment" under an answered finding opens it, `n` opens it, and existing
text keeps it open. An empty box under every finding is a question nobody asked
— but a box reachable only by a keystroke is one that does not exist.

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
ALWAYS = (SKIP, DISCUSS)          # answers, but never options: see WORDS below
NOISE = {".git", "build", ".gradle", "node_modules", "DerivedData", "Pods", ".idea"}

#  Every word on the screen, in the language the review is written in. A finding
#  written in Russian under a heading that says "What you would see" is half
#  unreadable, and the half that is English is the half nobody asked for. The
#  file says which language it is in; nothing here guesses.
WORDS = {
    "en": {"see": "What you would see", "why": "Why", "code": "Code",
           "where": "Where", "gone": "no such file in the project",
           "empty": "No findings — there is nothing to triage.",
           "fix": "The fix",
           "ways": "Ways to fix it", "skip": "Skip", "discuss": "Discuss",
           "advised": "advised", "note": "Comment", "question": "Discussion",
           "add_note": "Add a comment", "note_ph": "Claude reads this together "
           "with your answer — say anything the button does not",
           "question_ph": "Write what you want to talk about",
           "answered": "answered {done} of {total}",
           "to_discuss": " · {n} to discuss",
           "finish": "Done → hand it to Claude",
           "finish_waiting": "Done → hand it to Claude",
           "closed": "Review closed", "stored": "Answers are in",
           "keep": "I'll finish them", "confirm_yes": "Hand it over anyway",
           "confirm_keys": "y — {yes}, anything else — {no}",
           "confirm": "{n} findings have no answer — Claude will leave those alone.",
           "keys_list": "↑↓ pick · → read · n {note} · q finish",
           "keys_text": "↑↓ scroll · ← list · tab code · space open · "
                        "n {note} · q finish",
           "hint_web": "↑↓ move · {pick}s {skip} · d {discuss} · "
                       "click a location to read the file",
           "pick_one": "f {do} · ", "pick_many": "1-{n} the ways to fix it · ",
           "nothing": "Nothing to do: everything was skipped.",
           "unfinished": "Nothing decided yet — reopen when you want to finish.",
           "handoff": ["Tell Claude the triage is done. It carries out the option",
                       "each finding was answered with, and brings every question",
                       "back to you. Comments are read with the answer they sit on."],
           "waiting": ["Claude was waiting on this process and has the result now.",
                       "You can close the page."]},
    "ru": {"see": "Что ты увидишь", "why": "Почему", "code": "Код",
           "where": "Где", "gone": "такого файла в проекте нет",
           "empty": "Находок нет — разбирать нечего.",
           "fix": "Исправление",
           "ways": "Варианты исправления",
           "skip": "Пропустить", "discuss": "Обсудить",
           "advised": "советую", "note": "Комментарий", "question": "Обсуждение",
           "add_note": "Добавить комментарий",
           "note_ph": "Claude прочитает это вместе с твоим ответом — напиши то, "
           "чего не говорит кнопка",
           "question_ph": "Напиши, что хочешь обсудить",
           "answered": "отвечено {done} из {total}",
           "to_discuss": " · на обсуждение: {n}",
           "finish": "Готово → передать Claude",
           "finish_waiting": "Готово → передать Claude",
           "closed": "Ревью закрыто", "stored": "Ответы лежат в",
           "keep": "Доделаю", "confirm_yes": "Всё равно передать",
           "confirm_keys": "y — {yes}, иначе — {no}",
           "confirm": "Без ответа осталось: {n} — по ним Claude ничего "
                      "делать не будет.",
           "keys_list": "↑↓ выбрать · → читать · n {note} · q закончить",
           "keys_text": "↑↓ листать · ← список · tab код · пробел открыть · "
                        "n {note} · q закончить",
           "hint_web": "↑↓ листать · {pick}s {skip} · d {discuss} · "
                       "нажми на строку с кодом, чтобы открыть файл",
           "pick_one": "f {do} · ", "pick_many": "1-{n} варианты исправления · ",
           "nothing": "Делать нечего: всё пропущено.",
           "unfinished": "Пока ничего не решено — открой снова, когда захочешь.",
           "handoff": ["Скажи Claude, что разбор закончен. Он сделает то, что",
                       "выбрано в каждой находке, и вернётся с каждым вопросом.",
                       "Комментарий читает вместе с ответом, к которому он оставлен."],
           "waiting": ["Claude ждал этот процесс и уже получил результат.",
                       "Страницу можно закрыть."]},
}


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

def options_of(item):
    """What this finding offers, in the order it is shown."""
    return [o for o in (item.get("options") or [])
            if isinstance(o, dict) and o.get("id") and o.get("do")]


def answers(item):
    return [o["id"] for o in options_of(item)] + list(ALWAYS)


def chose(item):
    """Which option was picked, 1-based — 0 for skip, discuss, or nothing yet."""
    d = item.get("decision")
    return next((n for n, o in enumerate(options_of(item), 1) if o["id"] == d), 0)


def answered(item):
    return item.get("decision") in ALWAYS or bool(chose(item))


class Doc:
    def __init__(self, store):
        self.store = store
        with open(store, encoding="utf-8") as f:
            self.doc = json.load(f)
        self.findings = self.doc.get("findings") or []
        self.t = WORDS.get(self.doc.get("lang"), WORDS["en"])
        self.root = self._root()
        self.index = index_files(self.root)
        self.baseline = self._state()
        self._source = {}

    def source(self, rel):
        """`read_source`, remembered. The terminal redraws the whole detail pane
        on every keystroke, so without this an open file is re-read and re-split
        from disk each time an arrow key repeats."""
        if rel not in self._source:
            self._source[rel] = read_source(self.root, rel)
        return self._source[rel]

    def _state(self):
        """Both of the user's fields, together — a note left on a finding whose
        decision never changed is still an answer, and must survive the merge."""
        return {x.get("id"): (x.get("decision"), x.get("note") or "")
                for x in self.findings}

    def _root(self):
        if self.doc.get("root") and os.path.isdir(self.doc["root"]):
            return self.doc["root"]
        here = git_root(os.getcwd()) or os.getcwd()
        if store_for(here) == self.store:
            return here            # standing in the project this file describes
        sys.exit(f'{self.store} has no usable "root", and it is not the store\n'
                 f'for {here}. Every code link would resolve against the wrong\n'
                 f'tree. Add "root": "/path/to/project" to the file.')

    def counts(self):
        """(decided, skipped, to discuss, untouched). Options cannot be summed
        across findings — "fix 3" stopped being a fact the moment each finding
        started offering its own — so the tally counts answers, not kinds."""
        done = skipped = asked = un = 0
        for x in self.findings:
            d = x.get("decision")
            if d == SKIP:
                skipped += 1
            elif d == DISCUSS:
                asked += 1
            elif chose(x):
                done += 1
            else:
                un += 1
        return done, skipped, asked, un

    def notes(self):
        return sum(1 for x in self.findings if (x.get("note") or "").strip())

    def find(self, fid):
        return next((x for x in self.findings if x.get("id") == fid), None)

    def toggle(self, fid, value):
        x = self.find(fid)
        if x is not None:
            x["decision"] = None if x.get("decision") == value else value

    def note(self, fid, text):
        x = self.find(fid)
        if x is not None:
            x["note"] = text

    def apply(self, fid, change):
        """A partial answer from the page: decision, note, or both."""
        x = self.find(fid)
        if x is None:
            return False
        if "decision" in change:
            x["decision"] = change["decision"]
        if "note" in change:
            x["note"] = change["note"]
        return True

    def save(self):
        """Write back only the answers this session changed — decision and note
        alike — merged onto what is on disk now. Two open copies of the tool, or
        a stale one quit hours later, then cannot silently undo each other."""
        mine = {k: v for k, v in self._state().items() if v != self.baseline.get(k)}
        if not mine and os.path.exists(self.store):
            return
        try:
            with open(self.store, encoding="utf-8") as f:
                disk = json.load(f)
        except Exception:
            disk = self.doc
        for x in disk.get("findings") or []:
            if x.get("id") in mine:
                x["decision"], text = mine[x["id"]]
                if text:
                    x["note"] = text
                else:
                    x.pop("note", None)     # an emptied note leaves no husk behind
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
        self.baseline = self._state()


#  Set by whoever launched us. When Claude did, this process *is* the channel
#  back: Finish stops the server, the command Claude is waiting on returns, and
#  the summary below is what it reads. Launched from your own shell, there is no
#  such channel and the tool can only tell you to go say so.
WAITING = os.environ.get("TRIAGE_CALLER") == "claude"


def tally_of(doc):
    """One line: how much is answered, plus the only leftover that needs the
    user again. Four numbers to subtract in your head is not a progress bar."""
    t = doc.t
    done, sk, di, un = doc.counts()
    total = len(doc.findings)
    out = t["answered"].format(done=total - un, total=total)
    return out + (t["to_discuss"].format(n=di) if di else "")


def closing_words(doc, headline=True):
    t = doc.t
    done, sk, di, un = doc.counts()
    tally = tally_of(doc)
    out = ["", t["closed"] + " — " + tally] if headline else [tally]
    out += [f"{t['stored']} {doc.store}", ""]
    if WAITING:
        out += t["waiting"]
    elif done or di:
        out += t["handoff"]
    elif un:
        out.append(t["unfinished"])
    else:
        out.append(t["nothing"])
    return "\n".join(out)


# ──────────────────────────────── terminal ────────────────────────────────

def run_tui(doc):
    import curses
    import textwrap

    t = doc.t
    name = doc.doc.get("project") or ""
    if name:                       # the window title, where a browser tab would
        sys.stdout.write(f"\033]0;{name} — review triage\007")
        sys.stdout.flush()
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
        def tone(x):
            d = x.get("decision")
            return DIM if d == SKIP else BLUE if d == DISCUSS else \
                GREEN if chose(x) else 0

        pane, sel, scroll, opened = "list", 0, 0, {}
        refcur = {}         # finding → which code link the cursor is on

        def put(y, x, text, attr=0, width=None):
            room = (width if width is not None else scr.getmaxyx()[1] - x) - 1
            if room > 0:
                try:
                    scr.addnstr(y, x, text, room, attr)
                except curses.error:
                    pass

        def list_rows():
            rows = []
            for i, x in enumerate(doc.findings):
                pen = "*" if (x.get("note") or "").strip() else " "
                tick = "✓" if answered(x) else f"{i + 1}"
                rows.append((i, f" {tick:>2} {pen}{x.get('title', '')}", tone(x)))
            return rows

        def detail_rows(width):
            item = doc.findings[sel]
            rows = [(item.get("title", ""), BOLD),
                    (item.get("id", ""), DIM), ("", 0)]
            for key in ("see", "why"):
                label, val = t[key], (item.get(key) or "").strip()
                if not val:
                    continue
                rows.append((label.upper(), MAGENTA | BOLD))
                for para in val.split("\n"):
                    for line in textwrap.wrap(para, max(20, width - 2)) or [""]:
                        rows.append((line, 0))
                rows.append(("", 0))
            refs, missing = locations(item, doc.root, doc.index)
            if refs:
                rows.append((t["code"].upper(), MAGENTA | BOLD))
                for n, r in enumerate(refs, 1):
                    loc = f"{r['path']}:{r['line']}" if r["line"] else r["path"]
                    key = (sel, n)
                    on = refcur.get(sel, 0) == n - 1
                    rows.append((f" {'»' if on else ' '} {'▾' if key in opened else '▸'}"
                                 f" {loc}", CYAN | BOLD if on else CYAN))
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
                for name in missing:
                    rows.append((f"  {name} — {t['gone']}", DIM))
                rows.append(("", 0))
            elif not refs:
                rows.append((f"({item.get('where', '—')})", DIM))
                rows.append(("", 0))

            picked = item.get("decision")
            opts = options_of(item)
            # One way forward: describe it here, in full, and let the button be
            # the verb. Several ways: each carries its own words, and a section
            # above them would only say the same thing twice.
            how = (item.get("fix") or "").strip() or \
                  ((opts[0].get("why") or "").strip() if len(opts) == 1 else "")
            if how:
                rows.append((t["fix"].upper(), MAGENTA | BOLD))
                for para in how.split("\n"):
                    for line in textwrap.wrap(para, max(20, width - 2)) or [""]:
                        rows.append((line, 0))
                rows.append(("", 0))

            said = how and not (item.get("fix") or "").strip()   # `why` is above

            # A heading over a single button repeats the section that just said
            # what the fix is. Over several it does the work of naming them.
            if len(opts) > 1:
                rows.append((t["ways"].upper(), MAGENTA | BOLD))

            def cell(key, o, w):
                """One choice as a block of lines — a column of the table."""
                on = o["id"] == picked
                head = GREEN | BOLD if on else BOLD
                out = [(line, head) for line in
                       textwrap.wrap(f"{key}  {o.get('do', '')}", max(12, w),
                                     subsequent_indent="   ") or [str(key)]]
                if o.get("advised"):
                    out.append((f"   ▸ {t['advised']}", CYAN | BOLD))
                if not said:
                    out += [("   " + line, DIM) for line in
                            textwrap.wrap((o.get("why") or "").strip(), max(12, w - 3))]
                return out

            # Side by side while there is room: two choices are a choice, and a
            # vertical list of them reads as a queue of things to get through.
            cw = (width - 4) // 2
            if len(opts) > 1 and cw >= 26:
                for i in range(0, len(opts), 2):
                    left = cell(i + 1, opts[i], cw)
                    right = cell(i + 2, opts[i + 1], cw) if i + 1 < len(opts) else []
                    for k in range(max(len(left), len(right))):
                        seg = []
                        if k < len(left):
                            seg.append((1, left[k][0], left[k][1]))
                        if k < len(right):
                            seg.append((cw + 3, right[k][0], right[k][1]))
                        rows.append(seg)
                    rows.append(("", 0))
            elif len(opts) == 1:
                # Not "1 of 1". It is f, and it sits with s and d as the third
                # thing you can press.
                rows += [(" " + line, attr)
                         for line, attr in cell("f", opts[0], width - 3)]
            else:
                for n, o in enumerate(opts, 1):
                    rows += [(" " + line, attr) for line, attr in cell(n, o, width - 3)]
                    rows.append(("", 0))

            # Not options, and never in the table: nothing is being done about
            # the finding either way.
            rows.append((f" s  {t['skip']}", BOLD if picked == SKIP else 0))
            rows.append((f" d  {t['discuss']}", BOLD if picked == DISCUSS else 0))

            text = (item.get("note") or "").strip()
            if text or picked == DISCUSS:
                rows.append(("", 0))
                rows.append((t["question" if picked == DISCUSS else "note"].upper(),
                             MAGENTA | BOLD))
                for line in (textwrap.wrap(text, max(24, width - 2)) or [""]) if text \
                        else [f"({t['question_ph']} — n)"]:
                    rows.append((line, 0 if text else DIM))
            return rows

        def confirm(question):
            """y hands it over, anything else goes back to answering.
            Deliberately not Enter: the key you hit by accident must not be the
            one that leaves work on the floor."""
            h, w = scr.getmaxyx()
            keys = t["confirm_keys"].format(yes=t["confirm_yes"], no=t["keep"])
            put(h - 1, 0, f" {question}   {keys} ".ljust(w - 1), REV, w)
            scr.refresh()
            return scr.getch() in (ord("y"), ord("Y"))

        def write_note(item):
            """A line editor along the foot of the screen. Enter keeps it, Esc
            leaves what was there — the only place Enter decides anything, and
            it decides about text, never about a finding."""
            text = item.get("note") or ""
            curses.curs_set(1)
            try:
                while True:
                    h, w = scr.getmaxyx()
                    picked = item.get("decision")
                    label = f" {t['question' if picked == DISCUSS else 'note']}: "
                    room = max(8, w - len(label) - 2)
                    shown = text[-room:]
                    put(h - 1, 0, (label + shown).ljust(w - 1), REV, w)
                    try:
                        scr.move(h - 1, min(w - 2, len(label) + len(shown)))
                    except curses.error:
                        pass
                    scr.refresh()
                    try:
                        k = scr.get_wch()     # get_wch, not getch: a note is
                    except curses.error:      # typed in whatever language the
                        continue              # review is written in
                    if isinstance(k, str):
                        if k == "\x1b":
                            return None
                        if k in ("\n", "\r"):
                            return text
                        if k in ("\x7f", "\b"):
                            text = text[:-1]
                        elif k >= " ":
                            text += k
                    elif k in (curses.KEY_BACKSPACE, curses.KEY_DC):
                        text = text[:-1]
                    elif k == curses.KEY_ENTER:
                        return text
            finally:
                curses.curs_set(0)

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
            for i, row in enumerate(body[scroll:scroll + h - 1]):
                if isinstance(row, list):          # a row of side-by-side cells
                    for dx, line, attr in row:
                        put(i, lw + 1 + dx, line, attr, rw + 1 - dx)
                else:
                    put(i, lw + 1, row[0], row[1], rw + 1)

            for y in range(h - 1):
                put(y, lw, "│", DIM, 2)

            keys = " " + t["keys_list" if pane == "list" else "keys_text"] \
                        .format(note=t["note"]) + " "
            # Keys first. A narrow terminal clips the end of this line, and what
            # gets clipped has to be the progress, not the way out.
            put(h - 1, 0, (keys + "│ ").ljust(w - 1), REV, w)
            cells = min(len(doc.findings), 24)
            filled = round(cells * sum(answered(x) for x in doc.findings)
                           / max(1, len(doc.findings)))
            at = len(keys) + 2
            put(h - 1, at, "█" * filled, REV | GREEN, w - at)
            put(h - 1, at + filled, "░" * (cells - filled), REV, w - at - filled)
            put(h - 1, at + cells, " " + tally_of(doc) + " ", REV, w - at - cells)
            scr.refresh()

            k = scr.getch()
            refs, _ = locations(item, doc.root, doc.index)
            # Esc used to quit. It is also the first byte of every arrow key, so
            # a reach for → could end the review — and nothing that ends it
            # should be one stray byte away.
            if k == ord("q"):
                un = doc.counts()[3]
                if not un or confirm(t["confirm"].format(n=un)):
                    break
            elif ord("1") <= k <= ord("9"):
                opts = options_of(item)
                n = k - ord("0")
                if len(opts) > 1 and n <= len(opts):
                    doc.toggle(item["id"], opts[n - 1]["id"])
            elif k == ord("f"):
                opts = options_of(item)
                if len(opts) == 1:
                    doc.toggle(item["id"], opts[0]["id"])
            elif k == ord("s"):
                doc.toggle(item["id"], SKIP)
            elif k in (ord("d"), ord("n")):
                if k == ord("d"):
                    doc.toggle(item["id"], DISCUSS)
                # Discuss without a question is an empty hand-back, so turning it
                # on drops straight into the note. Turning it off leaves the text
                # alone — `n` is how you come back to it.
                if k == ord("n") or item.get("decision") == DISCUSS:
                    got = write_note(item)
                    if got is not None:
                        doc.note(item["id"], got)
            elif k == 9 and refs:                       # tab — walk the code links
                refcur[sel] = (refcur.get(sel, 0) + 1) % len(refs)
                pane = "detail"
            elif k == ord(" ") and refs:
                n = refcur.get(sel, 0) + 1
                key = (sel, n)
                if key in opened:
                    del opened[key]
                else:
                    anchor = refs[n - 1]["line"] or 1
                    opened[key] = [anchor - 10, anchor + 14]
                pane = "detail"
            elif k == curses.KEY_RIGHT:
                pane = "detail"
            elif k == curses.KEY_LEFT:
                pane = "list"
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
.it{padding:9px 10px;border-radius:7px;cursor:pointer;display:flex;gap:9px;align-items:flex-start}
.it:hover{background:rgba(128,128,128,.1)}
.it.on{background:rgba(120,120,255,.16)}
.bx{flex:0 0 auto;width:14px;font-size:12.5px;line-height:1.62;opacity:.45;
font-variant-numeric:tabular-nums;text-align:right}
.it.fix .bx,.it.discuss .bx{font-size:13px}
.it.fix .bx{color:#1a9e75;opacity:1}
.it.discuss .bx{color:#4a80e0;opacity:1}
.it.skip{opacity:.45}
.tt{font-size:13.5px}
#bar{border-top:1px solid rgba(128,128,128,.25);padding:12px 14px;display:flex;
gap:12px;align-items:center}
#stat_{flex:1;min-width:70px}
.steps{display:flex;gap:3px;margin:0 0 6px}
.steps span{flex:1;height:5px;border-radius:3px;background:rgba(128,128,128,.28)}
.steps span.on{background:#1a9e75}
/* Digits of equal width, so the line does not jitter as the count climbs. */
.count{font-size:12px;opacity:.6;font-variant-numeric:tabular-nums}
#pane{overflow-y:auto;padding:28px 34px 60px}
#pane h2{font-size:19px;font-weight:500;margin:0 0 6px}
.slug{font-family:ui-monospace,monospace;font-size:11px;opacity:.35;margin:0 0 20px}
.lbl{font-size:11px;letter-spacing:.08em;text-transform:uppercase;opacity:.5;margin:22px 0 5px}
p{margin:0 0 10px;white-space:pre-wrap}
button{font:inherit;font-size:14px;padding:8px 18px;border-radius:7px;cursor:pointer;
border:1px solid rgba(128,128,128,.4);background:transparent;color:inherit}
button:hover{background:rgba(128,128,128,.14)}
button.act{border-color:#1a9e75;color:#1a9e75}
button.act.d{border-color:#4a80e0;color:#4a80e0}
/* Choices sit side by side: two of them are a choice to weigh, and stacking
   them turns the pair into a queue to work down. */
.opts{display:grid;grid-template-columns:repeat(auto-fit,minmax(250px,1fr));
gap:10px;margin:0 0 14px;align-items:stretch}
.opt{display:flex;flex-direction:column;gap:6px;text-align:left;padding:15px 17px}
.opt b{font-weight:500;font-size:15px;line-height:1.5}
.opt i{font-style:normal;font-size:13.5px;line-height:1.5;opacity:.6}
/* Selected is a state of the card, not of its words: tinting the explanation
   green costs more readability than the border buys. */
.opt.act{background:rgba(26,158,117,.09);border-color:#1a9e75;color:inherit}
.opt.act .num{border-color:#1a9e75;color:#1a9e75}
.opt .top{display:flex;gap:9px;align-items:center}
.opt .num{font-family:ui-monospace,monospace;font-size:12px;opacity:.5;
border:1px solid rgba(128,128,128,.45);border-radius:5px;padding:0 6px;line-height:18px}
.opt.act .num{border-color:currentColor;opacity:1}
.adv{font-size:11px;letter-spacing:.06em;text-transform:uppercase;
padding:2px 8px;border-radius:20px;background:#1a9e75;color:#fff;font-weight:600}
/* Skip and Discuss are not options — nothing gets done about the finding either
   way — but they are answers a person clicks, so they look like every other
   button here, not like fine print. */
.row{display:flex;gap:9px;margin:0 0 12px;flex-wrap:wrap}
.ans{font-size:14px;padding:10px 18px;font-weight:500;text-align:left}
.ans.act{border-color:#1a9e75;color:#1a9e75;background:rgba(26,158,117,.1)}
p.under{font-size:13.5px;opacity:.6;margin:-4px 0 14px}
.more{border:none;padding:2px 0;font-size:13px;opacity:.6;text-decoration:underline;
text-underline-offset:3px}
.more:hover{background:transparent;opacity:1}
textarea{font:inherit;font-size:14px;width:100%;min-height:74px;padding:10px 12px;
border-radius:7px;border:1px solid rgba(128,128,128,.4);background:transparent;
color:inherit;resize:vertical}
textarea:focus{outline:none;border-color:#4a80e0}
.it .pen{opacity:.5;font-size:11px;margin-left:auto;flex:0 0 auto}
#ask{position:fixed;inset:0;background:rgba(0,0,0,.45);display:none;place-items:center;
padding:40px;z-index:5}
#ask.on{display:grid}
#ask>div{background:#faf9f7;color:#1a1a19;border-radius:12px;padding:24px 26px;
max-width:420px;box-shadow:0 18px 60px rgba(0,0,0,.35)}
@media(prefers-color-scheme:dark){#ask>div{background:#262624;color:#e8e7e3}}
#ask p{margin:0 0 18px;font-size:15px;line-height:1.5}
#ask .row{display:flex;gap:10px;justify-content:flex-end;margin:0}
/* Two buttons of equal weight say the two answers are equally good. One of
   them leaves work on the floor, so it does not get to look like the other. */
#ask .primary{background:#1a9e75;border-color:#1a9e75;color:#fff;font-weight:600}
#ask .primary:hover{background:#178a66}
#ask .ghost{border-color:transparent;opacity:.6;font-size:13.5px}
#ask .ghost:hover{opacity:1;background:rgba(128,128,128,.14)}
#fin{padding:8px 14px;font-size:13.5px;font-weight:500;flex:0 0 auto}
#fin.ready{border-color:#1a9e75;color:#1a9e75;background:rgba(26,158,117,.1)}
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
<div id="ask"><div><p id="askq"></p><div class="row">
  <button id="askno" class="primary"></button>
  <button id="askyes" class="ghost"></button></div></div></div>
<script>
const D = __DATA__;
let sel = 0;
let noteOpen = false;       // per finding: asked for by n, forgotten on the move
let done = false;           // set by Finish — the server is gone after that
const noteBox = () => document.getElementById('note');
const opts_ = i => D.findings[i].options || [];
function openNote(){ noteOpen = true; draw(); const b = noteBox(); if (b) b.focus(); }
const open = {};            // "id|path|line" -> {from, to}
const cache = {};           // path -> [lines]
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
const T = D._t;
fin.textContent = D._waiting ? T.finish_waiting : T.finish;
// Two projects triaged in two tabs are the same page without this.
if (D.project) document.title = D.project + ' — review triage';

// Which of the four states a finding is in. Options are per-finding, so the
// tally counts answers given, not kinds of answer.
const pick = x => (x.options || []).findIndex(o => o.id === x.decision) + 1;
const kind = x => x.decision === 'skip' ? 'skip'
               : x.decision === 'discuss' ? 'discuss'
               : pick(x) ? 'fix' : '';
const n = v => D.findings.filter(x => kind(x) === v).length;
const undecided = () => D.findings.length - n('fix') - n('skip') - n('discuss');
function stat(){
  // One step per finding, filled as it is answered. No arithmetic to do.
  const left = undecided();
  stat_.innerHTML = '<div class="steps">' + D.findings.map(x =>
      `<span class="${kind(x) ? 'on' : ''}"></span>`).join('') + '</div>'
    + `<div class="count">${esc(T.answered
        .replace('{done}', D.findings.length - left)
        .replace('{total}', D.findings.length))}</div>`;
  fin.className = left ? '' : 'ready';
}
function drawList(){
  // One question per row: answered or not. Which option was picked is on the
  // finding's own screen; a column of numbers here is a puzzle, not a list.
  let h = '';
  D.findings.forEach((x, i) => {
    h += `<div class="it ${kind(x)} ${i === sel ? 'on' : ''}" data-i="${i}">
      <span class="bx">${kind(x) ? '✓' : i + 1}</span>
      <span class="tt">${esc(x.title)}</span>
      ${(x.note || '').trim() ? '<span class="pen">note</span>' : ''}</div>`;
  });
  list.innerHTML = h;
  list.querySelectorAll('.it').forEach(e =>
    e.onclick = () => { flushNote(); sel = +e.dataset.i; noteOpen = false; draw(); });
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
  if (!got){ box.innerHTML = `<div class="bar2">${esc(r.path)} — ${esc(T.gone)}</div>`; return; }
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
    refs += `<div class="gone">${esc(name)} — ${esc(T.gone)}</div>`;
  });
  const opts = x.options || [];
  const btn = (id, label) =>
    `<button class="ans ${x.decision === id ? 'act' : ''}" data-opt="${esc(id)}">`
    + `${esc(label)}</button>`;
  // A choice of one is not a choice — it is an action, and it belongs in the
  // same row as the two answers that are always there. Cards, columns and a
  // number in the corner are all machinery for weighing alternatives, and there
  // are none to weigh.
  // With one way forward, the fix is described in prose above and the button is
  // just the verb. Squeezing the description onto the button leaves a label
  // nobody can read and a section that should have been there missing.
  let how = '', acts;
  if (opts.length === 1) {
    how = sec(T.fix, x.fix || opts[0].why);
    // `why` is what pressing the button costs. When `fix` took the section
    // above, the price still has to be on screen — the terminal prints it under
    // the button, and dropping it here makes the choice look cheaper than it is.
    const said = !(x.fix || '').trim();     // `why` is already the section above
    acts = `<div class="row">${btn(opts[0].id, opts[0].do)}`
         + `${btn('skip', T.skip)}${btn('discuss', T.discuss)}</div>`
         + (!said && opts[0].why ? `<p class="under">${esc(opts[0].why)}</p>` : '');
  } else {
    // A heading over one button repeats the section that just described the
    // fix. Over several it does the work of naming them. This branch also
    // catches a finding with no options at all, where there is nothing to name.
    how = sec(T.fix, x.fix)
        + (opts.length > 1 ? `<div class="lbl">${esc(T.ways)}</div>` : '');
    // The number is on the card. Reading "left to right" off a hint and
    // counting columns is work the screen can do instead.
    acts = '<div class="opts">' + opts.map((o, i) =>
        `<button class="opt ${x.decision === o.id ? 'act' : ''}" data-opt="${esc(o.id)}">`
        + `<span class="top"><span class="num">${i + 1}</span>`
        + (o.advised ? `<span class="adv">${esc(T.advised)}</span>` : '') + '</span>'
        + `<b>${esc(o.do)}</b>` + (o.why ? `<i>${esc(o.why)}</i>` : '')
        + '</button>').join('') + '</div>'
      + `<div class="row">${btn('skip', T.skip)}${btn('discuss', T.discuss)}</div>`;
  }
  // The box belongs to the button that opened it, right underneath it — by the
  // time it sits at the foot of the page it is a different context, and it
  // stops being the discussion you just started.
  const wants = x.decision === 'discuss' || (x.note || '').length || noteOpen;
  const ph = x.decision === 'discuss' ? T.question_ph : T.note_ph;
  // Once an answer is given there is often one more sentence to say about it.
  // Offering that as a keystroke and nothing else means it does not exist.
  const more = x.decision && !wants
    ? `<button class="more" data-note="1">+ ${esc(T.add_note)}</button>` : '';
  const pick = opts.length > 1
    ? T.pick_many.replace('{n}', Math.min(9, opts.length))
    : (opts.length ? T.pick_one.replace('{do}', opts[0].do) : '');
  // The id is a handle for talking about the finding afterwards, not something
  // the reader has to get past to reach the sentence that matters.
  pane.innerHTML = `<h2>${esc(x.title)}</h2><div class="slug">${esc(x.id)}</div>
    ${sec(T.see, x.see)}${sec(T.why, x.why)}
    ${refs ? `<div class="lbl">${esc(T.code)}</div>` + refs : sec(T.where, x.where)}
    ${how}${acts}
    ${more}${wants ? `<textarea id="note" maxlength="4000" placeholder="${esc(ph)}"
      >${esc(x.note || '')}</textarea>` : ''}
    <div class="hint">${esc(T.hint_web.replace('{pick}', pick)
        .replace('{skip}', T.skip).replace('{discuss}', T.discuss))}</div>`;
  if (wants){ noteBox().oninput = e => setNote(e.target.value);
              noteBox().onblur = flushNote; }
  pane.querySelectorAll('[data-note]').forEach(e => e.onclick = () => openNote());
  pane.querySelectorAll('[data-opt]').forEach(e =>
    e.onclick = () => setD(e.dataset.opt));
  pane.querySelectorAll('[data-ref]').forEach(e =>
    e.onclick = () => toggleRef(+e.dataset.ref));
  (x.refs || []).forEach((r, j) => { if (open[key(j)]) drawSrc(j); });
}
// Silence is a valid review, and an empty list is an answer — but it has to be
// said in words. Drawing the panes over nothing throws, and a white page says
// the tool is broken.
function draw(){
  if (!D.findings.length){ pane.innerHTML = `<p>${esc(T.empty)}</p>`; return; }
  drawList(); drawPane(); stat();
}
function post(body){
  return fetch('/save', {method:'POST', headers:{'Content-Type':'application/json'},
                         body: JSON.stringify(body)});
}
function setD(v){
  if (done) return;
  const x = D.findings[sel];
  x.decision = x.decision === v ? null : v;
  noteOpen = false;    // answering another way puts an empty box away again
  draw();
  if (x.decision === 'discuss') openNote();   // asking nothing is not a question
  post({id: x.id, decision: x.decision});
}
// One timer, and what it owes belongs to the finding that was typed in — not to
// whichever one is selected when it fires. Leaving the finding, leaving the box
// and finishing all send it now, so the 400 ms cannot swallow a comment.
let pending, owed;
function setNote(text){
  if (done) return;
  const x = D.findings[sel];
  x.note = text;
  drawList();          // never draw(): rebuilding the pane under a typing hand
  clearTimeout(pending);   // takes the caret with it
  owed = {id: x.id, note: text};
  pending = setTimeout(flushNote, 400);
}
function flushNote(){
  clearTimeout(pending);
  if (!owed) return;
  const body = owed;
  owed = null;
  return post(body);
}
// Finish kills the server. There is no reopening it, no back button and no
// reload — so it must never be one stray click away while answers are missing.
function confirmClose(question){
  return new Promise(resolve => {
    askq.textContent = question;
    askyes.textContent = T.confirm_yes;
    askno.textContent = T.keep;
    ask.className = 'on';
    const shut = v => { ask.className = ''; askyes.onclick = askno.onclick = null;
                        resolve(v); };
    askyes.onclick = () => shut(true);
    askno.onclick = () => shut(false);
    askno.focus();          // the safe answer is the one already under the hand
  });
}
async function finish(){
  const left = undecided();
  if (left && !await confirmClose(T.confirm.replace('{n}', left))) return;
  await flushNote();        // a comment still inside the debounce is an answer
  done = true;              // the user gave — the server is about to stop
  const r = await fetch('/done', {method:'POST'});   // can still be saved, so
  overtext.innerHTML = `<h3>${D._waiting ? T.finish_waiting : T.closed}</h3>`
                     + `<p>${esc(await r.text())}</p>`;   // stop accepting answers
  over.className = 'on';
}
onkeydown = e => {
  if (done) return;
  // Cmd+F is find, Cmd+S is save, Cmd+D is bookmark — in a tool for reading
  // code in a browser they are certain to be pressed, and a bare `s` test
  // would answer the finding on the way past.
  if (e.metaKey || e.ctrlKey || e.altKey) return;
  // Inside the note every key is a letter of the note, including `s` and `1`.
  if (e.target === noteBox()){ if (e.key === 'Escape') e.target.blur(); return; }
  const k = e.key.toLowerCase();
  const move = d => { flushNote();
                      sel = Math.min(Math.max(sel + d, 0), D.findings.length - 1);
                      noteOpen = false; draw(); e.preventDefault(); };
  if (e.key === 'ArrowDown'){ move(1); }
  else if (e.key === 'ArrowUp'){ move(-1); }
  // One option answers to f. Numbering a list of one asks the reader to pick
  // one out of one, which is not a question.
  else if (k === 'f' && opts_(sel).length === 1){ setD(opts_(sel)[0].id); }
  else if (k >= '1' && k <= '9' && opts_(sel).length > 1){
    const o = opts_(sel)[+k - 1];
    if (o) setD(o.id);
  }
  else if (k === 's'){ setD('skip'); }
  else if (k === 'd'){ setD('discuss'); }
  else if (k === 'n'){ openNote(); e.preventDefault(); }
};
draw();
</script></body></html>"""


def payload(doc):
    out = dict(doc.doc, _waiting=WAITING, _t=doc.t)
    # `options` is resolved here, not in the page: the fallback for a finding
    # written before options existed has to read the same in both modes.
    out["findings"] = [dict(x, options=options_of(x),
                            **dict(zip(("refs", "missing"),
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
            if not 0 < size <= 8192:
                return self.send_error(400)
            try:
                change = json.loads(self.rfile.read(size))
                item = doc.find(change["id"])
                assert item is not None
                # There is no global list of valid answers any more: each
                # finding says what can be done about it.
                if "decision" in change:
                    v = change["decision"]
                    assert v is None or v in answers(item)
                if "note" in change:
                    assert isinstance(change["note"], str)
                    assert len(change["note"]) <= 4000
            except Exception:
                return self.send_error(400)
            if not doc.apply(change["id"], change):   # the page owns the toggle
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
