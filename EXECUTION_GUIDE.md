# Task Execution Guide

> The rules for getting a task from to-do to committed. See `PLANNING_GUIDE.md` for how to create
> the requirements, the plan and the tracker.

**These rules do not depend on who does the work.** They hold when the user writes the code by hand,
when Claude writes it on request, and when the automated loop in `TASK_LOOP.md` runs it. That loop
is a machine built *on* these rules — it mechanizes them and adds a way to delegate the commit and,
as far as the project decided, what follows it. It is not an alternative set of rules, and this
document does not describe it.

---

## Who runs the work

- **By hand** — the user writes the code. Nothing here constrains that; the rules describe what
  makes a task finished, not who types.
- **On request** — Claude implements, presents, the user reviews and commits (see "Who writes to
  git").
- **Through the loop** — where a project has `.review/`, this is the default path for task work,
  with or without the skill name being typed. See `TASK_LOOP.md`.

Default means default: any change can be made outside the loop on request,
without a reason. "Just make this change", "skip the review", "I'll write it
myself" are complete instructions — follow them and do not re-propose the loop.
What is not optional is honesty about what actually ran; never present a partial
run as a completed one.

`/maintain`'s description is what makes "next task", "do T-014" and
"continue" start the loop.

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

Steps 4 and 5 are the only ones the loop changes: there, the user reviews the finished task rather
than the raw diff, and, where the requirement "Who writes to git" lets the loop commit, the commit
happens through the landing contract instead of by hand, and before the user looks; where that
requirement's last answer lets the loop merge, so does the merge into main. That order is what the
user chose in that requirement. Who decides that the task is finished — step 4 — never moves: an
objection to a task already in main is a new task on top of it, or a revert the user makes.

---

## Rules

### One task, one cycle

Do not start T-002 until T-001 is reviewed and committed. Even if tasks
seem small or related, each one goes through the full cycle. No exceptions.

### Who writes to git

The project decides, and records it in the requirement "Who writes to git"
([PLANNING_GUIDE.md](./PLANNING_GUIDE.md)): agents only read git and the user commits; or the loop
takes a finished task further, through `land.sh` and `publish.sh` (below): it commits and pushes a
branch, it also opens a pull request, or it also merges that pull request. Those answers are about
the loop, in a project that has it. Everywhere else, and at every answer, git is read-only for
agents. It is the user's preference, not a rule of these standards, and the user may change it.
Before it presents its first finished work, the agent asks that question (PLANNING_GUIDE.md, "Three
questions of every project") if it is not answered, and writes the answer into the requirements.
When the user asks in chat for a commit, give the files and the message; the user makes it.

Outside `land.sh` and `publish.sh`, and `/research`'s own `land.sh` for its folder where the user
answered that it commits, git is read-only for agents:

These rules are about the project's repository and its submodules. A test script
that builds a throwaway repository in a temporary folder and deletes it
(`templates/review/lib/selftest.sh`) writes no git the user owns.

**Never run a git command that changes anything.** Not `add`, `commit`, `reset`, `checkout`,
`switch`, `restore`, `stash`, `rm`, `mv`, `branch`, `merge`, `rebase`, `push`, `pull`, `tag`, or
`clean`. Read-only only: `status`, `diff`, `log`, `show`, `blame`, and `remote` to list the remotes.
The same goes for `gh`: never `gh pr create`, `merge`, `close` or `edit`, `gh api`, or `gh repo`;
`gh pr view`, `gh pr checks` and `gh auth status` only read.

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

### The loop's landing: `land.sh` and `publish.sh`

Where the requirement "Who writes to git" says so, the loop commits — that is the point of the
maintainer role — and, as far as it says, pushes, opens a pull request and merges it. It does so
through exactly two scripts. The answer is the permission: `/maintain --init` writes it to
`.review/land.conf`, and one line there revokes it. `land.sh` refuses unless eight conditions hold,
stages *and commits* only the task's declared files, the files the loop keeps as it goes (the
tracker, the test cases) and the end-to-end harness the task changed; it has no code path for push,
amend or force, and the only branch it may create or move to is `task/<id>`. `publish.sh` has no
code path for commit, amend or force, and publishes only what landings made. The loop reaches main
only through a pull request, never a direct commit
([TASK_LOOP.md § Landing](./TASK_LOOP.md#landing)).

Everything about the loop's landing is what makes it different from an agent running `git commit`:
it is delegated in advance, narrow in what it can do, revocable, and auditable in the commit
trailers. **Nothing generalizes from it.** In a chat session, and everywhere outside the loop, git
is read-only for agents whatever the requirement says — including "just staging" and "just tidying
up".

### The task boundary belongs to the user

By hand or on request, the user reviews the diff and commits it. Through the loop, the user reviews
**the finished task** — what changed and what the checks showed — and the
maintainer commits it where the requirement lets the loop commit; otherwise the user does.

The unit of review differs; the authority does not. The user, never the agent, decides that a task
is genuinely done and that work may continue. The maintainer may only stop asking for a category of
task when the user has said so — nothing measures its way out of asking
([MAINTAINER_TRAINING.md](./MAINTAINER_TRAINING.md)).

### Reporting to the user

Every message to the user is written by [.agents/skills/write](./.agents/skills/write/SKILL.md). The
points below are about the work, not the text; rules for the text were measured to make messages
worse next to the skill ([MEASURED.md](./.agents/skills/write/MEASURED.md)).

- **During long work, say what runs and what comes next** when a step starts or ends, in the user's
  terms: what it does to their product, not a step name. Never leave the user without word.
- **Keep working while the next step serves the request.** Ask only what the user must decide. Never
  stop to ask whether to run the next step of the work they asked for, or whether it is worth its
  tokens.
- **Ask in the chat, one thing at a time**, except where a guide or skill gathers them: the planning
  questions come a block at a time (PLANNING_GUIDE.md, Step 0); review findings go where
  `/code-review` sends them; books are asked for in one list. A long file does not replace the
  questions; it is named by its absolute path for the rest.
- **Each option says something the others do not, and its label keeps it**: who does what, as a
  phrase, never one word cut out of it. Two wordings of one meaning are not a choice; take the one
  the user already used, and do not ask.

### Work given to other agents

Their assignment names the task and the standards they follow — these documents, the project's
requirements and plan, its `.review/` — and adds no rule of its own. A rule they need that the
standards lack goes to the user first. The one exception is a measurement of these standards, whose
skill lists the rules its assignments add.

In a project with the task loop, each agent runs on the model and effort of its role in
`.claude/agents.conf` (TASK_LOOP.md, "Models"), passed when it starts. Before agents start, the user
reads in one line how many, on which model, and roughly how many tokens they will take; after they
finish, how many they took.

### A review's findings

A finding that reaches the one who wrote the change — from a person, `/code-review` or the loop's
review — is not an instruction, and it may itself be wrong. Check each against the code and the
task — under the bar of a later round of `/code-review`, as its "Another round" says — those you are
least sure of first, and answer it:

- real: the fix is at its cause, which may be elsewhere than the finding points — another place, an
  architecture change, a new task proposed to the user — and in your own words, never the suggested
  fix pasted; check that it makes nothing worse. A fix that goes against a decision of the project
  is not a fix; it is a question for the user;
- wrong, a choice of the task reported as a defect included: say why, naming the line or the
  decision that shows it — a decision of the user, quoted from where it is written, never your own
  earlier reasoning;
- real but another task's: propose writing it into that task, or into a new one;
- unsettled once checked: say what was checked and what is still assumed.

A finding that comes again is judged again, and it is never fixed for coming again: the earlier
answer stands unless the code, the task or your view of them changed. Say why it came: the reviewer
is wrong about the code, or it lacked a decision of the task — then propose writing that decision
where the next reviewer reads it. Never apply a suggestion you don't fully understand.

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
