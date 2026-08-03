# Coding Standards

Reusable coding standards and Claude Code skills for consistent, clean code across projects.

## Standards

| Document | Description |
|----------|-------------|
| [CLEAN_CODE.md](./CLEAN_CODE.md) | Language-agnostic clean code principles (SOLID, DRY, naming, etc.) |
| [KOTLIN.md](./KOTLIN.md) | Kotlin / KMP coding standards |
| [SWIFT.md](./SWIFT.md) | Swift / iOS coding standards |
| [ARCHITECTURE.md](./ARCHITECTURE.md) | Clean Architecture, package organization, presentation patterns |
| [TESTING.md](./TESTING.md) | Testing pyramid, conventions, per-layer strategies |
| [KOTLIN_MULTIPLATFORM.md](./KOTLIN_MULTIPLATFORM.md) | KMP project init, test locations, runners, frameworks |
| [PLANNING_GUIDE.md](./PLANNING_GUIDE.md) | Product planning process: intake, implementation plans, task trackers |
| [EXECUTION_GUIDE.md](./EXECUTION_GUIDE.md) | Rules for getting a task from to-do to committed — whoever does the work |
| [TASK_LOOP.md](./TASK_LOOP.md) | The machine that runs task work: gates, executor, reviewer, maintainer, landing, advancing |
| [MAINTAINER_TRAINING.md](./MAINTAINER_TRAINING.md) | Teaching the maintainer: which findings matter, and when not to ask you |

## Skills

Claude Code skills (slash commands) for enforcing standards:

| Skill | Command | Purpose |
|-------|---------|---------|
| [review](./skills/review.md) | `/review` | Hunt inconsistencies, potential problems, and complications |
| [refactor](./skills/refactor.md) | `/refactor` | Guided refactoring with patterns |
| [test](./skills/test.md) | `/test` | Test generation with best practices |
| [document](./skills/document.md) | `/document` | Documentation generation |
| [theory](./skills/theory.md) | `/theory` | Theoretical foundation (THEORY.md) generation |
| [maintain](./skills/maintain.md) | `/maintain` | Run or set up the task loop: review, land, advance |
| [policy](./skills/policy.md) | `/policy` | Turn a disagreement with the maintainer into a rule or threshold |

## Templates

Copy-and-fill starting points, not documentation:

| Template | Copy to | Purpose |
|----------|---------|---------|
| [templates/review/lib/](./templates/review/lib/) | — runs from the submodule | Orchestrator, landing script, prompts, schemas. Never copied, never edited |
| [templates/review/project/](./templates/review/project/) | `.review/` | Gates, policy, landing config, decision logs — yours to edit |
| [templates/agents/](./templates/agents/) | `.claude/agents/` | `diff-reviewer` and `maintainer` subagents |

## Usage

### Starting a new project

This repo is consumed as a **git submodule at `CodingStandards/`**, so every
path below is relative to your project root. Add it first:

```bash
git submodule add https://github.com/x128/CodingStandards.git CodingStandards
```

**HTTPS on purpose.** That URL is written into your project's `.gitmodules` and
is then used by everyone who clones it, CI included — an SSH URL there makes a
GitHub key a hard requirement for building the project. This repo is public, so
HTTPS needs no credentials at all. If you personally prefer SSH, keep the
portable URL and rewrite it locally, once, for every repo you touch:

```bash
git config --global url."git@github.com:".insteadOf https://github.com/
```

Then paste this prompt. It is the whole setup — standards wiring and the task
loop in one pass:

```text
Read CodingStandards/CLAUDE.md and CodingStandards/TASK_LOOP.md, then set this
project up to use those standards.

1. Write this project's CLAUDE.md, referencing the standards by submodule path:
   CLEAN_CODE.md, ARCHITECTURE.md, TESTING.md, and the language standard for
   this stack (KOTLIN.md or SWIFT.md). If there is no standard for this
   language, say so plainly and use the language-agnostic three.
2. Run /maintain --init to set up the review loop: detect the stack, fill in
   .review/gates.sh, wire permissions, and install the routing block.

Report back: the five gate commands, the risk paths, any gate slot you could not
fill and why, and confirmation that the routing block is in CLAUDE.md. Do not
write any feature code yet.
```

