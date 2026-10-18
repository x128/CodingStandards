---
description: Find what is wrong in code — inconsistencies, potential problems, complications, replication — and give each finding options for the user to choose from. Use when asked to review code, a file or the working diff.
---

# Code Review Skill

Looks at code and reports what is wrong with it, each finding with the options for what to do;
the user chooses, and the skill carries out the choice. A review finds something only when it is
told what to hunt for, so it always runs the same four hunts. The task loop has its own reviewer
(TASK_LOOP.md); this skill is review on request.

## Instructions

### The four hunts, in this order

1. **Inconsistencies**: the same thing done two ways — two error conventions, a naming pattern
   broken in one place, a new function that ignores the module's idiom, a value checked in one
   caller and not another, a comment that no longer matches the code.
2. **Potential problems**: what breaks on input nobody tried — empty, maximum, negative,
   concurrent, repeated, out of order, partly failed; where an error is swallowed; what the
   second call does.
3. **Complications that hurt reading**: nesting that could be a guard clause, a name that lies,
   a parameter that matters only when another is set, a function doing two things, indirection
   with one implementation.
4. **Replication**: the same shape in several places; list every one, and ask whether the shape
   is still worth copying. Whether to refactor is the owner's call, not a verdict.

### Procedure

1. **The target and its intent.** A named path or snippet; otherwise the working diff. If it is
   unclear, ask; never review the whole repository unasked. A diff or a named path carries its
   own intent. A whole feature or codebase does not: it needs exit criteria, a task or a plan,
   because without one a defect and unbuilt work look the same. With none, say so and offer two
   things: reconstruct the intent first (PLANNING_GUIDE.md, Steps 1-2), or run only hunts 1 and 4
   and call the result an inventory, not findings. Unbuilt work is never a finding, and a
   `CLAUDE.md` that lists features not built yet states intent, not a false claim.
2. **Read the surroundings** — the module's other functions, its conventions, how similar cases
   are handled — before judging.
3. **Run the four hunts**, then check against CLEAN_CODE.md and the language standard for what
   the hunts missed, including a reason, warning, unit, source or promise that only a test name
   or the plan gives (CLEAN_CODE.md, "Comments"). With `--strict`, include minor style issues;
   with `--hunt`, run only that hunt.
4. **Prove or mark each finding**: a concrete case where it goes wrong (input and wrong output, a
   sequence of calls), or the plain word that it is unproven.
5. **Locate each finding**: `file:line`. A finding that cannot be located does not exist.

### Where the findings go

By default, into the findings file, which the user triages in the tool. Into the reply only when
the user asks for that or says they are away from the machine; silence is not a reason to ask.

**The file.** Ask the tool where it goes; never build the path yourself:

```bash
CodingStandards/templates/review/lib/triage.py --where
```

It is outside the repository, so a review leaves nothing to commit. The file holds `project`
(the title), `root` (the project directory; every code link resolves against it), `lang`
(`"ru"`, `"en"`), and the findings, most important first, with no groups or headings:

| field | content |
|---|---|
| `id` | a short name, unique in the file |
| `title` | the symptom, in the user's words |
| `where` | `path/File.kt:42`, repo-relative, several allowed; never copy code into the finding |
| `see` | what the user would observe — first |
| `why` | the mechanism, and whether it is proven |
| `fix` | how to fix it, in prose — only when there is one way forward |
| `options` | what can be done: `{"id", "do", "why"?, "advised"?}` each |

`decision` stays null and `note` is left out: they are the user's. The full schema is in the
script's docstring.

Launch the tool yourself, in the background, so you are woken when the user is done:

```bash
TRIAGE_CALLER=claude CodingStandards/templates/review/lib/triage.py --web
```

The terminal mode (the same command without `--web`) needs a real terminal; the terminal pane of
the Claude app passes it no keys. The reply is then a short note: what is needed from the user,
the target and the number of findings, what was checked and came out clean, what was not checked,
and that the page is open (or the absolute `--web` command). It never names or ranks a finding: an
answer given in the chat is not recorded in the file.

**The reply.** The same findings, numbered, each with its options, so the user can answer from a
phone with "1 — 2, 2 — s":

