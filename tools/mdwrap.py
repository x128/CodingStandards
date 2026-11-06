#!/usr/bin/env python3
"""Line breaks of the Markdown in this repository: every paragraph is wrapped at 100 columns.

    python3 tools/mdwrap.py check [FILE...]   report what is wrong; exit 1 when anything is
    python3 tools/mdwrap.py fill  [FILE...]   fix it in the files

Without FILE, both take the Markdown files that differ from the last commit (HEAD), new files too,
except one whose text is still HEAD's (moved, or changed only in mode). A file renamed in the index
(git mv, git add) is compared with its text under the old name, so a move alone changes no line
breaks; so is a copy whose source changed in the same diff, the only copy git pairs.

A line that ends early, while the next word would still fit, reads as a deliberate break: a list,
a new thought. So:
- text not in HEAD word for word (a new paragraph, or one whose words changed) is filled to 100;
  a paragraph that was even in HEAD is refilled only from the change on, and may stop with a line
  up to 8 columns short, so that a small edit does not ripple through the whole paragraph;
- a committed paragraph keeps its line breaks, unless a line is longer than 100, a line ends far
  earlier than its other lines, or it is an item of a list another item of which was filled;
- a word never starts a line when Markdown would read it as a block (-, +, *, #, >, |, 1.), when it
  is a dash, or when it is a back-reference like "(a),"; a label like "(b)" never ends a line;
- links and code spans are not split (a code span longer than a line is); a quoted text with
  spaces at its edges or two in a row is never split, and runs of spaces inside a line are kept as
  they are, so exact texts in quotes stay exact;
- short lines written one under another (three or more, all under 60 columns) stay as they are;
- a line that starts with a bold label (**Fix:**) or with an id (R01, S12, C3) starts its own
  paragraph, as written; ids written one under another get a hanging indent;
- front matter, code blocks, tables, headings, HTML, and paragraphs laid out with the filler
  character U+3164 are never touched.

fill writes a file only when its text is the same apart from line breaks and indentation, and when
it renders to the same HTML. The rendering is compared with markdown-it: install it with
`npm install -g markdown-it`, or set MARKDOWN_IT to the folder of the package.
"""
import argparse
import difflib
import json
import os
import re
import subprocess
import sys
from pathlib import Path

WIDTH = 100
SLACK = 8
QUOTE_LIMIT = 90  # the longest quoted text looked at; see keep_quote

FENCE = re.compile(r"^\s*(```|~~~)")
ITEM = re.compile(r"^(\s*(?:[-*+]|\d+[.)])(?: \[[ xX]\])?\s+)")
QUOTE = re.compile(r"^(\s*>\s?)")
STARTS_BLOCK = re.compile(r"^(-|\+|\*|#{1,6}|>.*|\|.*|=+|\d+[.)]|```.*|~~~.*|—|–)$")
LABEL = re.compile(r"^\([a-z0-9]\)$")
BACK_REFERENCE = re.compile(r"^\([a-z0-9]\)[,.;:]$")
BOLD_LABEL = re.compile(r"^\s*(> ?)?\s*\*\*[A-Z][^*]{0,40}:\*\*")
ID_LINE = re.compile(r"^([A-Z]\d{1,3}) ")
LINK = re.compile(r"\[[^\]\n]*\]\([^)\s]*\)")
DASH_START = re.compile(r"^\s*(> ?)?\s*[—–] ")
FILLER = "ㅤ"


# ---------------------------------------------------------------- reading the repository

def git(top, *args, can_fail=False):
    """The output of a git command run at the top of the repository (where the tool runs, for top
    None). A failure stops the tool with git's message, unless the caller takes it as an answer:
    None."""
    at = ["-C", str(top)] if top else []
    r = subprocess.run(["git", "--no-optional-locks", *at, *args], capture_output=True,
                       encoding="utf8")
    if r.returncode != 0 and not can_fail:
        sys.exit(f"mdwrap: git {args[0]} failed: {r.stderr.strip()}")
    return r.stdout if r.returncode == 0 else None


def top_level():
    out = git(None, "rev-parse", "--show-toplevel", can_fail=True)
    if out is None:
        sys.exit("mdwrap: run it inside a git repository")
    return Path(out.strip())


def head_text(top, path):
    """The file's text in HEAD, "" for a path HEAD does not have."""
    return git(top, "show", f"HEAD:{path}", can_fail=True) or ""


