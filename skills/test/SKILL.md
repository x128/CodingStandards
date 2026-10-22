---
description: Write or improve tests by TESTING.md and say what is covered and what is not. Use when asked to add tests, cover edge cases or close coverage gaps.
---

# Test Skill

Writes or improves tests for the code it is pointed at, following TESTING.md and the language
standard, and says what is covered and what is not.

## Instructions

1. **The target.** The file or function named; with `--edge-cases`, only the edge cases of the
   function named; with `--coverage`, the code that has no tests; otherwise the code that changed.
2. **Read** the code under test, its public functions, what it depends on, and the tests that
   already exist, so the new ones match them.
3. **Write the tests** as TESTING.md and the language standard say: names, the three parts of a
   test, one behaviour per test, fakes, test data, what to test on each layer, and what not to
   test. A test checks what a caller sees, not internal state (CLEAN_CODE.md, "Test Behavior, Not
   Implementation"). For each public function left to test, cover the normal case, the edge cases
   (empty, boundary values such as 0, 1 and the maximum, invalid input), the failures, the change
   of state where there is one, and concurrent calls where the code is shared between them.
4. **Run them** on every platform the project builds, and see each new one fail once
   (TESTING.md, "Coverage Requirements").
5. **Report:** first, each test that fails because the code is wrong — the test, and the file and
   line of the code; then the cases covered, the tests written, and what is not covered and why.
   A failing test is never loosened to pass, and the code under test is changed only when the
   user chooses it.

## Allowed Prompts
- Read source files and existing tests
- Write test files
- Run tests

## Example Usage

```
/test src/services/PaymentService.kt
/test --edge-cases processOrder
/test --coverage
```
