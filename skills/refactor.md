# Refactor Skill

Bring code to the standards, and find out how well the standards worked. A named file, function
or smell is refactored with the patterns below; a whole project, in rounds. Every refactoring
ends with what following the rules did to the code (see "How the Rules Worked").

## Instructions

When invoked with a target, help refactor that code; with none, refactor the whole project in
rounds (below).

1. **Identify scope**: Determine what code needs refactoring:
   - Specific file/function if provided
   - Code smells found during review
   - User-identified problem areas

2. **Analyze current state**:
   - Read the code thoroughly
   - Identify specific issues
   - Understand the context and dependencies
   - Check for existing tests

3. **Plan refactoring**: Apply these patterns as needed:

### Extract Method
When: Code block does multiple things or is repeated
```
// Before
processOrder() {
    // validate (10 lines)
    // calculate (15 lines)
    // save (10 lines)
}

// After
processOrder() {
    validate()
    calculate()
    save()
}
```

### Extract Class
When: Class has multiple responsibilities
```
// Before: UserManager handles user logic + email + persistence

// After: UserService has the core user logic, UserNotifier the email handling, UserRepository the persistence
UserService
UserNotifier
UserRepository
```

### Replace Conditionals with Polymorphism
When: Repeated switch/if on type
```
// Before
if (type == "video") processVideo()
else if (type == "audio") processAudio()

// After
interface MediaProcessor { process() }
class VideoProcessor implements MediaProcessor
class AudioProcessor implements MediaProcessor
```

### Introduce Parameter Object
When: Multiple parameters travel together
```
// Before
createUser(name, email, age, address, city, country)

// After
createUser(personalInfo: PersonalInfo, address: Address)
```

### Replace Magic Numbers
When: Unexplained literal values
```
// Before
if (size > 52428800) { }

// After
MEGABYTE = 1024 * 1024
MAX_FILE_SIZE_BYTES = 50 * MEGABYTE
if (size > MAX_FILE_SIZE_BYTES) { }
```

### Remove Dead Code
When: Unreachable or unused code exists
- Delete it entirely
- Trust version control for history; the commit message says what was removed and why
- Commented-out code is dead code too; what it shows goes into that commit message

### Flatten Nested Conditionals
When: Deep nesting (>3 levels)
```
// Before
if (a) {
    if (b) {
        if (c) {
            doThing()
        }
    }
}

// After (guard clauses)
if (!a) return
if (!b) return
if (!c) return
doThing()
```

4. **Execute refactoring**:
   - Make one change at a time
   - Run tests after each change
   - Keep commits atomic and focused

5. **Verify**:
   - Ensure tests still pass
   - Check no behavior changed (unless intentional)
   - Review the improvement
   - Write what the rules did, as "How the Rules Worked" says

## A Whole Project, in Rounds

1. **Before the first round**, ask the human what must not change besides the behaviour, with
   the options "only the behaviour" and "the behaviour and the public types that the platform
   code calls", and say what a round will cost: one round of a project of about 2 500 lines cost
   0.8 to 2.6 million tokens (Tripsplit, October 2026). Above 1 million, wait for a yes.
2. **The list.** A fresh agent that will not do the work reads `CLAUDE.md`, the standards it
   lists and the code, and runs the build, the tests and the project's lint or gates. It changes
   no code. It writes `REFACTORING.md`: numbered items, most costly first, each with the file
   and line (or the rule and how to find every place), the rule it breaks (file and section of
   the standard, quoted in a few words), what to change, and the status "to do". Only departures
   from a rule of the standards, not taste. A list of an earlier round is first renamed
   `REFACTORING-ROUND-<n>.md`.
3. **The work.** Fresh engineers, one sitting each, do the items in order, one at a time: change
   the code and its tests, make the build and the tests pass, mark the item "done" with one
   sentence, or "not done" with the reason when the item is wrong. A decision of the plan that
   changes, or one the standards ask to record, goes into its Decisions Log.
4. **Check.** The tests pass and none of them checks less than before. `/loss-check` on the code
   before the round against the code after it, by an agent that did not do the work; a loss is
   repaired before the round is shown.
5. **How the rules worked**, for the round (below).
6. **Next round** while the new list has items worth their cost. With the same standards the
   lists shrink from round to round (Tripsplit: 11, 11 and 8 items in the first round, 5 each in
   the second); a list that does not shrink is an entry of "How the rules worked".

## How the Rules Worked

A fresh agent runs `/reflect` on the refactoring and adds the section "How the rules worked" to
`REFACTORING.md` (for one target, to the report). Each entry gives the quoted line of the
standard and the file and line of code:
- a change that followed a rule and made the code harder to read or to change, such as a
  function split only to lower its CRAP score;
- a rule that two agents, or the agent and the human, read differently; two files of the
  standards that say different things;
- a problem in the code that no rule names, such as one decision made in several places;
- every correction the human made, in their words.
If there is nothing, it says so.

## Hand It to /self-improve

The entries of "How the rules worked" go on, so that the next project gets better rules:
- an obvious defect of the standards (two files that disagree, an example that does not compile,
  a broken link) is fixed as [/self-improve](./self-improve.md) says in step 2;
- everything else goes into `EVALUATION.md`, "Open directions", with the project, the round and
  the quoted lines. One project is not enough to change a rule
  ([MAINTAINER_TRAINING.md](../MAINTAINER_TRAINING.md)): it is a candidate that `/self-improve`
  measures before the rule changes.
Tell the human the candidates and what measuring each would cost (`EVALUATION.md`, "Costs of
runs"). A project that `/self-improve` measures has no `EVALUATION.md` and no copy of this
section.

## Output Format

```
## Refactoring: [target]

### Issues Identified
1. [Issue] at [location]

### Refactoring Plan
1. [Step 1] - [Rationale]
2. [Step 2] - [Rationale]

### Changes Made
- [File]: [Description of change]

### Verification
- [ ] Tests pass
- [ ] Behavior unchanged
- [ ] Code follows standards

### How the Rules Worked
- [Quoted line of the standard] at [file:line]: [what following it did], or "nothing to report"
```

For a whole project, `REFACTORING.md` is the output, one per round.

## Allowed Prompts
- Read and edit files
- Run tests
- Search codebase for patterns
- Start agents for the list, the work, the loss check and the reflection, after saying the cost

## Example Usage

```
/refactor
/refactor src/services/OrderService.kt
/refactor --extract-method processPayment
/refactor --smell duplicate-code
```