def diff_base(top):
    """HEAD, or the empty tree before the first commit, when every file is new."""
    if git(top, "rev-parse", "--verify", "--quiet", "HEAD", can_fail=True) is not None:
        return "HEAD"
    return git(top, "hash-object", "-t", "tree", os.devnull).strip()


def changed_files(top):
    """The Markdown files that differ from HEAD, new files too, each with the path to read it from
    HEAD by: the old path of a renamed file, or of the source of a copy git paired; its own else."""
    files = {}
    entries = iter(git(top, "diff", diff_base(top), "-M", "-C", "-z", "--name-status",
                       "--diff-filter=d", "--").split("\0"))
    for status in entries:
        if not status:
            break
        in_head = next(entries)
        now = next(entries) if status[0] in "RC" else in_head
        if now.endswith(".md"):
            files[now] = in_head
    for f in git(top, "ls-files", "--others", "--exclude-standard", "-z", "--", "*.md").split("\0"):
        if f:
            files.setdefault(f, f)
    return files


# ---------------------------------------------------------------- the shape of a paragraph

def tokens(text):
    """Words: split at single spaces outside code spans. A run of spaces stays inside its word."""
    out, word, in_code = [], "", False
    for i, ch in enumerate(text):
        if ch == "`":
            in_code = not in_code
        lone = (ch == " " and not in_code and i > 0 and text[i - 1] != " "
                and i + 1 < len(text) and text[i + 1] != " ")
        if lone:
            out.append(word)
            word = ""
        else:
            word += ch
    if word:
        out.append(word)
    return [w for w in out if w]


def words(text, width=WIDTH):
    """tokens(), with links and quoted texts kept whole while they fit on a line."""
    def protect(m):
        s = m.group(0)
        return s.replace(" ", "\x00") if len(s) <= width - 10 else s
    text = LINK.sub(protect, text)
    text = re.sub(r'"[^"\n]{1,%d}"' % QUOTE_LIMIT, keep_quote, text)
    return [t.replace("\x00", " ") for t in tokens(text)]


def keep_quote(m):
    """A quoted text whose spaces are part of it, at its edges or two in a row ("   ", " ALPS "),
    is never split: a line break there would change the exact text. Other quotes break like words:
    keeping them whole would leave a short line, which reads as a deliberate break."""
    s = m.group(0)
    exact = s[1:2] == " " or s[-2:-1] == " " or "  " in s
    return s.replace(" ", "\x00") if exact else s


def split_long_code(ws, width):
    """A code span too long for a line may break at its single spaces (a line break inside a code
    span reads as a space)."""
    out = []
    for w in ws:
        if "`" in w and len(w) > width - 10 and " " in w:
            out.extend(p for p in re.split(r"(?<! ) (?! )", w) if p)
        else:
            out.append(w)
    return out


def no_line_start(word):
    return STARTS_BLOCK.match(word) or BACK_REFERENCE.match(word)


def skipped(lines):
    skip = [False] * len(lines)
    if lines and lines[0] == "---":
        end = next((i for i in range(1, len(lines)) if lines[i] == "---"), 0)
        for i in range(end + 1):
            skip[i] = True
    fence = None
    for i, line in enumerate(lines):
        m = FENCE.match(line)
        if fence:
            skip[i] = True
            if m and m.group(1) == fence:
                fence = None
        elif m:
            skip[i] = True
            fence = m.group(1)
    return skip


def unquoted(line):
    return QUOTE.sub("", line, count=1) if QUOTE.match(line) else line


def structural(line):
    s = unquoted(line).lstrip()
    return (not s or s.startswith("#") or s.startswith("|") or s.startswith("<")
            or re.match(r"^\s*(---+|\*\*\*+|___+)\s*$", line))


def new_item(line, first):
    """Whether a line with a list marker starts a new item, as CommonMark reads it: an ordered
    marker other than 1 cannot interrupt a paragraph, unless it is a sibling or outer item."""
    body = unquoted(line)
    m = ITEM.match(body)
    if not m:
        return False
    number = re.match(r"^(\d+)[.)]", m.group(1).strip())
    if not number or number.group(1) == "1":
        return True
    indent = len(body) - len(body.lstrip())
    fbody = unquoted(first)
    findent = len(fbody) - len(fbody.lstrip())
    return indent <= findent if ITEM.match(fbody) else indent < findent


