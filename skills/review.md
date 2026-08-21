# Code Review Skill

Review code for inconsistencies, replication, potential problems, and
complications that make it harder to read.

This is review as an activity: you ask, it reports, you decide what to do.

The task loop uses the same hunts through a machine-readable contract —
JSON findings, triage, a landing decision ([TASK_LOOP.md](../TASK_LOOP.md)).
That loop consumes review; it is not a version of it. Use this skill whenever
you want code looked at, loop or no loop.

## Instructions

### The brief matters more than the checklist

Asked to "review this code", a model reads it, finds it reasonable, and reports
that it is fine — especially code it just wrote. Nothing in that answer is
useful. The review only produces anything when it is told **what to hunt for**.

So the brief is always four specific hunts, in this order:

1. **Inconsistencies** — the same thing done two different ways. Two error
   paths with different conventions, a naming pattern broken in one place, a new
   function that ignores the module's existing idiom, a value validated in one
   caller and not the other, a comment describing behavior the code no longer
   has. Inconsistency is the cheapest defect class to find and the most reliable
   signal that something was written without looking around it.

2. **Potential problems** — what breaks under input nobody tried. Empty,
   maximum, negative, concurrent, repeated, out-of-order, partially failed.
   Where does an error get swallowed? What happens on the second call? What if
   this collection is empty? What if this runs twice at once?

3. **Complications that hurt reading** — where a reader has to hold too much in
   their head. Nesting that could be a guard clause, a name that lies, a
   parameter that only matters when another is set, a function doing two things
   with an "and" in its name, indirection with a single implementation.

4. **Replication** — the same shape in several places. List every instance.

   It cancels the bias in hunt 1: matching the surrounding code scores well
   there, and matching is how a bad early decision spreads. So ask the second
   question too — **is the pattern still worth matching?**

   Whether to refactor is the owner's scheduling call, not a review verdict.

### Procedure

1. **Establish the target, and what it was meant to do.** A path or snippet if
   given; otherwise the working diff. If the target is ambiguous, ask — do not
   review the whole repository.

   **A diff or a named path carries its own intent**: someone made this change,
   and you judge the change. **A whole codebase or a whole feature does not.**
   There you need exit criteria, a tracker entry, or a plan, because without one
   a defect and work that was never started are indistinguishable in the source.
   If neither exists, say so and stop. Two honest options: reconstruct the
   intent ([PLANNING_GUIDE.md](../PLANNING_GUIDE.md) Steps 1–2) and review
   afterwards, or run only the hunts that need no intent — inconsistency and
   replication — labelling the output *inventory*, not *findings*.

   **Never report unbuilt work as a defect.** "Does nothing when tapped", "this
   screen is a placeholder", "state with no UI" describe a plan, not code
   quality, and they bury the real findings. Read a `CLAUDE.md` listing features
   that do not exist as evidence of intent, not as a false claim.

2. **Read the surroundings before judging.** Inconsistency is invisible without
   the neighbours: the module's other functions, the existing error convention,
   how similar cases are handled elsewhere. This is where the real findings are.

3. **Run the four hunts.** Then check against the standards —
   [CLEAN_CODE.md](../CLEAN_CODE.md) and the language document — for anything
   the hunts did not already cover: naming, function size, single
   responsibility, dependency direction, error handling, dead code.

4. **Prove or downgrade every finding.** For each one, either give a concrete
   case where it goes wrong (input → wrong output, a sequence of calls, a
   failing scenario) or mark it explicitly as unproven. "This could be unsafe"
   without a case is a question, not a finding — say which one it is.

5. **Quote the code.** `file:line` plus the actual line. A finding that cannot
   be located does not exist.

### Output

```
## Review: [target]

### Inconsistencies
- [file:line] `quoted code` — differs from [where it's done the other way]. Why it matters.

### Replication
- [file:line] `quoted code` — same shape as [file:line], [file:line].

### Potential problems
- [file:line] `quoted code` — fails when [concrete case]. Proven | unproven.

### Complications
- [file:line] `quoted code` — [what the reader has to hold in their head].

### Nothing found in
- [areas you checked and found clean — so the reader knows what was covered]

### Summary
[What to look at first, and what can wait.]
```

### Where the output goes

Up to about five findings: in the reply, in the shape above — there the hunt
headings double as a coverage report, showing what was looked for. More than
that: a findings file, and the reply carries only the count, the worst one, and
the command to open it.

