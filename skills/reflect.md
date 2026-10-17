# Reflect Skill

Look back at one piece of work — a measured change of the standards, a review, a correction from
the human — and say what it teaches. Run it in a fresh agent: the one who did the work judges its own
work too kindly.

## Instructions

When invoked:

1. **Gather what happened, as facts**:
   - what was expected: the hypothesis, the task, or what the human asked for, in their words;
   - what happened: the numbers with the file or run they come from, the diff, the human's reply;
   - every correction the human made during the work, in their words.

2. **Answer, each in plain short sentences**:
   - Where does the result differ from what was expected?
   - What is the cause? Not the consequence: the line of a standard, of a skill or of a prompt
     that the agents read and followed to get there. Quote it. "The agents did X" is a
     consequence; "KOTLIN.md line N says Y, and the agents did Y" is a cause.
   - Was any information lost: a reason, a unit, a warning, a convention? Where did it go?
   - Did anything go against a decision the human made: in the Decisions Log of the plan, or in
     the file of decisions that the one who runs you names?
   - Which correction of the human would have been unnecessary if the text had said it? Which
     file should say it, by when it is read ([MAINTAINER_TRAINING.md](../MAINTAINER_TRAINING.md))?
   - What worked and should stay as it is?

3. **Propose the next changes.** For each one:
   - the lines that would change, old and new;
   - the evidence for it, with numbers and their source;
   - how sure you are, and what result would prove it wrong;
   - whether it needs the human (a new direction, or against one of their decisions) or can be
     tried in the next iteration and brought back with its result;
   - what it would cost to measure.

4. **Report** in the form below. Keep it short; if it does not fit on a page, say where the rest
   is. Names from the code; every number with its source.

```
## Reflection: [what was looked at]

### Expected and happened
[Two to five sentences]

### Causes
[Each: the quoted line, where it is, and what the agents did because of it]

### Lost or contradicted
[Information lost and decisions of the human gone against; or "none"]

### Keep
[What worked]

### Next changes
[Each: the change, the evidence, how sure, who decides, the cost to measure]
```

## Allowed Prompts
- Read the standards, the recorded decisions, the work and its results
- Write nothing but the report

## Example Usage

```
/reflect the refactoring round that removed the comments
/reflect the human's correction about deleted comments
```