def blocks(lines, skip):
    """Paragraphs as (start, end) line ranges: a plain paragraph, a list item, a quote paragraph."""
    i, out = 0, []
    while i < len(lines):
        if skip[i] or structural(lines[i]):
            i += 1
            continue
        j = i + 1
        while (j < len(lines) and not skip[j] and not structural(lines[j])
               and not new_item(lines[j], lines[i]) and not BOLD_LABEL.match(lines[j])
               and not ID_LINE.match(lines[j])
               and not lines[j - 1].endswith("  ") and not lines[j - 1].endswith("\\")
               and bool(QUOTE.match(lines[j])) == bool(QUOTE.match(lines[i]))):
            j += 1
        out.append((i, j))
        i = j
    return out


def shape(block, hanging=False):
    """The quote prefix, the first line's indent, the other lines' indent, each line's content."""
    quote = QUOTE.match(block[0])
    q = quote.group(1) if quote else ""
    body = [b[len(QUOTE.match(b).group(1)):] if QUOTE.match(b) else b for b in block]
    item = ITEM.match(body[0])
    if item:
        first = item.group(1)
        rest = " " * len(first)
        contents = [body[0][len(first):]] + body[1:]
    else:
        first = re.match(r"^(\s*)", body[0]).group(1)
        ident = ID_LINE.match(body[0].lstrip())
        rest = first + " " * (len(ident.group(1)) + 1) if hanging and ident else first
        contents = body
    return q, first, rest, [c.strip() for c in contents]


def rows(block, hanging=False):
    return [words(c) for c in shape(block, hanging)[3]]


def norm(block):
    return " ".join(" ".join(unquoted(b).split()) for b in block).strip()


# ---------------------------------------------------------------- filling

def fill(ws, width, first, rest):
    out, current = [], []
    for word in ws:
        indent = first if not out else rest
        if current and len(indent + " ".join(current + [word])) > width:
            carried = []
            while no_line_start(word if not carried else carried[0]) and len(current) > 1:
                carried.insert(0, current.pop())
            while LABEL.match(current[-1]) and len(current) > 1:
                carried.insert(0, current.pop())
            out.append(indent + " ".join(current))
            current = carried
        current.append(word)
    if current:
        out.append((first if not out else rest) + " ".join(current))
    return out


def hard_break(block):
    return block[-1].endswith("  ") and not block[-1].endswith("\\")


def refill_block(block, width, hanging=False):
    q, first, rest, contents = shape(block, hanging)
    ws = split_long_code(words(" ".join(contents), width), width)
    lines = [q + l for l in fill(ws, width - len(q), first, rest)]
    if hard_break(block):
        lines[-1] += "  "
    return lines


def ends_early(line, nxt, width, slack):
    """The line could take words of the next one, without leaving a dash or a block marker to
    start it, and is more than `slack` short of the width."""
    if not nxt or len(line.rstrip()) >= width - slack:
        return False
    used, k = len(line.rstrip()), 0
    while k < len(nxt) and used + 1 + len(nxt[k]) <= width:
        used += 1 + len(nxt[k])
        k += 1
    while 0 < k < len(nxt) and no_line_start(nxt[k]):
        k -= 1
    return k > 0


def even(block, width, slack, hanging=False):
    r = rows(block, hanging)
    return (all(len(l) <= width for l in block)
            and not any(ends_early(block[k], r[k + 1], width, slack) for k in range(len(block) - 1)))


def crooked(block, width, slack, hanging=False):
    """A line ends far earlier than the paragraph's other lines, though words of the next would
    fit: a break that reads as deliberate, whatever width the paragraph was wrapped at."""
    q, first, _, contents = shape(block, hanging)
    r = [words(c) for c in contents]
    if len(block) >= 3 and all(len(l) < 60 for l in block):
        return False  # short lines one under another: laid out line by line on purpose
    if len(q) + len(first) + len(" ".join(contents)) <= width and any(len(l) < 60 for l in block[:-1]):
        return True
    w = max(len(l) for l in block)
    return any(ends_early(block[k], r[k + 1], w, slack)
               or (ends_early(block[k], r[k + 1], width, 0) and len(block[k]) < 0.6 * w)
               for k in range(len(block) - 1)) or any(DASH_START.match(l) for l in block[1:])