```
**1. [the symptom]**
`file:line` — `quoted line`
[What the user would observe.] [The mechanism; proven or not.]
  1. [what happens if chosen] — [its price now and later]
  2. [the other thing that can be done] — [its price] ← advised
  s. Skip · d. Discuss
```

With one way forward, the fix is described above and the line is `f. [the act]`. End with what
was checked and clean and what was not checked. Unanswered findings are named, not let slide.

The run directory that the loop's `run.sh` writes under `.review/` is a different file in a
different schema; this skill does not triage it.

### How a finding is written

- Short plain sentences: first what the user sees, then why. No metaphors and no chains of
  subordinate clauses: a finding nobody reads is worth nothing.
- Each thing is called by its name in the code: `Dispatchers.Default`, `println`,
  `PdfRenderer.close()`, `sampleDir()`, `contentPadding`. An invented generalization — «вычислительный
  пул», «журнал», «шасси», «замер», «инструментальный тест», «расхождение в данных» — is unknown to
  the reader, and the finding is not read at all. A word that is in neither the code nor the tasks does not appear,
  unless the same sentence explains it.
- A number comes with where it is from. "The cache holds 96 MB" is the question "why 96?", not a
  fact. "96 MB is the reader's share of the 500 MB peak in §13 of the plan, which it shares with
  the browser" is a fact.
- The options include the move the user would make themselves. For a document under a password,
  the first obvious move is to ask for the password. A list without that move is wrong, however
  many right options it has.

### Options

Options follow EXECUTION_GUIDE.md, "Reporting to the user", and:
- `do` says what happens, in this finding's own words — an act, never a bucket such as "defer";
- "A, or else B" is two options;
- two or three options; fixing now, fixing later, writing it down, and deciding against it on
  purpose are all options; Skip and Discuss are always there and never among them;
- one way forward is an action, not a choice: describe it in `fix`, and the one option's `do` is
  the act itself ("Fix it", "Add it to git"); the tool shows it as one button, key `f`, beside
  Skip and Discuss;
- `advised` marks your recommendation; nothing picks it by default;
- every `do`, `why` and `see` is written out in whole sentences, without metaphors and without
  transliterated jargon, so that someone who has not read the code knows what will happen and
  what it costs.

BAD: `{"do": "Note in T-002, decide there"}`
GOOD: `{"do": "Do not fix now; add to T-002 — to its description, that the launch screen takes the app's theme; to its exit criteria, that a cold start in dark mode shows no white flash", "why": "T-002 rewrites the launch and touches the same files, so it is done there at no extra cost; left out, the flash is found again later."}`

### After the user answers

Carry out the option each finding was answered with, with what the user's comment adds, and
nothing else. Read every comment. Bring each Discuss back as a question. If carrying an option out
shows it is wrong, stop and ask.

An option that changes a task edits the task itself: its description gains what has to be built,
and its exit criteria gain a checkable line, written like the others. No date, no finding id, no
mention of the review.

Then write the commit message: one line, imperative, no period, plain text, saying what the
change does; unrelated changes are separate commits. It is committed as EXECUTION_GUIDE.md, "Who
writes to git", says. In the loop, `land.sh` writes it.

### Rules

- Report what you find; never decide what is worth reporting.
- An empty hunt is an answer; never invent findings.
- Say what you did not check.
- Keep proven and suspected apart.
- Change nothing on your own; findings are pointers for whoever owns the fix (the standards'
  CLAUDE.md, "Handling Review Feedback"). When they go to someone else to act on, say so with them.

## Allowed Prompts
- Read the target, its module, the standards, and other call sites
- Run tests or a snippet to prove a finding
- Write the findings file where `triage.py --where` says, and launch `triage.py`
- Edit project files (source, the tracker, the plan's Decisions Log) only to carry out the option
  the user chose

## Example Usage

```
/code-review src/services/UserService.kt
/code-review                                # the working diff
/code-review --strict                       # include minor style issues
/code-review --hunt inconsistencies         # one hunt only
/code-review --hunt replication             # only: what else looks like this?
```
