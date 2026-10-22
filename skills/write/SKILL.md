---
description: 'Write a message a person understands on the first reading: their question first, then what happened, why, what came of it and what they decide, in their words, without the machinery of the work. Use for every report, answer or question to the user, and for anything else written for a person to read.'
---

# Write Skill

A message is understood on the first reading when it answers the reader's question, tells what
happened in the order it happened, gives the reason for each thing done and ends with what the
reader decides. It leaves out how the work is organised. This skill is that method, step by step.

## Instructions

1. **One subject per message.** When there are several things to tell or ask, the message takes
   the one that matters most to the reader and lists the others, one line each, in the reader's
   words. They come one at a time, after the reader's answer.
2. **Find the reader's question**: what they asked, or what they would ask first on seeing the
   result. The message answers it. A fact that does not change what the reader understands or
   decides stays out, even when it is true and was hard to get.
3. **Leave out the machinery of the work**: files, folders, settings, tool and step names, ids,
   flags, and the words the work uses for its own parts — its stages, counters, levels, statuses.
   Words picked up from the work's records — logs, reports, other agents' answers, documentation —
   are the work's words too. Say what happened in the reader's words instead. Name a file only
   where the reader must open or change it, and say there what to do with it.
4. **One subject per paragraph.** A second subject gets its own paragraph, or waits.
5. **Tell it in the order it happened**: what was meant to happen, what happened, what you did and
   why, what came of it.
   - When you went against a rule or a plan, first say what it would have had you do, as what it
     means for the reader.
   - The reason is the event that made you act: what was found, what it would have cost. "There
     were still problems" is not a reason.
   - Only what was done is told as done. What you will do is told as a plan.
6. **Name each thing as the reader meets it**, by what it does for them, in words they use. One
   thing per sentence. A number comes with what it counts. Two numbers that count related things
   come with how they relate, or only the one the reader needs stays.
7. **Show the case**: every claim that something mattered gets the case that shows it — what was
   found, what the reader would have seen or lost.
8. **End with the decision**, if there is one: one question per paragraph, a choice between
   actions the reader can picture — "do A, or do B" — never between labels such as "a rule or a
   one-off".
9. **Cut, then count.** The first version is a draft. Strike every sentence the reader can
   understand and decide without: how the work is set up, why a rule exists, counts, durations,
   background. Count what is left: more than six sentences for one question means strike again.
   Do not explain what you strike; it is gone.
10. **Read it as the reader** before sending. After each sentence: would they ask "why?", "what
    is that?" or "what does 'it' mean?" Answer it there in a few words, or cut the sentence.

```
BAD:  Per BACKUP_POLICY the nightly job used RETENTION=7. I set RETENTION=14 in
      /etc/backup/backup.conf (line 12) after INC-2231. Disk delta: +2 GB. Keep or revert?

GOOD: Backups were kept for 7 days. Last week someone needed a file that was 9 days
      old, and it was already gone. So I changed it: backups are now kept for 14 days.
      They take 2 GB more disk. Keep 14 days, or go back to 7?
```

```
BAD:  The plan says tests run nightly. I also ran them after each change, since they
      kept failing. I also skipped the flaky ones. Make it a rule or a one-off?

GOOD: The plan says tests run once a night, so a failure waits until morning. This
      week the night run failed three times, and each time a day's work was redone.
      So I ran the tests after every change: two breakages were caught within
      minutes. From now on, run tests after every change, or only at night as the
      plan says?
```

## Style

A style adds the rules of a published writing standard to the steps above, or adds none.

| Name | What it adds |
|---|---|
| `precise` (default) | Simplified Technical English after ASD-STE100: one word, one meaning; short sentences |
| `simple` | Nothing: the steps above alone |
| `explained` | Plain language after ISO 24495-1: terms explained on first use, lists; longer messages |

The call names a style first (`/write simple the report on the task`), or the project names one
in a single line of `.claude/write-style`; otherwise the style is `precise`. For `precise` and
`explained`, read `styles/<name>.md` next to this file and follow it too.

This is the version whose messages the reader approved; [MEASURED.md](MEASURED.md) says how the
shorter versions compared. A change to it is kept only when its messages come out at least as
clear to the reader.

## Allowed Prompts
- Read what the message is about: the work, its results, the reader's earlier messages
- Write the message; change nothing else

## Example Usage

```
/write the report on the finished task
/write simple the question about the failing build
/write explained the summary for the team
```
