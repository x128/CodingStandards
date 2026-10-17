# Self-Improve Skill

Improve these standards by evidence. Agents build and refactor real projects under the
standards; measurements show what each rule makes them do; the human sets the direction and
corrects; every change of a rule is measured before and after. The state of this work is in
[EVALUATION.md](../EVALUATION.md); the tools are in
[templates/self-improve/](../templates/self-improve/).

## Instructions

When invoked with no argument, continue from `EVALUATION.md`. When invoked with a direction,
start an iteration on it. Directions also come from real projects: after each refactoring,
`/refactor` writes what the rules did to the code into `EVALUATION.md`, "Open directions", with
the project and the quoted lines.

### 1. Read the state

- `EVALUATION.md`: the human's decisions in force, what was measured so far with its numbers,
  the open directions, and how much each kind of run cost.
- The standards as they are now.
- The work folder: ask the human for a folder outside every git repository, unless they have set
  `$SELF_IMPROVE_WORK`. Raw results of earlier iterations may be on another machine; what was learned
  from them is in `EVALUATION.md`. When a direction needs projects that are not in the work folder,
  offer two options: the human copies that folder over, or the iteration starts from a new project.

### 2. Pick one direction and write its hypothesis

One direction per iteration: the one the human named, or the open direction of `EVALUATION.md`
with the strongest evidence. Before anything runs, write down:
- the lines of the standards that change, old and new;
- what should get better, and the number that will show it;
- what must not get worse, and the number that will show that;
- which result would mean the change failed.

Who decides:
- **The human decides the direction**: a new rule, a removed rule, a change that goes against a
  decision of theirs, anything they would want to see first. Give it in two or three plain
  sentences with the evidence for it and the cost. The human does not need every detail; they
  need enough to say "go", "not now" or "go this other way".
- **You decide the rest.** When a change follows from the evidence and from a decision the human
  already made, and you expect it to work, make it in the next iteration and bring the result:
  the numbers before and after, or why it did not work and what to try instead.
- Fix obvious defects without asking: an example that does not compile, two files that say
  different things, a broken link. Of two files that disagree, the one that agrees with the
  human's decisions is right; if neither does, it is a question of direction. A fix passes gates
  1 to 3 of step 4; the readers of gate 4 are needed only when the meaning of a rule changes.

### 3. Say the cost and wait

Before any run of agents, say what will run, why, and how many tokens it will cost, with the
source of the estimate (the costs in `EVALUATION.md`). Give the upper bound too: runs so far cost
up to 1.6 times the first estimate. When the estimate is above 1 million tokens, wait for the
human's yes; below it, say it and go on. A yes covers the run it was given for, also when the run has to be continued after
a usage limit: wait for the limit to reset and say what is left. Never start agents instead of
answering a question.

### 4. Change the text and pass the edit gates

First copy the standards as they are into the work folder: this copy is arm A. Then change the
standards in the working tree. Shorten rather than add: a rule that replaces another is not
longer than it unless the evidence asks for more. Before any project sees the change:
1. **Nothing is lost.** `/loss-check` on the arm A copy against the working tree, run by an agent
   that did not write the change. Every
   removed line — prose, a table row, a comment inside an example — has its meaning in the new
   text, or it is put back.
2. **Examples are real code.** Every changed Kotlin or Swift example compiles: Kotlin with the
   compiler, Swift with `swiftc -typecheck`, against stubs of what the example leaves out. The
   language-agnostic pseudocode of CLEAN_CODE.md is complete in the same way: no placeholder that
   is not code, such as `[imports]`, and every name it calls says what it does; a body left out as
   `{ ... }` is allowed.
3. **One meaning across files.** A fresh agent reads every file that names the changed thing and
   lists what contradicts it. The same rule says the same thing everywhere.
4. **Readers.** Three fresh agents, with nothing but the changed text, apply it to five to ten
   concrete cases. If they answer differently, the text is not clear yet. A small change of
   wording can break a text that passed, so the final text is checked again as it will be
   committed.
5. **Skills are run, not read.** A changed skill is run on a small project made for it, and a
   second agent compares what it did with what its name and its text say.

### 5. Measure before and after

All projects live in the work folder. The human's own projects are never touched; a copy of one
is used only when the human asks for it. For a direction that came from a refactoring of the
human's project, offer that: both arms start from a copy of the project as it was before that
round.