Two things in that prompt are load-bearing. **The routing block** is what makes
later requests run the loop instead of ad-hoc edits — a setup that skips it
leaves a pipeline nobody invokes. **"Do not write any feature code yet"** keeps
setup from sliding into implementation before you have looked at the gates.

Landing starts at `LANDING=off` on purpose: the loop runs end to end and prints
the commit instead of making it. Turn it on in `.review/land.conf` once you have
watched a few refusals behave.

### If the project is a new product, not just a new repo

Plan before there are tasks to run:

```text
Follow CodingStandards/PLANNING_GUIDE.md. Ask me the intake questions first,
then write the implementation plan and the task tracker. No code yet.
```

### Running work after setup

```text
Do the next task.
```

That is the whole trigger — the routing block turns any request to do task work
into a full loop run (gates → review → triage → fix rounds → landing), not just
an edit. You do not type `/maintain`, and there is no magic phrase: "next task",
"do T-014", and "continue" all enter the same path.

The loop is the **default**, never an obligation. "Just make this change", "skip
the review", "I'll write this one myself" are complete instructions — see
[EXECUTION_GUIDE.md § Who runs the work](./EXECUTION_GUIDE.md#who-runs-the-work).

### Example project structure

```
MyApp/
├── CodingStandards/          # this repo, as a submodule — never edited here
│   ├── CLEAN_CODE.md
│   ├── KOTLIN.md
│   ├── TASK_LOOP.md
│   ├── skills/
│   └── templates/
├── .review/                  # copied out of templates/ — yours to edit
│   ├── gates.sh              # the only file that knows your language
│   ├── land.conf
│   ├── REVIEW_POLICY.md
│   └── decisions/            # findings, tasks, escalations — the training log
├── .claude/
│   ├── agents/               # diff-reviewer, maintainer
│   └── settings.json         # write-git deny list
└── CLAUDE.md                 # standards references + the routing block
```

## What's Covered

### CLEAN_CODE.md
- Naming conventions
- Function design (single responsibility, minimal parameters)
- Class design (cohesion, encapsulation)
- SOLID principles
- DRY, KISS, YAGNI
- Error handling
- Testing principles
- Code smells reference

### Language Standards
- Naming conventions
- Null safety
- Error handling patterns
- State management
- Async/concurrency
- Collections
- Testing patterns
- Summary checklists

### ARCHITECTURE.md
- Clean Architecture layers
- Package organization
- Presentation patterns (MVI/MVVM)

### TESTING.md
- Testing pyramid and conventions
- Per-layer test strategies
- Test naming and structure

### KOTLIN_MULTIPLATFORM.md
- KMP project initialization (submodule, versions, Gradle setup)
- Test locations and runners
- Platform frameworks

### PLANNING_GUIDE.md
- Intake questions for new products
- Implementation plan structure and rules
- Task tracker format and conventions
- Cross-check and maintenance process

### EXECUTION_GUIDE.md
- Rules that hold by hand, on request, and inside the loop alike
- One task at a time — never batch
- Git is read-only, with one delegated exception
- The task boundary and the definition of done belong to the user

### TASK_LOOP.md
- What it is built on: execution rules, review, gates — none of which it replaces
- Three roles: executor, reviewer, maintainer — on deterministic gates
- Layer 0 gate slots and how to wire them for any language
- JSON contracts for findings and verdicts
- Triage rules, round limits, escalation
- Landing: the eight conditions, and why commit authority is a script
- Findings are pointers, not instructions — over-fitting to the reviewer
- Advancing: when the maintainer may take the next task without asking

### MAINTAINER_TRAINING.md
- Track A — which findings matter: decision log, policy rules, double commit
- Track B — when not to ask: task-boundary signals, shadow metric, unlocking
- Delayed feedback: provisional vs confirmed acceptance, retraction
- Replication: the third-occurrence trigger — refactor before the task, not after
- Attribution: concrete triggers for tracing a symptom to the task that introduced it
- Eval loop: agreement rate, blocker recall, auto-advance precision
- Prompt optimization, and why fine-tuning is usually the wrong tool
