# Templates

This repo is consumed as a git submodule at `CodingStandards/` in the host
project. **Nothing here is edited in place** — edits inside a submodule get
overwritten on update and leak into every other project.

So the review pipeline is split by ownership:

```
templates/
├── review/
│   ├── lib/        RUNS FROM THE SUBMODULE — never copy, never edit
│   │   ├── run.sh          one review pass
│   │   ├── land.sh         the only thing that commits
│   │   ├── prompts/{reviewer,maintainer}.md
│   │   └── schemas/*.json
│   └── project/    COPY ONCE into <host>/.review/ — yours to edit forever
│       ├── gates.sh
│       ├── REVIEW_POLICY.md
│       └── decisions/
└── agents/         COPY into <host>/.claude/agents/ — Claude Code only looks there
```

The rule: **shared and identical everywhere → `lib/`. Project-specific → copied
out.** Improvements to `lib/` reach every project with
`git submodule update --remote`; nothing you copied out is disturbed.

## Install

Run `/maintain --init`, or follow
[TASK_LOOP.md § Install](../TASK_LOOP.md#install) — the commands live there and
only there, so the two lists cannot drift apart or miss the same step twice.

What that gets you, and what still needs your judgment:

1. **Fill in `.review/gates.sh`** — the five slots (`build`, `test`, `format`,
   `lint`, `arch`). The only file that knows what language the project is
   written in. Per-stack commands:
   [TASK_LOOP.md](../TASK_LOOP.md#wiring-a-new-language).
2. **Run `.review/gates.sh`** until every slot reports honestly. Do not leave
   `TODO` stubs — a gate that cannot run is worse than no gate.
3. **Replace the example rules in `.review/REVIEW_POLICY.md`** with your own.
   `R-001` (perf needs a measurement) is worth keeping; `R-002`–`R-004` are
   shape examples. Do not restate the built-in decision rules as policy — the
   file explains why.
4. **Check the agent CLI flags** in `lib/run.sh` against your installed
   versions. Model choice per role is set via `REVIEWER_CMD` / `MAINTAINER_CMD`
   environment variables — no edit needed.
5. **Deny write-git in `.claude/settings.json`.** The reviewer subagent holds
   `Bash` so it can verify claims, and `Bash` reaches `git commit`. Deny every
   mutating git command and pre-approve the one script that is allowed to write
   — `land.sh`. The block is in [TASK_LOOP.md](../TASK_LOOP.md#landing).
6. **Paste `.review/CLAUDE.snippet.md` into the project's `CLAUDE.md`.**
   Everything above is inert without it: it is what makes "do the next task"
   run the loop instead of editing files ad hoc.

Run it from the project root. `/maintain` writes the task file itself; for a
manual pass, start from the template:

```bash
cp .review/task.example.json .review/current-task.json   # then fill in id, scope, exit_criteria
CodingStandards/templates/review/lib/run.sh --task-file .review/current-task.json
```

Requires `jq` >= 1.6 and `git`. The task file must live under `.review/` —
`run.sh` refuses otherwise, because that is the only directory outside the tree
fingerprint.

## Overriding a shared file

`run.sh` prefers `.review/<path>` over its own copy. To customize one prompt:

```bash
mkdir -p .review/prompts
cp CodingStandards/templates/review/lib/prompts/reviewer.md .review/prompts/
```

Prefer contributing the fix back here — an override is a fork you now maintain.
Project-specific *content* (rules, examples) belongs in
`.review/REVIEW_POLICY.md`, which is already loaded into the maintainer's context
and needs no override.

## What ships here

| File | Owner | Purpose |
|------|-------|---------|
| `review/lib/run.sh` | submodule | One review pass: diff → gates → reviewer → quote verification → triage → filtered output |
| `review/lib/land.sh` | submodule | The only thing that commits; refuses unless eight conditions hold |
| `review/lib/common.sh` | submodule | Tree fingerprint, fail-closed counts, config read as data |
| `review/lib/prompts/reviewer.md` | submodule | Reviewer contract: quote, evidence, confidence, silence-is-valid |
| `review/lib/prompts/maintainer.md` | submodule | Triage decision rules and worked examples |
| `review/lib/schemas/*.json` | submodule | Findings and verdicts schemas — the enforcement mechanism |
| `review/project/gates.sh` | project | Layer 0 — the five deterministic gates, per stack |
| `review/project/REVIEW_POLICY.md` | project | The maintainer's rubric; grows with every disagreement |
| `review/project/land.conf` | project | Landing and advancing switches |
| `review/project/task.example.json` | project | Task contract format: scope and exit criteria |
| `review/project/escalations-answered.example.json` | project | How a human's answer to an escalation is recorded |
| `review/project/CLAUDE.snippet.md` | project | Routing block: makes the loop the default path for task work |
| `review/project/decisions/` | project | Decision log format (training data) |
| `agents/diff-reviewer.md` | project | Reviewer subagent, least-privilege tools |
| `agents/maintainer.md` | project | Maintainer subagent; Bash limited to land.sh and read-only git |
