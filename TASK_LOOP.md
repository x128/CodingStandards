# Task Loop

> A machine that runs task work end to end: `executor → reviewer → maintainer`,
> over deterministic gates.
>
> Language-agnostic — everything stack-specific lives in `.review/gates.sh`.
>
> See `MAINTAINER_TRAINING.md` for teaching the maintainer your judgment.

---

## What this is built on

Three things exist without this loop and are unchanged by it:

| Ingredient | What it is | Defined in |
|-----------|------------|-----------|
| **Execution rules** | What doing a task means: one at a time, exit criteria are the definition of done, who decides a task is finished, who owns git | `EXECUTION_GUIDE.md` |
| **Review** | Reading code for defects, inconsistency, replication | `.agents/skills/code-review/SKILL.md`, `CLEAN_CODE.md`, the language standards |
| **Gates** | The project's own build, test, format, lint, and architecture commands | `.review/gates.sh` |

You can execute tasks and review code with none of this document. People do it
by hand every day, and `/code-review` works on its own.

**The loop is not an automated version of any of them.** It is a machine that
runs them in a fixed order with roles that cannot mark their own work, and it
adds two things that do not otherwise exist:

- a **landing contract** — the conditions under which a commit may happen without you (`land.sh`),
  and how far it then goes (`publish.sh`), where the requirement "Who writes to git" lets the loop
  commit
- an **advance decision** — whether the loop waits for you after a finished task, or goes on with
  one line saying what it finished (`land.conf`)

Those two are the whole reason this document exists. Everything else here is
plumbing that makes them safe enough to use.

**What it does not change.** The execution rules hold inside the loop exactly as they do outside it:
one task at a time, exit criteria are the definition of done, and *you* decide a task is genuinely
finished. Where the requirement "Who writes to git" lets the loop commit, it moves **mechanical**
acts — committing and, as far as it says, pushing, opening a pull request and merging it — behind a
contract you enable and can revoke. It never moves the judgment.

Remove the loop and nothing is lost except the automation: the rules, the review,
and the gates are all still there, and you run them yourself.

---

## Table of Contents

