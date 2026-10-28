# Dispatcher Training

> How to stop making the same mistake twice.
>
> The user says something is wrong. That becomes a line in a file. The file gets
> read the next time the same situation comes up.

---

## Why a file

Everything worked out during a session disappears when the window closes. A
correction that was only said in the conversation is gone the same day, and the
same mistake comes back tomorrow.

A file in git is the only place it survives. That is the whole reason this
document exists.

**"Remembered" is not a place.** Assistant-side memory — a memory directory, a
`MEMORY.md`, any store the tool writes on its own — sits on one machine, outside
git. A rule put there is gone on the next clone, and the session that wrote it
acts as though the correction is handled. Never record a correction there, and
never offer to.

---

## What to do when the user says something is wrong

1. **Write down what they said, in their words**, right away, with what is
   still open, where the next session reads it: for a project, as a row of the
   Decisions Log of its plan, "TBD" under Chosen and the task it came up in under
   Rationale; for these standards, into the file the table below names. The rule
   goes into its file once a small check shows it does what the user asked: agents
   given the file before and after the change, on the same situation, and the
   difference is the one asked for. Chosen then says the rule and where it went. The
   user is asked only before a check that costs much.

2. **Work out *when* it happened — not what it was about.** While installing a
   compiler? While writing the report? While looking for bugs in the code?
   While running git?

3. **Put the rule in the file that gets read at that point.**

4. **Have it committed**: a file of the project as its plan's row "Who writes to
   git" says (EXECUTION_GUIDE.md, "Who writes to git"), a file of these
   standards by the user. A rule that is not committed lasted one session.

Step 2 is the one that goes wrong. A rule about writing reports, put into the
document about reviewing code, will never be read while writing a report.

| It happened while | The rule goes in |
|---|---|
| installing or configuring a build | the language document (`KOTLIN_MULTIPLATFORM.md`, …) |
| planning, before any code exists | `PLANNING_GUIDE.md` |
| doing a task | `EXECUTION_GUIDE.md` |
| checking a finished change before it is shown as done | `skills/qa/SKILL.md` |
| giving work to another agent | `EXECUTION_GUIDE.md`, "Work given to other agents" |
| writing the report back to the user | `skills/write/SKILL.md`; `EXECUTION_GUIDE.md`, the reporting section |
| looking for bugs in the code | `skills/code-review/SKILL.md` |
| refactoring code to the standards | the plan's Decisions Log for this project; `skills/refactor/SKILL.md` for how a refactoring runs |
| running the automatic loop | `TASK_LOOP.md` |
| measuring these standards | `skills/self-improve/SKILL.md` |
| editing these standards | `CLAUDE.md` of this repo, "Contributing Guidelines" |

---

## Do not turn a rejected finding into a rule

When the user rejects something, it usually means *not yet* — not *never*.

What happened in this repo: a review produced twenty findings about the code.
The user rejected all twenty. Not because they were wrong — because the project
had no plan yet, and the plan is written before the code. Every one of those
findings still matters, later.

So:

- Never keep a list of things not to raise again.
- Never count how many times something was rejected.
- No file here grows the more it is used.

---

## Never decide whether the user looks

The user decides what they read. Nothing here works out that a piece of work is
small enough that they need not see it, and nothing keeps score of how often
they had no objection.

Saying what you think is fine: *"I think everything in this review is small
stuff."* Then show it anyway. Saying it is a report. Deciding it for them is
taking away the one judgment that has to be theirs.

---

## Two things to say about a review

Both belong to the dispatcher. Neither belongs to the review itself — a review
asked whether its own output was worth reading will always say yes.

**Is this review about the right thing?** Look at where the work actually stands
before reading a single finding. If the plan is supposed to come before the code
and there is no plan, then the code was written out of order, and going through
it line by line misses what is wrong. The honest answer there is one finding,
not twenty.

**Is anything important left in it?** If everything in a review is about naming,
a bit of duplication, or something nobody ever sees, the review is finished,
however long it is. Say so.

The dispatcher learns these two the same way as everything else: say them out
loud, and when the user disagrees, the reason goes into this file — as a
statement about the whole review, never as a ban on one kind of finding.

---

## A rule for this project, or a rule for every project

| Written in | Applies to | How it moves |
|---|---|---|
| the project — its plan's Decisions Log, its `.review/` | that project only | it does not move on its own |
| `CodingStandards/` | every project | a line here that is wrong is fixed; a rule that is not here waits for a second project |

A rule that came out of one project belongs to that project: copying it here
after one project turns one project's accident into everyone's rule. Fixing a
line already here is not that. Wrong means two documents here say different
things, or a project followed a line here and got a result these documents call
a mistake.

---

## Checklist

- [ ] The correction is written in a file, not only said in the conversation
- [ ] Filed by when it happens, not by what it is about
- [ ] No rejected finding was turned into a rule
- [ ] Nothing was counted or scored
- [ ] Nothing decided for the user whether they look
- [ ] Nothing was copied into `CodingStandards/` out of a single project
