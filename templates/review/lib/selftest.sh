#!/usr/bin/env bash
#
# selftest.sh — runs run.sh and land.sh end to end on a throwaway repository,
# with the reviewer and the maintainer replaced by fixed answers, and checks the
# exit code and the line each case must print. The validation of agent output in
# run.sh is exactly the code no real run exercises until a model answers with
# findings — and it once refused every non-empty answer for two months
# unnoticed. Run it after any change to run.sh, land.sh, the schemas or the
# decision rules of prompts/maintainer.md.
#
# The repository it builds lives in a temporary folder and is deleted at the
# end; the project's own repository is only read.
#
# Usage: CodingStandards/templates/review/lib/selftest.sh
# Exit:  0 — every case behaved; 1 — at least one did not (each is printed)

set -uo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 1
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
FAILURES=0

fail_setup() { echo "setup failed: $1"; exit 1; }

repository="$WORK/project"
mkdir -p "$repository/.review" "$repository/src" || fail_setup "folders"
cd "$repository" || fail_setup "cd"
git init -q -b main || fail_setup "git init"
git config user.email selftest@example.com && git config user.name selftest || fail_setup "git config"
printf 'fun answer() = 41\n' >src/answer.kt
git add src/answer.kt && git commit -q -m start || fail_setup "first commit"
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

finding() {
  printf '{"findings":[{"id":"F-001","file":"src/answer.kt","line":1,"code_quote":"fun answer() = 42","category":%s,"severity":"major","confidence":"confirmed","evidence":"answer() returns 42 where 41 is expected"}]}' "$1"
}

verdict() {
  printf '{"verdicts":[{"finding_id":"F-001","verdict":%s,"severity":"major","decision_rule":"%s","reason":"the finding names a real change of behaviour"}]}' "$1" "$2"
}

check() {
  local name="$1" expected_exit="$2" expected_line="$3" actual_exit="$4" log="$5"
  if [ "$actual_exit" -eq "$expected_exit" ] && grep -qF -- "$expected_line" "$log"; then
    echo "ok    $name (exit $actual_exit)"
  else
    echo "FAIL  $name: expected exit $expected_exit and «$expected_line», got exit $actual_exit — log follows"
    sed 's/^/      /' "$log"
    FAILURES=$((FAILURES + 1))
  fi
}

review() {
  local name="$1" expected_exit="$2" expected_line="$3" reviewer_answer="$4" maintainer_answer="$5"
  printf '%s' "$reviewer_answer" >"$WORK/reviewer.json"
  printf '%s' "$maintainer_answer" >"$WORK/maintainer.json"
  REVIEWER_CMD="cat $WORK/reviewer.json #" MAINTAINER_CMD="cat $WORK/maintainer.json #" \
    "$LIB_DIR/run.sh" --task-file .review/task.json >"$WORK/run.log" 2>&1
  check "$name" "$expected_exit" "$expected_line" $? "$WORK/run.log"
}

land() {
  local name="$1" expected_exit="$2" expected_line="$3" landing="$4"
  printf 'THRESHOLD=major\nLANDING=%s\n' "$landing" >.review/land.conf
  "$LIB_DIR/land.sh" --task-file .review/task.json --run "$(ls -d .review/runs/* | tail -1)" >"$WORK/land.log" 2>&1
  check "$name" "$expected_exit" "$expected_line" $? "$WORK/land.log"
}

review "no findings is clean" 0 "CLEAN — gates green, no verified findings." '{"findings":[]}' '{"verdicts":[]}'
review "an accepted finding goes to the executor" 3 "accepted (>= major): 1" \
  "$(finding '"bug"')" "$(verdict '"accept"' no-rule-fired)"
review "an escalated finding goes to the user" 4 "escalated         : 1" \
  "$(finding '"bug"')" "$(verdict '"escalate"' needs-human-judgment)"
review "a category outside the schema fails closed" 1 "reviewer output does not match" \
  "$(finding '"opinion"')" "$(verdict '"accept"' no-rule-fired)"
review "a category given as a list fails closed" 1 "reviewer output does not match" \
  "$(finding '["bug"]')" "$(verdict '"accept"' no-rule-fired)"
review "a verdict outside the schema fails closed" 1 "maintainer output is malformed" \
  "$(finding '"bug"')" "$(verdict '"maybe"' no-rule-fired)"
review "a verdict given as a list fails closed" 1 "maintainer output is malformed" \
  "$(finding '"bug"')" "$(verdict '["escalate"]' needs-human-judgment)"
review "a rejected finding leaves the run clean" 0 "rejected          : 1" \
  "$(finding '"bug"')" "$(verdict '"reject"' contradicts-green-gate)"