**This skill writes nothing inside the project.** Ask the tool where the file
goes rather than building the path yourself — it owns that rule, and a path
assembled twice is a path that eventually differs:

```bash
CodingStandards/templates/review/lib/triage.py --where
```

It answers under `~/.claude/projects/`, outside the repository, so an ad-hoc
review leaves nothing to commit, ignore or clean up, and no exported report.

**The loop is the other case.** `run.sh` writes a run directory under `.review/`
in the reviewer's own schema, because later steps read it
([TASK_LOOP.md](../TASK_LOOP.md)). That is the machine's bookkeeping, not a
review artifact, and the rule above does not reach it. The two files are
unrelated: nothing converts between them and the loop never calls `triage.py`.
Triaging a loop run by hand needs that conversion written first — it does not
exist yet.

The user triages it — never in chat, and never in a generated UI:

```bash
CodingStandards/templates/review/lib/triage.py          # terminal, two panes
CodingStandards/templates/review/lib/triage.py --web    # browser
```

Both modes read and write the same file, found by walking up from the current
directory to the nearest project that has one — so either runs from anywhere
inside it, a submodule included, and lands where `--where` said.

The file needs two things above the findings: `project`, the title, and `root`,
the project directory. Every code link resolves against `root`, so a file
without it is refused rather than guessed at.

**Launch it yourself when you can wait for the answer**, with
`TRIAGE_CALLER=claude` and the process in the background:

```bash
TRIAGE_CALLER=claude CodingStandards/templates/review/lib/triage.py --web
```

Then the page's button reads *Done → back to Claude*, pressing it ends the
process, and you are woken with the tally — no "come back and tell me" step.
Without that variable the tool knows there is no channel and says so instead of
promising one.

Schema is in the script's docstring; the fields that carry the judgment:

| field | what goes in it |
|-------|-----------------|
| `title` | the symptom, in the user's words |
| `where` | `path/File.kt:42`, several allowed — the tool opens the real file at that line, so never copy code into the finding. A name it cannot find in the project is shown as unresolved, so prefer repo-relative paths |
| `see` | what the user would observe — lead with this |
| `why` | the mechanism; `file:line` is evidence, not the explanation |
| `fix` | how to fix it, in prose — written when there is one way forward, and left out when the options carry it themselves |
| `options` | what can be done about it — see below. This is the finding's whole answer space, and writing it is the work |

### Options

Each option is `{"id", "do", "why"?, "advised"?}` and becomes one keyed row in
the tool. `do` says what happens when it is pressed, in this finding's own
words; `why` is the price or the consequence, one line; `advised` marks your
recommendation.

```json
"options": [
  {"id": "fix-now", "do": "Turn edge-to-edge on — enableEdgeToEdge() in MainActivity",
                    "why": "the shell is written in T-002 anyway, cheaper now"},
  {"id": "refuse",  "do": "Decide against it, write the reason into the decision log",
                    "why": "then it is settled and stops coming back every review"},
  {"id": "note-t002", "do": "Note on T-002, decide there",
                      "why": "both of the above are shell work that does not exist yet",
                      "advised": true}]
```

- **`do` is an act, never a category.** "Defer", "later", "wontfix" name a
  bucket; a month on, nobody can tell what was agreed to. "Note on T-002" they
  can.
- **"A, or else B" is two options.** This is the mistake that matters: one
  option holding a fork looks answered, and the file records a decision the user
  never made — the choice quietly comes back to you, and they never see it
  happen. If you write "or", split the row.
- **Fixing now and fixing later are both fixes.** So are "write it down and stop
  thinking about it" and "decide against it on purpose". None of these is a
  skip.
- **Two or three, never five.** They sit side by side and get read together, so
  every row costs attention.
- **One way forward is not a choice — it is an action.** Then `do` is the verb
  and nothing more, and the fix is described in `fix`, a paragraph shown above
  the buttons:

  ```json
  {"fix": "Кнопка «Назад» на экране файла не перехватывается, и система закрывает приложение. Вернуть обработчик в навигации, чтобы «Назад» уводил на список файлов, из которого файл был открыт.",
   "options": [{"id": "fix", "do": "Починить"}]}
  ```

  The tool then draws three plain buttons — Починить · Пропустить · Обсудить —
  with the explanation above them where it can be read, and the keys are `f`,
  `s`, `d`. There is no "1", because picking one out of one is not a choice. Do
  not push the description onto the button: it becomes an unreadable label, and
  the section that should have carried it is missing. With several options there
  is no `fix` section — each one carries its own words, and the keys are the
  numbers.
