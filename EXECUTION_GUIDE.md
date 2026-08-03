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
- **On request** — Claude implements, presents, the user reviews and commits.
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
there, the user reviews the finished task rather than the raw diff, and the
commit happens through the landing contract instead of by hand. Who decides —
step 4 — never moves.

---

## Rules

### One task, one cycle

Do not start T-002 until T-001 is reviewed and committed. Even if tasks
seem small or related, each one goes through the full cycle. No exceptions.

### Git is read-only

**Never run a git command that changes anything.** Not `add`, `commit`,
`reset`, `checkout`, `switch`, `restore`, `stash`, `rm`, `mv`, `branch`,
`merge`, `rebase`, `push`, `pull`, `tag`, or `clean`. Read-only only:
`status`, `diff`, `log`, `show`, `blame`.

This includes tidying up. A messy `git status` after moving files is the
user's to read, not yours to clean. Staging is part of how the user reviews
work: `git add` on their behalf empties `git diff` and destroys the review
they were about to do.

If a write operation is needed, put the command in the response and let the
user run it. Do not offer to run it yourself.

### The one exception: `land.sh`

The loop commits — that is the point of the maintainer role. It does so through
exactly one script, `land.sh`, which the user enabled deliberately and can
revoke with one line in `.review/land.conf`. That script
refuses unless eight conditions hold, stages *and commits* only the task's
declared files, and has no code path for push, amend, force, or branch switching
([TASK_LOOP.md § Landing](./TASK_LOOP.md#landing)).

Everything about that exception is what makes it different from an agent running
`git commit`: it is delegated in advance, narrow in what it can do, revocable,
and auditable in the commit trailers. **Nothing generalizes from it.** In a chat
session, and everywhere outside the loop, git stays read-only — including "just
staging" and "just tidying up".

### The task boundary belongs to the user

By hand or on request, the user reviews the diff and commits. Through the loop,
the maintainer commits and the user reviews **the finished task** — what
changed, what the review found, what was rejected and why.

The unit of review differs; the authority does not. The user, never the agent,
decides that a task is genuinely done and that work may continue. The maintainer may only stop asking for a category
of task after that category has earned it, measured
([MAINTAINER_TRAINING.md § Track B](./MAINTAINER_TRAINING.md#track-b-when-not-to-ask)).

### No moving on without confirmation

After presenting a completed task, wait for the user to confirm the work
is accepted before picking up the next one.

### Exit criteria are the definition of done

A task is done when all its exit criteria are met. If a criterion can't be
verified, flag it — don't skip it silently.

---

## Why

- Small, reviewed increments catch mistakes early
- Each commit is a clean, reviewable unit of work
- The user stays in control of what enters the repository
- Rolling back a single task is trivial
