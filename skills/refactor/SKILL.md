---
description: 'Bring code to the standards without changing its behaviour: one target, or the whole project in rounds. Use when asked to refactor or clean up code.'
---

# Refactor Skill

Refactor code to the standards: a named file, function or smell, or the whole project in rounds.

## Instructions

When invoked with a target, refactor that code; with none, refactor the whole project in rounds
(below).

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
   - Name the files and the message of each commit (EXECUTION_GUIDE.md, "Who writes to git")

5. **Verify**:
   - Ensure tests still pass
   - Check no behavior changed (unless intentional)
   - Review the improvement
   - When comments were removed, a fresh agent runs `/loss-check` on the code before and after
   - Say what the rules did (see "How the Rules Worked")

## A Whole Project, in Rounds

A round is one list of the places where the code departs from the standards, worked through by
fresh agents. The list and the checks run on the role `REVIEWER` of `.review/agents.conf`, the
work on `EXECUTOR`.

1. **Before starting**, ask one question at a time and wait for each answer: what must not change
   besides the behaviour ("only the behaviour", "the behaviour and the public types that the
   platform code calls", "I will name it"), and whether the build may download, and what. Before
   each round, say what it will cost and where the estimate comes from; above 1 million tokens,
   wait for a yes.
2. **Save the project as it is**, outside the repository, to compare against in step 5.
3. **The list.** A fresh agent that will not do the work reads `CLAUDE.md`, the standards, the plan
   and the code, runs the build and the tests, and lists where the code departs from a rule of
   the standards: the place, the rule (quoted in a few words), and what to change. Not taste. It
   decides nothing for the human: a decision the standards ask the project to make, or use case
   texts the plan lacks, are proposed to the human.
4. **The work.** Fresh engineers do the items one at a time; the build and the tests pass after
   each. Where an item's suggestion would break the rule it cites, the rule wins. An item that
   needs a download not allowed, would change what must not change, or needs the human's
   decision waits for the human.
5. **Check.** The build and the tests pass. A fresh agent reads the diff for code made harder to
   read and for tests that check less; another runs `/loss-check` against the saved project.
   What they find is repaired.
6. **Report.** First what is needed from the human: answers to what waits, whether to go on
   ("finish what waited", "one more pass over the whole project", "stop"), and the commit, which is made as the project
   decided (EXECUTION_GUIDE.md, "Who writes to git"). Then what was done, what waits, and what
   could not be run. The repository gets only the project.

## How the Rules Worked

After a refactoring, a fresh agent runs `/reflect` on it, with the human's request and every
correction in their words, and answers, each with the quoted line of the standard and the file
and line of code:
- Which change followed a rule and made the code harder to read or to change?
- Which rule was read two ways, or which two files of the standards say different things?
- Which problem of the code does no rule name?
The answers go into the report, or "nothing". A correction of the human about the project goes
where [MAINTAINER_TRAINING.md](../../MAINTAINER_TRAINING.md) says; one about the standards or a skill
is an answer here. The refactoring changes only the project.
For the answers about the standards or a skill, propose [/self-improve](../self-improve/SKILL.md) for them, and say what it would cost.

## Output Format

```
## Refactoring: [target]

### What is needed from you
[Decisions, the commits to make, or "nothing"]

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
- [Quoted line of the standard] at [file:line]: [what following it did], or "nothing"
```

## Allowed Prompts
- Read and edit files
- Run tests
- Search codebase for patterns
- Start fresh agents for the list, the work and the checks, after saying the cost

## Example Usage

```
/refactor
/refactor src/services/OrderService.kt
/refactor --extract-method processPayment
/refactor --smell duplicate-code
```
