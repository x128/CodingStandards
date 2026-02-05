# Claude Code Skills

Reusable skills (slash commands) for Claude Code that enforce clean code principles.

## Available Skills

| Skill | Command | Purpose |
|-------|---------|---------|
| [review](./review.md) | `/review` | Code review against clean code standards |
| [refactor](./refactor.md) | `/refactor` | Guided refactoring with patterns |
| [test](./test.md) | `/test` | Test generation with best practices |
| [document](./document.md) | `/document` | Documentation generation |

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
# Document file/class
/document src/services/ExportService.kt

# Generate API reference
/document --api

# Architecture overview
/document --architecture
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
