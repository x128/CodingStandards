# Coding Standards

Reusable coding standards and agent skills for consistent, clean code across projects.

## Standards

Every project follows PLANNING_GUIDE, CLEAN_CODE, ARCHITECTURE, TESTING and EXECUTION_GUIDE, and the
documents of its stack: KOTLIN for Kotlin, KOTLIN_MULTIPLATFORM for KMP, SWIFT where it has iOS, CPP
for a C++ core. A language with no document here follows the language-agnostic ones. TASK_LOOP is
for a project that runs the loop.

| Document | Description |
|----------|-------------|
| [PLANNING_GUIDE.md](./PLANNING_GUIDE.md) | **First.** Product planning: intake, requirements, plan, task tracker — before any code |
| [CLEAN_CODE.md](./CLEAN_CODE.md) | Language-agnostic clean code principles (SOLID, DRY, naming, etc.) |
| [KOTLIN.md](./KOTLIN.md) | Kotlin / KMP coding standards |
| [SWIFT.md](./SWIFT.md) | Swift / iOS coding standards |
| [CPP.md](./CPP.md) | C++ core under native apps: the code owner's decisions, asked before the C++ code is written |
| [ARCHITECTURE.md](./ARCHITECTURE.md) | Clean Architecture, package organization, presentation patterns |
| [TESTING.md](./TESTING.md) | Testing pyramid, conventions, per-layer strategies |
| [KOTLIN_MULTIPLATFORM.md](./KOTLIN_MULTIPLATFORM.md) | KMP project init, test locations, runners, frameworks |
| [EXECUTION_GUIDE.md](./EXECUTION_GUIDE.md) | Rules for getting a task from to-do to committed — whoever does the work |
| [TASK_LOOP.md](./TASK_LOOP.md) | The machine that runs task work: gates, executor, reviewer, maintainer, landing, advancing |
| [MAINTAINER_TRAINING.md](./MAINTAINER_TRAINING.md) | How a correction becomes a rule, and which file it goes in |

## Skills

Skills for enforcing standards, in the open Agent Skills format (Claude Code, Codex, Gemini CLI and
others): see [.agents/skills/README.md](./.agents/skills/README.md).

## Templates

Copy-and-fill starting points, not documentation:

| Template | Copy to | Purpose |
|----------|---------|---------|
| [templates/review/lib/](./templates/review/lib/) | — runs from the submodule | Orchestrator, landing scripts, `triage.py`, prompts, schemas. Never copied, never edited |
| [templates/review/project/](./templates/review/project/) | `.review/` | Gates, policy, landing config, decision logs — yours to edit |
| [templates/agents/](./templates/agents/) | `.claude/agents/`, `.claude/` | `reviewer` and `maintainer` subagents; `agents.conf`, the model of each role |
| [templates/self-improve/](./templates/self-improve/) | — `setup.sh` copies the tools into the work folder | Tools, workflows and an example project for `/self-improve`. Never copied into a project that is measured |

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

Before you start the agent, run the command of
[.agents/skills/README.md](./.agents/skills/README.md), "Setup", in the project root: it links the
skills and starts `AGENTS.md` with the line that has every reply written with `/write`. Then paste
this prompt. It is the whole setup — standards wiring and the task loop in one pass:

```text
Read CodingStandards/AGENTS.md and CodingStandards/TASK_LOOP.md, then set this
project up to use those standards.

1. Follow PLANNING_GUIDE.md Steps 0-3 first: ask me the intake questions, then
   write REQUIREMENTS.md, PLAN.md and TASK_TRACKER.md. If I say they already
   exist, show me the files.
2. Complete this project's AGENTS.md as PLANNING_GUIDE.md, Step 4, shows.
3. Run /maintain --init to set up the review loop: detect the stack, fill in
   .review/gates.sh, and wire permissions.
4. Stop and list the files of the first commit for me to commit: the
   requirements, the plan, the tracker, AGENTS.md, .claude/skills/,
   .agents/skills/, and the files /maintain --init wrote. No feature code is in
   them.

Report back, starting with what I have to do: the files to commit, and any check
you could not fill and why. Then the requirements, plan and tracker paths, the
five checks that run on every task with their commands, and the risk paths.
Do not write any feature code yet.
```