**The project.** By default a new one each iteration, so the rules are not tuned to one codebase:
another domain, about 2 500 lines of main code, business rules with numbers, failures of storage
and of a network service, a background job, a few screens. A spec agent writes what the builders
get (`REQUIREMENTS.md`, `docs/LIBRARIES.md`, `CLAUDE.md`) and, apart from it, the hidden
material: `ACCEPTANCE.md` (about 25 scenarios with exact texts and numbers), `RULES.md` (about 30
business rules to look for in the code), `CHANGES.md` (two or three changes of business rules),
and a script that computes the expected numbers. A second agent computes the numbers on its own
and lists every ambiguity; fix them before anything is built.
`templates/self-improve/example/` is a finished spec of this kind, with a small platform library
in `templates/self-improve/platform/`.

**Setup.** `tools/setup.sh <work folder>` checks the jars of `tools/jars.txt`, builds the
platform library and copies the tools into the work folder; `tools/make-project.sh` makes each
project folder with its own copy of the standards of its arm (the standards folder is its third
argument); `tools/refresh-standards.sh` puts a fresh copy into a project that already exists,
before a refactoring round. That copy leaves out what belongs to the evaluation — this skill, `EVALUATION.md`,
`templates/self-improve/` and every index line that names them — and keeps everything a real
project gets, `/loss-check` and `/reflect` included. Projects get neutral names, `p1`, `p2` and
so on, in a folder of the iteration (the tools find projects by these names); which arm each one
is, is written in a file outside the project folders.

**The arms.** The standards before the change (A) against the standards after it (B).
- Build: a planner, then fresh engineers, one epic per sitting (`workflows/build.js`), under A
  and under B. Two projects per arm when the difference is expected to be small.
- Refactor: a reviewer lists where the code departs from the standards, fresh engineers work
  through the list (`workflows/refactor.js`). Repeat for several rounds on the same projects;
  quality must hold or improve from round to round. Before measuring, check that the reviewer's
  list cites a changed line; if none does, the change was not tested: say so and stop. Both arms
  get the same number of rounds from the same start; one more round alone makes the code better.

**The measures** (`workflows/measure.js`, `workflows/loss.js`, scripts in `tools/`):
- behaviour: testers write the hidden scenarios as tests through the screens; rerun their tests
  yourself (`run-extra.sh`). When later code changes below the screens, adapt their tests only
  in how they build objects and fakes, and prove with `adapted_checks.py` that no check changed;
- where the rules are: the rule locator puts each rule of `RULES.md` in a file, line and layer
  and lists its copies; every quote is checked by `check_locator.py`;
- lint: comments and CRAP score (`lint-project.sh`); counts (`count_code.py`);
- nothing lost: every comment removed by a refactoring is traced (`removed_comments.py`,
  `loss_parts.py`, `workflows/loss.js`, `loss_report.py`); above about 300, a sample of every
  k-th one. `trace_summary.py` counts where each meaning is now: the main code, the tests or the
  documents. To compare two arms, trace the same comments with the same prompt in both;
- maintenance: a fresh agent makes each change of `CHANGES.md` on version A and on version B;
  count the files and layers it touched and whether the scenarios still pass (`change_report.py`);
  a scenario of the changed rule fails on both by design, any other failure is a regression;
- blind judges: two per pair, each version read first once, only `src/`; they say which version
  they would maintain and what one tells that the other does not. Judges are the same model as
  the authors, so a verdict of judges alone decides nothing: when judges and the other measures
  disagree, the other measures decide, and what the judges say one version tells and the other
  does not is a list of things to check, not a verdict;
- isolation: `scan_transcripts.py` lists every builder or refactorer that read hidden material,
  another project or a folder of the human.

If no measure shows the gain the hypothesis promised, revert the change, unless it makes the text
shorter and nothing gets worse. Save each result in the work folder as soon as a run ends, and copy each project before the next
run touches it. Never delete results. After a cut-off, where each project stopped is in its own
`TASK_TRACKER.md` or `REFACTORING.md`.

### 6. Reflect

Run `/reflect` in a fresh agent with the hypothesis, the numbers and the human's words. It says
what happened against what was expected, the cause in the text of the standards, and the next
candidates.

### 7. Report and record

- **To the human**: what changed, what the numbers say and where each number comes from, and
  what you propose next. Plain short sentences, names from the code. At most one question, with
  concrete options; one of them is the move the human would make themselves.
- **Keep or revert** the change by the result. A rule that measurements on one application
  brought in stays a trial, marked so in `EVALUATION.md`, until a second, different application
  confirms it; if it does not, it is taken out. [MAINTAINER_TRAINING.md](../MAINTAINER_TRAINING.md),
  "A rule for this project, or a rule for every project", asks the same of a rule that comes from
  one host project.
