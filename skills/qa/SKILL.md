---
description: 'Check a finished change the way its user will meet it before it is shown as done: every build, every test on every platform, each exit criterion with evidence, the app run on each platform with every touched transition recorded and read frame by frame, edge states, budgets and regressions — each check by its own agent, each pass challenged by another. Use before a task is shown as done, when asked to test, check or verify a change, and when a defect got past an earlier check.'
---

# QA Skill

Checks a finished change from the outside, as its user will meet it, and reports what fails with
the evidence. It never fixes anything: the report goes to whoever does the work. A defect that
gets past it is a defect of this skill too, and the skill is corrected and replayed on that defect
("When a defect got past").

It needs the project's plan and tracker; a booted simulator, emulator or device for each platform
the project ships; `ffmpeg`; and the platform's command-line tools (`xcrun simctl`, `adb`). A
check whose tool or device is missing is reported as not checked, never as passed.

## Instructions

### 1. The list of what to check

`/qa` keeps the project's test cases in `qa/test-cases.md` (format:
`templates/qa/test-cases.example.md`): each says what the user does and sees, and how it is
covered — by `/qa` by hand, or by a named end-to-end test. A unit or integration test does not
take a case off `/qa`; an end-to-end test does. A full regression run (`--full`) takes every case
of the file, when the user or the plan asks for one; the run of a task takes the cases its change
can reach. A project without the file starts it with the list of this run.

Write the list of this run down before any check runs: what is not on the list is not checked,
and the report says so.

1. **The change**: the uncommitted work, or `--base <ref>`; the task and its exit criteria from
   the tracker.
2. **What the change can break.** Hold the whole app in view: the plan, `qa/test-cases.md`, the
   code around the change. Read what the change's author wrote it may affect, and the diff. Judge
   from the whole app which features the change can reach — through shared code, state, data,
   navigation and platforms — including what the author did not name, and take their cases. A
   behaviour the change adds or changes gets its case added or changed in the file. A case covered
   by an end-to-end test is not walked by hand, except a few chosen anew each run to check the
   tests themselves; a case that fails by hand while its test passes is reported as a fault of
   that test or its environment.
3. **The neighbours**: behaviours that share the changed code but are not the point of the change
   — they are where regressions hide.
4. **The states of each behaviour**: first launch and later launches; empty, one, many, the
   largest the plan names; slow, failing and missing data; no network; no permission; the app
   sent to the background and back, and its process killed and started again; rotation or a
   window size change; light and dark appearance; the largest text size; the same action twice
   quickly; leaving in the middle. Keep the ones the change can reach.
5. **The numbers the plan sets** for these behaviours — time, memory, size — and where each is
   written.
6. **The version to compare with**: `--base` or `HEAD`, taken out into its own folder
   ("Another version of the code", below) and built there. Warnings, neighbours and numbers are
   compared with it.
7. **The time of each check**, set by what is at stake in its items, so that the whole run fits
   the time the work has.

### 2. The checks

Each check is run by its own agent, on the model of the role `QA` in `.review/agents.conf`. It
gets the list and the standards, never the reasoning of whoever made the change, and returns a
verdict per item — pass, fail, unproven or not checked — with its evidence: a test report, a log,
a frame, a measurement, each by path. A pass with no evidence is not a pass.

| Check | Fails when |
|---|---|
| **Build** — every target and configuration the project ships, debug and release | it does not build, or it has a warning the version to compare with does not have |
| **Tests** — every test command of the project on every platform; each test the change adds is seen failing once with its code broken (TESTING.md, "Coverage Requirements"), in a copy of the tree | a test fails; a behaviour of the change has no test (TESTING.md); a test passes with its code broken |
| **Criteria** — each exit criterion, shown by a named test or by a check repeated with its artefact | a criterion is not met, or is claimed without evidence; one that cannot be checked is reported as not checked, never as met |
| **Motion** — the app run on each platform; every transition on the list recorded and read frame by frame (below) | any frame the user would see as a flash, a jump or a wrong state |
| **States** — each state on the list driven on the device and captured | the app shows what the plan does not describe for that state, hangs, or loses data |
| **Numbers** — each number of the list measured with the platform's tools, the same way on both versions | the measurement misses the number |
| **Neighbours** — the neighbours, with the same checks, on both versions | anything that worked in the version to compare with does not |
| **Parity** — the same behaviour on each platform | the platforms differ where the plan does not say they differ |

Checks that build in the same tree, or drive the same simulator, emulator or device, run one
after another, never at once. The list gives each check a time; a check that has spent it reports
what it has, and the rest as not checked, rather than holding a device the next check waits for. A check that changed a device setting — network, permissions,
appearance, text size, rotation — sets it back before it ends.

**Recording a transition.** A screenshot after a transition shows where it ended, not what the
user saw on the way.

