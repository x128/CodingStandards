# CodingStandards

Reusable coding standards and Claude Code skills for consistent, clean code across projects.

## Structure
```
CLEAN_CODE.md    # Language-agnostic principles
KOTLIN.md        # Kotlin/KMP standards
SWIFT.md         # Swift/iOS standards
skills/          # Claude Code skills (slash commands)
```

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