- **Committing is the human's.** Say which files to commit and give the message, with the
  numbers; do not run git yourself.
- **Rewrite `EVALUATION.md`** as the state is now, not as a diary: git keeps the history.

## Feedback from the human

The human corrects; you work out the change.
1. Restate the correction in one sentence and show one concrete case before and after. If it can
   be read two ways, ask, with both readings as the options.
2. Carry it out without losing information. "Code explains itself" means that what a comment
   says becomes a name, a type or a check in the code, pinned by a test (work to do goes to the
   tracker, history to the commit message, as CLEAN_CODE.md, "Comments", says), never that the
   comment is deleted. Before
   removing a convention, ask whether it is one: `// Arrange`, `// Act`, `// Assert` and
   `// Given`, `// When`, `// Then` are.
3. Find the cause, not the consequence: the line of the file that led to the mistake.
4. Write the correction into the file that is read when the same situation comes up again
   ([MAINTAINER_TRAINING.md](../MAINTAINER_TRAINING.md)), never into assistant memory.
5. Check that it worked: run the same situation again.

## What went wrong before, and the rule that came of it

| What happened | The rule now |
|---|---|
| Asked for self-explaining code, the editor deleted comments in the examples of the standards, and their meaning was lost | Nothing is deleted before its meaning is where CLEAN_CODE.md, "Comments", puts it; `/loss-check` by another agent |
| Examples had placeholders such as `[imports]` and did not compile | Examples are real code and are compiled |
| The `/document` skill deleted comments, the opposite of its name | A skill is run before it goes in, and its name says what it does |
| A limit of 200 lines per class made agents split 31 test classes into 134 (test code from 16.1 to 25.1 thousand lines) | No limits in lines; CRAP score from the literature; every rule is measured by what agents do with it |
| "Its own result type for each use case" made agents copy one status check into five use cases | The rule locator found it; the rule "a refusal is declared with its rule" took the copies from 10 to 0 in one project and from 7 to 0 in another, in one round |
| Comments removed by refactoring: 0 of 905 traced lost, yet 9 of 10 judges preferred the commented code and all 10 found it easier to read | Open in `EVALUATION.md` |
| A final text was put together from checked paragraphs and never checked as a whole | The final text is checked as it will be committed |
| A definition was made up, or averaged from several authors | Each source on its own, with chapter and page; no definition that no source gives |
| The human was asked to write the wording | Propose wordings yourself; the human corrects |
| Reports of many pages, numbers without their source | Dialogue, one thing at a time, every number with its source |
| Words that exist only in the assistant's habits | Names from the code, or a plain explanation in the same sentence |
| Agents were started without a word, instead of an answer | Say what runs, why and what it costs first |
| A resumed run started finished work again (three projects got an unplanned extra round) | Resuming replays only an unchanged prefix of calls; with parallel branches that prefix breaks. Start a new run of only the unfinished parts (`skipPlan`, `skipReview`, `firstSitting` in the workflows) |
| A compiler downloaded a dependency by itself | Ask before any download, with file, source and size; ask before the first run of a tool that downloads on its own, and if its size cannot be known in advance, say so and ask anyway |
| Obvious defects were left with "not touched without your word" | Fix obvious defects; ask only about direction |
| A rule about comments was measured on code that had none; no reviewer acted on it, and one more round of refactoring made the code better by itself | Before measuring, the reviewer's list must cite the changed line; both arms get the same start and the same number of rounds |
| A removal with a variable in its path was stopped by the safety check of the shell | Scripts write `rm -rf "${DIR:?}"`, so an empty variable stops them |

## Sources

The standards rest on books and articles, and the set grows. The books, the papers and the notes
of what was read in them are in the folder `CodingStandards-Sources`, which is not part of this
repository; ask the human where it is. A new book goes there as `Author - Title (year)`, its
notes into `Notes`, and each gets a row in `INDEX.md`. When a question has no source there, say
which book would answer it, and ask the human for every book you need at once.
Read each source on its own, give chapter and page, and have a second reader check each claim
against the page. Do not merge several authors into one definition. Record in
`EVALUATION.md` which sources each part of the standards rests on.

## Allowed Prompts
- Read the standards, `EVALUATION.md` and the work folder
- Change the standards in the working tree, `EVALUATION.md` and the work folder
- Run agents and workflows after saying their cost; above 1 million tokens only after the human's yes
- Run compilers, build, test and measuring scripts in the work folder
- Never run git; never touch the human's projects; never download without asking

## Example Usage

```
/self-improve
/self-improve reasons and warnings become names in the main code
```
