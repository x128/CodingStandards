# Coding Standards

Reusable coding standards and Claude Code skills for consistent, clean code across projects.

## Standards

| Document | Description |
|----------|-------------|
| [CLEAN_CODE.md](./CLEAN_CODE.md) | Language-agnostic clean code principles (SOLID, DRY, naming, etc.) |
| [KOTLIN.md](./KOTLIN.md) | Kotlin / KMP coding standards |
| [SWIFT.md](./SWIFT.md) | Swift / iOS coding standards |
| [ARCHITECTURE.md](./ARCHITECTURE.md) | Clean Architecture, package organization, presentation patterns |
| [TESTING.md](./TESTING.md) | Testing pyramid, conventions, per-layer strategies |
| [KOTLIN_MULTIPLATFORM.md](./KOTLIN_MULTIPLATFORM.md) | KMP project init, test locations, runners, frameworks |
| [PLANNING_GUIDE.md](./PLANNING_GUIDE.md) | Product planning process: intake, implementation plans, task trackers |

## Skills

Claude Code skills (slash commands) for enforcing standards:

| Skill | Command | Purpose |
|-------|---------|---------|
| [review](./skills/review.md) | `/review` | Code review against clean code standards |
| [refactor](./skills/refactor.md) | `/refactor` | Guided refactoring with patterns |
| [test](./skills/test.md) | `/test` | Test generation with best practices |
| [document](./skills/document.md) | `/document` | Documentation generation |

## Usage

### Reference in Projects

Add to your project's `CLAUDE.md`:

```markdown
# MyProject

## Standards
Follow `../CodingStandards/CLEAN_CODE.md`
Follow `../CodingStandards/KOTLIN.md`

## Skills
Follow skills from `../CodingStandards/skills/`
```

### Example Project Structure

```
Projects/
├── CodingStandards/     # This repo
│   ├── CLEAN_CODE.md
│   ├── KOTLIN.md
│   ├── SWIFT.md
│   ├── ARCHITECTURE.md
│   ├── TESTING.md
│   ├── KOTLIN_MULTIPLATFORM.md
│   ├── PLANNING_GUIDE.md
│   └── skills/
├── MyApp/
│   └── CLAUDE.md        # References ../CodingStandards
└── AnotherProject/
    └── CLAUDE.md        # References ../CodingStandards
```

## What's Covered

### CLEAN_CODE.md
- Naming conventions
- Function design (single responsibility, minimal parameters)
- Class design (cohesion, encapsulation)
- SOLID principles
- DRY, KISS, YAGNI
- Error handling
- Testing principles
- Code smells reference

### Language Standards
- Naming conventions
- Null safety
- Error handling patterns
- State management
- Async/concurrency
- Collections
- Testing patterns
- Summary checklists

### ARCHITECTURE.md
- Clean Architecture layers
- Package organization
- Presentation patterns (MVI/MVVM)

### TESTING.md
- Testing pyramid and conventions
- Per-layer test strategies
- Test naming and structure

### KOTLIN_MULTIPLATFORM.md
- KMP project initialization (submodule, versions, Gradle setup)
- Test locations and runners
- Platform frameworks

### PLANNING_GUIDE.md
- Intake questions for new products
- Implementation plan structure and rules
- Task tracker format and conventions
- Cross-check and maintenance process
