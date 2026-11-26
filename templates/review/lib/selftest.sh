#!/usr/bin/env bash
#
# selftest.sh — runs review.sh, land.sh and publish.sh end to end on throwaway
# repositories, with the reviewer, the maintainer and gh replaced by fixed
# answers and the end-to-end harness by a fake one, and checks the exit code and
# the line each case must print. The validation of agent output in review.sh is
# exactly the code no real run exercises until a model answers with findings —
# and it once refused every non-empty answer for two months unnoticed. Run it
# after any change to review.sh, land.sh, publish.sh, e2e-gate.sh, the schemas or
# the decision rules of prompts/maintainer.md.
#
# The repositories it builds, and the bare ones that stand in for a remote, live
# in a temporary folder and are deleted at the end; the project's own repository
# is only read.
#
# Usage: CodingStandards/templates/review/lib/selftest.sh
# Exit:  0 — every case behaved; 1 — at least one did not (each is printed)

set -uo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 1
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
FAILURES=0

# review.sh runs nothing on a disk with less than MIN_FREE_GB free, and measures it
# with df. Here df reports a disk of 1 TB free, so that no case depends on the room
# left on the machine that runs this; the case of a low disk asks for more than that.
mkdir -p "$WORK/df-bin" || { echo "setup failed: df-bin"; exit 1; }
printf '#!/bin/sh
echo "Filesystem 1024-blocks Used Available Capacity Mounted on"
echo "fake 2147483648 1073741824 1073741824 50%% /"
' \
  >"$WORK/df-bin/df" && chmod +x "$WORK/df-bin/df" || { echo "setup failed: df"; exit 1; }
# On a low disk review.sh measures with du what the loop left under .review/runs. Here du
# reports DU_KB kilobytes, and none unless a case sets it.
printf '#!/bin/sh
printf "%%s\\t%%s\\n" "${DU_KB:-0}" .review/runs
' \
  >"$WORK/df-bin/du" && chmod +x "$WORK/df-bin/du" || { echo "setup failed: du"; exit 1; }
export PATH="$WORK/df-bin:$PATH"
export E2E_REPEAT_PAUSE=0
# The runs of the end-to-end tests meet in DEVICE_LOCK_DIR to hold a platform (e2e-gate.sh):
# here a folder of this test, so that nothing is written outside it.
export DEVICE_LOCK_DIR="$WORK/devices"

fail_setup() { echo "setup failed: $1"; exit 1; }

repository="$WORK/project"
mkdir -p "$repository/.review" "$repository/src" "$repository/qa" || fail_setup "folders"
cd "$repository" || fail_setup "cd"
git init -q -b main || fail_setup "git init"
git config user.email selftest@example.com && git config user.name selftest \
  || fail_setup "git config"
printf 'fun answer() = 41\n' >src/answer.kt
# The cases and the end-to-end harness start committed with the code. The fake
# harness leaves one JUnit report per platform in which the tests of both cases pass,
# unless a case sets another report (E2E_XML, or E2E_XML_<platform> for one platform,
# or E2E_REPORT, a file to copy), where it goes inside the report folder (E2E_NAME), a
# second place it is copied to (E2E_ALSO), another exit code (E2E_EXIT), the one
# platform it runs on (E2E_ONLY) or a file it appends to (E2E_TOUCH). E2E_ENV_TIMES names a
# file that holds a number: while it is above zero the harness takes one off and exits 75,
# as a harness does whose device is not there. E2E_SLEEP is how many seconds the harness
# takes before it writes its report, E2E_HANG how many after, and E2E_STAMPS a file it
# appends `<platform> start <pid>` to when it begins and `<platform> end <pid>` when it ends.
# Each published project
# below commits the same harness. The gate tries a platform once more after an exit 75 with
# no pause here.
cat >qa/test-cases.md <<'EOF'
# Test cases

## Answer

- **TC-001 Answer.** Open the app: it shows 42. — e2e: `AnswerE2E.shows42`
- **TC-002 Start.** Start the app: it opens with no error. — e2e:
  `AnswerE2E.starts`
EOF
cat >.review/e2e.sh <<'EOF'
#!/usr/bin/env bash
report="$2/${E2E_NAME:-r.xml}"
mkdir -p "$(dirname "$report")"
[ -z "${E2E_TOUCH:-}" ] || printf 'touched\n' >>"$E2E_TOUCH"
[ -z "${E2E_STAMPS:-}" ] || echo "$1 start $$" >>"$E2E_STAMPS"
[ -z "${E2E_SLEEP:-}" ] || sleep "$E2E_SLEEP"
if [ -n "${E2E_ENV_TIMES:-}" ] && [ "$(cat "$E2E_ENV_TIMES")" -gt 0 ]; then
  echo "$(($(cat "$E2E_ENV_TIMES") - 1))" >"$E2E_ENV_TIMES"
  exit 75
fi
platform_xml="E2E_XML_$1"
if [ -n "${E2E_REPORT:-}" ]; then
  cp "$E2E_REPORT" "$report"
elif [ "$1" = "${E2E_ONLY:-$1}" ]; then
  passing="<testsuite hostname=\"$1\"><testcase classname=\"AnswerE2E\" name=\"shows42\"/>"\
"<testcase classname=\"AnswerE2E\" name=\"starts\"/></testsuite>"
  printf '%s' "${!platform_xml:-${E2E_XML:-$passing}}" >"$report"
fi
if [ -n "${E2E_ALSO:-}" ] && [ -f "$report" ]; then
  mkdir -p "$(dirname "$2/$E2E_ALSO")" && cp "$report" "$2/$E2E_ALSO"
fi
[ -z "${E2E_HANG:-}" ] || sleep "$E2E_HANG"
[ -z "${E2E_STAMPS:-}" ] || echo "$1 end $$" >>"$E2E_STAMPS"
exit "${E2E_EXIT:-0}"
EOF
chmod +x .review/e2e.sh
cp .review/e2e.sh "$WORK/e2e.green"
git add src/answer.kt qa/test-cases.md .review/e2e.sh && git commit -q -m start \
  || fail_setup "first commit"
printf 'fun answer() = 42\n' >src/answer.kt

cat >.review/gates.sh <<'EOF'
#!/usr/bin/env bash
mkdir -p "$(dirname "$1")"
echo '{"build":{"status":"pass","blocking":true,"command":"true","output":""}}' >"$1"
EOF
chmod +x .review/gates.sh
printf '# Review Policy\n' >.review/REVIEW_POLICY.md
printf 'THRESHOLD=major\nLANDING=off\nASK_AFTER_RUNS=100\n' >.review/land.conf
cat >.review/task.json <<'EOF'
{"id": "T-001", "title": "Answer 42", "category": "bugfix", "scope": ["src/*"],
 "exit_criteria": [{"text": "answer() returns 42", "verified_by": "manual: read src/answer.kt"}]}
EOF
# /qa's records of the tasks that land, in folders that sort before every
# timestamped run, so that land() still takes the newest run.
for task_id in T-001 T-004; do
  mkdir -p ".review/runs/0-qa-$task_id"
  printf '{"task": "%s", "failures": []}' "$task_id" >".review/runs/0-qa-$task_id/qa.json"
done

finding() {
  printf '{"findings":[{"id":"F-001","file":"src/answer.kt","line":1,'\
'"code_quote":"fun answer() = 42","category":%s,"severity":"major","confidence":"confirmed",'\
'"evidence":"answer() returns 42 where 41 is expected"}]}' "$1"
}

verdict() {
  printf '{"verdicts":[{"finding_id":"F-001","verdict":%s,"severity":"major","decision_rule":"%s",'\
'"reason":"the finding names a real change of behaviour"}]}' "$1" "$2"
}

check() {
  local name="$1" expected_exit="$2" expected_line="$3" actual_exit="$4" log="$5"
  if [ "$actual_exit" -eq "$expected_exit" ] && grep -qF -- "$expected_line" "$log"; then
    echo "ok    $name (exit $actual_exit)"
  else
    echo "FAIL  $name: expected exit $expected_exit and «${expected_line}», "\
"got exit $actual_exit — log follows"
    sed 's/^/      /' "$log"
    FAILURES=$((FAILURES + 1))
  fi
}

# says <name> <line> [<log>] and never_says <name> <line> [<log>]: what the log of the
# case before holds, and what it must not hold.
says() {
  if grep -qF -- "$2" "${3:-$WORK/post.log}"; then
    echo "ok    $1"
  else
    echo "FAIL  $1: no «$2» — log follows"
    sed 's/^/      /' "${3:-$WORK/post.log}"
    FAILURES=$((FAILURES + 1))
  fi
}
never_says() {
  if grep -qF -- "$2" "${3:-$WORK/post.log}"; then
    echo "FAIL  $1: «$2» is there — log follows"
    sed 's/^/      /' "${3:-$WORK/post.log}"
    FAILURES=$((FAILURES + 1))
  else
    echo "ok    $1"
  fi
}

# The newest review run, by the time each records — the names of two runs made in one
# second do not sort by time — and what its meta.json holds: run_records <name> <jq filter>.
newest_run() {
  local meta
  for meta in .review/runs/*/meta.json; do
    [ -f "$meta" ] || continue
    jq -c --arg run "${meta%/meta.json}" '{time: (.time // 0), run: $run}' "$meta"
  done | jq -sr 'sort_by(.time) | last | .run'
}
run_records() {
  local run
  run="$(newest_run)"
  if jq -e "$2" "$run/meta.json" >/dev/null 2>&1; then
    echo "ok    $1"
  else
    echo "FAIL  $1: «$2» does not hold in $run/meta.json — it follows"
    sed 's/^/      /' "$run/meta.json"
    FAILURES=$((FAILURES + 1))
  fi
}

review() {
  local name="$1" expected_exit="$2" expected_line="$3" reviewer_answer="$4" maintainer_answer="$5"
  printf '%s' "$reviewer_answer" >"$WORK/reviewer.json"
  printf '%s' "$maintainer_answer" >"$WORK/maintainer.json"
  REVIEWER_CMD="cat $WORK/reviewer.json #" MAINTAINER_CMD="cat $WORK/maintainer.json #" \
    "$LIB_DIR/review.sh" --task-file .review/task.json >"$WORK/run.log" 2>&1
  check "$name" "$expected_exit" "$expected_line" $? "$WORK/run.log"
}

land() {
  local name="$1" expected_exit="$2" expected_line="$3" landing="$4"
  printf 'THRESHOLD=major\nLANDING=%s\n' "$landing" >.review/land.conf
  "$LIB_DIR/land.sh" --task-file .review/task.json --run "$(ls -d .review/runs/* | tail -1)" \
    >"$WORK/land.log" 2>&1
  check "$name" "$expected_exit" "$expected_line" $? "$WORK/land.log"
}

# The hook of /qa: `check` reads the newest e2e.json and runs nothing.
e2e_check() {
  local name="$1" expected_exit="$2" expected_line="$3" actual_exit
  "$LIB_DIR/e2e-gate.sh" check >"$WORK/check.log" 2>&1
  actual_exit=$?
  echo "check exited $actual_exit" >>"$WORK/check.log"
  check "$name" "$expected_exit" "$expected_line" "$actual_exit" "$WORK/check.log"
}

e2e_check "with no end-to-end run recorded /qa is held back" 2 "no end-to-end run is recorded"
e2e_check "holding /qa back, the hook says it is the /qa skill's" 2 \
  "This is the hook of the /qa skill"
mkdir -p "$WORK/no-repository"
(cd "$WORK/no-repository" && GIT_CEILING_DIRECTORIES="$WORK" "$LIB_DIR/e2e-gate.sh" check) \
  >"$WORK/check.log" 2>&1
check_exit=$?
echo "check exited $check_exit" >>"$WORK/check.log"
check "outside a git repository /qa is held back, not let through" 2 \
  "is not inside a git repository" "$check_exit" "$WORK/check.log"
review "no findings is clean" 0 "CLEAN — gates green, no verified findings." \
  '{"findings":[]}' '{"verdicts":[]}'
# A run records how it ended: its end, its exit code and the stage it had reached.
run_records "a clean run records its end" '.end == "clean" and .exit == 0'
e2e_check "after a passing end-to-end run /qa may go on" 0 "check exited 0"
review "an accepted finding goes to the executor" 3 "accepted (>= major): 1" \
  "$(finding '"bug"')" "$(verdict '"accept"' no-rule-fired)"
review "an escalated finding waits for an answer" 4 "escalated         : 1" \
  "$(finding '"bug"')" "$(verdict '"escalate"' needs-judgment)"
review "a category outside the schema fails closed" 1 "reviewer output does not match" \
  "$(finding '"opinion"')" "$(verdict '"accept"' no-rule-fired)"
run_records "a run that an agent's answer ended records the stage" \
  '.end == "error" and .stage == "reviewer"'
review "a category given as a list fails closed" 1 "reviewer output does not match" \
  "$(finding '["bug"]')" "$(verdict '"accept"' no-rule-fired)"
review "a verdict outside the schema fails closed" 1 "maintainer output is malformed" \
  "$(finding '"bug"')" "$(verdict '"maybe"' no-rule-fired)"
review "a verdict given as a list fails closed" 1 "maintainer output is malformed" \
  "$(finding '"bug"')" "$(verdict '["escalate"]' needs-judgment)"
review "a rejected finding leaves the run clean" 0 "rejected          : 1" \
  "$(finding '"bug"')" "$(verdict '"reject"' contradicts-green-gate)"

land "landing off on main prints the commit with a note" 0 "Note: current branch is main" off
land "landing on on main refuses by condition 8" 3 "condition 8" on
cp .review/task.json "$WORK/task.json"
printf '{"id": "T-001", "title": "Answer 42", "category": "bugfix", "scope": ["src/*"], '\
'"exit_criteria": []}' \
  >.review/task.json
land "a task with no exit criteria lands" 0 "Exit-Criteria: 0 verified" off
cp "$WORK/task.json" .review/task.json

counted() {
  local name="$1" expected_exit="$2" expected_line="$3" task_id="$4"; shift 4
  printf '{"id": "%s", "title": "Answer 42", "category": "bugfix", "scope": ["src/*"], '\
'"exit_criteria": []}' \
    "$task_id" >".review/$task_id.json"
  printf '{"findings":[]}' >"$WORK/reviewer.json"
  printf '{"verdicts":[]}' >"$WORK/maintainer.json"
  REVIEWER_CMD="cat $WORK/reviewer.json #" MAINTAINER_CMD="cat $WORK/maintainer.json #" \
    "$LIB_DIR/review.sh" --task-file ".review/$task_id.json" "$@" >"$WORK/run.log" 2>&1
  check "$name" "$expected_exit" "$expected_line" $? "$WORK/run.log"
}

printf 'THRESHOLD=major\nLANDING=off\nASK_AFTER_RUNS=2\n' >.review/land.conf
counted "the first run of a task runs" 0 "CLEAN" T-002
counted "a run up to the limit runs" 0 "CLEAN" T-002
runs_before="$(ls .review/runs | wc -l)"
counted "a task at its limit of reviews stops and says what it read" 6 \
  "LIMIT OF REVIEWS — T-002 has had 2 reviews since the count started, 2 runs in all" T-002
if [ "$(ls .review/runs | wc -l)" -eq "$runs_before" ]; then
  echo "ok    a run past the limit leaves no run behind"
else
  echo "FAIL  a run past the limit left a run directory behind"
  FAILURES=$((FAILURES + 1))
fi
counted "the runs of another task are not counted" 0 "CLEAN" T-003
counted "--past-limit below the limit is refused" 1 \
  "only for a task at its limit" T-003 --past-limit
counted "--past-limit runs once more" 0 "CLEAN" T-002 --past-limit
counted "--past-limit left in the command fails on the next run" 1 \
  "only for a task at its limit" T-002 --past-limit
counted "after --past-limit the count starts again from zero" 0 "CLEAN" T-002
counted "a run up to the limit after --past-limit runs" 0 "CLEAN" T-002
counted "the count after --past-limit reaches the limit again" 6 \
  "has had 2 reviews since the count started, 5 runs in all" T-002
for task_without_id in '{"title": "no id"}' '{"id": "", "title": "empty id"}'; do
  printf '%s' "$task_without_id" >.review/no-id.json
  REVIEWER_CMD="cat $WORK/reviewer.json #" MAINTAINER_CMD="cat $WORK/maintainer.json #" \
    "$LIB_DIR/review.sh" --task-file .review/no-id.json >"$WORK/run.log" 2>&1
  check "a task file $task_without_id fails closed" 1 "has no .id" $? "$WORK/run.log"
done
for limit in none 0 05; do
  printf 'THRESHOLD=major\nLANDING=off\nASK_AFTER_RUNS=%s\n' "$limit" >.review/land.conf
  counted "a limit of '$limit' fails closed" 1 "must be a whole number from 1" T-002
done

printf 'THRESHOLD=major\nLANDING=off\nASK_AFTER_RUNS=100\nMIN_FREE_GB=99999\n' >.review/land.conf
review "a disk with too little free space runs nothing" 1 "DISK LOW" \
  '{"findings":[]}' '{"verdicts":[]}'
# Whose turn it is on a low disk is read from what the loop left: df has 1024 GB free and
# 99999 are asked for, so 98975 GB are missing.
DU_KB=524288 \
  review "a low disk the loop's files cannot free is the user's" 1 \
  "   For the user, only they can: free 98975 GB on this disk: what the loop left under "\
".review/runs takes only 512 MB" '{"findings":[]}' '{"verdicts":[]}'
DU_KB=103782809600 \
  review "a low disk the loop's own files can free is the loop's" 1 \
  "   The loop goes on: delete what the loop left behind (maintain, step 12)" \
  '{"findings":[]}' '{"verdicts":[]}'
# The script measures all that is under the runs, and the loop may delete only a part of
# it: so the loop's line ends with whose the stop is when nothing of that part is left.
DU_KB=103782809600 \
  review "the loop's line on a low disk says whose the stop is with nothing left to delete" 1 \
  "of tasks that landed — and run again. With nothing of that left to delete: For the user, "\
"only they can: free 98975 GB on this disk" '{"findings":[]}' '{"verdicts":[]}'
printf 'THRESHOLD=major\nLANDING=off\nASK_AFTER_RUNS=100\n' >.review/land.conf
mkdir -p "$WORK/bin"
cat >"$WORK/bin/claude" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$CLAUDE_ARGS"
cat >/dev/null
case "$*" in
  *Bash*) cat "$CLAUDE_REVIEW" ;;
  *) cat "$CLAUDE_VERDICTS" ;;
esac
EOF
chmod +x "$WORK/bin/claude"
printf '%s' "$(finding '"bug"')" >"$WORK/reviewer.json"
printf '%s' "$(verdict '"reject"' contradicts-green-gate)" >"$WORK/maintainer.json"
printf '{"id": "T-005", "title": "Answer 42", "category": "bugfix", "scope": ["src/*"], '\
'"exit_criteria": []}' >.review/T-005.json
through_claude() {
  local name="$1" expected_exit="$2" expected_line="$3"
  : >"$WORK/claude-args"
  PATH="$WORK/bin:$PATH" CLAUDE_ARGS="$WORK/claude-args" CLAUDE_REVIEW="$WORK/reviewer.json" \
    CLAUDE_VERDICTS="$WORK/maintainer.json" \
    "$LIB_DIR/review.sh" --task-file .review/T-005.json >"$WORK/run.log" 2>&1
  check "$name" "$expected_exit" "$expected_line" $? "$WORK/run.log"
}
through_claude "with no agents.conf every role runs on opus" 0 \
  "models: reviewer opus, maintainer opus"
check "a role with no line starts claude with --model opus" 0 \
  "-p --model opus --allowedTools Read --output" 0 "$WORK/claude-args"
mkdir -p .claude && printf 'MAINTAINER=inherit\n' >.claude/agents.conf
through_claude "inherit is refused for a role review.sh starts" 1 "with no session to inherit from"
printf 'REVIEWER=opus \t high   # reviews the change\nMAINTAINER=sonnet\n' >.claude/agents.conf
through_claude "the model of each role is printed before the run" 0 \
  "models: reviewer opus high, maintainer sonnet"
check "the reviewer starts with the model and effort of its role" 0 \
  "-p --model opus --effort high --allowedTools Read,Grep,Glob,Bash" 0 "$WORK/claude-args"
check "the run records the command of each role" 0 \
  '"reviewer": "claude -p --model opus --effort high' \
  0 "$(ls -d .review/runs/* | tail -1)/meta.json"
counted "a command set by hand is named instead of the model" 0 \
  "models: reviewer REVIEWER_CMD, maintainer MAINTAINER_CMD" T-005
printf 'REVIEWER=opus fast\n' >.claude/agents.conf
runs_before="$(ls .review/runs | wc -l)"
counted "an effort outside the list fails closed" 1 "has effort 'fast'" T-005
if [ "$(ls .review/runs | wc -l)" -eq "$runs_before" ]; then
  echo "ok    a role that cannot run leaves no run behind"
else
  echo "FAIL  a role that cannot run left a run directory behind"
  FAILURES=$((FAILURES + 1))
fi
rm .claude/agents.conf
printf '{"id": "T-004", "title": "Answer 42", "category": "bugfix", "scope": ["src/*"], '\
'"exit_criteria": [{"text": "answer() returns 42", "verified_by": "manual: read src/answer.kt"}]}' \
  >.review/T-004.json
runs_listed="$(ls .review/runs)"
printf '%s' "$(finding '"bug"')" >"$WORK/reviewer.json"
printf '%s' "$(verdict '"reject"' contradicts-green-gate)" >"$WORK/maintainer.json"
REVIEWER_CMD="cat $WORK/reviewer.json #" MAINTAINER_CMD="cat $WORK/maintainer.json #" \
  "$LIB_DIR/review.sh" --task-file .review/T-004.json >"$WORK/run.log" 2>&1
run_of_t004=".review/runs/$(comm -13 <(printf '%s\n' "$runs_listed") <(ls .review/runs))"
cp .review/gates.sh "$WORK/gates.green"
cat >.review/gates.sh <<'EOF'
#!/usr/bin/env bash
echo '{"test":{"status":"fail","blocking":true,"command":"false",'\
'"output":"could not boot the test simulator"}}' >"$1"
exit 1
EOF
"$LIB_DIR/land.sh" --task-file .review/T-004.json --run "$run_of_t004" >"$WORK/land.log" 2>&1
check "red gates at landing refuse by condition 3" 3 \
  "gates are red at landing time" $? "$WORK/land.log"
"$LIB_DIR/land.sh" --task-file .review/T-004.json --run "$run_of_t004" >"$WORK/land.log" 2>&1
check "landing the same run may be retried once after red gates" 3 \
  "gates are red at landing time" $? "$WORK/land.log"
"$LIB_DIR/land.sh" --task-file .review/T-004.json --run "$run_of_t004" >"$WORK/land.log" 2>&1
check "red gates at landing twice send the work back to review.sh" 3 \
  "failed at or after its gates twice" $? "$WORK/land.log"
"$LIB_DIR/land.sh" --task-file .review/T-004.json --run "$run_of_t004" >"$WORK/land.log" 2>&1
check "a landing that failed twice goes back to review.sh: the loop goes on" 3 \
  "   The loop goes on: run review.sh again: another landing of this run would repeat uncounted" \
  $? "$WORK/land.log"
if grep -qF "the user" "$WORK/land.log"; then
  echo "FAIL  a landing that failed twice names the user — log follows"
  sed 's/^/      /' "$WORK/land.log"
  FAILURES=$((FAILURES + 1))
else
  echo "ok    and names no user"
fi
printf '{"id": "T-050", "title": "Answer 42", "category": "bugfix", "scope": ["src/*"], '\
'"exit_criteria": []}' >.review/T-050.json
REVIEWER_CMD="cat $WORK/reviewer.json #" MAINTAINER_CMD="cat $WORK/maintainer.json #" \
  "$LIB_DIR/review.sh" --task-file .review/T-050.json >"$WORK/run.log" 2>&1
check "red gates end a run before its review" 2 "GATES RED — no LLM review" $? "$WORK/run.log"
run_records "a run with red gates records where it ended" \
  '.end == "gates-red" and .exit == 2 and .stage == "gates"'

cp "$WORK/gates.green" .review/gates.sh
runs_listed="$(ls .review/runs)"
REVIEWER_CMD="cat $WORK/reviewer.json #" MAINTAINER_CMD="cat $WORK/maintainer.json #" \
  "$LIB_DIR/review.sh" --task-file .review/T-004.json >"$WORK/run.log" 2>&1
run_of_t004=".review/runs/$(comm -13 <(printf '%s\n' "$runs_listed") <(ls .review/runs))"
printf '#!/usr/bin/env bash\nexit 143\n' >.review/gates.sh
for attempt in first second; do
  "$LIB_DIR/land.sh" --task-file .review/T-004.json --run "$run_of_t004" >"$WORK/land.log" 2>&1
  check "gates killed at landing refuse the $attempt time" 3 "did not run" $? "$WORK/land.log"
done
"$LIB_DIR/land.sh" --task-file .review/T-004.json --run "$run_of_t004" >"$WORK/land.log" 2>&1
check "gates killed at landing twice send the work back to review.sh" 3 \
  "failed at or after its gates twice" $? "$WORK/land.log"

cat >.review/gates.sh <<'EOF'
#!/usr/bin/env bash
echo '{"build":{"status":"pass","blocking":true,"command":"true","output":""},'\
'"lint":{"status":"fail","blocking":false,"command":"false","output":"style"}}' >"$1"
EOF
runs_listed="$(ls .review/runs)"
REVIEWER_CMD="cat $WORK/reviewer.json #" MAINTAINER_CMD="cat $WORK/maintainer.json #" \
  "$LIB_DIR/review.sh" --task-file .review/T-004.json >"$WORK/run.log" 2>&1
run_of_t004=".review/runs/$(comm -13 <(printf '%s\n' "$runs_listed") <(ls .review/runs))"
for attempt in first second third; do
  "$LIB_DIR/land.sh" --task-file .review/T-004.json --run "$run_of_t004" >"$WORK/land.log" 2>&1
  check "a failing gate that does not block never stops a $attempt landing" 0 \
    "Note: current branch is main" $? "$WORK/land.log"
done
cp "$WORK/gates.green" .review/gates.sh

# The landing is killed once its gates run, and the gates say so with a file as they
# start. How long land.sh takes to reach them differs from machine to machine, so the
# case waits for that file and not for a second: a minute at most, and no longer than the
# landing lives. It does not wait for the count, which is what it asks about.
printf '#!/usr/bin/env bash\n: >"%s"\nsleep 30\n' "$WORK/gates.started" >.review/gates.sh
"$LIB_DIR/land.sh" --task-file .review/T-004.json --run "$run_of_t004" >"$WORK/land.log" 2>&1 &
landing=$!
waited=0
until [ -e "$WORK/gates.started" ] || [ "$waited" -ge 60 ] \
      || ! kill -0 "$landing" 2>/dev/null; do
  sleep 1
  waited=$((waited + 1))
done
pkill -P "$landing"
kill "$landing" 2>/dev/null
wait "$landing" 2>/dev/null
if [ -e "$WORK/gates.started" ] && [ "$(cat "$run_of_t004/landing-reds")" = 1 ]; then
  echo "ok    a landing killed while the gates run is counted"
elif [ -e "$WORK/gates.started" ]; then
  echo "FAIL  a landing killed while the gates run is not counted"
  FAILURES=$((FAILURES + 1))
else
  echo "FAIL  a landing killed while the gates run is not counted: its gates had not "\
"started after $waited s — log follows"
  sed 's/^/      /' "$WORK/land.log"
  FAILURES=$((FAILURES + 1))
fi
printf '0\n' >"$run_of_t004/landing-reds"
cp "$WORK/gates.green" .review/gates.sh

git checkout -q -b feature || fail_setup "feature branch"
printf '#!/usr/bin/env bash\nexit 1\n' >.git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
printf 'THRESHOLD=major\nLANDING=on\nASK_AFTER_RUNS=100\n' >.review/land.conf
for attempt in first second; do
  "$LIB_DIR/land.sh" --task-file .review/T-004.json --run "$run_of_t004" >"$WORK/land.log" 2>&1
  check "a commit that fails after green gates fails the $attempt time" 1 \
    "commit failed" $? "$WORK/land.log"
done
"$LIB_DIR/land.sh" --task-file .review/T-004.json --run "$run_of_t004" >"$WORK/land.log" 2>&1
check "a commit that failed twice sends the work back to review.sh" 3 \
  "failed at or after its gates twice" $? "$WORK/land.log"
rm .git/hooks/pre-commit

# The end-to-end tests. They run after the review, whatever they come to, and only a
# harness file that is not there ends a run before it. Each review here has no findings,
# so it ends CLEAN unless the end-to-end tests did not pass; the run it made is $last_run.
# Each is a review, though the work is the same: --again (a run on reviewed work repeats
# only its end-to-end tests, e2e_repeat below).
printf 'THRESHOLD=major\nLANDING=off\nASK_AFTER_RUNS=100\n' >.review/land.conf
printf '{"findings":[]}' >"$WORK/reviewer.json"
printf '{"verdicts":[]}' >"$WORK/maintainer.json"
e2e_review() {
  local name="$1" expected_exit="$2" expected_line="$3" task_file="$4" runs_listed
  runs_listed="$(ls .review/runs)"
  REVIEWER_CMD="touch $WORK/reviewer-ran; cat $WORK/reviewer.json #" \
    MAINTAINER_CMD="cat $WORK/maintainer.json #" \
    "$LIB_DIR/review.sh" --task-file "$task_file" --again >"$WORK/run.log" 2>&1
  review_exit=$?
  check "$name" "$expected_exit" "$expected_line" "$review_exit" "$WORK/run.log"
  last_run=".review/runs/$(comm -13 <(printf '%s\n' "$runs_listed") <(ls .review/runs))"
}
e2e_land() {
  local name="$1" expected_exit="$2" expected_line="$3" task_file="$4" run="$5"
  "$LIB_DIR/land.sh" --task-file "$task_file" --run "$run" >"$WORK/land.log" 2>&1
  check "$name" "$expected_exit" "$expected_line" $? "$WORK/land.log"
}
xml() {
  local testcase
  printf '<testsuite>'
  for testcase in "$@"; do
    case "$testcase" in
      *=failed)
        printf '<testcase classname="AnswerE2E" name="%s"><failure message="41"/></testcase>' \
          "${testcase%=*}" ;;
      *=skipped)
        printf '<testcase classname="AnswerE2E" name="%s"><skipped/></testcase>' \
          "${testcase%=*}" ;;
      *)         printf '<testcase classname="AnswerE2E" name="%s"/>' "$testcase" ;;
    esac
  done
  printf '</testsuite>'
}

printf '{"id": "T-006", "title": "Answer 42", "category": "bugfix", "scope": ["src/*"], '\
'"exit_criteria": []}' >.review/T-006.json
# reviewer_ran <name> [not]: whether the reviewer of the last e2e_review ran.
reviewer_ran() {
  if { [ -e "$WORK/reviewer-ran" ] && [ "${2:-}" != not ]; } || \
     { [ ! -e "$WORK/reviewer-ran" ] && [ "${2:-}" = not ]; }; then
    echo "ok    $1"
  else
    echo "FAIL  $1: the reviewer $([ -e "$WORK/reviewer-ran" ] && echo ran || echo "did not run")"
    sed 's/^/      /' "$WORK/run.log"
    FAILURES=$((FAILURES + 1))
  fi
  rm -f "$WORK/reviewer-ran"
}
rm -f "$WORK/reviewer-ran"
mv .review/e2e.sh "$WORK/e2e.sh"
e2e_review "no end-to-end harness stops the review" 1 \
  "NO E2E HARNESS — copy CodingStandards/templates/review/project/e2e.sh" .review/T-006.json
reviewer_ran "a missing harness still ends the run before the review" not
e2e_check "after a run with no harness /qa is held back" 2 "found no working harness"
mv "$WORK/e2e.sh" .review/e2e.sh
E2E_XML='<testsuite tests="0"/>' \
  e2e_review "a harness that runs no test is said to have run none, and the review is made" 1 \
  "app: the e2e run ran no test" .review/T-006.json
says "its run says that no end-to-end test ran" "NO END-TO-END TEST RAN — the harness is there "\
"and ran none:" "$WORK/run.log"
never_says "and calls it no missing harness" "NO E2E HARNESS" "$WORK/run.log"
reviewer_ran "the review of a run that ran no test is made"
e2e_check "after a run that ran no test /qa is held back and told why" 2 "E2E DID NOT RUN"
E2E_ONLY=none E2E_EXIT=143 \
  e2e_review "a harness killed before any test is said to have run none" 1 \
  "app: the e2e run ran no test (exit 143)" .review/T-006.json
rm -f "$WORK/reviewer-ran"
cp qa/test-cases.md "$WORK/test-cases.md"
printf '# Test cases\n\n- **TC-001 Answer.** Open the app: it shows 42. — manual\n' \
  >qa/test-cases.md
e2e_review "tests that no case names are no harness" 1 \
  "app: no case of qa/test-cases.md names an e2e test that ran" .review/T-006.json
cp "$WORK/test-cases.md" qa/test-cases.md
E2E_XML="$(xml shows42=skipped starts)" \
  e2e_review "a named test that is skipped is red" 2 "named but did not pass: AnswerE2E.shows42" \
  .review/T-006.json
rm -f "$WORK/reviewer-ran"
E2E_XML="$(xml shows42=failed starts)" \
  e2e_review "a failing end-to-end test is red" 2 "app: failed: AnswerE2E.shows42" \
  .review/T-006.json
reviewer_ran "red end-to-end tests do not hold the review back"
run_records "a red run that made a review is counted as one" \
  '(.count | type) == "number" and .end == "e2e-red"'
says "its last line says the review is made and the tests did not pass" "REVIEWED — no verified "\
"findings; the end-to-end tests of this run did not pass: see above." "$WORK/run.log"
# A harness says with exit 75 that its device or a tool was not there: the environment,
# not the code. The gate tries the platform once more, and the review is made all the same.
E2E_ONLY=none E2E_EXIT=75 \
  e2e_review "a harness that says the device was not there is believed" 75 \
  "E2E COULD NOT RUN — the environment, not the code" .review/T-006.json
environment_run="$last_run"
says "it names the platform and the exit code twice" "app: .review/e2e.sh says the device or a "\
"tool was not there (exit 75), twice" "$WORK/run.log"
reviewer_ran "the review of that run is made"
if [ -f "$environment_run/approved.json" ]; then
  echo "ok    the review of that run is kept"
else
  echo "FAIL  the review of that run is kept: $environment_run has no approved.json"
  FAILURES=$((FAILURES + 1))
fi
never_says "it is not called red" "E2E RED" "$WORK/run.log"
never_says "and not a missing harness" "NO E2E HARNESS" "$WORK/run.log"
if jq -e '.status == "environment" and .results.app.outcome == "environment"' \
     "$environment_run/e2e.json" >/dev/null 2>&1; then
  echo "ok    its record says the environment"
else
  echo "FAIL  its record says the environment: $environment_run/e2e.json follows"
  sed 's/^/      /' "$environment_run/e2e.json"
  FAILURES=$((FAILURES + 1))
fi
run_records "it records its end as the environment, and counts its review" \
  '.end == "environment" and .exit == 75 and (.count | type) == "number"'
e2e_land "such a run does not land" 3 "condition 3" .review/T-006.json "$environment_run"
e2e_check "after it /qa is held back and told to run the tests again" 2 "E2E DID NOT RUN"
E2E_EXIT=75 E2E_XML="$(xml shows42=failed starts)" \
  e2e_review "a device lost under the tests is the environment's, whatever the report holds" 75 \
  "E2E COULD NOT RUN" .review/T-006.json
if jq -e '.status == "environment"' "$last_run/e2e.json" >/dev/null 2>&1; then
  echo "ok    its record says the environment, not red"
else
  echo "FAIL  its record says the environment, not red: $last_run/e2e.json follows"
  sed 's/^/      /' "$last_run/e2e.json"
  FAILURES=$((FAILURES + 1))
fi
rm -f "$WORK/reviewer-ran"
echo 1 >"$WORK/env-times"
: >"$WORK/e2e-calls"
E2E_ENV_TIMES="$WORK/env-times" E2E_TOUCH="$WORK/e2e-calls" \
  e2e_review "the gate tries the platform once more by itself" 0 "── e2e: pass" \
  .review/T-006.json
if [ "$(grep -c . "$WORK/e2e-calls")" -eq 2 ]; then
  echo "ok    the harness ran twice"
else
  echo "FAIL  the harness ran twice: it ran $(grep -c . "$WORK/e2e-calls") time(s)"
  FAILURES=$((FAILURES + 1))
fi
says "and the run is clean" "CLEAN — gates green, no verified findings." "$WORK/run.log"
printf '%s' "$(finding '"bug"')" >"$WORK/reviewer.json"
printf '%s' "$(verdict '"accept"' no-rule-fired)" >"$WORK/maintainer.json"
E2E_XML="$(xml shows42=failed starts)" \
  e2e_review "findings and red tests come back in one run" 3 "accepted (>= major): 1" \
  .review/T-006.json
says "the red tests are in it" "E2E RED. Failing:" "$WORK/run.log"
says "and its last line says both" "── also: the end-to-end tests of this run did not pass "\
"(above); the task lands only once they do." "$WORK/run.log"
printf '{"findings":[]}' >"$WORK/reviewer.json"
printf '{"verdicts":[]}' >"$WORK/maintainer.json"
rm -f "$WORK/reviewer-ran"

# A run on work whose review is made and whose end-to-end tests have not passed repeats only
# the tests: no review, no run folder, no count. Each run of e2e_review above is a review all
# the same (--again), since each gives the gate another report on the same work.
# e2e_repeat <name> <exit> <line> <task-file> [flags] runs review.sh as the loop does;
# $new_runs is how many run folders it made. record_holds <name> <file> <jq filter>.
e2e_repeat() {
  local name="$1" expected_exit="$2" expected_line="$3" task_file="$4" runs_listed
  shift 4
  runs_listed="$(ls .review/runs)"
  REVIEWER_CMD="touch $WORK/reviewer-ran; cat $WORK/reviewer.json #" \
    MAINTAINER_CMD="cat $WORK/maintainer.json #" \
    "$LIB_DIR/review.sh" --task-file "$task_file" "$@" >"$WORK/run.log" 2>&1
  check "$name" "$expected_exit" "$expected_line" $? "$WORK/run.log"
  new_runs="$(comm -13 <(printf '%s\n' "$runs_listed") <(ls .review/runs) | grep -c .)"
}
record_holds() {
  if [ "$(jq -r "$3" "$2" 2>/dev/null)" = true ]; then
    echo "ok    $1"
  else
    echo "FAIL  $1: «$3» does not hold in $2 — it follows"
    sed 's/^/      /' "$2" 2>/dev/null
    FAILURES=$((FAILURES + 1))
  fi
}
runs_made() {
  if [ "$new_runs" -eq "$2" ]; then
    echo "ok    $1"
  else
    echo "FAIL  $1: the run made $new_runs run folder(s), not $2"
    FAILURES=$((FAILURES + 1))
  fi
}
for task_id in T-100 T-101; do
  printf '{"id": "%s", "title": "Answer 42", "category": "bugfix", "scope": ["src/*"], '\
'"exit_criteria": []}' "$task_id" >".review/$task_id.json"
  mkdir -p ".review/runs/0-qa-$task_id"
  printf '{"task": "%s", "failures": []}' "$task_id" >".review/runs/0-qa-$task_id/qa.json"
done
E2E_ONLY=none E2E_EXIT=75 \
  e2e_repeat "the first run on new work makes its review" 75 "E2E COULD NOT RUN" \
  .review/T-100.json
reviewer_ran "its reviewer ran"
repeated="$(newest_run)"
count_before="$(jq '.count' "$repeated/meta.json")"
: >"$WORK/e2e-calls"
E2E_TOUCH="$WORK/e2e-calls" \
  e2e_repeat "the next run on the same work repeats only the tests" 0 \
  "── this work is reviewed already ($(basename "$repeated"): clean; the end-to-end tests could "\
"not run): only its end-to-end tests run again" .review/T-100.json
reviewer_ran "it makes no review" not
runs_made "it makes no run folder" 0
says "the tests ran once" "── e2e: pass" "$WORK/run.log"
says "it says that the review stands and that none was made" "REPEATED — only the end-to-end "\
"tests of $(basename "$repeated") ran again; its review stands: clean. No review was made, and "\
"none is counted." "$WORK/run.log"
record_holds "such a repeat counts no review" "$repeated/meta.json" \
  ".count == $count_before and .end == \"clean\" and .exit == 0"
if [ "$(newest_run)" = "$repeated" ]; then
  echo "ok    one meta.json stands for the work"
else
  echo "FAIL  one meta.json stands for the work: the newest run is $(newest_run)"
  FAILURES=$((FAILURES + 1))
fi
record_holds "the repeat leaves the run's own record of its tests as it was" \
  "$repeated/e2e.json" '.status == "environment"'
record_holds "and records its own beside it" "$repeated/e2e-again/1/e2e.json" '.status == "pass"'
e2e_check "after the repeat /qa reads what the tests came to last" 0 "check exited 0"
e2e_land "and the run then lands" 0 "For the user to commit" .review/T-100.json "$repeated"
E2E_XML="$(xml shows42=failed starts)" \
  e2e_repeat "work whose tests passed is reviewed again, as before" 2 "E2E RED" \
  .review/T-100.json
reviewer_ran "so its reviewer ran"
red_run="$(newest_run)"
E2E_XML="$(xml shows42=failed starts)" \
  e2e_repeat "red tests on the same work are repeated the same way" 2 \
  "this work is reviewed already" .review/T-100.json
reviewer_ran "the repeat of red tests makes no review" not
E2E_XML="$(xml shows42=failed starts)" \
  e2e_repeat "a third red try on the same work runs" 2 "E2E RED" .review/T-100.json
: >"$WORK/e2e-calls"
E2E_TOUCH="$WORK/e2e-calls" E2E_XML="$(xml shows42=failed starts)" \
  e2e_repeat "a fourth red try on the same work is stopped" 6 "STOPPED — the end-to-end tests "\
"of T-100 were red in 3 tries in a row on the same work ($(basename "$red_run")); nothing ran." \
  .review/T-100.json
says "it names what failed" "   app: failed: AnswerE2E.shows42" "$WORK/run.log"
says "a retry of red tests is the loop's, and does not mend them" \
  "   The loop goes on: a retry does not mend it" "$WORK/run.log"
never_says "and is no question" "For the user" "$WORK/run.log"
if [ ! -s "$WORK/e2e-calls" ]; then
  echo "ok    at that stop no test ran"
else
  echo "FAIL  at that stop no test ran: the harness ran"
  FAILURES=$((FAILURES + 1))
fi
e2e_repeat "--past-limit there needs the loop's reason" 1 "needs --because" .review/T-100.json \
  --past-limit
e2e_repeat "and takes no decision of the user" 1 "--user-decided is for a stop that is the user's" \
  .review/T-100.json --past-limit --user-decided
E2E_XML="$(xml shows42=failed starts)" \
  e2e_repeat "its reason lets it try once more" 2 "this work is reviewed already" \
  .review/T-100.json --past-limit --because "the device was busy with another run"
record_holds "the reason is kept with the repeat" "$red_run/e2e-again/3/past-limit.json" \
  '.because == "the device was busy with another run" and .user_decided == null'
record_holds "and not in the run's meta.json" "$red_run/meta.json" \
  '.past_limit == false and .stop == null and .because == null and .user_decided == null'
for attempt in second third; do
  E2E_XML="$(xml shows42=failed starts)" \
    e2e_repeat "a red try after the loop's reason runs ($attempt)" 2 "E2E RED" .review/T-100.json
done
E2E_XML="$(xml shows42=failed starts)" \
  e2e_repeat "red tries on the same work after the loop's reason are the user's" 6 \
  "NOT CONVERGING — the end-to-end tests of T-100 were red in 3 tries in a row on the same work "\
"($(basename "$red_run")) after the loop's reason passed this stop; nothing ran." \
  .review/T-100.json
says "it says the reason that did not hold" \
  "   the loop's reason then, which did not hold: the device was busy with another run" \
  "$WORK/run.log"
says "and that the work does not converge" "   For the user, the work does not converge:" \
  "$WORK/run.log"
e2e_repeat "there the loop's reason passes no more" 1 "this stop takes --user-decided" \
  .review/T-100.json --past-limit --because "the device is free now"
E2E_XML="$(xml shows42=failed starts)" \
  e2e_repeat "once the user decided to go on it tries once more" 2 \
  "this work is reviewed already" .review/T-100.json --past-limit --user-decided
record_holds "the repeat records that they decided, and no words" \
  "$red_run/e2e-again/6/past-limit.json" '.user_decided == true and .because == null'
E2E_XML="$(xml shows42=failed starts)" \
  e2e_repeat "a decision of the user lets one try through" 6 "NOT CONVERGING" .review/T-100.json
E2E_ONLY=none E2E_EXIT=75 \
  e2e_repeat "--again reviews the same work again" 75 "E2E COULD NOT RUN" .review/T-100.json \
  --again
reviewer_ran "the reviewer ran on the same work"
runs_made "and the run made a folder of its own" 1
absent_run="$(newest_run)"
for attempt in second third; do
  E2E_ONLY=none E2E_EXIT=75 \
    e2e_repeat "a try with no device on the same work runs ($attempt)" 75 \
    "this work is reviewed already" .review/T-100.json
done
E2E_ONLY=none E2E_EXIT=75 \
  e2e_repeat "a device that stays away stops the repeat" 6 "STOPPED — the end-to-end tests of "\
"T-100 could not run in 3 tries in a row on the same work ($(basename "$absent_run")); nothing "\
"ran." .review/T-100.json
says "and names no user: the loop restores it" "   The loop goes on: restore it" "$WORK/run.log"
never_says "a device that stays away is no question" "For the user" "$WORK/run.log"
E2E_ONLY=none E2E_EXIT=75 \
  e2e_repeat "what the loop restored lets it try once more" 75 "this work is reviewed already" \
  .review/T-100.json --past-limit --because "the emulator is booted again"
for attempt in second third; do
  E2E_ONLY=none E2E_EXIT=75 \
    e2e_repeat "a try with no device after the loop's reason runs ($attempt)" 75 \
    "this work is reviewed already" .review/T-100.json
done
E2E_ONLY=none E2E_EXIT=75 \
  e2e_repeat "a device still away after what the loop restored is the user's to bring" 6 \
  "could not run in 3 tries in a row on the same work ($(basename "$absent_run")) after the "\
"loop's reason passed this stop; nothing ran." .review/T-100.json
says "only they can bring it" "   For the user, only they can:" "$WORK/run.log"
E2E_XML='<testsuite tests="0"/>' \
  e2e_repeat "a harness that ran no test" 1 "NO END-TO-END TEST RAN" .review/T-100.json --again
no_test_run="$(newest_run)"
for attempt in second third; do
  E2E_XML='<testsuite tests="0"/>' \
    e2e_repeat "a repeat that runs no test runs ($attempt)" 1 "this work is reviewed already" \
    .review/T-100.json
done
E2E_XML='<testsuite tests="0"/>' \
  e2e_repeat "repeats that run no test on the same work are bounded the same way" 6 \
  "could not run in 3 tries in a row on the same work ($(basename "$no_test_run"))" \
  .review/T-100.json
says "it names what stopped them" "   app: the e2e run ran no test (exit 0)" "$WORK/run.log"
cp src/answer.kt "$WORK/answer.kt"
printf '// once more\n' >>src/answer.kt
e2e_repeat "changed work is reviewed again" 0 "CLEAN — gates green" .review/T-100.json
reviewer_ran "the reviewer ran on the changed work"
runs_made "and the run of the changed work has a folder of its own" 1
cp "$WORK/answer.kt" src/answer.kt
printf 'THRESHOLD=major\nLANDING=off\nASK_AFTER_RUNS=1\n' >.review/land.conf
E2E_ONLY=none E2E_EXIT=75 \
  e2e_repeat "a task's one review whose tests could not run" 75 "E2E COULD NOT RUN" \
  .review/T-101.json
e2e_repeat "a task at its limit can still repeat its tests" 0 "this work is reviewed already" \
  .review/T-101.json
never_says "the limit of reviews does not stop the repeat" "LIMIT OF REVIEWS" "$WORK/run.log"
for tries in 0 three; do
  printf 'THRESHOLD=major\nLANDING=off\nASK_AFTER_RUNS=100\nE2E_TRIES=%s\n' "$tries" \
    >.review/land.conf
  e2e_repeat "an E2E_TRIES of '$tries' fails closed" 1 \
    "E2E_TRIES in .review/land.conf must be a whole number from 1" .review/T-101.json
done
printf 'THRESHOLD=major\nLANDING=off\nASK_AFTER_RUNS=100\n' >.review/land.conf
# The landing's condition on a /qa failure reads every try. Its green side is the newest try
# of the run that is landed; its red side is every try of every other run of the task, the
# run's own and each repeat's, each with its own time and its own words of the cases. A try
# of the run that is landed is never the red side: red and then green on the same work
# proves no fix.
for task_id in T-103 T-104 T-105 T-106 T-107; do
  printf '{"id": "%s", "title": "Answer 42", "category": "bugfix", "scope": ["src/*"], '\
'"exit_criteria": []}' "$task_id" >".review/$task_id.json"
  mkdir -p ".review/runs/0-qa-$task_id"
  printf '{"task": "%s", "failures": [{"case": "TC-001"}]}' "$task_id" \
    >".review/runs/0-qa-$task_id/qa.json"
done
cp src/answer.kt "$WORK/answer.kt"
E2E_XML="$(xml shows42=failed starts)" \
  e2e_repeat "the test of a /qa failure is red before its fix" 2 \
  "app: failed: AnswerE2E.shows42" .review/T-103.json
printf '// the fix\n' >>src/answer.kt
E2E_ONLY=none E2E_EXIT=75 \
  e2e_repeat "the run of the fix whose own try could not run" 75 "E2E COULD NOT RUN" \
  .review/T-103.json
fixed_run="$(newest_run)"
e2e_repeat "and whose repeat passes" 0 "REPEATED" .review/T-103.json
e2e_land "a fix whose own try could not run and whose repeat passed lands" 0 \
  "For the user to commit" .review/T-103.json "$fixed_run"
cp "$WORK/answer.kt" src/answer.kt
E2E_ONLY=none E2E_EXIT=75 \
  e2e_repeat "a run whose own try could not run" 75 "E2E COULD NOT RUN" .review/T-104.json
same_run="$(newest_run)"
E2E_XML="$(xml shows42=failed starts)" \
  e2e_repeat "the test of a /qa failure is red in its repeat" 2 \
  "this work is reviewed already" .review/T-104.json
e2e_repeat "and green in the next repeat on the same work" 0 "REPEATED" .review/T-104.json
e2e_land "red, then green in tries of the run that is landed is not proven" 3 \
  "a /qa failure without an end-to-end test seen red, then green: TC-001" \
  .review/T-104.json "$same_run"
printf '// the fix\n' >>src/answer.kt
e2e_repeat "the fix is reviewed, and its test passes" 0 "CLEAN — gates green" \
  .review/T-104.json
e2e_land "a failure seen red only in a repeat of an earlier run, then green, lands" 0 \
  "For the user to commit" .review/T-104.json "$(newest_run)"
cp "$WORK/answer.kt" src/answer.kt
E2E_ONLY=none E2E_EXIT=75 \
  e2e_repeat "a run of a case that is then reworded could not run" 75 "E2E COULD NOT RUN" \
  .review/T-105.json
red_run="$(newest_run)"
E2E_XML="$(xml shows42=failed starts)" \
  e2e_repeat "its test is red in the repeat" 2 "this work is reviewed already" \
  .review/T-105.json
sed 's/it shows 42\./it shows a number./' "$WORK/test-cases.md" >qa/test-cases.md
printf '// the fix\n' >>src/answer.kt
e2e_repeat "with the case reworded the fix is reviewed, and its test passes" 0 \
  "CLEAN — gates green" .review/T-105.json
e2e_land "a case reworded between a red repeat and the green run proves nothing" 3 \
  "whose words changed since /qa failed it: TC-001 (as recorded in $(basename "$red_run")/"\
"e2e-again/1)" .review/T-105.json "$(newest_run)"
cp "$WORK/test-cases.md" qa/test-cases.md
cp "$WORK/answer.kt" src/answer.kt
E2E_ONLY=none E2E_EXIT=75 \
  e2e_repeat "a run of another task with the same /qa failure could not run" 75 \
  "E2E COULD NOT RUN" .review/T-106.json
E2E_XML="$(xml shows42=failed starts)" \
  e2e_repeat "and its test is red in the repeat" 2 "this work is reviewed already" \
  .review/T-106.json
printf '// the fix\n' >>src/answer.kt
e2e_repeat "the fix in a task of its own passes" 0 "CLEAN — gates green" .review/T-107.json
e2e_land "a red repeat of another task proves nothing" 3 \
  "a /qa failure without an end-to-end test seen red, then green: TC-001" \
  .review/T-107.json "$(newest_run)"
cp "$WORK/answer.kt" src/answer.kt
rm -f "$WORK/reviewer-ran"

# The hold on a platform. One run of the end-to-end tests uses android or ios at a time, in
# every copy of every project on the machine: e2e-gate.sh holds the platform with a folder in
# DEVICE_LOCK_DIR ($WORK/devices here) while it runs the harness, waits while another holds
# it, and gives it back. A second copy of the project, a clone with the files of .review/
# that are not committed, shares the platform with the first. hold_by_another <seconds from
# now> <pid> makes a hold by hand, as a run of another copy, elsewhere, would: it holds until
# then, and its run is the process <pid>. held_start <copy> <log> [flags] starts review.sh
# there in the background, as e2e_review does, and $held_pid is its process; held_review
# waits for it. stamped <line> waits until the harness has stamped the line, arrives <file>
# until the file is there.
printf '{"id": "T-102", "title": "Answer 42", "category": "bugfix", "scope": ["src/*"], '\
'"exit_criteria": []}' >.review/T-102.json
holds="$DEVICE_LOCK_DIR"
copy="$WORK/copy"
git clone -q "$repository" "$copy" || fail_setup "the second copy"
cp .review/gates.sh .review/REVIEW_POLICY.md .review/land.conf .review/T-102.json \
  "$copy/.review/" && cp src/answer.kt "$copy/src/answer.kt" || fail_setup "the second copy"
on_android() {
  mkdir -p "$1/app/src/main" && printf '<category android:name="android.intent.category.LAUNCHER"/>\n' \
    >"$1/app/src/main/AndroidManifest.xml" || fail_setup "an Android app in $1"
}
on_android "$repository"
on_android "$copy"
hold_by_another() {
  local started
  started="$(. "$LIB_DIR/common.sh" && process_started "$2")"
  mkdir -p "$holds/android.lock" && \
    jq -n --argjson until "$(( $(date +%s) + $1 ))" --argjson pid "$2" --arg started "$started" \
      '{pid: $pid, pid_started: $started, root: "/elsewhere/project",
        who: ".review/runs/elsewhere", kind: "run", since: ($until - 600), until: $until}' \
      >"$holds/android.lock/holder" \
    || fail_setup "a hold of another copy"
}
held_start() {
  local copy="$1" log="$2"
  shift 2
  (cd "$copy" && REVIEWER_CMD="touch $WORK/reviewer-ran; cat $WORK/reviewer.json #" \
    MAINTAINER_CMD="cat $WORK/maintainer.json #" \
    exec "$LIB_DIR/review.sh" --task-file .review/T-102.json "$@") >"$log" 2>&1 &
  held_pid=$!
}
held_review() {
  held_start "$@"
  wait "$held_pid"
}
stamped() {
  local tenths=0
  until grep -q "$1" "$WORK/stamps" 2>/dev/null; do
    tenths=$((tenths + 1))
    [ "$tenths" -lt 600 ] || return 1
    sleep 0.1
  done
}
arrives() {
  local tenths=0
  until [ -e "$1" ]; do
    tenths=$((tenths + 1))
    [ "$tenths" -lt 600 ] || return 1
    sleep 0.1
  done
}
: >"$WORK/stamps"
E2E_SLEEP=3 E2E_STAMPS="$WORK/stamps" held_start "$repository" "$WORK/first.log" --again
first_pid="$held_pid"
stamped "android start" || fail_setup "the first run's tests did not start"
E2E_SLEEP=3 E2E_STAMPS="$WORK/stamps" held_review "$copy" "$WORK/second.log" --again
second_exit=$?
wait "$first_pid"
first_exit=$?
overlap="$(awk '$2 == "start" { if (open != "") { print "overlap"; exit } open = $3 }
  $2 == "end" && $3 == open { open = "" }' "$WORK/stamps")"
if [ "$first_exit" -eq 0 ] && [ "$second_exit" -eq 0 ] && [ -z "$overlap" ] \
   && [ "$(grep -c ' start ' "$WORK/stamps")" -eq 2 ]; then
  echo "ok    two runs of the tests on one platform never overlap"
else
  echo "FAIL  two runs of the tests on one platform never overlap: exit $first_exit and"\
" $second_exit; the stamps, then the two logs, follow"
  sed 's/^/      /' "$WORK/stamps" "$WORK/first.log" "$WORK/second.log"
  FAILURES=$((FAILURES + 1))
fi
says "the second says what it waits for" "── android: waiting — held by .review/runs/" \
  "$WORK/second.log"
if [ ! -e "$holds/android.lock" ]; then
  echo "ok    and the platform is given back after both"
else
  echo "FAIL  and the platform is given back after both: $holds/android.lock is there"
  FAILURES=$((FAILURES + 1))
fi
rm -f "$WORK/reviewer-ran"
sleep 300 &
holder_pid=$!
hold_by_another 600 "$holder_pid"
printf 'E2E_WAIT=1\nE2E_TRIES=1\n' >>.review/land.conf
held_review "$repository" "$WORK/run.log" --again
check "a platform still busy after E2E_WAIT is the environment's, and the review is made" 75 \
  "android: busy — held by .review/runs/elsewhere of /elsewhere/project since " $? \
  "$WORK/run.log"
reviewer_ran "its review is made"
says "and running it again later is the loop's" \
  "   The loop goes on: run review.sh again later: it repeats only these tests" "$WORK/run.log"
e2e_repeat "a wait for a busy platform is no try with a device that was not there" 75 \
  "── this work is reviewed already" .review/T-102.json
hold_by_another -5 "$holder_pid"
e2e_repeat "a run whose hold ran out while it still lives keeps the platform" 75 \
  "android: busy — held by .review/runs/elsewhere of /elsewhere/project" .review/T-102.json
kill "$holder_pid" 2>/dev/null
wait "$holder_pid" 2>/dev/null
e2e_repeat "a hold that ran out is taken over" 0 "── android: the hold of .review/runs/elsewhere "\
"of /elsewhere/project ran out — taking over" .review/T-102.json
says "and the repeat it let through ran the tests" "REPEATED — only the end-to-end tests" \
  "$WORK/run.log"
printf 'THRESHOLD=major\nLANDING=off\nASK_AFTER_RUNS=100\n' >.review/land.conf
mkdir -p "$holds/android.lock" && touch -t 202001010000 "$holds/android.lock" \
  || fail_setup "a hold with no record"
held_review "$repository" "$WORK/run.log" --again
check "a hold that never said who holds it is taken over after a minute" 0 \
  "names no holder and is over a minute old — taking over" $? "$WORK/run.log"
rm -f "$WORK/reviewer-ran"
: >"$WORK/stamps"
HOLD_LEASE=3 HOLD_RENEW=1 E2E_SLEEP=30 E2E_STAMPS="$WORK/stamps" \
  held_start "$repository" "$WORK/first.log" --again
first_pid="$held_pid"
stamped "android start" || fail_setup "the tests of the run to be killed did not start"
arrives "$holds/android.lock/group" || fail_setup "the run to be killed recorded no group"
harness_pid="$(awk '$2 == "start" { print $3; exit }' "$WORK/stamps")"
gate_pid="$(jq -r '.pid' "$holds/android.lock/holder" 2>/dev/null)"
case "$gate_pid" in ''|*[!0-9]*) gate_pid="" ;; esac
[ -z "$gate_pid" ] || kill -9 "$gate_pid"
HOLD_LEASE=3 HOLD_RENEW=1 held_review "$copy" "$WORK/second.log" --again
check "a gate killed while its tests run gives the platform back" 0 \
  "ran out — taking over" $? "$WORK/second.log"
says "and whoever takes it over stops the tests it left running" \
  "; stopped what it left running: " "$WORK/second.log"
# The harness, whose gate is gone, is no child of this test: once stopped it may stay a
# zombie until the system reaps it.
runs_still() {
  case "$(ps -o stat= -p "$1" 2>/dev/null)" in
    '' | *Z*) return 1 ;;
  esac
}
sleep 1
if runs_still "$harness_pid"; then
  echo "FAIL  the first harness is gone: process $harness_pid still runs"
  kill "$harness_pid" 2>/dev/null
  FAILURES=$((FAILURES + 1))
else
  echo "ok    the first harness is gone"
fi
wait "$first_pid" 2>/dev/null
# The harness starts only once its process group is recorded with the hold. Here jq, on the
# one call that records it, writes $WORK/recording and takes two seconds, or fails (JQ_GROUP).
mkdir -p "$WORK/group-jq" && printf '#!/bin/sh
case "$*" in *group_started:*) : >"%s"
  [ -z "$JQ_GROUP" ] || exit "$JQ_GROUP"; sleep 2 ;; esac
exec "%s" "$@"
' \
  "$WORK/recording" "$(command -v jq)" >"$WORK/group-jq/jq" && chmod +x "$WORK/group-jq/jq" \
  || fail_setup "a jq that records the group slowly"
rm -f "$WORK/reviewer-ran" "$WORK/recording"
: >"$WORK/stamps"
JQ_GROUP="" PATH="$WORK/group-jq:$PATH" HOLD_LEASE=3 HOLD_RENEW=1 E2E_SLEEP=30 \
  E2E_STAMPS="$WORK/stamps" held_start "$repository" "$WORK/first.log" --again
first_pid="$held_pid"
arrives "$WORK/recording" || fail_setup "the run to be killed did not record its group"
gate_pid="$(jq -r '.pid' "$holds/android.lock/holder" 2>/dev/null)"
case "$gate_pid" in ''|*[!0-9]*) gate_pid="" ;; esac
[ -z "$gate_pid" ] || kill -9 "$gate_pid"
HOLD_LEASE=3 HOLD_RENEW=1 E2E_STAMPS="$WORK/stamps" held_review "$copy" "$WORK/second.log" --again
check "a gate killed while it records the group of its harness gives the platform back" 0 \
  "ran out — taking over" $? "$WORK/second.log"
sleep 1
left=""
for pid in $(awk '$2 == "start" { print $3 }' "$WORK/stamps"); do
  runs_still "$pid" && { left="$left $pid"; kill -- "-$pid" 2>/dev/null || kill "$pid"; }
done
if [ -z "$left" ] && [ "$(grep -c ' start ' "$WORK/stamps")" -eq 1 ]; then
  echo "ok    and leaves no harness: its own never started"
else
  echo "FAIL  and leaves no harness: its own never started: still running:${left:- none} — the"\
" stamps follow"
  sed 's/^/      /' "$WORK/stamps"
  FAILURES=$((FAILURES + 1))
fi
wait "$first_pid" 2>/dev/null
rm -f "$WORK/reviewer-ran"
: >"$WORK/stamps"
JQ_GROUP=5 PATH="$WORK/group-jq:$PATH" E2E_STAMPS="$WORK/stamps" \
  held_review "$repository" "$WORK/run.log" --again
check "a harness whose group cannot be recorded with the hold is not started" 75 \
  "android: the hold cannot be made at $holds/android.lock" $? "$WORK/run.log"
if [ ! -s "$WORK/stamps" ] && [ ! -e "$holds/android.lock" ]; then
  echo "ok    no test of it ran, and the platform is given back"
else
  echo "FAIL  no test of it ran, and the platform is given back: the hold is"\
" $([ -e "$holds/android.lock" ] && echo "still there" || echo gone) — the stamps follow"
  sed 's/^/      /' "$WORK/stamps"
  FAILURES=$((FAILURES + 1))
fi
# Two runs that wait for the same hold that ran out: one takes it over, the other goes on
# waiting. Here the second reads the hold first, and slowly: its jq, on the read of until,
# writes $WORK/reading and waits until the tests of the first have begun.
mkdir -p "$WORK/until-jq" && printf '#!/bin/sh
case "$*" in *".until | floor"*) : >"%s"
  tenths=0
  until grep -q " start " "%s" 2>/dev/null || [ "$tenths" -ge 600 ]; do
    sleep 0.1; tenths=$((tenths + 1))
  done ;;
esac
exec "%s" "$@"
' "$WORK/reading" "$WORK/stamps" "$(command -v jq)" \
  >"$WORK/until-jq/jq" && chmod +x "$WORK/until-jq/jq" || fail_setup "a jq that reads slowly"
sleep 0 &
gone_pid=$!
wait "$gone_pid"
hold_by_another -5 "$gone_pid"
rm -f "$WORK/reviewer-ran" "$WORK/reading"
: >"$WORK/stamps"
PATH="$WORK/until-jq:$PATH" E2E_SLEEP=3 E2E_STAMPS="$WORK/stamps" \
  held_start "$copy" "$WORK/second.log" --again
second_pid="$held_pid"
arrives "$WORK/reading" || fail_setup "the slow run did not read the hold"
E2E_SLEEP=3 E2E_STAMPS="$WORK/stamps" held_review "$repository" "$WORK/first.log" --again
first_exit=$?
wait "$second_pid"
second_exit=$?
overlap="$(awk '$2 == "start" { if (open != "") { print "overlap"; exit } open = $3 }
  $2 == "end" && $3 == open { open = "" }' "$WORK/stamps")"
if [ "$first_exit" -eq 0 ] && [ "$second_exit" -eq 0 ] && [ -z "$overlap" ] \
   && [ "$(grep -c ' start ' "$WORK/stamps")" -eq 2 ]; then
  echo "ok    of two runs that wait for one hold that ran out, one takes it over and the other waits"
else
  echo "FAIL  of two runs that wait for one hold that ran out, one takes it over and the other"\
" waits: exit $first_exit and $second_exit; the stamps, then the two logs, follow"
  sed 's/^/      /' "$WORK/stamps" "$WORK/first.log" "$WORK/second.log"
  FAILURES=$((FAILURES + 1))
fi
says "the first takes it over" "ran out — taking over" "$WORK/first.log"
says "the other waits for the first, and names it" "── android: waiting — held by .review/runs/" \
  "$WORK/second.log"
says "the first by its project" " of $repository since " "$WORK/second.log"
# A taker that was killed while it took a hold over leaves <lock>.taking: once it is over a
# minute old, the next taker removes it.
rm -f "$WORK/reviewer-ran"
printf 'E2E_WAIT=5\n' >>.review/land.conf
hold_by_another -5 "$gone_pid"
mkdir -p "$holds/android.lock.taking" && touch -t 202001010000 "$holds/android.lock.taking" \
  || fail_setup "what a killed taker left"
held_review "$repository" "$WORK/run.log" --again
check "what a taker that was killed left does not keep the hold from being taken over" 0 \
  "ran out — taking over" $? "$WORK/run.log"
if [ ! -e "$holds/android.lock.taking" ] && [ ! -e "$holds/android.lock" ]; then
  echo "ok    and nothing of the take-over is left"
else
  echo "FAIL  and nothing of the take-over is left: $(ls "$holds" | tr '\n' ' ')"
  FAILURES=$((FAILURES + 1))
fi
printf 'THRESHOLD=major\nLANDING=off\nASK_AFTER_RUNS=100\n' >.review/land.conf
rm -f "$WORK/reviewer-ran"
: >"$WORK/stamps"
E2E_SLEEP=30 E2E_STAMPS="$WORK/stamps" held_start "$repository" "$WORK/run.log" --again
stamped "android start" || fail_setup "the tests of the run to be stopped did not start"
harness_pid="$(awk '$2 == "start" { print $3; exit }' "$WORK/stamps")"
[ -d "$holds/android.lock" ] && held_while_running=yes || held_while_running=no
kill -TERM "$held_pid"
stopped_at="$(date +%s)"
wait "$held_pid"
stopped_in=$(( $(date +%s) - stopped_at ))
if [ "$held_while_running" = yes ] && [ ! -e "$holds/android.lock" ] && [ "$stopped_in" -lt 10 ]
then
  echo "ok    a run that is stopped releases at once"
else
  echo "FAIL  a run that is stopped releases at once: held while it ran: $held_while_running;"\
" ended $stopped_in s after the stop; the hold is"\
" $([ -e "$holds/android.lock" ] && echo "still there" || echo gone) — the log follows"
  sed 's/^/      /' "$WORK/run.log"
  FAILURES=$((FAILURES + 1))
fi
if runs_still "$harness_pid"; then
  echo "FAIL  and stops its tests: process $harness_pid still runs"
  kill "$harness_pid" 2>/dev/null
  FAILURES=$((FAILURES + 1))
else
  echo "ok    and stops its tests"
fi
rm -f "$WORK/reviewer-ran"
: >"$WORK/a-file"
DEVICE_LOCK_DIR="$WORK/a-file/devices" held_review "$repository" "$WORK/run.log" --again
check "a place where no hold can be made is said, never passed over" 75 \
  "android: the hold cannot be made at $WORK/a-file/devices/android.lock" $? "$WORK/run.log"
says "where the runs meet is the user's to say" "   For the user, only they can: let the runs meet" \
  "$WORK/run.log"
reviewer_ran "and the review is made"
printf 'E2E_LOCK=off\n' >>.review/land.conf
DEVICE_LOCK_DIR="$WORK/a-file/devices" held_review "$repository" "$WORK/run.log" --again
check "E2E_LOCK=off runs without a hold" 0 "── e2e: pass on android" $? "$WORK/run.log"
# A harness that ends by itself within E2E_TIMEOUT is read by what it left, held or not.
printf 'THRESHOLD=major\nLANDING=off\nASK_AFTER_RUNS=100\nE2E_TIMEOUT=30\n' >.review/land.conf
held_review "$repository" "$WORK/run.log" --again
check "a harness that ends within E2E_TIMEOUT passes" 0 "── e2e: pass on android" $? \
  "$WORK/run.log"
never_says "and its platform is not one whose hold cannot be made" "the hold cannot be made" \
  "$WORK/run.log"
E2E_XML="$(xml shows42=failed starts)" held_review "$repository" "$WORK/run.log" --again
check "one whose test failed within E2E_TIMEOUT is red, the test named" 2 \
  "android: failed: AnswerE2E.shows42" $? "$WORK/run.log"
printf 'E2E_LOCK=off\n' >>.review/land.conf
held_review "$repository" "$WORK/run.log" --again
check "and with E2E_LOCK=off one that ends within E2E_TIMEOUT passes" 0 \
  "── e2e: pass on android" $? "$WORK/run.log"
printf 'THRESHOLD=major\nLANDING=off\nASK_AFTER_RUNS=100\nE2E_TIMEOUT=2\n' >.review/land.conf
started_at="$(date +%s)"
E2E_SLEEP=60 held_review "$repository" "$WORK/run.log" --again
check "a harness that does not end is stopped" 75 \
  "android: .review/e2e.sh did not end in 2 s (E2E_TIMEOUT) and was stopped" $? "$WORK/run.log"
if [ $(( $(date +%s) - started_at )) -lt 20 ] && [ ! -e "$holds/android.lock" ]; then
  echo "ok    the run then ends, and gives the platform back"
else
  echo "FAIL  the run then ends, and gives the platform back: it took"\
" $(( $(date +%s) - started_at )) s; the hold is"\
" $([ -e "$holds/android.lock" ] && echo "still there" || echo gone)"
  FAILURES=$((FAILURES + 1))
fi
# What a platform that E2E_TIMEOUT stopped comes to is read from what its harness left.
says "one that left nothing could not finish its tests: the environment" \
  "E2E COULD NOT RUN — the environment, not the code:" "$WORK/run.log"
never_says "and is no missing harness" "NO E2E HARNESS" "$WORK/run.log"
never_says "nor a harness that ran no test" "NO END-TO-END TEST RAN" "$WORK/run.log"
E2E_HANG=60 held_review "$repository" "$WORK/run.log" --again
check "one stopped after its tests passed could not finish them either" 75 \
  "android: .review/e2e.sh did not end in 2 s (E2E_TIMEOUT) and was stopped" $? "$WORK/run.log"
record_holds "and never passes" "$(newest_run)/e2e.json" \
  '.status == "environment" and .results.android.outcome == "environment"'
never_says "and is no missing harness either" "NO E2E HARNESS" "$WORK/run.log"
E2E_HANG=60 E2E_XML="$(xml shows42=failed starts)" held_review "$repository" "$WORK/run.log" \
  --again
check "one stopped after a test failed is red, the test named" 2 \
  "android: failed: AnswerE2E.shows42" $? "$WORK/run.log"
says "and the stop said" \
  "android: .review/e2e.sh did not end in 2 s (E2E_TIMEOUT) and was stopped" "$WORK/run.log"
never_says "and it is no missing harness" "NO E2E HARNESS" "$WORK/run.log"
never_says "nor one that ran no test" "NO END-TO-END TEST RAN" "$WORK/run.log"
for setting in E2E_WAIT=soon E2E_TIMEOUT=-1 E2E_LOCK=yes; do
  printf 'THRESHOLD=major\nLANDING=off\nASK_AFTER_RUNS=100\n%s\n' "$setting" >.review/land.conf
  held_review "$repository" "$WORK/run.log" --again
  check "an $setting fails closed" 1 "${setting%%=*} in .review/land.conf must be " $? \
    "$WORK/run.log"
done
# A check that drives a device by hand — /qa, the executor — takes the same hold with
# device.sh, as a check of its copy of the project, for some minutes: it runs out by itself,
# and the check takes the platform again to keep it. device <copy> <log> <arguments> runs
# device.sh in a copy; the stand-ins adb and xcrun append what they are asked to
# $WORK/device.log. held_until <platform> prints until when the platform is held.
mkdir -p "$WORK/device-bin" || fail_setup "device-bin"
for tool in adb xcrun; do
  printf '#!/bin/sh\necho "%s $*" >>"$DEVICE_LOG"\n' "$tool" >"$WORK/device-bin/$tool" \
    && chmod +x "$WORK/device-bin/$tool" || fail_setup "a stand-in $tool"
done
: >"$WORK/device.log"
device() {
  local copy="$1" log="$2"
  shift 2
  (cd "$copy" && DEVICE_LOG="$WORK/device.log" PATH="$WORK/device-bin:$PATH" \
    exec "$LIB_DIR/device.sh" "$@") >"$log" 2>&1
}
held_until() { jq -r '.until' "$holds/$1.lock/holder" 2>/dev/null; }
printf 'THRESHOLD=major\nLANDING=off\nASK_AFTER_RUNS=100\n' >.review/land.conf
rm -f "$WORK/reviewer-ran"
: >"$WORK/stamps"
E2E_SLEEP=3 E2E_STAMPS="$WORK/stamps" held_start "$repository" "$WORK/run.log" --again
stamped "android start" || fail_setup "the tests of the run a check waits for did not start"
device "$repository" "$WORK/device-take.log" take android
take_exit=$?
grep -q "android end" "$WORK/stamps" && after_the_run=yes || after_the_run=no
wait "$held_pid"
if [ "$take_exit" -eq 0 ] && [ "$after_the_run" = yes ] && [ -d "$holds/android.lock" ]; then
  echo "ok    device.sh take waits while a run holds the platform"
else
  echo "FAIL  device.sh take waits while a run holds the platform: exit $take_exit; after the"\
" run's tests: $after_the_run — the stamps, then its log, follow"
  sed 's/^/      /' "$WORK/stamps" "$WORK/device-take.log"
  FAILURES=$((FAILURES + 1))
fi
says "and says whom it waits for" "── android: waiting — held by .review/runs/" \
  "$WORK/device-take.log"
held_review "$repository" "$WORK/run.log" --again
check "a run takes over the hold of its own copy's check" 0 \
  "is this copy's own — taking over" $? "$WORK/run.log"
device "$copy" "$WORK/device-take.log" take android
check "device.sh take holds a free platform at once" 0 \
  "── android: held for this copy of the project until " $? "$WORK/device-take.log"
printf 'E2E_WAIT=1\n' >>.review/land.conf
held_review "$repository" "$WORK/run.log" --again
check "while a check of another copy holds the platform a run waits" 75 \
  "android: busy — held by a check by hand of " $? "$WORK/run.log"
printf 'THRESHOLD=major\nLANDING=off\nASK_AFTER_RUNS=100\nE2E_WAIT=60\n' >.review/land.conf
held_start "$repository" "$WORK/run.log" --again
tenths=0
until grep -q "waiting — held by a check by hand of " "$WORK/run.log" 2>/dev/null; do
  tenths=$((tenths + 1))
  [ "$tenths" -lt 300 ] || break
  sleep 0.1
done
device "$copy" "$WORK/device-release.log" release android
release_exit=$?
wait "$held_pid"
check "its release lets the run go" 0 "── e2e: pass on android" $? "$WORK/run.log"
check "device.sh release gives the platform back" 0 "── android: given back" "$release_exit" \
  "$WORK/device-release.log"
device "$repository" "$WORK/device-take.log" take ios android
check "device.sh take holds several platforms" 0 "── ios: held for this copy" $? \
  "$WORK/device-take.log"
device "$repository" "$WORK/device-off.log" off android android emulator-5558
check "device.sh off switches a device off while this copy holds its platform" 0 \
  "── android: switched off emulator-5558" $? "$WORK/device-off.log"
says "with adb" "adb -s emulator-5558 emu kill" "$WORK/device.log"
device "$repository" "$WORK/device-off.log" off ios ios UDID-1
check "and a simulator" 0 "── ios: switched off UDID-1" $? "$WORK/device-off.log"
says "with simctl" "xcrun simctl shutdown UDID-1" "$WORK/device.log"
held_before="$(held_until android)"
device "$repository" "$WORK/device-take.log" take android --minutes 90
held_after="$(held_until android)"
if [ $(( ${held_after:-0} - ${held_before:-0} )) -ge 3000 ]; then
  echo "ok    taken again, the hold is made longer"
else
  echo "FAIL  taken again, the hold is made longer: until $held_before, then $held_after — the"\
" log follows"
  sed 's/^/      /' "$WORK/device-take.log"
  FAILURES=$((FAILURES + 1))
fi
device "$repository" "$WORK/status.log" status
check "device.sh status says who holds each platform, and until when" 0 \
  "android: held by a check by hand of " $? "$WORK/status.log"
says "and of every platform held" "ios: held by a check by hand of " "$WORK/status.log"
device "$repository" "$WORK/device-release.log" release android ios
release_exit=$?
if [ "$release_exit" -eq 0 ] && [ ! -e "$holds/android.lock" ] && [ ! -e "$holds/ios.lock" ]
then
  echo "ok    device.sh release gives every platform it names back"
else
  echo "FAIL  device.sh release gives every platform it names back: exit $release_exit — the"\
" log follows"
  sed 's/^/      /' "$WORK/device-release.log"
  FAILURES=$((FAILURES + 1))
fi
sleep 300 &
holder_pid=$!
hold_by_another 600 "$holder_pid"
cp "$WORK/device.log" "$WORK/device.log.before"
device "$repository" "$WORK/device-off.log" off android android emulator-5554
check "off refuses while another holds the platform" 1 \
  "android is held by .review/runs/elsewhere of /elsewhere/project since " $? \
  "$WORK/device-off.log"
says "taking the platform first is the loop's" "   The loop goes on: take the platform first" \
  "$WORK/device-off.log"
device "$repository" "$WORK/device-release.log" release android
check "release refuses while another holds the platform" 1 \
  "android is held by .review/runs/elsewhere of /elsewhere/project since " $? \
  "$WORK/device-release.log"
if cmp -s "$WORK/device.log" "$WORK/device.log.before" && \
   [ "$(jq -r '.root' "$holds/android.lock/holder" 2>/dev/null)" = /elsewhere/project ]; then
  echo "ok    and neither switches a device off nor touches the other's hold"
else
  echo "FAIL  and neither switches a device off nor touches the other's hold: the stand-ins"\
" were asked, or the hold changed — what they were asked follows"
  sed 's/^/      /' "$WORK/device.log"
  FAILURES=$((FAILURES + 1))
fi
printf 'E2E_WAIT=1\n' >>.review/land.conf
device "$repository" "$WORK/device-take.log" take android
check "a platform still held by another after E2E_WAIT is not taken" 75 \
  "android: busy — held by .review/runs/elsewhere of /elsewhere/project since " $? \
  "$WORK/device-take.log"
says "and taking it later is the loop's" "   The loop goes on: " "$WORK/device-take.log"
device "$repository" "$WORK/status.log" status
check "device.sh status names a run of another copy" 0 \
  "android: held by .review/runs/elsewhere of /elsewhere/project since " $? "$WORK/status.log"
mkdir -p "$holds/ios.lock" && cp "$holds/android.lock/holder" "$holds/ios.lock/holder" \
  && rm -rf "$holds/android.lock" || fail_setup "a hold of another copy on ios"
device "$repository" "$WORK/device-take.log" take ios android
check "a take that cannot hold every platform it names" 75 "ios: busy — held by " $? \
  "$WORK/device-take.log"
if [ ! -e "$holds/android.lock" ]; then
  echo "ok    holds none of them"
else
  echo "FAIL  holds none of them: $holds/android.lock is there"
  FAILURES=$((FAILURES + 1))
fi
kill "$holder_pid" 2>/dev/null
wait "$holder_pid" 2>/dev/null
rm -rf "$holds/ios.lock" "$holds/android.lock"
mkdir -p "$holds/android.lock" && \
  jq -n --argjson until "$(( $(date +%s) - 5 ))" \
    '{pid: 1, pid_started: "", root: "/elsewhere/project", who: "a check by hand",
      kind: "agent", since: ($until - 1800), until: $until}' >"$holds/android.lock/holder" \
  || fail_setup "a check's hold that ran out"
device "$repository" "$WORK/device-take.log" take android
check "a check's hold that ran out is taken over" 0 \
  "── android: the hold of a check by hand of /elsewhere/project ran out — taking over" $? \
  "$WORK/device-take.log"
device "$repository" "$WORK/device-release.log" release android
cp "$WORK/device.log" "$WORK/device.log.before"
device "$repository" "$WORK/device-off.log" off android android emulator-5554
check "off refuses where this copy does not hold the platform" 1 \
  "android is not held by this copy" $? "$WORK/device-off.log"
if cmp -s "$WORK/device.log" "$WORK/device.log.before"; then
  echo "ok    and switches nothing off"
else
  echo "FAIL  and switches nothing off: the stand-ins were asked — it follows"
  sed 's/^/      /' "$WORK/device.log"
  FAILURES=$((FAILURES + 1))
fi
DEVICE_LOCK_DIR="$WORK/a-file/devices" device "$repository" "$WORK/device-take.log" take android
check "a place where device.sh can make no hold is said" 1 \
  "android: the hold cannot be made at $WORK/a-file/devices/android.lock" $? \
  "$WORK/device-take.log"
says "and where the runs meet is the user's to say" \
  "   For the user, only they can: let the runs meet" "$WORK/device-take.log"
device "$repository" "$WORK/device-take.log" take android --minutes soon
check "a hold of no whole number of minutes is refused" 1 \
  "--minutes must be a whole number of minutes from 1, not 'soon'" $? "$WORK/device-take.log"
device "$repository" "$WORK/device-take.log" take app
check "device.sh holds android and ios alone" 1 "device.sh holds android and ios, not 'app'" $? \
  "$WORK/device-take.log"
printf 'E2E_LOCK=off\n' >>.review/land.conf
device "$repository" "$WORK/device-take.log" take android
check "with E2E_LOCK=off device.sh holds nothing" 0 \
  "E2E_LOCK=off in .review/land.conf: each copy has devices of its own" $? \
  "$WORK/device-take.log"
if [ ! -e "$holds/android.lock" ]; then
  echo "ok    and makes no hold"
else
  echo "FAIL  and makes no hold: $holds/android.lock is there"
  FAILURES=$((FAILURES + 1))
fi
device "$repository" "$WORK/device-off.log" off android android emulator-5560
check "and switches a device off with no hold" 0 "── android: switched off emulator-5560" $? \
  "$WORK/device-off.log"
rm -f "$WORK/device.log.before" "$WORK/reviewer-ran"
printf 'THRESHOLD=major\nLANDING=off\nASK_AFTER_RUNS=100\n' >.review/land.conf
sleep 300 &
holder_pid=$!
hold_by_another 600 "$holder_pid"
rm -rf "$copy/app"
mkdir -p "$copy/app/App.xcodeproj" && \
  printf 'SDKROOT = iphoneos;\nproductType = "com.apple.product-type.application";\n' \
  >"$copy/app/App.xcodeproj/project.pbxproj" || fail_setup "an iOS app in the second copy"
printf 'E2E_WAIT=5\n' >>"$copy/.review/land.conf"
held_review "$copy" "$WORK/run.log" --again
check "another platform does not wait" 0 "── e2e: pass on ios" $? "$WORK/run.log"
never_says "nor says that it waits" "waiting — held by" "$WORK/run.log"
kill "$holder_pid" 2>/dev/null
wait "$holder_pid" 2>/dev/null
rm -rf "$holds/android.lock" "$copy" app "$WORK/a-file"
rm -f "$WORK/reviewer-ran"
mkdir -p app/src/main app/App.xcodeproj
printf '<category android:name="android.intent.category.LAUNCHER"/>\n' \
  >app/src/main/AndroidManifest.xml
printf 'SDKROOT = iphoneos;\nproductType = "com.apple.product-type.application";\n' \
  >app/App.xcodeproj/project.pbxproj
E2E_ONLY=app \
  e2e_review "an Android app in the tree needs its tests run on Android" 1 \
  "android: the e2e run ran no test" .review/T-006.json
check "an iOS app in the tree needs its tests run on iOS" 1 "ios: the e2e run ran no test" \
  "$review_exit" "$WORK/run.log"
rm -rf app
E2E_TOUCH=src/x \
  e2e_review "an end-to-end run that changes the tree ends the run with an error" 1 \
  "the e2e run modified the working tree" .review/T-006.json
rm -f src/x
printf 'v1\n' >"src/Отчёт.kt"
E2E_TOUCH="src/Отчёт.kt" \
  e2e_review "an end-to-end run that changes a file with a non-ASCII name ends the run with an "\
"error" 1 "the e2e run modified the working tree" .review/T-006.json
rm -f "src/Отчёт.kt"
# The loop's and the owner's files are outside the fingerprint; the run changes them
# no more than the rest. A harness that rewrites the cases would choose its own tests.
for touched in qa/test-cases.md TASK_TRACKER.md REQUIREMENTS.md; do
  E2E_TOUCH="$touched" E2E_XML="$(xml starts)" \
    e2e_review "an end-to-end run that changes $touched ends the run with an error" 1 \
    "the e2e run modified the working tree" .review/T-006.json
done
cp "$WORK/test-cases.md" qa/test-cases.md
rm -f TASK_TRACKER.md REQUIREMENTS.md

# The platforms the tree ships, from its files.
mkdir -p "app/Диск.xcodeproj"
printf 'SDKROOT = iphoneos;\nproductType = "com.apple.product-type.application";\n' \
  >"app/Диск.xcodeproj/project.pbxproj"
E2E_ONLY=app \
  e2e_review "an iOS app whose project has a non-ASCII name needs its tests run on iOS" 1 \
  "ios: the e2e run ran no test" .review/T-006.json
rm -rf app
mkdir -p app/App.xcodeproj
printf 'SDKROOT = auto;\nSUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx";\n'\
'productType = "com.apple.product-type.application";\n' >app/App.xcodeproj/project.pbxproj
E2E_ONLY=app \
  e2e_review "a multiplatform Xcode app that runs on iOS needs its tests run on iOS" 1 \
  "ios: the e2e run ran no test" .review/T-006.json
rm -rf app
mkdir -p app/src/main
printf '<category android:name="android.intent.category.LEANBACK_LAUNCHER"/>\n' \
  >app/src/main/AndroidManifest.xml
E2E_ONLY=app \
  e2e_review "an Android TV app needs its tests run on Android" 1 \
  "android: the e2e run ran no test" .review/T-006.json
rm -rf app
mkdir -p third_party/pdfkit/sample/src/main
printf '<category android:name="android.intent.category.LAUNCHER"/>\n' \
  >third_party/pdfkit/sample/src/main/AndroidManifest.xml
e2e_review "the sample app of a vendored library ships no platform" 0 "── e2e: pass on app " \
  .review/T-006.json
rm -rf third_party

# Android and iOS together: each platform's report is its own, and a test a
# case names counts on each platform by itself.
mkdir -p app/src/main app/App.xcodeproj
printf '<category android:name="android.intent.category.LAUNCHER"/>\n' \
  >app/src/main/AndroidManifest.xml
printf 'SDKROOT = iphoneos;\nproductType = "com.apple.product-type.application";\n' \
  >app/App.xcodeproj/project.pbxproj
e2e_review "passing end-to-end tests on Android and iOS let the review go on" 0 \
  "── e2e: pass on android ios " .review/T-006.json
E2E_ONLY=android E2E_ALSO=../ios/r.xml \
  e2e_review "a report another platform's run left is not the platform's own" 1 \
  "ios: the e2e run ran no test" .review/T-006.json
E2E_XML="$(xml shows42 starts)" \
  e2e_review "the same report for two platforms is no harness" 1 \
  "ios: a report is the same file as one of android" .review/T-006.json
E2E_XML_ios="$(xml shows42=skipped starts)" \
  e2e_review "a named test skipped on one platform is red" 2 \
  "ios: named but did not pass: AnswerE2E.shows42" .review/T-006.json
E2E_XML_ios="$(xml starts)" \
  e2e_review "a named test missing on a platform that runs its class is red" 2 \
  "ios: named but did not run: AnswerE2E.shows42" .review/T-006.json
cp qa/test-cases.md "$WORK/test-cases.md"
printf -- '- **TC-003 Empty folder.** — e2e: `com.disk.FileListE2E.emptyFolder`, %s\n' \
  '`FileListE2E.testEmptyFolder`' >>qa/test-cases.md
E2E_XML_android='<testsuite hostname="android"><testcase classname="AnswerE2E" name="shows42"/>'\
'<testcase classname="AnswerE2E" name="starts"/>'\
'<testcase classname="com.disk.FileListE2E" name="emptyFolder"/></testsuite>' \
E2E_XML_ios='<testsuite hostname="ios"><testcase classname="AnswerE2E" name="shows42"/>'\
'<testcase classname="AnswerE2E" name="starts"/>'\
'<testcase classname="FileListE2E" name="testEmptyFolder"/></testsuite>' \
  e2e_review "each platform's own test of a case, in classes of one short name, passes" 0 \
  "── e2e: pass on android ios " .review/T-006.json
cp "$WORK/test-cases.md" qa/test-cases.md
rm -rf app

# Reading the JUnit XML.
E2E_XML="$(printf '<testsuite>\r\n<testcase\r\n classname="AnswerE2E" name="shows42">'\
'<failure/></testcase>\r\n<testcase classname="AnswerE2E" name="starts"/>\r\n</testsuite>')" \
  e2e_review "a failure in a report with CRLF line ends is red" 2 \
  "app: failed: AnswerE2E.shows42" .review/T-006.json
E2E_XML='<testsuite><!-- <testcase classname="AnswerE2E" name="shows42"/> -->'\
'<testcase classname="AnswerE2E" name="starts"/></testsuite>' \
  e2e_review "a testcase in a comment never ran" 2 "named but did not pass: AnswerE2E.shows42" \
  .review/T-006.json
E2E_XML='<testsuite><testcase classname="AnswerE2E" name="shows42"><system-out>'\
'<![CDATA[log: </testcase> <done>]]></system-out><failure/></testcase>'\
'<testcase classname="AnswerE2E" name="starts"/></testsuite>' \
  e2e_review "a failure after output that holds </testcase> is red" 2 \
  "app: failed: AnswerE2E.shows42" .review/T-006.json
cp qa/test-cases.md "$WORK/test-cases.md"
cat >>qa/test-cases.md <<'EOF'
- **TC-003 Spellings.** — e2e: `Spaces.eq`, `AnswerE2E.save & quit`, `SizeTests.size > 0`,
  `AnswerUITests.testShows42()`, `Param.shows42`
EOF
E2E_XML='<testsuite><testcase classname="AnswerE2E" name="shows42"/>'\
'<testcase classname="AnswerE2E" name="starts"/><testcase classname = "Spaces" name = "eq"/>'\
'<testcase classname="AnswerE2E" name="save &amp; quit"/>'\
'<testcase classname="SizeTests" name="size > 0"/>'\
'<testcase classname="AnswerUITests" name="testShows42()"/>'\
'<testcase classname="Param" name="shows42(int)[1]"/>'\
'<testcase classname="Param" name="shows42(int)[2]"/></testsuite>' \
  e2e_review "a report and marks spelled in other valid ways pass" 0 "── e2e: pass on app " \
  .review/T-006.json
cp "$WORK/test-cases.md" qa/test-cases.md
E2E_NAME=connected/debug/TEST-Pixel.XML \
  e2e_review "a report in a subfolder, named .XML, is read" 0 "── e2e: pass on app " \
  .review/T-006.json
E2E_XML='<testsuite timestamp="2026-01-01T00:00:00">'\
'<testcase classname="AnswerE2E" name="shows42"/>'\
'<testcase classname="AnswerE2E" name="starts"/></testsuite>' \
  e2e_review "a report older than the run is no harness" 1 "app: a report is older than this run" \
  .review/T-006.json
awk 'BEGIN {
  line = sprintf("%-100s", "I/TestRunner: <step> done"); gsub(/ /, "x", line)
  print "<testsuite><testcase classname=\"AnswerE2E\" name=\"starts\"/>"
  for (i = 1; i <= 500; i++) {
    print "<testcase classname=\"Bulk\" name=\"t" i "\"><system-out><![CDATA["
    for (j = 1; j <= 100; j++) print line
    print "]]></system-out></testcase>"
  }
  print "<testcase classname=\"AnswerE2E\" name=\"shows42\"><failure/></testcase></testsuite>" }' \
  >"$WORK/big.xml"
started=$SECONDS
E2E_REPORT="$WORK/big.xml" \
  e2e_review "a report with megabytes of output is read whole" 2 \
  "app: failed: AnswerE2E.shows42" .review/T-006.json
if [ $((SECONDS - started)) -le 20 ]; then
  echo "ok    a report of $(wc -c <"$WORK/big.xml" | tr -d ' ') bytes is read in "\
"$((SECONDS - started)) s"
else
  echo "FAIL  a report of $(wc -c <"$WORK/big.xml" | tr -d ' ') bytes took "\
"$((SECONDS - started)) s"
  FAILURES=$((FAILURES + 1))
fi

# The marks of the cases.
printf '# Test cases\n\n1. **TC-001 Answer.** It shows 42. — e2e: `AnswerE2E.shows42`\n'\
'2. **TC-002 Start.** — e2e: `AnswerE2E.starts`\n' >qa/test-cases.md
E2E_XML="$(xml shows42=skipped starts)" \
  e2e_review "a case in a numbered list is a case" 2 "named but did not pass: AnswerE2E.shows42" \
  .review/T-006.json
printf '# Test cases\n\n- **TC-001 Answer.** It shows 42. — e2e: AnswerE2E.shows42\n'\
'- **TC-002 Start.** — e2e: AnswerE2E.starts\n' >qa/test-cases.md
E2E_XML="$(xml shows42=skipped starts)" \
  e2e_review "a mark without backticks names its test" 2 \
  "named but did not pass: AnswerE2E.shows42" .review/T-006.json
printf '# Test cases\n\n- **TC-001 Answer.** It shows 42. — e2e: `AnswerE2E.shows42` and %s\n' \
  '`AnswerE2E.starts`' >qa/test-cases.md
E2E_XML="$(xml shows42 starts=skipped)" \
  e2e_review "every test of a mark joined by and is named" 2 \
  "named but did not pass: AnswerE2E.starts" .review/T-006.json
printf '# Test cases\n\n- **TC-001 Answer.** It shows 42. — e2e: `AnswerE2E.\n  shows42`\n' \
  >qa/test-cases.md
e2e_review "a mark wrapped inside its backticks names its test" 0 "── e2e: pass on app " \
  .review/T-006.json
printf '# Test cases\n\nNo case yet.\n' >qa/test-cases.md
e2e_review "before the first case, a test that ran is a harness" 0 "── e2e: pass on app " \
  .review/T-006.json
cp "$WORK/test-cases.md" qa/test-cases.md

# Skip tags: one counts only where it sits on the test, and the test is still
# in the run to be skipped.
printf '// see "T-999: TC-001"\n' >src/notes.kt
E2E_XML="$(xml starts)" \
  e2e_review "a skip tag that sits on no test skips nothing" 2 \
  "named but did not pass: AnswerE2E.shows42" .review/T-006.json
rm src/notes.kt
printf 'class AnswerE2E { @Ignore("T-017: TC-001") fun shows42() {} }\n' >src/AnswerE2E.kt
E2E_XML="$(xml starts)" \
  e2e_review "a test skipped for a task is still in the run" 2 \
  "named but did not pass: AnswerE2E.shows42" .review/T-006.json
printf 'class AnswerE2E { @Ignore("T-017:TC-001 Android shows filesDir") fun shows42() {} }\n' \
  >src/AnswerE2E.kt
E2E_XML="$(xml shows42=skipped starts)" \
  e2e_review "a skip tag with more words and no space after the colon counts" 0 \
  "── e2e: pass on app " .review/T-006.json
printf "def shows42(): pytest.skip(reason='T-016+T-004: TC-001')\n" >src/AnswerE2E.kt
E2E_XML="$(xml shows42=skipped starts)" \
  e2e_review "a skip tag in single quotes, for a task of two ids, counts" 0 \
  "── e2e: pass on app " .review/T-006.json
rm src/AnswerE2E.kt
mkdir -p CodingStandards/templates/review
cp -R "$LIB_DIR" CodingStandards/templates/review/lib
(. CodingStandards/templates/review/lib/common.sh && skip_tags) >"$WORK/tags.log" 2>&1
tags_exit=$?
if [ "$tags_exit" -eq 1 ] && [ ! -s "$WORK/tags.log" ]; then
  echo "ok    a plain copy of the standards in the project holds no skip tag"
else
  echo "FAIL  a plain copy of the standards in the project holds skip tags (exit $tags_exit):"
  sed 's/^/      /' "$WORK/tags.log"
  FAILURES=$((FAILURES + 1))
fi
rm -rf CodingStandards

# Landing. The work marks a case with the test that reproduces a failure of /qa;
# the cases are one of the loop's own files, so no task names them in its scope.
printf '{"id": "T-007", "title": "Answer 42", "category": "bugfix", "scope": ["src/*"], '\
'"exit_criteria": []}' >.review/T-007.json
mkdir -p .review/runs/0-qa-T-007
printf '{"task": "T-007", "failures": []}' >.review/runs/0-qa-T-007/qa.json
e2e_review "passing end-to-end tests let the review go on" 0 "CLEAN — gates green" \
  .review/T-007.json
run_of_t007="$last_run"
mkdir -p app/src/main
printf '<category android:name="android.intent.category.LAUNCHER"/>\n' \
  >app/src/main/AndroidManifest.xml
e2e_check "a platform the newest end-to-end run never ran on holds /qa back" 2 \
  "never ran on: android"
rm -rf app
e2e_land "a run with passing end-to-end tests lands" 0 "For the user to commit" \
  .review/T-007.json "$run_of_t007"
# The records of the loop land with the task only where the project says so.
cp .review/land.conf "$WORK/land.conf.saved"
printf '# Plan\n' >PLAN.md
mkdir -p .review/decisions
printf '{"task": "T-007"}\n' >.review/decisions/tasks.jsonl
printf 'WITH_RECORDS=yes\n' >>.review/land.conf
e2e_land "with WITH_RECORDS=yes the plan lands with the task" 0 "  PLAN.md" \
  .review/T-007.json "$run_of_t007"
e2e_land "with WITH_RECORDS=yes the decision logs land with the task" 0 \
  "  .review/decisions/tasks.jsonl" .review/T-007.json "$run_of_t007"
e2e_review "a review with the plan landing beside it goes on" 0 "CLEAN — gates green" \
  .review/T-007.json
check "the reviewer is told the plan lands with the task" 0 "landing with this task" 0 \
  "$last_run/reviewer-prompt.md"
printf 'WITH_RECORDS=maybe\n' >>.review/land.conf
e2e_land "a WITH_RECORDS that is neither yes nor no refuses" 3 "must be yes or no" \
  .review/T-007.json "$run_of_t007"
cp "$WORK/land.conf.saved" .review/land.conf
rm PLAN.md .review/decisions/tasks.jsonl
printf -- '- **TC-003 Never.** It never runs. — e2e: `AnswerE2E.doesNotExist`\n' \
  >>qa/test-cases.md
e2e_land "a case marked after the run with a test the run never saw refuses" 3 \
  "was not checked against: TC-003 AnswerE2E.doesNotExist" .review/T-007.json "$run_of_t007"
sed 's/`AnswerE2E.starts`/`AnswerE2E.shows42`/' "$WORK/test-cases.md" >qa/test-cases.md
e2e_land "a test moved to another case after the run refuses" 3 \
  "was not checked against: TC-002 AnswerE2E.shows42" .review/T-007.json "$run_of_t007"
grep -v -e 'TC-002' -e 'AnswerE2E.starts' "$WORK/test-cases.md" >qa/test-cases.md
e2e_land "a case unmarked after the run lands: the run saw more than it needs" 0 \
  "For the user to commit" .review/T-007.json "$run_of_t007"
cp "$WORK/test-cases.md" qa/test-cases.md
mv "$run_of_t007/e2e.json" "$WORK/e2e.json"
e2e_land "a run without end-to-end tests is not a completed run" 3 "condition 1: " \
  .review/T-007.json "$run_of_t007"
mv "$WORK/e2e.json" "$run_of_t007/e2e.json"
printf '# changed\n' >>.review/e2e.sh
e2e_land "a harness changed after the run refuses" 3 "the tree changed after this review ran" \
  .review/T-007.json "$run_of_t007"
e2e_review "a run on a changed harness goes on" 0 "CLEAN — gates green" .review/T-007.json
e2e_land "a harness changed before the run lands with the task" 0 "  .review/e2e.sh" \
  .review/T-007.json "$last_run"
cp "$last_run/e2e.json" "$WORK/e2e.ran.json"
jq '.harness = "0000 .review/e2e.sh"' "$WORK/e2e.ran.json" >"$last_run/e2e.json"
e2e_land "a harness that is not the one the run recorded refuses" 3 "is not as it ran" \
  .review/T-007.json "$last_run"
cp "$WORK/e2e.ran.json" "$last_run/e2e.json"
git checkout -q -- .review/e2e.sh
e2e_land "a run on a harness changed back since refuses" 3 "the tree changed after this review ran" \
  .review/T-007.json "$last_run"
mv .review/runs/0-qa-T-007 "$WORK/0-qa-T-007"
e2e_land "a task /qa never checked refuses" 3 "no /qa record (qa.json) for T-007" \
  .review/T-007.json "$run_of_t007"
mv "$WORK/0-qa-T-007" .review/runs/0-qa-T-007
printf '{"task": "T-007", "failures": [{"case": "the answer is 41"}]}' \
  >.review/runs/0-qa-T-007/qa.json
e2e_land "a /qa failure with no case refuses" 3 "not {task, failures: [{case: TC-nnn}]}" \
  .review/T-007.json "$run_of_t007"
printf '{"task": "T-007", "failures": [{"case": "TC-001"}]}' >.review/runs/0-qa-T-007/qa.json
e2e_land "a /qa failure whose test never failed refuses" 3 "seen red, then green: TC-001" \
  .review/T-007.json "$run_of_t007"
# The case says what is to be seen, so the refusal is the loop's: its last line says
# whose turn it is, and nothing in it sends anyone to the user.
e2e_land "a /qa failure is the loop's to fix" 3 "   The loop goes on: fix it" \
  .review/T-007.json "$run_of_t007"
if grep -qF "the user" "$WORK/land.log"; then
  echo "FAIL  the refusal of a /qa failure names the user — log follows"
  sed 's/^/      /' "$WORK/land.log"
  FAILURES=$((FAILURES + 1))
else
  echo "ok    its refusal names no user"
fi
( . "$LIB_DIR/common.sh"; turn user:anything x ) >"$WORK/turn.log" 2>&1
check "a kind that is not the user's is refused" 1 "is neither loop nor user:" $? "$WORK/turn.log"
printf '[{"finding_id": "TC-001", "resolution": "accepted-as-is", "by": "human"}]' \
  >"$run_of_t007/escalations-answered.json"
e2e_land "a /qa failure the user answered lands" 0 "For the user to commit" \
  .review/T-007.json "$run_of_t007"
rm "$run_of_t007/escalations-answered.json"
sed 's/`AnswerE2E.shows42`/`AnswerE2E.shows42`, `AnswerE2E.shows43`/' "$WORK/test-cases.md" \
  >qa/test-cases.md
E2E_XML="$(xml shows42 starts shows43=failed)" \
  e2e_review "the test of a /qa failure fails before the fix" 2 \
  "app: failed: AnswerE2E.shows43" .review/T-007.json
E2E_XML="$(xml shows42 starts shows43)" \
  e2e_review "the test of a /qa failure passes after the fix" 0 "CLEAN — gates green" \
  .review/T-007.json
e2e_land "a /qa failure seen red, then green lands" 0 "For the user to commit" \
  .review/T-007.json "$last_run"
cp "$WORK/test-cases.md" qa/test-cases.md
printf '{"task": "T-007", "failures": []}' >.review/runs/0-qa-T-007/qa.json

printf 'class AnswerE2E { @Ignore("T-007: TC-001") fun shows42() {} }\n' >src/AnswerE2E.kt
E2E_XML="$(xml shows42=skipped starts)" \
  e2e_review "a test skipped for the task its defect belongs to is not red" 0 \
  "CLEAN — gates green" .review/T-007.json
e2e_land "a test still skipped for the task refuses its landing" 3 \
  "the end-to-end test of TC-001 is still skipped for T-007" .review/T-007.json "$last_run"
printf '{"task": "T-004", "failures": [{"case": "TC-001"}]}' >.review/runs/0-qa-T-004/qa.json
E2E_XML="$(xml shows42=skipped starts)" \
  e2e_review "a deferred test lets the review of another task go on" 0 "CLEAN — gates green" \
  .review/T-004.json
e2e_land "a deferred /qa failure never seen red refuses" 3 "seen red, then green: TC-001" \
  .review/T-004.json "$last_run"
E2E_XML="$(xml shows42=failed starts)" \
  e2e_review "the test of a deferred /qa failure fails" 2 "app: failed: AnswerE2E.shows42" \
  .review/T-004.json
E2E_XML="$(xml shows42=skipped starts)" \
  e2e_review "the test of a deferred /qa failure is skipped" 0 "CLEAN — gates green" \
  .review/T-004.json
e2e_land "a /qa failure seen red and skipped for its own task lands" 0 \
  "For the user to commit" .review/T-004.json "$last_run"
rm src/AnswerE2E.kt
printf '{"task": "T-004", "failures": []}' >.review/runs/0-qa-T-004/qa.json

# More landings, each on a task of its own, so that no earlier run of another
# task counts for it. new_task <id> [failures] writes the task and /qa's record.
new_task() {
  printf '{"id": "%s", "title": "Answer 42", "category": "bugfix", "scope": ["src/*"], '\
'"exit_criteria": []}' "$1" >".review/$1.json"
  mkdir -p ".review/runs/0-qa-$1"
  printf '{"task": "%s", "failures": %s}' "$1" "${2:-[]}" >".review/runs/0-qa-$1/qa.json"
}
new_task T-008
cp .review/e2e.sh "$WORK/e2e.committed"
cat >.review/e2e.sh <<EOF
#!/usr/bin/env bash
mkdir -p "\$2"
printf '%s' '$(xml shows42 starts)' >"\$2/r.xml"
cp "$WORK/e2e.committed" "\$0.new" && mv "\$0.new" "\$0"
EOF
e2e_review "a harness that puts the committed one back while it runs ends the run with an "\
"error" 1 "the harness changed while it ran" .review/T-008.json
git checkout -q -- .review/e2e.sh
printf '#!/usr/bin/env bash\nexit 0\n' >.review/e2e-app.sh
chmod +x .review/e2e-app.sh
e2e_review "a run beside an uncommitted .review/e2e-* goes on" 0 "CLEAN — gates green" \
  .review/T-008.json
e2e_land "an uncommitted .review/e2e-* that ran lands with the task" 0 "  .review/e2e-app.sh" \
  .review/T-008.json "$last_run"
rm .review/e2e-app.sh

# A task of the harness alone: no file of its scope changed.
new_task T-090
printf 'fun answer() = 41\n' >src/answer.kt
printf '# the harness alone\n' >>.review/e2e.sh
e2e_review "a change of the harness alone is reviewed" 0 "CLEAN — gates green" .review/T-090.json
e2e_land "a change of the harness alone lands as its own task" 0 "  .review/e2e.sh" \
  .review/T-090.json "$last_run"
git checkout -q -- .review/e2e.sh
printf 'fun answer() = 42\n' >src/answer.kt

new_task T-009 '[{"case": "TC-001"}]'
e2e_review "a run with a /qa failure recorded goes on" 0 "CLEAN — gates green" .review/T-009.json
printf '[{"finding_id": "TC-001", "resolution": "accepted-as-is", "by": "maintainer"}]' \
  >"$last_run/escalations-answered.json"
e2e_land "an answer to a /qa failure that is not the user's refuses" 3 \
  "seen red, then green: TC-001" .review/T-009.json "$last_run"
printf '[{"finding_id": "TC-001", "resolution": "fixed", "by": "human"}]' \
  >"$last_run/escalations-answered.json"
e2e_land "an answer that a /qa failure is fixed proves nothing" 3 \
  "seen red, then green: TC-001" .review/T-009.json "$last_run"
rm "$last_run/escalations-answered.json"

new_task T-010
E2E_XML="$(xml shows42=failed starts)" \
  e2e_review "a test of a case fails before /qa has checked the task" 2 \
  "app: failed: AnswerE2E.shows42" .review/T-010.json
e2e_review "and passes after its fix" 0 "CLEAN — gates green" .review/T-010.json
printf '{"task": "T-010", "failures": [{"case": "TC-001"}]}' >.review/runs/0-qa-T-010/qa.json
e2e_land "a test seen red only before /qa recorded the failure proves nothing" 3 \
  "seen red, then green: TC-001" .review/T-010.json "$last_run"

new_task T-011 '[{"case": "TC-001"}]'
e2e_review "a run after /qa recorded a failure goes on" 0 "CLEAN — gates green" \
  .review/T-011.json
printf '{"task": "T-011", "failures": []}' >.review/runs/0-qa-T-011/qa.json
e2e_land "a /qa failure stays recorded when its qa.json is rewritten" 3 \
  "seen red, then green: TC-001" .review/T-011.json "$last_run"

new_task T-012
printf 'fun report() = 1\n' >"src/Отчёт.kt"
e2e_review "a run with a new file of a non-ASCII name goes on" 0 "CLEAN — gates green" \
  .review/T-012.json
e2e_land "a file with a non-ASCII name inside the scope lands" 0 "src/Отчёт.kt" \
  .review/T-012.json "$last_run"
rm "src/Отчёт.kt"

# The record of /qa. Beside its counts it lists each item with its verdict, and apart
# from them what the app does that nothing written describes. A record whose items do
# not hold refuses like one that cannot be read, and the line before the refusal says
# what does not hold. qa_record <task> <name> <json> writes one more record of the task.
qa_record() {
  mkdir -p ".review/runs/0-qa-$1-$2"
  jq -n --arg task "$1" --argjson record "$3" '$record + {task: $task, time: now}' \
    >".review/runs/0-qa-$1-$2/qa.json"
}
record_refuses() {
  local name="$1" fault="$2" record="$3"
  qa_record T-020 items "$record"
  e2e_land "$name" 3 "its items do not hold" .review/T-020.json "$last_run"
  if grep -qF -- ".review/runs/0-qa-T-020-items/qa.json: $fault" "$WORK/land.log"; then
    echo "ok    and says what: $fault"
  else
    echo "FAIL  the refusal does not say «$fault» — log follows"
    sed 's/^/      /' "$WORK/land.log"
    FAILURES=$((FAILURES + 1))
  fi
}
new_task T-020
e2e_review "a run of a task whose /qa lists its items goes on" 0 "CLEAN — gates green" \
  .review/T-020.json
two_passes='{"id": "TC-001", "verdict": "pass"}, {"id": "the build", "verdict": "pass"}'
record_refuses "items that do not match the counts refuse" \
  "2 item(s) say pass and counts.pass is 3" \
  "{\"counts\": {\"pass\": 3}, \"failures\": [], \"items\": [$two_passes]}"
record_refuses "an item with a verdict and no reason refuses" \
  "item TC-001 says unproven and gives no reason" \
  '{"counts": {"unproven": 1}, "failures": [],
    "items": [{"id": "TC-001", "verdict": "unproven"}]}'
record_refuses "a behaviour nothing written describes that names a case refuses" \
  "a behaviour nothing written describes names a case (TC-001 shows 41): a case is written" \
  "{\"counts\": {\"pass\": 2}, \"failures\": [], \"items\": [$two_passes],
    \"behaviour_without_requirement\": [{\"what\": \"TC-001 shows 41\", \"where\": \"Answer\"}]}"
record_refuses "a behaviour nothing written describes whose place names a case refuses" \
  "a behaviour nothing written describes names a case (TC-001, the answer): a case is written" \
  "{\"counts\": {\"pass\": 2}, \"failures\": [], \"items\": [$two_passes],
    \"behaviour_without_requirement\": [{\"what\": \"the answer is dark on a dark ground\",
      \"where\": \"TC-001, the answer\"}]}"
says "the record is told the two ways to hold" \
  "so what fails in it is a failure: list the case in failures, or leave its id out of what and where" \
  "$WORK/land.log"
record_refuses "counts that are no numbers refuse" \
  '1 item(s) say pass and counts.pass is "1", which is no number' \
  '{"counts": {"pass": "1"}, "failures": [], "items": [{"id": "TC-001", "verdict": "pass"}]}'
record_refuses "a verdict that is none of the five refuses" \
  "items is not a list of {id, verdict}, each verdict one of pass, fail, unproven, not_checked, "\
"after_merge" \
  '{"counts": {"pass": 1}, "failures": [], "items": [{"id": "TC-001", "verdict": "fine"}]}'
record_refuses "items that are no list refuse" "items is not a list of {id, verdict}" \
  '{"counts": {"pass": 1}, "failures": [], "items": {"TC-001": "pass"}}'
record_refuses "an item put off until after the merge with no check to make refuses" \
  "item the build of main is put off until after the merge and does not say how it is checked "\
"then (check)" \
  '{"counts": {"after_merge": 1}, "failures": [], "items": [{"id": "the build of main",
    "verdict": "after_merge", "reason": "the workflow runs only on a push to the base branch"}]}'
record_refuses "an item put off until after the merge that names a case refuses" \
  "item TC-001 on the base branch is put off until after the merge and names a case: a case is "\
"what is seen in the app, and is checked on the pull request" \
  '{"counts": {"after_merge": 1}, "failures": [], "items": [{"id": "TC-001 on the base branch",
    "verdict": "after_merge", "reason": "the workflow runs only on a push to the base branch",
    "check": "the run of the build workflow on main, at the merge commit"}]}'
record_refuses "items with no counts beside them refuse" \
  "2 item(s) say pass and counts.pass is 0" "{\"failures\": [], \"items\": [$two_passes]}"
record_refuses "a failing item under no case refuses" \
  "item the build says fail and failures does not list its case: /qa writes the case of every "\
"failure and lists it in failures" \
  '{"counts": {"pass": 1, "fail": 1}, "failures": [],
    "items": [{"id": "TC-001", "verdict": "pass"},
              {"id": "the build", "verdict": "fail",
               "reason": "the release build stops at the linker"}]}'
record_refuses "a failing item of a case the failures do not list refuses" \
  "item TC-002 on iOS says fail and failures does not list its case" \
  '{"counts": {"fail": 2}, "failures": [{"case": "TC-001"}],
    "items": [{"id": "TC-001", "verdict": "fail", "reason": "it shows 41"},
              {"id": "TC-002 on iOS", "verdict": "fail", "reason": "it opens with an error"}]}'
record_refuses "a behaviour nothing written describes with no place refuses" \
  "behaviour_without_requirement is not a list of {what, where}" \
  "{\"counts\": {\"pass\": 2}, \"failures\": [], \"items\": [$two_passes],
    \"behaviour_without_requirement\": [{\"what\": \"a double tap opens a shelf twice\"}]}"
qa_record T-020 items "{\"counts\": {\"pass\": 2}, \"failures\": [], \"items\": [$two_passes]}"
e2e_land "a record that holds lands" 0 "For the user to commit" .review/T-020.json "$last_run"
qa_record T-020 items "{\"counts\": {\"pass\": 2, \"not_checked\": 1}, \"failures\": [],
  \"items\": [$two_passes, {\"id\": \"TC-001 on iOS\", \"verdict\": \"not_checked\",
    \"reason\": \"the simulator did not boot\"}],
  \"behaviour_without_requirement\": [{\"what\": \"a double tap on a shelf opens it twice\",
    \"where\": \"Shelves\"}]}"
e2e_land "what nothing written describes, recorded apart, holds no landing" 0 \
  "For the user to commit" .review/T-020.json "$last_run"
rm -rf .review/runs/0-qa-T-020-items

# What /qa left, and whose it is. After every /qa, at every level, pr-post.sh qa <qa-dir>
# checks the record and prints what each thing /qa left needs next, with a last line that
# says whose turn it is. A failing case says what is to be seen, so it is the loop's to
# fix, however often /qa was red; the same case failing on three works, each after a fix,
# is the user's, and so is what nothing written describes: there, right after /qa, the
# question is said and asked, and a landing names it and does not ask it again. Below the
# pull request levels it posts nothing and says where the report stays.
qa_says() {
  local name="$1" expected_exit="$2" expected_line="$3" qa_dir="$4"
  "$LIB_DIR/pr-post.sh" qa "$qa_dir" >"$WORK/post.log" 2>&1
  check "$name" "$expected_exit" "$expected_line" $? "$WORK/post.log"
}
qa_record T-021 clean '{"failures": []}'
qa_says "below the pull request levels pr-post.sh qa posts nothing and says so" 0 \
  "LANDING=off opens no pull request: the report stays in" .review/runs/0-qa-T-021-clean
says "a /qa that left nothing says so" "   nothing: every item passed"
never_says "and gives nobody a turn" "The loop goes on"
mkdir -p .review/runs/0-qa-T-021-empty
qa_says "a folder with no record of /qa is no /qa" 1 "has no qa.json" \
  .review/runs/0-qa-T-021-empty
rmdir .review/runs/0-qa-T-021-empty

qa_record T-022 first '{"failures": [{"case": "TC-001"}], "work": "w1"}'
qa_says "a failing case is the loop's to fix: what should be is written" 0 \
  "   TC-001 failed. What should be is written (qa/test-cases.md:5):" \
  .review/runs/0-qa-T-022-first
says "it quotes the case" '      "**TC-001 Answer.** Open the app: it shows 42."'
says "it names the end-to-end test of the case" "      its end-to-end test: AnswerE2E.shows42"
says "it says the loop goes on" "   The loop goes on: fix TC-001 — it is no question: see its test fail"
never_says "it names no user" "For the user"
never_says "a case that failed once has no fix before it" "it failed in"
qa_record T-022 second '{"failures": [{"case": "TC-001"}], "work": "w2"}'
qa_says "a second failing /qa of the same case is still the loop's" 0 \
  "   The loop goes on: fix TC-001 — it is no question" .review/runs/0-qa-T-022-second
says "it says in which /qa the case failed" \
  "      it failed in 2 /qa of this task, each on other work: 0-qa-T-022-first, 0-qa-T-022-second"
says "and sends the loop to why the fix before did not hold" \
  "; it failed after a fix before: find why that fix did not hold first"
never_says "a second failing /qa names no user" "For the user"

qa_record T-023 first '{"failures": [{"case": "TC-001"}], "work": "w1"}'
qa_record T-023 second '{"failures": [{"case": "TC-002"}], "work": "w2"}'
qa_record T-023 third '{"failures": [{"case": "TC-001"}], "work": "w3"}'
qa_says "a third failing /qa of other cases is still the loop's" 0 \
  "   The loop goes on: fix TC-001 — it is no question" .review/runs/0-qa-T-023-third
says "its case failed in two of them" "      it failed in 2 /qa of this task"
never_says "a third failing /qa of other cases names no user" "For the user"

for work in w1 w2 w3; do
  qa_record T-024 "$work" "{\"failures\": [{\"case\": \"TC-002\"}], \"work\": \"$work\"}"
done
qa_says "the same case failing in three /qa, each on other work, is the user's" 0 \
  "   For the user, the work does not converge: TC-002 failed again after each of 2 fixes" \
  .review/runs/0-qa-T-024-w3
says "it says what the user decides" \
  "whether to go on trying, to stop the task here, or to change what the case expects"
says "it lists the three /qa" \
  "it failed in 3 /qa of this task, each on other work: 0-qa-T-024-w1, 0-qa-T-024-w2, 0-qa-T-024-w3"
says "and how the review runs once they decided to go on" \
  "; when they decide to go on, review.sh runs once more with --past-limit --user-decided"
never_says "nothing sends the loop on with that case" "The loop goes on"
for name in first second third; do
  qa_record T-025 "$name" '{"failures": [{"case": "TC-002"}], "work": "w1"}'
done
qa_says "on unchanged work the same case is no circle" 0 \
  "   The loop goes on: fix TC-002 — it is no question" .review/runs/0-qa-T-025-third
never_says "on unchanged work nothing is the user's" "For the user"
never_says "and no fix is counted" "it failed in"

# A record that does not say which work /qa checked is not known to be of other work: no fix
# is counted from it, and no circle is read from it. Beside such records the works that are
# known count as they are.
for name in first second third; do
  qa_record T-040 "$name" '{"failures": [{"case": "TC-002"}]}'
done
qa_says "three /qa that do not say which work they checked are no circle" 0 \
  "   The loop goes on: fix TC-002 — it is no question" .review/runs/0-qa-T-040-third
never_says "nothing of them is the user's" "For the user"
never_says "and no fix is counted between them" "it failed in"
qa_record T-040 fourth '{"failures": [{"case": "TC-002"}], "work": "w1"}'
qa_record T-040 fifth '{"failures": [{"case": "TC-002"}], "work": "w2"}'
qa_says "beside them two works that are known count as two" 0 \
  "      it failed in 2 /qa of this task, each on other work: 0-qa-T-040-fourth, 0-qa-T-040-fifth" \
  .review/runs/0-qa-T-040-fifth
never_says "and two are no circle" "For the user"
qa_record T-040 sixth '{"failures": [{"case": "TC-002"}], "work": "w3"}'
qa_says "a third work that is known is the circle" 0 \
  "   For the user, the work does not converge: TC-002 failed again after each of 2 fixes" \
  .review/runs/0-qa-T-040-sixth
double_tap='"behaviour_without_requirement": [{"what": "a double tap on a shelf opens it twice",
  "where": "Shelves"}]'
qa_record T-026 asks "{\"failures\": [], $double_tap}"
qa_says "what nothing written describes is the user's" 0 \
  "   For the user, what should be: a double tap on a shelf opens it twice (Shelves) — /qa saw it" \
  .review/runs/0-qa-T-026-asks
says "the question is asked once, and holds nothing" \
  "ask it once, in their words; the task does not wait for the answer"
says "the task waits for the answer only where one of its own criteria does" \
  "the task does not wait for the answer unless one of its own criteria does"
never_says "a question is not a thing that passed" "nothing: every item passed"

qa_record T-027 items "{\"counts\": {\"pass\": 3}, \"failures\": [], \"items\": [$two_passes]}"
qa_says "a record that does not hold says what" 1 \
  "qa.json does not hold: 2 item(s) say pass and counts.pass is 3" .review/runs/0-qa-T-027-items
never_says "and nothing is said of what it left" "what /qa left"
rm -rf .review/runs/0-qa-T-027-items

printf -- '- **TC-003 Launch.** Start the app: the launch screen shows its name. — manual\n' \
  >>qa/test-cases.md
qa_record T-028 launch '{"failures": [{"case": "TC-003"}]}'
qa_says "a case with no test is told to get one" 0 \
  "      no end-to-end test is marked for it" .review/runs/0-qa-T-028-launch
says "its words are quoted without the mark" \
  '      "**TC-003 Launch.** Start the app: the launch screen shows its name."'
says "the loop writes the test and marks the case" \
  "   The loop goes on: fix TC-003 — it is no question: write its end-to-end test and mark the case (e2e: \`<test>\`)"
cp "$WORK/test-cases.md" qa/test-cases.md
qa_says "a failure whose case is not written goes back to /qa first" 0 \
  "   TC-003 failed, and qa/test-cases.md has no TC-003" .review/runs/0-qa-T-028-launch
says "the loop has /qa write the case, then fixes" \
  "   The loop goes on: have /qa write the case of TC-003, then fix it"

qa_record T-029 open '{"counts": {"pass": 1, "unproven": 1, "not_checked": 2}, "failures": [],
  "items": [{"id": "TC-001", "verdict": "pass"},
            {"id": "TC-002", "verdict": "unproven", "reason": "the frames do not show the start"},
            {"id": "TC-001 on iOS", "verdict": "not_checked", "reason": "the simulator did not boot"},
            {"id": "TC-002 on iOS", "verdict": "not_checked", "reason": "the simulator did not boot"}]}'
qa_says "what /qa left unproven is listed with its reason" 0 \
  "   1 unproven: TC-002 (the frames do not show the start)" .review/runs/0-qa-T-029-open
says "an unproven item is the loop's" \
  "   The loop goes on: an unproven item goes back to the work, which makes it provable"
says "what /qa could not check is listed with its reason" \
  "   2 not checked: TC-001 on iOS (the simulator did not boot); TC-002 on iOS (the simulator did not boot)"
says "an item not checked is the loop's" \
  "   The loop goes on: restore what failed — a tool, a device — and run /qa again"
never_says "neither is the user's" "For the user"
qa_record T-029 counts '{"counts": {"pass": 1, "unproven": 2, "not_checked": 0}, "failures": []}'
qa_says "a record with counts alone says how many" 0 "   2 unproven" \
  .review/runs/0-qa-T-029-counts
never_says "and lists no count that is zero" "not checked"
qa_record T-029 build '{"counts": {"pass": 1, "fail": 1}, "failures": [],
  "items": [{"id": "TC-001", "verdict": "pass"},
            {"id": "the build", "verdict": "fail", "reason": "the release build stops at the linker"}]}'
qa_says "a failing item under no case does not hold, and pr-post.sh qa says what" 1 \
  "qa.json does not hold: item the build says fail and failures does not list its case" \
  .review/runs/0-qa-T-029-build
rm -rf .review/runs/0-qa-T-029-build
qa_record T-029 platform '{"counts": {"pass": 1, "fail": 1}, "failures": [{"case": "TC-001"}],
  "items": [{"id": "TC-001 on Android", "verdict": "pass"},
            {"id": "TC-001 on iOS", "verdict": "fail", "reason": "it shows 41"}]}'
qa_says "a failing item of a case the failures list holds" 0 \
  "   TC-001 failed. What should be is written" .review/runs/0-qa-T-029-platform
# An item is of a case when its id is the case id, or goes on after it with a character that
# is no letter, digit or dash: a blank, a colon, a bracket. An id that goes on with a digit
# or a dash names another case.
qa_record T-029 colon '{"counts": {"pass": 1, "fail": 1}, "failures": [{"case": "TC-002"}],
  "items": [{"id": "TC-001", "verdict": "pass"},
            {"id": "TC-002: the start", "verdict": "fail", "reason": "it opens with an error"}]}'
qa_says "a failing item whose id is its case and a colon is of that case" 0 \
  "   TC-002 failed. What should be is written" .review/runs/0-qa-T-029-colon
qa_record T-029 longer '{"counts": {"fail": 2}, "failures": [{"case": "TC-002"}],
  "items": [{"id": "TC-002 (the start)", "verdict": "fail", "reason": "it opens with an error"},
            {"id": "TC-0021 on iOS", "verdict": "fail", "reason": "it shows no list"}]}'
qa_says "an id that goes on with a digit is of another case" 1 \
  "qa.json does not hold: item TC-0021 on iOS says fail and failures does not list its case" \
  .review/runs/0-qa-T-029-longer
qa_record T-029 longer '{"counts": {"fail": 1}, "failures": [{"case": "TC-002"}],
  "items": [{"id": "TC-002-b", "verdict": "fail", "reason": "it opens with an error"}]}'
qa_says "and so is an id that goes on with a dash" 1 \
  "qa.json does not hold: item TC-002-b says fail and failures does not list its case" \
  .review/runs/0-qa-T-029-longer
rm -rf .review/runs/0-qa-T-029-longer
qa_record T-029 count '{"counts": {"pass": 1, "fail": 2}, "failures": []}'
qa_says "failures counted with no case at all are said too" 0 \
  "   2 failed with no case among the failures" .review/runs/0-qa-T-029-count
says "the loop has /qa write its case" \
  "   The loop goes on: have /qa write the case of each, then fix it"
never_says "a failure is not a thing that passed" "nothing: every item passed"
qa_record T-029 platforms '{"counts": {"pass": 1, "fail": 2}, "failures": [{"case": "TC-001"}]}'
qa_says "a case that failed on two platforms is one failure with its case" 0 \
  "   TC-001 failed. What should be is written" .review/runs/0-qa-T-029-platforms
never_says "and no failure is said to have no case" "with no case among the failures"
qa_record T-029 later '{"counts": {"pass": 1, "after_merge": 1}, "failures": [],
  "items": [{"id": "TC-001", "verdict": "pass"},
            {"id": "the build of main", "verdict": "after_merge",
             "reason": "the workflow runs only on a push to the base branch",
             "check": "the run of the build workflow on main, at the merge commit"}]}'
qa_says "below the pull request levels pr-post.sh qa lists what is put off" 0 \
  "   1 to check after the merge — they do not hold it:" .review/runs/0-qa-T-029-later
says "an item put off until after the merge is listed with its reason" \
  "      the build of main — the workflow runs only on a push to the base branch. Then: the run of the build workflow on main, at the merge commit"
never_says "an item put off is not a thing that passed" "nothing: every item passed"
says "below the pull request levels nothing waits on an item put off" \
  "   The loop goes on: nothing merges at LANDING=off: what is put off stands in the report of the task (maintain, step 13)"
never_says "and the user is not asked where the loop makes no merge" "For the user"
# A count of items put off that no item backs says neither what is checked then nor why:
# it is no item put off, and the merge reads it as not checked.
qa_record T-029 counted '{"counts": {"pass": 1, "after_merge": 2}, "failures": []}'
qa_says "a count of items put off with no item behind it is said to count as not checked" 0 \
  "   2 put off until after the merge by a count alone: no item says its check, so they count as not checked" \
  .review/runs/0-qa-T-029-counted
says "and the loop has /qa list each with its check" \
  "   The loop goes on: have /qa list each as an item, with its reason and the check that will be made then (items), or check it now"
never_says "a count alone is not said to be free of the merge" "do not hold"

new_task T-030
qa_record T-030 asks "{\"failures\": [], $double_tap}"
qa_record T-030 again "{\"failures\": [], $double_tap}"
e2e_review "a run of a task whose /qa saw what nothing written describes goes on" 0 \
  "CLEAN — gates green" .review/T-030.json
e2e_land "a landing ends with what nothing written describes" 0 \
  "   For the user, what should be: a double tap on a shelf opens it twice (Shelves)" \
  .review/T-030.json "$last_run"
if [ "$(grep -cF "For the user, what should be" "$WORK/land.log")" -eq 1 ] \
   && tail -1 "$WORK/land.log" | grep -qF "For the user, what should be"; then
  echo "ok    it is the last line, once for what two /qa saw"
else
  echo "FAIL  the question is not the last line of the landing, once — log follows"
  sed 's/^/      /' "$WORK/land.log"
  FAILURES=$((FAILURES + 1))
fi
not_asked_again="— /qa saw it, and pr-post.sh qa, right after that /qa, is where it is asked, "\
"once: it is not asked again here"
says "the landing names the question, and says that it is not asked again there" \
  "(Shelves) $not_asked_again" "$WORK/land.log"
never_says "nothing at a landing tells the loop to ask it" "ask it" "$WORK/land.log"
rm -rf .review/runs/0-qa-T-030-asks .review/runs/0-qa-T-030-again
e2e_land "the landing of a task with no such question ends as before" 0 \
  "For the user to commit" .review/T-030.json "$last_run"
never_says "and asks nothing" "For the user, what" "$WORK/land.log"

# What a fix may not bend. A failing case is proven by its test seen red, then green, and
# between the two neither its words nor its mark may give way: a run records a digest of
# the words of each case, and the marks it was checked against. A case that no end-to-end
# test can see, which /qa marks `manual: <why>`, is proven by a later /qa that passes it
# on other work; a pass of /qa never stands in for a case that has a test.
new_task T-031 '[{"case": "TC-001"}]'
E2E_XML="$(xml shows42=failed starts)" \
  e2e_review "the test of a case that is then reworded fails first" 2 \
  "app: failed: AnswerE2E.shows42" .review/T-031.json
red_run="$last_run"
words_digest() { ( . "$LIB_DIR/common.sh"; printf '%s' "$1" | sha256_stdin ); }
if jq -e --arg answer "$(words_digest '**TC-001 Answer.** Open the app: it shows 42.')" \
     --arg start "$(words_digest '**TC-002 Start.** Start the app: it opens with no error.')" \
     '.cases == {"TC-001": $answer, "TC-002": $start}' "$red_run/e2e.json" >/dev/null 2>&1; then
  echo "ok    a run records a digest of the words of each case"
else
  echo "FAIL  a run records no digest of the words of each case — its e2e.json follows"
  sed 's/^/      /' "$red_run/e2e.json"
  FAILURES=$((FAILURES + 1))
fi
sed 's/it shows 42\./it shows a number./' "$WORK/test-cases.md" >qa/test-cases.md
e2e_review "with the case reworded its test passes" 0 "CLEAN — gates green" .review/T-031.json
e2e_land "a case reworded between the red run and the landing proves nothing" 3 \
  "whose words changed since /qa failed it: TC-001 (as recorded in $(basename "$red_run"))" \
  .review/T-031.json "$last_run"
says "the loop is told that the words of a failing case stay" \
  "   The loop goes on: fix it" "$WORK/land.log"
says "and that its mark stays" "a mark stays on a failing case, and so do its words" \
  "$WORK/land.log"
cp "$red_run/e2e.json" "$WORK/e2e.red.json"
jq 'del(.cases)' "$WORK/e2e.red.json" >"$red_run/e2e.json"
e2e_land "a red run made before the words were recorded is not compared" 0 \
  "For the user to commit" .review/T-031.json "$last_run"
cp "$WORK/e2e.red.json" "$red_run/e2e.json"
cp "$WORK/test-cases.md" qa/test-cases.md
e2e_land "with the words as they were when its test failed, the task lands" 0 \
  "For the user to commit" .review/T-031.json "$last_run"


# The words are those the first red run was made against: a case reworded between two red
# runs is compared with the first.
new_task T-041 '[{"case": "TC-001"}]'
E2E_XML="$(xml shows42=failed starts)" \
  e2e_review "the test of a case that is reworded before a second red run fails first" 2 \
  "app: failed: AnswerE2E.shows42" .review/T-041.json
first_red_run="$last_run"
sed 's/it shows 42\./it shows a number./' "$WORK/test-cases.md" >qa/test-cases.md
E2E_XML="$(xml shows42=failed starts)" \
  e2e_review "reworded, its test fails once more" 2 "app: failed: AnswerE2E.shows42" \
  .review/T-041.json
e2e_review "and then passes" 0 "CLEAN — gates green" .review/T-041.json
e2e_land "a case reworded between two red runs proves nothing" 3 \
  "whose words changed since /qa failed it: TC-001 (as recorded in $(basename "$first_red_run"))" \
  .review/T-041.json "$last_run"
cp "$WORK/test-cases.md" qa/test-cases.md
e2e_land "with the words of the first red run, the task lands" 0 "For the user to commit" \
  .review/T-041.json "$last_run"

# The words are those /qa failed the case with: pr-post.sh qa, run right after /qa, keeps a
# digest of the words of each failing case beside the record, once. So a case reworded
# before its test was ever seen failing proves nothing either; what /qa itself wrote anew
# when it failed the case is what counts.
new_task T-042
e2e_review "a run of a task made before /qa fails a case goes on" 0 "CLEAN — gates green" \
  .review/T-042.json
qa_record T-042 failed '{"failures": [{"case": "TC-001"}], "work": "w1"}'
qa_says "pr-post.sh qa on a failing case says whose it is" 0 "   The loop goes on: fix TC-001" \
  .review/runs/0-qa-T-042-failed
if jq -e --arg answer "$(words_digest '**TC-001 Answer.** Open the app: it shows 42.')" \
     '. == {"TC-001": $answer}' .review/runs/0-qa-T-042-failed/cases.json >/dev/null 2>&1; then
  echo "ok    and keeps a digest of the words of the failing case beside the record"
else
  echo "FAIL  pr-post.sh qa kept no digest of the words of the failing case — the folder follows"
  ls .review/runs/0-qa-T-042-failed | sed 's/^/      /'
  FAILURES=$((FAILURES + 1))
fi
sed 's/it shows 42\./it shows a number./' "$WORK/test-cases.md" >qa/test-cases.md
E2E_XML="$(xml shows42=failed starts)" \
  e2e_review "the test of a case reworded before its first red run fails" 2 \
  "app: failed: AnswerE2E.shows42" .review/T-042.json
e2e_review "and passes after the fix" 0 "CLEAN — gates green" .review/T-042.json
words_changed="whose words changed since /qa failed it: TC-001 (as recorded in 0-qa-T-042-failed)"
e2e_land "a case reworded after /qa failed it and before its test was seen failing proves nothing" \
  3 "$words_changed" .review/T-042.json "$last_run"
"$LIB_DIR/pr-post.sh" qa .review/runs/0-qa-T-042-failed >"$WORK/post.log" 2>&1
e2e_land "pr-post.sh qa run again keeps the words as they were" 3 "$words_changed" \
  .review/T-042.json "$last_run"
cp "$WORK/test-cases.md" qa/test-cases.md
e2e_land "with the words /qa failed the case with, the task lands" 0 "For the user to commit" \
  .review/T-042.json "$last_run"
# A later /qa that writes the case anew and fails it again says what is to be seen now.
sed 's/it shows 42\./it shows 42 at once./' "$WORK/test-cases.md" >qa/test-cases.md
qa_record T-042 again '{"failures": [{"case": "TC-001"}], "work": "w2"}'
qa_says "a later /qa that sharpens the case and fails it again says whose it is" 0 \
  "   The loop goes on: fix TC-001" .review/runs/0-qa-T-042-again
E2E_XML="$(xml shows42=failed starts)" \
  e2e_review "the test of the sharpened case fails" 2 "app: failed: AnswerE2E.shows42" \
  .review/T-042.json
e2e_review "and the sharpened case passes after its fix" 0 "CLEAN — gates green" \
  .review/T-042.json
e2e_land "the words of the newest /qa that failed the case are the ones that count" 0 \
  "For the user to commit" .review/T-042.json "$last_run"
sed 's/it shows 42\./it shows 42 or so./' "$WORK/test-cases.md" >qa/test-cases.md
e2e_review "with the sharpened case reworded a run goes on" 0 "CLEAN — gates green" \
  .review/T-042.json
e2e_land "reworded after that /qa, it proves nothing" 3 \
  "whose words changed since /qa failed it: TC-001 (as recorded in 0-qa-T-042-again)" \
  .review/T-042.json "$last_run"
cp "$WORK/test-cases.md" qa/test-cases.md
qa_record T-042 clean '{"failures": [], "work": "w3"}'
"$LIB_DIR/pr-post.sh" qa .review/runs/0-qa-T-042-clean >"$WORK/post.log" 2>&1
if [ ! -e .review/runs/0-qa-T-042-clean/cases.json ]; then
  echo "ok    a /qa that failed no case keeps no words"
else
  echo "FAIL  pr-post.sh qa wrote cases.json for a /qa that failed no case"
  FAILURES=$((FAILURES + 1))
fi
new_task T-032 '[{"case": "TC-001"}]'
E2E_XML="$(xml shows42=failed starts)" \
  e2e_review "the test of a case whose mark then grows fails first" 2 \
  "app: failed: AnswerE2E.shows42" .review/T-032.json
sed 's/`AnswerE2E.shows42`/`AnswerE2E.shows42`, `AnswerE2E.shows43`/' "$WORK/test-cases.md" \
  >qa/test-cases.md
E2E_XML="$(xml shows42 starts shows43)" \
  e2e_review "with a second test in its mark the tests pass" 0 "CLEAN — gates green" \
  .review/T-032.json
e2e_land "a mark that grows between the red run and the landing changes nothing" 0 \
  "For the user to commit" .review/T-032.json "$last_run"
cp "$WORK/test-cases.md" qa/test-cases.md

new_task T-033 '[{"case": "TC-001"}]'
E2E_XML="$(xml shows42=failed starts)" \
  e2e_review "the test of a case that then gets a note fails first" 2 \
  "app: failed: AnswerE2E.shows42" .review/T-033.json
cat >qa/test-cases.md <<'CASES'
# Test cases

## Answer

* **TC-001 Answer.** Open the app:
  it shows 42.   --   e2e: `AnswerE2E.shows42`
  - Got past `/qa` once: the check read one frame, not the frames before it.
- **TC-002 Start.** Start the app: it opens with no error. — e2e:
  `AnswerE2E.starts`
CASES
e2e_review "with a note under the case, wrapped another way, its test passes" 0 \
  "CLEAN — gates green" .review/T-033.json
e2e_land "a note under the case, and the case wrapped another way, change nothing" 0 \
  "For the user to commit" .review/T-033.json "$last_run"
cp "$WORK/test-cases.md" qa/test-cases.md

new_task T-034
qa_record T-034 failed '{"failures": [{"case": "TC-001"}], "work": "w1"}'
e2e_review "a run of a task with a failing case records its mark" 0 "CLEAN — gates green" \
  .review/T-034.json
sed 's/ — e2e: `AnswerE2E.shows42`/ — manual: no test sees it/' "$WORK/test-cases.md" \
  >qa/test-cases.md
qa_record T-034 passed '{"counts": {"pass": 1}, "failures": [], "work": "w2",
  "items": [{"id": "TC-001", "verdict": "pass"}]}'
e2e_review "with the mark taken off the case, a run still goes on" 0 "CLEAN — gates green" \
  .review/T-034.json
e2e_land "a mark taken off a failing case refuses" 3 \
  "a /qa failure lost its end-to-end test after /qa failed it: TC-001" \
  .review/T-034.json "$last_run"
cp "$WORK/test-cases.md" qa/test-cases.md

cat >>qa/test-cases.md <<'CASES'
- **TC-003 Launch.** Start the app: the launch screen shows its name. — manual: the launch
  screen is the system's
  - Got past `/qa` once: nobody looked at the launch screen.
- **TC-004 Icon.** Look at the home screen: the icon of the app is there. — manual
  - Got past `/qa` once: the icon was the default one.
CASES
new_task T-035
qa_record T-035 failed '{"failures": [{"case": "TC-003"}], "work": "w1"}'
e2e_review "a run of a task that failed a case /qa marks manual goes on" 0 \
  "CLEAN — gates green" .review/T-035.json
manual_unproven="of a case /qa marks manual, not passed by a later /qa on other work: TC-003"
e2e_land "a failing case /qa marks manual is not proven by itself" 3 "$manual_unproven" \
  .review/T-035.json "$last_run"
says "the loop is told what proves such a case" \
  "a case no end-to-end test can see, which /qa marks — manual: <why>, is proven by the next /qa that passes it after the fix" \
  "$WORK/land.log"
launch_passed='"counts": {"pass": 1}, "failures": [],
  "items": [{"id": "TC-003 on the phone", "verdict": "pass"}]'
qa_record T-035 passed "{$launch_passed, \"work\": \"w1\"}"
e2e_land "a pass on the same work proves nothing" 3 "$manual_unproven" \
  .review/T-035.json "$last_run"
qa_record T-035 passed "{$launch_passed}"
e2e_land "a pass on work that is not known proves nothing" 3 "$manual_unproven" \
  .review/T-035.json "$last_run"
qa_record T-035 passed "{$launch_passed, \"work\": \"w2\"}"
e2e_land "the next /qa that passes it on other work proves it" 0 "For the user to commit" \
  .review/T-035.json "$last_run"
qa_record T-035 open '{"counts": {"pass": 1, "not_checked": 1}, "failures": [], "work": "w3",
  "items": [{"id": "TC-003 on the phone", "verdict": "pass"},
            {"id": "TC-003 on the tablet", "verdict": "not_checked",
             "reason": "the emulator did not boot"}]}'
e2e_land "a later /qa that could not check all of it proves nothing" 3 "$manual_unproven" \
  .review/T-035.json "$last_run"
says "the refusal names the item that is not passed" \
  "work: TC-003 (item TC-003 on the tablet says not_checked in 0-qa-T-035-open)" "$WORK/land.log"
rm -rf .review/runs/0-qa-T-035-open
qa_record T-035 again '{"failures": [{"case": "TC-003"}], "work": "w3"}'
e2e_land "a still later /qa that fails it again proves nothing" 3 "$manual_unproven" \
  .review/T-035.json "$last_run"
qa_record T-035 both '{"failures": [{"case": "TC-001"}, {"case": "TC-003"}], "work": "w4"}'
e2e_land "one refusal lists each kind of failure that is not proven" 3 \
  "a /qa failure without an end-to-end test seen red, then green: TC-001; $manual_unproven" \
  .review/T-035.json "$last_run"

new_task T-036
qa_record T-036 failed '{"failures": [{"case": "TC-001"}], "work": "w1"}'
e2e_review "a run of a task that failed a case with a test goes on" 0 "CLEAN — gates green" \
  .review/T-036.json
qa_record T-036 passed '{"counts": {"pass": 1}, "failures": [], "work": "w2",
  "items": [{"id": "TC-001", "verdict": "pass"}]}'
e2e_land "a /qa pass does not stand in for a test" 3 \
  "a /qa failure without an end-to-end test seen red, then green: TC-001" \
  .review/T-036.json "$last_run"

new_task T-037
qa_record T-037 failed '{"failures": [{"case": "TC-004"}], "work": "w1"}'
e2e_review "a run of a task that failed a case with neither a test nor a reason goes on" 0 \
  "CLEAN — gates green" .review/T-037.json
qa_record T-037 passed '{"counts": {"pass": 1}, "failures": [], "work": "w2",
  "items": [{"id": "TC-004", "verdict": "pass"}]}'
e2e_land "a case with neither a test nor a reason is not proven by a /qa pass" 3 \
  "a /qa failure without an end-to-end test seen red, then green: TC-004" \
  .review/T-037.json "$last_run"

# A case that failed on one platform is proven only by a /qa that passes it there: each item
# of the case that failed passes in the later one. An item that passed then is not asked
# again, and the refusal names the item that is not there or not passed.
new_task T-043
qa_record T-043 failed '{"counts": {"pass": 1, "fail": 1}, "failures": [{"case": "TC-003"}],
  "work": "w1",
  "items": [{"id": "TC-003 on Android", "verdict": "fail", "reason": "the launch screen is blank"},
            {"id": "TC-003 on iOS", "verdict": "pass"}]}'
e2e_review "a run of a task whose manual case failed on one platform goes on" 0 \
  "CLEAN — gates green" .review/T-043.json
qa_record T-043 passed '{"counts": {"pass": 1}, "failures": [], "work": "w2",
  "items": [{"id": "TC-003 on iOS", "verdict": "pass"}]}'
e2e_land "a pass on another platform does not prove the failure on this one" 3 \
  "$manual_unproven" .review/T-043.json "$last_run"
says "the refusal names the item that failed and is not there" \
  "work: TC-003 (item TC-003 on Android failed in 0-qa-T-043-failed and is not among the items of 0-qa-T-043-passed)" \
  "$WORK/land.log"
qa_record T-043 passed '{"counts": {"pass": 1, "unproven": 1}, "failures": [], "work": "w2",
  "items": [{"id": "TC-003 on Android", "verdict": "unproven",
             "reason": "the recording starts after the launch screen"},
            {"id": "TC-003 on iOS", "verdict": "pass"}]}'
e2e_land "a later /qa that left the item that failed unproven proves nothing" 3 \
  "$manual_unproven (item TC-003 on Android says unproven in 0-qa-T-043-passed)" \
  .review/T-043.json "$last_run"
qa_record T-043 passed '{"counts": {"pass": 1}, "failures": [], "work": "w2",
  "items": [{"id": "TC-003 on Android", "verdict": "pass"}]}'
e2e_land "a /qa that passes the item that failed proves it: what passed then is not asked again" 0 \
  "For the user to commit" .review/T-043.json "$last_run"
qa_record T-043 passed '{"counts": {"pass": 2}, "failures": [], "work": "w2",
  "items": [{"id": "TC-003 on Android", "verdict": "pass"},
            {"id": "TC-003 on iOS", "verdict": "pass"}]}'
e2e_land "and so does a /qa that passes each item the failing one listed" 0 \
  "For the user to commit" .review/T-043.json "$last_run"
# A failing /qa that listed the case whole is answered by the items of the later one.
new_task T-044
qa_record T-044 failed '{"counts": {"fail": 1}, "failures": [{"case": "TC-003"}], "work": "w1",
  "items": [{"id": "TC-003", "verdict": "fail", "reason": "the launch screen is blank"}]}'
e2e_review "a run of a task whose manual case failed as a whole goes on" 0 \
  "CLEAN — gates green" .review/T-044.json
qa_record T-044 passed '{"counts": {"pass": 2}, "failures": [], "work": "w2",
  "items": [{"id": "TC-003 on Android", "verdict": "pass"},
            {"id": "TC-003 on iOS", "verdict": "pass"}]}'
e2e_land "a case that failed as a whole is proven by a /qa that passes it on each platform" 0 \
  "For the user to commit" .review/T-044.json "$last_run"
# The landing reads an item as of a case the way the record is checked: the case id, then a
# character that is no letter, digit or dash.
new_task T-047
qa_record T-047 failed '{"failures": [{"case": "TC-003"}], "work": "w1"}'
e2e_review "a run of a task whose manual case failed and is passed under an id with a colon goes on" 0 \
  "CLEAN — gates green" .review/T-047.json
qa_record T-047 passed '{"counts": {"pass": 1}, "failures": [], "work": "w2",
  "items": [{"id": "TC-0031: the launch screen", "verdict": "pass"}]}'
e2e_land "a pass of an item whose id goes on with a digit is no pass of the case" 3 \
  "$manual_unproven" .review/T-047.json "$last_run"
qa_record T-047 passed '{"counts": {"pass": 1}, "failures": [], "work": "w2",
  "items": [{"id": "TC-003: the launch screen", "verdict": "pass"}]}'
e2e_land "a later /qa that passes the item under its id with a colon proves the case" 0 \
  "For the user to commit" .review/T-047.json "$last_run"
# pr-post.sh qa says the same of such cases, right after /qa.
qa_record T-038 launch '{"failures": [{"case": "TC-003"}]}'
qa_says "a failing case /qa marks manual is told what proves it" 0 \
  "      /qa marks it manual: the launch screen is the system's" .review/runs/0-qa-T-038-launch
says "its fix needs no end-to-end test" \
  "   The loop goes on: fix TC-003 — it is no question: no end-to-end test can see it, so the next /qa that passes it on the changed work proves it (condition 7)"
never_says "and nothing tells the loop to write one" "write its end-to-end test"
never_says "a note under the case is no part of its reason" "Got past"
says "a record that does not say which work /qa checked is told so, where a later /qa must prove the fix" \
  "; this record does not say which work /qa checked (work): have /qa add it — pr-post.sh work prints it — or no later /qa proves the fix"
qa_record T-038 known '{"failures": [{"case": "TC-003"}], "work": "w1"}'
qa_says "a record that says its work is told what proves the case" 0 \
  "next /qa that passes it on the changed work proves it (condition 7)" \
  .review/runs/0-qa-T-038-known
never_says "and nothing more is asked of it" "does not say which work"
rm -rf .review/runs/0-qa-T-038-known
qa_says "a failing case marked manual with no reason is told to get a test, or its reason" 0 \
  "      no end-to-end test is marked for it" .review/runs/0-qa-T-037-failed
says "its words are quoted without the note under it" \
  '      "**TC-004 Icon.** Look at the home screen: the icon of the app is there."'
says "the reason is /qa's to write" \
  "where no end-to-end test can see it, /qa says so in the case (— manual: <why>), and the next /qa after the fix proves it"
cp "$WORK/test-cases.md" qa/test-cases.md

# Below the pull request levels too a record of /qa says which work it checked: pr-post.sh
# work prints the fingerprint of the work and HEAD at every level, and asks no remote
# there. So a fixed failure of a case /qa marks manual is proven by the next /qa at every
# level, and a record that leaves its work out is told what it lacks.
cat >>qa/test-cases.md <<'CASES'
- **TC-003 Launch.** Start the app: the launch screen shows its name. — manual: the launch
  screen is the system's
CASES
"$LIB_DIR/pr-post.sh" work >"$WORK/work.log" 2>&1
check "below the pull request levels pr-post.sh work prints the work as it is" 0 '"work": "' $? \
  "$WORK/work.log"
if jq -e --arg head "$(git rev-parse HEAD)" \
     '.head == $head and (.work | test("^[0-9a-f]{64}$")) and (has("merge_base") | not)' \
     "$WORK/work.log" >/dev/null 2>&1; then
  echo "ok    with HEAD, and with no merge base: there is no pull request to check whole"
else
  echo "FAIL  pr-post.sh work does not print {work, head} alone — log follows"
  sed 's/^/      /' "$WORK/work.log"
  FAILURES=$((FAILURES + 1))
fi
new_task T-039
qa_record T-039 failed \
  "{\"failures\": [{\"case\": \"TC-003\"}], \"work\": \"$(jq -r '.work' "$WORK/work.log")\"}"
e2e_review "a run of a task whose manual case failed below the pull request levels goes on" 0 \
  "CLEAN — gates green" .review/T-039.json
printf 'fun answer() = 42 // the launch screen shows the name\n' >src/answer.kt
e2e_review "a run after its fix goes on" 0 "CLEAN — gates green" .review/T-039.json
cp "$WORK/work.log" "$WORK/work.before.log"
"$LIB_DIR/pr-post.sh" work >"$WORK/work.log" 2>&1
if [ "$(jq -r '.work' "$WORK/work.log" 2>/dev/null)" = "$(jq -r '.tree_fingerprint' "$last_run/meta.json")" ] \
   && [ "$(jq -r '.work' "$WORK/work.log")" != "$(jq -r '.work' "$WORK/work.before.log")" ]; then
  echo "ok    after the fix it prints other work, the work the review of the fix recorded"
else
  echo "FAIL  pr-post.sh work does not print the work the review recorded — log follows"
  sed 's/^/      /' "$WORK/work.log"
  FAILURES=$((FAILURES + 1))
fi
launch_passed_here='"counts": {"pass": 1}, "failures": [],
  "items": [{"id": "TC-003", "verdict": "pass"}]'
qa_record T-039 passed "{$launch_passed_here}"
e2e_land "a /qa that passes it and does not say which work it checked proves nothing" 3 \
  "of a case /qa marks manual, not passed by a later /qa on other work: TC-003" \
  .review/T-039.json "$last_run"
says "the loop is told that each /qa records the work it checked" \
  "is proven by the next /qa that passes it after the fix, each /qa recording the work it checked (pr-post.sh work prints it)" \
  "$WORK/land.log"
qa_record T-039 passed "{$launch_passed_here, \"work\": \"$(jq -r '.work' "$WORK/work.log")\"}"
e2e_land "below the pull request levels a manual case fixed and passed by the next /qa lands" 0 \
  "For the user to commit" .review/T-039.json "$last_run"
printf 'fun answer() = 42\n' >src/answer.kt
cp "$WORK/test-cases.md" qa/test-cases.md
# The words of a case are its text without the mark alone — the ids after `e2e:`, as
# case_marks reads them, or `manual` with its reason after a dash: what stands after an
# end-to-end mark is words too, and a word that ends in -manual: is no mark.
cat >qa/test-cases.md <<'CASES'
# Test cases

- **TC-001 Answer.** Open the app — e2e: `AnswerE2E.shows42` — it shows 42.
- **TC-002 Start.** Start the app — e2e: AnswerE2E.starts; AnswerE2E.shows43 and it opens
  with no error.
- **TC-003 Help.** Open the user-manual: it shows the index.
- **TC-004 Launch.** Start the app: the launch screen shows its name. — manual: the launch
  screen is the system's
CASES
( . "$LIB_DIR/common.sh"; case_words; echo "the cases that say why no test sees them:"
  case_manual; printf 'the tests: '; case_tests | tr '\n' ' '; echo ) >"$WORK/words.log" 2>&1
says "the words after an end-to-end mark are words of the case" \
  "TC-001	**TC-001 Answer.** Open the app — it shows 42." "$WORK/words.log"
says "a mark of bare ids ends where its ids end" \
  "TC-002	**TC-002 Start.** Start the app and it opens with no error." "$WORK/words.log"
says "a word that ends in -manual: stays in the words" \
  "TC-003	**TC-003 Help.** Open the user-manual: it shows the index." "$WORK/words.log"
says "manual with its reason is no word of the case" \
  "TC-004	**TC-004 Launch.** Start the app: the launch screen shows its name." "$WORK/words.log"
says "the reason of a manual case is read" "TC-004	the launch screen is the system's" \
  "$WORK/words.log"
never_says "a word that ends in -manual: is no reason" "TC-003	it shows the index." \
  "$WORK/words.log"
says "the tests of the marks are read as before" \
  "the tests: AnswerE2E.shows42 AnswerE2E.starts AnswerE2E.shows43 " "$WORK/words.log"
new_task T-045 '[{"case": "TC-001"}]'
E2E_XML="$(xml shows42=failed starts shows43)" \
  e2e_review "the test of a case with words after its mark fails first" 2 \
  "app: failed: AnswerE2E.shows42" .review/T-045.json
sed -i.bak 's/ — it shows 42\./ — it shows a number./' qa/test-cases.md && rm qa/test-cases.md.bak
E2E_XML="$(xml shows42 starts shows43)" \
  e2e_review "with the words after the mark changed its test passes" 0 "CLEAN — gates green" \
  .review/T-045.json
e2e_land "words changed after the mark of a failing case prove nothing" 3 \
  "whose words changed since /qa failed it: TC-001" .review/T-045.json "$last_run"
new_task T-046
qa_record T-046 failed '{"failures": [{"case": "TC-003"}], "work": "w1"}'
E2E_XML="$(xml shows42 starts shows43)" \
  e2e_review "a run of a task that failed a case with -manual: in a word goes on" 0 \
  "CLEAN — gates green" .review/T-046.json
qa_record T-046 passed '{"counts": {"pass": 1}, "failures": [], "work": "w2",
  "items": [{"id": "TC-003", "verdict": "pass"}]}'
e2e_land "a case with -manual: in a word is no manual case: a /qa pass does not prove it" 3 \
  "a /qa failure without an end-to-end test seen red, then green: TC-003" \
  .review/T-046.json "$last_run"
cp "$WORK/test-cases.md" qa/test-cases.md

# The stop reads the runs. review.sh reads the runs of the task before it makes a new one,
# counts the reviews among them, and stops where a finding or an end repeats. Each task
# here is its own. `round` makes one run: with `new` the work changes first; the reviewer
# accepts one finding at a line of src/pickup.kt, or none with `-`; ROUND_FILE names
# another file and ROUND_QUOTE another quote than the line. `on_the_way` is a run a case
# needs before it, which must end as given.
cp .review/gates.sh "$WORK/gates.before-rounds"
cp .review/land.conf "$WORK/land.conf.before-rounds"
for line in $(seq 80); do printf 'val l%s = %s\n' "$line" "$line"; done >src/pickup.kt
limit_is() { printf 'THRESHOLD=major\nLANDING=off\nASK_AFTER_RUNS=%s\n' "$1" >.review/land.conf; }
round_run() {
  local task_id="$1" work="$2" at="$3"; shift 3
  [ -f ".review/$task_id.json" ] || printf '{"id": "%s", "title": "Pickup", '\
'"category": "bugfix", "scope": ["src/*"], "exit_criteria": []}' "$task_id" >".review/$task_id.json"
  [ "$work" = same ] || printf '// a fix\n' >>src/fix.kt
  if [ "$at" = - ]; then
    printf '{"findings":[]}' >"$WORK/reviewer.json"
    printf '{"verdicts":[]}' >"$WORK/maintainer.json"
  else
    printf '{"findings":[{"id":"F-001","file":"%s","line":%s,'\
'"code_quote":"%s","category":"bug","severity":"major","confidence":"confirmed",'\
'"evidence":"the pickup is taken twice"}]}' "${ROUND_FILE:-src/pickup.kt}" "$at" \
      "${ROUND_QUOTE:-val l$at = $at}" >"$WORK/reviewer.json"
    printf '%s' "$(verdict '"accept"' no-rule-fired)" >"$WORK/maintainer.json"
  fi
  REVIEWER_CMD="cat $WORK/reviewer.json #" MAINTAINER_CMD="cat $WORK/maintainer.json #" \
    "$LIB_DIR/review.sh" --task-file ".review/$task_id.json" "$@" >"$WORK/run.log" 2>&1
}
round() {
  local name="$1" expected_exit="$2" expected_line="$3"; shift 3
  round_run "$@"
  check "$name" "$expected_exit" "$expected_line" $? "$WORK/run.log"
}
on_the_way() {
  local expected_exit="$1" actual_exit; shift
  round_run "$@"
  actual_exit=$?
  [ "$actual_exit" -eq "$expected_exit" ] && return 0
  echo "FAIL  a run on the way ($*): expected exit $expected_exit, got $actual_exit — log follows"
  sed 's/^/      /' "$WORK/run.log"
  FAILURES=$((FAILURES + 1))
}
red_gates() {
  printf '#!/usr/bin/env bash\necho %s >"$1"\nexit 1\n' \
    "'{\"test\":{\"status\":\"fail\",\"blocking\":true,\"command\":\"false\",\"output\":\"$1\"}}'" \
    >.review/gates.sh
}
green_gates() { cp "$WORK/gates.before-rounds" .review/gates.sh; }

# The limit counts reviews, and at the limit the script says what it read.
limit_is 5
on_the_way 3 T-060 new 3
on_the_way 3 T-060 new 20
on_the_way 3 T-060 new 35
on_the_way 0 T-060 new -
on_the_way 0 T-060 new -
round "reviews that found different things, each fixed, reach the limit and say so" 6 \
  "LIMIT OF REVIEWS — T-060 has had 5 reviews since the count started, 5 runs in all" \
  T-060 new -
says "there it says what each review accepted" \
  "   accepted by each review, oldest first: 1, 1, 1, 0, 0" "$WORK/run.log"
says "and that the loop goes on" "   The loop goes on: no finding came back after its fix" \
  "$WORK/run.log"
never_says "a count alone is no question" "the user" "$WORK/run.log"
round "--past-limit then runs the sixth with nobody's words" 0 "CLEAN" T-060 same - --past-limit
run_records "a run past a limit that converges records that" \
  '.past_limit_kind == "converging" and .stop == "reviews" and .because == null
   and .user_decided == null and .count == null'

on_the_way 0 T-061 new -
red_gates "could not compile"
on_the_way 2 T-061 same -
red_run_of_t061="$(newest_run)"
green_gates
on_the_way 0 T-061 same -
printf '#!/usr/bin/env bash\nexit 1\n' >.review/gates.sh
on_the_way 1 T-061 same -
green_gates
on_the_way 0 T-061 same -
round "of five runs, two that made no review leave three reviews" 0 "CLEAN" T-061 same -
run_records "the sixth run is the fourth review" '.count == 4'
if jq -e '.count == null and .end == "gates-red"' "$red_run_of_t061/meta.json" >/dev/null; then
  echo "ok    a run that made no review has no number among the reviews"
else
  echo "FAIL  a run that made no review has no number among the reviews: "\
"$(jq -c '{count, end: .end}' "$red_run_of_t061/meta.json")"
  FAILURES=$((FAILURES + 1))
fi
limit_is 3
on_the_way 0 T-062 new -
red_gates "could not compile"
on_the_way 2 T-062 same -
green_gates
on_the_way 0 T-062 same -
on_the_way 0 T-062 same -
round "at the limit the count says reviews and runs apart" 6 \
  "has had 3 reviews since the count started, 4 runs in all" T-062 same -
says "reviews that accepted nothing are no question either" \
  "   The loop goes on: no review accepted a finding, so the reviews are not what repeats" \
  "$WORK/run.log"

# A finding that comes back after its fix: said at the second time, a stop at the third.
limit_is 100
on_the_way 3 T-063 new 10
round "a finding that comes back after its fix is said at the end of the run" 3 \
  "   again after a change: F-001 src/pickup.kt:10 — also accepted in " T-063 new 10
says "with what comes of a third time" "   a third time in a row review.sh stops" "$WORK/run.log"
round "the third review of it still runs, and says that the next run stops" 3 \
  "   that is 3 reviews in a row: the next run of review.sh stops" T-063 new 10
third_review_of_t063="$(newest_run)"
runs_before="$(ls .review/runs | wc -l)"
round "a third time in a row review.sh stops" 6 \
  "NOT CONVERGING — the fixes of T-063 do not close a finding of the review; nothing ran." \
  T-063 new 10
says "it says what does not converge" \
  '   src/pickup.kt:10 (bug) `val l10 = 10` was accepted in 3 reviews in a row, each after' \
  "$WORK/run.log"
says "it says where the finding is written, and that a run's patch is the whole change" \
  "   what it says: $third_review_of_t063/approved.json; the whole change as each review saw "\
"it: the diff.patch of each of those runs — what a fix changed is what differs between two" \
  "$WORK/run.log"
says "and that it is the user's" \
  "   For the user, the work does not converge: the same finding came back after each of 2 fixes" \
  "$WORK/run.log"
says "with the way on once they decided" "--past-limit --user-decided then runs once more" \
  "$WORK/run.log"
if [ "$(ls .review/runs | wc -l)" -eq "$runs_before" ]; then
  echo "ok    a stop leaves no run behind"
else
  echo "FAIL  a stop left a run directory behind"
  FAILURES=$((FAILURES + 1))
fi
round "--past-limit alone does not pass a stop that is the user's" 1 \
  "this stop takes --user-decided" T-063 same 10 --past-limit
round "the loop's own reason does not pass it either" 1 \
  "this stop takes --user-decided" T-063 same 10 --past-limit --because "it moves"
round "--user-decided takes no words" 1 "unknown argument: try the other rounding" \
  T-063 same 10 --past-limit --user-decided "try the other rounding"
round "beside the user's decision no reason is taken: nothing keeps words there" 1 \
  "this stop takes --user-decided alone" \
  T-063 same 10 --past-limit --user-decided --because "they said to try the other rounding"
round "once the user decided to go on it runs once more" 3 "accepted (>= major): 1" \
  T-063 same 10 --past-limit --user-decided
run_records "and the run records that they decided, and no words" \
  '.user_decided == true and .past_limit_kind == "user" and .stop == "finding"
   and .because == null and ([.. | strings] | all(test("rounding") | not))'
# The user's decision to go on holds until the next review. A run past the stop that ended
# before its review made none: nothing is new, and the same question is not asked again.
for attempt in first second third; do on_the_way 3 T-082 new 10; done
on_the_way 6 T-082 new 10
red_gates "could not compile"
on_the_way 2 T-082 same 10 --past-limit --user-decided
green_gates
round "a run past the stop of a finding that made no review does not use up the user's decision" \
  3 "accepted (>= major): 1" T-082 same 10
round "the review made on that decision, which accepts the finding again, brings the stop back" \
  6 "was accepted in 4 reviews in a row" T-082 new 10
# What the finding says is read where the newest review of the row wrote it, also when a
# run after that review made none: runs made before review.sh read them may stand so.
on_the_way 3 T-083 new 10
on_the_way 3 T-083 new 10
red_gates "could not compile"
on_the_way 2 T-083 new 10
red_run_of_t083="$(newest_run)"
green_gates
on_the_way 3 T-083 new 10
third_review_of_t083="$(newest_run)"
jq '.time = now' "$red_run_of_t083/meta.json" >"$WORK/meta.json" \
  && mv "$WORK/meta.json" "$red_run_of_t083/meta.json"
round "the stop of a finding names the run of the newest review, not a newer run without one" \
  6 "   what it says: $third_review_of_t083/approved.json; " T-083 new 10
on_the_way 3 T-064 new 10
round "the same finding on unchanged work did not come back after a fix" 3 \
  "accepted (>= major): 1" T-064 same 10
never_says "so nothing is said of it at the end of the run" "again after a change" \
  "$WORK/run.log"
on_the_way 3 T-064 same 10
round "the same finding on unchanged work is no circle" 3 "accepted (>= major): 1" \
  T-064 same 10
on_the_way 3 T-065 new 10
on_the_way 3 T-065 new 12
on_the_way 3 T-065 new 14
round "a finding whose line moved with each fix is the same place" 6 \
  "NOT CONVERGING — the fixes of T-065 do not close a finding of the review" T-065 new 14
on_the_way 3 T-066 new 3
round "another finding in the same file is not the first come back" 3 \
  "accepted (>= major): 1" T-066 new 20
never_says "so nothing is said of it either" "again after a change" "$WORK/run.log"
on_the_way 3 T-066 new 35
round "different findings in one file are no circle" 3 "accepted (>= major): 1" T-066 new 50
# The same quote is the same place only where the file holds that line once. Three
# defects that begin with a line the file holds at several places, each fixed before the
# next is found, are three findings; a finding whose line the file holds once is the same
# finding however far a fix moved it.
for line in $(seq 80); do
  case "$line" in
    10 | 40 | 70) printf '    return null\n' ;;
    *) printf 'val g%s = %s\n' "$line" "$line" ;;
  esac
done >src/guard.kt
for line in 10 40 70; do
  ROUND_FILE=src/guard.kt ROUND_QUOTE="return null" on_the_way 3 T-080 new "$line"
  sed "${line}s/.*/    return fallback$line/" src/guard.kt >"$WORK/guard.kt" \
    && mv "$WORK/guard.kt" src/guard.kt
done
round "findings far apart that begin with a line the file held at several places are no circle" \
  0 "CLEAN" T-080 new -
cp src/pickup.kt src/moved.kt
for line in 10 30 50; do
  ROUND_FILE=src/moved.kt ROUND_QUOTE="val l10 = 10" on_the_way 3 T-081 new "$line"
  { for moved in $(seq 20); do printf '// moved down\n'; done; cat src/moved.kt; } \
    >"$WORK/moved.kt" && mv "$WORK/moved.kt" src/moved.kt
done
round "a finding that each fix moved far, quoted by a line the file holds once, is the same place" \
  6 '   src/moved.kt:50 (bug) `val l10 = 10` was accepted in 3 reviews in a row' T-081 new -
rm src/guard.kt src/moved.kt

# At the limit, where the script cannot read that the work converges, the loop judges and
# gives its reason.
limit_is 3
on_the_way 3 T-067 new 3
on_the_way 3 T-067 new 20
on_the_way 3 T-067 new 35
round "findings that differ and do not get fewer are the loop's to judge" 6 \
  "   they do not get fewer" T-067 new 50
says "the loop is told to judge whether the work moves" \
  "   The loop goes on: the findings differ and do not get fewer: judge whether the work moves" \
  "$WORK/run.log"
never_says "and nothing there is the user's" "the user" "$WORK/run.log"
round "there --past-limit needs its reason" 1 \
  '--past-limit at this stop needs --because "<what moves toward the goal>"' \
  T-067 same 50 --past-limit
round "a reason of blanks is no reason" 1 \
  '--past-limit at this stop needs --because "<what moves toward the goal>"' \
  T-067 same 50 --past-limit --because "  "
round "the loop's reason passes it" 3 "accepted (>= major): 1" \
  T-067 same 50 --past-limit --because "each was a defect of its own"
run_records "and the run records it" \
  '.past_limit_kind == "loop" and .stop == "reviews" and .user_decided == null
   and .because == "each was a defect of its own"'
# Where the loop cannot tell whether the work moves, the line makes it a question, and the
# user's decision to go on passes that stop too.
on_the_way 3 T-084 new 3
on_the_way 3 T-084 new 20
on_the_way 3 T-084 new 35
on_the_way 6 T-084 new 50
round "the user's decision to go on passes a stop of the loop's too" 3 "accepted (>= major): 1" \
  T-084 same 50 --past-limit --user-decided
run_records "and the run records whose stop it was, and that they decided" \
  '.past_limit_kind == "loop" and .stop == "reviews" and .user_decided == true
   and .because == null'
limit_is 2
on_the_way 3 T-068 new 10
on_the_way 3 T-068 new 10
round "a finding that came back once asks why at the limit" 6 \
  "   came back after its fix: src/pickup.kt:10 (bug), in 2 reviews in a row (" T-068 new 10
says "the loop finds why the fix did not hold" \
  "   The loop goes on: a finding came back after its fix: find why the fix did not hold" \
  "$WORK/run.log"
on_the_way 3 T-068 same 10 --past-limit --because "another fix"
round "a run past the limit does not wipe the circle" 6 \
  "was accepted in 3 reviews in a row" T-068 new 10

# Runs that end the same way: the same gates red with the same output.
limit_is 100
red_gates "the pickup test fails"
on_the_way 2 T-069 new -
round "two runs that end the same way say so at the end of the second" 2 \
  "── the same end as the run before (" T-069 new -
says "with what was red" \
  "): gates red: test, the same output each time but for its numbers; a third time in a row" \
  "$WORK/run.log"
round "the third run that ends the same way says that the next run stops" 2 \
  "── the same end as the 2 runs before: gates red: test, the same output each time but for "\
"its numbers; the next run of review.sh stops and says whose turn it is" T-069 new -
round "three runs in a row that end the same way after changes stop the fourth" 6 \
  "STOPPED — T-069 ended the same way in 3 runs in a row, each after a change of the work; "\
"nothing ran." T-069 new -
says "it names the gates that stayed red" \
  "   gates red: test, the same output each time but for its numbers (" "$WORK/run.log"
says "the first time that stop is the loop's, which finds the cause" \
  "   The loop goes on: the changes between those runs did not move it, and review.sh cannot "\
"tell fixes that do not close a failure from a machine that failed each time" "$WORK/run.log"
says "it says what passes the stop" \
  'run again with --past-limit --because "<what the cause was, and what was done about it>"' \
  "$WORK/run.log"
never_says "the same end the first time is no question" "the user" "$WORK/run.log"
round "with no reason that stop is not passed" 1 \
  '--past-limit at this stop needs --because "<what the cause was, and what was done about it>"' \
  T-069 same - --past-limit
round "the user's decision does not pass it: nothing is theirs to decide there" 1 \
  "this stop is the loop's: --user-decided is for a stop that is the user's" \
  T-069 same - --past-limit --user-decided
round "nor does their decision beside a reason" 1 \
  "this stop is the loop's: --user-decided is for a stop that is the user's" \
  T-069 same - --past-limit --user-decided --because "the build was stale"
round "the cause the loop found passes it" 2 "GATES RED" \
  T-069 same - --past-limit --because "the build was stale and is made from nothing"
pass_of_t069="$(basename "$(newest_run)")"
run_records "and the run records which stop it passed, and the reason" \
  '.stop == "same-end-after-changes" and .past_limit_kind == "loop" and .user_decided == null
   and .because == "the build was stale and is made from nothing"'
says "a run past that stop that ends the same way again says so" \
  "── the same end as before this stop was passed: gates red: test, the same output each time "\
"but for its numbers; three more times in a row and review.sh stops again" "$WORK/run.log"
# After such a pass the row starts again: three more runs in a row that end the same way,
# each after a change, and the reason did not hold. Only then is it the user's.
round "after the pass the next run that ends the same way runs" 2 "GATES RED" T-069 new -
never_says "one more of the same end is said nowhere yet" "the same end as" "$WORK/run.log"
round "the second more says that it ended as the run before" 2 \
  "── the same end as the run before (" T-069 new -
round "the third more says that the next run stops" 2 \
  "── the same end as the 2 runs before: gates red: test, the same output each time but for "\
"its numbers; the next run of review.sh stops and says whose turn it is" T-069 new -
round "the same end three more times after the loop's reason stops the next run" 6 \
  "NOT CONVERGING — T-069 ended the same way in 3 more runs in a row, each after a change of "\
"the work, since $pass_of_t069 passed this stop; nothing ran." T-069 new -
says "it says which reason did not hold" \
  "   the loop's reason then, which did not hold: the build was stale and is made from nothing" \
  "$WORK/run.log"
says "and now it is the user's" \
  "   For the user, the work does not converge: the same check stayed red through the cause "\
"the loop found and 3 more fixes" "$WORK/run.log"
says "with what they decide, and the way on" \
  "whether to go on trying, to stop the task here, or to change what is asked of it; "\
"--past-limit --user-decided then runs once more" "$WORK/run.log"
round "there the loop's reason passes no more" 1 "this stop takes --user-decided" \
  T-069 same - --past-limit --because "the gate is mended"
round "once the user decided to go on at that stop it runs once more" 2 "GATES RED" \
  T-069 same - --past-limit --user-decided
run_records "and the run records that they decided" \
  '.stop == "same-end-after-changes" and .past_limit_kind == "user" and .user_decided == true
   and .because == null'
# Each of the three more comes after a change: the oldest of them is compared with the run
# that passed the stop as well. A run on the work of that run is a retry and none of the
# three, so the stop after it is the stop of a retry, the loop's, and the user's comes once
# three runs since the pass each came after a change.
for attempt in first second third; do on_the_way 2 T-088 new -; done
on_the_way 6 T-088 new -
on_the_way 2 T-088 new - --past-limit --because "the build was stale and is made from nothing"
pass_of_t088="$(basename "$(newest_run)")"
on_the_way 2 T-088 same -
on_the_way 2 T-088 new -
on_the_way 2 T-088 new -
round "a retry on the work of the run that passed the stop is none of the three more" 6 \
  "STOPPED — T-088 ended the same way in 3 runs in a row; nothing ran." T-088 new -
says "the stop after such a retry is the loop's" \
  "   The loop goes on: a retry does not mend it" "$WORK/run.log"
never_says "two runs after a change since the loop's reason are no question" "the user" \
  "$WORK/run.log"
round "the loop's reason passes the stop after such a retry" 2 "GATES RED" \
  T-088 same - --past-limit --because "the simulator is booted again"
round "three runs since the pass, each after a change, are then the user's" 6 \
  "NOT CONVERGING — T-088 ended the same way in 3 more runs in a row, each after a change of "\
"the work, since $pass_of_t088 passed this stop; nothing ran." T-088 new -
says "the line counts a fix before each of the three" \
  "   For the user, the work does not converge: the same check stayed red through the cause "\
"the loop found and 3 more fixes" "$WORK/run.log"
# A different end between starts the row again: the same end three times after it is the
# first time once more, and the loop's.
for attempt in first second third; do on_the_way 2 T-087 new -; done
on_the_way 6 T-087 new -
on_the_way 2 T-087 same - --past-limit --because "the service was down and is up again"
on_the_way 2 T-087 new -
on_the_way 2 T-087 new -
red_gates "another test fails"
on_the_way 2 T-087 new -
red_gates "the pickup test fails"
for attempt in first second third; do on_the_way 2 T-087 new -; done
round "a different end between starts the row again" 6 \
  "STOPPED — T-087 ended the same way in 3 runs in a row, each after a change of the work; "\
"nothing ran." T-087 new -
says "and the stop is the loop's again" \
  "   The loop goes on: the changes between those runs did not move it" "$WORK/run.log"
never_says "the first time after another end is no question" "the user" "$WORK/run.log"
on_the_way 2 T-070 new -
on_the_way 2 T-070 same -
on_the_way 2 T-070 same -
round "on the same work it is a retry that does not mend it" 6 \
  "STOPPED — T-070 ended the same way in 3 runs in a row; nothing ran." T-070 same -
says "and the loop's to find the cause of" "   The loop goes on: a retry does not mend it" \
  "$WORK/run.log"
never_says "a retry is no question" "the user" "$WORK/run.log"
round "the loop's reason passes that stop" 2 "GATES RED" \
  T-070 same - --past-limit --because "the simulator is booted again"
# A pass of the stop on the same work is no such pass, and that stop stays in force while
# the runs end the same way: the same end through changes after it is the first time that
# the work changed, and the loop's.
on_the_way 6 T-070 new -
on_the_way 2 T-070 same - --past-limit --because "the simulator is erased and booted again"
on_the_way 2 T-070 new - --past-limit --because "the test waits for the screen now"
round "after passes on the same work the same end through changes is the loop's the first time" \
  6 "STOPPED — T-070 ended the same way in 3 runs in a row, each after a change of the work; "\
"nothing ran." T-070 new -
never_says "a retry passed before makes it no question" "the user" "$WORK/run.log"
# End-to-end tests that ran and failed the same way through changes are read as red gates
# are: the script cannot tell a device that went away under them from the code, so the
# first time the loop finds the cause, and after its reason three more are the user's. A
# harness that ran no test checked nothing: that is the loop's to restore, every time.
green_gates
no_device='<testsuite hostname="app"><testcase classname="AnswerE2E" name="shows42">'\
'<failure message="no device"/></testcase><testcase classname="AnswerE2E" name="starts"/>'\
'</testsuite>'
for attempt in first second third; do
  E2E_XML="$no_device" E2E_EXIT=1 on_the_way 2 T-085 new -
done
round "end-to-end tests that failed the same way through changes of the work stop the fourth run" \
  6 "STOPPED — T-085 ended the same way in 3 runs in a row, each after a change" \
  T-085 new -
says "it names the tests that stayed red" \
  "   end-to-end tests red: app: .review/e2e.sh exited 1; app: failed: AnswerE2E.shows42" \
  "$WORK/run.log"
says "tests that ran and failed are the loop's to find the cause of, the first time" \
  "   The loop goes on: the changes between those runs did not move it" "$WORK/run.log"
never_says "a device that went away under the tests is no question" "the user" "$WORK/run.log"
E2E_XML="$no_device" E2E_EXIT=1 on_the_way 2 T-085 same - --past-limit \
  --because "the emulator had gone away and is booted again"
for attempt in first second third; do
  E2E_XML="$no_device" E2E_EXIT=1 on_the_way 2 T-085 new -
done
round "the same tests red three more times after the loop's reason are the user's" 6 \
  "NOT CONVERGING — T-085 ended the same way in 3 more runs in a row, each after a change" \
  T-085 new -
says "tests that stayed red through the cause the loop found do not converge" \
  "   For the user, the work does not converge: the same check stayed red through the cause "\
"the loop found and 3 more fixes" "$WORK/run.log"
for attempt in first second third; do
  E2E_ONLY=none E2E_EXIT=1 on_the_way 1 T-086 new -
done
round "a harness that ran no test three times is no circle of the work, though it changed" 6 \
  "STOPPED — T-086 ended the same way in 3 runs in a row; nothing ran." T-086 new -
says "it says that no test ran" \
  "   no end-to-end test ran: app: the e2e run ran no test (exit 1)" "$WORK/run.log"
says "and that is the loop's to restore" "   The loop goes on: a retry does not mend it" \
  "$WORK/run.log"
never_says "a device that never ran a test is no question" "the user" "$WORK/run.log"
for seconds in 6 7 9; do
  red_gates "BUILD FAILED in ${seconds}s"
  on_the_way 2 T-071 new -
done
round "numbers alone do not make another output" 6 "STOPPED — T-071 ended the same way" \
  T-071 new -
for output in "a is undefined" "b is undefined" "c is undefined"; do
  red_gates "$output"
  on_the_way 2 T-072 new -
done
red_gates "d is undefined"
round "another output each time is no circle" 2 "GATES RED" T-072 new -
limit_is 3
for output in "a is undefined" "b is undefined" "c is undefined"; do
  red_gates "$output"
  on_the_way 2 T-073 new -
done
round "as many runs in a row with no review stop the task" 6 \
  "LIMIT OF RUNS — the last 3 runs of T-073 made no review (ASK_AFTER_RUNS=3); nothing ran." \
  T-073 new -
says "it says how each ended" \
  "   how they ended, oldest first: gates red; gates red; gates red" "$WORK/run.log"
says "and the loop looks for what they share" \
  "   The loop goes on: find what they share before another run" "$WORK/run.log"
round "that stop too needs the loop's reason" 1 "--past-limit at this stop needs --because" \
  T-073 same - --past-limit
# A run made before review.sh recorded how a run ends is read from what it left.
for meta in .review/runs/*/meta.json; do
  jq 'del(.end, .exit, .stage, .past_limit_kind, .stop, .because, .user_decided)' "$meta" \
    >"$meta.old" && mv "$meta.old" "$meta"
done
round "runs made before their end was recorded are read from what they left" 6 \
  "   how they ended, oldest first: gates red; gates red; gates red" T-073 same -
round "and so are their reviews" 6 "was accepted in 3 reviews in a row" T-065 same 14
green_gates
limit_is 100

# A run folder that cannot be read is never read as no run; the flags that pass a stop go
# with --past-limit alone.
mkdir -p .review/runs/unreadable && printf '{' >.review/runs/unreadable/meta.json
round "a meta.json that cannot be read stops the count" 1 \
  ".review/runs/unreadable/meta.json is not readable — the runs of a task are read from" \
  T-060 same -
printf '' >.review/runs/unreadable/meta.json
round "nor is an empty one read as no run" 1 \
  ".review/runs/unreadable/meta.json is not readable" T-060 same -
rm -r .review/runs/unreadable
round "--because without --past-limit is a usage error" 1 "--because goes with --past-limit" \
  T-060 same - --because "it moves"
round "an empty --because without --past-limit is one too" 1 \
  "--because goes with --past-limit" T-060 same - --because ""
round "and so is --user-decided" 1 "--user-decided goes with --past-limit" \
  T-060 same - --user-decided

# A case of /qa in a circle. review.sh reads the /qa records of the task too, and counts as
# pr-post.sh qa does: a case the newest /qa failed that has failed on three works, each
# after a fix, stops the task, and that is the user's. Once they decided to go on the
# reviews run until the next /qa: one that fails the case again brings the stop back, one
# that does not ends it.
failing() { printf '{"failures": [{"case": "%s"}], "work": "%s"}' "$1" "$2"; }
qa_record T-074 w1 "$(failing TC-001 w1)"
qa_record T-074 w2 "$(failing TC-001 w2)"
round "a case that failed in two /qa after a fix does not stop the task" 0 "CLEAN" T-074 new -
qa_record T-074 w3 "$(failing TC-001 w3)"
runs_before="$(ls .review/runs | wc -l)"
round "a case that failed in three /qa, each on other work, stops it" 6 \
  "NOT CONVERGING — the fixes of T-074 do not close a case of /qa; nothing ran." T-074 new -
says "the stop says in which /qa the case failed" \
  "   TC-001 failed in 3 /qa of this task, each on other work: 0-qa-T-074-w1, "\
"0-qa-T-074-w2, 0-qa-T-074-w3" \
  "$WORK/run.log"
says "and where what the case expects is written" \
  "   what it expects: qa/test-cases.md:5; what /qa saw each time: the report.md of each" \
  "$WORK/run.log"
says "a case in a circle is the user's" \
  "   For the user, the work does not converge: TC-001 failed again after each of 2 fixes" \
  "$WORK/run.log"
says "it says what they decide" \
  "whether to go on trying, to stop the task here, or to change what the case expects" \
  "$WORK/run.log"
says "and the way on once they decided" "--past-limit --user-decided then runs once more" \
  "$WORK/run.log"
if [ "$(ls .review/runs | wc -l)" -eq "$runs_before" ]; then
  echo "ok    the stop of a case leaves no run behind"
else
  echo "FAIL  the stop of a case left a run directory behind"
  FAILURES=$((FAILURES + 1))
fi
round "--past-limit alone does not pass the stop of a case" 1 "this stop takes --user-decided" \
  T-074 same - --past-limit
round "nor does the loop's own reason" 1 "this stop takes --user-decided" \
  T-074 same - --past-limit --because "the next fix closes it"
round "once the user decided to go on the review runs" 0 "CLEAN" \
  T-074 same - --past-limit --user-decided
run_records "and the run records which stop they passed" \
  '.stop == "case" and .user_decided == true and .past_limit_kind == "user"'
round "and the reviews run again until the next /qa" 0 "CLEAN" T-074 new -
qa_record T-074 w4 "$(failing TC-001 w4)"
round "a later /qa that fails the case again stops the task again" 6 \
  "   TC-001 failed in 4 /qa of this task, each on other work: " T-074 new -
qa_record T-074 w5 '{"failures": [], "work": "w5"}'
round "a later /qa that passes it lifts the stop" 0 "CLEAN" T-074 new -

qa_record T-075 a "$(failing TC-001 w1)"
qa_record T-075 b "$(failing TC-002 w2)"
qa_record T-075 c "$(failing TC-001 w3)"
qa_record T-075 d "$(failing TC-002 w4)"
round "two cases that failed in turn, twice each, do not stop the task" 0 "CLEAN" T-075 new -
qa_record T-075 e "$(failing TC-001 w5)"
round "two cases that fail in turn are read too" 6 \
  "   TC-001 failed in 3 /qa of this task, each on other work: 0-qa-T-075-a, 0-qa-T-075-c, "\
"0-qa-T-075-e" \
  T-075 new -

# No fix lies between two /qa of the same work, and a record that does not say which work
# it checked is not known to be of other work: neither makes a circle.
for name in first second third; do qa_record T-076 "$name" "$(failing TC-001 w1)"; done
round "a case that failed in three /qa of unchanged work is no circle" 0 "CLEAN" T-076 new -
for name in first second third; do
  qa_record T-077 "$name" '{"failures": [{"case": "TC-001"}]}'
done
round "three /qa that do not say which work they checked stop no review" 0 "CLEAN" T-077 new -

# The decision to go on is taken at one stop. A finding in a circle is read first; the
# user's decision on it is none on the case, which the next run reads.
on_the_way 3 T-078 new 10
on_the_way 3 T-078 new 10
on_the_way 3 T-078 new 10
for work in w1 w2 w3; do qa_record T-078 "$work" "$(failing TC-002 "$work")"; done
round "a finding in a circle is read before a case in a circle" 6 \
  "NOT CONVERGING — the fixes of T-078 do not close a finding of the review" T-078 same -
on_the_way 0 T-078 same - --past-limit --user-decided
round "the decision to go on at another stop does not pass the stop of a case" 6 \
  "NOT CONVERGING — the fixes of T-078 do not close a case of /qa" T-078 same -

# A /qa record that does not hold, or cannot be read, is never read as no failure.
qa_record T-079 w1 "$(failing TC-001 w1)"
qa_record T-079 items \
  "{\"counts\": {\"pass\": 3}, \"failures\": [], \"items\": [$two_passes]}"
runs_before="$(ls .review/runs | wc -l)"
round "a /qa record that does not hold stops the run and says so" 1 \
  "its items do not hold; the line before this one says what" T-079 new -
says "the line before says what does not hold" \
  ".review/runs/0-qa-T-079-items/qa.json: 2 item(s) say pass and counts.pass is 3" "$WORK/run.log"
says "and that nothing ran" "nothing ran" "$WORK/run.log"
if [ "$(ls .review/runs | wc -l)" -eq "$runs_before" ]; then
  echo "ok    a /qa record that does not hold leaves no run behind"
else
  echo "FAIL  a /qa record that does not hold left a run directory behind"
  FAILURES=$((FAILURES + 1))
fi
printf '{' >.review/runs/0-qa-T-079-items/qa.json
round "a /qa record that is no JSON stops the run too" 1 \
  "the /qa records of T-079 could not be read" T-079 new -
says "the line before names the record and says what to do with it" \
  "   .review/runs/0-qa-T-079-items/qa.json is not readable — the /qa records of a task are "\
"read from these files: repair it or remove that folder" "$WORK/run.log"
printf '{' >.review/runs/0-qa-T-079-items/qa.json.other
mkdir -p .review/runs/0-qa-other-task
mv .review/runs/0-qa-T-079-items/qa.json.other .review/runs/0-qa-other-task/qa.json
rm .review/runs/0-qa-T-079-items/qa.json
round "a record that cannot be read may be another task's: the line says which file it is" 1 \
  "   .review/runs/0-qa-other-task/qa.json is not readable — the /qa records of a task are " \
  T-079 new -
rm -r .review/runs/0-qa-other-task
rm -r .review/runs/0-qa-T-079-items
round "with the record gone the review runs" 0 "CLEAN" T-079 new -

# Runs of a task that landed are not read as the runs of a new task under the same id. The
# tree records that a landing committed with its review: a commit that carries the trailer
# Task-Id and names the review — Review-Run, which land.sh writes below the pull request
# levels, or Review-Runs, on the squash of a pull request. The runs and the /qa records of
# an id are read from the newest such commit on. `landed <task>` makes that commit, as
# land.sh writes it, of the tree as it is committed; with `no-review` it names no review,
# as a commit of land.sh on the branch of a pull request. A commit records its time in
# whole seconds, so the second it was made in is let pass.
landed() {
  local trailers="Task-Id: $1
Gates: test=pass"
  [ "${2:-}" = no-review ] || trailers="$trailers
Review-Run: $(basename "$(newest_run)") (local)"
  git update-ref HEAD \
    "$(git commit-tree -p HEAD -m "$1: Pickup" -m "$trailers" 'HEAD^{tree}')" \
    || fail_setup "the landing of $1"
  sleep 1
}
limit_is 2
on_the_way 0 T-094 new -
on_the_way 0 T-094 new -
on_the_way 6 T-094 new -
landed T-094
round "a task that takes the id of one that landed has its own count of reviews" 0 "CLEAN" \
  T-094 new -
run_records "its first review is the first of its count" '.count == 1 and .epoch == 0'
on_the_way 0 T-094 new -
round "and its own limit" 6 \
  "LIMIT OF REVIEWS — T-094 has had 2 reviews since the count started, 2 runs in all" T-094 new -
limit_is 100
on_the_way 3 T-091 new 10
on_the_way 3 T-091 new 10
landed T-091
round "a finding where the task that landed had one is the first of the new task" 3 \
  "accepted (>= major): 1" T-091 new 10
never_says "it did not come back: what was fixed before the landing was another task" \
  "again after a change" "$WORK/run.log"
round "the same finding after a fix of the new task came back once" 3 \
  "   a third time in a row review.sh stops (maintain, step 5)" T-091 new 10
for work in w1 w2 w3; do qa_record T-092 "$work" "$(failing TC-001 "$work")"; done
on_the_way 6 T-092 new -
landed T-092
qa_record T-092 new "$(failing TC-001 n1)"
round "a case that failed in the /qa of a task that landed has failed once in the new task" \
  0 "CLEAN" T-092 new -
qa_says "the print after /qa counts the /qa of the new task alone" 0 "   TC-001 failed" \
  .review/runs/0-qa-T-092-new
never_says "so the case failed once" "it failed in" "$WORK/post.log"
never_says "and that is no question" "the user" "$WORK/post.log"
# What does not record that a landing committed with its review: a commit that names no
# review, and the landing of a task whose id only begins with this one.
limit_is 2
on_the_way 0 T-093 new -
on_the_way 0 T-093 new -
landed T-093 no-review
round "a commit that names no review, as land.sh makes on a pull request, ends no task" 6 \
  "LIMIT OF REVIEWS — T-093 has had 2 reviews since the count started, 2 runs in all" T-093 new -
landed T-0931
round "nor does the landing of a task whose id begins with this one" 6 \
  "LIMIT OF REVIEWS — T-093 has had 2 reviews since the count started, 2 runs in all" T-093 new -
rm src/pickup.kt src/fix.kt
cp "$WORK/land.conf.before-rounds" .review/land.conf

# Last in this repository, since it commits: the harness as a link to a file in
# the reviewed tree.
new_task T-013
mkdir -p scripts
cp .review/e2e.sh scripts/e2e.sh
rm .review/e2e.sh
ln -s ../scripts/e2e.sh .review/e2e.sh
git add scripts/e2e.sh .review/e2e.sh \
  && git commit -q -m "the harness behind a link" -- scripts/e2e.sh .review/e2e.sh \
  || fail_setup "link commit"
e2e_review "a run through a harness committed as a link goes on" 0 "CLEAN — gates green" \
  .review/T-013.json
e2e_land "a harness committed as a link lands" 0 "For the user to commit" .review/T-013.json \
  "$last_run"

# ---------------------------------------------------------------------------
# Publishing. Each project has a bare repository as its remote; gh is a stand-in
# that logs its calls to calls, keeps the pull requests as JSON in prs.json, the
# statuses posted in statuses.json and every comment and review in comments.json,
# and answers as the files next to them say. It answers with the fields --json asks
# for, and acts only on the repository --repo names, as real gh does with the flag,
# or gh api its path. A gh api whose path matches the pattern in api-fails does not
# reach GitHub: it prints gh's line for that and exits 1. So does one that only reads and
# whose path matches the pattern in api-read-fails, where a post would still arrive. With
# checks-fail neither gh pr checks nor a gh pr view that asks for statusCheckRollup
# reaches it; with `pr checks` in that file, gh pr checks alone does not. The line
# `unread` of the file checks is one gh pr checks that does not reach it. With offline no
# call reaches it.
# ---------------------------------------------------------------------------

# A PATH with no <tool> on it, whatever this machine has installed: path_without <tool>. A
# folder that holds the tool is copied without it, and a folder that is on PATH twice once.
path_without() {
  local tool="$1" directory copy found path=""
  while IFS= read -r directory; do
    if [ -e "$directory/$tool" ]; then
      copy="$WORK/no-$tool/$(printf '%s' "$directory" | tr '/' '_')"
      if [ ! -d "$copy" ]; then
        mkdir -p "$copy" || fail_setup "no-$tool folder"
        for found in "$directory"/*; do
          [ "$(basename "$found")" = "$tool" ] || ln -s "$found" "$copy/" || \
            fail_setup "no-$tool link"
        done
      fi
      directory="$copy"
    fi
    path="$path${path:+:}$directory"
  done < <(printf '%s' "$PATH" | tr ':' '\n')
  printf '%s' "$path"
}
path_without_gh="$(path_without gh)"
[ -n "$path_without_gh" ] || fail_setup "a PATH without gh"

mkdir -p "$WORK/gh-bin"
cat >"$WORK/gh-bin/gh" <<'EOF'
#!/usr/bin/env bash
export GIT_AUTHOR_NAME=gh GIT_AUTHOR_EMAIL=gh@example.com \
  GIT_COMMITTER_NAME=gh GIT_COMMITTER_EMAIL=gh@example.com
printf '%s\n' "$*" >>"$GH_STATE/calls"
# offline: GitHub gives no answer to any call.
if [ -e "$GH_STATE/offline" ]; then
  echo "error connecting to api.github.com" >&2
  exit 1
fi
PRS="$GH_STATE/prs.json"
STATUSES="$GH_STATE/statuses.json"
COMMENTS="$GH_STATE/comments.json"
for state in "$PRS" "$STATUSES" "$COMMENTS"; do
  [ -e "$state" ] || printf '[]' >"$state"
done

flag() {
  local name="$1"; shift
  while [ $# -gt 0 ]; do
    if [ "$1" = "$name" ]; then printf '%s' "${2:-}"; return 0; fi
    shift
  done
  return 1
}

fields() {
  jq --arg fields "$(flag --json "$@")" '
    def pick: . as $record | ($fields | split(",") | map({(.): $record[.]}) | add);
    if type == "array" then map(pick) else pick end'
}

# A number selects that pull request, whatever a branch is called.
find_pr() {
  jq -c --arg selector "$1" '
    [.[] | select(if ($selector | test("^[0-9]+$")) then .number == ($selector | tonumber)
                  elif ($selector | test("^https://")) then .url == $selector
                  else .headRefName == $selector end)] | last // empty' "$PRS"
}

update_json() {
  local file="$1" updated
  shift
  updated="$(jq "$@" "$file")" && printf '%s' "$updated" >"$file"
}

update_prs() { update_json "$PRS" "$@"; }

set_pr() {
  update_prs --argjson number "$1" "map(if .number == \$number then $2 else . end)"
}

current_heads() {
  local number head oid
  for number in $(jq -r '.[] | select(.state == "OPEN") | .number' "$PRS"); do
    head="$(jq -r --argjson number "$number" \
      '.[] | select(.number == $number) | .headRefName' "$PRS")"
    oid="$(git -C "$GH_REMOTE" rev-parse --verify --quiet "refs/heads/$head")" &&
      set_pr "$number" ".headRefOid = \"$oid\""
  done
}

someone_pushes() {
  local head="refs/heads/$1"
  git -C "$GH_REMOTE" update-ref "$head" \
    "$(git -C "$GH_REMOTE" commit-tree "$head^{tree}" -p "$head" -m "someone else")"
}

next_id() { jq '[.[].id] | (max // 99) + 1' "$COMMENTS"; }

# What says which checks a pull request has: its own word, or the first line of the file
# checks.
checks_word() {
  local word
  word="$(find_pr "$1" | jq -r '.checks // empty')"
  [ -n "$word" ] || word="$(head -1 "$GH_STATE/checks")"
  printf '%s' "$word"
}

# The checks a pull request reports now, as gh pr checks lists them and as gh pr view
# gives them in statusCheckRollup.
checks_of() {
  local checks
  case "$(checks_word "$1")" in
    passed) checks='[{"name":"build","bucket":"pass"}]' ;;
    skipped) checks='[{"name":"build","bucket":"pass"},{"name":"docs","bucket":"skipping"}]' ;;
    pending) checks='[{"name":"build","bucket":"pass"},{"name":"test","bucket":"pending"}]' ;;
    failing) checks='[{"name":"build","bucket":"fail"}]' ;;
    cancelled) checks='[{"name":"build","bucket":"cancel"}]' ;;
    cancelled+pending)
      checks='[{"name":"build","bucket":"cancel"},{"name":"test","bucket":"pending"}]' ;;
    unknown) checks='[{"name":"build","bucket":"neutral"}]' ;;
    # A failing check beside one whose description holds the words gh has for "none".
    word) checks='[{"name":"build","bucket":"fail","description":"1 test failed"},
                   {"name":"lint","bucket":"pass",
                    "description":"no checks reported for Kotlin sources"}]' ;;
    *) checks='[]' ;;
  esac
  # The statuses posted at the head of the pull request are checks of it too, the
  # newest of each context.
  current_heads
  jq -c --argjson checks "$checks" --arg head "$(find_pr "$1" | jq -r .headRefOid)" '
    $checks + ([.[] | select(.sha == $head)] | group_by(.context) | map(last)
      | map({name: .context, description,
             bucket: ({success: "pass", failure: "fail", error: "fail"}[.state]
                      // "pending")}))' "$STATUSES"
}

case "$1 $2" in
  "auth status") [ ! -e "$GH_STATE/logged-out" ]; exit ;;
  "repo view") [ ! -e "$GH_STATE/no-repo" ]; exit ;;
esac

# gh api names the repository in its path, repos/<owner>/<repository>/..., and has no
# --repo; the rest of the path says what is asked.
if [ "$1" = api ]; then
  # down-at-api: GitHub gives no answer from the first gh api call on.
  if [ -e "$GH_STATE/down-at-api" ]; then
    rm "$GH_STATE/down-at-api"
    touch "$GH_STATE/offline"
    echo "error connecting to api.github.com" >&2
    exit 1
  fi
  if [ -e "$GH_STATE/api-fails" ] &&
     printf '%s' "$2" | grep -Eq -- "$(cat "$GH_STATE/api-fails")"; then
    echo "error connecting to api.github.com" >&2
    exit 1
  fi
  if [ -e "$GH_STATE/api-read-fails" ] && ! flag --method "$@" >/dev/null &&
     printf '%s' "$2" | grep -Eq -- "$(cat "$GH_STATE/api-read-fails")"; then
    echo "error connecting to api.github.com" >&2
    exit 1
  fi
  if [ "$(printf '%s' "$2" | cut -d/ -f3)" != "$(basename "$GH_REMOTE" .git)" ]; then
    echo "gh: Not Found (HTTP 404)" >&2
    exit 1
  fi
  rest="$(printf '%s' "$2" | cut -d/ -f4-)"
  number="$(printf '%s' "$rest" | cut -d/ -f2)"
  input="$(flag --input "$@")"
  case "$(flag --method "$@" || echo GET) $rest" in
    "POST statuses/"*)
      update_json "$STATUSES" --arg sha "${rest#statuses/}" --slurpfile input "$input" \
        '. + [$input[0] + {sha: $sha}]'
      echo '{"id": 1}' ;;
    "POST pulls/"*"/reviews")
      if [ -e "$GH_STATE/review-422" ] && [ "$(jq '.comments | length' "$input")" -gt 0 ]; then
        echo '{"message": "Unprocessable Entity"}'
        echo "gh: Unprocessable Entity (HTTP 422)" >&2
        exit 1
      fi
      id="$(next_id)"
      update_json "$COMMENTS" --slurpfile input "$input" --argjson id "$id" \
        --argjson pr "$number" '
        . + [{id: $id, node_id: "PRR_\($id)", kind: "review", pr: $pr, state: "COMMENTED",
              body: $input[0].body, commit_id: $input[0].commit_id}]
          + [$input[0].comments // [] | to_entries[]
             | {id: ($id + 1 + .key), node_id: "PRRC_\($id + 1 + .key)", kind: "line",
                pr: $pr, review_id: $id, body: .value.body, path: .value.path,
                line: .value.line}]'
      printf '{"id": %s}\n' "$id" ;;
    "POST pulls/"*"/comments/"*"/replies")
      # GitHub takes a reply only to the first comment of a thread.
      if jq -e --argjson to "$(printf '%s' "$rest" | cut -d/ -f4)" \
           'any(.[]; .id == $to and .in_reply_to_id != null)' "$COMMENTS" >/dev/null; then
        echo '{"message": "Validation Failed"}'
        echo "gh: Validation Failed (HTTP 422)" >&2
        exit 1
      fi
      id="$(next_id)"
      update_json "$COMMENTS" --slurpfile input "$input" --argjson id "$id" \
        --argjson pr "$number" --argjson to "$(printf '%s' "$rest" | cut -d/ -f4)" '
        . + [{id: $id, node_id: "PRRC_\($id)", kind: "line", pr: $pr, in_reply_to_id: $to,
              body: $input[0].body}]'
      printf '{"id": %s}\n' "$id" ;;
    "POST issues/"*"/comments")
      id="$(next_id)"
      update_json "$COMMENTS" --slurpfile input "$input" --argjson id "$id" \
        --argjson pr "$number" '
        . + [{id: $id, node_id: "IC_\($id)", kind: "issue", pr: $pr, body: $input[0].body}]'
      printf '{"id": %s}\n' "$id" ;;
    "GET pulls/"*"/reviews/"*"/comments")
      jq --argjson review "$(printf '%s' "$rest" | cut -d/ -f4)" \
        '[.[] | select(.kind == "line" and .review_id == $review)]' "$COMMENTS" ;;
    "GET pulls/"*"/reviews")
      jq --argjson pr "$number" '[.[] | select(.kind == "review" and .pr == $pr)]' "$COMMENTS" ;;
    "GET pulls/"*"/comments")
      jq --argjson pr "$number" '[.[] | select(.kind == "line" and .pr == $pr)]' "$COMMENTS" ;;
    "GET issues/"*"/comments")
      jq --argjson pr "$number" '[.[] | select(.kind == "issue" and .pr == $pr)]' "$COMMENTS" ;;
    *) echo "gh: Not Found (HTTP 404): $*" >&2; exit 1 ;;
  esac
  exit
fi

repository="$(flag --repo "$@")"
if [ "${repository##*/}" != "$(basename "$GH_REMOTE" .git)" ]; then
  echo "no pull requests in '$repository'" >&2
  exit 1
fi

case "$1 $2" in
  "pr list")
    [ ! -e "$GH_STATE/list-fails" ] || { echo "could not reach the server" >&2; exit 1; }
    current_heads
    jq --arg head "$(flag --head "$@")" --arg base "$(flag --base "$@")" \
      --arg state "$(flag --state "$@" || echo open)" '
      [.[] | select(.headRefName == $head and ($base == "" or .baseRefName == $base)
                    and ($state == "all" or .state == ($state | ascii_upcase)))] | reverse' \
      "$PRS" | fields "$@" ;;
  "pr create")
    [ ! -e "$GH_STATE/create-fails" ] || { echo "the server said no" >&2; exit 1; }
    head="$(flag --head "$@")"
    base="$(flag --base "$@")"
    oid="$(git -C "$GH_REMOTE" rev-parse --verify --quiet "refs/heads/$head")" ||
      { echo "no such head" >&2; exit 1; }
    git -C "$GH_REMOTE" rev-parse --verify --quiet "refs/heads/$base" >/dev/null ||
      { echo "no such base" >&2; exit 1; }
    if [ -n "$(jq -r --arg head "$head" --arg base "$base" \
         '.[] | select(.state == "OPEN" and .headRefName == $head and .baseRefName == $base
                       and (.isCrossRepository | not)) | .url' "$PRS")" ]; then
      echo "a pull request for that branch already exists" >&2
      exit 1
    fi
    body="$(flag --body "$@")" || body="$(cat "$(flag --body-file "$@")")"
    number="$(($(jq length "$PRS") + 1))"
    url="https://example.test/pull/$number"
    update_prs --arg url "$url" --arg head "$head" --arg base "$base" --arg oid "$oid" \
      --argjson number "$number" --arg title "$(flag --title "$@")" --arg body "$body" \
      '. + [{number: $number, url: $url, state: "OPEN", headRefName: $head, baseRefName: $base,
             headRefOid: $oid, reviewDecision: "", isCrossRepository: false, title: $title,
             body: $body}]'
    printf '%s\n' "$url" ;;
  "pr edit")
    number="$(find_pr "$3" | jq -r .number)"
    update_prs --argjson number "$number" --rawfile body "$(flag --body-file "$@")" \
      'map(if .number == $number then .body = $body else . end)' ;;
  "pr view")
    [ ! -e "$GH_STATE/view-fails" ] || { echo "could not reach the server" >&2; exit 1; }
    if [ -e "$GH_STATE/pushes-at-view" ]; then
      rm "$GH_STATE/pushes-at-view"
      someone_pushes "$(find_pr "$3" | jq -r .headRefName)"
    fi
    current_heads
    record="$(find_pr "$3")"
    case ",$(flag --json "$@")," in
      *,statusCheckRollup,*)
        if [ -e "$GH_STATE/checks-fail" ] &&
           [ "$(cat "$GH_STATE/checks-fail")" != "pr checks" ]; then
          echo "error connecting to api.github.com" >&2
          exit 1
        fi
        record="$(printf '%s' "$record" | jq -c --argjson rollup "$(checks_of "$3")" \
          '. + {statusCheckRollup: $rollup}')" ;;
    esac
    printf '%s' "$record" | fields "$@" ;;
  "pr checks")
    # down-at-checks: GitHub gives no answer from this call on.
    if [ -e "$GH_STATE/down-at-checks" ]; then
      rm "$GH_STATE/down-at-checks"
      touch "$GH_STATE/offline"
      echo "error connecting to api.github.com" >&2
      exit 1
    fi
    if [ -e "$GH_STATE/pushes-at-checks" ]; then
      rm "$GH_STATE/pushes-at-checks"
      someone_pushes "$(find_pr "$3" | jq -r .headRefName)"
    fi
    answer="$(checks_word "$3")"
    checks="$(checks_of "$3")"
    # Each call takes one line of the file checks, down to its last.
    if [ -z "$(find_pr "$3" | jq -r '.checks // empty')" ]; then
      [ "$(wc -l <"$GH_STATE/checks")" -le 1 ] || sed -i.old 1d "$GH_STATE/checks"
    fi
    if [ -e "$GH_STATE/checks-fail" ] || [ "$answer" = unread ]; then
      echo "error connecting to api.github.com" >&2
      exit 1
    fi
    if [ "$checks" = "[]" ]; then
      echo "no checks reported on the 'head' branch" >&2
      exit 1
    fi
    flag --json "$@" >/dev/null ||
      { printf '%s' "$checks" | jq -r '.[] | "\(.name)\t\(.bucket)"'; exit 0; }
    printf '%s' "$checks" | fields "$@" ;;
  "pr merge")
    [ ! -e "$GH_STATE/refuses-merge" ] ||
      { echo "the base branch policy prohibits the merge" >&2; exit 1; }
    # down-at-merge: the connection goes at the merge — unsent: before it is sent;
    # unanswered: after GitHub merged, before its answer came; after: once gh answered,
    # with the remote too.
    down="$(cat "$GH_STATE/down-at-merge" 2>/dev/null)"
    rm -f "$GH_STATE/down-at-merge"
    if [ "$down" = unsent ]; then
      touch "$GH_STATE/offline"
      echo "error connecting to api.github.com" >&2
      exit 1
    fi
    record="$(find_pr "$3")"
    number="$(printf '%s' "$record" | jq -r .number)"
    head_branch="$(printf '%s' "$record" | jq -r .headRefName)"
    base_branch="$(printf '%s' "$record" | jq -r .baseRefName)"
    if [ -e "$GH_STATE/pushes-at-merge" ]; then
      rm "$GH_STATE/pushes-at-merge"
      someone_pushes "$head_branch"
    fi
    head="$(git -C "$GH_REMOTE" rev-parse "refs/heads/$head_branch")"
    match="$(flag --match-head-commit "$@")"
    if [ -n "$match" ] && [ "$match" != "$head" ]; then
      echo "the head of the pull request is not the commit asked for" >&2
      exit 1
    fi
    base="refs/heads/$base_branch"
    # A squash is one commit on the base branch, with the subject and the body given.
    case " $* " in
      *" --squash "*)
        merged="$(git -C "$GH_REMOTE" commit-tree "$head^{tree}" \
          -p "$(git -C "$GH_REMOTE" rev-parse "$base")" \
          -m "$(flag --subject "$@")" -m "$(flag --body "$@")")" ;;
      *)
        merged="$(git -C "$GH_REMOTE" commit-tree "$head^{tree}" \
          -p "$(git -C "$GH_REMOTE" rev-parse "$base")" -p "$head" -m "Merge pull request")" ;;
    esac
    git -C "$GH_REMOTE" update-ref "$base" "$merged"
    set_pr "$number" ".state = \"MERGED\" | .headRefOid = \"$head\""
    if [ -e "$GH_STATE/moves-the-checkout" ]; then
      git switch -q "$base_branch" &&
        git pull -q --ff-only "$(git remote | head -1)" "refs/heads/$base_branch"
      git branch -q -D "$head_branch"
    fi
    case "$down" in
      unanswered)
        case " $* " in
          *" --delete-branch "*) git -C "$GH_REMOTE" update-ref -d "refs/heads/$head_branch" ;;
        esac
        touch "$GH_STATE/offline"
        echo "error connecting to api.github.com" >&2
        exit 1 ;;
      after)
        git config --unset "url.$GH_REMOTE.insteadOf"
        touch "$GH_STATE/offline" ;;
    esac
    [ ! -e "$GH_STATE/fails-after-merge" ] ||
      { echo "could not tidy the local checkout" >&2; exit 1; }
    case " $* " in
      *" --delete-branch "*) git -C "$GH_REMOTE" update-ref -d "refs/heads/$head_branch" ;;
    esac ;;
esac
EOF
chmod +x "$WORK/gh-bin/gh"
# The stand-in of curl, which a script asks only after git or gh failed, to tell a host
# that gives no answer from one that refuses: it logs its calls to curl-calls and exits 0,
# an answer of the host, or 7, no connection, while the file offline is there.
mkdir -p "$WORK/curl-bin" || fail_setup "curl-bin"
cat >"$WORK/curl-bin/curl" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$GH_STATE/curl-calls"
[ ! -e "$GH_STATE/offline" ] || exit 7
exit 0
EOF
chmod +x "$WORK/curl-bin/curl" || fail_setup "curl"
export PATH="$WORK/curl-bin:$WORK/gh-bin:$PATH" GH_STATE GH_REMOTE

published_projects=0
edits=0
published_project() {
  local remote_name="$1"
  published_projects=$((published_projects + 1))
  repository="$WORK/published-$published_projects"
  GH_REMOTE="$repository.git"
  GH_STATE="$repository.gh"
  mkdir -p "$GH_STATE" "$repository/.review" "$repository/src" || fail_setup "published folders"
  printf 'passed\n' >"$GH_STATE/checks"
  printf '[]' >"$GH_STATE/prs.json"
  git init -q --bare -b main "$GH_REMOTE" || fail_setup "bare remote"
  cd "$repository" || fail_setup "cd published"
  git init -q -b main || fail_setup "published git init"
  git config user.email selftest@example.com && git config user.name selftest \
    || fail_setup "published git config"
  printf 'fun answer() = 0\n' >src/answer.kt
  cp "$WORK/e2e.green" .review/e2e.sh
  git add src/answer.kt .review/e2e.sh && git commit -q -m start \
    || fail_setup "published first commit"
  git remote add "$remote_name" "$GH_REMOTE" && git push -q "$remote_name" main \
    || fail_setup "published first push"
  cp "$WORK/gates.green" .review/gates.sh
  printf '# Review Policy\n' >.review/REVIEW_POLICY.md
  task_with_id T-001
}

task_with_id() {
  local record
  printf '{"id": "%s", "title": "Answer 42", "category": "bugfix", "scope": ["src/*"], '\
'"exit_criteria": []}' \
    "$1" >.review/task.json
  # /qa's record of the task, without which no landing of it goes through.
  record=".review/runs/0-qa-$(printf '%s' "$1" | tr -c 'A-Za-z0-9._-' _)"
  mkdir -p "$record" && jq -n --arg id "$1" '{task: $id, failures: []}' >"$record/qa.json"
}

set_level() {
  local level="$1"; shift
  printf 'THRESHOLD=major\nASK_AFTER_RUNS=100\nCHECKS_WAIT=0\nLANDING=%s\n' "$level" \
    >.review/land.conf
  [ $# -eq 0 ] || printf '%s\n' "$@" >>.review/land.conf
}

reviewed_change() {
  local runs_before
  edits=$((edits + 1))
  printf 'fun answer() = %s\n' "$edits" >src/answer.kt
  printf '{"findings":[]}' >"$WORK/reviewer.json"
  printf '{"verdicts":[]}' >"$WORK/maintainer.json"
  runs_before="$(ls .review/runs 2>/dev/null)"
  REVIEWER_CMD="cat $WORK/reviewer.json #" MAINTAINER_CMD="cat $WORK/maintainer.json #" \
    "$LIB_DIR/review.sh" --task-file .review/task.json >"$WORK/run.log" 2>&1
  run=".review/runs/$(comm -13 <(printf '%s\n' "$runs_before") <(ls .review/runs))"
}

land_run() {
  local name="$1" expected_exit="$2" expected_line="$3"; shift 3
  "$LIB_DIR/land.sh" --task-file .review/task.json --run "$run" "$@" >"$WORK/land.log" 2>&1
  check "$name" "$expected_exit" "$expected_line" $? "$WORK/land.log"
}

# At push and below the work is reviewed, then landed. At pr and merge the order is
# the other way round (TASK_LOOP.md, "The contract at the pull request levels"): the
# work, land.sh — which commits, pushes and opens the pull request — review.sh on the
# pull request, /qa, then publish.sh --check or --merge.
land_change() {
  local name="$1" expected_exit="$2" expected_line="$3" level="$4"; shift 4
  set_level "$level" "$@"
  case "$level" in
    pr | merge) pr_work; pr_land "$name" "$expected_exit" "$expected_line" ;;
    *) reviewed_change; land_run "$name" "$expected_exit" "$expected_line" ;;
  esac
}

pr_work() {
  edits=$((edits + 1))
  printf 'fun answer() = %s\n' "$edits" >src/answer.kt
}

pr_land() {
  local name="$1" expected_exit="$2" expected_line="$3"; shift 3
  "$LIB_DIR/land.sh" --task-file .review/task.json "$@" >"$WORK/land.log" 2>&1
  check "$name" "$expected_exit" "$expected_line" $? "$WORK/land.log"
}

# The record of the newest landing of the project, and what it holds: landing_records
# <name> <jq filter>.
newest_landing() {
  local record
  for record in .review/runs/land-*/landing.json; do
    [ -f "$record" ] || continue
    jq -c --arg record "$record" '{time: (.time // 0), record: $record}' "$record"
  done | jq -sr 'sort_by(.time) | last | .record'
}
landing_records() {
  local record
  record="$(newest_landing)"
  if jq -e "$2" "$record" >/dev/null 2>&1; then
    echo "ok    $1"
  else
    echo "FAIL  $1: «$2» does not hold in $record — it follows"
    sed 's/^/      /' "$record"
    FAILURES=$((FAILURES + 1))
  fi
}

# review.sh on the pull request, with the reviewer's and the maintainer's answers given,
# or none; the run it made is $run.
pr_review() {
  local name="$1" expected_exit="$2" expected_line="$3" runs_before
  local reviewer_answer="${4:-}" maintainer_answer="${5:-}"
  [ -n "$reviewer_answer" ] || reviewer_answer='{"findings":[]}'
  [ -n "$maintainer_answer" ] || maintainer_answer='{"verdicts":[]}'
  printf '%s' "$reviewer_answer" >"$WORK/reviewer.json"
  printf '%s' "$maintainer_answer" >"$WORK/maintainer.json"
  runs_before="$(ls .review/runs 2>/dev/null)"
  REVIEWER_CMD="cat $WORK/reviewer.json #" MAINTAINER_CMD="cat $WORK/maintainer.json #" \
    "$LIB_DIR/review.sh" --task-file .review/task.json >"$WORK/run.log" 2>&1
  check "$name" "$expected_exit" "$expected_line" $? "$WORK/run.log"
  run=".review/runs/$(comm -13 <(printf '%s\n' "$runs_before") <(ls .review/runs) | tail -1)"
}

# /qa on the pull request: its record, of the work as it is and since the merge base of
# the newest run, and its report, posted with pr-post.sh qa. qa_recorded [<failures>]
# [<since>] [<unproven>] [<more>] writes the two into $qa_folder, <more> being a JSON
# object merged into the record; qa_checked posts the report too.
qa_runs=0
qa_recorded() {
  local more="${4:-}"
  [ -n "$more" ] || more='{}'
  qa_runs=$((qa_runs + 1))
  qa_folder=".review/runs/qa-$qa_runs"
  mkdir -p "$qa_folder"
  jq -n --arg task "$(jq -r .id .review/task.json)" --arg head "$(git rev-parse HEAD)" \
    --arg work "$(. "$LIB_DIR/common.sh" && tree_fingerprint)" \
    --arg since "${2:-$(jq -r '.merge_base' "$run/meta.json")}" --argjson failures "${1:-[]}" \
    --argjson more "$more" \
    '{task: $task, time: now, head: $head, work: $work, since: $since, extent: "full",
      reason: "the first /qa of the pull request",
      counts: {pass: 3, fail: ($failures | length), unproven: '"${3:-0}"', not_checked: 0},
      failures: $failures} + $more' >"$qa_folder/qa.json"
  printf '# /qa\n\nEvery case it can reach passed.\n' >"$qa_folder/report.md"
}
qa_checked() {
  qa_recorded "$@"
  step "/qa posts its report" "$WORK/qa.log" "$LIB_DIR/pr-post.sh" qa "$qa_folder"
}

# A step a case needs on its way, which must succeed; a failure is printed and counted.
step() {
  local name="$1" log="$2"
  shift 2
  "$@" >"$log" 2>&1 && return 0
  echo "FAIL  $name: '$*' failed — log follows"
  sed 's/^/      /' "$log"
  FAILURES=$((FAILURES + 1))
  return 1
}

# The task through its pull request up to the merge: the work, the landing, a clean
# review and /qa.
reviewed_pull_request() {
  local level="$1"; shift
  set_level "$level" "$@"
  pr_work
  step "the landing of the work" "$WORK/land.log" \
    "$LIB_DIR/land.sh" --task-file .review/task.json || return 1
  pr_review_quietly && qa_checked
}

pr_review_quietly() {
  local runs_before
  printf '{"findings":[]}' >"$WORK/reviewer.json"
  printf '{"verdicts":[]}' >"$WORK/maintainer.json"
  runs_before="$(ls .review/runs 2>/dev/null)"
  step "the review of the pull request" "$WORK/run.log" env \
    REVIEWER_CMD="cat $WORK/reviewer.json #" MAINTAINER_CMD="cat $WORK/maintainer.json #" \
    "$LIB_DIR/review.sh" --task-file .review/task.json
  local reviewed=$?
  run=".review/runs/$(comm -13 <(printf '%s\n' "$runs_before") <(ls .review/runs) | tail -1)"
  return "$reviewed"
}

merged_change() {
  local name="$1" expected_exit="$2" expected_line="$3"; shift 3
  reviewed_pull_request merge "$@"
  publish "$name" "$expected_exit" "$expected_line" --merge
}

publish() {
  local name="$1" expected_exit="$2" expected_line="$3"; shift 3
  "$LIB_DIR/publish.sh" --task-file .review/task.json "$@" >"$WORK/publish.log" 2>&1
  check "$name" "$expected_exit" "$expected_line" $? "$WORK/publish.log"
}

pr_post() {
  local name="$1" expected_exit="$2" expected_line="$3"; shift 3
  "$LIB_DIR/pr-post.sh" "$@" >"$WORK/post.log" 2>&1
  check "$name" "$expected_exit" "$expected_line" $? "$WORK/post.log"
}

holds() {
  local name="$1"; shift
  if "$@"; then
    echo "ok    $name"
  else
    echo "FAIL  $name"
    FAILURES=$((FAILURES + 1))
  fi
}

not() { ! "$@"; }
jq_true() { jq -e "$@" >/dev/null; }
landing_ran() { ls -d .review/runs/land-* >/dev/null 2>&1; }
on_branch() { [ "$(git branch --show-current)" = "$1" ]; }
remote_has() { git -C "$GH_REMOTE" show-ref --verify --quiet "refs/heads/$1"; }
local_has() { git show-ref --verify --quiet "refs/heads/$1"; }
tip_of() { git rev-parse "refs/heads/$1"; }
remote_is() { [ "$(git -C "$GH_REMOTE" rev-parse "refs/heads/$1")" = "$2" ]; }
remote_log_has() { git -C "$GH_REMOTE" log "refs/heads/$1" --format=%B \
  | grep -F -- "$2" >/dev/null; }
remote_file_has() { git -C "$GH_REMOTE" show "refs/heads/$1:$2" | grep -F -- "$3" >/dev/null; }
gh_called() { grep -qF -- "$1" "$GH_STATE/calls" 2>/dev/null; }
gh_count_is() { [ "$(grep -cF -- "$1" "$GH_STATE/calls" 2>/dev/null)" -eq "$2" ]; }
gh_call_without_repository() {
  grep -E '^pr ' "$GH_STATE/calls" | grep -vF -- --repo >/dev/null ||
    grep -E '^api ' "$GH_STATE/calls" | grep -vE '^api repos/[^/ ]+/[^/ ]+/' >/dev/null
}
printed() { grep -qF -- "$1" "$WORK/land.log" "$WORK/publish.log" 2>/dev/null; }
# The newest status of a context at HEAD, as the stand-in of gh keeps them.
status_is() {
  [ "$(jq -r --arg sha "$(git rev-parse HEAD)" --arg context "$1" \
    '[.[] | select(.sha == $sha and .context == $context)] | last | .state // "none"' \
    "$GH_STATE/statuses.json")" = "$2" ]
}
# Whether the newest status of a context at HEAD says a text.
status_says() {
  jq_true --arg sha "$(git rev-parse HEAD)" --arg context "$1" --arg text "$2" \
    '[.[] | select(.sha == $sha and .context == $context)] | last | .description
     | contains($text)' "$GH_STATE/statuses.json"
}
posted() { jq_true --arg text "$1" 'any(.[]; .body | contains($text))' \
  "$GH_STATE/comments.json" >/dev/null; }
posted_count_is() {
  [ "$(jq --arg text "$1" '[.[] | select(.body | contains($text))] | length' \
    "$GH_STATE/comments.json")" -eq "$2" ]
}

# What a person does on the pull request, which the loop only reads.
on_pull_request() {
  local updated
  updated="$(jq --argjson number "$1" "map(if .number == \$number then $2 else . end)" \
    "$GH_STATE/prs.json")" \
    && printf '%s' "$updated" >"$GH_STATE/prs.json"
}
merged_by_a_person() {
  gh pr merge "$1" --repo "x/$(basename "$GH_REMOTE" .git)" --squash --subject "by a person" \
    --body "$(jq -r --arg url "$1" '.[] | select(.url == $url) | .body' "$GH_STATE/prs.json")" \
    --delete-branch
}
a_person_comments() {
  local updated
  updated="$(jq --arg body "$1" '. + [{id: (1000 + length), node_id: "IC_\(1000 + length)",
    kind: "issue", pr: 1, body: $body}]' "$GH_STATE/comments.json")" \
    && printf '%s' "$updated" >"$GH_STATE/comments.json"
}
a_person_comments_on_line() {
  local updated
  updated="$(jq --arg path "$1" --argjson line "$2" --arg body "$3" '
    . + [{id: (1000 + length), node_id: "PRRC_\(1000 + length)", kind: "line", pr: 1,
          path: $path, line: $line, body: $body}]' "$GH_STATE/comments.json")" \
    && printf '%s' "$updated" >"$GH_STATE/comments.json"
}
a_person_reviews_with() {
  local updated
  updated="$(jq --arg body "$1" '. + [{id: (1000 + length), node_id: "PRR_\(1000 + length)",
    kind: "review", pr: 1, user: {login: "reviewer", type: "User"}, state: "COMMENTED",
    body: $body}]' "$GH_STATE/comments.json")" \
    && printf '%s' "$updated" >"$GH_STATE/comments.json"
}
# A person's answer inside the thread of the comment <id>, on its line.
a_person_answers_in_thread() {
  local updated
  updated="$(jq --argjson to "$1" --arg body "$2" '
    (.[] | select(.id == $to)) as $root
    | . + [{id: (1000 + length), node_id: "PRRC_\(1000 + length)", kind: "line", pr: 1,
            in_reply_to_id: $to, path: $root.path, line: $root.line, body: $body}]' \
    "$GH_STATE/comments.json")" && printf '%s' "$updated" >"$GH_STATE/comments.json"
}
a_bot_comments() {
  local updated
  updated="$(jq --arg body "$1" '. + [{id: (1000 + length), node_id: "IC_\(1000 + length)",
    kind: "issue", pr: 1, user: {login: "coverage[bot]", type: "Bot"}, body: $body}]' \
    "$GH_STATE/comments.json")" && printf '%s' "$updated" >"$GH_STATE/comments.json"
}
pull_request_exists() {
  local updated
  updated="$(jq --arg head "$1" --arg base "$2" --argjson number "$3" \
    --argjson cross "${4:-false}" \
    '. + [{number: $number, url: "https://example.test/pull/\($number)", state: "OPEN", '\
'headRefName: $head,
           baseRefName: $base, headRefOid: "", reviewDecision: "", isCrossRepository: $cross,
           checks: "failing"}]' "$GH_STATE/prs.json")" \
    && printf '%s' "$updated" >"$GH_STATE/prs.json"
}

# ---- push -----------------------------------------------------------------

published_project origin
start="$(git rev-parse main)"
land_change "push on main lands on the branch of the task" 0 "landed T-001 on task/T-001" push
holds "push moves the work onto the branch of the task" on_branch task/T-001
holds "push leaves the local main where it was" [ "$(git rev-parse main)" = "$start" ]
holds "push leaves the remote main where it was" remote_is main "$start"
holds "push puts the commit on the remote branch" remote_is task/T-001 "$(git rev-parse HEAD)"
holds "push sets the upstream of the branch" \
  [ "$(git rev-parse --abbrev-ref '@{upstream}')" = "origin/task/T-001" ]
holds "push never asks gh" not test -e "$GH_STATE/calls"
land_change "a second landing stays on the branch of the task" 0 "landed T-001 on task/T-001" push
holds "a second landing pushes its commit" remote_is task/T-001 "$(git rev-parse HEAD)"

published_project origin
start="$(git rev-parse HEAD)"
set_level push
reviewed_change
land_run "a dry run names the branch it would take" 0 "Branch: task/T-001" --dry-run
holds "the commands of a dry run make that branch first" \
  grep -qF "git switch -c task/T-001" "$WORK/land.log"
holds "a dry run stays on main" on_branch main
holds "a dry run commits nothing" [ "$(git rev-parse HEAD)" = "$start" ]
holds "a dry run pushes nothing" not remote_has task/T-001

printf '#!/usr/bin/env bash\necho %s >"$1"\nexit 1\n' \
  "'{\"test\":{\"status\":\"fail\",\"blocking\":true,\"command\":\"false\",\"output\":\"red\"}}'" \
  >.review/gates.sh
land_run "red gates refuse a landing at push" 3 "gates are red at landing time"
holds "a refused landing stays on main" on_branch main
holds "a refused landing creates no branch" not local_has task/T-001
holds "a refused landing keeps the change uncommitted" test -n "$(git status --porcelain src)"
cp "$WORK/gates.green" .review/gates.sh

published_project origin
set_level push
reviewed_change
cat >.review/gates.sh <<'EOF'
#!/usr/bin/env bash
printf 'changed by a gate\n' >>src/answer.kt
echo '{"build":{"status":"pass","blocking":true,"command":"true","output":""}}' >"$1"
EOF
land_run "gates that change the tree refuse a landing at push" 3 \
  "the tree changed while the gates ran"
holds "that refusal creates no branch" not local_has task/T-001
holds "that refusal stays on main" on_branch main

published_project origin
set_level push
reviewed_change
cat >.review/gates.sh <<'EOF'
#!/usr/bin/env bash
mkdir -p qa && printf -- '- **TC-001 Answer.** — e2e: `AnswerE2E.never`\n' >>qa/test-cases.md
echo '{"build":{"status":"pass","blocking":true,"command":"true","output":""}}' >"$1"
EOF
land_run "gates that mark a case refuse a landing at push" 3 \
  "was not checked against: TC-001 AnswerE2E.never"
holds "a mark refused after the gates creates no branch" not local_has task/T-001

published_project origin
set_level push
reviewed_change
printf '#!/usr/bin/env bash\nexit 1\n' >.git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
land_run "a commit that fails on the new branch fails" 1 "commit failed"
holds "the failed commit leaves the new branch current" on_branch task/T-001
rm .git/hooks/pre-commit
land_run "the same run lands on the branch it moved to: the fingerprint has no branch name in it" \
  0 "landed T-001 on task/T-001"

published_project origin
set_level push
printf 'fun question() = 6 * 7\n' >src/new.kt
reviewed_change
printf '#!/usr/bin/env bash\nexit 1\n' >.git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
land_run "a commit with a new file fails and leaves it staged" 1 "commit failed"
rm .git/hooks/pre-commit
land_run "the same run lands after that: a staged file is not a changed tree" 0 \
  "landed T-001 on task/T-001"

# ---- branches --------------------------------------------------------------

published_project origin
git branch task/T-001
land_change "an existing branch of the task that is not current refuses" 3 \
  "task/T-001 exists and is not the current branch" push
holds "that refusal comes before the gates" not test -e "$run/gates.land.json"
holds "that refusal stays on main" on_branch main
git switch -q -c feature
land_change "that branch refuses from any other branch too" 3 \
  "task/T-001 exists and is not the current branch" push

published_project origin
git push -q origin main:refs/heads/task/T-001
start="$(git rev-parse HEAD)"
land_change "the branch of the task on the remote alone refuses" 3 \
  "task/T-001 exists on origin" push
holds "that refusal comes before the gates" not test -e "$run/gates.land.json"
holds "that refusal commits nothing" [ "$(git rev-parse HEAD)" = "$start" ]

published_project origin
git branch task
land_change "a branch named task refuses before the commit" 3 "a branch named task exists" push
holds "that refusal comes before the gates" not test -e "$run/gates.land.json"
git branch -q -D task
git push -q origin main:refs/heads/task
land_change "a branch named task on the remote refuses too" 3 "a branch named task exists" push

published_project origin
land_change "a landing that moves the branch on" 0 "landed T-001 on task/T-001" push
landed="$(git rev-parse HEAD)"
moved="$(GIT_AUTHOR_NAME=x GIT_AUTHOR_EMAIL=x@example.com \
  GIT_COMMITTER_NAME=x GIT_COMMITTER_EMAIL=x@example.com \
  git -C "$GH_REMOTE" commit-tree "task/T-001^{tree}" -p task/T-001 -m "someone else")"
git -C "$GH_REMOTE" update-ref refs/heads/task/T-001 "$moved"
land_change "a remote branch that moved refuses before the commit" 3 \
  "task/T-001 on origin has moved past this one" push
says "bringing the two branches together is the user's" \
  "   For the user, only they can: bring the two together" "$WORK/land.log"
holds "that refusal commits nothing" [ "$(git rev-parse HEAD)" = "$landed" ]
publish "a rejected push is an error saying the branch moved" 1 "the remote branch task/T-001 moved"
holds "a push refused for a branch that moved is the user's too, as before the commit" \
  test "$(tail -1 "$WORK/publish.log")" = "   For the user, only they can: bring the two together"
holds "a rejected push forces nothing" remote_is task/T-001 "$moved"
git config remote.origin.push '+refs/heads/*:refs/heads/*'
publish "a + in remote.origin.push does not force it" 1 "the remote branch task/T-001 moved"
holds "that push forces nothing" remote_is task/T-001 "$moved"

published_project origin
start="$(git rev-parse HEAD)"
git config remote.origin.push 'refs/heads/task/T-001:refs/heads/main'
land_change "a mapping in remote.origin.push does not send it elsewhere" 0 \
  "landed T-001 on task/T-001" push
holds "the remote main stays where it was" remote_is main "$start"
holds "the commit goes to the branch of the task" remote_is task/T-001 "$(git rev-parse HEAD)"

published_project origin
cat >.git/hooks/post-commit <<'EOF'
#!/usr/bin/env bash
unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE
head=refs/heads/task/T-001
git push -q origin HEAD:$head
git -C "$GH_REMOTE" update-ref "$head" \
  "$(git -C "$GH_REMOTE" -c user.name=x -c user.email=x@example.com \
    commit-tree "$head^{tree}" -p "$head" -m "someone else")"
EOF
chmod +x .git/hooks/post-commit
land_change "a branch that moves after the commit reaches land.sh as 4" 4 \
  "the remote branch task/T-001 moved" push
rm .git/hooks/post-commit

published_project origin
start="$(git rev-parse HEAD)"
land_change "an unknown LANDING refuses" 3 \
  "LANDING=sometimes in .review/land.conf is not one of" sometimes
holds "an unknown LANDING commits nothing" [ "$(git rev-parse HEAD)" = "$start" ]
publish "publish.sh refuses an unknown LANDING" 3 "LANDING=sometimes"
for spelling in 'LANDING = merge' 'landing=push' 'export LANDING=push'; do
  printf 'THRESHOLD=major\nASK_AFTER_RUNS=100\n%s\n' "$spelling" >.review/land.conf
  reviewed_change
  land_run "the line '$spelling' refuses, never a silent off" 3 "is not LANDING=<level>"
  publish "publish.sh refuses the line '$spelling'" 3 "is not LANDING=<level>"
done
printf 'THRESHOLD=major\nASK_AFTER_RUNS=100\nLANDING=push\nlanding=merge\n' >.review/land.conf
reviewed_change
land_run "such a line refuses after a good one too" 3 "is not LANDING=<level>"
printf 'THRESHOLD=major\nASK_AFTER_RUNS=100\nLANDING=\n' >.review/land.conf
reviewed_change
land_run "an empty LANDING refuses, never a silent off" 3 \
  "LANDING= in .review/land.conf is not one of"
publish "publish.sh refuses an empty LANDING" 3 "LANDING= in .review/land.conf is not one of"
holds "those lines commit nothing" [ "$(git rev-parse HEAD)" = "$start" ]

published_project origin
land_change "on keeps refusing on main" 3 "landing never touches a protected branch" on
holds "on does not leave main" on_branch main
git switch -q -c feature
land_change "on commits on a branch of its own" 0 "landed T-001 on feature" on
holds "on pushes nothing" not remote_has feature
holds "on creates no branch" not local_has task/T-001

published_project origin
git switch -q -c feature
land_change "a branch that is not protected stays" 0 "landed T-001 on feature" push
holds "that branch is the one pushed" remote_has feature
holds "that branch gets no task branch next to it" not local_has task/T-001

published_project origin
start="$(git rev-parse HEAD)"
git tag main
land_change "a tag named like the branch does not hide a protected branch" 0 \
  "landed T-001 on task/T-001" push
holds "main keeps its commit" [ "$(tip_of main)" = "$start" ]
holds "the remote main keeps its commit" remote_is main "$start"

published_project origin
git switch -q -c Release
land_change "PROTECTED_BRANCHES holds whatever the case of the branch" 0 \
  "landed T-001 on task/T-001" push 'PROTECTED_BRANCHES="release"'

published_project origin
git branch -q master
git switch -q master
land_change "master is protected when the base branch is main" 0 "landed T-001 on task/T-001" push

published_project origin
git switch -q --detach
land_change "a detached HEAD refuses at push" 3 "HEAD is detached" push

for unusable_id in "T 001" "T+001" "T..001" "T/001"; do
  published_project origin
  task_with_id "$unusable_id"
  land_change "a task id of '$unusable_id' refuses" 3 "cannot name a branch" push
  holds "that refusal stays on main" on_branch main
done

published_project origin
git switch -q -c feature
task_with_id "T 001"
land_change "a task id that cannot name a branch refuses on any branch" 3 \
  "cannot name a branch" push
git commit -q --allow-empty -m "made by hand, no trailer"
jq -n '{id: "a\n\nb", title: "x", scope: ["src/*"], exit_criteria: []}' >.review/task.json
publish "a task id of several lines refuses" 3 "cannot name a branch"
holds "that refusal pushes nothing" not remote_has feature

# ---- what a landing may carry ----------------------------------------------

published_project origin
git commit -q --allow-empty -m "hand-made, never reviewed"
start="$(git rev-parse HEAD)"
land_change "a commit no landing made under the task refuses" 3 "commits no landing made" merge
holds "that refusal names it" printed "hand-made, never reviewed"
says "pushing or moving such a commit is the user's" \
  "   For the user, only they can: push or move them" "$WORK/land.log"
holds "that refusal comes before the gates" not landing_ran
holds "that refusal stays on main" on_branch main
land_change "that goes for push too" 3 "commits no landing made" push
git push -q origin main
land_change "once a person has pushed it, it is not the landing's" 0 \
  "landed T-001 on task/T-001" push

published_project origin
land_change "a landing on the branch of the task" 0 "landed T-001 on task/T-001" push
git commit -q --allow-empty -m "hand-made on the branch"
land_change "a hand commit under a second landing refuses" 3 "hand-made on the branch" push
git commit -q --allow-empty -m "T-001: another" -m "Task-Id: T-001"
publish "publish.sh refuses it under a HEAD of the task too" 3 "commits no landing made"
says "and says there too that pushing or moving it is the user's" \
  "   For the user, only they can: push or move them" "$WORK/publish.log"
holds "that refusal pushes nothing" not remote_log_has task/T-001 "hand-made on the branch"

published_project origin
git switch -q -c feature
printf 'work in progress\n' >src/wip.kt
git add src/wip.kt && git commit -q -m "WIP do not ship"
git push -q origin feature
land_change "at merge a hand commit already pushed refuses as well" 3 "WIP do not ship" merge
holds "that refusal merges nothing" not gh_called "pr merge"
land_change "at pr a person merges, and sees it" 0 "pull request: https://example.test/pull/1" pr

published_project origin
git switch -q -c feature
merged_change "merge from a branch of its own merges" 0 "merged T-001"
holds "that branch is not deleted: it is not the task's" not gh_called "--delete-branch"
holds "that branch stays on the remote" remote_has feature
holds "that branch stays here" local_has feature

# ---- the loop's own files ---------------------------------------------------

project_with_a_plan() {
  published_project origin
  mkdir -p qa .review/decisions
  printf '# Plan\n' >PLAN.md
  printf '# Tracker\n' >TASK_TRACKER.md
  printf '# Cases\n' >qa/test-cases.md
  printf '{"task": "T-000"}\n' >.review/decisions/tasks.jsonl
  git add PLAN.md TASK_TRACKER.md qa/test-cases.md .review/REVIEW_POLICY.md \
    .review/decisions/tasks.jsonl
  git commit -q -m "the plan" && git push -q origin main
}

project_with_a_plan
reviewed_pull_request merge
printf 'T-001 done\n' >>TASK_TRACKER.md
printf 'a new case\n' >>qa/test-cases.md
pr_land "the tracker and the test cases, written after the review, land on its pull request" 0 \
  "landed T-001 on task/T-001"
holds "their commit is the loop's files alone" test "$(git log -1 --format=%s)" = "T-001: records"
publish "the tracker and the test cases, written after the review, do not stale it" 0 \
  "merged T-001" --merge
holds "the tracker reaches main with the task" remote_file_has main TASK_TRACKER.md "T-001 done"
holds "the test cases too" remote_file_has main qa/test-cases.md "a new case"
holds "they do not wait in the tree" test -z "$(git status --porcelain -- TASK_TRACKER.md qa)"

printf '{"task": "T-001"}\n' >>.review/decisions/tasks.jsonl
printf 'T-002: what T-001 hands it\n' >>TASK_TRACKER.md
printf 'the epic, groomed\n' >>PLAN.md
printf 'a rule\n' >>.review/REVIEW_POLICY.md
task_with_id T-002
reviewed_pull_request merge
holds "the reviewer is not shown the plan or the tracker" \
  not grep -qE 'TASK_TRACKER|PLAN' "$run/diff.patch"
publish "what the loop left in the tracker does not refuse the next task" 0 "merged T-002" --merge
holds "what it left reaches main" remote_file_has main TASK_TRACKER.md "T-002: what T-001 hands it"
holds "the plan is the user's to commit" not remote_file_has main PLAN.md "the epic, groomed"
holds "that plan is still in the tree" grep -q "the epic, groomed" PLAN.md
holds "at merge too the decision logs are the user's to commit" \
  not remote_file_has main .review/decisions/tasks.jsonl '"T-001"'
holds "a rule of the policy is the user's to commit" \
  not remote_file_has main .review/REVIEW_POLICY.md "a rule"
holds "that rule is still in the tree" grep -q "a rule" .review/REVIEW_POLICY.md

project_with_a_plan
set_level pr
pr_work
printf 'T-001 done\n' >>TASK_TRACKER.md
printf '{"task": "T-001"}\n' >>.review/decisions/tasks.jsonl
pr_land "at pr the tracker goes on the branch of the task" 0 "landed T-001 on task/T-001"
holds "it is in the pull request" remote_file_has task/T-001 TASK_TRACKER.md "T-001 done"
holds "below merge the decision logs stay out of the commit" \
  not remote_file_has task/T-001 .review/decisions/tasks.jsonl '"T-001"'
merged_by_a_person "https://example.test/pull/1"
git fetch -q origin
holds "so the way back to the base branch stays open" git switch -q main

project_with_a_plan
set_level off
reviewed_change
printf 'T-001 done\n' >>TASK_TRACKER.md
land_run "at off the commit the user gets holds the tracker too" 0 "TASK_TRACKER.md"
holds "it is in the list of files they are given" grep -qx '  TASK_TRACKER.md' "$WORK/land.log"
holds "and nothing was committed" test "$(git log -1 --format=%s)" = "the plan"

project_with_a_plan
set_level on
git switch -q -c work
reviewed_change
printf 'T-001 done\n' >>TASK_TRACKER.md
land_run "at on too" 0 "landed T-001 on work: 2 file(s)"

project_with_a_plan
reviewed_pull_request merge
printf 'more code\n' >>src/answer.kt
publish "work changed after the review and not committed is not merged" 3 \
  "the task's work is not all committed: src/answer.kt" --merge
pr_land "it lands as a commit of its own on the pull request" 0 "landed T-001 on task/T-001"
holds "that commit says it follows the review" \
  test "$(git log -1 --format=%s)" = "T-001: changes after review 1"
publish "a change to the code after the review still stales it" 3 \
  "M1: the tree changed after this review ran" --merge
holds "work the loop has not checked shows the review pending" status_is loop/review pending

# ---- pull requests ---------------------------------------------------------

published_project origin
land_change "pr opens a pull request" 0 "pull request: https://example.test/pull/1" pr
holds "the commit takes no --run at pr" not printed "--run is required"
holds "the pull request goes from the branch of the task to the base branch" \
  gh_called "--base main --head task/T-001"
holds "its title is the task" gh_called "--title T-001: Answer 42 --body-file"
holds "its description is the loop's, ending with the trailers" \
  jq_true '.[0].body | contains("<!-- loop:body -->") and contains("Task-Id: T-001")' \
  "$GH_STATE/prs.json"
holds "it is never a draft" not gh_called "--draft"
holds "its head shows the review pending: the loop has not checked it yet" \
  status_is loop/review pending
holds "and /qa pending" status_is loop/qa pending
publish "a rerun shows the open pull request" 0 "pull request: https://example.test/pull/1"
holds "a rerun opens none" gh_count_is "pr create" 1
land_change "a landing on an open pull request updates it" 0 \
  "pull request: https://example.test/pull/1" pr
holds "that landing opens none" gh_count_is "pr create" 1
holds "that landing pushes its commit" remote_is task/T-001 "$(git rev-parse HEAD)"
holds "pr never merges" not gh_called "pr merge"
touch "$GH_STATE/list-fails"
publish "a failed question about pull requests is an error" 1 "could not say whether"
holds "it never opens a second pull request" gh_count_is "pr create" 1
rm "$GH_STATE/list-fails"

earlier="$(git rev-parse HEAD)"
landings="$(ls -d .review/runs/land-* | wc -l)"
task_with_id T-002
land_change "a next task on the unmerged branch of the earlier one refuses: no stacking" 3 \
  "HEAD carries T-001 which is not on main of origin" pr
holds "that refusal comes before the gates" [ "$(ls -d .review/runs/land-* | wc -l)" = "$landings" ]
holds "it commits nothing on the earlier branch" [ "$(git rev-parse HEAD)" = "$earlier" ]
holds "it opens no pull request of its own" not gh_called "--head task/T-002"

published_project origin
touch "$GH_STATE/create-fails"
land_change "a pull request that cannot be opened ends at 4" 4 "could not open a pull request" pr
holds "the message of 4 at pr says a change of code is landed, then reviewed" \
  printed "the work, then land.sh, which adds a commit, then review.sh"
rm "$GH_STATE/create-fails"
publish "publish.sh alone opens it" 0 "pull request: https://example.test/pull/1"

published_project origin
cat >.git/hooks/post-commit <<'EOF'
#!/usr/bin/env bash
touch "$GH_STATE/logged-out"
EOF
chmod +x .git/hooks/post-commit
land_change "a refusal of publish.sh after the commit is 4, not a landing that finished" 4 \
  "publishing did not finish" pr
rm .git/hooks/post-commit
publish "publish.sh alone refuses when gh is not logged in" 3 "gh is not logged in"
rm "$GH_STATE/logged-out"
publish "publish.sh alone finishes when gh is back" 0 "pull request: https://example.test/pull/1"

published_project origin
land_change "a pull request a person will merge" 0 "pull request: https://example.test/pull/1" pr
merged_by_a_person https://example.test/pull/1
publish "a rerun after a person merged says so" 0 "already merged: https://example.test/pull/1"
holds "that rerun pushes nothing back" not remote_has task/T-001
holds "that rerun opens none" gh_count_is "pr create" 1

published_project origin
land_change "a pull request a person will close" 0 "pull request: https://example.test/pull/1" merge
holds "at merge the landing does not merge either" not gh_called "pr merge"
on_pull_request 1 '.state = "CLOSED"'
publish "a closed pull request is a no, and stays one" 5 "was closed without a merge"
says "reopening it is the user's" \
  "   For the user, only they can: reopen it, or say that the task ends here" "$WORK/publish.log"
publish "--merge of a closed pull request waits too" 5 "was closed without a merge" --merge
holds "a closed pull request opens no other" gh_count_is "pr create" 1
holds "a closed pull request merges nothing" not gh_called "pr merge"
pr_review "the review of a closed pull request is the user's: only they reopen it" 1 \
  "   For the user, only they can: reopen it"
says "the review says that it was closed" \
  "REVIEW REFUSED — https://example.test/pull/1 was closed without a merge" "$WORK/run.log"
pr_work
pr_land "a landing on a closed pull request waits too" 4 "was closed without a merge"
holds "that landing opens no other" gh_count_is "pr create" 1

published_project origin
git push -q origin main:refs/heads/hotfix
hotfix="$(git rev-parse main)"
pull_request_exists task/T-001 hotfix 7
merged_change "a pull request into another base is not this one" 0 \
  "merged T-001: https://example.test/pull/2 into main"
holds "the base it never checked does not move" remote_is hotfix "$hotfix"
holds "the commit reaches the base branch" remote_log_has main "Task-Id: T-001"

published_project origin
pull_request_exists task/T-001 main 7 true
land_change "a pull request from a fork with the same branch name is not this one" 0 \
  "pull request: https://example.test/pull/2" pr

published_project origin
git switch -q -c 1234
pull_request_exists other main 1234
merged_change "a branch named like a number is not that pull request" 0 \
  "merged T-001: https://example.test/pull/2 into main"
holds "that pull request stays open" \
  [ "$(jq -r '.[] | select(.number == 1234) | .state' "$GH_STATE/prs.json")" = "OPEN" ]

# ---- the pull request levels ------------------------------------------------

# A finding of the reviewer and the maintainer's verdict on it.
pr_finding() {
  jq -nc --arg id "$1" --arg file "$2" --argjson line "$3" --arg quote "$4" \
    '{id: $id, file: $file, line: $line, code_quote: $quote, category: "bug",
      severity: "major", confidence: "confirmed", rule_violated: "REQUIREMENTS.md, Answer",
      evidence: "answer() returns another number than 42"}'
}
pr_verdict() {
  jq -nc --arg id "$1" --arg verdict "$2" --arg rule "$3" \
    '{finding_id: $id, verdict: $verdict, severity: "major", decision_rule: $rule,
      reason: "the number the user sees is not the one asked for"}'
}
on_and_off_the_diff="{\"findings\": [$(pr_finding F-001 src/answer.kt 1 'fun answer()'),
  $(pr_finding F-002 src/util.kt 1 'fun util() = 1')]}"
accepted_and_rejected="{\"verdicts\": [$(pr_verdict F-001 accept no-rule-fired),
  $(pr_verdict F-002 reject out-of-task-scope)]}"
gates_that_record() {
  cat >.review/gates.sh <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$REVIEW_BASE" >>"$WORK/review-base"
echo '{"build":{"status":"pass","blocking":true,"command":"true","output":"","seconds":3,'\
'"summary":"7 tests"}}' >"\$1"
EOF
  chmod +x .review/gates.sh
  : >"$WORK/review-base"
}
person_id() {
  jq -r '[.[] | select(.body | startswith("Why 42"))][0].id' "$GH_STATE/comments.json"
}

published_project origin
gates_that_record
land_change "below the pull request levels" 0 "landed T-001 on task/T-001" push
holds "REVIEW_BASE is HEAD there, at the review and the landing" \
  [ "$(sort -u "$WORK/review-base")" = HEAD ]

published_project origin
gates_that_record
set_level pr
pr_work
pr_land "land.sh at pr takes no --run: it commits, pushes and opens the pull request" 0 \
  "pull request: https://example.test/pull/1"
holds "and does not merge" not gh_called "pr merge"
holds "its gates measure the change from the merge base (REVIEW_BASE)" \
  [ "$(tail -1 "$WORK/review-base")" = "$(git rev-parse HEAD^)" ]
holds "its gates are kept in a landing folder, which is no review run" \
  test -f "$(ls -d .review/runs/land-* | tail -1)/gates.json"
publish "--merge refuses at pr: the merge is the user's" 3 \
  "   For the user, only they can: the merge, with squash" --merge
says "and says that --check tells whether the pull request is ready" \
  "publish.sh merges nothing there, and --check says whether the pull request is ready" \
  "$WORK/publish.log"
publish "--check with no review run refuses" 3 "M1: no review run of T-001" --check
pr_review "a review on the pull request" 0 "CLEAN — gates green"
holds "REVIEW_BASE reaches gates.sh as the merge base" \
  [ "$(tail -1 "$WORK/review-base")" = "$(jq -r .merge_base "$run/meta.json")" ]
holds "the run records the pull request, the head it reviewed and its time" \
  jq_true --arg head "$(git rev-parse HEAD)" \
  '.pr_url == "https://example.test/pull/1" and .head == $head and .time > 0' "$run/meta.json"
holds "no prompt names the pull request" not grep -q "example.test/pull" "$run/reviewer-prompt.md"
holds "the run is posted as a review" posted "<!-- loop:review $(basename "$run") -->"
holds "its summary gives each gate with its seconds and summary line" \
  posted "| build | pass | 3 | 7 tests |"
holds "and the end-to-end tests of each platform" posted "| app | 2 | 2 |"
holds "the head shows the review green" status_is loop/review success
holds "and each gate" status_is loop/build success
holds "and the end-to-end tests" status_is loop/e2e-app success
holds "a gate's status gives its summary line" jq_true 'any(.[]; .context == "loop/build"
  and .description == "pass — 7 tests")' "$GH_STATE/statuses.json"
holds "/qa is pending" status_is loop/qa pending
publish "--check with no /qa of this work refuses" 3 "M5: /qa has not checked this work of T-001" \
  --check
pr_post "at the pull request levels pr-post.sh work prints the merge base too" 0 \
  '"merge_base": "' work
holds "with the work as it is and HEAD" jq_true --arg head "$(git rev-parse HEAD)" \
  --arg work "$(. "$LIB_DIR/common.sh" && tree_fingerprint)" \
  --arg base "$(jq -r '.merge_base' "$run/meta.json")" \
  '.head == $head and .work == $work and .merge_base == $base' "$WORK/post.log"
qa_checked
holds "the report of /qa is a comment" posted "<!-- loop:qa qa-$qa_runs -->"
holds "/qa turns green" status_is loop/qa success
holds "the description lists the runs" \
  jq_true '.[0].body | contains("| Run | Head | Result") and contains("| qa-")' "$GH_STATE/prs.json"
publish "--check at pr says ready" 0 "ready to merge: https://example.test/pull/1" --check
holds "--check merges nothing" not gh_called "pr merge"
printf '# Tracker\n\n- T-001 done\n' >TASK_TRACKER.md
pr_land "the loop's files alone land on the open pull request" 0 \
  "landed T-001 on task/T-001: 1 file(s)"
holds "as the commit of the records" test "$(git log -1 --format=%s)" = "T-001: records"
holds "their head keeps the review: the work did not change" status_is loop/review success
holds "and /qa" status_is loop/qa success
publish "a commit of the loop's files keeps the review valid" 0 "ready to merge" --check
a_person_comments "$(printf 'Why 42?\nThe tracker says 41.')"
publish "what a person wrote, unanswered, waits" 5 \
  "are not settled, the first $(person_id) by  on the pull request, not answered" --check
says "answering it is the loop's" \
  "   The loop goes on: weigh it like a finding and answer it: pr-post.sh comments shows it "\
"whole, pr-post.sh reply $(person_id) <answer> <text-file> answers" "$WORK/publish.log"
pr_post "pr-post.sh comments shows it whole" 0 "The tracker says 41." comments
says "and says that it is the loop's" " — not answered: the loop's"
printf 'Whether the tracker or the requirements hold is not found out yet.\n' >"$WORK/reply.md"
pr_post "the loop answers that it is not settled" 0 "reply to $(person_id) (unsettled) posted" \
  reply "$(person_id)" unsettled "$WORK/reply.md"
publish "a remark answered unsettled is the loop's to settle" 5 \
  "   The loop goes on: find out what is still assumed, then answer it again" --check
says "its line says how it was answered" \
  "the first $(person_id) by  on the pull request, answered unsettled" "$WORK/publish.log"
never_says "and sends nothing to the user" "For the user" "$WORK/publish.log"
pr_post "pr-post.sh comments says so too" 0 "— answered unsettled: the loop's to settle" comments
printf 'The requirements ask for 42: REQUIREMENTS.md, "Answer".\n' >"$WORK/reply.md"
pr_post "the loop answers it" 0 "reply to $(person_id) (not-a-problem) posted" \
  reply "$(person_id)" not-a-problem "$WORK/reply.md"
holds "the reply names what it answers, and how" \
  posted "<!-- loop:reply $(person_id) not-a-problem -->"
publish "a person's comment the loop disagreed with waits for the user" 5 \
  "   For the user, what a person wrote: decide between what its author wrote and the loop's "\
"answer not-a-problem; their decision is posted with pr-post.sh reply $(person_id) user "\
"<text-file>" --check
says "its line says how the loop answered" \
  "the first $(person_id) by  on the pull request, answered not-a-problem" "$WORK/publish.log"
pr_post "pr-post.sh comments says whose it is" 0 \
  "— answered not-a-problem: For the user, what a person wrote" comments
# With several comments open the stop is the loop's while one of them is: one not answered,
# or one answered unsettled. Its line names that comment, also when another stands before
# it; the user's line comes only when every open comment is theirs.
a_person_comments "And the button is red where the plan says blue."
second="$(jq -r '.[-1].id' "$GH_STATE/comments.json")"
publish "a comment not answered behind one the loop disagreed with keeps the stop the loop's" 5 \
  "2 comment(s) of people on https://example.test/pull/1 are not settled, the first that is the loop's $second by  on the pull request, not answered" \
  --check
says "its line names the comment the loop has still to answer" \
  "   The loop goes on: weigh it like a finding and answer it: pr-post.sh comments shows it "\
"whole, pr-post.sh reply $second <answer> <text-file> answers" "$WORK/publish.log"
never_says "the user is not asked while the loop has a comment to answer" "For the user" \
  "$WORK/publish.log"
printf 'Which colour the plan means is not found out yet.\n' >"$WORK/reply.md"
pr_post "the loop answers the second that it is not settled" 0 \
  "reply to $second (unsettled) posted" reply "$second" unsettled "$WORK/reply.md"
publish "a comment answered unsettled behind one that is the user's is the loop's too" 5 \
  "the first that is the loop's $second by  on the pull request, answered unsettled" --check
says "the loop finds out what is still assumed" \
  "   The loop goes on: find out what is still assumed, then answer it again" "$WORK/publish.log"
never_says "and the user is not asked then either" "For the user" "$WORK/publish.log"
printf 'The button is blue now.\n' >"$WORK/reply.md"
pr_post "the loop fixes the second and says so" 0 "reply to $second (fixed) posted" \
  reply "$second" fixed "$WORK/reply.md"
publish "once every open comment is the user's, the stop is theirs" 5 \
  "1 comment(s) of people on https://example.test/pull/1 are not settled, the first $(person_id) by  on the pull request, answered not-a-problem" \
  --check
says "and its line is the user's" \
  "   For the user, what a person wrote: decide between what its author wrote and the loop's "\
"answer not-a-problem; their decision is posted with pr-post.sh reply $(person_id) user "\
"<text-file>" "$WORK/publish.log"
printf 'The user: 42 it is, the tracker is wrong.\n' >"$WORK/user.md"
pr_post "the user's decision is posted" 0 "reply to $(person_id) (user) posted" \
  reply "$(person_id)" user "$WORK/user.md"
pr_post "the same reply again" 0 "no second one" reply "$(person_id)" user "$WORK/user.md"
holds "is posted once" posted_count_is "<!-- loop:reply $(person_id) user -->" 1
a_bot_comments "Coverage: 81%"
publish "what a person wrote, settled, and a bot's comment, no longer wait" 0 "ready to merge" \
  --check
a_person_reviews() {
  local updated
  updated="$(jq --arg state "$1" '. + [{id: (1000 + length), node_id: "PRR_\(1000 + length)",
    kind: "review", pr: 1, user: {login: "reviewer", type: "User"}, state: $state, body: ""}]' \
    "$GH_STATE/comments.json")" && printf '%s' "$updated" >"$GH_STATE/comments.json"
}
a_person_reviews CHANGES_REQUESTED
publish "changes requested in a review wait, with no rule of the branch too" 5 \
  "changes are requested" --check
says "asking the one who requested them is the user's" \
  "   For the user, what a person wrote: ask them to approve or dismiss it, once every remark "\
"is answered" "$WORK/publish.log"
a_person_reviews APPROVED
publish "the same person's approval lifts them" 0 "ready to merge" --check
jq -n '{context: "loop/qa", state: "failure", description: "someone said so"}' >"$WORK/status.json"
gh api "repos/x/$(basename "$GH_REMOTE" .git)/statuses/$(git rev-parse HEAD)" --method POST \
  --input "$WORK/status.json" >/dev/null
publish "a status of the loop that is not green at HEAD waits" 5 "loop/qa: someone said so" --check
pr_post "pr-post.sh statuses posts them again" 0 "statuses posted" statuses
publish "then it is ready again" 0 "ready to merge" --check
set_level merge
publish "at merge --merge merges" 0 "merged T-001: https://example.test/pull/1 into main" --merge
holds "with a squash" gh_called " --squash "
holds "whose body carries the trailers" remote_log_has main "Task-Id: T-001"
holds "and ends on the base branch" on_branch main

# On the pull request, a run on reviewed work repeats only the end-to-end tests and posts
# the statuses again.
published_project origin
land_change "a pull request whose tests will not run at first" 0 \
  "pull request: https://example.test/pull/1" pr
E2E_ONLY=none E2E_EXIT=75 \
  pr_review "a review on the pull request whose tests could not run" 75 "E2E COULD NOT RUN"
holds "its tests do not show green" not status_is loop/e2e-app success
pr_review "the next run on the pull request repeats only the tests" 0 \
  "this work is reviewed already"
holds "and posts the statuses again: the tests show green" status_is loop/e2e-app success
holds "with no second review on the pull request" posted_count_is "<!-- loop:review " 1

# On the pull request the review's status is its own: the end-to-end tests have theirs, and
# what they came to holds the merge, not the review.
published_project origin
land_change "a pull request for the statuses of its review and its tests" 0 \
  "pull request: https://example.test/pull/1" pr
E2E_ONLY=none E2E_EXIT=75 pr_review \
  "a run whose tests could not run shows the review green and the tests pending" 75 \
  "E2E COULD NOT RUN"
holds "it shows the review green" status_is loop/review success
holds "and the tests pending" status_is loop/e2e-app pending
holds "the pending tests say why, and that they are to be repeated" status_says loop/e2e-app \
  "could not run: .review/e2e.sh says the device or a tool was not there (exit 75), twice — to be repeated"
publish "the merge waits for the tests all the same" 3 "M2:" --check
pr_review "the repeat turns them green with no second review" 0 \
  "this work is reviewed already"
holds "the repeat shows the tests green" status_is loop/e2e-app success
holds "and the review still green" status_is loop/review success
holds "one review is posted" posted_count_is "<!-- loop:review " 1
mkdir -p qa && printf '# Test cases\n\n- **TC-001 Answer.** It shows 42. — e2e: `AnswerE2E.later`\n' \
  >qa/test-cases.md
pr_post "the statuses after a mark is written that the run was not checked against" 0 \
  "statuses posted" statuses
holds "a mark the run was not checked against fails the tests' status" \
  status_is loop/e2e-app failure
holds "and says which" status_says loop/e2e-app "names end-to-end tests this run was not checked against"
holds "the review's status stays its own" status_is loop/review success
rm -r qa
pr_work
pr_land "new work on the pull request whose tests will be red" 0 "landed T-001"
E2E_XML="$(xml shows42=failed starts)" pr_review \
  "red tests fail their own status, not the review's" 2 "E2E RED"
holds "the review of red tests shows green" status_is loop/review success
holds "and the red tests fail" status_is loop/e2e-app failure
mv "$run/e2e.json" "$WORK/e2e.kept.json"
pr_post "the statuses of a reviewed run whose tests left no record" 0 "statuses posted" statuses
holds "show its review by the review alone" status_is loop/review success
mv "$WORK/e2e.kept.json" "$run/e2e.json"

published_project origin
printf 'fun util() = 1\n' >src/util.kt
git add src/util.kt && git commit -q -m util && git push -q origin main
set_level merge
pr_work
pr_land "at merge too the landing opens the pull request" 0 \
  "pull request: https://example.test/pull/1"
pr_review "a finding on the diff and one off it" 3 "accepted (>= major): 1" \
  "$on_and_off_the_diff" "$accepted_and_rejected"
first_run="$run"
holds "the run is posted as one review" gh_count_is "/reviews --method POST" 1
holds "the finding on the diff is a comment on its line" \
  jq_true 'any(.[]; .kind == "line" and .path == "src/answer.kt" and .line == 1
              and (.body | contains("F-001")))' "$GH_STATE/comments.json"
holds "with its triage" posted "Triage: **accept**, major, by no-rule-fired"
holds "the finding off the diff is in the body" \
  jq_true 'any(.[]; .kind == "review" and (.body | contains("Findings off the diff")
                                              and contains("F-002")))' "$GH_STATE/comments.json"
holds "and on no line" \
  not jq_true 'any(.[]; .kind == "line" and (.body | contains("F-002")))' "$GH_STATE/comments.json"
holds "the comment of each finding is recorded" jq_true '."F-001" > 0' "$run/pr-comments.json"
a_person_answers_in_thread "$(jq '."F-001"' "$run/pr-comments.json")" "Not a bug: 1 is a draft."
thread_answer="$(jq '[.[] | select(.kind == "line" and .in_reply_to_id != null)] | last | .id' \
  "$GH_STATE/comments.json")"
printf 'It is: the requirements ask for 42.\n' >"$WORK/reply.md"
pr_post "a person's answer inside a finding's thread is answered there" 0 \
  "reply to $thread_answer (fixed) posted" reply "$thread_answer" fixed "$WORK/reply.md"
holds "at the root of the thread" \
  jq_true --argjson to "$(jq '."F-001"' "$run/pr-comments.json")" --arg marker \
  "<!-- loop:reply $thread_answer fixed -->" \
  'any(.[]; .in_reply_to_id == $to and (.body | startswith($marker)))' "$GH_STATE/comments.json"
holds "the review status fails while a finding is accepted" status_is loop/review failure
statuses_posted="$(grep -c 'statuses/' "$GH_STATE/calls")"
pr_post "pr-post.sh run again" 0 "no second one" run "$run"
holds "a rerun posts no second review" gh_count_is "/reviews --method POST" 1
holds "a rerun posts the statuses again" \
  [ "$(grep -c 'statuses/' "$GH_STATE/calls")" -gt "$statuses_posted" ]
qa_checked
publish "--merge with an accepted finding refuses" 3 \
  "M3: 1 accepted finding(s) at or above major are unresolved" --merge
pr_work
pr_land "the fix lands as a commit after the review" 0 "landed T-001 on task/T-001"
holds "its message says so" test "$(git log -1 --format=%s)" = "T-001: changes after review 1"
publish "--merge of work newer than the review refuses" 3 \
  "M1: the tree changed after this review ran" --merge
printf '[{"finding_id": "F-001", "answer": "fixed", "text": "answer() is 42.", "commit": ""}]' \
  >"$first_run/answers.json"
pr_review "the review of the fix" 0 "CLEAN — gates green"
publish "--merge with no /qa of this work refuses" 3 "M5: /qa has not checked this work" --merge
qa_checked
publish "--merge with an answer not posted refuses" 3 \
  "M7: runs or findings of https://example.test/pull/1 that are not posted there: "\
"$(basename "$first_run") F-001" --merge
pr_post "the answers of a run are posted" 0 "answers of $(basename "$first_run") posted" \
  answers "$first_run"
holds "each answer is a reply to its finding's comment" \
  jq_true --argjson to "$(jq '."F-001"' "$first_run/pr-comments.json")" \
  'any(.[]; .in_reply_to_id == $to and (.body | contains("**fixed** in")))' \
  "$GH_STATE/comments.json"
holds "a fix that names no commit is HEAD's" \
  jq_true --arg head "$(git rev-parse HEAD)" '.[0].commit == $head' \
  "$first_run/answers-posted.json"
pr_post "answers again" 0 "posted" answers "$first_run"
holds "post nothing twice" posted_count_is "<!-- loop:answer $(basename "$first_run") F-001 -->" 1
publish "--merge merges once every item holds" 0 "merged T-001" --merge
holds "the squash counts the findings of every run" \
  remote_log_has main "Findings: 2 reviewed, 1 rejected, 0 outstanding at major+"

published_project origin
set_level merge
pr_work
pr_land "a landing to escalate on" 0 "pull request: https://example.test/pull/1"
pr_review "an escalated finding" 4 "escalated         : 1" \
  "{\"findings\": [$(pr_finding F-001 src/answer.kt 1 'fun answer()')]}" \
  "{\"verdicts\": [$(pr_verdict F-001 escalate needs-judgment)]}"
qa_checked
publish "--merge with an escalation unanswered refuses" 3 \
  "M4: 1 escalation(s) are waiting for an answer" --merge
holds "the review status waits for the answer" status_is loop/review pending
printf '[{"finding_id": "F-001", "resolution": "accepted-as-is", "by": "agent", '\
'"note": "42 is what the user asked for."}]' >"$run/escalations-answered.json"
pr_post "the answer to an escalation is posted" 0 "answers of $(basename "$run") posted" \
  answers "$run"
holds "it is a reply to the escalated finding" posted "**accepted-as-is**, by agent"
holds "the review turns green without a commit" status_is loop/review success
pr_post "answers again" 0 "posted" answers "$run"
holds "posts nothing twice" posted_count_is "<!-- loop:answer $(basename "$run") F-001 -->" 1
publish "then it merges" 0 "merged T-001" --merge

published_project origin
set_level merge
pr_work
pr_land "a landing whose review is posted unrecorded" 0 "pull request: https://example.test/pull/1"
pr_review "its review" 0 "CLEAN — gates green"
rm "$run/pr-review.json"
publish "a run whose post is not recorded refuses" 3 \
  "M1: $(basename "$run") is not posted on https://example.test/pull/1" --merge
pr_post "pr-post.sh run finds the review GitHub took" 0 "unrecorded: recorded now" run "$run"
holds "and posts no second one" gh_count_is "/reviews --method POST" 1
qa_checked '[]' "" 1
open_qa="qa-$qa_runs"
publish "/qa that left an item unproven goes back to the loop" 3 \
  "M5: /qa left 1 unproven and 0 not checked in $open_qa" --merge
says "the refusal says what the loop does next" \
  "   The loop goes on: an unproven item goes back to the work; then run /qa of the whole pull request again" \
  "$WORK/publish.log"
never_says "a /qa that left nothing unchecked is sent to no device" "restore what failed" \
  "$WORK/publish.log"
holds "a record with counts alone names no item in the refusal" \
  grep -qxF "PUBLISHING REFUSED — M5: /qa left 1 unproven and 0 not checked in $open_qa" \
  "$WORK/publish.log"
holds "so does its status" status_is loop/qa pending
qa_checked '[]' "$(git rev-parse HEAD)"
publish "a later /qa of less than the whole pull request does not clear it" 3 \
  "M5: /qa left 1 unproven and 0 not checked in $open_qa" --merge
jq -n '{by: "human", answer: "accepted-as-is", words: "The emulator is broken: fine."}' \
  >".review/runs/$open_qa/open-answered.json"
# This record is of the form made before, with words: it is read as it is.
pr_post "the statuses again" 0 "statuses posted" statuses
holds "the user's answer turns /qa green" status_is loop/qa success
publish "and the task merges" 0 "merged T-001" --merge

# What can be checked only after the merge. /qa records such an item as after_merge, with
# its reason and the check it will make. It is in no count the merge reads, so the merge
# does not wait on it: the script that merges writes down what is owed
# (.review/runs/after-merge-<task>/owed.json) and lists it, every later review and landing
# says what is still owed, and no later task merges (M10) until each item has its result
# in results.json beside the list — a pass with what was seen, a failure with the task of
# the tracker that takes the defect, or a check that could not be made, with the user's
# acceptance beside it — and the report is on the merged pull request. A count of items put
# off that no item backs says no check, and stays among those not checked. with_items
# <items> makes the <more> of qa_recorded from a list of items, the counts taken from them.
with_items() {
  jq -nc --argjson items "[$1]" '
    {counts: (reduce ("pass", "fail", "unproven", "not_checked", "after_merge") as $verdict
                ({}; .[$verdict] = ([$items[] | select(.verdict == $verdict)] | length))),
     items: $items}'
}
passed_case='{"id": "TC-001", "verdict": "pass"}'
build_of_main='{"id": "the build of main", "verdict": "after_merge",
  "reason": "the workflow runs only on a push to the base branch",
  "check": "the run of the build workflow on main, at the merge commit"}'
put_off="$(with_items "$passed_case, $build_of_main")"
owed=.review/runs/after-merge-T-001
owed_block="OWED AFTER THE MERGE — /qa put off 1 check(s) of T-001 until now:"
owed_next="   The loop goes on: make them now (/qa --after-merge T-001): the results go into "\
"$owed/results.json, with a report.md beside it; no later task merges before each has its result"
qa_status_ends() {
  jq_true --arg sha "$(git rev-parse HEAD)" --arg state "$1" --arg ending "$2" \
    '[.[] | select(.sha == $sha and .context == "loop/qa")] | last
     | .state == $state and (.description | endswith($ending))' "$GH_STATE/statuses.json"
}
# A later task up to its merge: its landing, its review and its /qa, in $WORK/land.log
# and $WORK/run.log.
later_task() { task_with_id "$1" && reviewed_pull_request "${2:-merge}"; }
# The tracker is one of the loop's files: a landing commits it, with nothing reviewed again.
tracker_lands() {
  printf '%s\n' "$1" >>TASK_TRACKER.md
  step "the landing of the tracker" "$WORK/land.log" \
    "$LIB_DIR/land.sh" --task-file .review/task.json
}
result_is() { printf '[%s]' "$1" >"$owed/results.json"; }
# The loop's line of M5 for what /qa did not check: it restores what failed, and it is told
# where an item goes that can be checked only after the merge.
loop_restores="restore what failed — boot or erase the simulator — and run /qa of the whole "\
"pull request again; an item that can be checked only once the pull request is merged is "\
"recorded by /qa as after_merge, with the check it will make, and does not hold the merge"

published_project origin
set_level merge
pr_work
pr_land "a landing whose /qa puts an item off until after the merge" 0 \
  "pull request: https://example.test/pull/1"
pr_review "the review of that landing" 0 "CLEAN — gates green"
qa_checked '[]' "" 0 "$put_off"
says "at the pull request levels pr-post.sh qa lists what is put off until after the merge" \
  "   1 to check after the merge — they do not hold it:" "$WORK/qa.log"
says "with its reason and the check that will be made then" \
  "      the build of main — the workflow runs only on a push to the base branch. Then: the run of the build workflow on main, at the merge commit" \
  "$WORK/qa.log"
says "and the loop makes that check right after the merge" \
  "   The loop goes on: they are checked right after the merge (/qa --after-merge T-001)" \
  "$WORK/qa.log"
never_says "the user is not asked about an item put off" "For the user" "$WORK/qa.log"
holds "the status of /qa says so" qa_status_ends success ", 0 not checked, 1 after the merge"
publish "--check says what is owed after the merge" 0 \
  "ready to merge: https://example.test/pull/1" --check
says "and names each check" "   after the merge /qa owes 1 check(s): the build of main" \
  "$WORK/publish.log"
holds "the description lists it under the /qa runs" \
  jq_true --arg line "- After the merge: the build of main — the run of the build workflow on main, at the merge commit" \
  '.[0].body | contains($line)' "$GH_STATE/prs.json"
holds "nothing is owed before the merge" not test -e "$owed"
publish "an item put off until after the merge does not hold it" 0 "merged T-001" --merge
says "the merge lists what is owed after it" "$owed_block" "$WORK/publish.log"
says "each with the check to make" \
  "  - the build of main: the run of the build workflow on main, at the merge commit" \
  "$WORK/publish.log"
holds "and ends with what the loop does now" \
  test "$(tail -1 "$WORK/publish.log")" = "$owed_next"
holds "it writes the list beside the runs" \
  jq_true --arg from ".review/runs/qa-$qa_runs" \
  '.task == "T-001" and .pr_url == "https://example.test/pull/1" and .pr_number == 1
   and .base == "main" and (.time | type) == "number"
   and .items == [{id: "the build of main",
                   reason: "the workflow runs only on a push to the base branch",
                   check: "the run of the build workflow on main, at the merge commit",
                   from: $from}]' "$owed/owed.json"
holds "the squash says how many checks are put off" \
  remote_log_has main "QA: qa-$qa_runs (full; 1 to check after the merge)"
pr_post "a report that is not written yet is not posted" 3 \
  "$owed holds no checks owed after a merge, or no report.md yet" after-merge "$owed"
later_task T-002
says "the landing of a later task says what is owed, and runs" \
  "OWED — T-001: the build of main, put off until after its merge: no result ($owed)" \
  "$WORK/land.log"
says "and so does its review" \
  "OWED — T-001: the build of main, put off until after its merge: no result ($owed)" \
  "$WORK/run.log"
publish "a later task does not merge while a check owed after a merge has no result" 3 \
  "M10: T-001 was merged with checks put off until after its merge, and these have no result that says what was seen: the build of main" \
  --merge
says "making the check is the loop's" \
  "   The loop goes on: make them (/qa --after-merge T-001): $owed/results.json" \
  "$WORK/publish.log"
publish "--check of the later task refuses the same way" 3 \
  "M10: T-001 was merged with checks put off until after its merge" --check
printf 'not JSON' >"$owed/results.json"
publish "results that cannot be read settle nothing" 3 \
  "have no result that says what was seen: the build of main" --merge
result_is '{"id": "the build of main", "verdict": "pass"}'
publish "a pass says what was seen" 3 \
  "have no result that says what was seen: the build of main" --merge
result_is '{"id": "the build of main", "verdict": "fine", "evidence": "run 41"}'
publish "a verdict that is none of the three is no result" 3 \
  "have no result that says what was seen: the build of main" --merge
result_is '{"id": "the build of main", "verdict": "not_checked"}'
publish "a check that could not be made says why" 3 \
  "have no result that says what was seen: the build of main" --merge
result_is '{"id": "the build of main", "verdict": "fail", "reason": "the job ends red"}'
publish "a result that failed names its task" 3 \
  "M10: T-001 was merged, and these checks failed after it and name no task of the tracker: the build of main" \
  --merge
says "a check that fails after the merge is a defect, which the loop writes down" \
  "   The loop goes on: a check that fails after the merge is a defect: write it into the tracker as a task, and name the task in its result" \
  "$WORK/publish.log"
result_is '{"id": "the build of main", "verdict": "fail", "reason": "the job ends red",
  "task": "T-077"}'
publish "a task that is not in the tracker settles nothing" 3 \
  "these checks failed after it and name no task of the tracker: the build of main" --merge
tracker_lands "### T-001: Answer 42"
result_is '{"id": "the build of main", "verdict": "fail", "reason": "the job ends red",
  "task": "T-001"}'
publish "nor does the merged task itself" 3 \
  "these checks failed after it and name no task of the tracker: the build of main" --merge
tracker_lands "### T-077: The build of main ends red"
result_is '{"id": "the build of main", "verdict": "fail", "reason": "the job ends red",
  "task": "T-077"}'
publish "a failed check that is a task of the tracker still waits for its report" 3 \
  "M10: the report of the checks after the merge of T-001 is not written" --merge
says "writing it is the loop's" "   The loop goes on: write $owed/report.md" "$WORK/publish.log"
holds "nothing is merged while something is owed" gh_count_is "pr merge" 1
printf '# After the merge of T-001\n\nThe build of main ends red: T-077.\n' >"$owed/report.md"
publish "a failed check that is a task of the tracker lets the next task merge" 0 \
  "merged T-002" --merge
holds "and its report is on the pull request it belongs to" \
  jq_true 'any(.[]; .pr == 1 and .kind == "issue"
                    and (.body | startswith("<!-- loop:after-merge T-001 -->\n# After the merge of T-001")))' \
  "$GH_STATE/comments.json"
never_says "a merge with nothing owed lists nothing" "OWED" "$WORK/publish.log"
pr_post "posted again, it is there once" 0 \
  "the report of the checks after the merge of T-001 is on https://example.test/pull/1 already: no second one" \
  after-merge "$owed"
holds "its marker is on the pull request once" \
  posted_count_is "<!-- loop:after-merge T-001 -->" 1

published_project origin
reviewed_pull_request merge
qa_checked '[]' "$(git rev-parse HEAD)" 0 "$put_off"
publish "a /qa after a fix that puts an item off does not hold the merge either" 0 \
  "merged T-001" --merge
says "and what it put off is owed too" "$owed_block" "$WORK/publish.log"
result_is '{"id": "the build of main", "verdict": "pass",
  "evidence": "run 41 of the build on main: success"}'
later_task T-002
never_says "a check that has its result is not said to be owed" "OWED" "$WORK/run.log"
publish "settled results with no report do not merge" 3 \
  "M10: the report of the checks after the merge of T-001 is not written" --merge
printf '# After the merge of T-001\n\nRun 41 of the build on main: success.\n' >"$owed/report.md"
publish "a result that passed settles it" 0 "merged T-002" --merge
holds "the report of a check that passed is on the merged pull request" \
  posted_count_is "<!-- loop:after-merge T-001 -->" 1
holds "its post is recorded beside the list" \
  jq_true '.pr_url == "https://example.test/pull/1" and (.id | tostring | length) > 0' \
  "$owed/pr-comment.json"

published_project origin
reviewed_pull_request merge
qa_checked '[]' "" 0 "$put_off"
publish "a merge with a check put off" 0 "merged T-001" --merge
result_is '{"id": "the build of main", "verdict": "not_checked",
  "reason": "the host was down"}'
printf '# After the merge of T-001\n\nThe host was down: nothing was seen.\n' >"$owed/report.md"
pr_post "the report is posted from the base branch, on the pull request that was merged" 0 \
  "report of the checks after the merge of T-001 posted: https://example.test/pull/1" \
  after-merge "$owed"
later_task T-002
says "a check that could not be made is said so in the later runs" \
  "OWED — T-001: the build of main, put off until after its merge: could not be checked and is not accepted ($owed)" \
  "$WORK/run.log"
publish "a check that could not be made after the merge is the user's" 3 \
  "M10: T-001 is merged, and the build of main could not be checked after it (the host was down)" \
  --merge
says "it is beyond what was agreed, with the file their acceptance goes into" \
  "   For the user, beyond what was agreed: leave it unchecked, or say how to check it; their acceptance goes into $owed/open-answered.json, {\"by\": \"human\", \"answer\": \"accepted-as-is\"}" \
  "$WORK/publish.log"
never_says "no words of theirs are asked for" "words" "$WORK/publish.log"
jq -n '{by: "agent", answer: "accepted-as-is"}' >"$owed/open-answered.json"
publish "an acceptance that is not the user's settles nothing" 3 \
  "the build of main could not be checked after it" --merge
jq -n '{by: "human", answer: "accepted-as-is"}' >"$owed/open-answered.json"
publish "their acceptance settles it" 0 "merged T-002" --merge
holds "the report posted before is not posted again" \
  posted_count_is "<!-- loop:after-merge T-001 -->" 1

published_project origin
reviewed_pull_request merge
qa_checked '[]' "" 0 "$put_off"
# A lock on the index stops the checkout, and nothing before the merge writes the index.
touch .git/index.lock
publish "a merge whose checkout could not move still writes the list" 1 \
  "could not move to main" --merge
holds "the list is there all the same" jq_true '.items | length == 1' "$owed/owed.json"
written="$(jq '.time' "$owed/owed.json")"
rm .git/index.lock
publish "run again, it lists what is owed" 0 "$owed_block" --merge
holds "and the list is written once" \
  jq_true --argjson written "$written" '.time == $written and (.items | length) == 1' \
  "$owed/owed.json"

published_project origin
touch "$GH_STATE/moves-the-checkout"
reviewed_pull_request merge
qa_checked '[]' "" 0 "$put_off"
publish "with a gh that moves the checkout itself the list is written too" 0 "$owed_block" \
  --merge
holds "that list holds the item" \
  jq_true '.items | map(.id) == ["the build of main"]' "$owed/owed.json"

published_project origin
git worktree add -q -b task/T-001 "$repository-linked" || fail_setup "linked worktree"
cp -R .review "$repository-linked/"
cd "$repository-linked" || fail_setup "cd linked worktree"
reviewed_pull_request merge
qa_checked '[]' "" 0 "$put_off"
publish "a merge from a linked worktree lists what is owed too" 0 "$owed_block" --merge
holds "that merge ends with what the loop does now" \
  test "$(tail -1 "$WORK/publish.log")" = "$owed_next"

published_project origin
reviewed_pull_request pr
qa_checked '[]' "" 0 "$put_off"
publish "at pr --check says what is owed after the merge" 0 \
  "   after the merge /qa owes 1 check(s): the build of main" --check
says "with the pull request ready to merge" "ready to merge: https://example.test/pull/1" \
  "$WORK/publish.log"
holds "at pr nothing is owed before the user merged" not test -e "$owed"
merged_by_a_person https://example.test/pull/1
publish "a pull request a person merged owes its checks too" 0 \
  "already merged: https://example.test/pull/1"
says "publish.sh on the task's branch lists them" "$owed_block" "$WORK/publish.log"
holds "and writes the list" jq_true '.items | map(.id) == ["the build of main"]' "$owed/owed.json"
publish "run again there, it lists them again" 0 "$owed_block"
git fetch -q origin
git switch -q main && git pull -q --ff-only origin main
later_task T-002 pr
publish "at pr --check of a later task waits for what is owed too" 3 \
  "M10: T-001 was merged with checks put off until after its merge" --check

# What the list holds: of each item /qa put off, by its id, what the newest record of the
# task says. A count alone is no item; an item a later /qa checked is owed no more.
published_project origin
reviewed_pull_request merge
qa_recorded '[]' "" 0 \
  '{"counts": {"pass": 3, "fail": 0, "unproven": 0, "not_checked": 1, "after_merge": 2}}'
publish "a /qa with counts alone holds the merge by its count of items put off" 3 \
  "M5: /qa left 0 unproven and 3 not checked in qa-$qa_runs (2 of them put off until after the merge by a count alone: no item says its check)" \
  --check
says "the loop's line says what to do about a count alone, and about what was not checked" \
  "   The loop goes on: have /qa list each item it put off by a count alone, with its reason and the check that will be made then (items), or check it now; $loop_restores" \
  "$WORK/publish.log"
qa_recorded '[]' "" 0 \
  '{"counts": {"pass": 3, "fail": 0, "unproven": 0, "not_checked": 0, "after_merge": "one"}}'
publish "a count of items put off that is no number holds the merge too" 3 \
  "M5: /qa of the whole pull request ran again and still left 0 unproven and 1 not checked in qa-$qa_runs (1 of them put off until after the merge by a count alone" \
  --check
pr_post "the statuses with such a count" 0 "statuses posted" statuses
holds "the status of /qa waits on such a count" \
  jq_true --arg sha "$(git rev-parse HEAD)" \
  '[.[] | select(.sha == $sha and .context == "loop/qa")] | last
   | .state == "pending" and (.description | test("still left 0 unproven and 1 not checked"))' \
  "$GH_STATE/statuses.json"
qa_checked '[]' "" 0 "$put_off"
publish "a later /qa of the whole pull request that lists what it puts off clears it" 0 \
  "   after the merge /qa owes 1 check(s): the build of main" --check
later_check="the run of the build workflow on main, and of the deploy that follows it"
qa_checked '[]' "$(git rev-parse HEAD)" 0 "$(with_items '{"id": "the build of main",
  "verdict": "after_merge", "reason": "the workflow runs only on a push to the base branch",
  "check": "'"$later_check"'"}, {"id": "the release job", "verdict": "after_merge",
  "reason": "it runs when the pull request closes", "check": "the release job of the merge"}')"
publish "what a later /qa puts off is owed beside what an earlier one did" 0 \
  "   after the merge /qa owes 2 check(s): the build of main; the release job" --check
holds "of an item two records put off the newest says the check" \
  jq_true --arg line "- After the merge: the build of main — $later_check" \
  '.[0].body | contains($line)' "$GH_STATE/prs.json"
holds "the status counts what the task puts off" \
  qa_status_ends success ", 0 not checked, 2 after the merge"
qa_checked '[]' "$(git rev-parse HEAD)" 0 \
  "$(with_items '{"id": "the release job", "verdict": "pass"}')"
publish "an item a later /qa checked is owed no more" 0 \
  "   after the merge /qa owes 1 check(s): the build of main" --check
never_says "and is not named among what is owed" "the release job" "$WORK/publish.log"
criterion_is() {
  jq --arg claim "$1" '.exit_criteria = [{text: "the build of main stays green",
                                         verified_by: $claim}]' .review/task.json \
    >"$WORK/task.json" && cp "$WORK/task.json" .review/task.json
}
criterion_is "after the merge: later"
publish "a claim put off until after the merge that names no item is refused" 3 \
  "M5: the criterion 'the build of main stays green' is put off until after the merge and names no item /qa put off until then (after the merge: <the item's id>)" \
  --merge
says "the loop has /qa record the item, or claims what was checked" \
  "   The loop goes on: have /qa record the item with its check, or claim what was checked" \
  "$WORK/publish.log"
criterion_is "after the merge: the release job"
publish "nor is one that names an item a later /qa checked" 3 \
  "names no item /qa put off until then" --merge
holds "nothing is merged on such a claim" not gh_called "pr merge"
criterion_is "after the merge:  the build of main "
publish "an exit criterion that can be checked only after the merge is claimed by its item" 0 \
  "merged T-001" --merge
holds "the squash says that the criterion is checked after the merge" \
  remote_log_has main "Exit-Criteria: 0 verified, 1 to check after the merge"
says "what is owed is listed with the check the newest record gives" \
  "  - the build of main: $later_check" "$WORK/publish.log"
never_says "an item that was checked before the merge is not owed after it" \
  "the release job" "$WORK/publish.log"

# What keeps the list. A merge that cannot write it says so, and run again writes it and
# merges nothing twice. A task whose id is used again reads the records made since the
# landing of the earlier one, and its list goes beside the earlier one's. A list that
# cannot be read holds a later merge like a check with no result.
published_project origin
reviewed_pull_request merge
qa_checked '[]' "" 0 "$put_off"
printf 'a file where the folder goes\n' >"$owed"
publish "a merge that cannot write down what is owed says so" 1 \
  "https://example.test/pull/1 is merged into main, but the checks /qa put off until after the merge could not be written down" \
  --merge
says "and says what the loop does about it" \
  "   The loop goes on: run publish.sh again on this branch: it writes the list and merges nothing twice" \
  "$WORK/publish.log"
holds "that merge is in the base branch" remote_log_has main "Task-Id: T-001"
rm "$owed"
publish "run again, it writes the list and lists what is owed" 0 "$owed_block" --merge
holds "and merges nothing twice" gh_count_is "pr merge" 1
result_is '{"id": "the build of main", "verdict": "pass",
  "evidence": "run 41 of the build on main: success"}'
printf '# After the merge of T-001\n\nRun 41 of the build on main: success.\n' >"$owed/report.md"
later_task T-001
publish "a task that takes the id of one that merged is ready with its own /qa" 0 \
  "ready to merge: https://example.test/pull/2" --check
never_says "what the task that landed put off is not owed by the one that took its id" \
  "after the merge /qa owes" "$WORK/publish.log"
later_check="the run of the build workflow on main, at the second merge commit"
qa_checked '[]' "" 0 "$(with_items "$passed_case, "'{"id": "the build of main",
  "verdict": "after_merge", "reason": "the workflow runs only on a push to the base branch",
  "check": "'"$later_check"'"}')"
publish "a task whose id is used again merges with what it puts off itself" 0 \
  "  - the build of main: $later_check" --merge
says "the results of its checks go beside a list of its own" \
  "the results go into $owed-pr2/results.json" "$WORK/publish.log"
holds "that list is of its own pull request" \
  jq_true --arg check "$later_check" \
  '.task == "T-001" and .pr_number == 2 and (.items | map(.check)) == [$check]' \
  "$owed-pr2/owed.json"
holds "and the list of the earlier pull request stays as it was" \
  jq_true '.pr_number == 1 and (.items | length) == 1' "$owed/owed.json"
printf 'not JSON' >"$owed-pr2/owed.json"
later_task T-002
says "a list that cannot be read is said in the later runs" \
  "OWED — $owed-pr2/owed.json, the list of the checks a merged task owes, is not readable" \
  "$WORK/run.log"
publish "a list of what is owed that cannot be read holds a later merge" 3 \
  "M10: $owed-pr2/owed.json, the list of the checks a merged task owes, is not readable" --merge
says "repairing it is the loop's" \
  "   The loop goes on: repair it — {task, pr_url, pr_number, base, time, items: [{id, reason, check, from}]}, as publish.sh wrote it after the merge" \
  "$WORK/publish.log"
holds "nothing is merged past a list that cannot be read" gh_count_is "pr merge" 2

# A file that is there and empty says nothing: it is no list of this pull request, no
# acceptance of the user and no record of a report that is posted. jq 1.6 ends -e with 0
# on an input that is empty, so what a file says is printed and compared, never taken from
# that exit code; with a newer jq these cases hold either way.
published_project origin
reviewed_pull_request pr
qa_checked '[]' "" 0 "$put_off"
merged_by_a_person https://example.test/pull/1
mkdir -p "$owed" && : >"$owed/owed.json"
publish "an empty file where the list goes is not read as the list of this pull request" 0 \
  "$owed_block"
holds "the list is written beside it" \
  jq_true '.pr_number == 1 and (.items | map(.id)) == ["the build of main"]' \
  "$owed-pr1/owed.json"
says "and the merge says where the results go" \
  "the results go into $owed-pr1/results.json" "$WORK/publish.log"
rm -r "$owed"
printf '[%s]' '{"id": "the build of main", "verdict": "not_checked",
  "reason": "the host was down"}' >"$owed-pr1/results.json"
printf '# After the merge of T-001\n\nThe host was down: nothing was seen.\n' \
  >"$owed-pr1/report.md"
: >"$owed-pr1/open-answered.json"
: >"$owed-pr1/pr-comment.json"
git fetch -q origin
git switch -q main && git pull -q --ff-only origin main
later_task T-002 pr
publish "an empty file is no acceptance of a check that could not be made" 3 \
  "M10: T-001 is merged, and the build of main could not be checked after it (the host was down)" \
  --check
jq -n '{by: "human", answer: "accepted-as-is"}' >"$owed-pr1/open-answered.json"
publish "an empty record of a post does not keep the report off the pull request" 0 \
  "ready to merge: https://example.test/pull/2" --check
holds "the later merge posted that report" posted_count_is "<!-- loop:after-merge T-001 -->" 1
: >"$owed-pr1/pr-comment.json"
pr_post "nor does pr-post.sh after-merge read an empty record as a report that is posted" 0 \
  "report of the checks after the merge of T-001 posted: https://example.test/pull/1" \
  after-merge "$owed-pr1"

# A merge that no run of publish.sh on the task's branch saw. At pr the user merges and
# goes back to the base branch, where publish.sh refuses: the list of what the task owes
# is then written by the next review or landing that finds the squash of the task in the
# history, its /qa records with items put off, their reports on a pull request, and no
# list of that pull request.
published_project origin
reviewed_pull_request pr
qa_checked '[]' "" 0 "$put_off"
merged_by_a_person https://example.test/pull/1
git fetch -q origin
git switch -q main && git pull -q --ff-only origin main
publish "on the base branch publish.sh refuses, also for a task that is merged" 3 \
  "current branch is main, a protected branch"
holds "so no list is written there" not test -e "$owed"
later_task T-002 pr
says "the landing of the next task finds the merged task and says what it owes" \
  "OWED — T-001: the build of main, put off until after its merge: no result ($owed)" \
  "$WORK/land.log"
holds "it wrote the list of the pull request that was merged" \
  jq_true --arg from ".review/runs/qa-$((qa_runs - 1))" \
  '.task == "T-001" and .pr_url == "https://example.test/pull/1" and .pr_number == 1
   and (.time | type) == "number"
   and .items == [{id: "the build of main",
                   reason: "the workflow runs only on a push to the base branch",
                   check: "the run of the build workflow on main, at the merge commit",
                   from: $from}]' "$owed/owed.json"
says "the review of the next task says it too" \
  "OWED — T-001: the build of main, put off until after its merge: no result ($owed)" \
  "$WORK/run.log"
publish "--check of the next task waits for a merge no run of publish.sh saw" 3 \
  "M10: T-001 was merged with checks put off until after its merge, and these have no result that says what was seen: the build of main" \
  --check
written="$(jq '.time' "$owed/owed.json")"
result_is '{"id": "the build of main", "verdict": "pass",
  "evidence": "run 41 of the build on main: success"}'
printf '# After the merge of T-001\n\nRun 41 of the build on main: success.\n' >"$owed/report.md"
publish "with its result and its report the next task is ready" 0 \
  "ready to merge: https://example.test/pull/2" --check
holds "the list found that way is written once" \
  jq_true --argjson written "$written" '.time == $written' "$owed/owed.json"
holds "and its report is on the pull request that was merged" \
  jq_true 'any(.[]; .pr == 1 and (.body | startswith("<!-- loop:after-merge T-001 -->")))' \
  "$GH_STATE/comments.json"

# A task that is not merged owes nothing yet, whatever its /qa put off; nor does a task
# whose /qa put nothing off.
published_project origin
reviewed_pull_request pr
qa_checked '[]' "" 0 "$put_off"
pr_review "a review of a task that is not merged" 0 "CLEAN — gates green"
never_says "says nothing owed by the task itself" "OWED" "$WORK/run.log"
holds "and writes no list before the merge" not test -e "$owed"

# A pull request that was merged at an earlier head than HEAD: what is on the branch since
# is new work and gets a pull request of its own, and the merged one owes its checks.
published_project origin
reviewed_pull_request pr
qa_checked '[]' "" 0 "$put_off"
merged_by_a_person https://example.test/pull/1
pr_work
pr_land "new work on a branch whose pull request was merged gets a pull request of its own" 0 \
  "pull request: https://example.test/pull/2"
holds "and the pull request that was merged owes its checks" \
  jq_true '.pr_number == 1 and (.items | map(.id)) == ["the build of main"]' "$owed/owed.json"

# What /qa could not check is not put off: it holds the merge as before. The refusal names
# the items and says whose turn it is: the loop's first — the work, or the tool or device,
# then /qa of the whole pull request again — and the user's once a second /qa of the whole
# pull request still leaves something open.
published_project origin
reviewed_pull_request merge
ios_not_checked='{"id": "TC-001 on iOS", "verdict": "not_checked",
  "reason": "the simulator did not boot"}'
qa_checked '[]' "" 0 "$(with_items "$passed_case, $ios_not_checked")"
open_qa="qa-$qa_runs"
publish "an item not checked because a device failed holds the merge, as before" 3 \
  "M5: /qa left 0 unproven and 1 not checked in $open_qa" --merge
says "the refusal names what /qa could not check, with its reason" \
  "M5: /qa left 0 unproven and 1 not checked in $open_qa: TC-001 on iOS (the simulator did not boot)" \
  "$WORK/publish.log"
says "what /qa could not check is the loop's to try again first" \
  "   The loop goes on: $loop_restores" "$WORK/publish.log"
never_says "a /qa that left nothing unproven sends nothing back to the work" \
  "an unproven item" "$WORK/publish.log"
never_says "the user is not asked before the loop tried again" "For the user" "$WORK/publish.log"
holds "nothing is merged with an item not checked" not gh_called "pr merge"
qa_checked '[]' "$(git rev-parse HEAD)"
publish "a /qa of less than the whole pull request is no second try" 3 \
  "   The loop goes on: restore what failed" --merge
qa_checked '[]' "" 0 "$(with_items "$passed_case, $ios_not_checked")"
again_qa="qa-$qa_runs"
publish "what a second /qa of the whole pull request still leaves open is the user's" 3 \
  "M5: /qa of the whole pull request ran again and still left 0 unproven and 1 not checked in $again_qa: TC-001 on iOS (the simulator did not boot)" \
  --merge
says "it is beyond what was agreed, with the file their acceptance goes into" \
  "   For the user, beyond what was agreed: merge without that checked, or not; their acceptance goes into .review/runs/$again_qa/open-answered.json, {\"by\": \"human\", \"answer\": \"accepted-as-is\"}" \
  "$WORK/publish.log"
never_says "no words of theirs are asked for beside a record of /qa either" "words" \
  "$WORK/publish.log"
never_says "nothing sends the loop round again then" "The loop goes on" "$WORK/publish.log"
holds "the status of /qa waits with what the second /qa left" \
  jq_true --arg sha "$(git rev-parse HEAD)" \
  '[.[] | select(.sha == $sha and .context == "loop/qa")] | last
   | .state == "pending" and (.description | startswith(
       "/qa of the whole pull request ran again and still left 0 unproven and 1 not checked"))' \
  "$GH_STATE/statuses.json"
: >".review/runs/$again_qa/open-answered.json"
publish "an empty file beside a record of /qa is no acceptance" 3 \
  "M5: /qa of the whole pull request ran again and still left" --merge
jq -n '{by: "agent", answer: "accepted-as-is"}' >".review/runs/$again_qa/open-answered.json"
publish "an acceptance beside a record of /qa that is not the user's settles nothing" 3 \
  "M5: /qa of the whole pull request ran again and still left" --merge
jq -n '{by: "human", answer: "accepted-as-is"}' >".review/runs/$again_qa/open-answered.json"
pr_post "the statuses after the user accepted an item not checked" 0 "statuses posted" statuses
holds "their acceptance, which keeps no words, turns /qa green" status_is loop/qa success
publish "their acceptance lets it merge" 0 "merged T-001" --merge
never_says "a merge with nothing put off owes nothing" "OWED" "$WORK/publish.log"

# "Again" is read of an item, by its id: one that an older record of the task also left
# open, with no acceptance beside that record. An item that is open for the first time is
# the loop's to restore and to check again, whatever else an older /qa left, and so is one
# that the user accepted before. A record of counts alone names no item, so it is read by
# its counts, as before.
published_project origin
reviewed_pull_request merge
android_unproven='{"id": "TC-002 on Android", "verdict": "unproven",
  "reason": "the emulator went away"}'
android_passed='{"id": "TC-002 on Android", "verdict": "pass"}'
ios_passed='{"id": "TC-001 on iOS", "verdict": "pass"}'
tablet_not_checked='{"id": "TC-002 on a tablet", "verdict": "not_checked",
  "reason": "no tablet was attached"}'
loop_tries_again="   The loop goes on: $loop_restores"
qa_checked '[]' "" 0 "$(with_items "$android_unproven")"
qa_checked '[]' "" 0 "$(with_items "$android_passed, $ios_not_checked")"
publish "an item open for the first time is the loop's, whatever an older /qa left open" 3 \
  "M5: /qa left 0 unproven and 1 not checked in qa-$qa_runs: TC-001 on iOS (the simulator did not boot)" \
  --merge
says "the loop restores what failed and has /qa check it again" "$loop_tries_again" \
  "$WORK/publish.log"
never_says "the user is not asked about an item no /qa left open before" "For the user" \
  "$WORK/publish.log"
qa_checked '[]' "" 0 "$(with_items "$android_passed, $ios_passed, $tablet_not_checked")"
accepted_qa="qa-$qa_runs"
publish "after an item was restored and passed, another that fails once is the loop's too" 3 \
  "M5: /qa left 0 unproven and 1 not checked in $accepted_qa: TC-002 on a tablet (no tablet was attached)" \
  --merge
says "the loop tries that one again as well" "$loop_tries_again" "$WORK/publish.log"
never_says "nor is the user asked about that one yet" "For the user" "$WORK/publish.log"
jq -n '{by: "human", answer: "accepted-as-is"}' \
  >".review/runs/$accepted_qa/open-answered.json"
qa_checked '[]' "" 0 "$(with_items "$android_passed, $ios_passed, $tablet_not_checked")"
publish "an item the user accepted in an older record is no second try in a newer one" 3 \
  "M5: /qa left 0 unproven and 1 not checked in qa-$qa_runs: TC-002 on a tablet (no tablet was attached)" \
  --merge
never_says "the user is not asked for what they accepted as if /qa had tried again" \
  "For the user" "$WORK/publish.log"
qa_checked '[]' "" 0 "$(with_items "$android_passed, $ios_passed, $tablet_not_checked")"
publish "the same item left open again by the next /qa of the whole pull request is the user's" 3 \
  "M5: /qa of the whole pull request ran again and still left 0 unproven and 1 not checked in qa-$qa_runs: TC-002 on a tablet (no tablet was attached)" \
  --merge
says "and that stop is beyond what was agreed" "   For the user, beyond what was agreed: " \
  "$WORK/publish.log"
qa_checked '[]' "" 0 "$(with_items "$android_passed, $tablet_not_checked"',
  {"id": "TC-001 on a foldable", "verdict": "unproven",
   "reason": "the recording does not show the fold"}')"
publish "one item left open again beside one open for the first time is still the loop's" 3 \
  "M5: /qa left 1 unproven and 1 not checked in qa-$qa_runs: TC-002 on a tablet (no tablet was attached); TC-001 on a foldable (the recording does not show the fold)" \
  --merge
says "with an item unproven and one not checked the loop's line names both steps" \
  "   The loop goes on: an unproven item goes back to the work; $loop_restores" \
  "$WORK/publish.log"
qa_checked '[]' "" 1
publish "a record of counts alone is read by its counts: an older record left something open" 3 \
  "M5: /qa of the whole pull request ran again and still left 1 unproven and 0 not checked in qa-$qa_runs" \
  --merge
qa_checked '[]' "" 0 "$(with_items '{"id": "TC-001 on a watch", "verdict": "not_checked",
  "reason": "no watch was paired"}')"
publish "and an item is read as left open before by an older record of counts alone" 3 \
  "M5: /qa of the whole pull request ran again and still left 0 unproven and 1 not checked in qa-$qa_runs: TC-001 on a watch (no watch was paired)" \
  --merge

published_project origin
printf 'fun util() = 1\n' >src/util.kt
git add src/util.kt && git commit -q -m util && git push -q origin main
set_level pr
pr_work
pr_land "a landing to review" 0 "pull request: https://example.test/pull/1"
touch "$GH_STATE/review-422"
pr_review "a review whose comments on lines GitHub refuses" 3 "accepted (>= major): 1" \
  "$on_and_off_the_diff" "$accepted_and_rejected"
holds "it says so" grep -qF "422" "$WORK/run.log"
holds "it is posted again with every finding in its body" \
  jq_true 'any(.[]; .kind == "review" and (.body | contains("F-001") and contains("F-002")))' \
  "$GH_STATE/comments.json"
holds "and with none on a line" not jq_true 'any(.[]; .kind == "line")' "$GH_STATE/comments.json"

published_project origin
set_level pr
pr_work
printf '{"findings":[]}' >"$WORK/reviewer.json"
printf '{"verdicts":[]}' >"$WORK/maintainer.json"
REVIEWER_CMD="cat $WORK/reviewer.json #" MAINTAINER_CMD="cat $WORK/maintainer.json #" \
  "$LIB_DIR/review.sh" --task-file .review/task.json --dry-run >"$WORK/run.log" 2>&1
check "--dry-run at pr reviews the uncommitted work" 0 "CLEAN — gates green" $? "$WORK/run.log"
holds "and asks gh nothing" not test -e "$GH_STATE/calls"
pr_review "the review refuses work not committed" 1 "commit it with land.sh first"
touch "$GH_STATE/create-fails"
pr_land "a landing whose pull request could not be opened" 4 "could not open a pull request"
rm "$GH_STATE/create-fails"
pr_review "the review refuses a branch with no pull request: publish.sh opens it" 1 \
  "   The loop goes on: run publish.sh alone: it opens the pull request, or says what stops it"
says "the review says that the branch has no pull request" \
  "REVIEW REFUSED — task/T-001 has no open pull request into main" "$WORK/run.log"
never_says "and sends no one to the user for it" "For the user" "$WORK/run.log"
publish "publish.sh alone opens it" 0 "pull request: https://example.test/pull/1"
publish "a review of --dry-run stands for no review on the pull request" 3 \
  "M1: no review run of T-001 on https://example.test/pull/1" --check
printf '#!/bin/sh\nexit 1\n' >"$GH_REMOTE/hooks/pre-receive"
chmod +x "$GH_REMOTE/hooks/pre-receive"
pr_work
pr_land "a landing whose push fails" 4 "the push to origin failed"
rm "$GH_REMOTE/hooks/pre-receive"
pr_review "the review refuses a pull request behind HEAD" 1 \
  "is behind HEAD — run publish.sh alone, then review again"
publish "publish.sh alone pushes it" 0 "pull request: https://example.test/pull/1"
pr_review "then the review runs" 0 "CLEAN — gates green"
# The remote branch moves to a commit this copy does not have.
elsewhere="$(GIT_AUTHOR_NAME=x GIT_AUTHOR_EMAIL=x@example.com \
  GIT_COMMITTER_NAME=x GIT_COMMITTER_EMAIL=x@example.com \
  git -C "$GH_REMOTE" commit-tree "task/T-001^{tree}" -p task/T-001 -m "someone else")"
git -C "$GH_REMOTE" update-ref refs/heads/task/T-001 "$elsewhere"
pr_review "a head pushed from elsewhere is the user's" 1 \
  "   For the user, only they can: bring the two together: that commit was pushed to "\
"task/T-001 from elsewhere"
says "the review says which head the pull request has" \
  "the head of https://example.test/pull/1 is $elsewhere, which HEAD does not contain" \
  "$WORK/run.log"

published_project origin
set_level pr ASK_AFTER_RUNS=2
printf '#!/usr/bin/env bash\necho %s >"$1"\nexit 1\n' \
  "'{\"test\":{\"status\":\"fail\",\"blocking\":true,\"command\":\"false\",\"output\":\"red\"}}'" \
  >.review/gates.sh
pr_work
pr_land "red gates refuse a landing at pr" 3 "gates are red at landing time" --run "$WORK"
holds "a --run given at pr is said to be unused" printed "--run is not used"
pr_land "a second time too" 3 "gates are red at landing time"
pr_land "past ASK_AFTER_RUNS landings that did not commit, land.sh says what was red" 3 \
  "2 landings of T-001 failed at or after their gates since the count started "\
"(ASK_AFTER_RUNS=2): test red; test red"
says "and the loop's next step" \
  "   The loop goes on: run .review/gates.sh alone until it is green, then land with "\
"--past-limit --because" \
  "$WORK/land.log"
never_says "two red landings of the same work are no question" "the user" "$WORK/land.log"
pr_land "--past-limit without its reason is refused there too" 1 \
  '--past-limit at this stop needs --because "<what was mended>"' --past-limit
pr_land "a reason of blanks is no reason at a landing either" 1 \
  '--past-limit at this stop needs --because "<what was mended>"' --past-limit --because "  "
pr_land "--past-limit lands once more" 3 "gates are red at landing time" \
  --past-limit --because "the gate is mended"
landing_records "the landing records what passed the limit" \
  '.past_limit == true and .past_limit_kind == "loop" and .because == "the gate is mended"
   and .user_decided == null and .result == "red"'
cp "$WORK/gates.green" .review/gates.sh
pr_land "after it the count starts again" 0 "landed T-001 on task/T-001"
pr_work
pr_land "--past-limit below the limit is refused" 1 "only for a task at its limit" --past-limit
pr_land "--because without --past-limit is a usage error at a landing too" 1 \
  "--because goes with --past-limit" --because "the gate is mended"
pr_land "an empty --because without --past-limit is one at a landing too" 1 \
  "--because goes with --past-limit" --because ""
pr_land "and so is --user-decided at a landing" 1 "--user-decided goes with --past-limit" \
  --user-decided

# land.sh reads its landings as review.sh reads its runs. At the limit, the newest three
# that failed the same way — the same gates red with the same output but for its
# numbers — each after a change of the work, are the loop's the first time: it finds
# the cause and lands with its reason. When the limit comes again with the gates red
# that way after such a landing, the reason did not hold, and that is the user's.
# Anything else is the loop's: the same work again, or other gates each time.
published_project origin
set_level pr ASK_AFTER_RUNS=3
red_at_landing() {
  printf '#!/usr/bin/env bash\necho %s >"$1"\nexit 1\n' \
    "'{\"test\":{\"status\":\"fail\",\"blocking\":true,\"command\":\"false\",\"output\":\"$1\"}}'" \
    >.review/gates.sh
}
# A landing a case needs before it, which its gates must refuse.
refused_landing() {
  local actual_exit
  "$LIB_DIR/land.sh" --task-file .review/task.json "$@" >"$WORK/land.log" 2>&1
  actual_exit=$?
  [ "$actual_exit" -eq 3 ] && grep -qF "condition 3: " "$WORK/land.log" \
    && ! grep -qF "since the count started" "$WORK/land.log" && return 0
  echo "FAIL  a landing on the way ($*): expected a refusal for its gates, "\
"got exit $actual_exit — log follows"
  sed 's/^/      /' "$WORK/land.log"
  FAILURES=$((FAILURES + 1))
}
for seconds in 6 7 9; do
  red_at_landing "the pickup test fails in ${seconds}s"
  pr_work
  refused_landing
done
landing_records "a landing records its work and what was red" \
  '(.work | type) == "string" and (.same | type) == "string" and .result == "red"
   and .past_limit_kind == null and .because == null and .user_decided == null
   and .stop == null'
pr_work
pr_land "three landings red the same way after changes stop the next" 3 \
  "3 landings of T-001 failed at or after their gates since the count started "\
"(ASK_AFTER_RUNS=3), the last 3 the same way after changes of the work: test red"
says "the first time that limit is the loop's, which finds the cause" \
  "   The loop goes on: the changes between those landings did not move it, and land.sh "\
"cannot tell fixes that do not close a failure from a machine that failed each time" \
  "$WORK/land.log"
says "it says what passes the limit" \
  'land with --past-limit --because "<what the cause was, and what was done about it>"' \
  "$WORK/land.log"
never_says "the same gates red the first time are no question" "the user" "$WORK/land.log"
pr_land "with no reason that limit is not passed" 1 \
  '--past-limit at this stop needs --because "<what the cause was, and what was done about it>"' \
  --past-limit
pr_land "the user's decision does not pass it at a landing either" 1 \
  "this stop is the loop's: --user-decided is for a stop that is the user's" \
  --past-limit --user-decided
pr_land "the cause the loop found passes the limit" 3 "gates are red at landing time" \
  --past-limit --because "the build was stale and is made from nothing"
landing_records "and the landing records which stop it passed, and the reason" \
  '.stop == "same-end-after-changes" and .past_limit_kind == "loop" and .user_decided == null
   and .because == "the build was stale and is made from nothing" and .past_limit == true'
pass_of_the_landings="$(basename "$(dirname "$(newest_landing)")")"
for seconds in 3 4 5; do
  red_at_landing "the pickup test fails in ${seconds}s"
  pr_work
  refused_landing
done
pr_work
pr_land "the same gates red through three more changes after the loop's reason stop it again" 3 \
  "3 landings of T-001 failed at or after their gates since the count started "\
"(ASK_AFTER_RUNS=3), the last 3 the same way after changes of the work: test red"
says "it says which reason did not hold" \
  "test red — as before $pass_of_the_landings passed this limit with the loop's reason, which "\
"did not hold: the build was stale and is made from nothing" "$WORK/land.log"
says "it says that the work does not converge" \
  "   For the user, the work does not converge: the same gates stayed red through the cause "\
"the loop found and the fixes after it" "$WORK/land.log"
says "what they decide" \
  "whether to go on trying, to stop the task here, or to change what is asked of it" \
  "$WORK/land.log"
says "and how the landing goes on once they decided" \
  "land.sh --past-limit --user-decided then lands once more" "$WORK/land.log"
pr_land "there --past-limit takes --user-decided" 1 "this stop takes --user-decided" \
  --past-limit --because "the gate is mended"
pr_land "--past-limit alone does not pass it either" 1 "this stop takes --user-decided" \
  --past-limit
pr_land "--user-decided takes no words at a landing either" 1 "unknown argument: go on" \
  --past-limit --user-decided "go on"
pr_land "beside the user's decision a landing takes no reason either" 1 \
  "this stop takes --user-decided alone" --past-limit --user-decided --because "they said go on"
pr_land "once the user decided to go on the landing runs" 3 "gates are red at landing time" \
  --past-limit --user-decided
landing_records "and the landing records that they decided, and no words" \
  '.user_decided == true and .past_limit_kind == "user" and .because == null
   and .past_limit == true and .stop == "same-end-after-changes"'
for attempt in first second third; do
  refused_landing
done
pr_land "three landings red the same way on the same work are a retry, not a question" 3 \
  "3 landings of T-001 failed at or after their gates since the count started "\
"(ASK_AFTER_RUNS=3): test red; test red; test red"
says "the loop mends the gates" "   The loop goes on: run .review/gates.sh alone" "$WORK/land.log"
never_says "a retry is no question at a landing" "the user" "$WORK/land.log"
refused_landing --past-limit --because "the cache is cleared"
for output in "a is undefined" "b is undefined" "c is undefined"; do
  red_at_landing "$output"
  pr_work
  refused_landing
done
pr_work
pr_land "landings red with another output each time, after changes, are the loop's" 3 \
  "(ASK_AFTER_RUNS=3): test red; test red; test red"
never_says "what differs each time is no question" "the user" "$WORK/land.log"
refused_landing --past-limit --because "each was a defect of its own"
printf '#!/usr/bin/env bash\nexit 143\n' >.review/gates.sh
for attempt in first second third; do refused_landing; done
pr_land "gates that did not run are said as that" 3 \
  "(ASK_AFTER_RUNS=3): the gates did not run; the gates did not run; the gates did not run"
says "and are the loop's" "   The loop goes on: run .review/gates.sh alone" "$WORK/land.log"
# A landing recorded before land.sh kept its work and what was red is read as it is.
for record in .review/runs/land-*/landing.json; do
  jq 'del(.work, .same, .past_limit_kind, .because, .user_decided)' "$record" >"$record.old" \
    && mv "$record.old" "$record"
done
pr_land "landings recorded before their work was kept are read from what they left" 3 \
  "(ASK_AFTER_RUNS=3): the gates did not run; the gates did not run; the gates did not run"

# A gate that is red now and then, with landings that commit between, shows that the
# gates do go green: the newest three landings are read whatever came of them, and three
# that did not commit with others between them are no circle of the work.
published_project origin
set_level pr ASK_AFTER_RUNS=3
for attempt in first second third; do
  red_at_landing "the pickup test fails"
  pr_work
  refused_landing
  cp "$WORK/gates.green" .review/gates.sh
  [ "$attempt" = third ] \
    || pr_land "after the $attempt red landing the same work lands" 0 "landed T-001 on task/T-001"
done
pr_land "a gate red now and then, with landings that commit between, is no circle" 3 \
  "3 landings of T-001 failed at or after their gates since the count started "\
"(ASK_AFTER_RUNS=3): test red; test red; test red"
says "that limit is the loop's" "   The loop goes on: run .review/gates.sh alone" "$WORK/land.log"
never_says "a gate that goes green between is no question" "the user" "$WORK/land.log"

# A different end between starts the row again: after a landing that passed the limit with
# the loop's reason, a landing that commits, and then the same gates red three more times
# after changes, are the first time once more, and the loop's.
published_project origin
set_level pr ASK_AFTER_RUNS=3
for attempt in first second third; do
  red_at_landing "the pickup test fails"
  pr_work
  refused_landing
done
pr_work
refused_landing --past-limit --because "the service was down and is up again"
cp "$WORK/gates.green" .review/gates.sh
pr_land "after the loop's reason the work lands with green gates" 0 "landed T-001 on task/T-001"
for attempt in first second third; do
  red_at_landing "the pickup test fails"
  pr_work
  refused_landing
done
pr_work
pr_land "a landing that committed between starts the row again" 3 \
  "(ASK_AFTER_RUNS=3), the last 3 the same way after changes of the work: test red"
says "and that limit is the loop's again" \
  "   The loop goes on: the changes between those landings did not move it" "$WORK/land.log"
never_says "the first time after a landing that committed is no question" "the user" \
  "$WORK/land.log"

# Each of the three comes after a change: once a landing passed the limit with the loop's
# reason, the oldest of the newest three is compared with the landing before it as well,
# which is the one that passed when no other came between. A landing again on the work of
# the one that passed is a retry: the limit after it is the limit alone, the loop's, and
# the user's comes when the limit is there again with three landings after changes.
published_project origin
set_level pr ASK_AFTER_RUNS=3
for attempt in first second third; do
  red_at_landing "the pickup test fails"
  pr_work
  refused_landing
done
pr_work
refused_landing --past-limit --because "the build was stale and is made from nothing"
pass_of_the_landings="$(basename "$(dirname "$(newest_landing)")")"
refused_landing
for attempt in second third; do
  pr_work
  refused_landing
done
pr_work
pr_land "a landing again on the work of the one that passed the limit is none of the three" 3 \
  "3 landings of T-001 failed at or after their gates since the count started "\
"(ASK_AFTER_RUNS=3): test red; test red; test red"
says "the limit after such a retry is the loop's" \
  "   The loop goes on: run .review/gates.sh alone" "$WORK/land.log"
never_says "two landings after a change since the loop's reason are no question" "the user" \
  "$WORK/land.log"
pr_land "the loop's reason passes the limit after such a retry" 3 \
  "gates are red at landing time" --past-limit --because "the cache is cleared"
landing_records "and that landing records that it passed the limit alone" \
  '.stop == "landings" and .past_limit_kind == "loop" and .because == "the cache is cleared"'
for attempt in first second third; do
  pr_work
  refused_landing
done
pr_work
pr_land "three landings since, each after a change, are then the user's" 3 \
  "test red — as before $pass_of_the_landings passed this limit with the loop's reason, which "\
"did not hold: the build was stale and is made from nothing"
says "and the landing says that the work does not converge" \
  "   For the user, the work does not converge: the same gates stayed red through the cause "\
"the loop found and the fixes after it" "$WORK/land.log"

# The landing of land.sh below the pull request levels is such a record: the new task
# under the id starts its own count.
published_project origin
set_level on ASK_AFTER_RUNS=1
git switch -q -c work
reviewed_change
step "the landing of the task" "$WORK/land.log" \
  "$LIB_DIR/land.sh" --task-file .review/task.json --run "$run"
sleep 1
pr_work
pr_review "a task under the id of one that land.sh landed has its own count" 0 \
  "CLEAN — gates green"

# At the pull request levels the squash of the merge is that record, and a commit of
# land.sh on the branch of the pull request is none: the reviews and the landings of the
# task that merged are not counted for the new task under its id.
published_project origin
set_level merge ASK_AFTER_RUNS=2
red_at_landing "the pickup test fails"
pr_work
refused_landing
cp "$WORK/gates.green" .review/gates.sh
step "the landing of the work" "$WORK/land.log" "$LIB_DIR/land.sh" --task-file .review/task.json
pr_review_quietly && qa_checked
step "the merge of the task" "$WORK/publish.log" \
  "$LIB_DIR/publish.sh" --task-file .review/task.json --merge
sleep 1
pr_work
step "the landing of the new task" "$WORK/land.log" \
  "$LIB_DIR/land.sh" --task-file .review/task.json
pr_review_quietly
run_records "the first review of a task under the id of one that merged is the first of its count" \
  '.count == 1'
red_at_landing "the pickup test fails"
pr_work
refused_landing
cp "$WORK/gates.green" .review/gates.sh
pr_land "a red landing of the task that merged is none of the new task" 0 \
  "landed T-001 on task/T-001"

# On the pull request the summary of a run counts reviews, and says what passed a stop.
published_project origin
set_level pr ASK_AFTER_RUNS=3
pr_work
step "the landing of the work" "$WORK/land.log" "$LIB_DIR/land.sh" --task-file .review/task.json
pr_review "a review of the pull request is its first review" 0 "CLEAN — gates green"
holds "the summary on the pull request counts reviews" posted "Review 1 of 3 (ASK_AFTER_RUNS)."
printf '#!/usr/bin/env bash\necho %s >"$1"\nexit 1\n' \
  "'{\"test\":{\"status\":\"fail\",\"blocking\":true,\"command\":\"false\",\"output\":\"red\"}}'" \
  >.review/gates.sh
pr_review "a run with red gates on the pull request makes no review" 2 "GATES RED"
holds "and its summary says so" posted "gates red. No review was made in this run."
cp "$WORK/gates.green" .review/gates.sh
answer_is_wrong="{\"findings\": [$(pr_finding F-001 src/answer.kt 1 'fun answer()')]}"
accepted="{\"verdicts\": [$(pr_verdict F-001 accept no-rule-fired)]}"
pr_review "the second review accepts a finding" 3 "accepted (>= major): 1" \
  "$answer_is_wrong" "$accepted"
holds "the red run between is not counted" posted "Review 2 of 3 (ASK_AFTER_RUNS)."
pr_review "and so does the third" 3 "accepted (>= major): 1" "$answer_is_wrong" "$accepted"
pr_review "at the limit of reviews the pull request gets no run" 6 \
  "LIMIT OF REVIEWS — T-001 has had 3 reviews since the count started, 4 runs in all" \
  "$answer_is_wrong" "$accepted"
printf '%s' "$answer_is_wrong" >"$WORK/reviewer.json"
printf '%s' "$accepted" >"$WORK/maintainer.json"
REVIEWER_CMD="cat $WORK/reviewer.json #" MAINTAINER_CMD="cat $WORK/maintainer.json #" \
  "$LIB_DIR/review.sh" --task-file .review/task.json --past-limit \
  --because "each was a defect of its own." >"$WORK/run.log" 2>&1
check "the loop's reason passes the limit on the pull request" 3 "accepted (>= major): 1" $? \
  "$WORK/run.log"
holds "the summary of a run past the limit says why" posted \
  "The limit was passed on the loop's judgement: each was a defect of its own."
holds "with one full stop" not posted "its own.."
# The same finding after each of two fixes, each landed on the pull request: a circle.
for fix in first second; do
  pr_work
  step "the landing of the $fix fix" "$WORK/land.log" \
    "$LIB_DIR/land.sh" --task-file .review/task.json
  pr_review "the review after the $fix fix accepts the finding again" 3 \
    "   again after a change: F-001 src/answer.kt:1" "$answer_is_wrong" "$accepted"
done
pr_review "on the pull request too a third time in a row review.sh stops" 6 \
  "NOT CONVERGING — the fixes of T-001 do not close a finding of the review" \
  "$answer_is_wrong" "$accepted"
REVIEWER_CMD="cat $WORK/reviewer.json #" MAINTAINER_CMD="cat $WORK/maintainer.json #" \
  "$LIB_DIR/review.sh" --task-file .review/task.json --past-limit --user-decided \
  >"$WORK/run.log" 2>&1
check "once the user decided to go on the pull request is reviewed again" 3 \
  "accepted (>= major): 1" $? "$WORK/run.log"
holds "and the summary says that the stop was passed on their decision" posted \
  "The stop was passed on the user's decision."

# A failure of /qa at the pull request levels: item M5 says the same as condition 7.
published_project origin
reviewed_pull_request merge
qa_checked '[{"case": "TC-001"}]'
publish "at merge too a /qa failure is the loop's to fix" 3 "   The loop goes on: fix it" --merge
holds "there it is item M5 of the merge" grep -qF \
  "M5: a /qa failure without an end-to-end test seen red, then green: TC-001" "$WORK/publish.log"
holds "and its refusal names no user" not grep -qF "the user" "$WORK/publish.log"
holds "there too pr-post.sh qa said first that the failing case is the loop's" grep -qF \
  "   The loop goes on: have /qa write the case of TC-001, then fix it" "$WORK/qa.log"
holds "the status of /qa gives the reason, and not whose turn it is" \
  jq_true --arg sha "$(git rev-parse HEAD)" '
    [.[] | select(.sha == $sha and .context == "loop/qa")] | last
    | .state == "failure" and .description
        == "a /qa failure without an end-to-end test seen red, then green: TC-001"' \
  "$GH_STATE/statuses.json"

# The record of /qa at the pull request levels: one whose items do not hold stops the
# merge where the description is written, which reads every record of the task.
published_project origin
reviewed_pull_request merge
cp ".review/runs/qa-$qa_runs/qa.json" "$WORK/qa.json"
jq '. + {items: [{id: "TC-001", verdict: "pass"}, {id: "the build", verdict: "pass"}]}' \
  "$WORK/qa.json" >".review/runs/qa-$qa_runs/qa.json"
publish "at merge a /qa record whose items do not match its counts stops the merge" 1 \
  "its items do not hold" --merge
holds "and it says which record, and what" grep -qF \
  ".review/runs/qa-$qa_runs/qa.json: 2 item(s) say pass and counts.pass is 3" "$WORK/publish.log"
holds "nothing is merged on such a record" not gh_called "pr merge"
jq '. + {items: [{id: "TC-001", verdict: "pass"}, {id: "TC-002", verdict: "pass"},
                 {id: "the build", verdict: "pass"}]}' \
  "$WORK/qa.json" >".review/runs/qa-$qa_runs/qa.json"
publish "with the items its counts give, it merges" 0 "merged T-001" --merge

# What /qa left, at the pull request levels: pr-post.sh qa says it first, then posts the
# report. What nothing written describes is asked there, once, and holds no merge: --check
# and the merge end with a line that names it and says that it is not asked again there,
# and the description of the pull request carries it.
ends_with() { tail -1 "$1" | grep -qF -- "$2"; }
what_should_be="For the user, what should be: a double tap on a shelf opens it twice (Shelves)"
double_tap_seen='{"behaviour_without_requirement":
  [{"what": "a double tap on a shelf opens it twice", "where": "Shelves"}]}'
published_project origin
reviewed_pull_request merge
qa_recorded '[]' "" 0 "$double_tap_seen"
pr_post "at the pull request levels pr-post.sh qa says what /qa left too" 0 \
  "   $what_should_be — /qa saw it" qa "$qa_folder"
says "right after /qa is where the question is asked" \
  "no requirement, exit criterion or case says what should happen: ask it once, in their words"
holds "it says so before it asks gh for anything" \
  [ "$(grep -n -m1 -F "$what_should_be" "$WORK/post.log" | cut -d: -f1)" -lt \
    "$(grep -n -m1 -F "report of $(basename "$qa_folder") posted" "$WORK/post.log" | cut -d: -f1)" ]
holds "then it posts the report" posted "<!-- loop:qa $(basename "$qa_folder") -->"
holds "the description of the pull request carries the question" \
  jq_true --arg line "- $what_should_be" '.[0].body | contains($line)' "$GH_STATE/prs.json"
publish "what nothing written describes leaves the pull request ready to merge" 0 \
  "ready to merge" --check
holds "--check ends with the question" ends_with "$WORK/publish.log" "   $what_should_be"
says "--check names it, and says that it is not asked again there" \
  "$what_should_be $not_asked_again" "$WORK/publish.log"
never_says "nothing at --check tells the loop to ask it" "ask it" "$WORK/publish.log"
publish "what nothing written describes does not hold the merge" 0 "merged T-001" --merge
holds "the merge ends with it" ends_with "$WORK/publish.log" "   $what_should_be"
holds "and says it once" [ "$(grep -cF "$what_should_be" "$WORK/publish.log")" -eq 1 ]
says "the merge names it, and says that it is not asked again there" \
  "$what_should_be $not_asked_again" "$WORK/publish.log"
never_says "nothing at the merge tells the loop to ask it" "ask it" "$WORK/publish.log"
cp "$qa_folder/qa.json" "$WORK/qa.json"
jq '. + {items: [{id: "TC-001", verdict: "pass"}]}' "$WORK/qa.json" >"$qa_folder/qa.json"
pr_post "at the pull request levels a record that does not hold is posted nowhere" 1 \
  "qa.json does not hold: 1 item(s) say pass and counts.pass is 3" qa "$qa_folder"

# A landing that commits says it after the line of its commit.
published_project origin
git checkout -q -b feature || fail_setup "feature branch of a landing that commits"
jq -n --argjson seen "$double_tap_seen" '{task: "T-001", failures: []} + $seen' \
  >.review/runs/0-qa-T-001/qa.json
land_change "a landing that commits says what nothing written describes" 0 \
  "   $what_should_be" on
holds "after the line of the commit" ends_with "$WORK/land.log" "   $what_should_be"
says "a landing that commits names it too, and says that it is not asked again there" \
  "$what_should_be $not_asked_again" "$WORK/land.log"
never_says "and nothing there tells the loop to ask it" "ask it" "$WORK/land.log"

# ---- what people wrote, and a read that failed -------------------------------

# A failed read of the comments is told by the exit code of each request, never by a
# word in what was read: a comment may quote the log of a build.
published_project origin
set_level merge
pr_work
step "the landing of the work" "$WORK/land.log" "$LIB_DIR/land.sh" --task-file .review/task.json
pr_review "a rejected finding whose evidence quotes the log of a build" 0 "rejected          : 1" \
  "{\"findings\": [$(pr_finding F-001 src/answer.kt 1 'fun answer()' \
    | jq -c '.evidence = "the log of the run says BUILD FAILED in 6s"')]}" \
  "{\"verdicts\": [$(pr_verdict F-001 reject contradicts-green-gate)]}"
holds "it is posted on its line, with those words" \
  jq_true 'any(.[]; .kind == "line" and .path == "src/answer.kt"
              and (.body | contains("BUILD FAILED in 6s")))' "$GH_STATE/comments.json"
qa_checked
publish "the loop's own comment that quotes BUILD FAILED does not stop the merge" 0 \
  "merged T-001" --merge

published_project origin
reviewed_pull_request merge
a_person_comments_on_line src/answer.kt 1 "The step fails: the log says BUILD FAILED in 6s."
on_line="$(jq -r '[.[] | select(.body | startswith("The step fails"))][0].id' \
  "$GH_STATE/comments.json")"
pr_post "a person's comment on a line that says BUILD FAILED is read like any other" 0 \
  "BUILD FAILED in 6s" comments
publish "the merge waits for its answer, and for nothing else" 5 "are not settled" --merge
holds "the read of the comments did not fail" not grep -qF "could not read" "$WORK/publish.log"
printf 'The step passes now: the build is green.\n' >"$WORK/reply.md"
pr_post "the loop answers it as fixed" 0 "reply to $on_line (fixed) posted" \
  reply "$on_line" fixed "$WORK/reply.md"
printf 'comments|reviews' >"$GH_STATE/api-fails"
publish "when gh cannot read the comments, the merge says so" 1 \
  "gh could not read the comments of https://example.test/pull/1" --merge
pr_post "and so does pr-post.sh comments" 1 \
  "gh could not read the comments of https://example.test/pull/1" comments
for request in 'issues/.*/comments' 'pulls/.*/reviews' 'pulls/.*/comments'; do
  printf '%s' "$request" >"$GH_STATE/api-fails"
  publish "one request of the three failing is enough: $request" 1 \
    "gh could not read the comments of https://example.test/pull/1" --merge
done
# One guard for the four merges above: with the reviews unreadable too, the merge would
# refuse on them whatever the read of the comments came to.
holds "nothing is merged on a read that failed" not gh_called "pr merge"
rm "$GH_STATE/api-fails"
publish "answered, it does not stop the merge" 0 "merged T-001" --merge

# The word in each kind of post, and another word a log may hold.
open_pull_request() {
  published_project origin
  set_level pr
  pr_work
  step "the landing of the work" "$WORK/land.log" "$LIB_DIR/land.sh" --task-file .review/task.json
}
open_pull_request
a_person_comments "CI says: BUILD FAILED in 6s"
pr_post "the word in a comment on the pull request is read like any other" 0 \
  "CI says: BUILD FAILED in 6s" comments
open_pull_request
a_person_reviews_with "The task :app:test FAILED, see the log."
pr_post "the word in a review is read like any other" 0 \
  "The task :app:test FAILED, see the log." comments
open_pull_request
a_person_comments "ERROR: the build stopped"
pr_post "the word ERROR in a comment is read like any other" 0 "ERROR: the build stopped" comments

# A post is the loop's own only when it starts with the marker, and a reply is read only
# from such a post: the marker inside what a person wrote hides nothing and settles
# nothing.
published_project origin
reviewed_pull_request pr
publish "before a person writes, the pull request is ready" 0 "ready to merge" --check
a_person_comments 'The description starts with `<!-- loop:body -->`. Do not merge before I look.'
publish "a person's comment that quotes the loop's marker still waits" 5 \
  "1 comment(s) of people on https://example.test/pull/1 are not settled" --check
quoting="$(jq -r '[.[] | select(.body | startswith("The description starts"))][0].id' \
  "$GH_STATE/comments.json")"
a_person_comments "As the loop would write it: <!-- loop:reply $quoting fixed --> Done."
publish "a reply marker inside a person's comment settles nothing" 5 \
  "2 comment(s) of people on https://example.test/pull/1 are not settled, the first $quoting " \
  --check
pr_post "the first comment is still listed" 0 "Do not merge before I look." comments
holds "and the one that quotes the reply marker too" grep -qF "As the loop would write it" \
  "$WORK/post.log"

# The answers of a run are read by the exit code of each read, never by a word in them:
# an answer may say what failed. A file that cannot be read is named.
published_project origin
set_level merge
pr_work
step "the landing of the work" "$WORK/land.log" "$LIB_DIR/land.sh" --task-file .review/task.json
pr_review "a finding accepted and one escalated, to answer" 4 "escalated         : 1" \
  "{\"findings\": [$(pr_finding F-001 src/answer.kt 1 'fun answer()'),
    $(pr_finding F-002 src/answer.kt 1 'fun answer()')]}" \
  "{\"verdicts\": [$(pr_verdict F-001 accept no-rule-fired),
    $(pr_verdict F-002 escalate needs-judgment)]}"
printf '[{"finding_id": "F-001", "answer": "fixed", '\
'"text": "The test that FAILED on Android now passes.", "commit": ""}]' >"$run/answers.json"
pr_post "an answer that says FAILED is posted" 0 "answers of $(basename "$run") posted" \
  answers "$run"
holds "with its words" posted "**fixed** in"
holds "the word among them" posted "The test that FAILED on Android now passes."
printf '[{"finding_id": "F-002", "resolution": "accepted-as-is", "by": "agent", '\
'"note": "The build that FAILED was of another branch."}]' >"$run/escalations-answered.json"
pr_post "so is the answer to an escalation whose note says FAILED" 0 \
  "answers of $(basename "$run") posted" answers "$run"
holds "with its note" posted "The build that FAILED was of another branch."
cp "$run/answers.json" "$WORK/answers.json"
printf '[{' >"$run/answers.json"
pr_post "an answers file that is not JSON is not readable, and is named" 1 \
  "the answers of $(basename "$run") are not readable: " answers "$run"
holds "by its path" grep -q "are not readable: .*/$(basename "$run")/answers\\.json\$" \
  "$WORK/post.log"
cp "$WORK/answers.json" "$run/answers.json"
printf '[{' >"$run/escalations-answered.json"
pr_post "nor is a file of answered escalations that is not JSON, and it is named" 1 \
  "the answers of $(basename "$run") are not readable: " answers "$run"
holds "by its path too" \
  grep -q "are not readable: .*/$(basename "$run")/escalations-answered\\.json\$" \
  "$WORK/post.log"
holds "neither posted anything again" \
  posted_count_is "<!-- loop:answer $(basename "$run") F-001 -->" 1

# Whether a reply is there already is read too, not taken from a read that failed: a
# reply that cannot be looked for is not posted a second time.
open_pull_request
a_person_comments "Is 42 the answer the requirements ask for?"
asked="$(jq -r '[.[] | select(.body | startswith("Is 42 the answer"))][0].id' \
  "$GH_STATE/comments.json")"
printf 'It is: REQUIREMENTS.md, "Answer".\n' >"$WORK/reply.md"
pr_post "a reply to a comment on the pull request" 0 \
  "reply to $asked (not-a-problem) posted" reply "$asked" not-a-problem "$WORK/reply.md"
printf 'issues/.*/comments' >"$GH_STATE/api-read-fails"
pr_post "a reply that cannot be looked for is not posted twice" 1 \
  "gh could not read the comments of https://example.test/pull/1" \
  reply "$asked" not-a-problem "$WORK/reply.md"
holds "the reply is there once" \
  posted_count_is "<!-- loop:reply $asked not-a-problem -->" 1
rm "$GH_STATE/api-read-fails"
pr_post "looked for again when gh answers, it is found" 0 "no second one" \
  reply "$asked" not-a-problem "$WORK/reply.md"
holds "and is still there once" \
  posted_count_is "<!-- loop:reply $asked not-a-problem -->" 1

# ---- merge -----------------------------------------------------------------

published_project origin
merged_change "merge with clean checks merges" 0 "merged T-001"
holds "it merges by URL" gh_called "pr merge https://example.test/pull/1 "
holds "it merges with a squash, never a merge commit" gh_called " --squash "
holds "it merges the commit it checked" gh_called "--match-head-commit"
holds "it deletes the branch of the task" gh_called "--delete-branch"
holds "it ends on the base branch" on_branch main
holds "the base branch here is the one on the remote" remote_is main "$(git rev-parse main)"
holds "the base branch gets one commit of the task" \
  [ "$(git rev-list --count "$(git rev-parse main^)..main")" = 1 ]
holds "that commit is the task, with the audit trailers" \
  test "$(git log -1 --format=%s main)" = "T-001: Answer 42"
holds "the base branch carries the Task-Id trailer" \
  test -n "$(git log main --format=%B --grep='Task-Id: T-001')"
holds "and the runs it rests on" \
  test -n "$(git log main --format=%B --grep='^Review-Runs: 1, last ')"
holds "the remote branch is gone" not remote_has task/T-001
holds "the local branch is gone" not local_has task/T-001
publish "publish.sh refuses on a protected branch" 3 "protected branch"

published_project origin
touch "$GH_STATE/moves-the-checkout"
merged_change "merge works with a gh that moves the checkout itself" 0 "merged T-001"
holds "it still ends on the base branch" on_branch main

published_project origin
touch "$GH_STATE/fails-after-merge"
merged_change "a merge gh fails to tidy up after is still a merge" 0 "merged T-001"
holds "that merge ends on the base branch" on_branch main
holds "that says the remote branch may be left" printed "did not finish tidying up"
holds "that merge leaves the remote branch, which gh deletes last" remote_has task/T-001

published_project origin
git switch -q -c develop
git push -q origin develop
start="$(git rev-parse main)"
merged_change "merge into a BASE_BRANCH" 0 \
  "merged T-001: https://example.test/pull/1 into develop" BASE_BRANCH=develop
holds "it ends on that branch" on_branch develop
holds "that branch here is the one on the remote" remote_is develop "$(tip_of develop)"
holds "main is not touched" remote_is main "$start"

published_project origin
git tag main
git push -q origin refs/tags/main
merged_change "merge with a tag named like the base branch" 0 "merged T-001"
holds "the base branch here takes the merge, not the tag" remote_is main "$(tip_of main)"

published_project origin
printf 'none\n' >"$GH_STATE/checks"
merged_change "merge in a repository with no checks but the loop's merges" 0 "merged T-001"

published_project origin
printf 'skipped\n' >"$GH_STATE/checks"
merged_change "skipped checks do not stop a merge" 0 "merged T-001"

published_project origin
printf 'none\npending\n' >"$GH_STATE/checks"
merged_change "checks still pending after CHECKS_WAIT stop the merge" 5 \
  "checks are pending" CHECKS_WAIT=3
holds "a merge never beats the checks to it" not gh_called "pr merge"

published_project origin
printf 'none\npending\npassed\n' >"$GH_STATE/checks"
merged_change "checks that appear and finish within CHECKS_WAIT merge in one run" 0 \
  "merged T-001" CHECKS_WAIT=5

published_project origin
printf 'none\nnone\npassed\n' >"$GH_STATE/checks"
printf 'THRESHOLD=major\nASK_AFTER_RUNS=100\nLANDING=merge\n' >.review/land.conf
pr_work
step "the landing of the work" "$WORK/land.log" "$LIB_DIR/land.sh" --task-file .review/task.json
pr_review_quietly && qa_checked
publish "a land.conf with no CHECKS_WAIT still gives checks time to appear" 0 "merged T-001" \
  --merge
holds "it asked until they did" gh_count_is "pr checks" 3

published_project origin
land_change "a CHECKS_WAIT that is no number refuses" 3 "CHECKS_WAIT=soon" merge CHECKS_WAIT=soon
holds "that refusal stays on main" on_branch main

published_project origin
printf 'pending\n' >"$GH_STATE/checks"
merged_change "merge with pending checks stops short of the merge" 5 \
  "checks are pending on https://example.test/pull/1"
holds "pending checks do not merge" not gh_called "pr merge"
holds "pending checks stay on the branch" on_branch task/T-001
printf 'failing\n' >"$GH_STATE/checks"
publish "publish.sh waits on failing checks" 5 "checks are failing on https://example.test/pull/1" \
  --merge
holds "failing checks do not merge" not gh_called "pr merge"
printf 'cancelled\n' >"$GH_STATE/checks"
publish "a cancelled check did not pass" 5 "checks are failing on https://example.test/pull/1" \
  --merge
holds "a cancelled check does not merge" not gh_called "pr merge"
printf 'cancelled+pending\n' >"$GH_STATE/checks"
publish "a cancelled check says so before a pending one" 5 \
  "checks are failing on https://example.test/pull/1" --merge
printf 'unknown\n' >"$GH_STATE/checks"
publish "a check of a kind nobody knows did not pass" 5 \
  "checks are failing on https://example.test/pull/1" --merge
holds "that check does not merge" not gh_called "pr merge"
printf 'passed\n' >"$GH_STATE/checks"
on_pull_request 1 '.reviewDecision = "CHANGES_REQUESTED"'
publish "publish.sh waits on requested changes" 5 \
  "changes are requested on https://example.test/pull/1" --merge
holds "requested changes do not merge" not gh_called "pr merge"
on_pull_request 1 '.reviewDecision = "APPROVED"'
touch "$GH_STATE/view-fails"
publish "an unreadable review decision stops the merge" 1 "could not read the review decision" \
  --merge
holds "an unreadable review decision does not merge" not gh_called "pr merge"
rm "$GH_STATE/view-fails"
touch "$GH_STATE/refuses-merge"
publish "a merge gh refuses waits with its reason" 5 "the base branch policy prohibits the merge" \
  --merge
says "trying the merge again is the loop's" \
  "   The loop goes on: gh's reason is above; run publish.sh --merge again once it no longer "\
"holds" "$WORK/publish.log"
on_pull_request 1 '.mergeable = "CONFLICTING"'
publish "a merge gh refuses for a conflict is the user's" 5 \
  "   For the user, only they can: merge main into task/T-001: the pull request conflicts "\
"with it" --merge
on_pull_request 1 '.mergeable = "MERGEABLE"'
rm "$GH_STATE/refuses-merge"
publish "publish.sh finishes the merge once nothing stands in the way" 0 "merged T-001" --merge
holds "the waiting opened one pull request" gh_count_is "pr create" 1

published_project origin
reviewed_pull_request merge
touch "$GH_STATE/pushes-at-view"
publish "a pull request that is ahead of HEAD waits" 5 \
  "   For the user, only they can: bring the two together: that commit was pushed to "\
"task/T-001 from elsewhere" --merge
says "its line says which head the pull request has" \
  "PUBLISHING WAITS — the head of https://example.test/pull/1 is " "$WORK/publish.log"
holds "that commit is not merged" not gh_called "pr merge"

# The other way round: this copy is ahead of the pull request, by a landing of the loop's
# files whose push failed. The work is the work the review saw.
published_project origin
reviewed_pull_request merge
printf '#!/bin/sh\nexit 1\n' >"$GH_REMOTE/hooks/pre-receive"
chmod +x "$GH_REMOTE/hooks/pre-receive"
printf '# Tracker\n\n- T-001 done\n' >TASK_TRACKER.md
pr_land "a landing of the loop's files whose push fails" 4 "the push to origin failed"
rm "$GH_REMOTE/hooks/pre-receive"
publish "a pull request that is behind HEAD is the loop's to push" 5 \
  "   The loop goes on: run publish.sh alone, which pushes it, then publish.sh --merge again" \
  --merge
never_says "and nothing of it goes to the user" "For the user" "$WORK/publish.log"
holds "nothing is merged meanwhile" not gh_called "pr merge"
publish "publish.sh alone pushes what the landing could not" 0 \
  "pull request: https://example.test/pull/1"
publish "and then it merges" 0 "merged T-001" --merge

published_project origin
reviewed_pull_request merge
touch "$GH_STATE/pushes-at-checks"
publish "a push during the wait for checks stops the merge: the loop never saw that head" 5 \
  "loop/build is not posted" --merge
holds "that commit does not reach the base branch" not remote_log_has main "someone else"

published_project origin
reviewed_pull_request merge
touch "$GH_STATE/pushes-at-merge"
publish "a push just before the merge is not merged: gh is told the head checked" 5 \
  "gh did not merge" --merge
holds "that push does not reach the base branch" not remote_log_has main "someone else"

# A task whose branch holds another task's commits, which land.sh refuses at these
# levels: a squash of the earlier task never puts them on the base branch.
published_project origin
reviewed_pull_request merge
git switch -q -c task/T-002
git commit -q --allow-empty -m "T-002: made on top by hand" -m "Task-Id: T-002"
task_with_id T-002
step "publish.sh alone opens the stacked pull request" "$WORK/publish.log" \
  "$LIB_DIR/publish.sh" --task-file .review/task.json
pr_review_quietly && qa_checked
publish "a stacked task waits for the earlier one" 5 "also carries T-001" --merge
holds "the earlier task does not reach the base branch through it" \
  not remote_log_has main "Task-Id: T-001"
holds "its pull request stays open" not gh_called "pr merge"
merged_by_a_person https://example.test/pull/1
publish "after a squash of the earlier one it still waits: those commits never reach main" 5 \
  "also carries T-001" --merge
holds "the base branch holds the earlier task, squashed" remote_log_has main "Task-Id: T-001"
holds "and not the stacked one" not remote_log_has main "Task-Id: T-002"

published_project origin
reviewed_pull_request merge
git switch -q main
printf 'from main\n' >src/other.kt
git add src/other.kt && git commit -q -m "moved on" && git push -q origin main
git switch -q task/T-001
git merge -q --no-edit main
publish "a merge of the base by a person is published" 0 "pull request: https://example.test/pull/1"
publish "it changed the work the review saw" 3 "M1: the tree changed after this review ran" \
  --merge
pr_review_quietly && qa_checked
publish "reviewed again, a merge of the base by a person does not stop the merge" 0 \
  "merged T-001" --merge
holds "the task reaches the base branch" remote_log_has main "Task-Id: T-001"
holds "and what the base had" remote_file_has main src/other.kt "from main"

# The checks of a pull request: none, failing, or not read. gh ends with 1 when there are
# none as when its request failed, and the description of a check may hold any words. So
# a list of checks is read by its buckets, and anything else by a second request, which
# says by its exit code and a field whether the pull request has none.
published_project origin
reviewed_pull_request merge
printf 'word\n' >"$GH_STATE/checks"
publish "a check whose description says no checks reported is still a check" 5 \
  "checks are failing on https://example.test/pull/1" --merge
holds "the failing check beside it stops the merge" not gh_called "pr merge"
printf 'passed\n' >"$GH_STATE/checks"
touch "$GH_STATE/checks-fail"
publish "checks that cannot be read are an error, not failing checks" 1 \
  "gh could not read the checks of https://example.test/pull/1" --merge
says "what gh said is shown" "error connecting to api.github.com" "$WORK/publish.log"
never_says "nothing says that checks are failing" "checks are failing" "$WORK/publish.log"
holds "nothing is merged on checks that were not read" not gh_called "pr merge"
publish "--check says of checks that cannot be read what --merge says" 1 \
  "gh could not read the checks of https://example.test/pull/1" --check
printf 'pr checks' >"$GH_STATE/checks-fail"
publish "checks that gh could not list on a pull request that has some are not none" 1 \
  "gh could not read the checks of https://example.test/pull/1" --merge
holds "that merges nothing either" not gh_called "pr merge"
rm "$GH_STATE/checks-fail"
printf 'none\n' >"$GH_STATE/checks"
cp "$GH_STATE/statuses.json" "$WORK/statuses.json"
printf '[]' >"$GH_STATE/statuses.json"
publish "a pull request with no check and no status is told from one that cannot be read" 5 \
  "is not posted" --merge
holds "by a second request, which says that it has none" gh_called "statusCheckRollup"
never_says "and no read failed" "could not read" "$WORK/publish.log"
cp "$WORK/statuses.json" "$GH_STATE/statuses.json"
publish "a repository with no checks is still told from one that cannot be read" 0 \
  "merged T-001" --merge

published_project origin
printf 'unread\npassed\n' >"$GH_STATE/checks"
merged_change "checks that could not be read at first are asked for again within CHECKS_WAIT" 0 \
  "merged T-001" CHECKS_WAIT=5
holds "it asked until gh answered" gh_count_is "pr checks" 2

# ---- the end of a merge ----------------------------------------------------

published_project origin
reviewed_pull_request merge
# A lock on the index stops the checkout, and nothing before the merge writes the index.
touch .git/index.lock
publish "a checkout that cannot move after a merge is an error" 1 "could not move to main" --merge
holds "that error says a rerun pushes nothing" printed "pushes nothing"
holds "that merge happened" remote_log_has main "Task-Id: T-001"
rm .git/index.lock
publish "publish.sh alone finishes the move" 0 "merged T-001" --merge
holds "that rerun pushes nothing back" not remote_has task/T-001
holds "that rerun merges nothing twice" gh_count_is "pr merge" 1
holds "that rerun ends on the base branch" on_branch main

published_project origin
reviewed_pull_request merge
git branch -f main \
  "$(git commit-tree "$(git rev-parse 'main^{tree}')" -p main -m "local work on main")"
publish "a base branch that cannot fast-forward is an error" 1 "could not fast-forward" --merge
says "bringing the base branch in line is the user's" \
  "   For the user, only they can: bring main here in line with origin: publish.sh refuses on "\
"main" "$WORK/publish.log"
holds "it does not say merged" not printed "merged T-001"
publish "run again, it refuses on the base branch, as its message says" 3 "protected branch" \
  --merge
holds "nothing sends anyone to run publish.sh alone" not printed "run publish.sh alone"

published_project origin
git worktree add -q -b task/T-001 "$repository-linked" || fail_setup "linked worktree"
cp -R .review "$repository-linked/"
cd "$repository-linked" || fail_setup "cd linked worktree"
merged_change "merge from a linked worktree with main checked out elsewhere" 0 \
  "checked out in another worktree"
holds "that merge happened" remote_log_has main "Task-Id: T-001"
holds "that worktree stays on its branch" on_branch task/T-001
publish "a rerun there says the same" 0 "checked out in another worktree" --merge
holds "that rerun pushes nothing back" not remote_has task/T-001
holds "that rerun merges nothing twice" gh_count_is "pr merge" 1

# ---- when the push does not go through --------------------------------------

published_project origin
printf '#!/bin/sh\nexit 1\n' >"$GH_REMOTE/hooks/pre-receive"
chmod +x "$GH_REMOTE/hooks/pre-receive"
land_change "land.sh returns 4 when the push fails" 4 \
  "run publish.sh alone, never land.sh again" push
holds "the message of 4 says what a change of code takes" \
  printed "a new pass of the loop on this branch: the work, review.sh, then land.sh"
holds "the output of publish.sh is shown" grep -qF "the push to origin failed" "$WORK/land.log"
holds "that commit landed" \
  [ "$(git log -1 --format='%(trailers:key=Task-Id,valueonly)' | head -1)" = "T-001" ]
holds "that commit is not on the remote" not remote_has task/T-001
publish "a push that still fails is an error" 1 "the push to origin failed"
rm "$GH_REMOTE/hooks/pre-receive"
publish "publish.sh alone finishes once the cause is gone" 0 "published T-001: task/T-001 on origin"
holds "the commit reaches the remote" remote_is task/T-001 "$(git rev-parse HEAD)"

# Whether the remote branch moved is read from git's own line for the branch, never from
# a word of what the push printed: a hook may print any, that line too.
published_project origin
cat >"$GH_REMOTE/hooks/pre-receive" <<'EOF'
#!/bin/sh
echo "[rejected] by the policy of this remote"
printf '!\trefs/heads/task/T-001:refs/heads/task/T-001\t[rejected] (fetch first)\n'
echo "[rejected] says the hook on stderr too" >&2
exit 1
EOF
chmod +x "$GH_REMOTE/hooks/pre-receive"
land_change "a push a hook refuses with the word [rejected] is for land.sh a push that failed" 4 \
  "the push to origin failed" push
never_says "land.sh shows no branch that moved" "moved on origin" "$WORK/land.log"
publish "a hook of the remote that prints [rejected] is not a branch that moved" 1 \
  "the push to origin failed"
never_says "nothing says that the branch moved" "moved on origin" "$WORK/publish.log"
says "what the hook printed is shown" "[rejected] by the policy of this remote" \
  "$WORK/publish.log"
holds "nothing of that push is on the remote" not remote_has task/T-001
rm "$GH_REMOTE/hooks/pre-receive"
# A hook of this copy prints where git prints its own lines, with nothing before its
# words, and before git says where it pushes to. What it prints on stderr is not read,
# whatever it holds.
cat >.git/hooks/pre-push <<'EOF'
#!/bin/sh
echo "[rejected] by the hook of this copy"
printf '!\trefs/heads/task/T-001:refs/heads/task/T-001\t[rejected] (fetch first)\n'
printf 'To origin\n!\trefs/heads/task/T-001:refs/heads/task/T-001\t[rejected] (fetch first)\n' >&2
exit 1
EOF
chmod +x .git/hooks/pre-push
publish "nor is a hook of this copy that prints git's own line for a branch that moved" 1 \
  "the push to origin failed"
never_says "that says of no branch that it moved either" "moved on origin" "$WORK/publish.log"
rm .git/hooks/pre-push
publish "without the hooks the same commit is published" 0 "published T-001: task/T-001 on origin"

# ---- publish.sh alone -------------------------------------------------------

published_project origin
set_level push
publish "publish.sh refuses on main" 3 "protected branch"
holds "that refusal pushes nothing" not remote_has task/T-001
land_change "a landing to publish by hand" 0 "landed T-001 on task/T-001" push
landed="$(git rev-parse HEAD)"
git commit -q --allow-empty -m "made by hand"
publish "publish.sh refuses a HEAD without the Task-Id trailer" 3 \
  "does not carry the trailer Task-Id: T-001"
holds "that refusal pushes nothing" remote_is task/T-001 "$landed"
git reset -q --hard "$landed"
task_with_id T-002
publish "publish.sh refuses a commit made for another task" 3 \
  "does not carry the trailer Task-Id: T-002"
task_with_id T-001
for level in off on; do
  set_level "$level"
  publish "publish.sh refuses at $level" 3 "LANDING=$level in .review/land.conf does not publish"
done
set_level push
git switch -q --detach
publish "publish.sh refuses a detached HEAD" 3 "HEAD is detached"

published_project origin
task_with_id T-10
land_change "a landing of T-10" 0 "landed T-10 on task/T-10" push
task_with_id T-1
publish "publish.sh tells T-1 from T-10" 3 "does not carry the trailer Task-Id: T-1"

published_project origin
git switch -q -c develop
git push -q origin develop
land_change "a commit on a branch that becomes the base" 0 "landed T-001 on develop" on
set_level push BASE_BRANCH=develop
publish "publish.sh refuses on a base branch that is not main" 3 "protected branch"
holds "that refusal pushes nothing" not remote_log_has develop "Task-Id: T-001"

published_project origin
git switch -q -c release
git push -q origin release
land_change "a commit on a branch that becomes protected" 0 "landed T-001 on release" on
set_level push 'PROTECTED_BRANCHES="release"'
publish "publish.sh refuses on a PROTECTED_BRANCHES entry" 3 "protected branch"
holds "that refusal pushes nothing" not remote_log_has release "Task-Id: T-001"

# ---- the remote ------------------------------------------------------------

published_project origin
git remote remove origin
land_change "a project with no remote refuses" 3 "this repository has no remote" push
holds "that refusal comes before the gates" not test -e "$run/gates.land.json"
holds "that refusal stays on main" on_branch main
publish "publish.sh refuses with no remote" 3 "this repository has no remote"
git remote add one "$GH_REMOTE"
git remote add other "$GH_REMOTE"
land_change "several remotes with no origin refuse" 3 "set REMOTE in" push
land_change "a REMOTE that does not exist refuses" 3 "REMOTE=gone in" push REMOTE=gone
land_change "REMOTE names the remote" 0 "landed T-001 on task/T-001" push REMOTE=other
holds "the commit goes to that remote" \
  [ "$(git rev-parse --abbrev-ref '@{upstream}')" = "other/task/T-001" ]

published_project origin
git remote add aaa "$WORK/nowhere.git"
land_change "among several remotes origin is taken" 0 "landed T-001 on task/T-001" push
holds "the commit goes to origin" \
  [ "$(git rev-parse --abbrev-ref '@{upstream}')" = "origin/task/T-001" ]

published_project origin
git init -q --bare -b main "$repository-upstream.git" || fail_setup "second remote"
git remote add upstream "$repository-upstream.git"
merged_change "gh acts on the repository of REMOTE, whatever other remotes there are" 0 \
  "merged T-001"
holds "every question to gh names it" not gh_call_without_repository

published_project origin
start="$(git rev-parse HEAD)"
git remote set-url origin "$WORK/gone.git"
land_change "a remote that cannot be reached refuses" 3 "the remote origin cannot be reached" push
holds "that refusal comes before the gates" not test -e "$run/gates.land.json"
holds "that refusal commits nothing" [ "$(git rev-parse HEAD)" = "$start" ]
land_change "BASE_BRANCH does not excuse it" 3 \
  "the remote origin cannot be reached" push BASE_BRANCH=main
publish "publish.sh refuses it too" 3 "the remote origin cannot be reached"

published_project origin
touch "$GH_STATE/logged-out"
land_change "pr refuses when gh is not logged in" 3 "gh is not logged in" pr
holds "that refusal stays on main" on_branch main
holds "that refusal comes before the gates" not landing_ran
land_change "push does not need gh" 0 "landed T-001 on task/T-001" push

published_project origin
touch "$GH_STATE/no-repo"
land_change "pr refuses when gh cannot see the repository" 3 "gh cannot see" pr
holds "that refusal stays on main" on_branch main

published_project origin
set_level merge
pr_work
PATH="$path_without_gh" "$LIB_DIR/land.sh" --task-file .review/task.json >"$WORK/land.log" 2>&1
check "merge refuses when gh is not installed" 3 "gh is not installed" $? "$WORK/land.log"

# ---- a remote whose host gives no answer ------------------------------------
# An offline project is published to a remote written http://127.0.0.1:1/x/<name>.git, which
# git reaches through a rewrite of that URL to the bare repository (url.<bare>.insteadOf), so
# no request leaves the machine. go_offline takes the rewrite out, after which git cannot
# connect, and makes the file offline: the stand-in of gh then answers no call, and that of
# curl exits 7, no connection. go_online undoes both. What this copy last heard of its remote
# is in .review/runs/.loop/last-heard.json: heard_holds <name> <jq filter>.
offline_project() {
  published_project origin
  offline_url="http://127.0.0.1:1/x/$(basename "$repository").git"
  git remote set-url origin "$offline_url" && git config remote.origin.proxy "" &&
    git config "url.$GH_REMOTE.insteadOf" "$offline_url" || fail_setup "offline project"
}
go_offline() {
  git config --unset "url.$GH_REMOTE.insteadOf"
  touch "$GH_STATE/offline"
}
go_online() {
  git config "url.$GH_REMOTE.insteadOf" "$offline_url"
  rm -f "$GH_STATE/offline"
}
heard_holds() {
  local heard=.review/runs/.loop/last-heard.json
  if [ "$(jq -r "$2" "$heard" 2>/dev/null)" = true ]; then
    echo "ok    $1"
  else
    echo "FAIL  $1: «$2» does not hold in $heard — it follows"
    sed 's/^/      /' "$heard" 2>/dev/null
    FAILURES=$((FAILURES + 1))
  fi
}

offline_project
for asked in git@github.com:acme/app.git=https://github.com/ \
             ssh://git@ssh.github.com:443/acme/app.git=https://ssh.github.com/ \
             https://token@git.example.com:8443/acme/app=https://git.example.com:8443/; do
  git remote add probe "${asked%%=*}"
  holds "${asked%%=*} is asked at ${asked#*=}" \
    [ "$(. "$LIB_DIR/common.sh" && remote_host_url probe)" = "${asked#*=}" ]
  git remote remove probe
done
git remote add probe "$WORK/nowhere.git"
holds "a remote that is a path has no host to ask" \
  [ -z "$(. "$LIB_DIR/common.sh" && remote_host_url probe)" ]
git remote remove probe
holds "GitHub is asked at its API" \
  [ "$(. "$LIB_DIR/common.sh" && github_api_url acme/app)" = https://api.github.com/ ]
holds "and another host of gh at that host" \
  [ "$(. "$LIB_DIR/common.sh" && github_api_url git.example.com/acme/app)" = \
    https://git.example.com/ ]
set_level merge
pr_work
pr_land "a remote reached through another URL lands as before" 0 "landed T-001 on task/T-001"
holds "curl is asked only after git or gh failed" not test -e "$GH_STATE/curl-calls"
heard_holds "what this copy last heard of its remote is kept: the base and the pull request" \
  '.base == "main" and (.pulls["task/T-001"] | test("^https://"))'
git config --unset "url.$GH_REMOTE.insteadOf"
pr_work
start="$(git rev-parse HEAD)"
pr_land "a host that answers and refuses is no lost connection" 3 \
  "the remote origin cannot be reached"
holds "that refusal commits nothing" [ "$(git rev-parse HEAD)" = "$start" ]
holds "the host was asked once" [ "$(grep -c '^' "$GH_STATE/curl-calls")" -eq 1 ]
says "and as it is written, before the rewrite" "http://127.0.0.1:1/" "$GH_STATE/curl-calls"
touch "$GH_STATE/offline"
PATH="$(path_without curl)" "$LIB_DIR/land.sh" --task-file .review/task.json \
  >"$WORK/land.log" 2>&1
check "without curl nothing is guessed" 3 "the remote origin cannot be reached" $? \
  "$WORK/land.log"
pr_land "a remote whose host gives no answer is told from one that refuses" 4 \
  "the remote origin gives no answer"
never_says "it is not called unreachable" "cannot be reached" "$WORK/land.log"
# curl's exit code decides, with a stand-in that exits $CURL_CODE: 35, a host that took the
# connection and spoke no TLS (an ssh server on port 443), tells nothing; 6, 7 and 28 are a
# host that gives no answer.
mkdir -p "$WORK/curl-code-bin" || fail_setup "curl-code-bin"
cat >"$WORK/curl-code-bin/curl" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$GH_STATE/curl-calls"
exit "$CURL_CODE"
EOF
chmod +x "$WORK/curl-code-bin/curl" || fail_setup "curl-code"
pr_work
start="$(git rev-parse HEAD)"
CURL_CODE=35 PATH="$WORK/curl-code-bin:$PATH" "$LIB_DIR/land.sh" --task-file .review/task.json \
  >"$WORK/land.log" 2>&1
check "a host that speaks no TLS tells nothing, and the refusal stays" 3 \
  "the remote origin cannot be reached" $? "$WORK/land.log"
never_says "it is not called a host that gives no answer" "gives no answer" "$WORK/land.log"
holds "nothing is committed then" [ "$(git rev-parse HEAD)" = "$start" ]
for code in 6 7 28; do
  pr_work
  CURL_CODE=$code PATH="$WORK/curl-code-bin:$PATH" "$LIB_DIR/land.sh" \
    --task-file .review/task.json >"$WORK/land.log" 2>&1
  check "curl's exit $code is a host that gives no answer" 4 \
    "the remote origin gives no answer" $? "$WORK/land.log"
done
set_level merge BASE_BRANCH=main
pr_work
pr_land "and so it is where BASE_BRANCH is set" 4 "the remote origin gives no answer"

offline_project
go_offline
set_level merge
pr_work
pr_land "with no base ever heard and none set the landing says what to set" 3 \
  "never heard which branch is its base — set BASE_BRANCH in .review/land.conf"
git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
pr_land "the base a clone recorded stands in for one never heard" 4 \
  "the remote origin gives no answer"

offline_project
set_level merge
touch "$GH_STATE/offline"
pr_work
pr_land "a gh that cannot connect is not called a login" 4 "GitHub gives no answer"
never_says "it does not send anyone to gh auth login" "gh auth login" "$WORK/land.log"
# ---- without the remote the landing, the review and /qa's tools go on ---------------
# The task lands, is reviewed and checked online; then the remote's host gives no answer.
# What the loop does here goes on, on what this copy last heard, and says what it owes;
# nothing is sent. gh_state is what the stand-in of gh keeps: the pull requests, the
# statuses and the comments.
gh_state() { cat "$GH_STATE/prs.json" "$GH_STATE/statuses.json" "$GH_STATE/comments.json" \
  2>/dev/null | cksum; }
offline_project
set_level merge
pr_work
step "the landing of the work online" "$WORK/land.log" \
  "$LIB_DIR/land.sh" --task-file .review/task.json
pr_review_quietly && qa_checked
online_pull="$(jq -r '.pr_url' "$run/meta.json")"
go_offline
pr_work
remote_tip="$(git -C "$GH_REMOTE" rev-parse refs/heads/task/T-001)"
sent_before="$(gh_state)"
pr_land "a remote that gives no answer does not stop a landing" 4 \
  "publishing is owed: the remote origin gives no answer"
says "it says it lands on what this copy last heard" \
  "── the remote origin gives no answer: landing here on what this copy last heard (base main)" \
  "$WORK/land.log"
holds "the commit is made" \
  [ "$(git log -1 --format=%s HEAD)" = "T-001: changes after review 1" ]
holds "with its trailer" [ -n "$(git log -1 --format=%B HEAD | grep -x 'Task-Id: T-001')" ]
holds "and nothing is sent" \
  [ "$(git -C "$GH_REMOTE" rev-parse refs/heads/task/T-001)" = "$remote_tip" -a \
    "$(gh_state)" = "$sent_before" ]
says "it says the loop goes on" "The loop goes on: go on here" "$WORK/land.log"
pr_review "the review runs on it here" 0 "CLEAN — gates green"
says "it says it reviews here, from the base as last fetched" \
  "── the remote origin gives no answer: reviewing here, from main as last fetched" \
  "$WORK/run.log"
says "its run says what it owes" "owed to GitHub: the review of $run" "$WORK/run.log"
never_says "and does not call that a run not posted" "is not posted on" "$WORK/run.log"
run_records "the run records that it was made offline, on the pull request last heard" \
  '.offline == true and .pr_url == "'"$online_pull"'" and .end == "clean" and .exit == 0'
offline_run="$run"
pr_post "pr-post.sh work answers from what was last fetched" 0 \
  "the merge base is of main as last fetched" work
holds "with a merge base" [ -n "$("$LIB_DIR/pr-post.sh" work 2>/dev/null \
  | jq -r '.merge_base // empty | select(test("^[0-9a-f]{40}$"))')" ]
qa_recorded
pr_post "the report of /qa is kept" 75 "owed to GitHub: the report of $qa_folder" qa "$qa_folder"
pr_post "an answer to a finding is kept" 75 "owed to GitHub" answers "$offline_run"
pr_post "what people wrote cannot be read without GitHub, and the script says so" 75 \
  "cannot be read without GitHub" comments
pr_post "a run is kept for when GitHub answers" 75 "owed to GitHub: the review of" \
  run "$offline_run"
holds "nothing of that is sent" [ "$(gh_state)" = "$sent_before" ]
printf 'T-001 done\n' >>TASK_TRACKER.md
pr_land "offline the loop's files alone land on the branch of the task" 4 "publishing is owed"
holds "in a commit of their own" [ "$(git log -1 --format=%s HEAD)" = "T-001: records" ]
jq -n '{base: "main"}' >.review/runs/.loop/last-heard.json
pr_review "a copy that kept no pull request takes the one its newest run names" 0 \
  "CLEAN — gates green" '{"findings":[]}' '{"verdicts":[]}'
run_records "and records it" '.pr_url == "'"$online_pull"'" and .offline == true'

# A post that fails for the connection: the gates go offline while they run.
go_online
pr_work
step "a landing online again" "$WORK/land.log" "$LIB_DIR/land.sh" --task-file .review/task.json
cat >.review/gates.sh <<'GATES'
#!/usr/bin/env bash
git config --unset "url.$GH_REMOTE.insteadOf"
touch "$GH_STATE/offline"
echo '{"build":{"status":"pass","blocking":true,"command":"true","output":""}}' >"$1"
GATES
pr_review "a post that fails for the connection leaves a clean run clean" 0 "CLEAN — gates green"
says "and it says what it owes" "owed to GitHub: the review of" "$WORK/run.log"
run_records "the run keeps its own end" '.end == "clean" and .exit == 0'
cp "$WORK/gates.green" .review/gates.sh

# At push the review needs no remote, and the landing commits and owes the push.
offline_project
set_level push BASE_BRANCH=main
go_offline
reviewed_change
remote_main="$(git -C "$GH_REMOTE" rev-parse refs/heads/main)"
land_run "at push the commit is made and the push is owed" 4 \
  "publishing is owed: the remote origin gives no answer"
holds "the commit is on the branch of the task" on_branch task/T-001
holds "and the remote is as it was" \
  [ "$(git -C "$GH_REMOTE" rev-parse refs/heads/main)" = "$remote_main" ]
holds "with no branch of the task" not remote_has task/T-001

# A first landing offline, in a copy that never heard of a pull request.
offline_project
set_level merge BASE_BRANCH=main
go_offline
pr_work
pr_land "a task whose pull request was never heard lands here" 4 "publishing is owed"
pr_review "a task whose pull request was never heard is reviewed all the same" 0 \
  "CLEAN — gates green"
run_records "its run names no pull request, and was made offline" \
  '.pr_url == null and .offline == true'
says "and it says how the run reaches the pull request" "owed to GitHub: the review of $run" \
  "$WORK/run.log"
holds "its base is the one last fetched" \
  [ "$(jq -r '.merge_base' "$run/meta.json")" = "$(git rev-parse refs/remotes/origin/main)" ]

# Online, pr-post.sh work asks for no pull request.
published_project origin
set_level pr
pr_work
step "a landing at pr" "$WORK/land.log" "$LIB_DIR/land.sh" --task-file .review/task.json
on_pull_request 1 '.state = "CLOSED"'
pr_post "pr-post.sh work asks for no pull request" 0 '"merge_base"' work

# ---- what is owed is sent when the host answers ------------------------------------
# A task lands and is reviewed online, with a finding; then the remote's host gives no
# answer, and the fix lands, is reviewed and checked here. publish.sh waits for GitHub with
# exit 75 and lists what is owed, in the order it is sent; when the host answers, publish.sh
# alone sends it, and the merge is checked anew: it is never kept.
put_off_once='{"counts": {"pass": 1, "fail": 0, "unproven": 0, "not_checked": 0, "after_merge": 1},
  "items": [{"id": "TC-001", "verdict": "pass"},
            {"id": "the build of main", "verdict": "after_merge",
             "reason": "the workflow runs only on a push to the base branch",
             "check": "the run of the build workflow on main, at the merge commit"}]}'
owed_listed() {
  local name="$1" log="$2" line at=0 found
  shift 2
  for line in "$@"; do
    found="$(grep -nF -- "$line" "$log" | head -1 | cut -d: -f1)"
    if [ -z "$found" ] || [ "$found" -le "$at" ]; then
      echo "FAIL  $name: «$line» is not listed after the line before — log follows"
      sed 's/^/      /' "$log"
      FAILURES=$((FAILURES + 1))
      return
    fi
    at="$found"
  done
  echo "ok    $name"
}
offline_project
set_level merge
pr_work
step "the landing of the work online" "$WORK/land.log" \
  "$LIB_DIR/land.sh" --task-file .review/task.json
pr_review "a review online with a finding" 3 "accepted (>= major): 1" \
  "{\"findings\": [$(pr_finding F-001 src/answer.kt 1 'fun answer()')]}" \
  "{\"verdicts\": [$(pr_verdict F-001 accept no-rule-fired)]}"
found_run="$run"
go_offline
pr_work
pr_land "the fix lands here while the host gives no answer" 4 "publishing is owed"
printf '[{"finding_id": "F-001", "answer": "fixed", "text": "answer() is 42.", "commit": ""}]' \
  >"$found_run/answers.json"
pr_review "the fix is reviewed here" 0 "CLEAN — gates green"
offline_run="$run"
says "the review says that publish.sh alone sends it" \
  "owed to GitHub: the review of $offline_run — publish.sh alone sends it" "$WORK/run.log"
says "and that it is posted when the host answers" \
  "reviewing here, from main as last fetched" "$WORK/run.log"
qa_recorded
pr_post "so does the report of /qa" 75 \
  "owed to GitHub: the report of $qa_folder — publish.sh alone sends it" qa "$qa_folder"
pr_post "pr-post.sh owed says what is owed while GitHub gives no answer" 75 \
  "the review of $offline_run" owed
publish "the merge waits for GitHub and lists what is owed" 75 "PUBLISHING WAITS FOR GITHUB" \
  --merge
owed_listed "in the order publish.sh sends it" "$WORK/publish.log" \
  "   Owed, and sent in this order by publish.sh alone when it answers:" \
  "     the push of task/T-001: 1 commit(s) the remote does not have" \
  "     the review of $offline_run" "     1 answer(s) of $found_run" \
  "     the report of $qa_folder" \
  "     the statuses and the description, made again when they are sent"
holds "nothing is merged" not gh_called "pr merge"
says "and the merge is not kept" \
  "   The merge is never kept: publish.sh --merge then checks the whole contract anew." \
  "$WORK/publish.log"
says "it says the loop goes on" "The loop goes on: go on here" "$WORK/publish.log"
go_online
pr_post "a run whose commit is not on the remote yet is not posted" 3 \
  "the push of $(jq -r '.head' "$offline_run/meta.json") is owed first: publish.sh alone" owed
holds "nothing of it is posted" not posted "<!-- loop:review $(basename "$offline_run") -->"
publish "back online, publish.sh alone sends it all" 0 \
  "nothing more is owed to https://example.test/pull/1"
holds "the remote branch is at HEAD" remote_is task/T-001 "$(git rev-parse HEAD)"
says "it says what it sent" "sent: the review of $offline_run" "$WORK/publish.log"
holds "the review run is posted once" \
  posted_count_is "<!-- loop:review $(basename "$offline_run") -->" 1
holds "the answer once" posted_count_is "<!-- loop:answer $(basename "$found_run") F-001 -->" 1
holds "the report of /qa once" posted_count_is "<!-- loop:qa $(basename "$qa_folder") -->" 1
holds "a run made offline is posted at the commit it reviewed" \
  jq_true --arg marker "<!-- loop:review $(basename "$offline_run") -->" \
  --arg head "$(jq -r '.head' "$offline_run/meta.json")" \
  'any(.[]; .kind == "review" and (.body | startswith($marker)) and .commit_id == $head)' \
  "$GH_STATE/comments.json"
holds "the statuses are those of the work as it is now" status_is loop/review success
publish "sent again, nothing is sent twice" 0 "nothing more is owed to"
holds "no review is posted twice" posted_count_is "<!-- loop:review $(basename "$offline_run") -->" 1
publish "then the merge goes" 0 "merged T-001" --merge

# A first landing offline, in a copy that never heard of its pull request.
offline_project
set_level merge BASE_BRANCH=main
go_offline
pr_work
pr_land "a first landing here" 4 "publishing is owed"
says "owes its pull request" "     the pull request of task/T-001 into main" "$WORK/land.log"
pr_review_quietly
never_heard_run="$run"
go_online
publish "a first landing offline owes its pull request too" 0 \
  "pull request: https://example.test/pull/1"
holds "its run made here is posted on it" \
  posted_count_is "<!-- loop:review $(basename "$never_heard_run") -->" 1
holds "and names it now" \
  jq_true '.pr_url == "https://example.test/pull/1"' "$never_heard_run/meta.json"
qa_checked
publish "and the merge goes on that review" 0 "merged T-001" --merge

# A base that moved meanwhile: the merge that waited for GitHub is not kept, and is checked
# anew on the base as it is.
offline_project
reviewed_pull_request merge
go_offline
publish "a merge that waited for GitHub" 75 "PUBLISHING WAITS FOR GITHUB" --merge
git -C "$GH_REMOTE" update-ref refs/heads/main "$(git -C "$GH_REMOTE" commit-tree \
  'refs/heads/main^{tree}' -p refs/heads/main -m "someone else's commit")"
go_online
publish "a base that moved meanwhile is checked anew at the merge" 0 "merged T-001" --merge
holds "the base keeps the commit that moved it" remote_log_has main "someone else's commit"

# The remote branch moved, or the pull request was closed, while the host gave no answer.
offline_project
reviewed_pull_request merge
go_offline
pr_work
pr_land "a landing here before the branch moves there" 4 "publishing is owed"
git -C "$GH_REMOTE" update-ref refs/heads/task/T-001 "$(git -C "$GH_REMOTE" commit-tree \
  'refs/heads/task/T-001^{tree}' -p refs/heads/task/T-001 -m "pushed from elsewhere")"
moved="$(git -C "$GH_REMOTE" rev-parse refs/heads/task/T-001)"
go_online
publish "a branch that moved on the remote meanwhile is not overwritten" 1 \
  "the remote branch task/T-001 moved"
holds "the remote keeps its commit" remote_is task/T-001 "$moved"

# A landing and its review here; the remote branch moves meanwhile, and the branch is put
# together anew by a rebase: the run reviewed a commit that is no commit of the branch any
# more, and is passed over. Brought together by a merge, the commit stays one of the branch,
# and its run is posted. put_together <rebase|merge>: the run is $apart_run.
put_together() {
  offline_project
  reviewed_pull_request merge
  go_offline
  pr_work
  pr_land "a landing here before the branch is put together by a $1" 4 "publishing is owed"
  pr_review_quietly
  apart_run="$run"
  git -C "$GH_REMOTE" update-ref refs/heads/task/T-001 "$(git -C "$GH_REMOTE" commit-tree \
    'refs/heads/task/T-001^{tree}' -p refs/heads/task/T-001 -m "T-001: from another copy" \
    -m "Task-Id: T-001")"
  go_online
  git fetch -q origin || fail_setup "fetch"
  case "$1" in
    rebase) git rebase -q origin/task/T-001 ;;
    merge) git merge -q -m "T-001: the branch brought together" -m "Task-Id: T-001" \
             origin/task/T-001 ;;
  esac >/dev/null 2>&1 || fail_setup "$1"
}
put_together rebase
publish "a run whose commit left the branch is passed over" 0 \
  "nothing more is owed to https://example.test/pull/1"
says "with a line that says why" "the review of $apart_run is not sent: \
$(jq -r '.head' "$apart_run/meta.json"), the commit it reviewed, is no commit of task/T-001 any \
more, and nothing is posted for it" "$WORK/publish.log"
holds "nothing is posted for it" not posted "<!-- loop:review $(basename "$apart_run") -->"
holds "and the branch as it is now is pushed" remote_is task/T-001 "$(git rev-parse HEAD)"
publish "the next publish.sh passes it over too" 0 "nothing more is owed to"
put_together merge
publish "a run whose commit is still one of the branch is posted" 0 \
  "sent: the review of $apart_run"
holds "it is posted once" posted_count_is "<!-- loop:review $(basename "$apart_run") -->" 1
never_says "and is not passed over" "is not sent:" "$WORK/publish.log"
# A run that is passed over is passed over whole: its answers are not owed either, and the
# merge does not wait for it. The run here hands a finding over, the fix answers it, and the
# commit it reviewed is then made anew.
offline_project
reviewed_pull_request merge
go_offline
pr_work
pr_land "a landing here whose review finds something" 4 "publishing is owed"
pr_review "its review hands a finding over" 3 "accepted (>= major): 1" \
  "{\"findings\": [$(pr_finding F-001 src/answer.kt 1 'fun answer()')]}" \
  "{\"verdicts\": [$(pr_verdict F-001 accept no-rule-fired)]}"
apart_run="$run"
printf '[{"finding_id": "F-001", "answer": "fixed", "text": "answer() is 42.", "commit": ""}]' \
  >"$apart_run/answers.json"
git commit -q --amend -m "T-001: the work, made anew" -m "Task-Id: T-001" || fail_setup "amend"
publish "what is owed for a run whose commit left the branch is not listed" 75 \
  "PUBLISHING WAITS FOR GITHUB"
never_says "neither its review" "the review of $apart_run" "$WORK/publish.log"
never_says "nor its answers" "answer(s) of $apart_run" "$WORK/publish.log"
go_online
publish "a run that is passed over owes no answers either" 0 \
  "nothing more is owed to https://example.test/pull/1"
says "the line says that nothing is posted for it" "the review of $apart_run is not sent: " \
  "$WORK/publish.log"
never_says "and no answer of it is sent" "answer(s) of $apart_run" "$WORK/publish.log"
pr_review_quietly
qa_checked
publish "and the merge does not wait for it" 0 "merged T-001" --merge

# Back online, publish.sh --merge asked before plain publish.sh: M1 sends the loop to
# publish.sh alone, which sends what is owed in its order.
offline_project
reviewed_pull_request merge
go_offline
pr_work
pr_land "a landing here before a merge is asked" 4 "publishing is owed"
pr_review_quietly
go_online
publish "a merge asked first back online is refused by M1" 3 \
  "M1: $(basename "$run") is not posted on https://example.test/pull/1 — publish.sh alone \
sends it, with everything owed, in order" --merge
never_says "it does not send the loop to pr-post.sh run" "pr-post.sh run" "$WORK/publish.log"
publish "publish.sh alone, as M1 says, sends it" 0 "sent: the review of $run"
qa_checked
publish "and then the merge goes" 0 "merged T-001" --merge

offline_project
reviewed_pull_request merge
go_offline
pr_work
pr_land "a landing here before the pull request is closed" 4 "publishing is owed"
on_pull_request 1 '.state = "CLOSED"'
remote_tip="$(git -C "$GH_REMOTE" rev-parse refs/heads/task/T-001)"
go_online
publish "a pull request closed meanwhile is not reopened or replaced" 5 \
  "was closed without a merge"
holds "nothing is pushed" remote_is task/T-001 "$remote_tip"
holds "and no pull request is opened" [ "$(jq length "$GH_STATE/prs.json")" -eq 1 ]

# The connection goes in the middle: at the push, at the checks, at the merge.
offline_project
reviewed_pull_request merge
pr_work
cat >.git/hooks/pre-push <<'HOOK'
#!/bin/sh
git config --unset "url.$GH_REMOTE.insteadOf"
touch "$GH_STATE/offline"
exit 1
HOOK
chmod +x .git/hooks/pre-push
pr_land "a push that fails for the connection is owed" 4 \
  "publishing is owed: the remote origin, or GitHub, gives no answer"
says "and listed" "     the push of task/T-001: 1 commit(s) the remote does not have" \
  "$WORK/land.log"
never_says "it is not called a failed push" "the push to origin failed" "$WORK/land.log"
rm .git/hooks/pre-push

offline_project
reviewed_pull_request merge
touch "$GH_STATE/down-at-checks"
publish "checks that cannot be read for want of GitHub wait for it" 75 \
  "PUBLISHING WAITS FOR GITHUB" --merge
never_says "they are not called an error" "PUBLISHING FAILED" "$WORK/publish.log"
holds "nothing is merged then" not gh_called "pr merge"

offline_project
reviewed_pull_request merge
printf 'unsent\n' >"$GH_STATE/down-at-merge"
publish "a merge that could not be sent is not told as refused" 75 \
  "the merge of https://example.test/pull/1 was not sent, or its answer was lost" --merge
never_says "it does not say gh did not merge" "gh did not merge" "$WORK/publish.log"
says "it says how it is found out" \
  "publish.sh --merge again, when GitHub answers, looks first whether the pull request is merged" \
  "$WORK/publish.log"
go_online
publish "when GitHub answers the merge goes" 0 "merged T-001" --merge

offline_project
set_level merge
pr_work
step "a landing whose /qa puts a check off until after the merge" "$WORK/land.log" \
  "$LIB_DIR/land.sh" --task-file .review/task.json
pr_review_quietly && qa_checked '[]' "" 0 "$put_off_once"
printf 'unanswered\n' >"$GH_STATE/down-at-merge"
publish "a merge whose answer was lost waits for GitHub" 75 "its answer was lost" --merge
go_online
publish "when GitHub answers, the merge it took is found" 0 "merged T-001" --merge
says "and what it owes after the merge is said" \
  "OWED AFTER THE MERGE — /qa put off 1 check(s) of T-001 until now:" "$WORK/publish.log"
holds "and written down" \
  jq_true '.items[0].id == "the build of main"' .review/runs/after-merge-T-001/owed.json

offline_project
set_level merge
pr_work
step "a landing whose /qa puts a check off until after the merge" "$WORK/land.log" \
  "$LIB_DIR/land.sh" --task-file .review/task.json
pr_review_quietly && qa_checked '[]' "" 0 "$put_off_once"
printf 'after\n' >"$GH_STATE/down-at-merge"
publish "a merge whose base cannot be updated here waits, and says the merge is sound" 75 \
  "https://example.test/pull/1 is merged; main here is not updated yet, because the remote origin gives no answer — nothing is wrong with the merge" \
  --merge
says "it says what the merge owes" \
  "OWED AFTER THE MERGE — /qa put off 1 check(s) of T-001 until now:" "$WORK/publish.log"
holds "the checkout stays on the branch of the task" on_branch task/T-001
says "and that publish.sh --merge then only updates main" \
  "The loop goes on: run publish.sh --merge again when it answers: it only updates main here" \
  "$WORK/publish.log"
go_online
publish "when it answers, publish.sh --merge updates main here" 0 "merged T-001" --merge
holds "main here is the merge" [ "$(git rev-parse HEAD)" = "$(git -C "$GH_REMOTE" rev-parse main)" ]

# At push, back online, publish.sh sends the push.
offline_project
set_level push BASE_BRANCH=main
go_offline
reviewed_change
land_run "a landing at push here" 4 "publishing is owed"
says "at push the push alone is owed" \
  "     the push of task/T-001: 1 commit(s) the remote does not have" "$WORK/land.log"
never_says "and no pull request" "the pull request of" "$WORK/land.log"
go_online
publish "at push, back online, publish.sh sends the push" 0 "published T-001"
holds "the remote has the commit" remote_is task/T-001 "$(git rev-parse HEAD)"

# ---- a reply to a person is kept, and sent only for the comment as it was read ------------
# Online, pr-post.sh comments keeps a digest of each comment it showed. Without GitHub a reply
# to such a comment is kept: which comment, as it was read, the answer, and the text file it
# names with a digest of that file — never the words of either. publish.sh alone sends it
# when the host answers, and only while the comment and the text file are as they were.
offline_project
reviewed_pull_request merge
seen=.review/runs/.loop/comments-seen.json
kept=.review/runs/.loop/replies-owed
a_person_comments "$(printf 'Why 42?\nThe tracker says 41.')"
asked="$(person_id)"
pr_post "pr-post.sh comments shows what a person wrote" 0 "The tracker says 41." comments
holds "and keeps a digest of each comment it showed" \
  jq_true --arg id "$asked" '.[$id] | test("^[0-9a-f]{64}$")' "$seen"
go_offline
printf 'The requirements ask for 42: REQUIREMENTS.md, "Answer".\n' >.review/runs/reply-42.md
pr_post "a reply without GitHub is kept" 75 \
  "owed to GitHub: the reply to $asked (not-a-problem) — publish.sh alone sends it" \
  reply "$asked" not-a-problem .review/runs/reply-42.md
holds "its record names the comment as it was read, the answer and the text file" \
  jq_true --arg id "$asked" --slurpfile seen "$seen" --arg file "$PWD/.review/runs/reply-42.md" \
  '.id == $id and .answer == "not-a-problem" and .seen == $seen[0][$id] and .file == $file' \
  "$kept/$asked.json"
holds "and keeps no words of the comment or of the reply" \
  not grep -rqE 'tracker says 41|ask for 42' .review/runs/.loop
publish "publish.sh lists the reply among what is owed" 75 "PUBLISHING WAITS FOR GITHUB"
owed_listed "after the reports and before the statuses" "$WORK/publish.log" \
  "   Owed, and sent in this order by publish.sh alone when it answers:" \
  "     the reply to $asked (not-a-problem)" \
  "     the statuses and the description, made again when they are sent"
pr_post "a reply to a comment never read here is refused" 3 \
  "POSTING REFUSED — 4242 was never read here: pr-post.sh comments shows what people wrote, "\
"when GitHub answers" reply 4242 fixed .review/runs/reply-42.md
holds "and is not kept" not test -e "$kept/4242.json"
go_online
publish "a reply that was kept is sent when the comment is as it was read" 0 \
  "nothing more is owed to https://example.test/pull/1"
says "it says it sent it" "sent: the reply to $asked (not-a-problem)" "$WORK/publish.log"
holds "the reply is posted" posted "<!-- loop:reply $asked not-a-problem -->"
holds "and is kept no longer" not test -e "$kept/$asked.json"
publish "sent again, the reply is not posted twice" 0 "nothing more is owed to"
holds "it is there once" posted_count_is "<!-- loop:reply $asked not-a-problem -->" 1

a_person_comments "And the button is red where the plan says blue."
second="$(jq -r '.[-1].id' "$GH_STATE/comments.json")"
pr_post "pr-post.sh comments shows the second comment" 0 "where the plan says blue" comments
go_offline
printf 'The button is blue now.\n' >.review/runs/reply-blue.md
pr_post "a reply to the second is kept" 75 "owed to GitHub: the reply to $second (fixed)" \
  reply "$second" fixed .review/runs/reply-blue.md
updated="$(jq --arg id "$second" 'map(if (.id | tostring) == $id
  then .body = "And the button is red where the plan says green." else . end)' \
  "$GH_STATE/comments.json")" && printf '%s' "$updated" >"$GH_STATE/comments.json"
go_online
publish "and not when the comment changed meanwhile" 0 \
  "the reply to $second is not sent: the comment changed since it was read — read it again "\
"with pr-post.sh comments, and answer what it says now"
holds "no reply to it is posted" not posted "<!-- loop:reply $second fixed -->"
holds "and it is kept no longer" not test -e "$kept/$second.json"
publish "the merge waits on that comment" 5 \
  "the first that is the loop's $second by  on the pull request, not answered" --check

# A text file used again for another reply: the reply it was named for is not sent. A reply
# posted at once, once GitHub answers, takes the place of the one kept for the same comment.
pr_post "pr-post.sh comments shows it again" 0 "where the plan says green" comments
a_person_comments "The label says Answer, not answer."
third="$(jq -r '.[-1].id' "$GH_STATE/comments.json")"
pr_post "and a third" 0 "The label says Answer" comments
go_offline
printf 'Green it is now.\n' >.review/runs/reply.md
pr_post "a reply to the second, kept" 75 "the reply to $second (fixed)" \
  reply "$second" fixed .review/runs/reply.md
printf 'The label reads Answer now.\n' >.review/runs/reply.md
pr_post "a reply to the third in the same file, kept" 75 "the reply to $third (fixed)" \
  reply "$third" fixed .review/runs/reply.md
go_online
publish "a reply whose text file changed since it was kept is not sent" 0 \
  "the reply to $second is not sent: its text file $PWD/.review/runs/reply.md changed since "\
"the reply was kept — answer it again with pr-post.sh reply"
holds "no reply to it is posted" not posted "<!-- loop:reply $second fixed -->"
holds "and the reply the file now holds is sent" posted "<!-- loop:reply $third fixed -->"
go_offline
printf 'Which green the plan means is not found out yet.\n' >.review/runs/reply-green.md
pr_post "a reply kept" 75 "the reply to $second (unsettled)" \
  reply "$second" unsettled .review/runs/reply-green.md
go_online
printf 'The button is the green of the plan now.\n' >.review/runs/reply-green-2.md
pr_post "a reply posted at once once GitHub answers" 0 "reply to $second (fixed) posted" \
  reply "$second" fixed .review/runs/reply-green-2.md
holds "takes the place of the one kept for the same comment" not test -e "$kept/$second.json"
publish "which is never sent after it" 0 "nothing more is owed to"
holds "so the comment stays answered fixed" not posted "<!-- loop:reply $second unsettled -->"

# GitHub goes while a reply is on its way: the reply is kept.
a_person_comments "One more: the title is cut."
fourth="$(jq -r '.[-1].id' "$GH_STATE/comments.json")"
pr_post "pr-post.sh comments shows a fourth" 0 "the title is cut" comments
printf 'The title is whole now.\n' >.review/runs/reply-title.md
touch "$GH_STATE/down-at-api"
pr_post "a reply whose post loses GitHub on the way is kept" 75 \
  "owed to GitHub: the reply to $fourth (fixed) — publish.sh alone sends it" \
  reply "$fourth" fixed .review/runs/reply-title.md
holds "its record is there" test -f "$kept/$fourth.json"
go_online
publish "and is sent when GitHub answers" 0 "sent: the reply to $fourth (fixed)"
holds "once" posted_count_is "<!-- loop:reply $fourth fixed -->" 1


published_project github
merged_change "a remote not named origin is found" 0 "merged T-001"
holds "the commit reached it through a pull request" gh_called "--base main --head task/T-001"
holds "the base branch was updated from it" remote_is main "$(git rev-parse main)"
holds "that remote's main took the merge" remote_log_has main "Task-Id: T-001"

for url in git@github.com:acme/app.git https://github.com/acme/app.git \
           ssh://git@github.com/acme/app \
           https://token@github.com/acme/app/ ssh://git@ssh.github.com:443/acme/app.git; do
  git remote set-url github "$url"
  holds "$url is acme/app to gh" \
    [ "$(. "$LIB_DIR/common.sh" && remote_repository github)" = "acme/app" ]
done
git remote set-url github git@git.example.com:acme/app.git
holds "another host goes in front" \
  [ "$(. "$LIB_DIR/common.sh" && remote_repository github)" = "git.example.com/acme/app" ]

# ---- the base branch --------------------------------------------------------

published_project origin
git switch -q -c trunk
git push -q origin trunk
git -C "$GH_REMOTE" symbolic-ref HEAD refs/heads/trunk
land_change "the HEAD of the remote is the protected base branch" 0 "landed T-001 on task/T-001" pr
holds "the pull request goes to the HEAD of the remote" gh_called "--base trunk --head task/T-001"

published_project origin
git remote set-head origin main
git switch -q -c trunk
git push -q origin trunk
start="$(git rev-parse HEAD)"
git -C "$GH_REMOTE" symbolic-ref HEAD refs/heads/trunk
land_change "the remote is asked, not what a clone recorded" 0 "landed T-001 on task/T-001" push
holds "the base branch on the remote takes no direct push" remote_is trunk "$start"

published_project origin
git switch -q -c develop
git push -q origin develop
land_change "BASE_BRANCH is protected" 0 "landed T-001 on task/T-001" pr BASE_BRANCH=develop
holds "the pull request goes to BASE_BRANCH" gh_called "--base develop --head task/T-001"

published_project origin
start="$(git rev-parse HEAD)"
land_change "a BASE_BRANCH the remote does not have refuses before the commit" 3 \
  "the base branch devlop is not on the remote" pr BASE_BRANCH=devlop
holds "that refusal commits nothing" [ "$(git rev-parse HEAD)" = "$start" ]

published_project origin
git switch -q -c release
land_change "PROTECTED_BRANCHES are left for the branch of the task" 0 \
  "landed T-001 on task/T-001" push 'PROTECTED_BRANCHES="release"'

published_project origin
git -C "$GH_REMOTE" symbolic-ref HEAD refs/heads/nowhere
land_change "with no answer from the remote the base branch is main if it exists" 0 \
  "landed T-001 on task/T-001" pr
holds "the pull request goes to main" gh_called "--base main --head task/T-001"

published_project origin
git branch -q -m main master
git push -q origin master
git -C "$GH_REMOTE" symbolic-ref HEAD refs/heads/nowhere
git push -q origin --delete main
land_change "with no main and no answer from the remote the base branch is master" 0 \
  "landed T-001 on task/T-001" pr
holds "the pull request goes to master" gh_called "--base master --head task/T-001"

rules_in_prompt="$(grep -oE '\(`[a-z-]+`\)' "$LIB_DIR/prompts/maintainer.md" \
  | tr -d '()`' | sort -u)"
rules_in_schema="$(jq -r '.properties.verdicts.items.properties.decision_rule.enum[]' \
  "$LIB_DIR/schemas/maintainer-verdicts.schema.json" | sort -u)"
missing="$(comm -23 <(printf '%s\n' "$rules_in_prompt") <(printf '%s\n' "$rules_in_schema"))"
if [ -z "$missing" ]; then
  echo "ok    every decision rule of the prompt is in the schema"
else
  echo "FAIL  decision rules of prompts/maintainer.md missing from the schema: $missing"
  FAILURES=$((FAILURES + 1))
fi

# The scripts ask for jq 1.6 or newer, and jq 1.6 reads a word of its own after `$` as
# that word: a program that binds a variable of such a name — after `as`, alone or inside
# a pattern that takes a list or an object apart, as a label, as a named argument of the
# command line, as a parameter of a function — does not compile there, and neither does
# such a word alone as a key of an object. jq 1.7 takes both, so only this case holds the
# scripts to it on a machine with a newer jq. jq needs no blank between `as` or `label`
# and what follows, so a binding is read with one or with none. Comment lines are passed
# over, and a pattern is read as far as its line goes: one that binds such a word on a
# later line of its own is not seen. jq_words_bound <file>... prints the lines that do so,
# as grep -Hn gives them.
jq_words='and|as|catch|def|elif|else|end|foreach|if|import|include|label|module|or|reduce'
jq_words="$jq_words|then|try|__loc__"
jq_binds="(\\b(as|label) *\\\$|\\bas *[[{][^|]*\\\$|--(arg|argjson|slurpfile|rawfile) +"
jq_binds="$jq_binds|\\bdef +[a-z_]+\\([^)]*\\\$)($jq_words)\\b"
jq_words_bound() {
  grep -HnE -- "$jq_binds|[{,] *($jq_words) *[,}]" "$@" | grep -vE '^[^:]+:[0-9]+: *#'
}
# What the case must catch, in programs made up here. printf puts the word in, so that
# this file, which the case reads too, holds no such binding.
mkdir -p "$WORK/jq-names" || fail_setup "jq-names"
printf '. as [$%s] | 1\n' end >"$WORK/jq-names/list.sh"
printf '. as {$%s} | 1\n' end >"$WORK/jq-names/object.sh"
printf 'reduce .[] as [$key, {at: [$%s]}] (0; . + 1)\n' or >"$WORK/jq-names/deeper.sh"
printf '. as [$first] ?// {$%s} | 1\n' if >"$WORK/jq-names/alternative.sh"
printf '. as $x | label $%s | 1\n' end >"$WORK/jq-names/label.sh"
printf '. as {%s: $x} | [$x, {%s: 1}] | . as [$%sing] | 1\n' end end end \
  >"$WORK/jq-names/none.sh"
# jq reads a pattern, a variable and a label written with no blank before them as well.
printf '. as[$%s] | 1\n' end >"$WORK/jq-names/list-close.sh"
printf '. as{$%s} | 1\n' end >"$WORK/jq-names/object-close.sh"
printf '. as$%s | 1\n' end >"$WORK/jq-names/variable-close.sh"
printf '. as $x | label$%s | 1\n' end >"$WORK/jq-names/label-close.sh"
printf '. as[$%sing] | {%s: 1} | . as{%s: $x} | label$%sless | 1\n' end end end end \
  >"$WORK/jq-names/none-close.sh"
jq_words_bound "$WORK"/jq-names/*.sh >"$WORK/jq-names.log"
says "a variable that a list pattern binds by a word jq 1.6 keeps is caught" \
  "/list.sh:1:" "$WORK/jq-names.log"
says "and one that an object pattern binds" "/object.sh:1:" "$WORK/jq-names.log"
says "and one bound deeper in a pattern" "/deeper.sh:1:" "$WORK/jq-names.log"
says "and one bound in the alternative of a pattern" "/alternative.sh:1:" "$WORK/jq-names.log"
says "and a label of such a name" "/label.sh:1:" "$WORK/jq-names.log"
never_says "a key of a pattern that is such a word, and a longer name, are none" \
  "/none.sh" "$WORK/jq-names.log"
says "a list pattern written with no blank after as is caught too" \
  "/list-close.sh:1:" "$WORK/jq-names.log"
says "and an object pattern written so" "/object-close.sh:1:" "$WORK/jq-names.log"
says "and a variable bound with no blank after as" "/variable-close.sh:1:" "$WORK/jq-names.log"
says "and a label with no blank before its name" "/label-close.sh:1:" "$WORK/jq-names.log"
never_says "written so, a key of a pattern and a longer name are none either" \
  "/none-close.sh" "$WORK/jq-names.log"
bound="$(jq_words_bound "$LIB_DIR"/*.sh "$LIB_DIR"/../project/*.sh)"
if [ -z "$bound" ]; then
  echo "ok    no jq program of the scripts names a variable or a lone key by a word jq 1.6 keeps"
else
  echo "FAIL  no jq program of the scripts names a variable or a lone key by a word jq 1.6 "\
"keeps: these do not compile there"
  printf '%s\n' "$bound" | sed 's/^/      /'
  FAILURES=$((FAILURES + 1))
fi

# The scripts send the user only what is theirs. A script that stops for the user says so
# through `turn user:<kind>` (common.sh), so a line of a script that names the user or a
# person and holds no kind of USER_DECIDES would send them what no kind covers.
# names_a_person <file>... prints such lines, each with its file and the number of its
# first line: a command that goes on after a `\` is read as one line, and a comment is
# passed over. Six texts are named here and nowhere else. Three hand the commit over at
# LANDING=off and on a protected branch, where the hand-over is the setting itself. Three
# are the scripts' own words about --user-decided, the flag of a stop that is the user's:
# the two refusals of the flag where it is misused, each in review.sh and in land.sh, and
# the line of the pull request for a stop that was passed with it.
user_kinds="$(. "$LIB_DIR/common.sh" && printf '%s' "$USER_DECIDES" | tr ' ' '|')"
[ -n "$user_kinds" ] || fail_setup "USER_DECIDES"
names_a_person() {
  local script
  for script in "$@"; do
    awk -v script="$script" '
      joined == "" { start = NR }
      { joined = joined $0 }
      /\\$/ { sub(/\\$/, "", joined); next }
      { if (joined !~ /^[ \t]*#/) print script ":" start ": " joined; joined = "" }' "$script"
  done | grep -E 'the user|the person|a person|only they|somebody|someone else' \
    | grep -vE "user:($user_kinds)" \
    | grep -vF -e 'For the user to commit:' \
        -e 'Commands (for the user only when they ask for them; never run them):' \
        -e 'the loop would not commit here; the user decides where the commit goes' \
        -e 'and nothing keeps words where the user decided' \
        -e "--user-decided is for a stop that is the user's" \
        -e "was passed on the user'\"'\"'s decision."
}
# What the case must catch, in scripts made up here.
mkdir -p "$WORK/names" || fail_setup "names"
printf 'echo "If that is not enough, tell the user now." >&2\n' >"$WORK/names/plain.sh"
printf 'refuse "it is never forced, "\\\n"so a person brings the two together"\n' \
  >"$WORK/names/continued.sh"
printf '# the user decides this\n  # and so does a person\n' >"$WORK/names/comment.sh"
printf 'refuse "it was closed" user:only-theirs "the user reopens it"\n' >"$WORK/names/kind.sh"
printf 'refuse "it was closed" user:anything "the user reopens it"\n' >"$WORK/names/no-kind.sh"
names_a_person "$WORK"/names/*.sh >"$WORK/names.log"
says "a line of a script that names the user and says no kind of what is theirs is caught" \
  "/plain.sh:1:" "$WORK/names.log"
says "and one that names a person where its command goes on" "/continued.sh:1:" "$WORK/names.log"
says "and one whose kind is not of the list" "/no-kind.sh:1:" "$WORK/names.log"
never_says "a comment that names them is none" "/comment.sh" "$WORK/names.log"
never_says "nor is a line that says the kind" "/kind.sh" "$WORK/names.log"
named="$(cd "$LIB_DIR" && \
  names_a_person review.sh land.sh publish.sh pr-post.sh e2e-gate.sh device.sh common.sh)"
if [ -z "$named" ]; then
  echo "ok    the scripts send the user only what is theirs"
else
  echo "FAIL  the scripts send the user only what is theirs: these lines name the user or a "\
"person and say no kind of what is theirs (turn, common.sh)"
  printf '%s\n' "$named" | sed 's/^/      /'
  FAILURES=$((FAILURES + 1))
fi

[ "$FAILURES" -eq 0 ] || { echo "$FAILURES case(s) failed"; exit 1; }
echo "all cases behaved"
