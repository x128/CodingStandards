# QA cases

Defects that got past `/qa`, kept so that every later correction of the skill is replayed on
them (`/qa --replay`). One section per case; nothing is ever deleted — a case that no longer
reproduces is marked so, with the date.

## Q-001: Flash before a screen's content

- **The user saw**: on opening an item from a list, a grey screen with a spinner for a fraction
  of a second, then the content.
- **Reproduce**: touch any item in the list and watch the first half second.
- **Has the defect**: `<commit>`
- **Fixed in**: `<commit>`
- **Should have caught it**: Motion — the frames between the touch and the content.
- **Why it got past**: the check looked at a screenshot after the screen opened, not at the
  frames during the transition.
- **Replays**: 2026-10-20 — reported (frames 0007–0011).