- iOS: `xcrun simctl io <device> recordVideo --codec=h264 <file> &`, wait for `Recording started`,
  touch, wait until nothing moves, then `kill -INT` the recorder and `wait` for it. Touch with
  the session's simulator control tool where there is one, or with a UI test in a copy of the
  tree. Stop a recorder only with `INT`: one whose client is killed any other way keeps
  recording inside the simulator, and every later recording fails with "Host recording is
  already in progress" until the simulator is shut down and booted again.
- Android: `adb shell settings put system show_touches 1`, so the touch is visible in the
  frames; `adb shell screenrecord /sdcard/<file>.mp4 &`, `adb shell input tap <x> <y>`, then
  `adb shell pkill -INT screenrecord` and `adb pull`.

**Reading the frames.** Cut every frame the recorder wrote, each named by its own timestamp:
`ffmpeg -i <video> -fps_mode passthrough -frame_pts 1 <dir>/%d.png`. A resampling filter such
as `-vf fps=60` drops frames, and a flash is often exactly one frame. The time of a frame is its
number times the stream's `time_base` (`ffprobe -show_entries stream=time_base <video>`). Look
at every frame from the touch until nothing moves any more. Every frame in that range must show
either the screen being left, the screen arriving, the animation between them, or a state the
plan describes. Report with frame numbers and times:
- a frame that is blank, white or black where the previous screen or content should be;
- content shown and then replaced by other content: a placeholder of one size swapped for content
  of another, a spinner or progress text that appears and is gone, two versions of the same thing
  at once;
- an element that moves without the user moving it: a layout jump, a scroll position lost;
- text, images or colours that change and change back.

Also take from the frames the time from the touch to the first frame with the final content; it
is the number the user feels.

**Another version of the code.** A replay, the version to compare with and the broken copy of the
Tests check are built in a folder of their own, never by changing the working tree:
`CodingStandards/templates/review/lib/export-version.sh <ref> <folder>` (or `WORKTREE` for a
copy of the uncommitted work).

### 3. Challenge every pass

A separate agent gets every pass with its evidence and tries to show it wrong: reads the frames
again, repeats the check, tries the neighbouring input or state. A pass it breaks becomes a fail,
or unproven when the evidence settles nothing.

### 4. Report

As EXECUTION_GUIDE.md, "Reporting to the user", says. The failures come first, each with what the
user sees, how to reproduce it and the evidence by path; with each, the test that pins it — a unit
test, a UI test, or "no test catches it, because …"; then what is unproven and why — it does not
count as passed; then what passed, with its evidence; then what was not checked and why. Never
"everything works": the report says what was checked.

### 5. When a defect got past

A defect found after this skill passed the change — by the user, by a later check, by a later
task — is a defect of this skill as well as of the code.

1. **The case**: add to `qa/test-cases.md` the case that should have caught it, or sharpen the
   one that was there, with the commit that still has the defect, the commit that fixed it, and
   the check that should have caught it.
2. **Find why it passed**: the case was never written; the change's author left the place out
   of what it may affect, and `/qa` did not reach it either; the behaviour or the state was not
   on the list; no check looked at it; a check looked at the
   wrong thing (the screen after the transition instead of the frames during it); the challenge
   accepted weak evidence.
3. **Correct where it went wrong**: this file when a check missed it, a case was never written or
   `/qa` did not see how far the change reaches; `skills/maintain/SKILL.md`, step 4, when the
   author's account of what the change may affect left the place out; the general instruction that
   would have caught it, never the single case (MAINTAINER_TRAINING.md). The standards are
   committed by the user, in their own repository.
4. **Replay**: run the skill on the commit that still has the defect and see the defect reported.
   A correction that was not replayed is a guess.
5. **Replay the other cases** of `qa/test-cases.md` that got past `/qa` too, so that the
   correction broke none of them.

## Allowed Prompts
- Read code, tests, the plan, the tracker and `.review/**`
- Build, run tests, install and run the app on simulators, emulators and devices, record the
  screen, cut frames
- Start an agent for each check and for the challenge
- Take another version of the code out into a folder of its own, and break code only there
- Write recordings, frames and reports under `.review/runs/` when the project has `.review/`, and
  otherwise under a temporary directory; write `qa/test-cases.md`; correct this file after a
  defect got past
- The working tree's source and tests: read only — QA reports, the work is done elsewhere
- Git: read-only (`status`, `diff`, `log`, `show`, `ls-tree`, `cat-file`)

## Example Usage

```
/qa                    # the uncommitted change
/qa --task T-016       # against the exit criteria of a task
/qa --base main        # the whole branch since main
/qa --full             # every case of qa/test-cases.md: a full regression
/qa --replay           # every case of qa/test-cases.md that got past /qa
```
