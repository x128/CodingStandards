# Code Review Skill

Review code for inconsistencies, replication, potential problems, and
complications that make it harder to read.

This is review as an activity: you ask, it reports, you decide what to do.

The task loop uses the same hunts through a machine-readable contract —
JSON findings, triage, a landing decision ([TASK_LOOP.md](../TASK_LOOP.md)).
That loop consumes review; it is not a version of it. Use this skill whenever
you want code looked at, loop or no loop.

## Instructions

### The brief matters more than the checklist

Asked to "review this code", a model reads it, finds it reasonable, and reports
that it is fine — especially code it just wrote. Nothing in that answer is
useful. The review only produces anything when it is told **what to hunt for**.

So the brief is always four specific hunts, in this order:

1. **Inconsistencies** — the same thing done two different ways. Two error
   paths with different conventions, a naming pattern broken in one place, a new
   function that ignores the module's existing idiom, a value validated in one
   caller and not the other, a comment describing behavior the code no longer
   has. Inconsistency is the cheapest defect class to find and the most reliable
   signal that something was written without looking around it.

2. **Potential problems** — what breaks under input nobody tried. Empty,
   maximum, negative, concurrent, repeated, out-of-order, partially failed.
   Where does an error get swallowed? What happens on the second call? What if
   this collection is empty? What if this runs twice at once?

3. **Complications that hurt reading** — where a reader has to hold too much in
   their head. Nesting that could be a guard clause, a name that lies, a
   parameter that only matters when another is set, a function doing two things
   with an "and" in its name, indirection with a single implementation.

4. **Replication** — the third or later copy of a shape that already exists.
   Count the instances and list them.

   This one exists to cancel a bias in hunt 1. Hunting inconsistency rewards
   code that matches its surroundings, and matching is exactly how a bad early
   decision spreads: every copy is locally consistent and nobody ever decided
   to spread it. So when the code matches the existing pattern, ask the second
   question too — **is the pattern still worth matching?** At the third copy,
   changing it is as cheap as it will ever be again.

   Report the count and the locations. Whether to refactor now is a scheduling
   decision for whoever owns the code, not a review verdict.

### Procedure

1. **Establish the target.** A path or snippet if given; otherwise the working
   diff. If the target is ambiguous, ask — do not review the whole repository.

2. **Read the surroundings before judging.** Inconsistency is invisible without
   the neighbours: the module's other functions, the existing error convention,
   how similar cases are handled elsewhere. This is where the real findings are.

3. **Run the four hunts.** Then check against the standards —
   [CLEAN_CODE.md](../CLEAN_CODE.md) and the language document — for anything
   the hunts did not already cover: naming, function size, single
   responsibility, dependency direction, error handling, dead code.

4. **Prove or downgrade every finding.** For each one, either give a concrete
   case where it goes wrong (input → wrong output, a sequence of calls, a
   failing scenario) or mark it explicitly as unproven. "This could be unsafe"
   without a case is a question, not a finding — say which one it is.

5. **Quote the code.** `file:line` plus the actual line. A finding that cannot
   be located does not exist.

### Output

```
## Review: [target]

### Inconsistencies
- [file:line] `quoted code` — differs from [where it's done the other way]. Why it matters.

### Replication
- [file:line] `quoted code` — 3rd instance of [shape]; others at [file:line], [file:line].

### Potential problems
- [file:line] `quoted code` — fails when [concrete case]. Proven | unproven.

### Complications
- [file:line] `quoted code` — [what the reader has to hold in their head].

### Nothing found in
- [areas you checked and found clean — so the reader knows what was covered]

### Summary
[What to look at first, and what can wait.]
```

### Rules

- **Silence is a valid review.** An empty section is an answer. Do not
  manufacture findings to look thorough — invented findings are more expensive
  than missed ones, because they get fixed.
- **Say what you did not check.** Untested paths, code you could not reach,
  areas out of scope. A review with unstated gaps reads as a clean bill.
- **Separate proven from suspected**, always. Pattern-matched bug priors
  (off-by-one, null, boundary) look identical to real findings and are wrong
  most of the time.
- **Do not fix anything.** This skill reports. The fix is a separate decision by
  whoever owns the code.
- **The reader owns the fix.** Findings are pointers to look at, not change
  orders — state that in the output when handing it to someone who will act on
  it ([CLAUDE.md](../CLAUDE.md#handling-review-feedback)).

## Allowed Prompts

- Read the target and its surrounding module
- Search for related patterns, existing conventions, and other call sites
- Run tests or a snippet to prove a finding
- Read the project's standards documents
- Never edit source files

## Example Usage

```
/review src/services/UserService.kt
/review                              # the working diff
/review --strict                     # include minor style issues
/review --hunt inconsistencies       # one hunt only
/review --hunt replication           # only: what is this the third copy of?
```
