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
| **Review** | Reading code for defects, inconsistency, replication | `skills/review.md`, `CLEAN_CODE.md`, the language standards |
| **Gates** | The project's own build, test, format, lint, and architecture commands | `.review/gates.sh` |

You can execute tasks and review code with none of this document. People do it
by hand every day, and `/review` works on its own.

**The loop is not an automated version of any of them.** It is a machine that
runs them in a fixed order with roles that cannot mark their own work, and it
adds two things that do not otherwise exist:

- a **landing contract** — the conditions under which a commit may happen
  without you (`land.sh`)
- an **advance decision** — whether you are shown a finished task at all
  (`land.conf`)

Those two are the whole reason this document exists. Everything else here is
plumbing that makes them safe enough to use.

**What it does not change.** The execution rules hold inside the loop exactly as
they do outside it: one task at a time, exit criteria are the definition of
done, and *you* decide a task is genuinely finished. The loop moves **one**
action — the mechanical act of committing — behind a contract you enable and can
revoke. It never moves the judgment.

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
              (max 2 rounds)      │ 1. triage findings        │
                                  │ 2. another round or done? │
                                  │ 3. land, then advance     │
                                  └──────┬──────────────┬─────┘
                                         │              │
                                    land.sh          escalate
                                    (commit)            │
                                         │              ▼
                                         ▼            HUMAN
                                    next task
