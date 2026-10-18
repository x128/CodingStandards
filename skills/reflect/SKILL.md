---
description: 'Look back at a piece of work: where the result differs from the expected, which line of a standard, skill or assignment caused it, and what to change. Use after a refactoring, a review, a change of the standards, or a correction of the user.'
---

# Reflect Skill

Looks back at one piece of work — a refactoring, a review, a change of the standards, a correction
of the human — and says what it teaches: where the result differs from what was expected, which
line of a standard, a skill or an assignment caused it, and what to change. It runs in an agent
that did not do the work: the one who did it judges it too kindly.

## Instructions

1. **The facts.** What was expected: the task, or the human's request in their words. What
   happened: the results, each number with where it comes from, and the diff. Every correction of
   the human during the work, in their words.
2. **The answers**, in plain short sentences:
   - Where does the result differ from what was expected?
   - What caused it? Quote the line of a standard, a skill or an assignment that the agents
     followed. "The agents did X" is what happened, not the cause.
   - Was a reason, a unit, a warning or a convention lost? Where did it go?
   - Did anything go against a decision of the human — in the plan's Decisions Log, or in the
     file of decisions that the caller names?
   - Which correction of the human would the text have made unnecessary, and which file should
     say it ([MAINTAINER_TRAINING.md](../../MAINTAINER_TRAINING.md))?
   - What worked and should stay?
3. **The changes.** For each: the lines old and new, the evidence with its source, how sure you
   are and what would prove it wrong, what measuring it would cost, and whether it needs the human
   (a new or removed rule, anything against one of their decisions, anything they would want to
   see first) or can be tried next and brought back with its result.
4. **The report**, short: expected and happened; causes; lost or contradicted; keep; next changes.

## Allowed Prompts
- Read the standards, the decisions of the human, the work and its results
- Write nothing but the report

## Example Usage

```
/reflect the refactoring of the player feature
/reflect the human's correction about deleted comments
```