def minimal_refill(block, head_block, width, slack, hanging=False):
    """Refill an edited paragraph from its first changed line and stop as soon as the rest is
    HEAD's lines again. None when HEAD's paragraph is uneven or shaped differently."""
    q, first, rest, contents = shape(block, hanging)
    hq, hfirst, hrest, hcontents = shape(head_block, hanging)
    if (q, first, rest) != (hq, hfirst, hrest) or not even(head_block, width, slack, hanging):
        return None
    p = 0
    while p < min(len(block), len(head_block)) and block[p] == head_block[p]:
        p += 1
    if p == len(block) == len(head_block):
        return block
    start = p
    if 0 < p < len(block) and ends_early(block[p - 1], words(contents[p]), width, slack):
        start = p - 1
    while start > 0 and "".join(block[:start]).count("`") % 2:
        start -= 1
    ws = words(" ".join(contents[start:]))
    suffixes = {}
    for j in range(1, len(head_block)):
        suffixes.setdefault(tuple(words(" ".join(hcontents[j:]))), j)
    room = width - len(q)
    done, cur, i = [], [], 0
    while i < len(ws):
        w = ws[i]
        indent = first if start + len(done) == 0 else rest
        if cur:
            line = indent + " ".join(cur)
            too_long = len(indent + " ".join(cur + [w])) > room
            j = suffixes.get(tuple(ws[i:]))
            if j is not None and (too_long or len(q + line) >= width - slack):
                return block[:start] + [q + l for l in done + [line]] + head_block[j:]
            if too_long:
                carried = []
                while no_line_start(w if not carried else carried[0]) and len(cur) > 1:
                    carried.insert(0, cur.pop())
                while LABEL.match(cur[-1]) and len(cur) > 1:
                    carried.insert(0, cur.pop())
                done.append(indent + " ".join(cur))
                cur = carried
        cur.append(w)
        i += 1
    if cur:
        done.append((first if start + len(done) == 0 else rest) + " ".join(cur))
    out = block[:start] + [q + l for l in done]
    if hard_break(block):
        out[-1] += "  "
    return out


def counterpart(block, head_blocks):
    text, best, score = norm(block), None, 0.6
    for hb in head_blocks:
        r = difflib.SequenceMatcher(None, text, norm(hb), autojunk=False).ratio()
        if r > score:
            best, score = hb, r
    return best


def lists(lines, spans, skip):
    """Spans of one list: sibling items of the same indent and kind, and what is indented under them."""
    groups, current, key = [], [], None
    for a, b in spans:
        first = unquoted(lines[a])
        m = ITEM.match(first)
        indent = len(first) - len(first.lstrip())
        kind = (QUOTE.match(lines[a]) is not None, indent, m.group(1).strip()[-1]) if m else None
        between = range(current[-1][1], a) if current else []
        interrupted = any(not skip[k] and lines[k].strip()
                          and lines[k].lstrip()[:1] in ("#", "|") for k in between)
        if current and not interrupted and (kind == key or indent > key[1]):
            current.append((a, b))
            continue
        if current:
            groups.append(current)
        current, key = ([(a, b)], kind) if kind else ([], None)
    if current:
        groups.append(current)
    return groups


def hanging_ids(lines, a, b):
    """Ids written one under another (R01, R02, …) get a hanging indent."""
    if not ID_LINE.match(lines[a]):
        return False
    before = lines[a - 1] if a > 0 else ""
    after = lines[b] if b < len(lines) else ""
    return bool(ID_LINE.match(before) or ID_LINE.match(after))


def refill_text(text, head, width=WIDTH, slack=SLACK):
    """The text with its paragraphs filled by the rules above, and what was filled, and why."""
    hlines = head.split("\n")
    head_blocks = [hlines[a:b] for a, b in blocks(hlines, skipped(hlines))]
    committed = {norm(hb) for hb in head_blocks}
    lines = text.split("\n")
    skip = skipped(lines)
    spans = blocks(lines, skip)
    hang = {s: hanging_ids(lines, *s) for s in spans}
    reason = {}
    for a, b in spans:
        block = lines[a:b]
        if any(FILLER in l for l in block):
            continue
        if norm(block) not in committed:
            reason[(a, b)] = "new"
        elif max(len(l) for l in block) > width:
            reason[(a, b)] = "longer than the width"
        elif len(block) > 1 and crooked(block, width, slack, hang[(a, b)]):
            reason[(a, b)] = "broken early"
    for group in lists(lines, spans, skip):
        if any(s in reason for s in group):
            for s in group:
                block = lines[s[0]:s[1]]
                if s not in reason and not any(FILLER in l for l in block) \
                        and not even(block, width, slack, hang[s]):
                    reason[s] = "same list"
    out, last, filled = [], 0, []
    for a, b in spans:
        block = lines[a:b]
        out.extend(lines[last:a])
        why = reason.get((a, b))
        new = block
        if why:
            new = None
            if why == "new":
                hb = counterpart(block, head_blocks)
                if hb is not None:
                    new = minimal_refill(block, hb, width, slack, hang[(a, b)])
                    if new is not None and max(len(l) for l in new) > width:
                        new = None
                why = "edited" if new is not None else why
            if new is None:
                new = refill_block(block, width, hang[(a, b)])
            if new != block:
                filled.append((a + 1, block, new, why))
        out.extend(new)
        last = b
    out.extend(lines[last:])
    return "\n".join(out), filled


