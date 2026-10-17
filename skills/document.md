# Document Skill

Write documents in Markdown that give a reader the whole picture: the architecture, the data
flow, the decisions. The code itself explains itself through names, types, checks and tests;
moving explanations from comments into code is the `/self-document` skill.

## Instructions

When invoked:

1. **Identify scope**:
   - A module, if one is named: one document for it, written with the module template below
   - `--architecture`, or no argument: the whole system, written with the system template below

   Documents go into the project's `docs/` folder, one file per module or system.

2. **Read the code and the project's plan** (its Decisions Log in particular), so that the
   document says what the code really does and why.

3. **Write what a reader needs and cannot get from one file**: the parts and what each is for,
   what depends on what, how data moves, which decisions were made and why. Do not repeat what
   the names and types of the code already say. Do not write comments into the code.

### Module template
```
# [Component Name]

## Purpose
[Why this exists, what problem it solves]

## Responsibilities
- [What it does]
- [What it doesn't do]

## Dependencies
- [What it depends on]
- [What depends on it]

## Data Flow
[How data moves through]

## Key Decisions
- [Decision]: [Rationale]
```

4. **Keep documents true**: update a document in the same change as the code it describes;
   delete what no longer holds.

### System template

```
# [Component/System Name]

## Overview
[High-level description]

## Architecture
[Structure and relationships]

## Key Concepts
[Domain terms and their meaning]

## Usage
[How to use/interact with this]
```

## Allowed Prompts
- Read source files
- Analyze code structure
- Write documentation files

## Example Usage

```
/document src/services/
/document --architecture
```