```

| Role | Decides | Power |
|------|---------|-------|
| Executor | How to write it | Edits files inside the task's scope |
| Reviewer | What is broken | None — emits JSON, touches nothing |
| Maintainer | What counts, when it's done, what lands | Commits, through one narrow script |

The maintainer is the role this pipeline exists for. It is not a second
reviewer: it never hunts for defects. It filters the reviewer's output, decides
whether the task is finished, lands it, and moves to the next one.

### Where the reliability comes from

Not from the maintainer being smart. From three things underneath it:

1. **Layer 0** — the compiler, tests, linter, and architecture rules are ground
   truth. Any finding contradicting a green gate loses.
2. **A landing contract** — the maintainer does not judge whether the work is
   good enough to commit. It checks conditions, all of which are mechanical
   (see [Landing](#landing)). Its discretion is narrow by construction.
3. **A human at the task boundary** — you review tasks, not commits. Early on
   you see every task; over time the maintainer learns which ones are not worth
   your attention (see [Advancing](#advancing)).

### Role separation

Use a **different model for the reviewer than for the executor**, and a
different one again for the maintainer. One model judging its own output
inflates its own scores while real quality drops. Different models and
asymmetric context break that loop.

With a single vendor, enforce the same separation structurally: a fresh session
per role, the reviewer never sees the executor's reasoning, and a hard iteration
limit.

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
| Kotlin / KMP | `./gradlew compileKotlinMetadata compileKotlinJvm` | `./gradlew allTests` | `ktlintCheck` | `detekt` | Konsist tests |
| Swift | `swift build` / `xcodebuild` | `swift test` | `swift-format lint` | `SwiftLint` | custom test target |
| TypeScript | `tsc --noEmit` | `vitest run` | `prettier --check` | `eslint` | `dependency-cruiser` |
| Python | `mypy` / `pyright` | `pytest` | `ruff format --check` | `ruff check` | `import-linter` |
| Rust | `cargo check --all-targets` | `cargo test` | `cargo fmt --check` | `cargo clippy -D warnings` | module-boundary tests |
| Go | `go build ./...` | `go test ./...` | `test -z "$(gofmt -l .)"` | `golangci-lint run` | `go-arch-lint` |
| C# | `dotnet build` | `dotnet test` | `dotnet format --verify-no-changes` | Roslyn analyzers | NetArchTest |

Every command there **checks** and never rewrites. A `--format` or `--write`
mode in the `format` slot breaks the rule above and stops the run right after
the gates, before a single token is spent on review; and a
command that exits 0 on failure — bare `gofmt -l` is the classic — is a gate
that never fires at all.

**Checklist when starting a project in a new language:**

- [ ] A tool for each of the five slots. If none exists for `arch`, write the
      rules as ordinary unit tests — every language can do this.
- [ ] Every gate runs from one command and exits non-zero on failure.
- [ ] Fast enough to run per task, and again at landing (target: under 2
      minutes). Scope `test` to affected modules if the full suite is slow, and
      run the full suite in CI.
- [ ] One definition, three call sites: local, hook, CI.
- [ ] Tool choices recorded in the project's `CLAUDE.md`.

**Gates run before the reviewer and again at landing.** A red build means the
reviewer never runs — send the executor back with the compiler output.

**Gates must not modify the tree.** Use check modes (`--check`, `lint`), not
formatters that rewrite files. `run.sh` compares the fingerprint immediately
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

Writes code for **one task** in its own worktree or branch.

- **Narrow scope beats clever orchestration.** A tightly scoped task with an
  explicit file boundary costs an order of magnitude less than a broad one, and
  the landing contract can check it.
- **Declares its scope.** The task's allowed paths come from the tracker; the
  executor works inside them. Landing verifies the diff stayed there.
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

So findings are handed over with a fixed framing that says exactly this: the
output may be wrong, none of it is an instruction, decide for yourself whether
something real is underneath, fix the cause rather than the complaint — and if
there is nothing real, say so and leave the code alone. The wording is verbatim
and lives in [skills/maintain.md § step 6](./skills/maintain.md), the copy that
is actually read at handoff time. It is not repeated here, because a framing
whose whole point is being verbatim cannot survive two copies.

This is the same principle `CLAUDE.md` states for human review comments: *the
reviewer identifies the issue, you own the fix*. The pipeline does not change
it; automation makes it easier to forget.

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

- `severity` follows from the rule level (`MUST` → blocker, `SHOULD` → major,
  `MAY` → minor).
- Quote-matches-source, `file:line` validity, and duplicate detection are script
  checks. A finding whose quote appears elsewhere in the file is relocated to the
  line where it actually is; one whose quote appears nowhere is dropped. That
  check alone removes a large share of hallucinations, and relocating rather
  than dropping keeps real findings that merely miscounted the diff.
  Multi-line quotes are matched on their first non-blank line.
- Truncated JSON is a mechanical failure: detect and retry with a smaller scope.

---

## Maintainer

Three jobs, in order. Only the first is a judgment call.

### Job 1 — Triage the findings

Inputs: `findings.json`, `gates.json`, `REVIEW_POLICY.md`, the architecture
context, and the task's exit criteria. One verdict per finding —
`accept` / `reject` / `escalate` — against `maintainer-verdicts.schema.json`.

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
5. **Out of task scope → reject**, and route it to the tracker as a new task
   rather than growing the diff.
6. **`possible` confidence with no counterexample → reject**, except
   `category: security`, which escalates instead. The rule does not reach a
   `confirmed` or `likely` finding at all — a proven security bug is an
   ordinary accept, and escalating it would delay a real fix behind a human.
7. **Architectural judgment, or gate/finding conflict → escalate.**

`lib/prompts/maintainer.md` is fed to the maintainer by `run.sh` and is
**normative**; this section explains the rules rather than restating them, and
`agents/maintainer.md` carries only their names and order.

That is the general rule in this repo: **where the same thing is stated twice,
the copy a model reads at runtime is the normative one, and the other says so
instead of paraphrasing.** Paraphrase is where drift hides — it reads as
authoritative and nothing checks it. Rule 6 was wrong in the prompt for exactly
this reason: two human-readable copies said one thing and the copy that decided
verdicts said another.

Only `accept` at or above the threshold reaches the executor. The threshold has
one source — `THRESHOLD` in `.review/land.conf`, overridable per run by
`run.sh --threshold`. The value actually used is recorded in the run, and
`land.sh` reads it from there, so landing can never apply a different bar than
the review did.
Accepted `minor`/`nit` go to an optional list. This threshold is the most
effective dial in the pipeline: raise it when diffs bloat, lower it when defects
leak.

### Job 2 — Another round, or done?

**Hard limit: 2 rounds.** Generator–critic loops stop paying after the first
couple; later rounds mostly rewrite working code. There is no third round and no
exception clause: if two rounds did not resolve a finding, the finding was not
understood, and a third attempt at it is guessing — escalate instead.

```
round 1: execute → gates → review → triage → accepted findings? → fix
round 2: execute → gates → review → triage → accepted findings? → escalate
```

- **Done** — gates green, no accepted `blocker`/`major`, no escalations.
- **Another round** — accepted findings exist and the round budget remains.
- **Escalate** — budget exhausted, an escalate verdict fired, or the same
  `file:line` was accepted in two consecutive rounds (the fix is not
  converging — a third attempt will not help).

### Job 3 — Land, then advance

Covered in the next two sections. The maintainer does not decide *whether the
work is good enough*; it checks conditions and commits, or refuses and says
which condition failed.

### Prohibitions

- Never adds findings the reviewer did not report; never rewrites a finding into
  a different problem.
- Never edits code, tests, or `REVIEW_POLICY.md`. Policy changes are yours.
- Never resolves an escalation by guessing. Escalation is a cheap, correct
  outcome.
- Never runs git directly. Its only write path is `land.sh`.

---

## Landing

The maintainer commits. This is the whole point of the role — but the authority
is deliberately shaped so that "commit" means one specific, checkable thing.

### The contract

`land.sh` refuses — exit 3, naming the condition — unless **all eight** hold:

| # | Condition | Why |
|---|-----------|-----|
| 1 | The run directory is a completed review run | An empty directory must never authorise a commit |
| 2 | The run's tree fingerprint matches the tree now | A review of a tree that has since changed is not a review of what is being committed |
| 3 | Gates re-run green **now** | Cheap insurance; catches a drifted environment |
| 4 | Zero accepted findings at or above the run's threshold | Nothing outstanding |
| 5 | Zero pending escalations | A human owes an answer |
| 6 | Changed files ⊆ the task's declared scope | The diff did not sprawl |
| 7 | Every exit criterion carries a `verified_by` claim | The tracker's definition of done, with the claim recorded in the commit |
| 8 | Branch is neither protected nor detached | Landing never touches trunk, and never makes an unreachable commit |

Then one switch, which is **not** a refusal: `LANDING` in `.review/land.conf`.
With `LANDING=on` the eight checks are followed by a commit; with `LANDING=off`
they are followed by the exact `git` commands printed for you to run, and the
exit code is 0. Every check runs either way — turning landing off removes the
commit, never the contract. That is why `off` is the shipped default: you get
the full pipeline before you delegate anything.

**Condition 7 is the one with no mechanical backing.** It checks that a claim
was *made*, not that it is true. `.review/` is excluded from the tree
fingerprint on purpose — the task file is filled in after the review, and
including it would invalidate every run before it could land — so nothing stops
a false claim but the person writing it. It is an auditable assertion, not a
proof. Anything genuinely checkable belongs in a gate, not in a criterion.

Conditions 1, 2, and 4 exist because the dangerous failure is not a wrong
judgment — it is a **missing** one reading as approval. An unreadable count, an
absent artifact, or a stale run must refuse, never default to zero.

Then, and only then, it stages **exactly the in-scope files** — never
`git add -A` — and commits with trailers linking the task and the review run.

The commit is `git commit --only -- <in-scope files>`, not a bare `git commit`.
A bare commit writes the whole index, so anything the user had staged when the
loop ran would ride along inside the task's commit without ever being
scope-checked — `.review/land.conf` and `.review/REVIEW_POLICY.md` most of all,
since they are filtered out of the changed-file list by design. The files that
define this pipeline's limits must not be able to change inside a commit the
pipeline made on its own. Whatever the user had staged stays staged, untouched.

### What landing cannot do

`land.sh` has no code path for `push`, `amend`, `--force`, `rebase`,
`checkout`, `reset`, `stash`, or `clean`. It commits on the current branch or it
fails. Trunk, history, and the remote are never touched by an agent.

### Why the authority is a script, not a permission

Agents get **no write-git permission by policy**. `.claude/settings.json` denies
the mutating `git` subcommands and their flag forms, and pre-approves one
command so it does not prompt: `land.sh`. That allow entry is a convenience, not
the boundary — `run.sh`, `gates.sh`, tests and linters are ordinary `Bash` calls
under the project's normal permission settings. What makes `land.sh` special is
that it is the only one that can write to git at all.

Be precise about what this is: permission patterns match by prefix, so the list
covers the invocations an agent would actually write, not every syntactically
possible one. It is a strong guardrail, not a sandbox. The structural guarantees
are elsewhere — the maintainer's tool grant, and the fact that `land.sh` cannot
push, amend, force, or switch branches no matter who calls it. The
agent's power is then the *script's semantics*, not git's surface area — and the
script lives in the CodingStandards submodule, so a project cannot quietly widen
it.

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
      "Bash(git filter-branch:*)", "Bash(git replace:*)",
      "Bash(git -C:*)", "Bash(git --git-dir:*)", "Bash(git --work-tree:*)",
      "Bash(git -c:*)", "Bash(git commit-tree:*)", "Bash(git symbolic-ref:*)",
      "Bash(git read-tree:*)", "Bash(git update-index:*)", "Bash(git bisect:*)",
      "Bash(git sparse-checkout:*)", "Bash(git clone:*)", "Bash(git init:*)",
      "Bash(git checkout-index:*)", "Bash(git stripspace:*)"
    ],
    "allow": [
      "Bash(CodingStandards/templates/review/lib/land.sh:*)",
      "Bash(./CodingStandards/templates/review/lib/land.sh:*)"
    ]
  }
}
```

