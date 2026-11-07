# Product Planning Guide

> How to go from a raw idea to requirements, a plan and a task tracker. This guide captures the
> process, rules, and formatting conventions.

**Follow steps 0–4 in order. Report which step you are on as you progress. Planning produces:
requirements, plan, task tracker, AGENTS.md, and CodingStandards submodule. After Step 4 the
planning process is complete. Task execution starts with T-001.**

---

## Step 0: Intake Questions

Before writing anything, ask 10–20 targeted questions to extract what would
otherwise take hours of back-and-forth. Don't ask obvious or generic
questions — only ones whose answers materially change the plan.

### Always ask:

**Product vision**

1. What does the product do, how does the user do that today without it, and what is hardest in
   that?
2. Who is the user? (expertise level, context, device)

**Platforms & core model**

3. What platforms? (mobile, desktop, web, all)
4. Online, offline, or hybrid? Any hard constraints?
5. What's the core data model? (what are the "nouns" of the system?)
6. What's the primary interaction loop? (what does the user do repeatedly?)

**Scope & philosophy**

7. What is explicitly NOT in MVP? (name 3+ things you're tempted to include)
8. What's the relationship between the user and AI (if any)?
9. Are there external stakeholders who interact with the output?

**UX**

10. How does the user see progress?
11. What's the smallest unit of user decision?

**Tech preferences**

12. Any strong tech stack preferences or constraints?
13. What's the deployment model?
14. Any AI/ML components? What size/where?

**Architecture, comments, git** — asked as "Three questions of every project" writes them

### Ask if relevant:

- Does the product have a versioning/history model?
- Is collaboration involved? How?
- What export formats matter?
- Are there regulatory or compliance concerns?
- Is there a "done" state, or is the product a living process?

**Stop asking when you have enough to write the philosophy section.** The three questions of every
project are asked all the same, on top of the 10–20, except one the user has already answered.

### How the questions are asked

**A block at a time, in the order above, and none the user has already answered.** Each group of
"Always ask" is one block; a question of "Ask if relevant" joins the block of its topic, and a block
with nothing left to ask is skipped. An open question, such as what the product does or who uses it,
is asked as text, without options: made up, they would read as already settled. The card of its
block comes after the user's answer. Except the three below, each question is written as
[.agents/skills/write](./.agents/skills/write/SKILL.md) says. The three questions of every project
are never moved into an earlier block, nor asked next to the package name of Step 4. Asked among the
first questions about a project, a question about use cases comes from nowhere; asked after the
product is described, it has something to stand on.

**A card is all the user sees.** While a card is open, the text written before it is out of sight,
and an app may show one question of the card at a time, without its header or the preview of an
option. So the first question of each card opens with its topic in a few plain words, such as "Now
about where the app runs.", and every question says in its own text what it asks about.

**Only an answer settles a question**: the option the user picked, or what they wrote. "Go on",
silence, a question they did not see, a recommendation, a conclusion from their other answers settle
nothing; the question stays open, in the task that waits on it.

### Three questions of every project

Their text is copied, not written again: as it is for a user who writes in English, translated
sentence by sentence for another language. Nothing is added or cut, and no example from the product
goes in. A translation keeps ViewModel, use case, git, pull request, main and master in English. In
a project with no screens, the screens and ViewModels of the text become the classes that call the
use cases, such as command handlers.

**A request with nothing to check or decide**

> Now let's talk a bit about the app's architecture. I will build the app in three layers:
>
> Presentation: screens with ViewModels
> ㅤㅤ↓
> Domain: use cases
> ㅤㅤ↑
> Data: repositories
>
> Where there is business logic, there is a use case. Where there is no logic, does the ViewModel
> call the repository directly, or still go through a use case? This rule is for the whole app.

- *Directly to the repository*: a use case only where there is logic. Fewer classes, but a
  ViewModel may call both use cases and repositories.
- *Always through a use case*: even if the use case is one line. A ViewModel calls only use cases,
  but there are more classes.

**Comments in the code**

> Comments in the code: do we try to write code without them, so that it explains itself, or are
> comments a normal part of the code?

- *Code without comments (Recommended)*: the code's structure says what it does: simple functions,
  each with its own job, clear names.
- *Comments are fine*: the agent writes and updates them where it sees fit.

**Who writes to git**

> How far does an agent take a finished task? Finished means it has passed the checks and the
> review. You can change this at any time.

- *The agent does not touch git*: you look at the changes and commit them yourself.
- *The agent commits and pushes to a remote branch*: you look at the branch and merge it into main
  yourself.
- *The agent commits, pushes and opens a pull request*: you look at the pull request and merge it
  yourself.
- *Full cycle up to the main branch (main or master)*: the agent commits, pushes, opens a pull
  request, fixes what the review finds and merges it into main. You look when you want to.

---

## Step 1: Write the Requirements and the Plan

The requirements say what the product owner wants: what the product is and does, why, and what it is
built with. The plan says in what order it gets built: the epics and their tasks. The detail of each
task is in the task tracker.

### Sample: REQUIREMENTS.md

```markdown
# [Product Name] — Requirements

> One-paragraph abstract: what it is, what makes it special, platform list.
> Bold statement of direction.

---

## 1. Core Philosophy

### 1.1 [First principle]

A choice the product owner made, and why.

### 1.2 [Second principle]
...

---

## 2. [Core Interaction Model]

Diagram(s) of primary flows. ASCII art is fine.

---

## 3. [Domain Model]

The conceptual model — vocabulary, "nouns", relationships.
NOT implementation classes.

---

## 4. Use Cases (MVP)

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

## 5. [Domain Taxonomy]

Detailed data categories, items, types, examples. Tables work well here.

---

## 6. Architecture

System diagram (ASCII), component descriptions, key interfaces.

---

## 7. Tech Stack

| Component | Library | Module |
|-----------|---------|--------|
| ... | ... | ... |

---

## 8. How the code is made

- A request with nothing to check or decide: [the answer]
- Comments in the code: [the answer]
- Who writes to git: [the answer]
```

### Sample: PLAN.md

```markdown
# [Product Name] — Plan

> How REQUIREMENTS.md gets built, in order. Task detail: TASK_TRACKER.md.

---

### [Epic Name]
- [ ] T-001 Task title
- [ ] T-002 Task title

### [Another Epic]
- [ ] T-003 Task title

### Post-MVP: [What the user can do]
- [ ] F-001 Feature title
```

### Rules

- **Only what is decided goes into the requirements**: a decision of the product owner goes into the
  section it is about; an open question is in the task that waits on it. Neither file says who said,
  asked or decided something
- **The product owner** is the one who answers the questions. Things are named in the product
  owner's words
- **Philosophy**: named principles, each a choice the product owner made
- **Use cases**: short — name, input, output that names every outcome, and at most 7 numbered rules,
  in the words of the subject. Not one per user action
- **Epics & Tasks**: reference index only — `- [ ] T-NNN Title`, grouped by epic as "Epic Rules" of
  Step 2 says. Post-MVP uses `F-NNN`. No descriptions here.
- **Research**: a study that an epic needs is a task of that epic, before the tasks that use it.
  Research that no epic needs yet, such as competitors, market or pricing, is an epic of its own,
  `Research`
- **No week numbers** in epic names
- **Theoretical foundation** (ML/AI projects): generate THEORY.md via the `/theory` skill

**Write them to `REQUIREMENTS.md` and `PLAN.md` at the project root before moving on.** Step 4
explains why this is the step that gets skipped and what it costs.

---

## Step 2: Write the Task Tracker

The tracker is the **single source of truth for all work**. Every task
(MVP and post-MVP) lives here with full detail.

### Sample

```markdown
# [Product Name] — Task Tracker

> All tasks. One file, one source of truth.
> What the tasks build: REQUIREMENTS.md. How, and in what order: PLAN.md.

---

## Rules

Each epic is one thing the user can do after it. Task IDs are permanent — never renumber,
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

This task shows the format. The description says what to do; it is rewritten
as the task changes.

Measurable exit criteria:
- ✅ A fact the product owner stated, or one the product has no choice about

————————————————————————————————————————————————————————————————————

## Epics

1. **[What the user can do]** — how the user sees that it works
2. **[What the user can do]** — how the user sees that it works
3. **Post-MVP: [What the user can do]** — how the user sees that it works

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

Description: what to do.

Measurable exit criteria:
- ✅ Specific verifiable fact or number

————————————————————————————————————————————————————————————————————

### T-002: Another task
- **Status**: 💡 to-do
- **Epic**: [Epic Name]
- **Blocked by**:
    T-001 Task title

Description. No criteria yet: nothing about it is known before the work reaches it.

————————————————————————————————————————————————————————————————————

## Post-MVP: [What the user can do]

————————————————————————————————————————————————————————————————————

### F-001: Future feature title
- **Status**: 💡 to-do
- **Epic**: Post-MVP: [What the user can do]

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

Each reference on its own indented line, always ID + title. If a task already appears in **Blocks**
or **Blocked by**, do not also list it in **Shares context with** — the blocking relation implies
shared context.

**Exit criteria say what the product owner said, or what the product has no choice about.** How the
product behaves is the product owner's decision. So a criterion goes into the tracker only when the
product owner said it, and not in text an agent wrote, or when there is nothing to choose: a file
format the product must read, a rule of the subject from a book the product owner named, a fact
measured on real data, what a task already done hands it. How another app does it is not a source:
it is a question for the product owner. A criterion does not say who said it.

**A criterion is what the user sees, or what the product must match.** How the code is built is
not one: the architecture is in the requirements, and the checks and the review hold it.

**The description, too, says only what is decided.** It says what the task gives the user; a
detail of how the product behaves that nobody decided is left as a question for the user.

**Most tasks have no criteria in the plan; they gather them as the work comes closer.** Before the
work reaches a task, its details are not known, and a guess written as a criterion reads as already
decided. Each task done shows something about the tasks after it: what it hands them, what it
leaves to them. That goes into their criteria then, and a choice about the product it raises is
asked of the user; the task loop (`/maintain`) does both. A task taken into work starts with the
criteria it has gathered, or with none: criteria written at that moment only describe what the work
is about to do.

**No criterion for what shows itself**: that the code builds, that the tests pass, that the app
runs on the phone. The checks show it, or the first task that needs it does, and it is fixed then.

**No number to reach.** A task has the criteria that are known, none included; none is added to
fill a list.

BAD — guessed before the work reached the task, or shown anyway:

```
- ✅ A line break never falls inside a word     ← nobody asked; another app does it so
- ✅ The app starts on the iPhone               ← the first task that needs the phone shows it
- ✅ All tests pass                             ← the checks show it
- ✅ The screen is a ViewModel with a State     ← how the code is built
```

GOOD:

```
- ✅ Opens every sample file of format version 1.1
- ✅ A recipe saved offline opens offline
- ✅ Shows the recipes in the order the import keeps them
```

**Prototype tasks**: need a criterion for the code they leave behind — deleted,
or taken over by a named task. There is no prototype mode: code written in a
prototype task follows the same standards as any other code.

**Separators**: `————————` full-width line between every task.

**No week or time estimates.** Epics provide sequencing, not scheduling.

**T-001 is always project initialization.** Its description should reference
the relevant platform-specific guide from CodingStandards for setup
instructions (e.g., `KOTLIN_MULTIPLATFORM.md` for KMP projects).

### Epic Rules

**An epic is one thing the user can do after it that they could not do before.** It is named by
that thing, in the user's words, and its line in the list of epics says how the user sees that it
works. It holds every task that thing needs, whatever the layer: the screen, the data, the
platform code, the study. One task is an epic too; there is no number to reach.

BAD — grouped by where the code lives; after any one of them the user can do nothing new:

```
### Data model          — recipe entity, storage format
### Storage             — database, sync
### Screens             — recipe list, recipe screen
```

GOOD — grouped by what the user gets:

```
### Save a recipe from a web page      — the share button, reading the page, storing it, the list
### Cook with the phone on the table   — step by step screen, the screen stays on, timers
```

**A task that two epics need goes in the first of them**, and does only what that epic needs; the
later one extends it.

**A task the epic's thing works without belongs to a later epic**: an automatic step where doing
it by hand works, a second device where one is enough. Each later epic is that one thing more.

**Epics go in the order the user gets them.** The first is the smallest thing the user can try,
and T-001 is its first task: there is no epic of setup or foundation.

**The user reads the list of epics before the tasks are written**: the names and the lines, in
order. The list is the part of the plan the user checks; the tasks under it are the agent's.

**An epic is groomed when its work starts** (`/groom`), and again after a change the plan rests
on: by then the epics before it are done, and its tasks and criteria are corrected by what they
showed.

Post-MVP epics: named `Post-MVP: [what the user can do]`, tasks prefixed `F-NNN`. Same rules,
descriptions can be shorter. No week numbers, no phases.

### Task Decomposition Tips

- **One deliverable** per task
- **One request, one task**: a feature the user asked for is not split into look-alike tasks,
  and no task or section is added that nobody asked for. Tasks and sections this guide requires
  count as asked for; a task that comes from a finding is proposed to the user
- **No description beyond title** → might be a sub-bullet, not a task
- **User testing**: include protocol inline, one task (not subtasks)
- **Naming/terminology**: terms the requirements use and nobody has settled are one task, before the
  tasks that use them

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

### Requirements and plan
- [ ] Architecture diagram names every component mentioned in tasks

### Tracker consistency
- [ ] Every task has: status, epic
- [ ] After each epic the user can do something new, and no epic needs a task of a later one
- [ ] No empty relation lines
- [ ] All references: ID + title, multi-line indented
- [ ] Separators between every task
- [ ] No duplicate IDs, no suffixes
- [ ] Post-MVP uses `F-NNN`

---

## Step 4: Project Artifacts

Create the project-level artifacts that complete the planning process.

1. **Agree on the root package name** where the stack names packages in reverse-domain notation
   (e.g., `com.example.projectname`). Ask outright and wait; this is the one thing in Step 4 worth
   blocking on.

   **Never derive an owner's identifier** — package, bundle ID, domain, account — from a submodule
   or remote URL, the repo folder name, or `git config`. Offering a guess as a ready-made option is
   the same mistake as writing one: it reads as already established, and it propagates into signing
   and every import.
2. **Add `x128/CodingStandards` as a git submodule** — the user does it; agents never write to git
   outside `land.sh` and `publish.sh`, and those only land a task
3. **Create `AGENTS.md`** at the project root: what the product is, where the requirements, the plan
   and the tracker are, and one line pointing at the standards. It is read on every request, so it
   holds only that:
   ```markdown
   # ProjectName

   One-sentence project description from the requirements.

   Code follows the standards in `CodingStandards/`; `CodingStandards/README.md`
   says which to read and when. An empty folder means the submodule is not
   initialised.

   Requirements — `REQUIREMENTS.md`, plan — `PLAN.md`, tasks — `TASK_TRACKER.md`.
   ```
   Link the skills into `.agents/skills/` and `.claude/skills/` as
   [.agents/skills/README.md](./.agents/skills/README.md), "Setup", says.

4. **The user commits the requirements, the plan, the tracker, `AGENTS.md`, `.claude/skills/`,
   `.agents/skills/`, and the files `/maintain --init` wrote if it ran, before a line of product
   code exists.** They are the first commit.

   **The failure to guard against is planning that never leaves the conversation.** Steps 0–3 can be
   run entirely in dialogue: the questions get asked, the answers are good, a complete plan takes
   shape, `AGENTS.md` gets written from it, and the code starts. The plan is real to everyone
   present — and it is gone when the session ends. Nothing was forgotten or dropped; it was simply
   never a file. **A plan that exists only in a session's context does not exist.**

   What survives is an `AGENTS.md` listing features nobody built, and no record anywhere of whether
   they were cut, deferred, or just not reached yet. The next person — or the next session — cannot
   tell a defect from unstarted work, and will report the second as the first.

   If you find a project in that state (`AGENTS.md` or `CLAUDE.md` and code, no requirements, no
   plan, no tracker), reconstruct Steps 1–2 from what was built before doing anything else, and
   treat that file's feature list as the surviving evidence of what was intended.

**Planning is now complete.** The artifacts are: requirements, plan, task tracker, AGENTS.md, and
CodingStandards submodule. Task execution starts with T-001. See `EXECUTION_GUIDE.md` for the task
execution workflow.

---

## Ongoing Maintenance

- **New tasks**: next unused ID. Add to both tracker and plan's epic listing.
- **Cancelled tasks**: deleted while the plan is being drawn up; after Step 4, `❌ cancelled` with
  the reason. Never renumber.
- **New decisions**: into the section of the requirements they are about.
- **Bugs**: a bug found is fixed at once by whoever writes the code, or written into the task it
  belongs to as an exit criterion — what the user should see.
- **New epics**: add to both files.
- **An epic about to start, or a change the plan rests on**: `/groom`.
- **Scope changes**: update philosophy. Rare — most changes are task-level.
