# Maintainer Training

> How the maintainer learns your judgment. Two separate decisions, trained
> separately:
>
> **A. Which findings matter** — from your overrules, into `REVIEW_POLICY.md`.
> **B. When not to ask you at all** — from your acceptances at the task
> boundary, into per-category advance thresholds.
>
> See `TASK_LOOP.md` for the loop these decisions sit in.

---

## Table of Contents

1. [Two Decisions, Two Datasets](#two-decisions-two-datasets)
2. [Track A: Which Findings Matter](#track-a-which-findings-matter)
3. [Track B: When Not to Ask](#track-b-when-not-to-ask)
   - [Acceptance is provisional](#acceptance-is-provisional-not-final)
   - [Replication: the executor copies what is there](#replication-the-executor-copies-what-is-already-there)
   - [Attribution: a symptom now, introduced earlier](#attribution-a-symptom-now-introduced-earlier)
4. [The Eval Loop](#the-eval-loop)
5. [Automatic Prompt Optimization](#automatic-prompt-optimization)
6. [Fine-Tuning: When Not To](#fine-tuning-when-not-to)
7. [Maintenance](#maintenance)
8. [Summary Checklist](#summary-checklist)

---

## Two Decisions, Two Datasets

"Training" here does not mean gradient descent. It means rules, thresholds, and
a measurement loop.

| | Track A — findings | Track B — advancing |
|---|---|---|
| Question | Does this finding reach the executor? | Do I show you this finished task? |
| Label comes from | You overruling a verdict | You accepting a task with no remarks |
| Stored as | Rules in `REVIEW_POLICY.md` | Thresholds in `.review/land.conf` |
| Dataset | `decisions/findings.jsonl` | `decisions/tasks.jsonl` |
| Also logged | `decisions/escalations.jsonl` — what you answered when the maintainer refused to decide | |
| Metric that governs | Blocker recall | Auto-advance precision |
| Failure you cannot afford | A real blocker rejected | A task you should have seen, silently landed |

They are trained separately because they fail differently. Track A is wrong when
it filters out something real. Track B is wrong when it decides you did not need
to look — and you did.

---

## Track A: Which Findings Matter

### Capture the overrules

Every disagreement is training data and is worthless if not written down when it
happens. One record per finding you overrule, in
`.review/decisions/findings.jsonl`:

```json
{"ts": "2026-08-03T14:22:00Z", "task": "T-014", "finding_id": "F-003",
 "finding": {"file": "src/parser.rs", "line": 88, "category": "bug",
             "severity": "blocker", "confidence": "possible",
             "code_quote": "let len = header[4] as usize;"},
 "maintainer": {"verdict": "reject", "reason": "possible confidence, no counterexample"},
 "human": {"verdict": "accept", "severity": "blocker"},
 "why": "Parser input is attacker-controlled; possible-confidence memory-safety
         findings on untrusted input must be accepted, not rejected.",
 "rule": "R-011"}
```

- **Log overrules, not agreements.** Sample a few agreements periodically for
  the eval set; disagreements are what teach.
- **`why` must generalize.** "Wrong here" teaches nothing. "Untrusted input
  changes the confidence threshold" becomes a rule.
- **A record with no `rule` is a decision you will make again next week.**
- Log with `/policy` so the format stays consistent.

### Write the rule (the double commit)

Every disagreement produces two changes: the outcome is fixed *and* the rule
that produced it is fixed. In `.review/REVIEW_POLICY.md`:

```markdown
### R-011: Memory-safety findings on untrusted input

- **Level**: MUST
- **Applies to**: `src/parser/**`, `src/net/**`
- **Verdict**: accept, severity blocker
- **Overrides**: built-in decision rule 6 (unproven `possible` → reject)
- **Rationale**: Input is attacker-controlled. A possible-confidence
  memory-safety finding is cheap to verify and catastrophic to miss.
- **Added**: 2026-08-03, after T-014 / F-003
```

- **`Level` sets severity deterministically**: `MUST` → blocker, `SHOULD` →
  major, `MAY` → minor. Never ask the model to invent a severity.
- **`Applies to` is a path glob.** Most taste is context-dependent: a force
  unwrap in a test is a nit, in production a blocker. A rule without a scope
  usually misfires.
- **`Overrides` makes precedence explicit.** Two rules matching one finding with
  different verdicts is the most common maintainer failure. A rule may also
  override a *built-in* decision rule for a scope — that is the legitimate way
  to encode "here, the usual default is wrong". Restating a built-in without
  overriding it is not: it makes the built-in unreachable and collapses every
  verdict to `policy-rule`.
- **`Rationale` in one or two sentences** — it is what lets the maintainer
  generalize to a case you never logged.

### What belongs in the policy

| Belongs | Does not belong |
|---------|-----------------|
| "Missing tenant id on a query is a blocker" | Anything a linter can check |
| "We don't document internal utilities — reject those nits" | Restating `CLEAN_CODE.md` |
| "Force unwrap: blocker in `src/`, minor in tests" | Facts about the project (that's `CLAUDE.md`) |
| "Perf findings without a benchmark are rejected" | One-off decisions about a single file |

**If a linter can enforce it, it is not a policy rule — it is a lint rule.** Move
it into Layer 0. A policy full of things the linter could check means Layer 0 is
underbuilt.

Target 20–40 rules. A curated set of canonical rules beats an exhaustive dump of
edge cases: long policies dilute attention and produce contradictory matches.
When a new rule is a special case of an existing one, edit the existing one.

### Few-shot examples

Rules say what to decide; examples show how. Two or three canonical, diverse
examples beat a page of prose:

1. A finding rejected because a green gate contradicts it.
2. A finding accepted as a blocker via a policy rule.
3. A finding escalated for an architectural judgment.

Keep them in `.review/REVIEW_POLICY.md` under `## Worked examples` — that file
is project-owned and already in the maintainer's context, so nothing in the
submodule needs overriding. Replace rather than accumulate. A growing example
list is a policy problem in disguise: write the rule instead.

---

## Track B: When Not to Ask

This is the track that makes the loop actually move. It starts fully manual and
earns autonomy per category.

**Nothing in this track is enforced by a script.** Landing is eight conditions in
`land.sh`, and Track A ends in `REVIEW_POLICY.md`, which `run.sh` puts in front
of the maintainer on every run. Track B is different in kind: the lifecycle
below, the `CONFIRM_AFTER` window, the ~20-sample bar, the shadow metric, the
revert-on-one-objection rule — all of it is a model appending JSONL and reading
it back. A record that never gets written does not read as an error; it reads as
no data, indefinitely, and a category simply never earns its silence.

That asymmetry is deliberate and worth keeping: the unenforced track decides
only **whether you are asked**, never whether a commit is allowed. Anything that
could let bad code through is in the scripts. So the failure mode of a neglected
Track B is a loop that keeps asking — annoying, not dangerous.

Two consequences for how to use it. Treat the numbers as directional, not as
measurements: they are as complete as the logging has been. And when a category
seems stuck at `ask`, check `tasks.jsonl` for missing boundaries before
concluding that the category is genuinely not ready. Auditing this is what
`/policy --eval` is for.

### The label is your silence

Every task boundary produces one record in `.review/decisions/tasks.jsonl`,
whether or not you had remarks:

```json
{"ts": "2026-08-05T11:30:00Z", "task": "T-021", "category": "add-tests",
 "signals": {"files": 2, "lines_added": 88, "lines_removed": 4,
             "paths": ["tests/parser/"], "risk_paths": [],
             "findings": {"accepted": 0, "rejected": 3, "escalated": 0},
             "rounds": 1, "tests_changed": true, "replicates": null},
 "decision": {"mode": "ask", "shown": true},
 "human": {"outcome": "accepted", "remarks": 0},
 "would_have_advanced": true, "status": "provisional"}
```

- `human.outcome` is `accepted` (no remarks), `accepted-with-remarks`, or
  `rejected`.
- `would_have_advanced` records what the current thresholds *would* have done
  even while `ADVANCE=ask`. This is the whole trick: **you can measure
  auto-advance long before you enable it**, because every asked task is also a
  shadow prediction.

### Signals, not vibes

The advance decision runs on mechanical signals. The model does not eyeball the
diff and feel confident:

| Signal | Points toward asking |
|--------|---------------------|
| Diff size (files, lines) | Large |
| Paths touched | Security, auth, money, concurrency, public API, data model, migrations |
| Findings | Any accepted `blocker`; many accepted findings |
| Rounds used | More than one |
| Tests | Behavior changed without a test change |
| Task category | Not seen before, or few prior samples |
| History in these paths | You have objected here before |

Risk paths are declared once per project in `.review/land.conf`. Everything in
them asks, always, regardless of what the log says — some code never earns
silence.

### Unlocking a category

1. **Start at `ADVANCE=ask`.** Every task is shown. The log fills up.
2. **After ~20 tasks in one category** with `would_have_advanced == true`,
   `human.outcome == accepted`, and status `confirmed` — not merely accepted —
   that category is a candidate.
3. **Check the shadow metric** (below). If auto-advance precision on that
   category is 100% over those samples, add it to `ADVANCE_CATEGORIES` in
   `.review/land.conf`.
4. **One objection reverts it.** If you object to an auto-advanced task in a
   category, that category goes back to `ask` immediately and needs a fresh
   record to be unlocked again.

Unlock per category, never globally. "Add tests", "extract function", and "fix
typo" earn silence quickly. "Change the data model" should never earn it.

### Acceptance is provisional, not final

**Your silence at the task boundary is weak evidence, not ground truth.** You
approved a summary in a few seconds; the consequences show up tasks later, when
you notice the code went somewhere wrong. The design must expect that, because
the naive version — "accepted once, clean forever" — accumulates exactly the
samples that later turn out to be the problem, and unlocks a category on them.

So every task record has a lifecycle:

```
accepted           → provisional ──(CONFIRM_AFTER later tasks, clean)──► confirmed
                                 └──(implicated later)────────────────► retracted
rejected / objected → closed  (never a clean sample; nothing to confirm)
```

Confirmation is its own appended record, like retraction — the original line is
never edited. Only `confirmed` records count toward unlocking a category.

- **`provisional`** on acceptance. It counts for nothing yet.
- **`confirmed`** after the confirmation window: `CONFIRM_AFTER` tasks in the
  same area have landed without this one being implicated. Default 5. Only
  confirmed samples count toward unlocking a category.
- **`retracted`** when a later investigation traces a problem back to it. A
  retraction is worth more than an acceptance — it is the label you almost
  never get.

Nothing is ever rewritten. Retraction is a new record referencing the old one,
so the history of what you believed and when stays intact.

### Replication: the executor copies what is already there

An executor writing task N reads the surrounding code and imitates it. That is
usually right, and it is exactly how a wrong decision from task N−5 reaches
task N+5 without anyone deciding anything. Nobody chose to spread it; each step
was locally consistent.

**The review layer makes this worse, not better.** A reviewer hunting
inconsistency scores "matches the existing pattern" as a virtue. Consistency
with the wrong thing is indistinguishable from consistency with the right
thing, unless someone asks whether the thing being matched is still worth
matching.

So the question is asked **before the task, not after it**, and it has a
mechanical trigger.

#### The trigger: the third occurrence

When the work would produce the **third** instance of a shape — the third
hand-rolled retry loop, the third place that parses the header inline, the
third view model with the same duplicated state block — stop and decide,
explicitly, one of three things:

| Decision | When | What happens |
|----------|------|-------------|
| **Extend** | The pattern is right; a third copy costs nothing | Proceed. Record `replicates: <file:line>` in the task record |
| **Refactor first** | The pattern is wrong, or the third copy is where it starts to hurt | The refactor becomes its own task, landing **before** this one. This task waits |
| **Deviate** | Neither: this case is genuinely different | Proceed differently, and say why in the task record — otherwise the next executor reads two patterns and picks at random |

One instance is a choice, two is a coincidence, three is a pattern — and the
third is the last cheap moment to change it. After that the cost of the refactor
grows with every task and the decision quietly becomes "never".

**Refactor-first is a separate task, never a widening of this one.** Folding it
in breaks the scope contract, defeats the landing check, and buries a structural
change inside a feature diff.

#### How the trigger fires

Three ways, in order of how reliably they work:

1. **The executor declares it.** Whenever it copies or extends an existing
   shape, it names the source: "following the pattern at `src/api/orders.rs:44`".
   A declaration with a count of two prior instances is the trigger.
2. **The reviewer reports it.** `category: "replication"` exists for this:
   *"this is the third occurrence of X; the others are at A and B"*. It is a
   finding about the change's relationship to the codebase, not about a defect
   inside it, and it is the one finding class a defect-hunting review will never
   produce on its own.
3. **The log shows it.** Same paths touched by several consecutive tasks, or
   the same policy rule firing repeatedly in one area — the policy compensating
   for the code instead of the code being fixed.

A `replication` finding is **not** automatically accepted. It goes to you, or to
whoever owns the architecture, because "should this be refactored now" is a
scheduling decision, not a code-quality one.

### Attribution: a symptom now, introduced earlier

The prospective trigger above will miss things. When it does, you find out
later — and the point of this procedure is that the fix belongs where the thing
entered, not where you noticed it.

**Concrete triggers. Any one of these starts an attribution, no judgment call:**

- You object to a finished task, and the thing you object to is **not in that
  task's diff**
- You ask for a refactor of code the pipeline itself wrote
- The same finding is rejected as `out-of-task-scope` **three times** in one
  area — the reviewer keeps pointing at something no task owns
- One policy rule fires in the same area in three consecutive tasks
- A `replication` finding is raised about a pattern the pipeline introduced

Run `/policy --trace`:

1. **State the symptom as an observable fact.** "Every caller re-parses the
   header because `parse()` returns a borrowed slice" — a thing someone can go
   and look at. Not "the design drifted". If you cannot write the symptom
   concretely, you are not ready to trace it; you are still annoyed.
2. **List the files the symptom lives in**, and walk `tasks.jsonl` plus the
   commit trailers backwards over every task that touched them, most recent
   first.
3. **Find the introduction, not the propagation** — the task that first made
   this shape possible, not the ones that copied it. The copies are evidence of
   how far it spread, not of where it came from.
4. **Read what the pipeline said at the time.** Check that task's
   `verdicts.json`. Very often the reviewer raised it and the maintainer
   rejected it, with the reason recorded — a rejected finding that later proves
   real is the most valuable label in Track A.
5. **Write the fix at the point of introduction:**

   | What the log shows | Where the fix goes |
   |--------------------|--------------------|
   | Reviewer saw it, maintainer rejected it | Track A rule — the rejection reason names the missing or mis-scoped rule |
   | Nobody saw it, and a tool could | Layer 0 gate |
   | Nobody saw it, and no tool could | Policy rule telling the reviewer to look for this class |
   | It spread by replication | The third-occurrence trigger did not fire — why? Usually the executor never declared the copy |
   | The task was mis-scoped, or its criteria too weak | Planning, not review (`PLANNING_GUIDE.md`) |

6. **Retract the affected task records** and re-check any category unlocked on
   them. A category unlocked partly on a retracted sample returns to `ask`.

The `cause` field on a retraction is the highest-value text in the log: the only
place where the symptom and its origin are written down together. Write it for
someone hitting this in six months.

### The metric that governs Track B

**Auto-advance precision** — of the tasks the maintainer did not show you, what
share would you have objected to. Target: zero, measured on the shadow
predictions before you enable anything.

Recall barely matters here. Asking about a trivial task costs seconds. Skipping
a task that needed you costs a defect nobody looked at, buried under later
commits — and by the time it surfaces, several tasks have landed on top of it.
Tune conservatively and accept a high ask rate for a long time.

---

## The Eval Loop

Without measurement every change is a guess, and LLM judges are not stable
enough for guessing — the same finding can get different verdicts across runs.

### Golden set (Track A)

50–200 findings with your verdicts, held out from the ones used as few-shot
examples. Draw from `findings.jsonl` plus a sample of agreements so the set is
not all edge cases. Store as `.review/eval/golden.jsonl`.

| Metric | Definition | Target |
|--------|-----------|--------|
| Agreement rate | Verdicts matching yours | > 85–90% |
| **Blocker recall** | Real blockers accepted | ~100% — never trade this away |
| False-accept rate | Noise passed to the executor | As low as possible without hurting recall |
| Escalation rate | Findings punted to you | 5–15%; near zero means it is guessing |
| Run variance | Verdict flips across repeated runs | Low; investigate any finding that flips |

### Shadow set (Track B)

Every task record with `would_have_advanced` is a free evaluation sample. No
extra labeling work — you were going to accept or object anyway.

| Metric | Definition | Target |
|--------|-----------|--------|
| **Auto-advance precision** | Auto-advanced tasks you did not object to | 100% |
| **Retraction rate** | Confirmed-clean tasks later traced to a problem | Near zero; a rise means the confirmation window is too short |
| Ask rate | Tasks still shown to you | Falls slowly; a fast fall is a warning |
| Category coverage | Categories with enough samples to unlock | Grows over months, not days |

Precision measured on immediate acceptance flatters itself. Measure it again on
**confirmed** outcomes only, and treat the gap between the two numbers as the
cost of your own delayed feedback.

### Running it

Use a CLI-first eval tool (promptfoo is a good default: YAML config, runs in
CI). Wire it as a gate:

- Run the golden set on every change to `REVIEW_POLICY.md` or the maintainer
  prompt.
- Fail the build if agreement drops below the floor, or if blocker recall drops
  at all.
- Run each case 3+ times and report variance. A single-run score on a
  non-deterministic judge is noise.

**Prompt, policy, and threshold changes are code changes**: a diff, a test run,
a commit — same as anything else in `EXECUTION_GUIDE.md`.

---

## Automatic Prompt Optimization

Only worth it once you have ~100+ labeled decisions in Track A and manual prompt
editing has plateaued. Optimizers search prompt and example space against a
metric — agreement with your verdicts, with blocker recall as a hard constraint.

1. **Bootstrapped few-shot** — picks the best demonstrations from your decision
   log. Minutes to run, often most of the gain.
2. **Joint instruction + demo optimization** (e.g. MIPROv2) — a couple hundred
   examples; tunes wording and examples together.
3. **Reflective evolution** (e.g. GEPA) — for multiple objectives or a plateau;
   uses textual feedback rather than a scalar score.

Cautions: optimize against a held-out set (optimizers overfit happily), keep the
result readable and in git, and re-measure after every model upgrade — an
optimized prompt is tuned to a specific model.

Track B does not need this. Its decision is thresholds over mechanical signals;
if you find yourself wanting an LLM to make the advance call directly, the
signals are too weak — add signals instead.

---

## Fine-Tuning: When Not To

For both tracks, fine-tuning is almost always the wrong tool:

- **Availability is a moving target.** Managed fine-tuning of current frontier
  models is limited or unavailable depending on vendor and generation; what is
  tunable tends to be older and weaker. Verify before planning around it.
- **The gain over rules + few-shot + optimization is small** for a
  classification task with a few dozen rules, and the cost — dataset curation,
  training runs, retraining on every model upgrade — is not.
- **Reward-based tuning invites reward hacking.** A weak grader teaches the
  model to score well, not to judge well. You would need an excellent eval loop
  first — and if you have one, you probably do not need tuning.

Revisit only if agreement plateaus below target with an optimized prompt, you
have hundreds of clean labeled examples, and self-service tuning of a current
model exists.

---

## Maintenance

- **Monthly: prune the policy.** Delete rules that never fired, merge
  duplicates, promote anything a linter could check into Layer 0. A rule count
  that only grows is a smell.
- **Monthly: re-check the advance thresholds.** Any category whose ask rate went
  to zero deserves a manual spot check — pull one landed task and read the diff
  yourself.
- **Watch for reward hacking.** If maintainer metrics improve while real quality
  (bugs shipped, reverts, review time) does not, the loop is optimizing itself.
  Re-separate roles, tighten the round limit, strengthen Layer 0.
- **Re-baseline after model changes.** New model, new eval run, before it
  touches a real task.
- **Recheck role assignment periodically.** Which model should review and which
  should maintain is an empirical question about the current generation.
- **Restrict the pipeline where it does not pay.** If the maintainer accepts
  nothing in an area for months, run gates only there and skip LLM review.

---

## Summary Checklist

**Track A — findings**

- [ ] Every overrule logged with a generalizable `why`
- [ ] Every disagreement produces a rule, or a lint rule in Layer 0
- [ ] Rules have level, path scope, verdict, rationale, and a date
- [ ] Severity derived from MUST/SHOULD/MAY, never invented
- [ ] Policy stays under ~40 rules; special cases edit existing rules
- [ ] Two or three canonical examples, replaced rather than accumulated
- [ ] Golden set held out from the few-shot examples
- [ ] Blocker recall never traded for agreement

**Track B — advancing**

- [ ] Every task boundary logged, including the ones you accepted silently
- [ ] Acceptance recorded as provisional; only confirmed samples unlock a category
- [ ] The third occurrence of a shape triggers an explicit extend / refactor-first / deviate decision
- [ ] Copies are declared by the executor and recorded as `replicates`
- [ ] Refactor-first is always its own task, landing before the one that waited
- [ ] Attribution runs on its concrete triggers, not on a feeling that something drifted
- [ ] Retractions appended, never rewritten, with the cause written for a stranger
- [ ] A retracted sample re-opens any category it helped unlock
- [ ] `would_have_advanced` recorded from the first day, while still on `ask`
- [ ] Risk paths declared and permanently excluded from auto-advance
- [ ] Categories unlocked one at a time, on ~20 clean samples
- [ ] Auto-advance precision measured on shadow predictions before enabling
- [ ] One objection reverts a category to `ask`
- [ ] Ask rate falling slowly is healthy; falling fast is a warning

**Both**

- [ ] Each eval case runs multiple times; variance tracked
- [ ] Policy, prompt, and threshold changes committed like code
- [ ] Metrics re-baselined after every model upgrade
