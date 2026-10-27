# Task Execution Guide

> The rules for getting a task from to-do to committed.
> See `PLANNING_GUIDE.md` for how to create the plan and tracker.

**These rules do not depend on who does the work.** They hold when the user
writes the code by hand, when Claude writes it on request, and when the
automated loop in `TASK_LOOP.md` runs it. That loop is a machine built *on* these
rules — it mechanizes them and adds a way to delegate one action (the commit).
It is not an alternative set of rules, and this document does not describe it.

---

## Who runs the work

- **By hand** — the user writes the code. Nothing here constrains that; the
  rules describe what makes a task finished, not who types.
- **On request** — Claude implements, presents, the user reviews; the change is
  committed as the project decided (see "Who writes to git").
- **Through the loop** — where a project has `.review/`, this is the default
  path for task work, with or without the skill name being typed. See
  `TASK_LOOP.md`.

Default means default: any change can be made outside the loop on request,
without a reason. "Just make this change", "skip the review", "I'll write it
myself" are complete instructions — follow them and do not re-propose the loop.
What is not optional is honesty about what actually ran; never present a partial
run as a completed one.

A project that sets up `.review/` without adding the routing block to its
`CLAUDE.md` gets the worst case: a loop that exists and is never invoked.
`/maintain --init` installs it.

---

## One Task at a Time

Tasks are executed **one at a time**. Never batch multiple tasks into a
single work unit.

The shape of every task:

1. **Pick the next task** — the next unblocked `💡 to-do`
2. **Do the work** — implement, test, verify exit criteria
3. **Stop and present** — show what changed, mark the task `✅ done`
4. **The user reviews** — and decides whether the task is actually finished
5. **The change is committed** — after that decision, never before it
6. **Repeat** — the next task starts only once this one is settled

Steps 4 and 5 are the only ones the loop changes, and only in *mechanism*:
there, the user reviews the finished task rather than the raw diff, and, where
D-004 lets the loop commit, the commit happens through the landing contract
instead of by hand. Who decides — step 4 — never moves.

---

## Rules

### One task, one cycle

Do not start T-002 until T-001 is reviewed and committed. Even if tasks
seem small or related, each one goes through the full cycle. No exceptions.

### Who writes to git

The project decides, and records it as D-004 ([PLANNING_GUIDE.md](./PLANNING_GUIDE.md)): agents
only read git and the user commits; or, besides, the loop commits through `land.sh` (below). It is
the user's preference, not a rule of these standards, and the user may change it. Until it is
recorded, git is read-only for agents: before it presents its first finished work, the agent asks
the question of D-004 (PLANNING_GUIDE.md, "The questions of D-002, D-003 and D-004") and writes the answer into the plan's Decisions Log, adding the row when it
is missing (PLANNING_GUIDE.md, "Decisions every project makes"). Wherever these standards say
D-004, they mean that row, whatever number the project gave it (its `CLAUDE.md` says). When the user asks in chat for a commit where git is read-only for agents, give the
files and the message; the user makes it.

Where git is read-only for agents:

These rules are about the project's repository and its submodules. A test script
that builds a throwaway repository in a temporary folder and deletes it
(`templates/review/lib/selftest.sh`) writes no git the user owns.

**Never run a git command that changes anything.** Not `add`, `commit`,
`reset`, `checkout`, `switch`, `restore`, `stash`, `rm`, `mv`, `branch`,
`merge`, `rebase`, `push`, `pull`, `tag`, or `clean`. Read-only only:
`status`, `diff`, `log`, `show`, `blame`.

This includes tidying up. A messy `git status` after moving files is the
user's to read, not yours to clean. Staging is part of how the user reviews
work: `git add` on their behalf empties `git diff` and destroys the review
they were about to do.

**Do not hand over the command either.** `git add …` or `git commit -m …`
pasted into a reply is blind: the user cannot see from it what would be staged
or what would land, and a stray keystroke runs it. It also assumes they commit
from a terminal.

Say what changed instead — which files, and what is in each — and stop there.
They commit in their own tool, where staging is visible before it happens.
Print a git command only when they ask for one.

### The loop's landing: `land.sh`

Where D-004 says so, the loop commits — that is the point of the maintainer
role. It does so through exactly one script, `land.sh`, which the user enabled
deliberately and can revoke with one line in `.review/land.conf`. That script
refuses unless eight conditions hold, stages *and commits* only the task's
declared files, and has no code path for push, amend, force, or branch switching
([TASK_LOOP.md § Landing](./TASK_LOOP.md#landing)).

Everything about the loop's landing is what makes it different from an agent running
`git commit`: it is delegated in advance, narrow in what it can do, revocable,
and auditable in the commit trailers. **Nothing generalizes from it.** In a chat
session, and everywhere outside the loop, git is what D-004 says, and read-only
where it says nothing — including "just staging" and "just tidying up".

### The task boundary belongs to the user

By hand or on request, the user reviews the diff, and it is committed as D-004 says. Through the loop,
the user reviews **the finished task** — what changed, what the review found,
what was rejected and why — and the maintainer commits it where D-004 lets the
loop commit; otherwise the user does.

The unit of review differs; the authority does not. The user, never the agent,
decides that a task is genuinely done and that work may continue. The maintainer
may only stop asking for a category of task when the user has said so — nothing
measures its way out of asking
([MAINTAINER_TRAINING.md](./MAINTAINER_TRAINING.md)).

### Reporting to the user

Every message to the user is written by [skills/write](./skills/write/SKILL.md). The points
below are about the work, not the text; rules for the text were measured to make messages worse
next to the skill ([MEASURED.md](./skills/write/MEASURED.md)).

- **During long work, say what runs and what comes next** when a step starts or
  ends, in the user's terms: what it does to their product, not a step name.
  Never leave the user without word.
- **Keep working while the next step serves the request.** Ask only what the user
  must decide. Never stop to ask whether to run the next step of the work they
  asked for, or whether it is worth its tokens.
- **Ask in the chat, one thing at a time**, except where a skill gathers them:
  review findings go where `/code-review` sends them;
  the intake questions of PLANNING_GUIDE.md come a block at a time, as its Step 0 says; books are asked for
  in one list. A long file does not replace
  the questions; it is named by its absolute path for the rest.
- **Each option says something the others do not, and its label keeps it**: who
  does what, as a phrase, never one word cut out of it. Two wordings of one
  meaning are not a choice; take the one the user already used, and do not ask.

### Work given to other agents

Their assignment names the task and the standards they follow — these documents,
the project's `CLAUDE.md`, its `.review/` — and adds no rule of its own. A rule
they need that the standards lack goes to the user first. The one exception is a
measurement of these standards, whose skill lists the rules its assignments add.

### No moving on without confirmation

After presenting a completed task, wait for the user to confirm the work
is accepted before picking up the next one.

### Exit criteria are the definition of done

A task is done when all its exit criteria are met and its behavior is covered by
tests. If a criterion can't be verified, flag it — don't skip it silently.

---

## Why

- Small, reviewed increments catch mistakes early
- Each commit is a clean, reviewable unit of work
- The user stays in control of what enters the repository
- Rolling back a single task is trivial
