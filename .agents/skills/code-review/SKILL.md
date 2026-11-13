---
name: code-review
description: >-
  Find what is wrong in code — inconsistencies, potential problems, complications, replication — and
  give each finding options for the user to choose from. Use when asked to review code, a file or
  the working diff.
---

# Code Review Skill

Looks at code and reports what is wrong with it; whoever wrote the change answers each finding
against the code and the task, the user chooses what to do, and the skill carries out the choice. A
review finds something only when it is told what to hunt for, so it always runs the same four hunts.
The task loop has its own reviewer (TASK_LOOP.md); this skill is review on request.

## Instructions

### The four hunts, in this order

1. **Inconsistencies**: the same thing done two ways — two error conventions, a naming pattern
   broken in one place, a new function that ignores the module's idiom, a value checked in one
   caller and not another, a comment that no longer matches the code.
2. **Potential problems**: what breaks on input nobody tried — empty, maximum, negative, concurrent,
   repeated, out of order, partly failed; where an error is swallowed; what the second call does.
3. **Complications that hurt reading**: nesting that could be a guard clause, a name that lies, a
   parameter that matters only when another is set, a function doing two things, indirection with
   one implementation.
4. **Replication**: the same shape in several places; list every one, and ask whether the shape is
   still worth copying. Whether to refactor is the owner's call, not a verdict: the weight is what
   the copies cost as they stand.

### Procedure

1. **The target and its intent.** A named path or snippet; otherwise the working diff. If it is
   unclear, ask; never review the whole repository unasked. A diff or a named path carries its
   own intent; the review is also told what the change is for — its task, or the request it
   answers — and the decisions it rests on, quoted from where they are written: a reviewer that does
   not know them reports the task's own choices as defects. A whole feature or codebase needs exit
   criteria, a task or a plan, because without one a defect and unbuilt work look the same. With
   none, say so and offer two things: reconstruct the intent first (PLANNING_GUIDE.md, Steps 1-2),
   or run only hunts 1 and 4 and call the result an inventory, not findings. Unbuilt work is never a
   finding, and an `AGENTS.md` that lists features not built yet states intent, not a false claim.
2. **Read the surroundings** — the module's other functions, its conventions, how similar cases
   are handled — before judging.
3. **Run the four hunts**, then check against CLEAN_CODE.md and the language standard for what the
   hunts missed, including a reason, warning, unit, source or promise that only a test name or the
   requirements give (CLEAN_CODE.md, "Comments"). With `--strict`, look for style issues too;
   with `--hunt`, run only that hunt.
4. **Prove or mark each finding**: a concrete case where it goes wrong (input and wrong output, a
   sequence of calls), or, once what can be checked is checked, the plain word that it is unproven.
5. **Locate each finding**: `file:line`. A finding that cannot be located does not exist.

**Who reviews.** When this session wrote the change or any of it, a fix of an earlier round
included, steps 2-5 run in a fresh agent, on the model and effort of the `reviewer` role in
`.claude/agents.conf` where the project has one — not as the loop's `reviewer` agent, which keeps to
the loop's contract. It is given this skill, the target and what it is for (step 1), and never this
session's reasoning, its answers to earlier findings or a list of what it fixed: whoever wrote a
change reads it too kindly, and a reviewer told what was fixed looks there. Of this skill, that
agent does steps 2-5, How a finding is written and the Rules, and returns its findings without `fix`
and `options`, with what it checked and found clean and what it did not check; the rest is this
session's, the file included, and the Rules hold for both. One reviewer per round. When this session
did not write the change, it reviews it itself, and the user is the author; from the round after
this session fixed something in it, this session answers every finding as the author.

**The author's answer** (`author`). Before the user sees a finding, this session, as the author,
answers it as EXECUTION_GUIDE.md, "A review's findings", says, those it is least sure of first:
`says` is `real`, `wrong`, `other_task`, `unsettled`, or `below_bar` (After the user answers), and
`why` is the answer. Then it writes the `fix` or `options` in its own words. The reviewer's weight
and certainty stay as they are, so the user sees both. A finding that repeats one of an earlier
round of this review carries `again` and is answered again, the earlier answer in view.

### Where the findings go

