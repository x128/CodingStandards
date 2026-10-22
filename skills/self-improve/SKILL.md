---
description: Change the coding standards and their skills by evidence, measuring each change before and after. Use when a standard or a skill needs to change.
---

# Self-Improve Skill

Improves these standards by evidence. Agents build and refactor projects under the standards;
measurements show what a rule makes them do; every change of a rule is measured before and after. The human sets the direction, corrects, and confirms the cost. It
needs a direction — from the human, or from what a refactoring or a review found about the rules —
and a work folder outside every repository; it gives back the changed standards with the evidence
for each change. Its tools are in `templates/self-improve/`.

## Instructions

### 1. The state

- The work folder: the human names it, or it is `$SELF_IMPROVE_WORK`. The rules themselves are the
  text of the standards; the state of the work lives in the folder, not in the repository: the
  human's decisions about the standards and who made each, what was measured with its numbers,
  what runs cost, the open directions, and which sources each part of the standards rests on.
  Keep it current, and update it before every long run so another session can go on.
- The standards as they are now.
- Results or projects that are on another machine: offer to copy the folder over, or start from a
  new project.

### 2. One direction, and its hypothesis

One direction per iteration: the one the human named, or the open direction with the strongest
evidence. What a refactoring or a review found about the rules goes into the open directions with
the project, the round and the quoted lines; when the direction is there already, it gains one
more project. Before anything runs, write down the lines that change (old and new), what should get
better and the number that will show it, what must not get worse and its number, and which result
means the change failed.

- **The human decides** a new rule, a removed rule, anything against a decision of theirs, and
  anything they would want to see first.
  Put it in two or three plain sentences with the evidence and the cost, so they can say "go",
  "not now" or "go this other way". Propose the wording yourself; the human corrects.
- **You decide** a change that follows from the evidence and from what the human already decided:
  make it, and bring back the numbers before and after. A default you chose where the standards
  needed one answer you may change on evidence; a rule the human decided goes in once it passes
  the edit gates, and a measurement does not revert it.
- **Fix obvious defects without asking**: an example that does not compile, two files that say
  different things, a broken link. Of two files that disagree, the one that agrees with the
  human's decisions is right; if neither does, it is a question of direction. Such a fix passes
  edit gates 1 to 3; gate 4 only when the meaning of a rule changes.

### 3. The cost

Before any run of agents, say what will run, why, and what it will cost in tokens, with the
source of the estimate and an upper bound (runs have cost up to 1.6 times their estimate). Above 1
million tokens, wait for the human's yes. A yes covers its run, also when the run continues after
a usage limit. Never start agents instead of answering a question.

### 4. The change and its edit gates

Put in every change that is waiting first, so a run is not paid twice, and pass gates 1 to 3 on
it against a copy made before it. Then copy the standards into the work folder (arm A), and make
the measured change. While a refactoring of a project reads these standards through its
submodule, change a copy in the work folder, pass the gates there, and pass gate 3 again on the
working tree when it is brought in. Shorten rather than add. Every assignment that compares two
versions names `diff -ru`. Before any project sees the change:

1. **Nothing is lost:** `/loss-check` on arm A against the changed text, by an agent that did not
   write the change.
2. **Examples are real code:** a changed Kotlin example compiles with the compiler, a Swift one
   with `swiftc -typecheck`, against stubs; the pseudocode of CLEAN_CODE.md has no placeholder
   that is not code (`{ ... }` for a left-out body is allowed), and every name it calls says what
   it does.
3. **One meaning:** a fresh agent reads every file that names the changed thing and lists what
   contradicts it.
4. **Readers:** three fresh agents, given nothing but the changed text, apply it to five to ten
   concrete cases; if they answer differently, the text is not clear yet. The final text is
   checked as it will be committed.
5. **A changed skill is run**, on a small project made for it, and a second agent compares what it
   did with what its name and its text say.
6. **The loop's scripts:** after a change to `run.sh`, `land.sh`, the schemas or the decision
   rules, `templates/review/lib/selftest.sh` passes.

### 5. Measure before and after

All projects live in the work folder; the human's projects are never touched, and a copy of one
is used only when the human asks. On such a copy, the tools of `templates/self-improve/` do not
work (they build Kotlin on the JVM): use the project's own build and tests, `/loss-check` and
blind judges.

**The project.** A new one each iteration, so the rules are not tuned to one codebase: another
domain, about 2 500 lines of main code, business rules with numbers, failures of storage and of a
network service, a background job, a few screens. A spec agent writes what the builders get
(`REQUIREMENTS.md`, `docs/LIBRARIES.md`, `CLAUDE.md`) and, apart from it, the hidden material:
`ACCEPTANCE.md` (about 25 scenarios with exact texts and numbers), `RULES.md` (about 30 business
rules), `CHANGES.md` (two or three changes of rules), and a script that computes the expected
numbers. A second agent computes them on its own and lists every ambiguity, which is fixed before
anything is built. `templates/self-improve/example/` is such a spec, with a small platform library
in `templates/self-improve/platform/`.

**Setup.** `tools/setup.sh <work folder>` checks the jars of `tools/jars.txt`, builds the platform
library and copies the tools; `tools/make-project.sh` makes each project folder with its own copy
of the standards of its arm (the standards folder is its third argument);
`tools/refresh-standards.sh` puts a fresh copy into an existing project before a refactoring. The
copy leaves out this skill, `templates/self-improve/`, and every line and section that names them;
if the name is left anywhere, the script fails. Projects are `p1`, `p2`, ... in a folder of the
iteration inside the work folder, where `scan_transcripts.py` finds them; which arm each is, is
written outside the project folders. Scripts remove folders with `rm -rf "${DIR:?}"`.

