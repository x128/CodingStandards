# Task Execution Guide

> How to work through the task tracker after planning is complete.
> See `PLANNING_GUIDE.md` for how to create the plan and tracker.

---

## One Task at a Time

Tasks are executed **one at a time**. Never batch multiple tasks into a
single work unit.

The cycle for every task:

1. **Pick the next task** — take the next unblocked `💡 to-do` task
2. **Do the work** — implement, test, verify exit criteria
3. **Stop and present** — show what changed, mark task `✅ done`
4. **User reviews** — the user inspects the diff, asks questions, requests changes
5. **User commits** — the user decides when to commit
6. **Repeat** — move to the next task only after the previous one is committed

---

## Rules

### One task, one cycle

Do not start T-002 until T-001 is reviewed and committed. Even if tasks
seem small or related, each one goes through the full cycle. No exceptions.

### The user commits

Do not run `git commit` unless the user explicitly asks. The review and
commit decision belongs to the user.

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
