# Style: precise

The skill `asd-ste100` from https://github.com/surendranb/writing-skills, with its reference file,
taken as they are (MIT licence, copyright (c) 2026 Surendran B; the licence text is at the end).

---

# ASD-STE100 Simplified Technical English

Control vocabulary and syntax to eliminate ambiguity in technical documentation.

## The core rule

**One word, one meaning. Imperative voice for instructions. Maximum 20 words per sentence.**

Workflow: `choose approved STE vocabulary` → `write imperative command` → `restrict sentence length to 20 words max` → `verify zero ambiguity`.

## Mechanics

1. **Approved vocabulary.** Use only words from the ASD-STE100 dictionary or approved technical nouns.
2. **Imperative commands.** Start steps with an action verb ("Remove the bolt", not "You should remove the bolt").
3. **Word count limits.** Maximum 20 words for procedural sentences; maximum 25 words for descriptive sentences.
4. **No noun clusters.** Maximum of 3 nouns in a sequence (e.g. use "valve control switch" instead of "engine fuel system valve control switch").
5. **Present tense.** Describe current states in present tense; avoid future tense ("The light is on" not "The light will turn on").
6. **No gerunds in titles.** Use simple nouns or infinitives for headings.
7. **Explicit conditions.** Place conditional clauses at the beginning of the sentence ("If the pressure is low, replace the filter").
8. **Approved modifiers.** Avoid vague adjectives like "extreme", "rapid", or "normal" unless quantified.

## Verify

- Sentences do not exceed 20 words for procedures
- Every instruction starts with an active imperative verb
- No noun clusters exceeding 3 words
- All technical terms conform to standard dictionary definitions
- Zero ambiguous pronouns (replace "it" or "they" with specific nouns)

## Do not

- Use words with multiple meanings (e.g., use "fast" or "secure", avoid "fixed")
- Write conditional clauses after the main action
- Use contractions or colloquialisms
- Use passive voice in maintenance steps

## References

For the enforceable limits (sentence/paragraph/noun-cluster caps), safety-text structure (WARNING/CAUTION/NOTE), and punctuation rules, read `references/REFERENCE.md` when a draft is borderline or needs verification — load on demand, not upfront.

## Example transformations

**Before:** "It is recommended that technicians should carefully inspect the aforementioned component assembly for any potential signs of wear prior to system operation."

**After:** "Inspect the component assembly for wear before you operate the system."

**Before:** "When the pressure drops too low, you might want to consider resetting the main system valve."

**After:** "If the pressure is low, reset the main valve."

# ASD-STE100 Reference — The Rules Behind the Skill

Read this when you need the precise limits and rule structure of the standard, or when a draft is borderline. Sources: asd-ste100.org (official), the ASD-STE100 term-checker rules, and the standard's published rule summaries. The standard is 53 writing rules in 9 sections plus a controlled dictionary; the dictionary itself is copyright ASD and is not reproduced here — apply its principle (plainest word, one meaning) rather than checking against the official word list.

## Verified limits (the numbers you can enforce)
- Instructions (procedures): maximum 20 words per sentence.
- Descriptive text: maximum 25 words per sentence.
- Maximum 6 sentences per paragraph; one topic per paragraph.
- Maximum 3 words in a noun cluster: "the hydraulic pump shaft" — not "the engine fuel pump drive shaft assembly".
- One instruction per sentence. If two actions happen at the same time, they may share one sentence ("Open the valve and listen for air flow").

## Word rules
- Use approved words only with the part of speech and meaning given in the dictionary: "test" is a noun (do the test), not a verb (to test).
- No synonyms: use "start", not "begin", "commence", or "initiate".
- No contractions (don't, isn't) and no omitted words to shorten a sentence.
- No idioms, slang, or jargon.
- No phrasal verbs (use "remove" not "take off").
- Technical nouns and technical verbs are allowed as project terms (your organization's approved additions to the dictionary).

## Sentence structure
- Write instructions in the imperative: "Close the valve." Not "The valve should be closed."
- Start an instruction with a clear command or condition: "When the pressure drops, close the valve."
- If an instruction starts with a descriptive statement, separate it from the command with a comma.
- Active voice. Passive is allowed only in descriptive text when the agent is unknown.
- No complex verb constructions (no auxiliary-verb stacks: "has been being checked").

## Safety text (WARNING, CAUTION, NOTE)
- WARNING: risk of injury or death. CAUTION: risk of damage to equipment. NOTE: information only, never an instruction.
- Start a safety instruction with the command or condition, then give the consequence: "Close the valve. This prevents fuel spillage."
- Notes give information only — they never contain instructions.

## Punctuation
- All standard English punctuation except the semicolon.
- Hyphens connect closely related words; hyphenated words count as one word for the sentence limit.
- Parentheses are allowed; text in parentheses counts as one word.
- In a vertical list, a colon has the same effect on the word count as a full stop.

---

MIT License

Copyright (c) 2026 Surendran B

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
