# Policy Skill

Record a disagreement with the maintainer and turn it into a rule. This is how
the maintainer learns your judgment.

Reference: [MAINTAINER_TRAINING.md](../MAINTAINER_TRAINING.md) — in particular
the two limits it sets on this skill: a rejected finding never becomes a rule,
and nothing here counts or scores anything.

## Instructions

Two kinds of disagreement, two destinations. Work out which one you are looking
at before writing anything.

| You said | Track | Goes into |
|----------|-------|-----------|
| "that finding was real" | A — findings | `REVIEW_POLICY.md` |
| "you should have shown me this task" | B — advancing | `land.conf` |
| any Track C trigger fires (see below) | C — attribution | wherever it entered |

**"Stop flagging this" is not on that list.** A rejection usually means *not
yet* — the finding is real and the project is not ready for it. Writing a rule
that suppresses it makes a temporary answer permanent, and the file grows every
time the review is used. Record why it was rejected, and leave the reviewer
looking.

Either way, do the **double commit**: fix the outcome *and* fix the thing that
produced it.

### Track A: a finding verdict was wrong

1. **Identify the finding and both verdicts.** Pull it from the latest
   `.review/runs/*/verdicts.json`. If the user is describing something not in a
   run, capture it in the same shape anyway.

2. **Ask why, once.** The reason must generalize. "Wrong here" is not usable;
   "untrusted input changes the confidence threshold" is a rule. One targeted
   question if it is not already clear.

3. **Check Layer 0 first.** If a linter, type checker, or architecture test
   could enforce this, it is not a policy rule — say so and offer to add it to
   `.review/gates.sh` instead. Policy is only for judgments no tool can make.

4. **Check for an existing rule.** Search `REVIEW_POLICY.md`. If the new case is
   a special case of an existing rule, **edit that rule** — narrow its scope,
   add an `Overrides` line — rather than appending. When the maintainer matched
   the wrong rule, the fix is usually a missing path scope.

5. **Write or edit the rule** in `.review/REVIEW_POLICY.md`:

   ```markdown
   ### R-nnn: <one-line statement>

   - **Level**: MUST | SHOULD | MAY
   - **Applies to**: <path globs>
   - **Verdict**: accept, severity <derived from level> | reject | escalate
   - **Overrides**: R-nnn (when two rules can match)
   - **Rationale**: <one or two sentences that generalize>
   - **Added**: <date>, after <task> / <finding id>
   ```

   Ids are never reused. Severity follows the level: MUST → blocker,
   SHOULD → major, MAY → minor.

6. **Log it** as one line in `.review/decisions/findings.jsonl`, including the
   `rule` id you just wrote. Format:
   `templates/review/project/decisions/findings.example.jsonl`.

### Track B: the advance decision was wrong

Only one direction of this is yours to act on.

1. **Identify the task record** in `.review/decisions/tasks.jsonl`.

2. **Which way was it wrong?**
   - **Advanced past something you needed to see** — the expensive direction.
     Revert that category to `ask` immediately: remove it from
     `ADVANCE_CATEGORIES` in `.review/land.conf`. If the task touched a path
     that should never advance silently, add it to `RISK_PATHS`.
   - **Asked about something trivial** — the cheap direction, and the end of it.
     Say you think the category is quiet. Do not propose unlocking it, and do
     not start a tally of the times the user had no objection: whether they go
     on looking is theirs to decide, and adding a category to
     `ADVANCE_CATEGORIES` is an edit they make
     ([MAINTAINER_TRAINING.md](../MAINTAINER_TRAINING.md) § Never decide whether
     the user looks).

3. **Update the record** with the actual outcome. Never rewrite history to make
   a past decision look better — a task that should have been shown is the most
   valuable row in the file.

### Track C: the symptom is here, it was introduced earlier — `--trace`

**Any one of these starts an attribution. No judgment call:**

- The user objects to a finished task and the thing they object to is **not in
  that task's diff**
- The user asks to refactor code the pipeline itself wrote
- The reviewer keeps rejecting the same finding as `out-of-task-scope` in one
  area — it is pointing at something no task owns
- One policy rule keeps firing in the same area — the policy is compensating for
  the code instead of the code being fixed
- A `replication` finding names a pattern the pipeline introduced

Do not write a rule about the symptom. Find where it entered.

1. **State the symptom as an observable fact** — "every caller re-parses the
   header because `parse()` returns a borrowed slice", a thing someone can go
   look at. Not "the design drifted". If it cannot be stated concretely, say so
   and stop: there is nothing to trace yet. Then list the files it lives in.
2. **Walk backwards** through `.review/decisions/tasks.jsonl` and the commit
   trailers (`Task-Id`, `Findings:`) over every task that touched those paths,
   most recent first.
3. **Find the introduction, not the propagation** — the task that first made
   this possible, not the ones built on top of it.
4. **Read what the pipeline said at the time.** Check that task's
   `verdicts.json`: very often the reviewer raised it and the maintainer
   rejected it, with the reason recorded. A rejected finding that later proved
   real is the most valuable label in the log.
5. **Write the fix where it belongs:**
   - Reviewer saw it, maintainer rejected it → Track A rule; the rejection
     reason names the missing or mis-scoped rule
   - Nobody saw it → can a gate catch this class? Layer 0 if yes; otherwise a
     policy rule telling the reviewer to look
   - The task was mis-scoped or its criteria too weak → planning fix
     ([PLANNING_GUIDE.md](../PLANNING_GUIDE.md)), not a review fix
6. **Append a retraction record** for the affected task — never edit the
   original. Format: the `type: "retraction"` line in
   `templates/review/project/decisions/tasks.example.jsonl`. Its `cause` field
   is the highest-value text in the log; write it for someone hitting this in
   six months.
7. **Re-check unlocked categories.** If the retracted task was in a category
   listed in `ADVANCE_CATEGORIES`, remove it: that category was advancing
   silently past work of a kind that turned out to need eyes.

Report the chain you walked, where it entered, and what changed as a result.

### `--prune` and `--eval`

- `--prune`: read `REVIEW_POLICY.md` and report rules that never fired,
  duplicates, and anything a linter could enforce. Propose deletions; do not
  delete without confirmation.
- `--eval`: run the maintainer over the golden set and report every case where
  its verdict differs from yours, with the rule that fired. Cases, not a score —
  a number tells you nothing about which judgment to fix.

### Rules

- Never write a rule the user did not agree to. You draft, they confirm.
- Never delete a rule without asking; rules encode decisions you weren't there
  for.
- Never write inside the `CodingStandards/` submodule. Everything this skill
  touches lives in the project's `.review/`.
- A disagreement that produced no rule will recur. Either write
  it down or record explicitly why it is a one-off.
- Policy and prompt changes are code changes: commit them like code
  ([EXECUTION_GUIDE.md](../EXECUTION_GUIDE.md)).

## Allowed Prompts

- Read `.review/**`, the diff, and source files
- Write `.review/REVIEW_POLICY.md`, `.review/land.conf`, and the decision logs
- Propose gate changes in `.review/gates.sh` (ask before editing)
- Never edit source files; git read-only

## Example Usage

```
/policy                          # record the last disagreement
/policy F-003 was a real bug     # a specific finding verdict (Track A)
/policy T-021 needed my eyes     # advanced past something you needed (Track B)
/policy --trace "every caller re-parses the header"   # attribute a symptom (Track C)
/policy --prune                  # unused, duplicate, and lintable rules
/policy --eval                   # where the maintainer differs from the golden set
```
