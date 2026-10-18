---
description: Turn a disagreement of the user with the task loop into a rule or setting in .review/. Use when the user says a finding was real, a task needed their eyes, or asks where a problem entered.
---

# Policy Skill

Turns a disagreement of the user with the task loop into a rule or a setting of the project, so
the loop's maintainer learns the user's judgment. It works only in the project's `.review/` and
follows the two limits of MAINTAINER_TRAINING.md: a rejected finding never becomes a rule, and
nothing here counts or scores anything.

## Instructions

First work out which kind of disagreement it is:

| The user said | Track | Goes into |
|---|---|---|
| "that finding was real" | A — findings | `.review/REVIEW_POLICY.md` |
| "you should have shown me this task" | B — advancing | `.review/land.conf` |
| a trigger of Track C fired | C — where it entered | wherever it entered |

"Stop flagging this" is none of them: a rejection usually means "not yet". Record why it was
rejected, and leave the reviewer looking. In every track, fix both the outcome and what produced
it.

### Track A: a finding's verdict was wrong

1. **The finding and both verdicts**, from the latest `.review/runs/*/verdicts.json`; something
   not in a run is written down in the same shape.
2. **Why, once.** The reason must hold beyond this case ("untrusted input changes the confidence
   threshold"); ask one question if it is not clear.
3. **A check first.** If a linter, a type checker or an architecture test could catch it, it is
   not a policy rule: offer to add it to `.review/gates.sh`. Policy is for judgments no tool makes.
4. **An existing rule.** Search `REVIEW_POLICY.md`; if the case is a special case of a rule,
   narrow that rule or add an `Overrides` line instead of adding a rule. A wrong match is usually
   a missing path scope.
5. **Write the rule:**

   ```markdown
   ### R-nnn: <one-line statement>

   - **Level**: MUST | SHOULD | MAY
   - **Applies to**: <path globs>
   - **Verdict**: accept, severity <from the level> | reject | escalate
   - **Overrides**: R-nnn (when two rules can match)
   - **Rationale**: <one or two sentences that hold beyond this case>
   - **Added**: <date>, after <task> / <finding id>
   ```

   Ids are never reused. MUST is a blocker, SHOULD major, MAY minor.
6. **Log it:** one line in `.review/decisions/findings.jsonl` with the rule id (format:
   `templates/review/project/decisions/findings.example.jsonl`).

### Track B: advancing was wrong

1. **The task record** in `.review/decisions/tasks.jsonl`.
2. **Which way:**
   - it went on past something the user needed to see: take the category out of
     `ADVANCE_CATEGORIES` at once, and add the path to `RISK_PATHS` if it must never go on without
     the user;
   - it asked about something trivial: say you think the category is quiet, and nothing more —
     adding a category is the user's own edit, and no tally of quiet tasks is kept.
3. **Update the record** with what really happened; never rewrite it to look better.

### Track C: the symptom is here, it entered earlier — `--trace`

Any one of these starts it:
- the user objects to a finished task, and what they object to is not in its diff;
- the user asks to refactor code the loop itself wrote;
- the same finding keeps getting `decision_rule: out-of-task-scope` in one area;
- one policy rule keeps firing in the same area;
- a replication finding names a shape the loop introduced.

Write no rule about the symptom itself; fix it where it entered.

1. **The symptom as a fact** someone can go and look at ("every caller re-parses the header
   because `parse()` returns a borrowed slice"), and the files it lives in. If it cannot be said
   that concretely, tell the user so and stop.
2. **Walk back** through `.review/decisions/tasks.jsonl` and the commit trailers (`Task-Id`,
   `Findings:`) of every task that touched those files, newest first; where the user commits by
   hand there are no trailers, so walk the log and the files each task touched.
3. **Find where it entered**, not where it spread.
4. **Read what the loop said then:** that task's `verdicts.json`. Often the reviewer raised it and
   the maintainer rejected it.
5. **Fix it where it belongs:** seen and rejected — a Track A rule; seen by nobody — a check in
   `gates.sh` if one can catch it, otherwise a rule that tells the reviewer to look; a task scoped
   wrong or with weak criteria — a planning fix (PLANNING_GUIDE.md).
6. **Append a retraction** for that task (the `type: "retraction"` line of
   `templates/review/project/decisions/tasks.example.jsonl`); never edit the original. Write its
   `cause` for someone who meets this in six months.
7. **Re-check categories:** if the retracted task's category is in `ADVANCE_CATEGORIES`, take it
   out.

Report the chain walked, where it entered, and what changed.

### `--prune` and `--eval`

- `--prune`: report rules that never fired, duplicates, and what a linter could do instead;
  propose deletions, delete nothing without a yes.
- `--eval`: run the maintainer over the golden set and list every case where its verdict differs
  from the user's, with the rule that fired — cases, not a score.

### Rules

- You draft; the user confirms every rule. No rule is deleted without asking.
- Never write inside `CodingStandards/`.
- A disagreement that produced no rule will come back: write it down, or record why it is a
  one-off.
- Policy changes are committed like code (EXECUTION_GUIDE.md, "Who writes to git").

## Allowed Prompts
- Read `.review/**`, the diff and source files
- Write `.review/REVIEW_POLICY.md`, `.review/land.conf` and the decision logs
- Propose changes to `.review/gates.sh` (ask before editing)
- Never edit source files; git read-only

## Example Usage

```
/policy                          # record the last disagreement
/policy F-003 was a real bug     # a finding's verdict (Track A)
/policy T-021 needed my eyes     # went on past something you needed (Track B)
/policy --trace "every caller re-parses the header"   # where a symptom entered (Track C)
/policy --prune                  # unused, duplicate and lintable rules
/policy --eval                   # where the maintainer differs from the golden set
```
