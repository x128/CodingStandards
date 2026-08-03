# Paste this into the project's CLAUDE.md when `.review/` exists

Without it, "do the next task" is just a request to edit files, and the pipeline
sits there unused. This block makes the loop the **default** path — it does not
make it mandatory.

---

## Task work goes through the maintainer loop by default

When asked to do task work with no other instruction, run the loop in
`CodingStandards/skills/maintain.md` rather than editing ad hoc. This applies
whether or not the skill was named: "next task", "do T-014", "continue", and
accepting a finished task all mean run the loop.

Roughly: task file → replication check → work in scope → `run.sh` → fix rounds →
`verified_by` → `land.sh` → log the boundary → present or advance. **Follow the
skill, not this sentence** — it is an orientation for a reader skimming
`CLAUDE.md`, and the steps that actually run are the numbered ones in the skill.

If `CodingStandards/` is empty, none of that is readable: this is a fresh clone
and the submodule was never initialised. Say so, and give the user this to run —
it is a git write, so it is theirs, not yours:

```bash
git submodule update --init --recursive
```

### The user can always bypass it

"Just make this change", "skip the review", "no pipeline for this one", "I'll
write this myself" — do exactly that, immediately, with no argument and no
re-proposal. The user does not owe a reason, and being asked twice for the same
bypass is its own kind of failure.

Hand-written code is normal. If the user writes it themselves and then asks for
a review or a commit, that is a fine way to use this repository too.

Small stuff — a typo, a rename, a one-line fix, a question — is not task work
and never needed the loop. If it has a tracker id, or you would want it in the
history as its own unit, treat it as task work.

### What is not the user's call

These are constraints on **you**, not on them:

- Don't run a mutating git command. `land.sh` is the pipeline's only write path;
  outside it, print the command and let the user run it.
- Don't silently skip a step and present the result as a completed loop run. Say
  what ran and what did not.
- Don't work around a landing refusal. It names the condition that failed —
  meet it, or say plainly that it is blocked.

## Gates

<!-- filled in by /maintain --init -->

| Slot | Command |
|------|---------|
| build | |
| test | |
| format | |
| lint | |
| arch | |

Run one pass: `CodingStandards/templates/review/lib/run.sh --task-file .review/current-task.json`

The loop writes `.review/current-task.json` at step 1. For a pass outside the
loop, copy `.review/task.example.json` to that path first and fill it in — it
must stay under `.review/`, which is the only directory the tree fingerprint
ignores.