By default, into the findings file, which the user triages in the tool. Into the reply only when
the user asks for that or says they are away from the machine; silence is not a reason to ask.

**The file.** Ask the tool where it goes; never build the path yourself:

```bash
CodingStandards/templates/review/lib/triage.py --where
```

It is outside the repository, so a review leaves nothing to commit. The file holds `project` (the
title), `root` (the project directory; every code link resolves against it), `lang` (`"ru"`,
`"en"`), `round` (1 for a new review), `earlier` (the findings of the earlier rounds of this review,
each with its `round`, `author`, `decision` and `note`; a new review leaves it out), and the
findings, most important first — what blocks first, minor last — with no groups or headings:

| field | content |
|---|---|
| `id` | a short name, unique in the file |
| `title` | the symptom, in the user's words |
| `where` | `path/File.kt:42`, repo-relative, several allowed; never copy code into the finding |
| `see` | what the user would observe — first |
| `why` | the mechanism, and whether it is proven |
| `if_left` | who meets it if it is left, how likely, what it costs; what is checked, what assumed |
| `weight` | `blocks`, `matters` or `minor` (How a finding is written) |
| `certainty` | 0 to 100: how sure the review is of that weight (How a finding is written) |
| `author` | `{"says", "why"}`: the author's answer — left out when the user is the author |
| `again` | the `id` in `earlier` of the finding this one repeats |
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
the target and the round, how many findings of each weight and how many of them the author answered
`wrong` or `below_bar`, what was checked and came out clean, what was not checked, and that the page
is open (or the absolute `--web` command). It never names or ranks a finding: an answer given in the
chat is not recorded in the file.

**The reply.** The same findings, numbered, each with its options, so the user can answer from a
phone with "1 — 2, 2 — s":

```
**1. [the symptom]** — [its weight], sure [its certainty] of 100[, again]
`file:line` — `quoted line`
[What the user would observe.] [The mechanism; proven or not.] [Who meets it if it is left, how
likely, what it costs; what is checked and what assumed.]
The author: [what the author says, and why; for a repeat, what it said before]
  1. [what happens if chosen] — [its price now and later]
  2. [the other thing that can be done] — [its price] ← advised
  s. Skip · d. Discuss
```

With one way forward, the fix is described above and the line is `f. [the act]`. End with what
was checked and clean and what was not checked. Unanswered findings are named, not let slide.

The run directory that the loop's `review.sh` writes under `.review/` is a different file in a
different schema; this skill does not triage it.

### How a finding is written

- Short plain sentences: first what the user sees, then why. No metaphors and no chains of
  subordinate clauses: a finding nobody reads is worth nothing.
- Each thing is called by its name in the code: `Dispatchers.Default`, `println`,
  `PdfRenderer.close()`, `sampleDir()`, `contentPadding`.
- A number comes with where it is from. "The cache holds 96 MB" is the question "why 96?", not a
  fact. "96 MB is the reader's share of the 500 MB peak in the requirements, which it shares with
  the browser" is a fact.
- What happens if it is left as is (`if_left`): who meets it — a user, an agent that follows the
  text, a reader of the README, nobody yet —, how likely that is and why, and what it costs them;
  then which of this was checked and which is only assumed. Follow the path to them before writing
  it: a line nobody on that path reaches is unlikely to hurt, however wrong it is. From that, its
  `weight`:
  - `blocks`: likely to hurt someone, and costly or hard to undo — a wrong result, lost data or
    information, a broken build, wrong work by someone who follows it. The change should not land
    until it is fixed.
  - `matters`: something is wrong now — a false statement, a check that cannot fail, a wrong result
    on some input — but few will meet it, or it is cheap to undo later.
  - `minor`: nothing goes wrong for anyone: only the form is off, or the harm waits for a change
    nobody plans.