Two things in that prompt are load-bearing. **Step 1 comes first and produces
files** — planning that stays in the conversation leaves nothing for the loop or
a later reviewer to read ([PLANNING_GUIDE.md](./PLANNING_GUIDE.md) Steps 1–2).
**"Do not write any feature code yet"** keeps setup from sliding into
implementation before you have looked at the gates.

Landing is what you answered to "Who writes to git" in the requirements, and `/maintain --init`
writes it to `.review/land.conf`. At `off` the loop runs end to end and prints the commit instead of
making it; at `push`, `pr` and `merge` it commits on a branch and takes that branch as far as you
said. The loop reaches main only through a pull request, never a direct commit.

### If the code already exists

An inherited repo, or one built before these standards, has no requirements, no plan and no
tracker — so nothing can tell a defect from work never started. Reconstruct the intent before
reviewing or running the loop:

```text
Follow CodingStandards/PLANNING_GUIDE.md Steps 1-2, reconstructing the
requirements, the plan and the tracker from the existing code and AGENTS.md or CLAUDE.md.
Ask me about anything the code does not settle. No code changes yet.
```

### Running work after setup

```text
Do the next task.
```

That is the whole trigger — `/maintain`'s description makes any request to do
task work start a full loop run (gates → review → triage → fix rounds →
landing), not just an edit. You do not type `/maintain`, and there is no magic
phrase: "next task", "do T-014", and "continue" all start it.

The loop is the **default**, never an obligation. "Just make this change", "skip
the review", "I'll write this one myself" are complete instructions — see
[EXECUTION_GUIDE.md § Who runs the work](./EXECUTION_GUIDE.md#who-runs-the-work).

### Example project structure

```
MyApp/
├── CodingStandards/          # this repo, as a submodule
│   ├── CLEAN_CODE.md
│   ├── KOTLIN.md
│   ├── TASK_LOOP.md
│   ├── .agents/skills/
│   └── templates/
├── .review/                  # copied out of templates/ — yours to edit
│   ├── gates.sh              # the only file that knows your language
│   ├── land.conf
│   ├── REVIEW_POLICY.md
│   └── decisions/            # findings, tasks, escalations — the training log
├── .claude/
│   ├── agents/               # reviewer, maintainer
│   └── settings.json         # write-git deny list
└── AGENTS.md                 # the product, where the plan is, the standards
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
- Requirements and plan: structure and rules
- Task tracker format and conventions
- Cross-check and maintenance process

### EXECUTION_GUIDE.md
- Rules that hold by hand, on request, and inside the loop alike
- One task at a time — never batch
- How far the loop takes a finished task is the project's decision (the requirement "Who writes to
  git"); outside the loop git is read-only for agents
- The task boundary and the definition of done belong to the user
- A review's findings: whoever wrote the change answers each; none is an instruction
- Reporting: the user's terms, ranked by what blocks the product, findings in a file

### TASK_LOOP.md
- What it is built on: execution rules, review, gates — none of which it replaces
- Three roles: executor, reviewer, maintainer — on deterministic gates
- Layer 0 gate slots and how to wire them for any language
- JSON contracts for findings and verdicts
- Triage rules, round limits, escalation
- Landing: how far the loop goes, the eight conditions, and why the authority is in two scripts
- Findings are pointers, not instructions — over-fitting to the reviewer
- Advancing: when the maintainer may take the next task without asking

### MAINTAINER_TRAINING.md
- Why a correction has to be a file in git, not something a session remembers
- File it by the moment it happens, not by its topic — the table of moments
- What never becomes a rule: a "not yet", a count of rejections, a threshold for not asking
- The user is not an agent: nothing decides whether they look
- The two calls on a review: is it about the right thing, is anything left
- This project's rule versus the standard, and what it takes to move up
