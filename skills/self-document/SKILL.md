---
description: Move explanations from comments into names, types, checks and tests, losing nothing. Use when asked to remove comments or to make code explain itself.
---

# Self-Document Skill

Makes code explain itself: each explanation a reader needs goes into a name, a type or a check in
the code, pinned by a test, as CLEAN_CODE.md, "Comments", says. No information is lost: a comment
goes only when what it says is somewhere better. Documents in `docs/` are the job of `/document`.

## Instructions

1. **The scope.** The file or function named; with no argument, all source and test code.
2. **Find** each comment, and each place where a reader would stop and ask what something is
   for, what unit a value is in, what must be true, or why it is done this way.
3. **Move each explanation** where CLEAN_CODE.md, "Comments", puts it: a name, a named constant or
   a type; a check that fails; a test whose name gives the reason and that fails when the code is
   changed the obvious way; work still to do into the tracker (a project without one starts it as
   PLANNING_GUIDE.md describes); history and code commented out into the commit message, or into
   the report for whoever writes it.
4. **While doing it:**
   - A comment goes only after what it says is in its new place, where a reader learns it without
     working it out. If nothing can carry it yet, it stays and the report says why.
   - The test markers stay (`// Arrange`, `// Act`, `// Assert`, or `// Given`, `// When`, `//
     Then`). A kind of comment the project allows (the row "Comments in the code" of its plan)
     stays and is kept true.
   - Behaviour does not change: the same results and exceptions for the same calls. A clearer
     exception message, or a new check for a precondition a comment stated, is allowed and
     reported.
   - A public name or signature changes only when every caller is in the project and is built
     with it; otherwise the report proposes the change. Swift callers and code compiled earlier do
     not see Kotlin default arguments.
   - No test that only says a constant equals its own value.
   - To see that a test fails when the code is changed the obvious way, change it, run the
     tests, and put it back; temporary copies go only into the project's `build` folder.
   - Code examples inside documents are text of the document; leave their comments alone.
5. **Check:** the build and the tests pass, and every explanation that was in a comment is now in
   the code with its test, in the tracker, in the report for the commit message, or still in the
   comment. Then a fresh agent runs `/loss-check` on the code before and after.
6. **Report:** what now carries each explanation; what goes into the commit message or the
   tracker; the comments kept and why; public names, signatures and exception messages changed,
   and new checks; changes proposed and not done.

## Allowed Prompts
- Read source files
- Change code and tests to carry explanations
- Start one agent for `/loss-check`

## Example Usage

```
/self-document src/services/ExportService.kt
/self-document
```
