---
description: 'Check that a change lost no information: for every removed line, find where its meaning is now. Use after a change removes comments or text.'
---

# Loss Check Skill

Checks that a change lost no information. It takes two versions — two files or two folders — and
for every removed line finds where its meaning is now, then reports what is lost. It is run by an
agent that did not make the change: the author finds what they meant to keep, not what they
dropped.

## Instructions

1. **The versions.** Take the two named versions; without them, ask which two. Compare them with
   `diff -ru`.
2. **What was removed.** One entry per removed comment block or line of text, with the line it
   described in the old version. A line that only moved is not removed.
3. **What it taught.** For each entry, say what a reader learned from it that the text around it
   did not say: a unit, a reason, a limit, a source, a warning, what a value stands for, what a
   function promises.
4. **Where it is now.** One verdict; a verdict that names a place gives it — file, line, and that
   line quoted:
   - repeated the code;
   - in the code: a name, a type, a constant or a check says it;
   - in a test: its name or what it asserts says it;
   - in a document: the plan, the tracker, a standard, or the commit message or the report that
     gives it;
   - no longer needed: what it described is gone, and nothing needs the information;
   - partly: say which part is missing;
   - lost.

   "In the code" means a reader of the new version learns it there, not that it can be worked out.
   A reason, warning, unit, source or promise taken out of the code that now lives only in a test
   or a document is not lost, but it is not where the reader of the code looks (CLEAN_CODE.md,
   "Comments"): name it.
5. **A second look.** Another agent checks every "lost" and "partly" and every fifth of the rest:
   for a loss it searches hard for the meaning; for a find it opens the place and asks whether a
   reader learns the same thing there. A quote that is not in the file is not a find.
6. **Report**, as EXECUTION_GUIDE.md, "Reporting to the user", says: the count of entries by
   verdict; what is lost or partly lost; what is not where the reader of the code looks; and for
   each of these, what will carry it — a name, a type or a check with its test — or that the line
   goes back.

A change with a loss, or with a meaning of the code left only in a test or a document, is not
finished: the meaning goes where it belongs before the change is shown or committed.

## Allowed Prompts
- Read both versions; run `diff -ru` and scripts that check quoted places
- Start one more agent for the second look
- Write nothing but the report

## Example Usage

```
/loss-check standards-before/CLEAN_CODE.md CLEAN_CODE.md
/loss-check old/src new/src
```
