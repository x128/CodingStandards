# Claude Code Skills

Reusable skills (slash commands) for Claude Code that enforce clean code principles.

## Available Skills

| Skill | Command | Purpose |
|-------|---------|---------|
| [review](./review.md) | `/review` | Hunt inconsistencies, potential problems, and complications |
| [refactor](./refactor.md) | `/refactor` | Refactor to the standards: one target with patterns, or the whole project in rounds; each ends with how the rules worked |
| [test](./test.md) | `/test` | Test generation with best practices |
| [document](./document.md) | `/document` | Architecture and module documents in Markdown |
| [self-document](./self-document.md) | `/self-document` | Move explanations from comments into names, types, checks and tests |
| [theory](./theory.md) | `/theory` | Theoretical foundation (THEORY.md) generation |
| [maintain](./maintain.md) | `/maintain` | Run or set up the task loop: review, land, advance |
| [policy](./policy.md) | `/policy` | Turn a disagreement with the maintainer into a rule |
| [self-improve](./self-improve.md) | `/self-improve` | Improve these standards by evidence: agents build and refactor projects, each change is measured before and after |
| [reflect](./reflect.md) | `/reflect` | Look back at a piece of work: causes in the text, what was lost, next changes |
| [loss-check](./loss-check.md) | `/loss-check` | Check that a change lost no information |

## Setup

### Option 1: Project-Level (Recommended)

Add to your project's `CLAUDE.md`:

```markdown
## Skills
Follow skills from `../CodingStandards/skills/`
```

Or copy the skills directory to your project:
```bash
cp -r /path/to/CodingStandards/skills .claude/skills/
```

### Option 2: Global Configuration

Add to `~/.claude/settings.json`:
```json
{
  "skills": {
    "paths": ["/path/to/CodingStandards/skills"]
  }
}
```

## Usage

### Code Review
```bash
# Review specific file
/review src/services/UserService.kt

# Review staged changes
/review

# Strict mode (includes minor issues)
/review --strict
```

### Refactoring
```bash
# Refactor the whole project, in rounds
/refactor

# Refactor a file
/refactor src/services/OrderService.kt

# Extract method
/refactor --extract-method processPayment

# Fix specific smell
/refactor --smell duplicate-code
```

### Test Generation
```bash
# Generate tests for file
/test src/services/PaymentService.kt

# Focus on edge cases
/test --edge-cases processOrder

# Find untested code
/test --coverage
```

### Documentation
```bash
# Move the explanations in a file's comments into names, types, checks and tests
/self-document src/services/ExportService.kt

# Document a module in Markdown
/document src/services/

# Architecture overview
/document --architecture
```

### Theoretical Foundation
```bash
# Generate THEORY.md for the project
/theory

# Focus on a subsystem
/theory src/solver/
```

## Integration with Standards

These skills reference the coding standards:
- [CLEAN_CODE.md](../CLEAN_CODE.md) - Language-agnostic principles
- [KOTLIN.md](../KOTLIN.md) - Kotlin/KMP standards
- [SWIFT.md](../SWIFT.md) - Swift/iOS standards

## Creating Custom Skills

1. Create a new `.md` file in this directory
2. Follow the structure:
   ```markdown
   # Skill Name

   Brief description.

   ## Instructions
   [What Claude should do when skill is invoked]

   ## Allowed Prompts
   [What tools/actions are permitted]

   ## Example Usage
   [How to invoke the skill]
   ```

3. Reference coding standards as needed