# ---------------------------------------------------------------- checks

def flat(text):
    """The text without its line breaks and indentation: what must not change."""
    return re.sub(r"[ \t]*\n[ \t>]*", "\n", text).replace("\n", " ")


RENDER_JS = r"""
const path = process.env.MARKDOWN_IT || 'markdown-it';
let MarkdownIt;
try { MarkdownIt = require(path); } catch (e) {
  try { MarkdownIt = require(require('child_process').execSync('npm root -g').toString().trim() + '/markdown-it'); }
  catch (e2) { process.stderr.write('markdown-it not found'); process.exit(3); }
}
const md = new MarkdownIt({ html: true });
const texts = JSON.parse(require('fs').readFileSync(0, 'utf8'));
process.stdout.write(JSON.stringify(texts.map(t => {
  if (t.startsWith('---\n')) { const e = t.indexOf('\n---\n', 4); if (e > 0) t = t.slice(e + 5); }
  return md.render(t).split(/\s+/).join(' ');
})));
"""


def rendered(*texts):
    r = subprocess.run(["node", "-e", RENDER_JS], input=json.dumps(list(texts)),
                       capture_output=True, text=True, env=os.environ)
    if r.returncode != 0:
        sys.exit("mdwrap: the rendering cannot be compared without markdown-it: "
                 "npm install -g markdown-it, or set MARKDOWN_IT to the folder of the package")
    return json.loads(r.stdout)


def problems(text, head, width=WIDTH):
    """What check reports in one file: line and why."""
    found = []
    lines = text.split("\n")
    skip = skipped(lines)
    for i, l in enumerate(lines):
        if not skip[i] and len(l) > width and " " in l.strip() and not unquoted(l).lstrip().startswith("|"):
            found.append((i + 1, f"longer than {width}"))
    hlines = head.split("\n")
    committed = {norm(hlines[a:b]) for a, b in blocks(hlines, skipped(hlines))}
    for a, b in blocks(lines, skip):
        block = lines[a:b]
        if norm(block) in committed or any(FILLER in l for l in block):
            continue
        for k, l in enumerate(block):
            ws = l.split()
            if k > 0 and DASH_START.match(l):
                found.append((a + k + 1, "starts with a dash"))
            if k < len(block) - 1 and ws and LABEL.match(ws[-1]):
                found.append((a + k + 1, f"ends with the label {ws[-1]}, apart from its value"))
            if k > 0 and ws and BACK_REFERENCE.match(ws[0]):
                found.append((a + k + 1, f"starts with the back-reference {ws[0]}"))
            if k < len(block) - 1 and re.search(r"\[[^\]]*$", l):
                found.append((a + k + 1, "a link is split here"))
    _, filled = refill_text(text, head, width)
    for line, before, after, why in filled:
        found.append((line, f"paragraph to refill ({why}): fill would make it {len(after)} lines"))
    return sorted(set(found))


# ---------------------------------------------------------------- commands

def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("command", choices=["check", "fill"])
    ap.add_argument("files", nargs="*")
    ap.add_argument("--width", type=int, default=WIDTH)
    args = ap.parse_args()
    top = top_level()
    changed = changed_files(top)
    files = args.files or [top / f for f in sorted(changed)]
    bad = 0
    for f in files:
        path = Path(f).resolve()
        if not path.is_relative_to(top):
            sys.exit(f"mdwrap: {f} is outside the repository")
        rel = path.relative_to(top).as_posix()
        text = path.read_text(encoding="utf8")
        head = head_text(top, changed.get(rel, rel))
        same_text_as_head = text == head
        if same_text_as_head and not args.files:
            continue
        if args.command == "check":
            for line, why in problems(text, head, args.width):
                print(f"{rel}:{line}: {why}")
                bad += 1
            continue
        new, filled = refill_text(text, head, args.width)
        if new == text:
            continue
        if flat(new) != flat(text):
            print(f"{rel}: not written: the text would change, not only its line breaks")
            bad += 1
            continue
        before, after = rendered(text, new)
        if before != after:
            print(f"{rel}: not written: it would render differently")
            bad += 1
            continue
        path.write_text(new, encoding="utf8")
        print(f"{rel}: {len(filled)} paragraphs filled")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
