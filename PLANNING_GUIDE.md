# Product Planning Guide

> How to go from a raw idea to a well-structured implementation plan and task
> tracker. This guide captures the process, rules, and formatting conventions.

**Follow steps 0–4 in order. Report which step you are on as you progress.
Planning produces: implementation plan, task tracker, CLAUDE.md, and
CodingStandards submodule. After Step 4 the planning process is complete.
Task execution starts with T-001.**

---

## Step 0: Intake Questions

Before writing anything, ask 10–20 targeted questions to extract what would
otherwise take hours of back-and-forth. Don't ask obvious or generic
questions — only ones whose answers materially change the plan.

### Always ask:

**Product vision**

1. One sentence: what does the product do?
2. What's the core insight — why is this approach better than what exists?
3. Who is the user? (expertise level, context, device)
4. What is the user's emotional journey? (what should they feel?)

**Platforms & core model**

5. What platforms? (mobile, desktop, web, all)
6. Online, offline, or hybrid? Any hard constraints?
7. What's the core data model? (what are the "nouns" of the system?)
8. What's the primary interaction loop? (what does the user do repeatedly?)

**Scope & philosophy**

9. What is explicitly NOT in MVP? (name 3+ things you're tempted to include)
10. What's the relationship between the user and AI (if any)?
11. Are there external stakeholders who interact with the output?

**UX & feel**

12. Should it feel like a game, a tool, a conversation, or something else?
13. How does the user see progress?
14. What's the smallest unit of user decision?

**Tech preferences**

15. Any strong tech stack preferences or constraints?
16. What's the deployment model?
17. Any AI/ML components? What size/where?

**Architecture, comments, commits** — asked as written in "The questions of D-002, D-003 and D-004"

18. Architecture: D-002.
19. Comments: D-003.
20. Commits: D-004.

### Ask if relevant:

- Does the product have a versioning/history model?
- Is collaboration involved? How?
- What export formats matter?
- Are there regulatory or compliance concerns?
- Is there a "done" state, or is the product a living process?

**Stop asking when you have enough to write the philosophy section.** The questions of
"Architecture, comments, commits" are asked all the same, on top of the 10–20, except one the user
has already answered.

### How the questions are asked

**A block at a time, in the order above.** Each group of "Always ask" is one block; a question of
"Ask if relevant" joins the block of its topic, and a block with nothing left to ask is skipped.
A question with answers to choose from goes on a card of the question tool (AskUserQuestion;
without it, a numbered list in the chat), four to a card, and a card holds the questions of one
block only. An open question, such as what the product does, is asked as text in the chat, and the
card of its block comes after the user's answer: options made up for an open question would be
guesses that read as already settled, as Step 4 says of the package name. The decisions every
project makes are never moved into an earlier block, nor asked next to the package name of
Step 4. Asked among the first questions about a project, a question about use cases comes from
nowhere; asked after the product is described, it has something to stand on.

**A card is all the user sees.** While a card is open, the text written before it is out of
sight, and an app may show one question of the card at a time, without its header or the
preview of an option. So the first question of each card opens with its topic in a few plain
words, such as "Now about where the app runs.", and every question says in its own text what it
asks about. Each question other than those of D-002, D-003 and D-004 is written as
[skills/write](./skills/write/SKILL.md) says.

### The questions of D-002, D-003 and D-004

Wherever these decisions are asked, they are asked on a card of their own, and the text below is
copied, not written again: as it is for a user who writes in English, translated sentence by
sentence for another language. Nothing is added or cut, and no example from the product goes in. A
translation keeps ViewModel, use case and Arrange / Act / Assert in English. In a project with no
screens, the screens and ViewModels of the text become the classes that call the use cases, such as
command handlers.

**D-002**

> Now let's talk a bit about the app's architecture. I will build the app in three layers:
>
> ```
> Presentation: screens with ViewModels  →  Domain: use cases  ←  Data: repositories
> ```
>
> Where there is business logic, there is a use case. Where there is no logic, does the ViewModel
> call the repository directly, or still go through a use case? This rule is for the whole app.

- *Directly to the repository*: a use case only where there is logic. Fewer classes, but a
  ViewModel may call both use cases and repositories.
- *Always through a use case*: even if the use case is one line. A ViewModel calls only use cases,
  but there are more classes.

**D-003**

> Comments in the code: by default there are none, except markers in tests such as
> Arrange / Act / Assert. Keep it that way?

- *Yes, no comments (Recommended)*: names and tests say what the code does.
- *Some are needed*: for example, a license header in every file. I will ask which and where.

When the user picks the second, the kinds and their places are asked as text and written into the row.

**D-004**

> Who makes commits: only you, or the agents too? You can change this at any time.

- *Only I commit*: agents only read git. You look at every change and commit it yourself.
- *Agents commit too*: an agent commits each task that passes checks and review; you look at it
  after. Only on your branch, never on main or master, no push. You turn it on yourself, with
  `LANDING=on` in `.review/land.conf`.

---

## Step 1: Write the Implementation Plan

The plan is a **strategy document**. It describes *what* and *why*.
Implementation detail belongs in the task tracker. The plan should read like
a manifesto — someone can understand the entire product without seeing tasks.

### Sample

```markdown
# [Product Name] — Product & Implementation Plan

> One-paragraph abstract: what it is, what makes it special, platform list.
> Bold statement of direction.
> "Why this beats X" — the competitive insight in 3–4 sentences.

---

## Table of Contents

1. Core Philosophy
2. [Core interaction model — product-specific name]
3. [Domain model — product-specific name]
4. [State / progress model — product-specific name]
5. [UX flow — product-specific name]
6. Use Cases (MVP)
7. [Domain taxonomy / schema — product-specific name]
8. Architecture
9. Epics & Tasks
10. Decisions Log
11. Risk Register
12. Tech Stack
13. Success Metrics

---

## 1. Core Philosophy

### 1.1 [First principle]

Explanation of a non-obvious design choice. 3–6 principles total.

### 1.2 [Second principle]
...

---

## 2. [Core Interaction Model]

Diagram(s) of primary flows. ASCII art is fine.

---

## 3. [Domain Model]

The conceptual model — vocabulary, "nouns", relationships.
NOT implementation classes — the user's mental model.

---

## 4. [State / Progress Model]

How the system tracks where the user is, what's decided, what hasn't.

---

## 5. [UX Flow]

The emotional journey. What motivates the user.

---

## 6. Use Cases (MVP)

### UC1: [Name]
**Input**: ...
**Output**: ...; or [each other outcome, by name]
**Rules**:
1. ...
2. ...

(Every use case has this form: a name, an input, an output that names
every outcome, and rules, in the words of the product's subject. A filled
example is in `ARCHITECTURE.md`, "Use Cases".)

---

## 7. [Domain Taxonomy]

Detailed data categories, items, types, examples. Tables work well here.

---

## 8. Architecture

System diagram (ASCII), component descriptions, key interfaces.

---

## 9. Epics & Tasks

→ All task detail in TASK_TRACKER.md

### [Epic Name]
- [ ] T-001 Task title
- [ ] T-002 Task title

### [Another Epic]
- [ ] T-003 Task title

### Post-MVP: [Theme]
- [ ] F-001 Feature title

---

## 10. Decisions Log

| ID | Decision | Options | Chosen | Rationale |
|----|----------|---------|--------|-----------|
| D-001 | ... | ... | TBD in T-NNN | ... |
| D-002 | A request with nothing to check or decide, such as "read a list and show it". Every project must make this decision | (a) the caller uses the interface that the domain layer declares, and no use case is written; (b) a use case whose body is that one call, and callers use only use cases | (a) or (b) | ... |
| D-003 | Comments in the code. Every project must make this decision | (a) none besides the test markers (`// Arrange`, `// Act`, `// Assert`, or `// Given`, `// When`, `// Then`); (b) the test markers and only the kinds named here, only where named here, such as a license header in every file | (a), unless the project has a reason for (b) | ... |
| D-004 | Who writes to git. Every project must make this decision | (a) agents only read git; the user commits; (b) the same, and the loop of `TASK_LOOP.md` also commits, through `land.sh` with `LANDING=on`, after its checks | Asked at intake: the user's preference, not a rule of the standards; the user may change it at any time | ... |

---

## 11. Risk Register

| # | Risk | Impact | Likelihood | Mitigation |
|---|------|--------|------------|------------|
| R1 | ... | ... | ... | ... |

---

## 12. Tech Stack

| Component | Library | Module |
|-----------|---------|--------|
| ... | ... | ... |

---

## 13. Success Metrics

| Metric | Target |
|--------|--------|
| ... | (number or binary outcome) |

Targets must be grounded in domain knowledge, industry benchmarks, or
experience — not invented. Revise iteratively as real usage data comes in.
```

### Plan Rules

**Decisions every project makes.** D-002, D-003 and D-004 of the sample log are decisions every
project records, and the standards name them by these numbers. In a log that already uses one of
these numbers for something else, the decision takes the number after the highest one in the log and keeps its Decision
text, and the project's `CLAUDE.md` says which number it has (Step 4).

- **Philosophy**: 3–6 named principles, each a non-obvious design choice
- **Use cases**: short — name, input, output that names every outcome, and
  at most 7 numbered rules, in the words of the subject. Not one per user action
- **Epics & Tasks**: reference index only — `- [ ] T-NNN Title`, grouped
  by epic. Post-MVP uses `F-NNN`. No descriptions here.
- **Decisions log**: pre-populate TBDs, reference the task where each
  decision will be made
- **Success metrics**: grounded in real data. If no analytics exist yet,
  replace this section with a task reference
- **Research**: always include a Research epic. Populate based on what's
  relevant: domain research, competitor analysis, market research (target
  audience, pricing, distribution)
- **No week numbers** in epic names
- **Theoretical foundation** (ML/AI projects): generate THEORY.md via the
  `/theory` skill

**Write it to `IMPLEMENTATION_PLAN.md` at the project root before moving on.**
Step 4 explains why this is the step that gets skipped and what it costs.

---

## Step 2: Write the Task Tracker

The tracker is the **single source of truth for all work**. Every task
(MVP and post-MVP) lives here with full detail.

### Sample

```markdown
# [Product Name] — Task Tracker

> All tasks. One file, one source of truth.
> Refer to IMPLEMENTATION_PLAN.md for architecture, philosophy, and use cases.

---

## Rules

Tasks follow S.M.A.R.T. criteria: Specific, Measurable, Achievable,
Relevant, Time-bound (to an epic). Task IDs are permanent — never renumber,
never reuse. New tasks get the next unused integer. Status ❌ cancelled
requires a comment.

Omit any relation line that has no entries. Every reference includes ID + title.

---

### T-000: Example Task
- **Status**: 💡 to-do
- **Epic**: [First Epic]
- **Shares context with**:
    T-002 Some task title
- **Blocks**:
    T-001 Another task title

This task shows the format. Append notes over time:

- 2026-03-01: Discovered X doesn't work with Y. Workaround: Z.
- 2026-03-05: Resolved. Switched to W per decision D-001.

Measurable exit criteria:
- ✅ Criterion described as a verifiable fact
- ✅ Another criterion with a number or binary outcome

————————————————————————————————————————————————————————————————————

## Epics

1. **[Epic Name]** — one-line description
2. **[Epic Name]** — one-line description
3. **Post-MVP: [Theme]** — one-line description

————————————————————————————————————————————————————————————————————

## [Epic Name]

————————————————————————————————————————————————————————————————————

### T-001: Task title
- **Status**: 💡 to-do
- **Epic**: [Epic Name]
- **Shares context with**:
    T-003 Related task title
- **Blocks**:
    T-002 Dependent task title

Description paragraph. Grows over time — append dated notes.

Measurable exit criteria:
- ✅ Specific verifiable fact or number
- ✅ Another criterion

————————————————————————————————————————————————————————————————————

### T-002: Another task
- **Status**: 💡 to-do
- **Epic**: [Epic Name]
- **Blocked by**:
    T-001 Task title

Description.

Measurable exit criteria:
- ✅ ...

————————————————————————————————————————————————————————————————————

## Post-MVP: [Theme]

————————————————————————————————————————————————————————————————————

### F-001: Future feature title
- **Status**: 💡 to-do
- **Epic**: Post-MVP: [Theme]

Description (can be shorter for post-MVP).

Measurable exit criteria:
- ✅ Verifiable fact
```

### Task Format Reference

```
### T-NNN: Task Name
- **Status**: 💡 to-do | ⏳ in progress | ✅ done | ❌ cancelled
- **Epic**: Epic Name
- **Shares context with**:
    T-NNN Title
- **Blocks**:
    T-NNN Title
- **Blocked by**:
    T-NNN Title

Description.

Measurable exit criteria:
- ✅ Verifiable fact
```

### Task Rules

**IDs**: permanent, sequential (gaps OK, no duplicates, no suffixes).

**Statuses**: `💡 to-do` · `⏳ in progress` · `✅ done` · `❌ cancelled`

**Relations** (in this order, omit if empty):
1. **Shares context with** — related concepts, read both when working on either
2. **Blocks** — must be done before those
3. **Blocked by** — those must be done before this

Each reference on its own indented line, always ID + title.
If a task already appears in **Blocks** or **Blocked by**, do not also list it
in **Shares context with** — the blocking relation implies shared context.

**Exit criteria**: every task needs ≥1 verifiable criterion.

**Prototype tasks**: need a criterion for the code they leave behind — deleted,
or taken over by a named task. There is no prototype mode: code written in a
prototype task follows the same standards as any other code.

**Separators**: `————————` full-width line between every task.

**No week or time estimates.** Epics provide sequencing, not scheduling.

**T-001 is always project initialization.** Its description should reference
the relevant platform-specific guide from CodingStandards for setup
instructions (e.g., `KOTLIN_MULTIPLATFORM.md` for KMP projects).

### Epic Rules

Epics are thematic groups, not phases. Name as noun phrases:
"Zone Layout Solver" not "Phase 2". No week numbers.

Post-MVP epics: named `Post-MVP: [Theme]`, tasks prefixed `F-NNN`.
Same format, descriptions can be shorter.

### Task Decomposition Tips

- **One deliverable** per task
- **One request, one task**: a feature the user asked for is not split into look-alike tasks,
  and no task or section is added that nobody asked for. Tasks and sections this guide requires
  count as asked for; a task that comes from a finding is proposed to the user
- **Write exit criteria first** — if you can't, the task isn't specific enough
- **>5 exit criteria** → consider splitting
- **No description beyond title** → might be a sub-bullet, not a task
- **User testing**: include protocol inline, one task (not subtasks)
- **Naming/terminology**: create a dedicated task — naming blocks onboarding

### LLM Integration Test Tasks

When a product includes an LLM component and the plan includes structured output testing, task exit criteria should specify:

**Assertion boundary** — which checks are structural vs semantic:
- **Structural (hard)**: grammar-enforced guarantees — valid JSON, field presence, enum membership, numeric bounds. These fail CI.
- **Semantic (soft)**: LLM comprehension quality — choice mapping, intent classification, numeric extraction from natural language, conflict detection. These log warnings for prompt-tuning review.

> Rule of thumb: if a constrained-decoding grammar (GBNF, JSON-Schema, etc.) could guarantee the property, hard-assert it. If it depends on the LLM "understanding" something, soft-assert it.

**Model capability expectations** — document in the task or linked from it:
- Target model name, size, and quantization (e.g., Qwen2.5-3B Q4_K_M)
- Tolerance ranges for numeric extraction (e.g., ±2 on boundary values)
- Expected accuracy for enum/status inference (e.g., ~80–90% for indirect phrasing)
- Known weak areas (e.g., multi-step arithmetic, conflict detection)

**Coupling matrix** — each LLM mode requires a matched set of system prompt + grammar + response DTO (Data Transfer Object). The task should list which modes are covered and reference the source files.

**Soft assertion mechanism** — the task should specify how soft failures are reported (e.g., stderr warnings, a dedicated log file) and which future task reviews them for prompt refinement.

See `TESTING.md` §Shared Expensive Resources for the implementation pattern (thread-safe lazy init, `assumeTrue` skip for missing models).

**Write it to `TASK_TRACKER.md` at the project root before moving on.** Step 3
cross-checks two files against each other; it has nothing to check if either of
them is still only in the conversation.

---

## Step 3: Cross-Check

### Plan ↔ Tracker alignment
- [ ] Every `T-NNN` and `F-NNN` in the plan exists in the tracker
- [ ] Every task in the tracker appears in the plan's epic listing
- [ ] Epic names match exactly between files
- [ ] T-000 is in tracker (example) but not in plan

### Plan consistency
- [ ] Abstract mentions the core insight
- [ ] Architecture diagram names every component mentioned in tasks
- [ ] Decisions log references task IDs for TBDs
- [ ] Every success metric is measurable

### Tracker consistency
- [ ] Every task has: status, epic, ≥1 exit criterion
- [ ] No empty relation lines
- [ ] All references: ID + title, multi-line indented
- [ ] Separators between every task
- [ ] No duplicate IDs, no suffixes
- [ ] Post-MVP uses `F-NNN`

---

## Step 4: Project Artifacts

Create the project-level artifacts that complete the planning process.

1. **Agree on the root package name** — use reverse-domain notation
   (e.g., `com.example.projectname`). Ask outright and wait; this is the one
   thing in Step 4 worth blocking on.

   **Never derive an owner's identifier** — package, bundle ID, domain, account —
   from a submodule or remote URL, the repo folder name, or `git config`. Offering
   a guess as a ready-made option is the same mistake as writing one: it reads as
   already established, and it propagates into signing and every import.
2. **Add `x128/CodingStandards` as a git submodule** — the user does it; agents never write
   to git outside `land.sh`, and `land.sh` only commits a task
3. **Create `CLAUDE.md`** at the project root, referencing only the
   CodingStandards documents relevant to this project's stack. Example for
   a Kotlin/KMP project:
   ```markdown
   # ProjectName

   One-sentence project description from the implementation plan.

   ## Standards
   Follow `CodingStandards/CLEAN_CODE.md`
   Follow `CodingStandards/KOTLIN.md`
   Follow `CodingStandards/ARCHITECTURE.md`
   Follow `CodingStandards/TESTING.md`
   Follow `CodingStandards/KOTLIN_MULTIPLATFORM.md`
   Follow `CodingStandards/EXECUTION_GUIDE.md`

   ## Project
   - Package: `com.example.projectname`
   - Module: `composeApp` (desktop target)
   - Decisions the standards name: D-002, D-003, D-004 (or the numbers this log gives them)
   ```
   Omit documents that don't apply (e.g., `SWIFT.md` for a pure Kotlin
   project). Add project-specific context (package name, modules,
   constraints) under `## Project`. Link the skills into `.claude/skills/` as
   [skills/README.md](./skills/README.md), "Setup", says; `CLAUDE.md` does not list them.

4. **The user commits the plan, the tracker, `CLAUDE.md`, `.claude/skills/`, and the files `/maintain --init` wrote if it ran, before a line of product code
   exists.** They are the first commit.

   **The failure to guard against is planning that never leaves the
   conversation.** Steps 0–3 can be run entirely in dialogue: the questions get
   asked, the answers are good, a complete plan takes shape, `CLAUDE.md` gets
   written from it, and the code starts. The plan is real to everyone present —
   and it is gone when the session ends. Nothing was forgotten or dropped; it
   was simply never a file. **A plan that exists only in a session's context
   does not exist.**

   What survives is a `CLAUDE.md` listing features nobody built, and no record
   anywhere of whether they were cut, deferred, or just not reached yet. The
   next person — or the next session — cannot tell a defect from unstarted
   work, and will report the second as the first.

   If you find a project in that state (`CLAUDE.md` and code, no plan, no
   tracker), reconstruct Steps 1–2 from what was built before doing anything
   else, and treat `CLAUDE.md`'s feature list as the surviving evidence of what
   was intended.

**Planning is now complete.** The artifacts are: implementation plan, task
tracker, CLAUDE.md, and CodingStandards submodule. Task execution starts
with T-001. See `EXECUTION_GUIDE.md` for the task execution workflow.

---

## Ongoing Maintenance

- **New tasks**: next unused ID. Add to both tracker and plan's epic listing.
- **Cancelled tasks**: `❌ cancelled` with dated comment. Never delete or renumber.
- **New decisions**: add to log with TBD or chosen value.
- **Notes/issues**: append dated bullets to the relevant task.
- **New epics**: add to both files.
- **Scope changes**: update philosophy. Rare — most changes are task-level.
