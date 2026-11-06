---
description: >-
  Groom an epic before its work starts, or again after a change the plan rests on: is it still the
  one thing the user gets, are its tasks the ones that thing needs, what is now known about each —
  then update the tracker with the user. Use when an epic is about to start, when a change touches
  the plan, or when asked to groom or audit an epic or its exit criteria.
---

# Groom Skill

Looks at one epic the way the owner of the product does, when its work is about to start: what the
user will be able to do after it, whether its tasks are the ones that thing needs, and what is now
known about each task. By then more is known than when the plan was written: the epics before it are
done, and their tasks have shown what they hand on. The skill turns that into a corrected list of
tasks with their exit criteria, and asks the user what only they can say. It needs the requirements,
the plan and the tracker, and writes only to them, after the user has answered.

## Instructions

### When

- **An epic is about to start**: before the first of its tasks is taken into work. The task loop
  calls the skill then.
- **A change the plan rests on**: a decision, a use case, the architecture, a task found wrong or
  missing — anything after which a later epic or its tasks no longer hold. Every epic not yet done
  that the change touches is groomed, the next one first.
- **When the user asks.**

### Steps

1. **The epic.** The one named, or the next epic with no task started. With `--change`: the change,
   and the epics not yet done whose line, tasks or criteria rest on what changed.
2. **What the user gets.** Read the epic's line in the list of epics, the user's own words it comes
   from, and what the done epics have built. Is it still one thing the user can do that they could
   not before (PLANNING_GUIDE.md, "Epic Rules")? It may now look like two things, need a task of a
   later epic, or hold a task its thing works without. Say so, with the change you propose.
3. **The tasks.** For each: is it needed for the epic's thing, is anything the thing needs missing,
   does the order hold. Tasks to add, move, merge or cancel are proposed, not made.
4. **The criteria.** For each task, what is known now: what the user said, what done tasks hand it,
   what the product has no choice about — written as criteria (PLANNING_GUIDE.md, "Task Rules"). A
   choice about the product, or a conclusion of the agent, is a question, never a criterion. A fact
   nobody measured, or one the sources disagree on, is said to be so. The gaps about what the user
   sees come first. A task may still have no criteria.
5. **Ask.** One short report to the user, in the user's language: the epic's line as it now stands,
   the proposed changes to its tasks, and the questions. Asked now is what the epic rests on: a
   change to its line, a change to its tasks, and what its first task waits on. A question a later
   task of the epic waits on stays in that task, and is asked when the task before it is done. A
   choice that changes nothing the user sees or does is decided, and the report names it in one
   line; in doubt, it is asked. Each option is one the user could pick, and says what it costs; a
   recommendation says why. Questions with answers to choose from are asked as PLANNING_GUIDE.md,
   "How the questions are asked", says.
6. **Write**, once the user has answered, only what the report showed and the answers settled: the
   tasks and their criteria in the tracker, the plan's index of epics and tasks where tasks changed,
   a decision in the requirements. IDs follow PLANNING_GUIDE.md, "Ongoing Maintenance". Then run
   the cross-check of PLANNING_GUIDE.md, Step 3.

### Rules

- Only the epic in front is groomed, or with `--change` the ones the change touches: the details
  of the epics further on are not known yet.
- The user decides the list of epics and each epic's line; the skill proposes.
- No code is written and no task is started here.
- Nothing is written before the user answers.

## Allowed Prompts
- Read the requirements, the plan, the tracker, `.review/decisions/**`, source files and the
  standards
- Write the tracker, the plan's index of epics and tasks, and the requirements, after the user
  answers
- Git: read-only

## Example Usage

```
/groom                       # the next epic, before its first task
/groom "Read a PDF"          # a named epic
/groom --change T-014        # after a task that changed what later epics rest on
```