land "landing off on main prints the commit with a note" 0 "Note: current branch is main" off
land "landing on on main refuses by condition 8" 3 "condition 8" on

counted() {
  local name="$1" expected_exit="$2" expected_line="$3" task_id="$4"; shift 4
  printf '{"id": "%s", "title": "Answer 42", "category": "bugfix", "scope": ["src/*"], "exit_criteria": []}' \
    "$task_id" >".review/$task_id.json"
  printf '{"findings":[]}' >"$WORK/reviewer.json"
  printf '{"verdicts":[]}' >"$WORK/maintainer.json"
  REVIEWER_CMD="cat $WORK/reviewer.json #" MAINTAINER_CMD="cat $WORK/maintainer.json #" \
    "$LIB_DIR/run.sh" --task-file ".review/$task_id.json" "$@" >"$WORK/run.log" 2>&1
  check "$name" "$expected_exit" "$expected_line" $? "$WORK/run.log"
}

printf 'THRESHOLD=major\nLANDING=off\nASK_AFTER_RUNS=2\n' >.review/land.conf
counted "the first run of a task runs" 0 "CLEAN" T-002
counted "a run up to the limit runs" 0 "CLEAN" T-002
runs_before="$(ls .review/runs | wc -l)"
counted "a run past the limit waits for the user" 6 "WAIT FOR THE USER — T-002 has had 2 runs since the count started, 2 in all" T-002
if [ "$(ls .review/runs | wc -l)" -eq "$runs_before" ]; then
  echo "ok    a run past the limit leaves no run behind"
else
  echo "FAIL  a run past the limit left a run directory behind"
  FAILURES=$((FAILURES + 1))
fi
counted "the runs of another task are not counted" 0 "CLEAN" T-003
counted "--past-limit below the limit is refused" 1 "only for a task at its limit" T-003 --past-limit
counted "--past-limit runs once more" 0 "CLEAN" T-002 --past-limit
counted "--past-limit left in the command fails on the next run" 1 "only for a task at its limit" T-002 --past-limit
counted "after --past-limit the count starts again from zero" 0 "CLEAN" T-002
counted "a run up to the limit after --past-limit runs" 0 "CLEAN" T-002
counted "the count after --past-limit reaches the limit again" 6 "has had 2 runs since the count started, 5 in all" T-002
for task_without_id in '{"title": "no id"}' '{"id": "", "title": "empty id"}'; do
  printf '%s' "$task_without_id" >.review/no-id.json
  REVIEWER_CMD="cat $WORK/reviewer.json #" MAINTAINER_CMD="cat $WORK/maintainer.json #" \
    "$LIB_DIR/run.sh" --task-file .review/no-id.json >"$WORK/run.log" 2>&1
  check "a task file $task_without_id fails closed" 1 "has no .id" $? "$WORK/run.log"
done
for limit in none 0 05; do
  printf 'THRESHOLD=major\nLANDING=off\nASK_AFTER_RUNS=%s\n' "$limit" >.review/land.conf
  counted "a limit of '$limit' fails closed" 1 "must be a whole number from 1" T-002
done

printf 'THRESHOLD=major\nLANDING=off\nASK_AFTER_RUNS=100\n' >.review/land.conf
printf '{"id": "T-004", "title": "Answer 42", "category": "bugfix", "scope": ["src/*"], "exit_criteria": [{"text": "answer() returns 42", "verified_by": "manual: read src/answer.kt"}]}' >.review/T-004.json
runs_listed="$(ls .review/runs)"
printf '%s' "$(finding '"bug"')" >"$WORK/reviewer.json"
printf '%s' "$(verdict '"reject"' contradicts-green-gate)" >"$WORK/maintainer.json"
REVIEWER_CMD="cat $WORK/reviewer.json #" MAINTAINER_CMD="cat $WORK/maintainer.json #" \
  "$LIB_DIR/run.sh" --task-file .review/T-004.json >"$WORK/run.log" 2>&1
run_of_t004=".review/runs/$(comm -13 <(printf '%s\n' "$runs_listed") <(ls .review/runs))"
cp .review/gates.sh "$WORK/gates.green"
cat >.review/gates.sh <<'EOF'
#!/usr/bin/env bash
echo '{"test":{"status":"fail","blocking":true,"command":"false","output":"could not boot the test simulator"}}' >"$1"
exit 1
EOF
"$LIB_DIR/land.sh" --task-file .review/T-004.json --run "$run_of_t004" >"$WORK/land.log" 2>&1
check "red gates at landing refuse by condition 3" 3 "gates are red at landing time" $? "$WORK/land.log"
"$LIB_DIR/land.sh" --task-file .review/T-004.json --run "$run_of_t004" >"$WORK/land.log" 2>&1
check "landing the same run may be retried once after red gates" 3 "gates are red at landing time" $? "$WORK/land.log"
"$LIB_DIR/land.sh" --task-file .review/T-004.json --run "$run_of_t004" >"$WORK/land.log" 2>&1
check "red gates at landing twice send the work back to run.sh" 3 "failed at or after its gates twice" $? "$WORK/land.log"