**The arms:** the standards before the change (A) against after it (B), from the same start and
with the same number of rounds.
- Build: a planner, then fresh engineers, one epic per sitting (`workflows/build.js`); two
  projects per arm when the difference is expected to be small.
- Refactor: a reviewer lists where the code departs from the standards, fresh engineers work
  through the list (`workflows/refactor.js`), round after round; quality must hold or improve from
  round to round. Before measuring, check that the
  reviewer's list cites a changed line; if none does, the change was not tested: say so and stop.
- The assignments add only these rules of the measurement:
  - every one: work only in the project folder, ignore notes of other projects, no network, no
    git, nobody can be asked, `REQUIREMENTS.md` is not edited;
  - a build: 6 to 9 epics of comparable size, one per sitting, the build and the lint pass after
    each; a plan that turns out wrong is corrected with a note in its Decisions Log;
  - a refactoring: it keeps the behaviour, the entry points of screens and background jobs, the
    public functions of the ViewModels with their state and event types, and what the tests
    check; the build passes after every item and the lint at the end; what would wait for the
    human is an item, or is marked "not done", with its reason, except a decision of the plan
    the change alters or one the standards ask to record (into the Decisions Log) and work still
    to do (a task in the tracker and the plan); what a removed comment said that belongs in a
    commit message goes into the item; an item no rule asks for, or that made the code worse, is
    undone; a test removed or loosened is named; where an item's way breaks the rule it cites,
    the rule wins; notes on the standards go under their own heading; a sitting stops before an
    item too large for what is left of it;
  - a change of `CHANGES.md`: only the code, its tests and the Decisions Log.
- A run cut off is not resumed when its branches ran in parallel: read where each project stopped
  from its `TASK_TRACKER.md`, or its `REFACTORING.md` in a refactoring, and start a new run of only the unfinished parts (`skipPlan`, `skipReview`,
  `firstSitting` in the workflows).

**The measures** (`workflows/measure.js`, `workflows/loss.js`, scripts in `tools/`):
- behaviour: testers write the hidden scenarios as tests through the screens; rerun them yourself
  (`run-extra.sh`); when code below the screens changes later, adapt the tests only in how they
  build objects and fakes, and prove with `adapted_checks.py` that no check changed;
- where the rules are: the rule locator puts each rule of `RULES.md` at a file, line and layer and
  lists its copies; `check_locator.py` checks every quote;
- lint and size: `lint-project.sh` (comments, CRAP), `count_code.py`;
- nothing lost: every comment a refactoring removed is traced (`removed_comments.py`,
  `loss_parts.py`, `workflows/loss.js`, `loss_report.py`; above about 300, a sample);
  `trace_summary.py` counts where each meaning is now; both arms get the same comments and the
  same prompt;
- maintenance: a fresh agent makes each change of `CHANGES.md` on A and on B; `change_report.py`
  counts files and layers touched and lists the failing scenarios; any but the changed rule's own
  is a regression;
- blind judges: two per pair, each version read first once, only `src/`; they are the same model
  as the authors, so they decide nothing alone, and what they say one version tells and the other
  does not is a list of things to check;
- isolation: `scan_transcripts.py` lists every agent that read hidden material, another project or
  a folder of the human.

If no measure shows the promised gain, revert the change, unless it makes the text shorter and
nothing gets worse. Save each result as soon as a run ends, copy each project before the next run
touches it, and never delete results.

### 6. Reflect

Run `/reflect` in a fresh agent with the hypothesis, the numbers and the human's words.

### 7. Report and record

- To the human, as EXECUTION_GUIDE.md, "Reporting to the user", says: what changed, what the
  numbers say and where each comes from, and what you propose next. The options of a question
  include the move the human would make themselves.
- Keep or revert by the result. A rule brought in by measurements on one application stays a
  trial until a second, different application confirms it, is taken out if it does not, and
  stays a trial while the second is mixed.
- Git as the human decided for this repository; say which files to commit and give the message.
- Update the state in the work folder: as it is now, not as a diary.

## Corrections of the human

Restate the correction in one sentence with one case before and after; if it reads two ways,
ask. Write the human's words and what is open into the state at once. Carry it out without losing
information. Find the line that led to the mistake, and fix it in the file that is read when the
same situation comes up again (MAINTAINER_TRAINING.md says which), through the edit gates of
section 4, once the human agrees with its wording. Then run the same situation again to see that
it worked.

## Sources

The books, papers and notes the standards rest on are in the folder `CodingStandards-Sources`,
outside this repository; ask the human where it is. A new book goes there as
`Author - Title (year)`, its notes into `Notes`, each with a row in its `INDEX.md`; when a question
has no source there, ask the human for every book you need at once. Read each source on its own,
by meaning and not by the word, give chapter and page, follow the author's own reasoning, and have
a second reader check each claim against the page. Authors may name one thing differently; check
what each says it does before taking two words for one thing. Never merge authors into one
definition, never write a definition no source gives, and never call a book irrelevant before
reading it.

## Allowed Prompts
- Read the standards and the work folder
- Change the standards and the work folder
- Run agents and workflows after saying their cost; above 1 million tokens, only after the human's yes
- Run compilers, builds, tests and measuring scripts in the work folder; compare folders with `diff -ru`
- Never touch the human's projects; never download without naming the file, its source and its
  size, and asking; ask also before the first run of a tool that downloads on its own, and when
  the size cannot be known, say so

## Example Usage

```
/self-improve
/self-improve reasons and warnings become names in the main code
```
