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
export PATH="$WORK/df-bin:$PATH"

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
# platform it runs on (E2E_ONLY) or a file it appends to (E2E_TOUCH). Each published
# project below commits the same harness.
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
e2e_check "after a passing end-to-end run /qa may go on" 0 "check exited 0"
review "an accepted finding goes to the executor" 3 "accepted (>= major): 1" \
  "$(finding '"bug"')" "$(verdict '"accept"' no-rule-fired)"
review "an escalated finding waits for an answer" 4 "escalated         : 1" \
  "$(finding '"bug"')" "$(verdict '"escalate"' needs-judgment)"
review "a category outside the schema fails closed" 1 "reviewer output does not match" \
  "$(finding '"opinion"')" "$(verdict '"accept"' no-rule-fired)"
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
counted "a run past the limit waits for the user" 6 \
  "WAIT FOR THE USER — T-002 has had 2 runs since the count started, 2 in all" T-002
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
  "has had 2 runs since the count started, 5 in all" T-002
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

# The end-to-end tests. Each review here has no findings, so it ends CLEAN
# unless the end-to-end tests stop it; the run it made is $last_run.
printf 'THRESHOLD=major\nLANDING=off\nASK_AFTER_RUNS=100\n' >.review/land.conf
printf '{"findings":[]}' >"$WORK/reviewer.json"
printf '{"verdicts":[]}' >"$WORK/maintainer.json"
e2e_review() {
  local name="$1" expected_exit="$2" expected_line="$3" task_file="$4" runs_listed
  runs_listed="$(ls .review/runs)"
  REVIEWER_CMD="touch $WORK/reviewer-ran; cat $WORK/reviewer.json #" \
    MAINTAINER_CMD="cat $WORK/maintainer.json #" \
    "$LIB_DIR/review.sh" --task-file "$task_file" >"$WORK/run.log" 2>&1
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
mv .review/e2e.sh "$WORK/e2e.sh"
e2e_review "no end-to-end harness stops the review" 1 \
  "NO E2E HARNESS — copy CodingStandards/templates/review/project/e2e.sh" .review/T-006.json
e2e_check "after a run with no harness /qa is held back" 2 "found no working harness"
mv "$WORK/e2e.sh" .review/e2e.sh
E2E_XML='<testsuite tests="0"/>' \
  e2e_review "a harness that runs no test is no harness" 1 "app: the e2e run ran no test" \
  .review/T-006.json
E2E_ONLY=none E2E_EXIT=143 \
  e2e_review "a harness killed before any test is no harness" 1 \
  "app: the e2e run ran no test (exit 143)" .review/T-006.json
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
if [ ! -e "$WORK/reviewer-ran" ]; then
  echo "ok    red end-to-end tests never reach the reviewer"
else
  echo "FAIL  red end-to-end tests reached the reviewer"
  FAILURES=$((FAILURES + 1))
fi
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
  e2e_review "an end-to-end run that changes the tree stops the review" 1 \
  "the e2e run modified the working tree" .review/T-006.json
rm -f src/x
printf 'v1\n' >"src/Отчёт.kt"
E2E_TOUCH="src/Отчёт.kt" \
  e2e_review "an end-to-end run that changes a file with a non-ASCII name stops the review" 1 \
  "the e2e run modified the working tree" .review/T-006.json
rm -f "src/Отчёт.kt"
# The loop's and the owner's files are outside the fingerprint; the run changes them
# no more than the rest. A harness that rewrites the cases would choose its own tests.
for touched in qa/test-cases.md TASK_TRACKER.md REQUIREMENTS.md; do
  E2E_TOUCH="$touched" E2E_XML="$(xml starts)" \
    e2e_review "an end-to-end run that changes $touched stops the review" 1 \
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
e2e_review "a harness that puts the committed one back while it runs stops the review" 1 \
  "the harness changed while it ran" .review/T-008.json
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
qa_says "an item put off until after the merge is listed with its reason" 0 \
  "   1 put off until after the merge: the build of main (the workflow runs only on a push to the base branch)" \
  .review/runs/0-qa-T-029-later
never_says "an item put off is not a thing that passed" "nothing: every item passed"

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
# reach GitHub: it prints gh's line for that and exits 1.
# ---------------------------------------------------------------------------

# A PATH with no gh on it, whatever this machine has installed. A folder that is on
# PATH twice is copied once.
path_without_gh=""
while IFS= read -r directory; do
  if [ -e "$directory/gh" ]; then
    copy="$WORK/no-gh/$(printf '%s' "$directory" | tr '/' '_')"
    if [ ! -d "$copy" ]; then
      mkdir -p "$copy" || fail_setup "no-gh folder"
      for tool in "$directory"/*; do
        [ "$(basename "$tool")" = "gh" ] || ln -s "$tool" "$copy/" || fail_setup "no-gh link"
      done
    fi
    directory="$copy"
  fi
  path_without_gh="$path_without_gh${path_without_gh:+:}$directory"
done < <(printf '%s' "$PATH" | tr ':' '\n')

mkdir -p "$WORK/gh-bin"
cat >"$WORK/gh-bin/gh" <<'EOF'
#!/usr/bin/env bash
export GIT_AUTHOR_NAME=gh GIT_AUTHOR_EMAIL=gh@example.com \
  GIT_COMMITTER_NAME=gh GIT_COMMITTER_EMAIL=gh@example.com
printf '%s\n' "$*" >>"$GH_STATE/calls"
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

case "$1 $2" in
  "auth status") [ ! -e "$GH_STATE/logged-out" ]; exit ;;
  "repo view") [ ! -e "$GH_STATE/no-repo" ]; exit ;;
esac

# gh api names the repository in its path, repos/<owner>/<repository>/..., and has no
# --repo; the rest of the path says what is asked.
if [ "$1" = api ]; then
  if [ -e "$GH_STATE/api-fails" ] &&
     printf '%s' "$2" | grep -Eq -- "$(cat "$GH_STATE/api-fails")"; then
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
    find_pr "$3" | fields "$@" ;;
  "pr checks")
    if [ -e "$GH_STATE/pushes-at-checks" ]; then
      rm "$GH_STATE/pushes-at-checks"
      someone_pushes "$(find_pr "$3" | jq -r .headRefName)"
    fi
    answer="$(find_pr "$3" | jq -r '.checks // empty')"
    if [ -z "$answer" ]; then
      answer="$(head -1 "$GH_STATE/checks")"
      [ "$(wc -l <"$GH_STATE/checks")" -le 1 ] || sed -i.old 1d "$GH_STATE/checks"
    fi
    case "$answer" in
      passed) checks='[{"name":"build","bucket":"pass"}]' ;;
      skipped) checks='[{"name":"build","bucket":"pass"},{"name":"docs","bucket":"skipping"}]' ;;
      pending) checks='[{"name":"build","bucket":"pass"},{"name":"test","bucket":"pending"}]' ;;
      failing) checks='[{"name":"build","bucket":"fail"}]' ;;
      cancelled) checks='[{"name":"build","bucket":"cancel"}]' ;;
      cancelled+pending)
        checks='[{"name":"build","bucket":"cancel"},{"name":"test","bucket":"pending"}]' ;;
      unknown) checks='[{"name":"build","bucket":"neutral"}]' ;;
      *) checks='[]' ;;
    esac
    # The statuses posted at the head of the pull request are checks of it too, the
    # newest of each context.
    current_heads
    checks="$(jq -c --argjson checks "$checks" --arg head "$(find_pr "$3" | jq -r .headRefOid)" '
      $checks + ([.[] | select(.sha == $head)] | group_by(.context) | map(last)
        | map({name: .context, description,
               bucket: ({success: "pass", failure: "fail", error: "fail"}[.state]
                        // "pending")}))' "$STATUSES")"
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
    [ ! -e "$GH_STATE/fails-after-merge" ] ||
      { echo "could not tidy the local checkout" >&2; exit 1; }
    case " $* " in
      *" --delete-branch "*) git -C "$GH_REMOTE" update-ref -d "refs/heads/$head_branch" ;;
    esac ;;
esac
EOF
chmod +x "$WORK/gh-bin/gh"
export PATH="$WORK/gh-bin:$PATH" GH_STATE GH_REMOTE

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
holds "that refusal commits nothing" [ "$(git rev-parse HEAD)" = "$landed" ]
publish "a rejected push is an error saying the branch moved" 1 "the remote branch task/T-001 moved"
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
publish "--merge of a closed pull request waits too" 5 "was closed without a merge" --merge
holds "a closed pull request opens no other" gh_count_is "pr create" 1
holds "a closed pull request merges nothing" not gh_called "pr merge"
pr_review "the review of a closed pull request is for the person" 1 \
  "was closed without a merge — for the person"
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
publish "--merge refuses at pr: the person merges" 3 "the person merges, with squash" --merge
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
pr_post "pr-post.sh comments shows it whole" 0 "The tracker says 41." comments
printf 'The requirements ask for 42: REQUIREMENTS.md, "Answer".\n' >"$WORK/reply.md"
pr_post "the loop answers it" 0 "reply to $(person_id) (not-a-problem) posted" \
  reply "$(person_id)" not-a-problem "$WORK/reply.md"
holds "the reply names what it answers, and how" \
  posted "<!-- loop:reply $(person_id) not-a-problem -->"
publish "a person's comment the loop disagreed with waits for the user" 5 \
  "answered not-a-problem: the user decides" --check
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
publish "/qa that left an item unproven waits for the user" 3 \
  "M5: /qa left 1 unproven and 0 not checked in $open_qa — restore what failed" --merge
holds "so does its status" status_is loop/qa pending
qa_checked '[]' "$(git rev-parse HEAD)"
publish "a later /qa of less than the whole pull request does not clear it" 3 \
  "M5: /qa left 1 unproven and 0 not checked in $open_qa" --merge
jq -n '{by: "human", answer: "accepted-as-is", words: "The emulator is broken: fine."}' \
  >".review/runs/$open_qa/open-answered.json"
pr_post "the statuses again" 0 "statuses posted" statuses
holds "the user's answer turns /qa green" status_is loop/qa success
publish "and the task merges" 0 "merged T-001" --merge

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
pr_review "the review refuses a branch with no pull request: for the person" 1 \
  "has no open pull request into main — for the person"
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

published_project origin
set_level pr ASK_AFTER_RUNS=2
printf '#!/usr/bin/env bash\necho %s >"$1"\nexit 1\n' \
  "'{\"test\":{\"status\":\"fail\",\"blocking\":true,\"command\":\"false\",\"output\":\"red\"}}'" \
  >.review/gates.sh
pr_work
pr_land "red gates refuse a landing at pr" 3 "gates are red at landing time" --run "$WORK"
holds "a --run given at pr is said to be unused" printed "--run is not used"
pr_land "a second time too" 3 "gates are red at landing time"
pr_land "past ASK_AFTER_RUNS landings that did not commit, the user decides" 3 \
  "2 landings of T-001 failed at or after their gates since the count started"
pr_land "--past-limit lands once more" 3 "gates are red at landing time" --past-limit
cp "$WORK/gates.green" .review/gates.sh
pr_land "after it the count starts again" 0 "landed T-001 on task/T-001"
pr_work
pr_land "--past-limit below the limit is refused" 1 "only for a task at its limit" --past-limit

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
rm "$GH_STATE/refuses-merge"
publish "publish.sh finishes the merge once nothing stands in the way" 0 "merged T-001" --merge
holds "the waiting opened one pull request" gh_count_is "pr create" 1

published_project origin
reviewed_pull_request merge
touch "$GH_STATE/pushes-at-view"
publish "a pull request that is ahead of HEAD waits" 5 "someone else pushed to task/T-001" --merge
holds "that commit is not merged" not gh_called "pr merge"

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

[ "$FAILURES" -eq 0 ] || { echo "$FAILURES case(s) failed"; exit 1; }
echo "all cases behaved"