cp "$WORK/gates.green" .review/gates.sh
runs_listed="$(ls .review/runs)"
REVIEWER_CMD="cat $WORK/reviewer.json #" MAINTAINER_CMD="cat $WORK/maintainer.json #" \
  "$LIB_DIR/run.sh" --task-file .review/T-004.json >"$WORK/run.log" 2>&1
run_of_t004=".review/runs/$(comm -13 <(printf '%s\n' "$runs_listed") <(ls .review/runs))"
printf '#!/usr/bin/env bash\nexit 143\n' >.review/gates.sh
for attempt in first second; do
  "$LIB_DIR/land.sh" --task-file .review/T-004.json --run "$run_of_t004" >"$WORK/land.log" 2>&1
  check "gates killed at landing refuse the $attempt time" 3 "did not run" $? "$WORK/land.log"
done
"$LIB_DIR/land.sh" --task-file .review/T-004.json --run "$run_of_t004" >"$WORK/land.log" 2>&1
check "gates killed at landing twice send the work back to run.sh" 3 "failed at or after its gates twice" $? "$WORK/land.log"

cat >.review/gates.sh <<'EOF'
#!/usr/bin/env bash
echo '{"build":{"status":"pass","blocking":true,"command":"true","output":""},"lint":{"status":"fail","blocking":false,"command":"false","output":"style"}}' >"$1"
EOF
runs_listed="$(ls .review/runs)"
REVIEWER_CMD="cat $WORK/reviewer.json #" MAINTAINER_CMD="cat $WORK/maintainer.json #" \
  "$LIB_DIR/run.sh" --task-file .review/T-004.json >"$WORK/run.log" 2>&1
run_of_t004=".review/runs/$(comm -13 <(printf '%s\n' "$runs_listed") <(ls .review/runs))"
for attempt in first second third; do
  "$LIB_DIR/land.sh" --task-file .review/T-004.json --run "$run_of_t004" >"$WORK/land.log" 2>&1
  check "a failing gate that does not block never stops a $attempt landing" 0 "Note: current branch is main" $? "$WORK/land.log"
done
cp "$WORK/gates.green" .review/gates.sh

printf '#!/usr/bin/env bash\nsleep 30\n' >.review/gates.sh
"$LIB_DIR/land.sh" --task-file .review/T-004.json --run "$run_of_t004" >"$WORK/land.log" 2>&1 &
landing=$!
sleep 1
pkill -P "$landing"
kill "$landing" 2>/dev/null
wait "$landing" 2>/dev/null
if [ "$(cat "$run_of_t004/landing-reds")" = 1 ]; then
  echo "ok    a landing killed while the gates run is counted"
else
  echo "FAIL  a landing killed while the gates run is not counted"
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
  check "a commit that fails after green gates fails the $attempt time" 1 "commit failed" $? "$WORK/land.log"
done
"$LIB_DIR/land.sh" --task-file .review/T-004.json --run "$run_of_t004" >"$WORK/land.log" 2>&1
check "a commit that failed twice sends the work back to run.sh" 3 "failed at or after its gates twice" $? "$WORK/land.log"
rm .git/hooks/pre-commit

rules_in_prompt="$(grep -oE '\(`[a-z-]+`\)' "$LIB_DIR/prompts/maintainer.md" | tr -d '()`' | sort -u)"
rules_in_schema="$(jq -r '.properties.verdicts.items.properties.decision_rule.enum[]' "$LIB_DIR/schemas/maintainer-verdicts.schema.json" | sort -u)"
missing="$(comm -23 <(printf '%s\n' "$rules_in_prompt") <(printf '%s\n' "$rules_in_schema"))"
if [ -z "$missing" ]; then
  echo "ok    every decision rule of the prompt is in the schema"
else
  echo "FAIL  decision rules of prompts/maintainer.md missing from the schema: $missing"
  FAILURES=$((FAILURES + 1))
fi

[ "$FAILURES" -eq 0 ] || { echo "$FAILURES case(s) failed"; exit 1; }
echo "all cases behaved"
