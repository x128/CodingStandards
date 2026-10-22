# How the write skill was measured

Not read by the agent that writes; read by whoever changes `SKILL.md`.

## The test

- **Inputs.** Twelve real messages a reader did not understand. For each, the writer got the
  notes the message was written from and what the reader had asked, and wrote the message again.
- **Writers.** Fresh agents of the model that writes to the user, two per input and variant: 24
  texts per variant. Each variant is the text of the writing rules the writer read.
- **Measure.** `check.py` counts, without a model, the places that may break a rule: names the
  reader has not used, numbers without what they count, more than one question. Length is counted
  in characters. Variants are compared text by text on the same input; the p values are from the
  sign test.
- **The check was tested first.** Errors were inserted into messages the reader had accepted.
  `check.py` caught 16 of 18; both misses were faults of the test, not of the check. On the
  original messages it flagged 34 of the 54 places the reader had complained about.
- **Mutation test of the rules.** Each rule was deleted in turn. A rule whose deletion did not
  raise the count of its own failures was taken out.

## Results, 21–22 October 2026

| Variant | Unseen names per text | Characters per text |
|---|---|---|
| The old reporting rules of EXECUTION_GUIDE.md | 30.5 | 3,297 |
| No rules at all | 27.1 | 2,805 |
| Six rules and the example | 19.4 | 2,148 |
| The ten-step version the reader approved (this skill; 12 texts) | 9.9 | 1,377 |
| Rules 1–2 and the example | 15.6 | 1,878 |
| Rules 1–2 plus the old reporting rules | 26.2 | 2,761 |
| Rules 1–2 plus the four process points kept in EXECUTION_GUIDE.md | 17.9–18.4 | 1,883–1,990 |

- **The ten-step version is the best of all.** It was left out of the mutation runs, and for a
  day the skill was cut to two rules on their strength alone. The reader read the two-rule texts
  and found them unclear: file names, settings and folder ids were back. Counting unseen names
  ranks versions, but only the reader says whether a message is clear.
- **Two rules beat six.** Fewer unseen names in 13 texts of 24 (p = 0.021); shorter in 21 of 24
  (p < 0.001).
- **The old reporting rules undo a skill.** Added to the two rules: more unseen names in 21 of 24, longer
  in 22 of 24 (both p < 0.001). They were cut from EXECUTION_GUIDE.md.
- **Rules that did nothing in the six-rule version.** Each deleted alone, none of these raised its own failures: show
  what you point to; say what a number counts; give the reason of each step; options are actions.
  Two narrow yes/no judges confirmed it for reasons and options; they had first caught every error
  inserted into accepted messages. A third judge, for pointers, could not tell accepted messages
  from broken ones, so pointers stay unmeasured.
- **Any added instruction costs.** The four process points kept in EXECUTION_GUIDE.md add two to
  three unseen names per text; the first two of them alone did so in 17 texts of 24 (p = 0.001).
- **Styles.** On the same twelve inputs the reader compared, side by side: the steps of this skill
  alone; the steps plus the reply rules of the `iso-24495` plugin; the steps plus the `asd-ste100`
  skill; and each of the two standards alone, without the steps. The reader kept three: the steps
  plus ASD-STE100 as the default (`precise`), the steps alone (`simple`), the steps plus
  ISO 24495-1 (`explained`).
  By `check.py` the three are close: 9.9 to 12.5 unseen names and 1,377 to 1,526 characters per
  text; each standard alone doubled the length, to about 2,670 characters.
