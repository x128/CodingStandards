# Product Planning Guide

> How to go from a raw idea to a well-structured implementation plan and task
> tracker. This guide captures the process, rules, and formatting conventions.

**Follow steps 0–5 in order. Report which step you are on as you progress.**

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

**Architecture & constraints**
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

### Ask if relevant:

- Does the product have a versioning/history model?
- Is collaboration involved? How?
- What export formats matter?
- Are there regulatory or compliance concerns?
- Is there a "done" state, or is the product a living process?

**Stop asking when you have enough to write the philosophy section.**

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
**Actor**: ...
**Flow**:
1. ...
2. ...
3. ...

(Cover: happy path, detailed input, feedback, direct manipulation,
comparison, external stakeholders, API access if any.)

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

- **Philosophy**: 3–6 named principles, each a non-obvious design choice
- **Use cases**: short — actor + 3–7 numbered steps each
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
- **Theoretical foundation** (ML/AI projects): generate THEORY.md via
  `/theory` skill, add the key correspondences to CLAUDE.md under
  `## Theoretical Foundation`

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
- 2026-03-05: Resolved. Switched to W per decision D-003.

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

**Separators**: `————————` full-width line between every task.

**No week or time estimates.** Epics provide sequencing, not scheduling.

### Epic Rules

Epics are thematic groups, not phases. Name as noun phrases:
"Zone Layout Solver" not "Phase 2". No week numbers.

Post-MVP epics: named `Post-MVP: [Theme]`, tasks prefixed `F-NNN`.
Same format, descriptions can be shorter.

### Task Decomposition Tips

- **One deliverable** per task
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

## Step 4: Project Initialization (T-001)

After the plan and tracker are accepted, **T-001 is always project
initialization**. This is the first thing executed — before any feature work.

T-001 includes:

1. **Agree on the root package name** — use reverse-domain notation
   (e.g., `com.example.projectname`). Don't assume — ask the user.
2. **Add `x128/CodingStandards` as a git submodule**
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

   ## Skills
   Follow skills from `CodingStandards/skills/`

   ## Project
   - Package: `com.example.projectname`
   - Module: `composeApp` (desktop target)
   ```
   Omit documents that don't apply (e.g., `SWIFT.md` for a pure Kotlin
   project). Add project-specific context (package name, modules,
   constraints) under `## Project`.
4. **Platform-specific setup** (if applicable):
   - **KMP/Compose Multiplatform**: follow
     [KOTLIN_MULTIPLATFORM.md](./KOTLIN_MULTIPLATFORM.md) — Gradle wrapper,
     version catalog, `gradle.properties`, `composeApp` module, verify with
     `./gradlew :composeApp:run`
   - Other platforms: follow the corresponding guide when one exists (e.g.,
     `TYPESCRIPT.md`, `SWIFT_PROJECT.md`)

---

## Step 5: Ongoing Maintenance

- **New tasks**: next unused ID. Add to both tracker and plan's epic listing.
- **Cancelled tasks**: `❌ cancelled` with dated comment. Never delete or renumber.
- **New decisions**: add to log with TBD or chosen value.
- **Notes/issues**: append dated bullets to the relevant task.
- **New epics**: add to both files.
- **Scope changes**: update philosophy. Rare — most changes are task-level.
