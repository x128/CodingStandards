# Refactor Skill

Guide and perform code refactoring following clean code principles.

## Instructions

When invoked, help refactor code to improve quality:

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

// After
UserService       // Core user logic
UserNotifier      // Email handling
UserRepository    // Persistence
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
MAX_FILE_SIZE_BYTES = 50 * 1024 * 1024  // 50 MB
if (size > MAX_FILE_SIZE_BYTES) { }
```

### Remove Dead Code
When: Unreachable or unused code exists
- Delete it entirely
- Trust version control for history

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
```

## Allowed Prompts
- Read and edit files
- Run tests
- Search codebase for patterns

## Example Usage

```
/refactor src/services/OrderService.kt
/refactor --extract-method processPayment
/refactor --smell duplicate-code
```
