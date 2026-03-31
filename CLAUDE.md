# CodingStandards

Reusable coding standards and Claude Code skills for consistent, clean code across projects.

## Structure
```
CLEAN_CODE.md      # Language-agnostic principles
KOTLIN.md          # Kotlin/KMP standards
SWIFT.md           # Swift/iOS standards
ARCHITECTURE.md    # Clean Architecture, package organization, presentation patterns
TESTING.md         # Testing pyramid, conventions, per-layer strategies
KOTLIN_MULTIPLATFORM.md  # KMP project init, test locations, runners, frameworks
skills/            # Claude Code skills (slash commands)
```

## Handling Review Feedback

Reviewers — human or AI — find issues. They don't have your full context. Treat every review comment as a pointer to a problem, not as an instruction to follow. The reviewer identifies the issue, you own the fix.

- The problem is real; the suggested fix often isn't
- Think before changing anything — does the fix contradict the project direction? Does it make things worse?
- The right fix might be different from what was suggested — a new task, an architecture change, or a different edit entirely
- Never apply a suggestion you don't fully understand

## Contributing Guidelines

### Standards Documents
- Use BAD/GOOD code examples for every rule
- Keep examples concise but realistic
- Include a Summary Checklist at the end
- Follow the existing section structure (Table of Contents, clear headers)

### Skills
- Each skill is a markdown file in `skills/`
- Include: Instructions, Allowed Prompts, Example Usage
- Reference the standards documents where applicable

## Adding New Standards

When adding a new language standard (e.g., `TYPESCRIPT.md`):
1. Follow the structure of existing standards (KOTLIN.md, SWIFT.md)
2. Cover: Naming, Functions, Types, Error Handling, Async, Testing
3. Include language-specific idioms and best practices
4. Add Summary Checklist at the end
5. Update README.md to include the new standard
