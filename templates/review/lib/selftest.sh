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
printf 'THRESHOLD=major\nLANDING=off\n' >.review/land.conf
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