The allow entries are literal command prefixes, so they only match the form the
command is actually typed in. `/maintain` invokes both scripts as
`CodingStandards/templates/review/lib/...` from the project root — the first
entry. The `./` variant is there because it is the other way people type it; an
absolute path matches neither and will prompt. That prompt is a nuisance, never
a hole: the deny list is what carries the guarantee, and an allow entry that
fails to match only costs a confirmation.

Keep this list in step with the prohibitions in
[EXECUTION_GUIDE.md](./EXECUTION_GUIDE.md#git-is-read-only): a subcommand that
is forbidden in prose but absent from the deny list is not forbidden at all.

`LANDING=off` in `.review/land.conf` is the kill switch: the pipeline then runs
to completion and prints the commit command for you instead of running it.

### Interactive work is different

This delegation is scoped to the pipeline. Outside it — in an ordinary chat
session — git stays read-only for agents, no exceptions. See
[EXECUTION_GUIDE.md](./EXECUTION_GUIDE.md#git-is-read-only). The difference is
not the tool, it is that landing is a contract you defined, enabled, and can
revoke, and the pipeline reaches it only through the eight conditions above.

---

## Advancing

After landing, the maintainer either asks you or takes the next task. **You
review tasks, not commits.**

### The starting mode: ask every time

`ADVANCE=ask` — the default, and where every project begins.

The maintainer presents the finished task: what changed, which findings were
accepted and how they were addressed, which were rejected and why, and the gate
results. You accept, or you object. On acceptance it takes the next unblocked
task from the tracker and starts the loop again.

You are looking at the *task*, not the diff of each commit. If the summary looks
right, that is enough.

### The goal: learn when not to ask

**Your silence is training data.** A task you accepted with no remarks is a
labeled example: work of this shape did not need your attention. Enough of those
in one category and the maintainer can stop asking about that category.

The decision is *not* "is this code good" — gates and review already answered
that. It is "is this task trivial enough that a human would have nothing to
say". That judgment runs on deterministic signals — diff size, paths touched,
findings raised, rounds used, whether behaviour changed without a test, the task
category, and your history in those paths. The signal table lives in
[MAINTAINER_TRAINING.md § Signals, not vibes](./MAINTAINER_TRAINING.md#signals-not-vibes)
and is not repeated here: two copies of it had already drifted apart.

`ADVANCE=auto` unlocks per-category, never globally: the maintainer advances
without asking only inside categories with a proven record, and asks about
everything else. `MAINTAINER_TRAINING.md` covers the thresholds, the metric that
governs them (precision of auto-advance — of the tasks it did not show you, how
many you would have objected to), and the rollback rule.

### The asymmetry that sets the thresholds

Asking too often costs you a few seconds. Advancing past a task you should have
seen costs a defect that nobody looked at, buried under later commits. Set the
thresholds accordingly: conservative, per-category, and reverting to `ask` the
moment you object to something that was auto-advanced.

---

## Project Setup

This repo is consumed as a git submodule at `CodingStandards/` in the host
project. **Nothing inside the submodule is ever edited** — it is a shared
library, and edits there are overwritten on the next
`git submodule update --remote` or leak into every other project.

So the pipeline splits by ownership:

| Part | Lives in | Edited | Why there |
|------|----------|--------|-----------|
| `run.sh`, `land.sh`, prompts, schemas | submodule — `CodingStandards/templates/review/lib/` | Never | Identical everywhere; `land.sh` in particular must not be widened by a project |
| `gates.sh` | project — `.review/` | Always | Encodes the stack — the one language-specific file |
| `REVIEW_POLICY.md` | project — `.review/` | Constantly | Your taste, this codebase |
| `land.conf` | project — `.review/` | Rarely | Landing and advancing switches |
| `decisions/`, `eval/` | project — `.review/` | Constantly | Your decisions, your golden set |
| Subagents | project — `.claude/agents/` | Rarely | Claude Code only discovers them there |

```
my-project/
├── CodingStandards/                     # submodule — read-only
│   └── templates/review/
│       ├── lib/                         # runs from here
│       │   ├── run.sh                   # one review pass (gates, review, triage)
│       │   ├── land.sh                  # the only thing that commits
│       │   ├── prompts/{reviewer,maintainer}.md
│       │   └── schemas/*.json
│       └── project/                     # copied once into .review/
├── .review/                             # yours, versioned in this repo
│   ├── gates.sh                         # ← the only file you must fill in
│   ├── land.conf                        # ← LANDING / ADVANCE switches
│   ├── REVIEW_POLICY.md                 # ← grows with every disagreement
│   ├── current-task.json                # the task in flight — scope, exit criteria
│   ├── decisions/{findings,tasks,escalations}.jsonl
│   ├── eval/golden.jsonl                # your verdicts, for /policy --eval
│   └── runs/                            # per-run artifacts — gitignored
└── .claude/agents/{diff-reviewer,maintainer}.md
```

### Install

```bash
git submodule add https://github.com/x128/CodingStandards.git CodingStandards
mkdir -p .review .claude/agents
cp -r CodingStandards/templates/review/project/. .review/
cp CodingStandards/templates/agents/*.md .claude/agents/
for f in decisions/findings decisions/tasks decisions/escalations eval/golden; do
  mv ".review/$f.example.jsonl" ".review/$f.jsonl"
done
chmod +x .review/gates.sh
echo '.review/runs/' >> .gitignore
```

Then, in order:

1. **Fill in `.review/gates.sh`** — the five slots. See
   [Wiring a new language](#wiring-a-new-language).
2. **Add the permissions block above** to `.claude/settings.json`.
3. **Paste `.review/CLAUDE.snippet.md` into the project's `CLAUDE.md`.** This
   is the step that is easy to skip and expensive to skip: without it, "do the
   next task" is a request to edit files and the pipeline sits there unused. A
   project that installs everything else and omits this has a loop nobody
   invokes.
4. **Run a task.** `/maintain` writes `.review/current-task.json` itself, from
   the tracker entry. For a manual pass, start from the template:
   `cp .review/task.example.json .review/current-task.json` and fill in `id`,
   `scope`, and `exit_criteria`.

```bash
# the loop is driven by the /maintain skill, which calls run.sh and land.sh
/maintain --task T-001
```

`/maintain --init` does all four, including detecting the stack and writing the
gate commands.

The block sets a **default**, not a rule for the user: any change can be made
outside the pipeline, on request, without justification
([EXECUTION_GUIDE.md § Who runs the work](./EXECUTION_GUIDE.md#who-runs-the-work)
states this in full, and `skills/maintain.md` and the snippet repeat it to the
agents that need to hear it — the one duplication in this repo that is on
purpose).

### Overriding a shared file

`run.sh` prefers `.review/<path>` over the submodule's copy, so a project can
override a prompt or schema by copying just that file. `land.sh` is deliberately
**not** overridable — it is the one file with write authority.

Prefer contributing improvements back to the submodule; an override is a fork
you now maintain. Project-specific *content* (rules, examples) belongs in
`.review/REVIEW_POLICY.md`, which is already in the maintainer's context.

### Hooks

Use hooks for invariants, never for logic:

- `PostToolUse` on edits → format and lint gates. Formatting must never reach
  the reviewer as a finding.
- `Stop` → refuse to finish while build or test is red.

---

## Failure Modes

| Symptom | Cause | Fix |
|---------|-------|-----|
| Diffs balloon after review | Threshold too low; nits reaching the executor | Accept `major`+ only |
| Reviewer invents bugs in correct code | Bug-prior pattern matching | Enforce quote + counterexample; reject `possible` without evidence |
| Maintainer agrees with everything | Same model/context as the reviewer | Different model per role; fresh session |
| Same finding every run | Missing policy rule | Write the rule — or better, encode it as a lint rule in Layer 0 |
| Landed commits you would have rejected | `ADVANCE=auto` too broad | Revert that category to `ask`; tighten thresholds |
| Landing refused and nobody knows why | Contract failure not surfaced | `land.sh` names the failing condition — read it, do not bypass it |
| Maintainer metrics improve, real quality doesn't | Reward hacking in the loop | Re-separate roles, tighten the round limit, strengthen Layer 0 |
| Cost per task is high | Broad scope | Narrow the task; diff + touched deps only; cheap model for triage |

---

## Summary Checklist

- [ ] Layer 0 exists first: build, test, format, lint, arch — one command each
- [ ] Gates run before the reviewer, and again at landing
- [ ] Reviewer sees the diff and touched dependencies only
- [ ] Reviewer output is schema-validated JSON with quote and evidence
- [ ] Quotes are script-verified against source; mismatches are dropped
- [ ] `severity` derived from rule level, never asked of the model
- [ ] A finding contradicting a green gate is always rejected
- [ ] Only `accept` + `severity ≥ major` reaches the executor
- [ ] Different model per role; fresh session per role
- [ ] Hard limit of 2 rounds, with an oscillation stop
- [ ] Landing passes all eight conditions or fails loudly
- [ ] Missing or malformed pipeline output fails closed, never as "nothing found"
- [ ] Agents have no write-git permission; `land.sh` is the only allowed command
- [ ] `land.sh` never pushes, amends, forces, or switches branches
- [ ] `LANDING=off` kill switch works and is documented
- [ ] `ADVANCE=ask` until a category has a proven record
- [ ] Every task boundary is logged: signals + your decision
- [ ] Auto-advance precision is measured; one objection reverts a category
