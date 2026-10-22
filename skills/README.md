# Claude Code Skills

Skills (slash commands) for Claude Code that work by the standards of this repository. Each
skill's own file says how to call it.

## Available Skills

| Skill | Command | Purpose |
|-------|---------|---------|
| [code-review](./code-review/SKILL.md) | `/code-review` | Find what is wrong in code; each finding comes with options, and the user chooses |
| [refactor](./refactor/SKILL.md) | `/refactor` | Bring code to the standards — one target, or the whole project in rounds — and say how the rules worked |
| [test](./test/SKILL.md) | `/test` | Write or improve tests by TESTING.md |
| [qa](./qa/SKILL.md) | `/qa` | Accept a finished change as its user meets it — builds, tests, criteria, motion frame by frame, states, numbers — and replay on every defect that got past |
| [document](./document/SKILL.md) | `/document` | Write a document of a module or of the system in `docs/` |
| [self-document](./self-document/SKILL.md) | `/self-document` | Move explanations from comments into names, types, checks and tests |
| [theory](./theory/SKILL.md) | `/theory` | Write THEORY.md: where the project's concepts come from |
| [maintain](./maintain/SKILL.md) | `/maintain` | Run the task loop on one task at a time, or set it up |
| [policy](./policy/SKILL.md) | `/policy` | Turn a disagreement with the task loop into a rule or setting of the project |
| [self-improve](./self-improve/SKILL.md) | `/self-improve` | Improve these standards by evidence, measuring each change before and after |
| [reflect](./reflect/SKILL.md) | `/reflect` | Look back at a piece of work: what differed from the expected, its cause, what to change |
| [loss-check](./loss-check/SKILL.md) | `/loss-check` | Check that a change lost no information |
| [research](./research/SKILL.md) | `/research` | Research a question and keep its journal, to come back to it later |

## Setup

Claude Code finds a skill only at `.claude/skills/<name>/SKILL.md` and puts its `description` into
every session. Link each skill there from the project root; the links are relative, so they work
in every clone where the submodule is initialised:

```bash
mkdir -p .claude/skills && for s in CodingStandards/skills/*/; do ln -sfn "../../${s%/}" ".claude/skills/$(basename "$s")"; done
```

Commit `.claude/skills/` with the project. A skill added to the standards later needs the same
command again.

## Creating Custom Skills

1. Create `<name>/SKILL.md` in this directory; `<name>` is the command.
2. Follow the structure:
   ```markdown
   ---
   description: What it does. Use when ...
   ---

   # Skill Name

   What it does, what it needs, what it gives back.

   ## Instructions
   [What Claude should do when the skill is invoked]

   ## Allowed Prompts
   [What tools and actions are permitted]

   ## Example Usage
   [How to invoke the skill]
   ```
3. Point to the standards by file and section instead of repeating them.
4. Name another skill only by its name and purpose, never by its steps, sections or files.
