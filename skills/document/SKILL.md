---
description: Write or update a document of a module or of the whole system in docs/. Use when asked to document a module or the architecture.
---

# Document Skill

Writes a Markdown document in the project's `docs/` folder that gives a reader the whole picture
of a module or of the system: its parts and what each is for, what depends on what, how data
moves, and which decisions were made and why. It changes no code; moving explanations from
comments into the code is the job of `/self-document`.

## Instructions

1. **The scope.** A named module gets one document; `--architecture`, or no argument, gets one for
   the whole system. If the document exists, update it instead of starting another. A change of
   the code updates its document in the same change.
2. **Read** the code in scope and the plan's Decisions Log, so the document says what the code
   really does and why. Where the code and the plan disagree, the document says what the code
   does, and the report names the disagreement. A reason found nowhere but in a comment goes into
   the document with that comment's place; a reason found nowhere is asked, not made up.
3. **Write** what a reader cannot get from one file. Do not repeat what names and types already
   say. Delete what no longer holds; keep the rest.

   A module:
   ```
   # [Module]
   ## Purpose
   ## Responsibilities (what it does, what it does not)
   ## Dependencies (on what, and what depends on it)
   ## Data Flow
   ## Key Decisions (each with its reason)
   ```
   The system:
   ```
   # [System]
   ## Overview
   ## Architecture
   ## Key Concepts (domain terms and what each means)
   ## Key Decisions (each with its reason)
   ## Usage
   ```
4. **Report** the path of each document and what changed in it.

## Allowed Prompts
- Read source files, the plan and its Decisions Log
- Write files in `docs/` only

## Example Usage

```
/document src/services/
/document --architecture
```