- **`advised` is a mark, not a default.** No key takes the recommendation
  blindly; the user still presses that option's own number.

### Write it as sentences, not as a headline

The option is the entire basis for the decision. Someone who has not read the
code has to be able to read it and know what will happen. Compressing it into
three words does not make it faster to read — it makes it unreadable, and then
the finding is worth nothing no matter how right it was.

BAD — words in a row that do not add up to a meaning:

```json
{"do": "Заметка в T-002, решать там",
 "why": "это работа по каркасу, которой ещё нет"}
```

What note, about what? Why there? What scaffolding — is someone building a
house? Every word has been replaced by a shorter one until nothing is left.

GOOD — the same decision, written out:

```json
{"do": "Не чинить сейчас, а записать в задачу T-002, что при запуске приложения экран мигает белым",
 "why": "T-002 всё равно переписывает запуск и трогает те же файлы, так что там это чинится заодно. Если не записать — забудется, и мигание найдут заново через полгода."}
```

- **Say what happens, in full.** "Записать в T-002, что экран мигает белым", not
  "заметка в T-002".
- **No metaphors for code.** No scaffolding, no plumbing, no skeletons. Name the
  thing that exists: the file, the screen, the task.
- **No jargon the language does not have.** Транслитерация английского термина —
  не русский язык, and a reader who has to decode the word is not deciding.
- **`why` is the price and the consequence**, in whole sentences: what it costs
  now, and what it costs later if this one is chosen.
- **Length is not the problem. Unreadability is.** Two full sentences that land
  beat six words that do not.

The same goes for `see` and `why` on the finding itself. The tool gives every
one of these room to be a paragraph.

Skip and Ask are always available and stand apart from the table — never put
them in `options`. Both mean nothing gets done about the finding, which is not
one of the things that can be done about it.

Set `lang` at the top of the file (`"ru"`, `"en"`) so the screen speaks the same
language the findings do.

There are no groups and no headings: the list is read top to bottom in the order
you write it, so put the finding that matters most first. A heading over a
section of findings names a bucket the reader never asked about, and the first
one gets read as the title of the whole review.

`decision` and `note` are the user's — leave `decision` null and omit `note`.
They press an option's number, or `s`, or `d`, and can add a comment to any
answer; the finish button closes the tool, and asks first if anything is still
unanswered. Then carry out the option each finding was answered with, and bring
each `discuss` back as a question. Read every comment: it is the only thing in
the file they wrote themselves, and it is there because the button did not say
everything they wanted to say.

### Then write the commit message

A review reshapes the change, so its one line can only be written after the
findings are answered. Imperative, no period, plain text — never `git commit -m`
([EXECUTION_GUIDE.md § Git is read-only](../EXECUTION_GUIDE.md#git-is-read-only)).
Say what the change does, not that it fixed five findings. Unrelated changes are
separate commits and separate lines. In the loop `land.sh` writes it from the task.

### Rules

- **Report what you find; never decide what is worth reporting.** A review that
  filters on its own judgment is grading its own work. Whether a whole review
  was worth reading is a call made after it, by the dispatcher and the user
  ([MAINTAINER_TRAINING.md](../MAINTAINER_TRAINING.md) § Two things to say about
  a review) — and it is never a standing ban on a class of finding.
- **Silence is a valid review.** An empty section is an answer. Do not
  manufacture findings to look thorough — invented findings are more expensive
  than missed ones, because they get fixed.
- **Say what you did not check.** Untested paths, code you could not reach,
  areas out of scope. A review with unstated gaps reads as a clean bill.
- **Separate proven from suspected**, always. Pattern-matched bug priors
  (off-by-one, null, boundary) look identical to real findings and are wrong
  most of the time.
- **Do not fix anything.** This skill reports. The fix is a separate decision by
  whoever owns the code.
- **The reader owns the fix.** Findings are pointers to look at, not change
  orders — state that in the output when handing it to someone who will act on
  it ([CLAUDE.md](../CLAUDE.md#handling-review-feedback)).

## Allowed Prompts

- Read the target and its surrounding module
- Search for related patterns, existing conventions, and other call sites
- Run tests or a snippet to prove a finding
- Read the project's standards documents
- Never edit source files

## Example Usage

```
/review src/services/UserService.kt
/review                              # the working diff
/review --strict                     # include minor style issues
/review --hunt inconsistencies       # one hunt only
/review --hunt replication           # only: what else looks like this?
```
