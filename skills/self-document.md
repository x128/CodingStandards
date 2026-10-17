# Self-Document Skill

Make code explain itself: move each explanation that a reader needs into a name, a type or a check
in the code, and pin it with a test. Keep a comment when nothing in the code can carry what it
says. No information is lost.
Documents in Markdown are the `/document` skill.

## Instructions

When invoked:

1. **Scope**: the file or the function that is named; with no argument, all source and test code
   of the project.

2. **Find what a reader needs and does not get from the code**: each existing comment, and each
   place where a reader would stop and ask what something is for, what unit a value is in, what
   must be true, or why it is done this way.

3. **Move each explanation into the code** ([CLEAN_CODE.md § Comments](../CLEAN_CODE.md#comments)),
   where the reader of the code will see it:
   - what a block does → a function named after what the block is for
   - what a function is for → a better name for the function
   - what a value means, or its unit → a name, a named constant or a type
   - what must be true → a type that allows nothing else, or a check that fails
   - which outside specification a value or a function follows → a name that says it
     (`SERVER_API_GUIDE_RETRY_DELAY_MILLIS`), and a test whose name names the specification
     ("waits 1500 ms between tries, as the server API guide asks"); a rule of the project's own
     requirements → the name of its test, while the name in the code says the rule in words
   - why the obvious way is not used, or a warning → a name at that place in the code that says
     it (`deleteTripRowFirst()`), and a test whose name states the reason in plain words and that
     fails when the code is changed the obvious way ("checks that the file exists, because
     length() gives 0 for a missing file")
   - what a function promises → its name (`deleteIfPresent`), a type for each outcome, and a test
   - work still to do → a task in the tracker of the project; a project without a tracker starts
     one as PLANNING_GUIDE.md describes before the comment goes
   - history, and code commented out → the commit message; if you do not write the commit,
     put it in your report for the one who does

   ```
   // BAD: comments explain the code
   // Timeout in seconds
   timeout = 30

   interface VideoExporter {
       /** Replaces the file at the destination if there is one. */
       fun export(project: Project, options: ExportOptions): ExportResult
   }

   // GOOD: the same information is in names and in a test
   BACKGROUND_TASK_TIMEOUT_SECONDS = 30

   interface VideoExporter {
       fun exportReplacingExistingFile(project: Project, options: ExportOptions): ExportResult
   }

   test("export replaces the file at the destination") { ... }
   ```

4. **Rules while you do it**:
   - A comment goes only after what it says is in the code, the tracker, or the commit message
     (in your report, for the one who writes the commit). If nothing
     can carry it yet, the comment stays and the report says why.
   - The test markers (`// Arrange`, `// Act`, `// Assert`, or `// Given`, `// When`, `// Then`) stay.
   - Behaviour does not change: the same results and the same exceptions for the same calls. A
     clearer exception message is allowed and is reported. So is a new check for a precondition
     that a comment stated; it is reported under "Public API changed".
   - A public name changes, and a public function or constructor gets a new parameter (even one
     with a default, added so that a test can replace something), only when every caller is in
     the project and is built with it. Otherwise the report proposes the change. Code compiled
     earlier, and Swift callers of Kotlin code, do not see Kotlin default arguments.
   - A test checks behaviour. A test that only says that a constant equals its own value is not
     written.
   - To see that a test fails when the code is changed the obvious way, change the code, run the
     tests and put the code back. Temporary copies go only into the project's `build` folder.
   - If row D-003 of the Decisions Log of the project's implementation plan allows a kind of
     comment (for example documentation of the public API of a published library), comments of
     that kind stay and are kept up to date. Without such a row, no new comments are written.
   - Code examples inside documents (standards, guides, READMEs) are text of the document. Their
     comments explain the document and are not changed by this skill.

5. **Check**: the build and the tests pass; every piece of information that was in a comment is
   now in a name, a type or a check in the code with a test that pins it, or (work to do) in the
   tracker, or (history) in the report, or the comment is still there.

6. **Report**:

   ```
   ## Self-documentation: [scope]

   ### In the code
   [Each name, constant, type, check or test that now carries an explanation, and the comment it replaces]

   ### For the commit message or the tracker
   [History, removed commented-out code, work still to do; or "none"]

   ### Comments kept
   [Each comment that stays, other than the test markers, and why nothing in the code can carry it yet; or "none"]

   ### Public API changed
   [Renamed public names, new constructor parameters, changed exception messages; or "none"]

   ### Proposed, not done
   [Public names that should change but have callers outside the project; or "none"]
   ```

## Allowed Prompts
- Read source files
- Analyze code structure
- Change code and tests to carry explanations

## Example Usage

```
/self-document src/services/ExportService.kt
/self-document
```