- How sure the review is of that weight (`certainty`, 0 to 100) is a second judgement, apart from
  the weight: a `minor` can be certain and a `blocks` a guess. The weight is the best estimate, and
  a doubt about it lowers this number, never the weight; `if_left` names what lowered it, a doubt
  between two weights too. The number is read off what the weight rests on, so that it means the
  same in every project:
  - 90 to 100: all of it is checked — the code read along the whole path, a case worked out or run,
    a requirement quoted;
  - 60 to 89: a step of it is assumed, or more than one, but not the step the weight turns on;
  - 30 to 59: the step the weight turns on is assumed;
  - below 30: it rests on a pattern seen elsewhere, not on this code.

  A number below 90 names in `if_left` what is assumed, how likely someone meets it and what it
  costs them included; with nothing to name, it is 90 or more.

  What the review is not sure of, it checks further before it reports — reads on along the path,
  works out a case, runs a test. What the check refutes was not found, and the number is what is
  left after that.

### Options

Options follow EXECUTION_GUIDE.md, "Reporting to the user", and:
- `do` says what happens, in this finding's own words — an act, never a bucket such as "defer";
- "A, or else B" is two options;
- two or three options; fixing now, fixing later, writing it down, and deciding against it on
  purpose are all options; Skip and Discuss are always there and never among them;
- one way forward is an action, not a choice: describe it in `fix`, and the one option's `do` is
  the act itself ("Fix it", "Add it to git"); the tool shows it as one button, key `f`, beside
  Skip and Discuss;
- they include the move the user would make themselves: for a document under a password, the first
  obvious move is to ask for the password, and a list without that move is wrong, however many right
  options it has;
- `advised` marks your recommendation; nothing picks it by default;
- every `do`, `why` and `see` is written out in whole sentences, without metaphors and without
  transliterated jargon, so that someone who has not read the code knows what will happen and
  what it costs.

BAD: `{"do": "Note in T-002, decide there"}`

GOOD: `{"do": "Do not fix now; add to T-002 — to its description, that the launch screen takes the
app's theme; to its exit criteria, that a cold start in dark mode shows no white flash", "why":
"T-002 rewrites the launch and touches the same files, so it is done there at no extra cost; left
out, the flash is found again later."}`

### After the user answers

Carry out the option each finding was answered with, with what the user's comment adds, and
nothing else. Read every comment. Bring each Discuss back as a question. If carrying an option out
shows it is wrong, stop and ask.

An option that changes a task edits the task itself: its description gains what has to be built,
and its exit criteria gain a checkable line, written like the others. No date, no finding id, no
mention of the review.

**Another round** follows a round that fixed a `blocks` or `matters` finding; a fixed `minor` calls
for none. It runs the same way, on the target as it now is: first the answered findings move to
`earlier` and `round` goes up by one, then a fresh reviewer (Who reviews). The bar rises one step of
the certainty scale each round: none in the first, below 30 in the second, below 60 in the third,
below 90 from the fourth. Under the bar the author answers from what it already knows and checks
nothing further; what that leaves unsettled is `below_bar`, and its advised option is to write it
down, not to fix it. A `blocks` finding, or one whose `if_left` says it may be `blocks`, is never
`below_bar`: under the bar, the author checks it further, as in the first round. A round that fixed
nothing above `minor` is the last: say that the review is finished, and what was answered `wrong` or
`below_bar`, and why.

After the last round, write the commit message: one line, imperative, no period, plain text, saying
what the change does; unrelated changes are separate commits. It is committed as EXECUTION_GUIDE.md,
"Who writes to git", says. In the loop, `land.sh` writes it.

### Rules

- Report what you find, minor findings too, each with its weight and how sure you are of it; never
  decide what is worth reporting. A finding the author answers `wrong` or `below_bar` is shown to
  the user with that answer, never left out.
- An empty hunt is an answer; never invent findings.
- Say what you did not check.
- Keep proven and suspected apart.
- Change nothing on your own; findings are pointers for whoever owns the fix (EXECUTION_GUIDE.md, "A
  review's findings"). When they go to someone else to act on, say so with them.

## Allowed Prompts
- Read the target, its module, the standards, and other call sites
- Run tests or a snippet to prove a finding
- Write the findings file where `triage.py --where` says, and launch `triage.py`
- Start a fresh reviewer agent on a change this session wrote
- Edit project files (source, the tracker, the requirements) only to carry out the option the user
  chose

## Example Usage

```
/code-review src/services/UserService.kt
/code-review                                # the working diff
/code-review --strict                       # look for style issues too
/code-review --hunt inconsistencies         # one hunt only
/code-review --hunt replication             # only: what else looks like this?
```