1. [The Loop](#the-loop)
2. [Layer 0: Deterministic Gates](#layer-0-deterministic-gates)
3. [Executor](#executor)
4. [Reviewer](#reviewer)
5. [Maintainer](#maintainer)
6. [Landing](#landing)
7. [Advancing](#advancing)
8. [Project Setup](#project-setup)
9. [Failure Modes](#failure-modes)
10. [Summary Checklist](#summary-checklist)

---

## The Loop

Three roles. The third one owns the tree.

```
   ┌──────────────────────────────────────────────────────┐
   │ task from the tracker                                │
   └────────────────────────┬─────────────────────────────┘
                            ▼
   ┌─────────────┐   ┌─────────────┐   ┌──────────────────┐
   │ EXECUTOR    │──►│ GATES       │──►│ REVIEWER         │
   │ writes code │   │ build/test/ │   │ diff + touched   │
   │             │   │ lint/arch   │   │ deps → findings  │
   └─────▲───────┘   └─────────────┘   └────────┬─────────┘
         │                                      ▼
         │ accepted findings      ┌───────────────────────────┐
         └────────────────────────┤ MAINTAINER                │
        (until review converges)  │ 1. triage findings        │
                                  │ 2. another round or done? │
                                  │ 3. land, then advance     │
                                  └──────┬──────────────┬─────┘
                                         │              │
                                    land.sh          escalate
                                    (commit, publish)   │
                                         │              ▼
                                         ▼          answered
                                    next task    (/maintain, step 7)
```

| Role | Decides | Power |
|------|---------|-------|
| Executor | How to write it | Edits files inside the task's scope, and the end-to-end harness |
| Reviewer | What is broken | None — emits JSON, touches nothing |
| Maintainer | What counts, whether another round is needed, what lands | Lands through two narrow scripts as far as the requirement "Who writes to git" lets the loop go, and writes on its pull request through a third; otherwise none |

The maintainer is the role this pipeline exists for. It is not a second reviewer: it never hunts for
defects. It filters the reviewer's output, decides whether another round is needed, lands the task
where the requirement "Who writes to git" lets the loop commit, and moves to the next one once the
task is accepted and committed.

**At the pull request levels**, `LANDING=pr` and `merge`, the loop works as a developer does. The
work and the project's own checks (`gates.sh`) come before the commit; then `land.sh` commits on
`task/<id>`, and `publish.sh` pushes and opens the pull request. The key checks run on the pull
request: `review.sh` reviews its change, the end-to-end tests run on it, `/qa` checks it, and each
posts its result there through `pr-post.sh` — the gates, the end-to-end runs, the review and `/qa`
as commit statuses, the findings with their verdicts as an inline review, the answer to each finding
as a reply, the `/qa` report as a comment, each run's statistics in its summary. What a person
writes on the pull request is read and answered like a finding. A fix is a new commit on the branch,
through `land.sh`. Then `publish.sh --merge` checks the merge contract and merges with squash, one
commit per task in main; at `pr`, `publish.sh --check` says the pull request is ready for you to
merge. At `off`, `on` and `push` the loop runs as drawn: the review comes before the commit, and the
loop opens no pull request.

### Where the reliability comes from

Not from the maintainer being smart. From three things underneath it:

1. **Layer 0** — the compiler, tests, linter, and architecture rules are ground
   truth. Any finding contradicting a green gate loses.
2. **A landing contract** — the maintainer does not judge whether the work is
   good enough to commit. It checks conditions, all of which are mechanical
   (see [Landing](#landing)). Its discretion is narrow by construction.
3. **A human at the task boundary** — you review tasks, not commits. Early on
   you see every task; over time you may decide which kinds you no longer need
   to see (see [Advancing](#advancing)).

### Role separation

**Each role works in its own fresh session.** The reviewer never sees the
executor's reasoning, and the maintainer sees the findings and the gates, not
the reviewer's reasoning. A session that judges work it argued for in its own
context approves too much.

**The pull request is for neither the reviewer nor the executor.** It holds the verdicts of the
triage and the answers to findings, which neither may see: the reviewer `review.sh` starts by
default has no `gh`, the `reviewer` agent is told never to read the pull request, and no prompt of
the reviewer or the executor names it.

**Models.** `.claude/agents.conf` names the model and effort of each role: executor, reviewer,
maintainer, `/qa` and helper. `review.sh` and every skill that starts agents take the role's model
from it and say it before they start. `review.sh` starts the reviewer and the maintainer in a
process of their own, with no session to inherit from: a role it starts gets the model named, `opus`
when the file names none; `inherit` is for an agent a session starts, which then runs on the
session's model.

---

## Layer 0: Deterministic Gates

Build this first. A project without Layer 0 does not get a maintainer — it gets
an argument between two chatbots with commit access.

### The five gate slots

Every language fills the same five slots. Nothing else about the pipeline
changes between projects.

| Slot | Question it answers | Blocking |
|------|--------------------|----------|
| `build` | Does it compile / typecheck? | Yes |
| `test` | Do the tests pass? | Yes |
| `format` | Is it formatted canonically? | Auto-fix, then yes |
| `lint` | Any known-bad patterns? | Yes for errors, no for warnings |
| `arch` | Do the architecture rules hold? | Yes |

The `arch` slot is the one teams skip and the one that pays for the pipeline.
Architecture rules written as executable tests ("classes named `*UseCase` live
in the `usecase` package", "the domain layer imports nothing from the data
layer") turn architectural review from opinion into a gate. See
`ARCHITECTURE.md` for the rules worth encoding.

### Wiring a new language

Fill in `.review/gates.sh`. Reference commands:

| Stack | build | test | format | lint | arch |
|-------|-------|------|--------|------|------|
| Kotlin / KMP | `./gradlew :composeApp:compileKotlinMetadata :composeApp:linkDebugFrameworkIosSimulatorArm64 :androidApp:assembleDebug` | `./gradlew :composeApp:allTests :androidApp:testDebugUnitTest` | `ktlintCheck` | `detekt` | Konsist tests |
| Swift | `swift build` / `xcodebuild` | `swift test` | `swift-format lint` | `SwiftLint` | custom test target |
| TypeScript | `tsc --noEmit` | `vitest run` | `prettier --check` | `eslint` | `dependency-cruiser` |
| Python | `mypy` / `pyright` | `pytest` | `ruff format --check` | `ruff check` | `import-linter` |
| Rust | `cargo check --all-targets` | `cargo test` | `cargo fmt --check` | `cargo clippy -D warnings` | module-boundary tests |
| Go | `go build ./...` | `go test ./...` | `test -z "$(gofmt -l .)"` | `golangci-lint run` | `go-arch-lint` |
| C# | `dotnet build` | `dotnet test` | `dotnet format --verify-no-changes` | Roslyn analyzers | NetArchTest |

Every command there **checks** and never rewrites. A `--format` or `--write` mode in the `format`
slot breaks the rule above and stops the run right after the gates, before a single token is spent
on review; and a command that exits 0 on failure — bare `gofmt -l` is the classic — is a gate that
never fires at all. So is a test command on a project that has no tests: `./gradlew allTests`,
`pytest`, `go test ./...` all exit 0 with nothing to run.

A gate that looks at the change — formatting of the changed files, comments added — measures it from
`$REVIEW_BASE`. At the pull request levels it is the merge base of the pull request, in `land.sh`
and in `review.sh`: there the work is committed before the review, and from `HEAD` the gate would
check nothing and post green. With `review.sh --base <ref>` it is the merge base with `<ref>`;
otherwise `HEAD`. A gate may write one summary line — test counts, lint counts — to the file
`$GATE_SUMMARY` names; it is shown with its result.

**Checklist when starting a project in a new language:**

- [ ] A tool for each of the five slots. If none exists for `arch`, write the rules as ordinary unit
      tests — every language can do this.
- [ ] Every gate runs from one command and exits non-zero on failure.
- [ ] Fast enough to run per task, and again at landing (target: under 2 minutes). Scope `test` to
      affected modules if the full suite is slow, and run the full suite in CI.
- [ ] One definition, three call sites: local, hook, CI.
- [ ] Tool choices recorded in the Tech Stack of the requirements.

**Gates run before the reviewer and again at landing** — at the pull request levels at landing
first, before the commit, then before the reviewer on the pull request. A red build means the
reviewer never runs — send the executor back with the compiler output. The end-to-end tests are a
check beside the review, not a condition of it: after the review `review.sh` runs them through
`.review/e2e.sh` on every platform the tree ships and counts them in its JUnit reports. Whatever
they come to, the review is made and stays, and the run's exit code and its last lines say both.
Red, the run ends as on a red gate. With no test that ran, or none that a case of `qa/test-cases.md`
names once the file has a case, it has no working harness; only a tree with no harness file at all
stops there before the review. A harness that ends with exit 75 says the device or a tool was not
there: nothing is known of the code, the run exits 75, and the next run on the same work repeats
only the tests and counts no review. The task lands only once they pass (condition 3).

**Gates must not modify the tree.** Use check modes (`--check`, `lint`), not
formatters that rewrite files. `review.sh` compares the fingerprint immediately
after the gates and stops there, naming the gate as the cause; landing re-checks
it again before committing. A mutating gate cannot slip through, and it is
reported as what it is rather than as the reviewer having written to the tree.

**A gate runner that cannot run is not a red gate.** A non-executable
`gates.sh`, or one that writes no usable `gates.json`, is a pipeline error —
both scripts say so and stop. Reporting it as "gates red" with an empty failure
list would send the executor to fix code that may be perfectly fine.

**The reviewed diff includes untracked files.** `git diff` alone hides them,
and a whole new source file would otherwise be committed with no review at all —
exactly the "add a module" task, not an edge case.

---

## Executor

Writes code for **one task**.

- **Narrow scope beats clever orchestration.** A tightly scoped task with an explicit file boundary
  costs an order of magnitude less than a broad one, and the landing contract can check it.
- **Declares its scope.** The task's allowed paths come from the tracker; the executor works inside
  them and in the end-to-end harness. Landing verifies the diff stayed there.
- **Never reviews its own diff**, and never sees rejected findings.

### Findings are pointers, not instructions

This is the failure mode that ruins otherwise good pipelines, and it is not the
reviewer's fault — it is what the executor does with the output.

An accepted finding is **a place to look**, not a change order. Handed to an
executor as a work item, it produces a literal, local edit that silences the
finding and misses the problem: a guard added at the call site instead of fixing
the invariant, a `try/catch` around the symptom, a rename that makes the
complaint stop applying. The diff grows, the review goes quiet, and nothing was
fixed.

So findings are handed over with a fixed framing that says exactly this: the output may be wrong,
none of it is an instruction, decide for yourself whether something real is underneath, fix the
cause rather than the complaint — and if there is nothing real, say so and leave the code alone. The
wording is verbatim and lives in [.agents/skills/maintain](./.agents/skills/maintain/SKILL.md), the
copy that is actually read at handoff time. It is not repeated here, because a framing whose whole
point is being verbatim cannot survive two copies.

This is the same principle `AGENTS.md` states for human review comments: *the reviewer identifies
the issue, you own the fix*. The pipeline does not change it; automation makes it easier to forget.

**Rejecting an accepted finding is a legitimate outcome.** The executor may come
back with "F-004 points at real coupling, but the fix belongs in the repository
layer — I've filed it as a task and changed nothing here." That is the system
working. An executor that never pushes back is not being careful; it is being
compliant, and compliance is what over-fitting looks like.

### Signs the executor is fitting the reviewer instead of the code

Watch for these at the task boundary; they are cheap to spot and each one is a
policy signal:

| Symptom | What it usually means |
|---------|----------------------|
| The diff grew after review, and the growth is all defensive | Symptoms silenced at call sites, cause untouched |
| A finding was "fixed" by a rename, a comment, or a cast | The complaint no longer matches; the code did not change |
| Round 2 touches files round 1 did not | The fix is chasing the reviewer, not the bug |
| Every finding produced an edit | Nobody judged anything |
| Tests changed to match new behavior, with no reason given | The test was bent to the code |

The last two are the ones to take seriously. A round where **some** accepted
findings produced no code change, with a stated reason, is a healthier signal
than a round where all of them did.

---

## Reviewer

### Scope

The diff plus the symbols it touches — never the whole repository. Wider scope
buys nothing and multiplies hallucinations and cost. On a large codebase give it
symbol-level navigation (an LSP-backed MCP server) instead of grep.

### Output contract

Free-form prose is unfilterable. The reviewer emits JSON against
`review-findings.schema.json`: `file`, `line`, `code_quote`, `category`,
`severity`, `evidence`, `confidence` required.

Categories: `bug`, `security`, `perf`, `arch`, `replication`, `style`, `nit`.

`replication` is the odd one out: it is not about a defect inside the change. It
reports that the change is the **third or later** copy of a shape that already
exists, with the earlier locations as evidence. It escalates rather than going
to the executor, because "refactor this before we build more on it" is a
scheduling decision about someone's time, not a code-quality verdict. It also
exists to cancel a bias the rest of review has: matching the surrounding code
scores as consistency, and matching is exactly how an early wrong decision
spreads without anyone choosing to spread it.

### Grounding rules (in the reviewer prompt verbatim)

1. **No quote, no finding.** If it cannot reproduce the exact source line, the
   finding does not exist.
2. **A bug claim needs a counterexample** — concrete input → wrong output, or a
   failing test. Otherwise it is a risk, not a bug.
3. **Separate `confirmed` from `possible`.** Models pattern-match bug priors
   (off-by-one, null, boundary) onto correct code and state them as fact.
4. **Cite the violated rule** for style and architecture findings.
5. **No fixes.** No patches, no rewrites.

```
// BAD finding — unfalsifiable, no quote, no evidence
{"file": "src/parser.rs", "severity": "major",
 "evidence": "This function may panic on malformed input and should be hardened"}

// GOOD finding — locatable, quoted, proven, honest about confidence
{"file": "src/parser.rs", "line": 88,
 "code_quote": "let len = header[4] as usize;",
 "category": "bug", "severity": "blocker",
 "evidence": "header shorter than 5 bytes panics: parse(&[0,1,2]) → index out of bounds",
 "reproducible": true, "confidence": "confirmed"}
```

### Deterministic fields are computed, not asked

- `severity` follows from the rule level (`MUST` → blocker, `SHOULD` → major, `MAY` → minor).
- Quote-matches-source, `file:line` validity, and duplicate detection are script checks. A finding
  whose quote appears elsewhere in the file is relocated to the line where it actually is; one whose
  quote appears nowhere is dropped. That check alone removes a large share of hallucinations, and
  relocating rather than dropping keeps real findings that merely miscounted the diff. Multi-line
  quotes are matched on their first non-blank line.
- Truncated JSON is a mechanical failure: detect and retry with a smaller scope.

---

## Maintainer

Three jobs, in order. Only the first is a judgment call.

### Job 1 — Triage the findings

Inputs: `findings.json`, `gates.json`, `REVIEW_POLICY.md`, the architecture context, and the task's
exit criteria. One verdict per finding — `accept` / `reject` / `escalate` — against
`maintainer-verdicts.schema.json`.

Decision rules, first match wins:

1. **Contradicts a green gate → reject.** The gate ran; the model guessed.
2. **Confirmed by a red gate → accept**, severity from the gate. Reachable only
   for gates declared non-blocking (`run_gate lint no`), since a red blocking
   gate stops the pipeline before the reviewer runs. With every gate blocking —
   the shipped default — this rule is inert by design.
3. **Matches a policy rule → that rule's verdict and severity.** This is where
   accumulated taste applies.
4. **`category: replication` → escalate** (`decision_rule: replication`, distinct
   from rule 7 so the log can tell them apart). Above the next two on purpose: a
   replication finding is *about* code outside the task and reports a count
   rather than a proof, so rules 5 and 6 would each silence it.
5. **Out of task scope → reject**, and propose it to the user as a new task
   rather than growing the diff. The end-to-end harness is in every task's scope.
6. **`possible` confidence with no counterexample → reject**, except
   `category: security`, which escalates instead. The rule does not reach a
   `confirmed` or `likely` finding at all — a proven security bug is an
   ordinary accept, and escalating it would delay a real fix behind an answer.
7. **Architectural judgment, or gate/finding conflict → escalate** (`needs-judgment`; logs written
   before 2026-11-12 name it `needs-human-judgment`).
8. **No rule above fires → accept** (`no-rule-fired`): the finding stands on its
   own evidence. It is not a policy rule matching, and is not logged as one.

An escalation is answered before landing, at the pull request levels before the merge; who answers
it, and when it reaches the user, is `/maintain`, step 7.

`lib/prompts/maintainer.md` is fed to the maintainer by `review.sh` and is
**normative**; this section explains the rules rather than restating them, and
`agents/maintainer.md` carries only their names and order.

That is the general rule in this repo: **where the same thing is stated twice,
the copy a model reads at runtime is the normative one, and the other says so
instead of paraphrasing.** Paraphrase is where drift hides — it reads as
authoritative and nothing checks it. Rule 6 was wrong in the prompt for exactly
this reason: two human-readable copies said one thing and the copy that decided
verdicts said another.

Only `accept` at or above the threshold reaches the executor. The threshold has one source —
`THRESHOLD` in `.review/land.conf`, overridable per run by `review.sh --threshold`. The value
actually used is recorded in the run, and `land.sh` reads it from there — at the pull request levels
`publish.sh`, for the merge — so landing can never apply a different bar than the review did.
Accepted `minor`/`nit` go to an optional list. This threshold is the most effective dial in the
pipeline: raise it when diffs bloat, lower it when defects leak.

### Job 2 — Another round, or done?

**Rounds go on while review keeps finding less.** Every review reads the whole change, so on a large
change a later round finds what an earlier one missed; three or four rounds are normal. New findings
of a later round go to the executor like those of the first. The fix does not converge when a
finding comes back after it: `review.sh` compares what each review accepted with the review before
it — the same file and category, at the same quote where the file holds that line once, or within
five lines — and says so at the end of the run.

```
round n: execute → gates → review → triage → accepted findings? → fix, round n+1
```

- **Done** — gates green, no accepted `blocker`/`major`, no escalations.
- **Another round** — accepted findings exist. The count is the `accepted (>= threshold)` line of
  `review.sh`; a run that made no review — red gates, an unusable review, an error, a missing
  harness — is not a round.
- **Stop and find the cause** — a finding came back after its fix, a round accepted as many findings
  as the one before it or more, or a run ended the same way as the one before: another attempt of
  the same kind will not help.
- **Escalate** — an escalate verdict fired.

**Three times in a row is a circle, and `review.sh` stops**: a finding accepted at the same place in
three reviews in a row, each after a change of the work; a case that failed in three `/qa` of the
task, each on other work; or three runs in a row that ended the same way — the same gates red with
the same output, the same end-to-end failures. It runs nothing and exits 6. A finding or a case that
the fixes do not close is yours: the output says what does not converge, and the next run takes your
decision to go on (`--past-limit --user-decided`), and no words of yours. Three runs that ended the
same way are the maintainer's the first time. Where the work changed each time and the same gates or
tests stayed red, the script cannot tell fixes that do not close the failure from a machine that
failed each time — a device that went away under the tests, a stale build, a service that was down —
and the maintainer can: it has the logs. It finds the cause, mends it and runs again with what the
cause was and what was done about it (`--past-limit --because`); your decision is not taken there.
When the runs end that way three more times in a row after that, each after a change of the work,
the reason did not hold, and that is yours, with the reason that was given. A different end between
starts the row again. Where nothing changed between the runs, or what failed was no check of the
code — no test ran, as with a simulator that will not boot, or the review could not be used, as when
it cannot quote a deleted file — a retry does not mend it, and the maintainer finds the cause before
it runs again, with its reason (`--past-limit --because`). A cause only you can remove is told to
you once, with what was tried. Checks still running are not a failure, and have their own count
([Publishing](#publishing)). A failing case of `/qa` is no question either until `review.sh` stops
for it: the loop fixes it as often as it fails (`/maintain`, step 8).

**A stop says when it is yours.** A script that stops for you says so in one line,
`For the user, …`, for one of five reasons: what should be where nothing written says it; something
beyond what was agreed; work that does not converge; an act only you can do; what a person wrote on
the pull request. Every other stop is the loop's, and its line `The loop goes on: …`, where it has
one, names the next step. `turn` in `lib/common.sh` holds the list, and `selftest.sh` checks that no
script names you outside it. So a failing case of `qa/test-cases.md` is fixed, however many `/qa`
were red, until `review.sh` stops for it: its words are what should be. A behaviour nothing written
describes is a question, which `/qa` records and `pr-post.sh qa` prints; it does not hold the task.

**`review.sh` stops after `ASK_AFTER_RUNS` reviews of one task** (`.review/land.conf`, 5 by
default). It counts the runs that made a review — rounds, and the reviews again after `/qa`, an
answer `fixed` or a landing refusal — and not the runs that ended before one: red gates, an error,
an unusable review. Five leaves room for the three or four rounds of a large change. Past the limit
it runs nothing, exits 6 and prints what it read: how many findings each review accepted, and
whether one came back after its fix. A count alone is never a question to you. Reviews that found
different things, each fixed, go on: the maintainer runs `--past-limit`, which runs once more and
starts the count again. Where a finding came back once, or the reviews accept no fewer, the
maintainer judges whether the work moves toward the goal and gives its reason,
`--past-limit --because "<why>"`, which is kept in the run and shown on the pull request; where it
cannot tell, that is a question to you. The same number of runs in a row with no review stops the
task too, with how each ended. The runs of a task that landed are not read for a new task under its
id: once a commit records that a landing of the id committed with its review — the commit of
`land.sh` below the pull request levels, the squash of the merge at them — `review.sh`, `land.sh`
and the print after `/qa` read the runs, the landings and the `/qa` records made after it. `land.sh`
checks its other conditions before the gates, so a landing refused for one of them costs no build; a
landing that fails at or after its gates — red, killed, or a commit that fails — may be retried once
on the same run, so the answers to its escalations still apply, and a second time goes back through
`review.sh`, since nothing else counts landings. At the pull request levels `land.sh` takes no run
and counts its own: past `ASK_AFTER_RUNS` red or unfinished gate runs of the task it refuses and
says what was red each time; the same gates red the same way three times in a row, each time on
other work, are the maintainer's the first time, as with `review.sh`, and yours when the limit comes
again with those gates red that way in every landing since the maintainer's reason; anything else
goes on with `--past-limit --because`. The stops back each other: the line at the end of a run says
early what repeats, the circle stops the third repeat, and the count stops a session that goes on
finding.

### Job 3 — Land, then advance

Covered in the next two sections. The maintainer does not decide *whether the work is good enough*;
it checks conditions and commits (at every `LANDING` but `off`), and at `merge` merges, or refuses
and says which condition failed.

### Prohibitions

- Never adds findings the reviewer did not report; never rewrites a finding into a different
  problem.
- Never edits code, tests, or `REVIEW_POLICY.md`. Policy changes are yours, apart from the rule
  `/policy` writes when the loop answered the same escalation the same way twice.
- Never resolves an escalation by guessing: it finds out — reads the code, runs the check that
  settles it — and decides, and only what is yours reaches you.
- Never runs git directly, and reads a pull request only with `gh pr view`, `gh pr checks` and
  `pr-post.sh comments`. Its only write paths are `land.sh` and `publish.sh`, and on a pull request
  `pr-post.sh`.

---

## Landing

Where the requirement "Who writes to git" lets the loop commit, the maintainer commits. This is the
whole point of the role — but the authority is deliberately shaped so that "commit" means one
specific, checkable thing. How far the task goes after that is your answer there, and
`/maintain --init` writes it to `LANDING` in `.review/land.conf`, the first time and each time the
answer changes. The answer is the permission: nothing is switched on by hand. The scripts do what
`LANDING` says and cannot read the requirements, so `/maintain` compares the two before each landing
and stops if `LANDING` goes further than the answer; a lower `LANDING` is yours, and stands.

| Answer | `LANDING` | What the loop does | What is left to you |
|-----|-----------|--------------------|---------------------|
| (a) | `off` | Shows the files and the message | The commit |
| (b) | `push` | Commits, pushes a branch | The merge |
| (c) | `pr` | Commits, pushes, opens a pull request before the review; the review, the end-to-end tests and `/qa` run on it and post there; fixes what they find, answers what people write on it | The merge, with squash |
| (d) | `merge` | The same, fixes what they find, answers what people write on it, merges it with squash | Looking when you want to, and what only you can decide or do |

`on` commits on the current branch and publishes nothing. Any value not listed here is a refusal,
never a silent `off` or `on`, and so is a line that only looks like one, such as `LANDING = merge`.
Only at (c) and (d) do the review, the end-to-end tests and `/qa` run on a pull request and stay on
it; below, they run before the commit, and their results stay in the run folders on your machine.

At (d) the merge does not wait for you: that is what the answer gives away, and it is why "you look
when you want to" is about main, not about the next task. `ADVANCE` still says whether the next task
waits for you ([Advancing](#advancing)). What you object to afterwards is already in main: the
objection becomes a new task on top of it, or a revert you make, since no agent can revert.

At every answer a commit of the loop holds the task's files and the files the loop keeps as it goes:
`TASK_TRACKER.md` and `qa/test-cases.md`. These are in no task's scope and are written after the
review, so the reviewer and conditions 2 and 6 leave them out. They land with the task, or a line in
the tracker would refuse the next task and the two would reach main only by hand. The end-to-end
harness lands with the task that changed it too, but as reviewed work: it is in the reviewed diff
and in the fingerprint of condition 2, so a harness changed to pass without a test running does not
go unseen.

`REQUIREMENTS.md` and `PLAN.md` change only with your answer, apart from the `[x]` of a finished
task in the plan, and neither the reviewer nor conditions 2 and 6 count them as task work. Where
`.review/land.conf` says `WITH_RECORDS=yes`, the task's commit holds them, with your policy rules
and the decision logs under `.review/`; the reviewer is told of those that changed before it ran.
Otherwise they stay in the working tree for you to read and commit, at every answer; the logs
record what you said. A log committed on a task branch stops you going back to the base branch
while its next line waits in the tree, until the branch is merged: with `WITH_RECORDS=yes` at
`push` and `pr`, merge before the loop writes to a log again. The loop's settings, `land.conf` and
`gates.sh`, never land with a task: what the loop may do is yours to commit. Nor does the task
file, which the project ignores.

### The contract

`land.sh` refuses — exit 3, naming the condition — unless **all eight** hold; at `pr` and `merge`
three of them, and the rest at the merge
([The contract at the pull request levels](#the-contract-at-the-pull-request-levels)):

| # | Condition | Why |
|---|-----------|-----|
| 1 | The run directory is a completed review run | An empty directory must never authorise a commit |
| 2 | The run's tree fingerprint matches the tree now, the loop's own files apart | A review of a tree that has since changed is not a review of what is being committed |
| 3 | Gates re-run green **now**; the run's end-to-end tests passed on every platform the tree ships, with every `e2e:` mark `qa/test-cases.md` has now, and `.review/e2e.sh` is as it ran; a change to it is reviewed and lands with the task | Cheap insurance; catches a drifted environment |
| 4 | Zero accepted findings at or above the run's threshold | Nothing outstanding |
| 5 | Zero pending escalations | An escalation is owed an answer |
| 6 | Changed files ⊆ the task's declared scope, the loop's own files and the end-to-end harness apart | The diff did not sprawl |
| 7 | Every exit criterion carries a `verified_by` claim; `/qa` recorded the task in a `qa.json`, each `/qa` failure has its end-to-end test seen failing, then passing, with the words of its case as they were when it failed — or, for a case that `/qa` marks `manual: <why>`, a later `/qa` of other work that passed it; or the test skipped for the task it belongs to, or the user's own answer — and no test is skipped for this task | The tracker's definition of done, with the claim recorded in the commit |
| 8 | `LANDING` is a known level, `WITH_RECORDS` is `yes` or `no`, and the branch is not detached. With `LANDING=on`, the branch is not protected. At `push` and up, a remote exists and answers, the task id can name a branch, `task/<id>` is the current branch or exists neither here nor on the remote, a branch that has to be created can be, the remote's copy of the branch has not moved past it, and it carries no commit that no landing made. At `pr` and `merge`, the base branch is on the remote, `gh` is installed, logged in and sees the repository, and `CHECKS_WAIT` is a number | The loop never commits on trunk, and never makes an unreachable commit; a landing never ends half done for a reason known in advance; with `LANDING=off` the user commits, so a protected branch is a note, not a refusal |

Then one switch, which is **not** a refusal: `LANDING` in `.review/land.conf`. At `on` and `push`
the eight checks, and at `pr` and `merge` the three of the commit contract, are followed by a
commit; at `push` and up, by publishing too; with `LANDING=off` they are followed by the exact `git`
commands, printed for the maintainer, who gives you the files and the message, and the exit code
is 0. Every check runs either way — turning landing off removes the commit, never the contract. The
one exception is the protected branch of condition 8: it guards the loop's own commit, so with
`LANDING=off` it is printed as a note, and a project that commits by hand on `main` still gets the
files and the message. That is why `off` is what `land.sh` falls back to when nothing is set: it
delegates nothing.

**Condition 7 is the one with no mechanical backing.** It checks that a claim was *made*, not that
it is true. `.review/`, the end-to-end harness apart, is excluded from the tree fingerprint on
purpose — the task file is filled in after the review, and including it would invalidate every run
before it could land — so nothing stops a false claim but the person writing it. It is an auditable
assertion, not a proof. Anything genuinely checkable belongs in a gate, not in a criterion.

Conditions 1, 2, and 4 exist because the dangerous failure is not a wrong
judgment — it is a **missing** one reading as approval. An unreadable count, an
absent artifact, or a stale run must refuse, never default to zero.

Then, and only then, it stages **exactly the in-scope files, the loop's own, the changed end-to-end
harness and, with `WITH_RECORDS=yes`, the loop's records** — never `git add -A` — and commits with
trailers linking the task and the review run; at the pull request levels only `Task-Id` and `Gates`,
and the rest go to the squash commit.

The commit is `git commit --only -- <those files>`, not a bare `git commit`. A bare commit writes
the whole index, so anything the user had staged when the loop ran would ride along inside the
task's commit without ever being scope-checked — `.review/land.conf` most of all, and
`.review/REVIEW_POLICY.md` with `WITH_RECORDS=no`, since they are filtered out of the changed-file
list by design. The files that define this pipeline's limits must not be able to change unseen
inside a commit the pipeline made on its own: the policy lands only by `WITH_RECORDS=yes`, and then
among the files the commit names. Whatever the user had staged stays staged, untouched.

`land.sh` exits `0` when the task went as far as `LANDING` says, `3` on a refusal, `1` on an error,
and `4` when the commit landed but publishing did not finish. The output of `publish.sh` is shown.
If no code has to change — the network was down, the checks are still running — meet the cause and
run `publish.sh` alone, never `land.sh` again: the commit is in, and another landing with nothing
new would only be refused. If code has to change, that is a new pass of the loop on the same branch:
the work, a review run and `land.sh`, which adds a commit; at the pull request levels, the work,
`land.sh`, then a review run.

### The contract at the pull request levels

At `pr` and `merge` what can be checked before the review is checked at the commit, and the rest at
the merge. The fingerprint makes that possible: it is the content of the task's work — the tree
apart from `.review/` and the loop's and the owner's files, with the end-to-end harness — never a
commit, so committing reviewed work, or the tracker, the plan or the records, leaves it as it was,
and changing a line of the work changes it.

**The commit.** `land.sh` takes no `--run`, and refuses — exit 3, naming the condition — unless
these hold:

| # | Condition | Why |
|---|-----------|-----|
| 8 | As above; and HEAD carries no commit of another task that is not on the base branch of the remote | A squash never puts those commits on the base branch, so a pull request that holds them could never merge |
| 6 | Changed files ⊆ the task's scope, the loop's own files, the end-to-end harness, and the records with `WITH_RECORDS=yes` | The diff did not sprawl |
| 3 | Gates re-run green **now** | The work builds before anyone reviews it |

A commit of the loop's files alone — the tracker's ✅, `qa/test-cases.md`, and with
`WITH_RECORDS=yes` the plan's `[x]` and the logs — lands on the task's branch while it has an open
pull request of this task: it changes no task work. This is how they usually come at these levels,
after the review and `/qa`, in a commit of their own that the squash joins to the task. It refuses
as nothing to commit only when nothing changed. The message is `--message`, else `<id>: <title>` for
the task's first commit on the branch; after it `<id>: changes before review` while no review on the
pull request reached HEAD yet, then `<id>: changes after review <n>`; and `<id>: records` for the
loop's files alone. The trailers are `Task-Id` and `Gates`, and those of the audit go to the squash
commit. The gates' results go to `.review/runs/land-<time>-<pid>/gates.json`, which is not a review
run. Then `publish.sh` ([Publishing](#publishing)).

**The merge.** `publish.sh --check` checks every item below and merges nothing; exit 0 says the pull
request is ready to merge. `publish.sh --merge` is for `merge` alone — at `pr` it refuses (3): you
merge — and merges once every item holds. Both refresh the pull request's description first. The
tree: the task's work committed and pushed, HEAD the pull request's head; the loop's files
committed, and with `WITH_RECORDS=yes` the records too; with `no`, the owner's files and the logs
may stay uncommitted; `.review/` apart.

| # | Condition | Of the eight |
|---|-----------|--------------|
| M1 | The newest review run of this task made on this pull request (`meta.pr_url`; by `meta.time`; `land-*` and `qa-*` folders are not review runs, and a run of `--dry-run` names no pull request) is complete, posted there (`pr-review.json`), of the change from the merge base as it is now (`meta.merge_base`), and its fingerprint is the work now | 1, 2 |
| M2 | Its end-to-end tests passed on every platform the tree ships, the harness as it ran, every `e2e:` mark checked | 3, the end-to-end half |
| M3 | Zero accepted findings at or above the threshold in it | 4 |
| M4 | Every escalation of it answered | 5 |
| M5 | Every exit criterion has `verified_by`; the task's `/qa` failures are proven as condition 7 says; no test is skipped for this task; the newest `qa.json` of the task (by its `time`) has `work` = the fingerprint now, and some `qa.json` of the task checked the whole pull request (`since` = the merge base); both say how far `/qa` went and why (`extent`, `reason`) and what came of it (`counts`), and their reports are on the pull request (`pr-comment.json`); no `/qa` since the newest of the whole pull request left anything unproven or not checked, or you accepted what it left (`open-answered.json` beside it) — a `/qa` after a fix does not clear what an earlier one left open; an item `/qa` put off until after the merge (`after_merge`, with the check it will make) is in neither count and does not hold the merge | 7 |
| M6 | The changed files of `merge-base..HEAD` ⊆ scope ∪ loop files ∪ harness ∪ records | 6 |
| M7 | Every review run of this task made on this pull request is posted there, and every finding of its `approved.json` and `escalated.json` has its answer posted (`answers-posted.json`) — not `optional.json`, which is never handed over | — |
| M8 | Everything a person wrote on the pull request — a comment, a review, a comment on a line; not the loop's own (a post that starts with its `<!-- loop:` marker) nor a bot's — is settled: a reply of the loop names it with the answer `fixed`, or `user`, your decision in your words, from the chat or from what you wrote. A reply that disagrees or defers leaves it to you; one that says `unsettled` is the loop's to settle. Otherwise wait (5) | — |
| M9 | On GitHub, at HEAD: each status of the loop is `success` — `loop/<gate>` for each blocking gate, `loop/e2e-<platform>` for each platform, `loop/review`, `loop/qa`; no other check failing or pending (the wait of `CHECKS_WAIT`); no changes requested; the pull request carries no other task's commits; its head is HEAD | — |
| M10 | No task merged before this one still owes a check that `/qa` put off until after its merge: each has its result in `results.json` beside its list, in the folder `publish.sh` names (`.review/runs/after-merge-<task>/`, or one of its own for a task id used again) — `pass` with what was seen, `fail` with the task of the tracker that takes the defect, or `not_checked` with your acceptance beside it — and the report is on its pull request | — |

An item that does not hold refuses, exit 3, naming it; M8 and M9 wait, exit 5. A failed gate that is
not blocking is posted as success, "fail (not blocking)". The statuses are for people to see; the
script decides the merge, since the repository may enforce nothing. Where your host can enforce it,
you can make the base branch take changes only through a pull request, with the loop's statuses
required and squash merges only; `/maintain --init` says how, and changes nothing there itself.

A person outranks the loop on the pull request. What you write there is weighed like a finding; the
loop fixes it, or answers why not — an `unsettled` remark is the loop's to find out and answer
again — and then the merge waits for your decision, which the loop posts as the answer `user` with
your words, given after its answer; your own decision written on the pull request is settled the
same way, by a reply `user` that quotes it. Changes requested in a review stand until the one who
asked approves or dismisses it.

The merge is a squash of that head and no other: `--squash --match-head-commit`, the subject
`<id>: <title>`, and the body the trailers — `Task-Id`, `Gates` (of the newest run),
`Findings: N reviewed, R rejected, 0 outstanding at <threshold>+` (all runs of the task),
`Exit-Criteria: N verified`, `Review-Runs: <count>, last <run>`, `QA: <qa run> (<extent>)`; where
`/qa` put checks off until after the merge, `Exit-Criteria` and `QA` say how many. The pull
request's description ends with the same trailers, so at `pr` your squash can take them.

### Branches

At `push`, `pr` and `merge` the commit never goes onto a protected branch: `main`, `master`,
`PROTECTED_BRANCHES` and the base branch.

- On a protected branch, or on `task/<another id>`, `land.sh` creates `task/<id>` from HEAD with
  `git switch -c`, after the gates are green and just before the commit, so a refused landing leaves
  the branch as it was. The uncommitted tree moves with it, and the tree fingerprint has no branch
  name in it. The task id has to make a branch name: it matches `^[A-Za-z0-9._-]+$` or landing
  refuses.
- On `task/<id>`, or on any other branch that is not protected, it stays there.
- If `task/<id>` exists, here or on the remote, and is not the current branch, condition 8 refuses
  before the gates: the work on that task is somewhere else.

A next task starts where the last one left the checkout, and agents cannot move it. At `push` that
is the branch of the earlier task, so the next one stacks on it, merged or not: its branch starts
from the earlier one, and a pull request of it to the base branch shows the earlier commits too
until those are in the base branch, and merging it merges them. After you merge, go back to the base
branch and update it before the next task starts; a squash merge above all leaves the stack showing
those commits again. At `pr` and `merge` a task never stacks: `land.sh` refuses (8) while HEAD
carries a commit of another task that is not on the base branch of the remote. At `merge` a task
ends on the base branch, so the next one starts there; at `pr`, once you have merged and updated it.

**Remote:** `REMOTE` in `land.conf`, else `origin` if it exists, else the only remote, else a
refusal. **Base branch:** `BASE_BRANCH` in `land.conf`, else the HEAD of the remote, asked at every
landing because what a clone recorded goes stale, else `main` if it exists, else `master`. A remote
that cannot be reached is a refusal, never a guess. Nothing assumes a remote named `origin`, and
`gh` is told which repository that remote is, or it would pick one of its own.

### Publishing

`land.sh` keeps the job of committing and has no push in it. `publish.sh` holds the push, the pull
request and the merge, and has no commit in it. `land.sh` calls it after a commit at `push`, `pr`
and `merge`; run alone, with `publish.sh --task-file <task.json>`, it finishes a push that failed or
a pull request that was not opened, without another commit. It merges only with `--merge`.

1. **Refuses** at `off` and `on`, on a protected branch, on a detached HEAD, on a task id that
   cannot name a branch, and unless HEAD carries the trailer `Task-Id: <id>` of the task file. It
   also refuses a branch that carries commits no landing made: among those the push would add to the
   remote and, at `merge`, among all that are not yet on the base branch. At `push` and `pr` a
   person merges and sees what the branch holds, so what they pushed themselves stands; at `merge`
   nobody does. A merge commit counts as neither: only a person can make one, and it is how the base
   gets into a branch that conflicts with it, so with one on top the trailer is read from the commit
   under it.
2. **Looks at what is there**, at `pr` and `merge`, before it pushes. A pull request of this branch
   into the base branch that was closed without a merge is somebody's no: nothing is pushed or
   opened, it exits `5`, and only a person reopens it. One merged at this very commit is finished:
   nothing is pushed back.
3. **Pushes** with `git push -u`, never forced, with both sides of the refspec written out, so
   `remote.<name>.push` cannot force or redirect it. A rejected push is an error that says the
   remote branch moved, and that bringing the two together is yours.
4. **At `pr` and `merge`, opens the pull request**, never as a draft, if the branch has none open:
   the title `<id>: <title>`, the description from `pr-post.sh body`. If one is open it opens none,
   so a rerun never opens a second one, and it prints the URL. Then `pr-post.sh statuses` gives the
   new head the statuses of the newest review on this pull request and the newest `/qa`, if their
   fingerprint is the work now: a commit of the loop's files alone carries them over, and a commit
   of new work shows `loop/review` pending, "not checked by the loop yet", and `loop/qa` pending
   with its reason, "/qa has not checked this work". `pr-post.sh answers` and `pr-post.sh qa` post
   them again, so an escalation answered turns `loop/review` green without a commit. It exits `0`.
5. **With `--merge`, at `merge` only, merges** once the merge contract holds
   ([above](#the-contract-at-the-pull-request-levels)); otherwise it says which item failed, with
   the URL. A cancelled check is a failing one. Up to `CHECKS_WAIT` seconds (30 unless `land.conf`
   says otherwise), `--check` and `--merge` wait for checks to appear, since until some seconds
   after a push `gh` reports none, and then to finish. A repository that reports no other check
   after that long merges. It merges that commit and no other, with `--squash --match-head-commit`,
   and `--delete-branch` for `task/<id>` only: any other branch is someone's. A refusal by `gh` is
   exit `5` with its reason. It finishes on the base branch, updated with `git pull --ff-only`, and
   deletes the local `task/<id>` with `git branch -d`. Once the pull request of a task whose `/qa`
   put checks off until after the merge is merged — by `--merge`, or at `pr` when `publish.sh` finds
   it merged — it writes them down beside the runs, in the folder it names
   (`after-merge-<task>/owed.json`; a task id used again gets a folder of its own), and lists them;
   the maintainer has `/qa` make them at once, and one that fails then is a defect like any other: a
   task in the tracker. A merge that no run of `publish.sh` saw — at `pr` you merge, and on the base
   branch it refuses — is found by the next review or landing, from the task's squash in the history
   and its `/qa` records, and the list is written then. A later task is reviewed and landed
   meanwhile; its merge waits until each check has its result (M10). When the base branch is checked
   out in another worktree, this one stays where it is and says so. When the checkout cannot move,
   it says so and exits `1`: the merge is in, and running `publish.sh --merge` again only retries
   the move. When the base branch here cannot fast-forward, the same; that one is for you to settle,
   as the script refuses on the base branch.

Exit codes: `0` done, `1` error, `3` refused, `5` waiting.

At `pr` and `merge` the rest of that answer, "fixes what the review and QA find", is the loop
itself. The maintainer reads the pull request with `gh pr view`, `gh pr checks` and
`pr-post.sh comments`, which shows whole what people wrote that is not settled — `gh pr view` shows
no comment on a line — and what needs fixing — a finding, a `/qa` failure, a failing check, a
person's comment — goes through the loop on the same branch: the work, `land.sh`, which adds a
commit and updates the pull request, then a review run. A person's comment is answered with
`pr-post.sh reply <id> <answer> <text-file>`.

Checks still running are not a failure. Each run of `publish.sh --check` or `--merge` waits
`CHECKS_WAIT` seconds, and the maintainer runs it again, up to three runs in a row, then tells you
once, and comes back to it. Set `CHECKS_WAIT` a little over what your checks take and a merge ends
in one run, with `0`, which is what the next task waits for at `ADVANCE=auto`.

A conflict with the base branch goes to you, since no agent can merge or rebase: `gh` refuses the
merge and `publish.sh --merge` exits `5` with its reason. Merge the base into the branch, or merge
the pull request yourself. The base merged in changes the work, so the loop then publishes it with
`publish.sh` alone, reviews it and checks it with `/qa` again before `publish.sh --merge`.

### What landing cannot do

`land.sh` has no code path for `push`, `amend`, `--force`, `rebase`, `checkout`, `reset`, `stash`,
or `clean`. It commits, on the current branch or on the one branch it may create, or it fails.
`publish.sh` has no code path for `commit`, `amend`, `--force`, `rebase`, `reset`, `stash`, or
`clean`. `pr-post.sh` has none for `push`, `commit` or merge: it writes on the pull request alone —
statuses, reviews, replies, comments, the description. History is never rewritten by an agent, and
for the loop **main is reached only through a pull request, never a direct commit**: no script
commits onto a protected branch or pushes one. It reaches main at `merge` alone. At `push` and `pr`
it stops at the branch and you merge it, and at `off` and `on` the remote is never touched at all.
What you do by hand is yours.

### Why the authority is a script, not a permission

Agents get **no write-git permission by policy**. `.claude/settings.json` denies the mutating `git`
subcommands and their flag forms, and the `gh` commands that write or reach around the list, and
pre-approves three commands that write so they do not prompt: `land.sh`, `publish.sh` and
`pr-post.sh`. Those allow entries are a convenience, not the boundary — `review.sh`, `gates.sh`,
tests and linters are ordinary `Bash` calls under the project's normal permission settings. What
makes the three special is that they are the only ones that can write to git or to a pull request at
all; `review.sh` posts through `pr-post.sh`. The deny list is what stops an agent from merging by
hand; `gh pr view` and `gh pr checks` stay allowed, and `pr-post.sh comments` reads, because reading
is how the loop sees a pull request: its checks and what people wrote on it.

Be precise about what this is: permission patterns match by prefix, so the list covers the
invocations an agent would actually write, not every syntactically possible one. It is a strong
guardrail, not a sandbox. The structural guarantees are elsewhere — the maintainer's tool grant, and
the fact that `land.sh` cannot push, amend, force, or move to any branch but `task/<id>`,
`publish.sh` cannot commit, amend, force, or publish a protected branch, and `pr-post.sh` cannot
push, commit or merge, no matter who calls them. The agent's power is then the *scripts' semantics*,
not git's surface area — and the scripts live in the CodingStandards submodule, so a project cannot
quietly widen them.

```json
{
  "permissions": {
    "deny": [
      "Bash(git add:*)", "Bash(git commit:*)", "Bash(git reset:*)",
      "Bash(git checkout:*)", "Bash(git switch:*)", "Bash(git restore:*)",
      "Bash(git stash:*)", "Bash(git rm:*)", "Bash(git mv:*)",
      "Bash(git push:*)", "Bash(git pull:*)", "Bash(git fetch:*)",
      "Bash(git merge:*)", "Bash(git rebase:*)", "Bash(git clean:*)",
      "Bash(git tag:*)", "Bash(git branch:*)", "Bash(git revert:*)",
      "Bash(git cherry-pick:*)", "Bash(git worktree:*)", "Bash(git apply:*)",
      "Bash(git am:*)", "Bash(git update-ref:*)", "Bash(git config:*)",
      "Bash(git submodule:*)", "Bash(git notes:*)", "Bash(git gc:*)",
      "Bash(git prune:*)", "Bash(git repack:*)", "Bash(git pack-refs:*)",
      "Bash(git maintenance:*)", "Bash(git fast-import:*)",
      "Bash(git filter-branch:*)", "Bash(git replace:*)",
      "Bash(git -C:*)", "Bash(git --git-dir:*)", "Bash(git --work-tree:*)",
      "Bash(git -c:*)", "Bash(git commit-tree:*)", "Bash(git symbolic-ref:*)",
      "Bash(git read-tree:*)", "Bash(git update-index:*)", "Bash(git bisect:*)",
      "Bash(git sparse-checkout:*)", "Bash(git clone:*)", "Bash(git init:*)",
      "Bash(git checkout-index:*)", "Bash(git stripspace:*)",
      "Bash(git --no-pager:*)", "Bash(git --paginate:*)", "Bash(git -p:*)",
      "Bash(git -P:*)", "Bash(git --bare:*)", "Bash(git --namespace:*)",
      "Bash(git --no-optional-locks:*)", "Bash(git --exec-path:*)",
      "Bash(git --literal-pathspecs:*)", "Bash(git remote add:*)",
      "Bash(git remote set-url:*)", "Bash(git remote remove:*)",
      "Bash(git remote rename:*)", "Bash(git remote rm:*)",
      "Bash(git remote update:*)", "Bash(git remote prune:*)",
      "Bash(git remote set-head:*)", "Bash(git remote set-branches:*)",
      "Bash(git reflog expire:*)", "Bash(git reflog delete:*)",
      "Bash(git reflog drop:*)", "Bash(git reflog write:*)", "Bash(git stage:*)",
      "Bash(git --config-env:*)", "Bash(git --no-replace-objects:*)",
      "Bash(git --no-lazy-fetch:*)", "Bash(git --no-advice:*)",
      "Bash(git --glob-pathspecs:*)", "Bash(git --noglob-pathspecs:*)",
      "Bash(git --icase-pathspecs:*)", "Bash(git --attr-source:*)",
      "Bash(gh pr create:*)", "Bash(gh pr merge:*)", "Bash(gh pr close:*)",
      "Bash(gh pr edit:*)", "Bash(gh pr reopen:*)", "Bash(gh pr ready:*)",
      "Bash(gh pr review:*)", "Bash(gh pr comment:*)", "Bash(gh pr checkout:*)",
      "Bash(gh pr update-branch:*)", "Bash(gh pr revert:*)", "Bash(gh pr lock:*)",
      "Bash(gh pr unlock:*)", "Bash(gh pr -R:*)", "Bash(gh pr --repo:*)",
      "Bash(gh -R:*)", "Bash(gh --repo:*)", "Bash(gh api:*)", "Bash(gh repo:*)",
      "Bash(gh release:*)", "Bash(gh workflow:*)", "Bash(gh alias:*)",
      "Bash(gh extension:*)", "Bash(gh extensions:*)", "Bash(gh config:*)",
      "Bash(gh secret:*)", "Bash(gh variable:*)", "Bash(gh issue:*)",
      "Bash(gh label:*)", "Bash(gh cache:*)", "Bash(gh ruleset:*)",
      "Bash(gh project:*)", "Bash(gh gist:*)", "Bash(gh codespace:*)",
      "Bash(gh run rerun:*)", "Bash(gh run cancel:*)", "Bash(gh run delete:*)",
      "Bash(gh auth login:*)", "Bash(gh auth logout:*)", "Bash(gh auth refresh:*)",
      "Bash(gh auth setup-git:*)", "Bash(gh auth switch:*)", "Bash(gh auth token:*)"
    ],
    "ask": [
      "Edit(.review/land.conf)", "Write(.review/land.conf)"
    ],
    "allow": [
      "Bash(CodingStandards/templates/review/lib/land.sh:*)",
      "Bash(./CodingStandards/templates/review/lib/land.sh:*)",
      "Bash(CodingStandards/templates/review/lib/publish.sh:*)",
      "Bash(./CodingStandards/templates/review/lib/publish.sh:*)",
      "Bash(CodingStandards/templates/review/lib/pr-post.sh:*)",
      "Bash(./CodingStandards/templates/review/lib/pr-post.sh:*)",
      "Bash(gh pr view:*)", "Bash(gh pr checks:*)"
    ]
  }
}
```

The `ask` entries make any edit of `land.conf` stop for your yes, `/maintain --init` included: that
file says how far the loop may go, and the scripts believe it. A shell redirect gets past them, as
it gets past any entry here. That is the limit of a guardrail, and `/maintain`'s comparison with the
requirement is the second one.

`gh` is never allowed as a whole: `Bash(gh:*)`, added to read pull requests, would let through every
`gh` command this list does not name, each of which prompts today. Reading has its own entries;
`gh run view` and `gh auth status` stay open and prompt.

The allow entries are literal command prefixes, so they only match the form the command is actually
typed in. `/maintain` invokes the scripts as `CodingStandards/templates/review/lib/...` from the
project root — the first entry of each. The `./` variant is there because it is the other way people
type it; an absolute path matches neither and will prompt. That prompt is a nuisance, never a hole:
the deny list is what carries the guarantee, and an allow entry that fails to match only costs a
confirmation.

A global option written before the subcommand (`git --no-pager add`) starts with no
`git <subcommand>` prefix of the list, so each global option git accepts before a subcommand has its
own line; so do the writing forms of `remote` and `reflog`, whose reading forms stay allowed.
Reading is therefore written without a global option — `git diff`, not `git --no-pager diff`; git
opens no pager when its output is not a terminal anyway. `gh pr` takes `-R` before its subcommand in
the same way, and `gh alias` and `gh extension` reach any command by another name, so they have
lines too.

Keep this list in step with the prohibitions in
[EXECUTION_GUIDE.md](./EXECUTION_GUIDE.md#who-writes-to-git): a subcommand that
is forbidden in prose but absent from the deny list is not forbidden at all.

`LANDING=off` in `.review/land.conf` is the kill switch: the pipeline then runs to completion, and
the maintainer gives you the files and the message instead of committing. `publish.sh` refuses at
`off` too. `LANDING=off` holds whatever the requirement says: `/maintain` stops only when `LANDING`
goes further than the requirement, never when it stays behind.

### Interactive work is different

This delegation is scoped to the pipeline. The requirement "Who writes to git" says how far the loop
goes, and only that. Outside the loop — in an ordinary chat session, or a project that has not set
it up — git is read-only for agents at every answer. See
[EXECUTION_GUIDE.md](./EXECUTION_GUIDE.md#who-writes-to-git). The difference is not the tool, it is
that landing is a contract you defined, enabled, and can revoke, and the pipeline reaches it only
through the conditions above.

---

## Advancing

After the landing step, the maintainer either asks you or takes the next task.
**You review tasks, not commits.**

### The starting mode: ask every time

`ADVANCE=ask` — the default, and where every project begins.

The maintainer presents the finished task: what changed, the gate results, and what `/qa` found. The
review's findings, and how each was answered, stay in `.review/`; at the pull request levels they
are on the pull request too, and the report starts with its link. You accept, or you object. On
acceptance — and with `LANDING=off`, once you have committed it — it takes the next unblocked task
from the tracker and starts the loop again. At `merge` you are shown a task already in main; the
loop waits for you, main did not.

You are looking at the *task*, not the diff of each commit. If the summary looks
right, that is enough.

### The goal: learn when not to ask

**Your silence is evidence, not a verdict.** A task you accepted with no
remarks says work of this shape did not need your attention. It is the reason
you might one day stop asking about that category — and the deciding is still
yours to do, in `land.conf`.

The decision is *not* "is this code good" — gates and review already answered that. It is "is this
task trivial enough that a human would have nothing to say", and it is yours. What the maintainer
may report to help you make it are deterministic signals — diff size, paths touched, how many
findings were raised, rounds used, whether behaviour changed without a test, the task category, and
your history in those paths. That sentence is the whole list — there is no table elsewhere, and no
score derived from it.

`ADVANCE=auto` works at any `LANDING` but `off`, and only once the landing has finished: `land.sh`,
or the last `publish.sh` after it, ended with `0` — at `merge` `publish.sh --merge`. At `pr` the
next task waits for your merge all the same, since a task never stacks there, so `auto` acts as
`ask`. It unlocks per-category, never globally, and **only you unlock it**: you name a category in
`ADVANCE_CATEGORIES` because you have decided you no longer want to see it. Nothing measures its way
in. The maintainer may say it thinks a category has gone quiet; adding the line is your edit
([MAINTAINER_TRAINING.md](./MAINTAINER_TRAINING.md) § Never decide whether the user looks). Rollback
is not a calculation either: one task you should have seen, and the category goes back to `ask`.

### The asymmetry that should make you slow to unlock

Asking too often costs you a few seconds. Advancing past a task you should have
seen costs a defect that nobody looked at, buried under later commits. Unlock
accordingly: one category at a time, never a risk path, and back to `ask` the
moment you object to something that was auto-advanced.

---

## Project Setup

This repo is consumed as a git submodule at `CodingStandards/` in the host
project. **The project never edits the submodule for itself** — it is a shared
library, and edits there are overwritten on the next
`git submodule update --remote` or leak into every other project. The standards
change in their own repository.

So the pipeline splits by ownership:

| Part | Lives in | Edited | Why there |
|------|----------|--------|-----------|
| `review.sh`, `land.sh`, `publish.sh`, `pr-post.sh`, `triage.py`, prompts, schemas | submodule — `CodingStandards/templates/review/lib/` | Never | Identical everywhere; `land.sh`, `publish.sh` and `pr-post.sh` in particular must not be widened by a project |
| `gates.sh` | project — `.review/` | Always | Encodes the stack — the one language-specific file |
| `REVIEW_POLICY.md` | project — `.review/` | Constantly | Your taste, this codebase |
| `land.conf` | project — `.review/` | Rarely | Landing and advancing switches |
| `agents.conf` | project — `.claude/` | Rarely | The model and effort of each role |
| `decisions/`, `eval/` | project — `.review/` | Constantly | Your decisions, your golden set |
| Subagents | project — `.claude/agents/` | Rarely | Claude Code only discovers them there |

```
my-project/
├── CodingStandards/                   # submodule — the project does not edit it
│   └── templates/review/
│       ├── lib/                       # runs from here
│       │   ├── review.sh              # one review pass (gates, review, triage)
│       │   ├── land.sh                # the only thing that commits
│       │   ├── publish.sh             # the only thing that pushes, opens or merges a pull request
│       │   ├── pr-post.sh             # what the loop writes on a pull request: statuses, replies
│       │   ├── selftest.sh            # review.sh and the scripts that write, on throwaway repos
│       │   ├── export-version.sh      # one version of the project into a folder of its own
│       │   ├── triage.py              # you answer findings — terminal or browser
│       │   ├── prompts/{reviewer,maintainer}.md
│       │   └── schemas/*.json
│       └── project/                   # copied once into .review/
├── .review/                           # yours, versioned in this repo
│   ├── gates.sh                       # ← the only file you must fill in
│   ├── land.conf                      # ← LANDING / ADVANCE switches
│   ├── REVIEW_POLICY.md               # ← grows with every disagreement
│   ├── current-task.json              # the task in flight — scope, exit criteria
│   ├── decisions/{findings,tasks,escalations}.jsonl
│   ├── eval/golden.jsonl              # your verdicts, for /policy --eval
│   └── runs/                          # per-run artifacts — gitignored
├── .claude/agents.conf                # ← the model of each role
└── .claude/agents/{reviewer,maintainer}.md
```

### Install

```bash
git submodule add https://github.com/x128/CodingStandards.git CodingStandards
mkdir -p .review .claude/agents
cp -r CodingStandards/templates/review/project/. .review/
cp CodingStandards/templates/agents/*.md .claude/agents/
cp CodingStandards/templates/agents/agents.conf .claude/
for f in decisions/findings decisions/tasks decisions/escalations eval/golden; do
  : > ".review/$f.jsonl"
done
chmod +x .review/gates.sh
printf '%s\n' .review/runs/ .review/current-task.json >> .gitignore
```

Then, in order:

1. **Fill in `.review/gates.sh`** — the five slots. See
   [Wiring a new language](#wiring-a-new-language).
2. **Add the permissions block above** to `.claude/settings.json`.
3. **Set `LANDING`** in `.review/land.conf` from the requirement "Who writes to git": (a) `off`,
   (b) `push`, (c) `pr`, (d) `merge`.
4. **Run a task.** `/maintain` writes `.review/current-task.json` itself, from the tracker entry.
   For a manual pass, start from the template:
   `cp .review/task.example.json .review/current-task.json` and fill in `id`, `scope`, and
   `exit_criteria`.

```bash
# the loop is driven by the /maintain skill, which calls review.sh, land.sh and, at pr
# and merge, publish.sh --check or --merge and pr-post.sh; land.sh calls publish.sh, and
# at pr and merge review.sh, publish.sh and /qa post through pr-post.sh
/maintain --task T-001
```

`/maintain --init` does the first three, including detecting the stack and writing the gate
commands.

The loop is a **default**, not a rule for the user: any change can be made outside the pipeline, on
request, without justification
([EXECUTION_GUIDE.md § Who runs the work](./EXECUTION_GUIDE.md#who-runs-the-work) states this in
full, and `.agents/skills/maintain/SKILL.md` repeats it to the agents that need to hear it — the one
duplication in this repo that is on purpose).

### Overriding a shared file

`review.sh` prefers `.review/<path>` over the submodule's copy, so a project can override a prompt
or schema by copying just that file. `land.sh`, `publish.sh` and `pr-post.sh` are deliberately
**not** overridable — they are the three files with write authority.

Prefer contributing improvements back to the submodule; an override is a fork you now maintain. An
overridden schema is updated together with the submodule's prompt that fills it: a decision rule the
prompt names and the schema lacks fails every run that reaches it (`selftest.sh` checks the shipped
pair). Project-specific *content* (rules, examples) belongs in `.review/REVIEW_POLICY.md`, which is
already in the maintainer's context.

### Hooks

Use hooks for invariants, never for logic:

- `PostToolUse` on edits → format and lint gates. Formatting must never reach
  the reviewer as a finding.

---

## Failure Modes

| Symptom | Cause | Fix |
|---------|-------|-----|
| Diffs balloon after review | Threshold too low; nits reaching the executor | Accept `major`+ only |
| Reviewer invents bugs in correct code | Bug-prior pattern matching | Enforce quote + counterexample; reject `possible` without evidence |
| Maintainer agrees with everything | Shares the reviewer's context | Fresh session per role; the maintainer gets findings and gates, not the reviewer's reasoning |
| Same finding every run | Missing policy rule | Write the rule — or better, encode it as a lint rule in Layer 0 |
| Landed commits you would have rejected | `ADVANCE=auto` too broad | Revert that category to `ask`; tighten thresholds |
| Landing refused and nobody knows why | Contract failure not surfaced | `land.sh` names the failing condition — read it, do not bypass it |
| Pull request stuck open | An item of the merge contract: a status or check failing or pending, a person's comment not settled, changes requested, `/qa` left something unproven | `publish.sh --check` or `--merge` says which; fix through the loop on the same branch, answer the comment, or run it again later; its last line says when it is the user's |
| Pull request will not merge | It conflicts with the base branch | `gh` says so at exit 5; merge the base into the branch yourself; the loop publishes, reviews and checks it again |
| Next task's branch repeats merged commits | The loop started on the earlier task's branch | After a merge at `push`, go back to the base branch and update it; at `pr` and `merge` `land.sh` refuses to stack |
| Maintainer metrics improve, real quality doesn't | Reward hacking in the loop | Re-separate roles, lower `ASK_AFTER_RUNS`, strengthen Layer 0 |
| Cost per task is high | Broad scope | Narrow the task; diff + touched deps only; cheap model for triage |

---

## Summary Checklist

- [ ] Layer 0 exists first: build, test, format, lint, arch — one command each
- [ ] Gates run before the reviewer and at every landing; at `pr` and `merge` the landing comes
      first
- [ ] Reviewer sees the diff and touched dependencies only
- [ ] Reviewer output is schema-validated JSON with quote and evidence
- [ ] Quotes are script-verified against source; mismatches are dropped
- [ ] `severity` derived from rule level, never asked of the model
- [ ] A finding contradicting a green gate is always rejected
- [ ] Only `accept` + `severity ≥ major` reaches the executor
- [ ] Fresh session per role
- [ ] Rounds go on while each accepts fewer findings; an oscillation stop
- [ ] Landing passes all eight conditions or fails loudly; at `pr` and `merge`, the commit contract
      before the review and the merge contract, M1–M10, before the merge
- [ ] At `pr` and `merge` the review, the end-to-end tests and `/qa` run on the pull request and
      post there; before the merge every finding handed over has its answer there, and every
      person's comment is fixed or decided by the user
- [ ] Missing or malformed pipeline output fails closed, never as "nothing found"
- [ ] `lib/selftest.sh` passes after any change to `review.sh`, `land.sh`, `publish.sh`,
      `pr-post.sh`, the schemas or the output contract — it is the only run of the validation that
      does not need a model to answer with findings
- [ ] Agents have no write-git or write-`gh` permission; `land.sh`, `publish.sh` and `pr-post.sh`
      are the only pre-approved commands that write
- [ ] `land.sh` never pushes, amends, forces, or moves to a branch but `task/<id>`
- [ ] `publish.sh` never commits or forces, publishes only what landings made, and merges only this
      task's commits, with squash
- [ ] `pr-post.sh` never pushes, commits or merges
- [ ] The loop reaches main only through a pull request, never a direct commit; at `pr` and `merge`
      a task never stacks on another's unmerged commits
- [ ] The tracker, the test cases and a changed end-to-end harness land with the task; a line left
      in the tracker does not refuse the next one; the requirements, the plan and the decision logs
      land with it with `WITH_RECORDS=yes`, and otherwise stay for you to commit
- [ ] `LANDING` goes no further than the requirement "Who writes to git"; an unknown value refuses,
      and a change to `land.conf` asks you
- [ ] `LANDING=off` kill switch works and is documented
- [ ] `ADVANCE=ask` until you add a category yourself
- [ ] Every task boundary is logged: signals + your decision
- [ ] One objection reverts a category to `ask`
