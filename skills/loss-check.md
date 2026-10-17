# Loss Check Skill

Check that a change lost no information. For every line the change removed — a comment in code,
a sentence or a table row in a document, a comment inside an example — find where its meaning is
now. Run it in an agent that did not make the change: the author of a change finds what they meant
to keep, not what they dropped.

## Instructions

When invoked:

1. **Scope**: the two versions that are named: two folders, or two files. Without them, ask which
   two.

2. **List what was removed**, one entry per removed comment block or removed line of text, with
   the line under it in the old version so that its context is clear. A line that was only moved
   is not removed.

3. **For each entry, say what a reader learned from it** that the line under it did not already
   say: a unit, a reason, a limit, where a rule comes from, a warning, what a value stands for,
   what a function promises. If it only repeated the code, say so.

4. **Find where that is now**, and give one verdict:
   - repeated the code;
   - in the code: a name, a type, a constant or a check says it;
   - in a test: a test name or what it asserts says it;
   - in a document: the plan, the tracker, the commit message (or the report written for it), or
     the text of a standard says it;
   - no longer needed: what it described is gone, and nothing needs the information;
   - partly: say which part is nowhere;
   - lost.
   Give the place — file, line and that line copied exactly — for every verdict that names one.
   For a comment removed from code that gave a reason, a warning, a unit, an outside source or a
   promise, also say whether a name, a
   type or a check in the code carries it (the number of a rule of the project's requirements
   belongs in a test name): if only a test or a document does, the information is not lost,
   but it is not where the reader of the code looks (CLEAN_CODE.md, "Comments").
   Say "in the code" only when a reader of the new version learns the same thing there, not when
   it can be worked out with effort.

5. **A second agent checks**: every "lost" and "partly", and every fifth of the others. For a
   loss it searches hard for the meaning; for a find it opens the place and asks whether a reader
   learns the same thing there. Check every quoted place against the files: by a script where
   there is one, otherwise by opening each place.

6. **Report**:

```
## Loss check: [scope]

[N] removed entries: [counts by verdict]

### Lost or partly lost
[Each: where it was, what it said, what is missing; or "none"]

### Not where the reader of the code looks
[Each reason, warning, unit, outside source or promise found only in a test or a document; or "none"]

### To do
[For each loss, and each entry of the section above: the name, type or check that will carry it, with its test; or put the line back]
```

A change with a loss, or a change of code with an entry under "Not where the reader of the code looks", is not
finished: the meaning goes where it belongs before the change is shown or
committed.

## Allowed Prompts
- Read both versions
- Run scripts that list removed lines and check quoted places
- Start one more agent for the check of step 5
- Write nothing but the report

## Example Usage

```
/loss-check standards-before/CLEAN_CODE.md CLEAN_CODE.md
/loss-check old/src new/src
```
