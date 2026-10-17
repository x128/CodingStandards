# Tripsplit

Shared expenses of people who travel together. Kotlin on the JVM.

## Standards
Follow `CodingStandards/CLEAN_CODE.md`
Follow `CodingStandards/KOTLIN.md`
Follow `CodingStandards/ARCHITECTURE.md`
Follow `CodingStandards/TESTING.md`
Follow `CodingStandards/PLANNING_GUIDE.md`
Follow `CodingStandards/EXECUTION_GUIDE.md`

## Project
- What to build: `REQUIREMENTS.md`. The product owner cannot be asked. Where a standard tells you to ask the owner, take the answer from `REQUIREMENTS.md`, or decide yourself and record the decision in the Decisions Log of the plan.
- Plan: `IMPLEMENTATION_PLAN.md` · Tasks: `TASK_TRACKER.md`. The whole of `REQUIREMENTS.md` is the first release: nothing in it is put off.
- Package: `app.tripsplit`
- Sources: `src/main/kotlin` · Tests: `src/test/kotlin`. The name of every test class ends in `Test`.
- Build and run all tests: `./build.sh`. A task is not done until it passes. The script uses tools that lie outside the project folder; that is as it should be.
- What the project can use: `docs/LIBRARIES.md`. Nothing else is available.
- Lint: `./lint.sh`. It fails on a comment in `src` other than the test markers `// Arrange`, `// Act`, `// Assert` or `// Given`, `// When`, `// Then` (CLEAN_CODE.md, "Comments"; a kind that row D-003 of the Decisions Log allows is listed as a grep pattern in `comment-allowed.txt`), and on a function whose CRAP score is above 8 (CLEAN_CODE.md, "One Thing per Function"; an exception recorded in the Decisions Log is listed as `Class.function` in `crap-exceptions.txt`). A task is not done until `./build.sh` and `./lint.sh` pass.
- This is Kotlin on the JVM only. There is no Android, iOS, Compose, Koin, SQLDelight or Voyager. Where a standard names one of them, apply the rule with what this project has: constructors and plain Kotlin in place of Koin, `lib.ui.ViewModel` in place of an Android or Voyager ViewModel, `lib.store` in place of SQLDelight. A screen is its ViewModel with its state and its events.
- Review is delegated. When the exit criteria of a task are met and `./build.sh` passes, mark the task done in `TASK_TRACKER.md` and take the next one. Nobody commits: there is no git here, do not run git.
