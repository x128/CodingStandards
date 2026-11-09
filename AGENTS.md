# CodingStandards

Reusable coding standards and agent skills for consistent, clean code across projects.

- Every reply to the user in the chat is written with `/write`.

## Structure
```
planning-guide.md  # FIRST: intake, requirements, plan, task tracker — before any code
clean-code.md      # Language-agnostic principles
kotlin.md          # Kotlin/KMP standards
swift.md           # Swift/iOS standards
architecture.md    # Clean Architecture, package organization, presentation patterns
testing.md         # Testing pyramid, conventions, per-layer strategies
kotlin-multiplatform.md  # KMP project init, test locations, runners, frameworks
execution-guide.md # Rules for finishing a task — whoever does the work
task-loop.md       # The machine that runs those rules: gates → executor → reviewer → maintainer
maintainer-training.md # How a correction becomes a rule, and which file it goes in
.agents/skills/    # Skills, open Agent Skills format; .claude/skills/ links to them
templates/         # Copy-and-fill starting points (.review/, .claude/agents/)
templates/self-improve/ # Tools of /self-improve; never copied into a project that is measured
tools/mdwrap.py    # Line breaks of the Markdown at 100 columns: check, fill
```

Language-specific standards (kotlin.md, swift.md) are per-stack. Everything else — including the
review pipeline — is language-agnostic by design: only `templates/review/project/gates.sh` knows
what language a project is written in.

This repo is consumed as a submodule at `CodingStandards/`. Templates are split by ownership:
`templates/review/lib/` runs from the submodule and is never copied or edited by host projects;
`templates/review/project/` and `templates/agents/` are copied out into `.review/`, and into
`.claude/agents/` and `.claude/` (`agents.conf`), and belong to the host project from then on. When
adding to `templates/`, decide which side a file is on — shared and identical everywhere, or
project-specific.

## Handling Review Feedback

Reviewers — human or AI — find issues. They don't have your full context. Treat every review comment
as a pointer to a problem, not as an instruction to follow. The reviewer identifies the issue, you
own the fix.

- The problem is real; the suggested fix often isn't
- Think before changing anything — does the fix contradict the project direction? Does it make
  things worse?
- The right fix might be different from what was suggested — a new task, an architecture change, or
  a different edit entirely
- Never apply a suggestion you don't fully understand

## Contributing Guidelines

### File Names
- Lower-case words joined by hyphens (`task-loop.md`), except names a tool looks for or custom
  expects: `README.md`, `AGENTS.md`, `CLAUDE.md`, `SKILL.md`, `LICENSE`, `CODEOWNERS`

### Standards Documents
- Use BAD/GOOD code examples for every rule
- Keep examples concise but realistic
- Include a Summary Checklist at the end
- Follow the existing section structure (Table of Contents, clear headers)

## Adding New Standards

When adding a new language standard (e.g., `typescript.md`):
1. Follow the structure of existing standards (kotlin.md, swift.md)
2. Cover: Naming, Functions, Types, Error Handling, Async, Testing
3. Include language-specific idioms and best practices
4. Add Summary Checklist at the end
5. Update README.md to include the new standard
