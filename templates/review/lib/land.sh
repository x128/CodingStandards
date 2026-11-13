#!/usr/bin/env bash
#
# land.sh — the only thing in the pipeline that commits.
#
# Runs FROM THE SUBMODULE and is deliberately NOT overridable by projects: it is
# the one file with commit authority, so it must not be widenable locally.
#
# It has no code path for push, amend, --force, rebase, checkout, reset, stash or
# clean. It stages the task's declared files, the loop's own and the end-to-end
# harness the task changed, and commits: on the current branch, or at LANDING=push,
# pr and merge on task/<id>, the one branch it may create and the only one it may
# move to. That is all it can do.
# Whatever happens to the commit next is in publish.sh, which it calls and which
# cannot commit.
#
# It refuses (exit 3) unless all eight landing conditions hold. A ninth switch,
# LANDING, then decides how far the task goes: off only prints the commit, which
# is not a refusal and exits 0; on commits; push, pr and merge commit and call
# publish.sh. See TASK_LOOP.md § Landing.
#
# Usage, from the project root:
#   land.sh --task-file <task.json> --run <run-dir> [--message "..."] [--dry-run]
#
# Exit codes:
#   0  committed and published as far as LANDING says (or printed the commit, in
#      dry-run / LANDING=off)
#   3  refused — a landing condition failed, with the reason on stderr
#   4  the commit landed but publishing did not finish — publish.sh's output says
#      why. If no code has to change, meet the cause and run publish.sh alone, never
#      land.sh again; a change to the code is a new pass of the loop on this branch
#   1  usage or environment error
#
# Requires: jq >= 1.6, git >= 2.23; gh at LANDING=pr and merge

set -uo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 1
# shellcheck source=common.sh
. "$LIB_DIR/common.sh"

TASK_FILE=""
RUN_DIR=""
MESSAGE=""
DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --task-file) require_value "--task-file" $#; TASK_FILE="$2"; shift 2 ;;
    --run)       require_value "--run" $#; RUN_DIR="$2"; shift 2 ;;
    --message)   require_value "--message" $#; MESSAGE="$2"; shift 2 ;;
    --dry-run)   DRY_RUN=1; shift ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done

[ -n "$TASK_FILE" ] || { echo "--task-file is required" >&2; exit 1; }
[ -n "$RUN_DIR" ]   || { echo "--run is required" >&2; exit 1; }
[ -f "$TASK_FILE" ] || { echo "no such task file: $TASK_FILE" >&2; exit 1; }
[ -d "$RUN_DIR" ]   || { echo "no such run directory: $RUN_DIR" >&2; exit 1; }

# Resolved before the cd below. Documented usage is "from the project root", but
# run from a subdirectory these relative paths would quietly point elsewhere
# afterwards and land as a condition-2 refusal instead of a usage error.
TASK_FILE="$(abspath "$TASK_FILE")" || exit 1
RUN_DIR="$(abspath "$RUN_DIR")" || exit 1

PROJECT_ROOT="$(git rev-parse --show-toplevel)" || exit 1
cd "$PROJECT_ROOT" || exit 1

REVIEW_DIR=".review"
CONFIG="$REVIEW_DIR/land.conf"

# The config is read as data, never sourced — a project must not be able to
# redefine a command or a guard in the one script with commit authority.
PROTECTED_BRANCHES="$(protected_branches "$CONFIG")"

refuse() {
  echo "LANDING REFUSED — condition $1: $2" >&2
  exit 3
}

LANDING="$(landing_level "$CONFIG")" || refuse 8 "$LANDING"

TASK_ID="$(jq -r '.id' "$TASK_FILE")"
[ -n "$TASK_ID" ] && [ "$TASK_ID" != "null" ] || { echo "task file has no .id" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 1. The run directory is a completed review run.
#    Missing files must never read as "nothing was found" — that would let any
#    empty directory authorise a commit.
# ---------------------------------------------------------------------------

for artifact in meta.json verdicts.json approved.json escalated.json e2e.json; do
  [ -f "$RUN_DIR/$artifact" ] || \
    refuse 1 "$RUN_DIR has no $artifact — this is not a completed review run"
done

# The threshold comes from the run that produced these verdicts, so landing can
# never apply a different bar than the review did.
THRESHOLD="$(jq -r '.threshold // "major"' "$RUN_DIR/meta.json")"

# ---------------------------------------------------------------------------
# 2. The run reviewed THIS tree. Any edit since the review — including the fix
#    that was supposed to be the last one — invalidates it.
# ---------------------------------------------------------------------------

# The run must belong to THIS task: the maintainer triaged against one task's
# scope, and landing checks another's. `.review/` (the harness apart) is outside the
# fingerprint, so nothing else would catch a swapped task file.
# Both sides are absolute: review.sh resolves the path before recording it, and
# this script resolves its own argument the same way.
REVIEWED_TASK="$(jq -r '.task_file // ""' "$RUN_DIR/meta.json")"
[ -n "$REVIEWED_TASK" ] || \
  refuse 2 "this run was made without a task file — its triage never saw a scope"
[ "$REVIEWED_TASK" = "$TASK_FILE" ] || \
  refuse 2 "this run reviewed $REVIEWED_TASK, not $TASK_FILE"

REVIEWED_FINGERPRINT="$(jq -r '.tree_fingerprint // ""' "$RUN_DIR/meta.json")"
CURRENT_FINGERPRINT="$(tree_fingerprint)"
[ -n "$REVIEWED_FINGERPRINT" ] || refuse 2 "$RUN_DIR/meta.json has no tree fingerprint"
[ "$REVIEWED_FINGERPRINT" = "$CURRENT_FINGERPRINT" ] || \
  refuse 2 "the tree changed after this review ran — review again before landing"

# ---------------------------------------------------------------------------
# 3, end-to-end half. The run's end-to-end tests passed on this tree, on every
#    platform the tree ships, through the harness as it is now. Only files are
#    read: the devices ran in review.sh, and condition 2 binds that run to this
#    tree, the harness included: a change to the harness is in the reviewed diff
#    and lands with the task.
# ---------------------------------------------------------------------------

PLATFORMS_NOW="$(platforms | jq -R . | jq -sc .)"
jq -e --arg fingerprint "$CURRENT_FINGERPRINT" --argjson need "$PLATFORMS_NOW" \
  '.status == "pass" and .fingerprint == $fingerprint and (($need - .platforms) | length) == 0' \
  "$RUN_DIR/e2e.json" >/dev/null 2>&1 || \
  refuse 3 "the end-to-end tests of this run did not pass on every platform the tree ships: "\
"$(printf '%s' "$PLATFORMS_NOW" | jq -r 'join(" ")')"

# The harness is `.review/e2e.sh` and any `.review/e2e-*` it calls: each must be
# now as it ran (recorded before the run), and `.review/e2e.sh` must be there.
HARNESS_NOW="$(harness_blobs)"
case "$HARNESS_NOW" in *" $REVIEW_DIR/e2e.sh"*) ;; *) HARNESS_NOW="" ;; esac
[ -n "$HARNESS_NOW" ] && [ "$(jq -r '.harness // ""' "$RUN_DIR/e2e.json")" = "$HARNESS_NOW" ] || \
  refuse 3 "$REVIEW_DIR/e2e.sh, or a $REVIEW_DIR/e2e-* beside it, is not as it ran — review again"

# Every test a case of qa/test-cases.md names now, under that case, was one the run
# was checked against. The cases are one of the loop's own files, outside condition
# 2: a mark written since the run names a test no run has seen pass. Checked again
# after the gates, which run between here and the commit.
marks_checked_by_run() {
  local now unchecked
  now="$(case_marks | marks_json)" || refuse 3 "could not read the marks of qa/test-cases.md"
  unchecked="$(jq -r --argjson now "$now" \
    '$now - (.marks // []) | map("\(.case) \(.test)") | join(", ")' "$RUN_DIR/e2e.json")" || \
    refuse 3 "$RUN_DIR/e2e.json is unreadable"
  [ -z "$unchecked" ] || \
    refuse 3 "qa/test-cases.md names end-to-end tests this run was not checked against: "\
"$unchecked — review again before landing"
}
marks_checked_by_run

# ---------------------------------------------------------------------------
# 4 & 5. No outstanding findings, no pending escalations.
# ---------------------------------------------------------------------------

APPROVED_COUNT="$(require_array_length "$RUN_DIR/approved.json")" || \
  refuse 4 "approved.json is unreadable — refusing to assume it is empty"
[ "$APPROVED_COUNT" -eq 0 ] || \
  refuse 4 "$APPROVED_COUNT accepted finding(s) at or above $THRESHOLD are unresolved"

ESCALATED_COUNT="$(require_array_length "$RUN_DIR/escalated.json")" || \
  refuse 5 "escalated.json is unreadable — refusing to assume it is empty"

# An escalation is answered, not waited out. The answer is recorded in
# escalations-answered.json — one entry per escalated finding — and only then
# does landing proceed. Without this an escalated finding (every replication
# finding, for one) could never land at all: re-running the review reproduces it.
if [ "$ESCALATED_COUNT" -gt 0 ]; then
  ANSWERS="$RUN_DIR/escalations-answered.json"
  [ -f "$ANSWERS" ] || \
    refuse 5 "$ESCALATED_COUNT escalation(s) are waiting for an answer — "\
"record the answers in $ANSWERS"
  # The same discipline conditions 4 and 5 apply above, and for the same reason:
  # a jq that dies on a malformed answers file prints nothing, and nothing is
  # indistinguishable from "no unanswered escalations". That is the exact
  # fail-open this whole section exists to prevent, so the file is proved to be
  # a JSON array first, and the query's own exit status is checked after.
  require_array_length "$ANSWERS" >/dev/null || \
    refuse 5 "$ANSWERS is unreadable — refusing to assume the escalations were answered"
  UNANSWERED="$(jq -r --slurpfile answers "$ANSWERS" '
    [ .[] | select(.finding_id as $id
        | ([$answers[0][] | select((.resolution // "") != "") | .finding_id] | index($id)) == null)
      | .finding_id ] | join(", ")' "$RUN_DIR/escalated.json")" || \
    refuse 5 "could not read the escalation answers in $ANSWERS — "\
"refusing to assume they are answered"
  [ -z "$UNANSWERED" ] || \
    refuse 5 "escalation(s) with no recorded answer: $UNANSWERED"
fi

# ---------------------------------------------------------------------------
# 6. The diff stayed inside the task's declared scope.
#    Note: in bash pattern matching `*` also matches `/`, so `src/*` covers
#    nested paths — write scopes accordingly.
# ---------------------------------------------------------------------------

# Built with a read loop rather than mapfile: macOS still ships bash 3.2.
SCOPE_PATTERNS=()
while IFS= read -r pattern; do
  [ -n "$pattern" ] && SCOPE_PATTERNS+=("$pattern")
done < <(jq -r '.scope[]?' "$TASK_FILE")
[ "${#SCOPE_PATTERNS[@]}" -gt 0 ] || refuse 6 "task $TASK_ID declares no scope"

# The pipeline's own bookkeeping (decision logs, policy edits, run artifacts) is
# never part of a task's diff: it is not scope-checked, not staged, and not
# committed here — see the `--only` on the commit below, which is what makes
# that last part true. Policy and threshold changes are the user's to commit.
# The end-to-end harness is the one exception: it is reviewed work and lands with
# the task, below, even a task of the harness alone. The loop's own files land too,
# but need a task to land with: alone, they are not a task.
# Names as they are (core.quotePath=false): a quoted non-ASCII name matches no
# scope and is no file to stage.
EVERY_CHANGE="$( { git -c core.quotePath=false diff --name-only;
                   git -c core.quotePath=false diff --cached --name-only;
                   git -c core.quotePath=false ls-files --others --exclude-standard; } \
                 | sort -u )"
CHANGED_FILES="$(printf '%s\n' "$EVERY_CHANGE" | only_task_work)"
HARNESS_CHANGED="$(printf '%s\n' "$EVERY_CHANGE" | grep -E '^\.review/e2e(\.sh|-.*)$')"
[ -n "$CHANGED_FILES" ] || [ -n "$HARNESS_CHANGED" ] || \
  refuse 6 "nothing to commit outside .review/, the end-to-end harness apart, "\
"and the loop's own files"

OUT_OF_SCOPE=""
IN_SCOPE=()
while IFS= read -r file; do
  [ -n "$file" ] || continue
  matched=0
  for pattern in "${SCOPE_PATTERNS[@]}"; do
    # shellcheck disable=SC2053
    if [[ "$file" == $pattern ]]; then matched=1; break; fi
  done
  if [ "$matched" -eq 1 ]; then
    IN_SCOPE+=("$file")
  else
    OUT_OF_SCOPE="$OUT_OF_SCOPE $file"
  fi
done <<<"$CHANGED_FILES"

[ -z "$OUT_OF_SCOPE" ] || \
  refuse 6 "files outside task scope:$OUT_OF_SCOPE — split them into their own task"

# What the commit holds: the task's files, the loop's own, and the end-to-end harness
# the task changed. The decision logs record what the user said, and the requirements
# and the plan are the product owner's: at every LANDING they stay in the tree for the
# user. A task of the harness alone has no file in scope: the expansion below is empty
# then, which bash 3.2 under `set -u` refuses to expand as "${IN_SCOPE[@]}".
TO_COMMIT=(${IN_SCOPE[@]+"${IN_SCOPE[@]}"})
while IFS= read -r file; do
  if is_loop_file "$file"; then
    TO_COMMIT+=("$file")
  fi
done <<<"$EVERY_CHANGE"
while IFS= read -r file; do
  [ -z "$file" ] || TO_COMMIT+=("$file")
done <<<"$HARNESS_CHANGED"

# ---------------------------------------------------------------------------
# 7. Every exit criterion carries an explicit verification claim.
#    Machine-checkable criteria belong in gates; the rest must at least be
#    stated, so the claim lands in the commit and can be audited later.
#    A task may have none: criteria are gathered before a task starts, never
#    written at its start (PLANNING_GUIDE.md, "Task Rules").
# ---------------------------------------------------------------------------

CRITERIA_COUNT="$(jq '.exit_criteria | length' "$TASK_FILE")"

UNVERIFIED=\
"$(jq -r '[.exit_criteria[] | select((.verified_by // "") == "")] | length' "$TASK_FILE")"
[ "$UNVERIFIED" -eq 0 ] || \
  refuse 7 "$UNVERIFIED exit criterion/criteria have no verified_by claim"

#    /qa checked the task, and each failure it recorded — in a qa.json, or in
#    the qa_failures an e2e.json of this task took from one, which outlasts a
#    qa.json rewritten or removed — has a test its case is marked with that
#    failed in a run of this task made after /qa recorded it: passing in this
#    run, or skipped in it under a tag of the case for the task it belongs to.
#    Or the user answered it. No test stays skipped for the task that lands
#    now. Every record is read: an unreadable one refuses, never reads as "no
#    failures".

QA_RECORDS="$(for record in "$REVIEW_DIR"/runs/*/qa.json; do
    [ -f "$record" ] || continue
    jq -c . "$record" || exit 1
  done | jq -sc --arg id "$TASK_ID" '
    map(select(.task == $id))
    | if all(.[]; (.failures | type) == "array"
                  and all(.failures[]; (.case? // "") | test("^TC-[0-9]+$")))
      then . else error("malformed") end')" || \
  refuse 7 "a qa.json is unreadable or not {task, failures: [{case: TC-nnn}]} — "\
"refusing to read it as no failures"
[ "$(printf '%s' "$QA_RECORDS" | jq 'length')" -gt 0 ] || \
  refuse 7 "no /qa record (qa.json) for $TASK_ID — /qa has not checked this task"

SKIP_TAGS="$(skip_tags)"
[ $? -le 1 ] || refuse 7 "could not search the tree for skipped end-to-end tests"
for task in $(printf '%s' "$TASK_ID" | tr '+' ' '); do
  STILL_SKIPPED="$(printf '%s\n' "$SKIP_TAGS" | awk -F'\t' -v task="$task" '
    { split($1, tag, ": "); n = split(tag[1], ids, "+")
      for (i = 1; i <= n; i++)
        if (ids[i] == task) { cases = cases " " tag[2]; files = files " " $2 } }
    END { if (cases != "")
            print substr(cases, 2) " is still skipped for " task " — make it pass:" files }')"
  [ -z "$STILL_SKIPPED" ] || refuse 7 "the end-to-end test of $STILL_SKIPPED"
done

RUNS_OF_TASK="$(for record in "$REVIEW_DIR"/runs/*/e2e.json; do
    [ -f "$record" ] || continue
    jq -c . "$record" || exit 1
  done | jq -sc --arg id "$TASK_ID" '[.[] | select(.task == $id)
    | {qa: (.qa_failures // []), failed: [.results[]?.failed[]?]}]')" || \
  refuse 7 "an e2e.json is unreadable — refusing to read it as no failures"
FAILURES="$(jq -nc --argjson records "$QA_RECORDS" --argjson runs "$RUNS_OF_TASK" \
  '[$records[].failures[].case] + [$runs[].qa[]] | unique')" || \
  refuse 7 "could not gather the /qa failures of $TASK_ID"
NOW="$(jq -c '{passed: [.results[]?.passed[]?], skipped: [.results[]?.skipped[]?]}' \
  "$RUN_DIR/e2e.json")" || \
  refuse 7 "$RUN_DIR/e2e.json is unreadable"
# Only the user's answer counts, and only one that lets the task land: `fixed`
# means review again (maintain, step 7).
ANSWERED="[]"
if [ -f "$RUN_DIR/escalations-answered.json" ]; then
  require_array_length "$RUN_DIR/escalations-answered.json" >/dev/null && \
  ANSWERED="$(jq -c '[.[] | select(.by == "human"
      and (.resolution == "accepted-as-is" or .resolution == "deferred"))
    | .finding_id]' "$RUN_DIR/escalations-answered.json")" || \
    refuse 7 "$RUN_DIR/escalations-answered.json is unreadable — refusing to assume an answer"
fi

UNPROVEN=""
for case_id in $(printf '%s' "$FAILURES" | jq -r '.[]'); do
  TESTS="$(case_tests "$case_id" | while IFS= read -r test_id; do
      tagged=false
      skip_tag_on "$SKIP_TAGS" "$case_id" "$test_id" && tagged=true
      jq -nc --arg test "$test_id" --argjson tagged "$tagged" '{test: $test, tagged: $tagged}'
    done | jq -sc .)"
  jq -en --argjson tests "$TESTS" --argjson runs "$RUNS_OF_TASK" --argjson now "$NOW" \
        --argjson answered "$ANSWERED" --arg case "$case_id" "$JQ_HIT"'
    def among($rows): . as $id | any($rows[]; hit($id));
    ($answered | index($case)) != null
      or any($tests[]; . as $mark
             | any($runs[]; . as $run
                   | ($run.qa | index($case)) != null and ($mark.test | among($run.failed)))
               and (($mark.test | among($now.passed))
                    or ($mark.tagged and ($mark.test | among($now.skipped)))))' \
    >/dev/null || UNPROVEN="$UNPROVEN $case_id"
done
[ -z "$UNPROVEN" ] || \
  refuse 7 "a /qa failure without an end-to-end test seen red, then green:$UNPROVEN — "\
"mark the case with its test (e2e: \`<test>\`), see it fail in a run of $TASK_ID made after /qa "\
"recorded it, then pass; where no end-to-end test can see it, the user answers it in "\
"$RUN_DIR/escalations-answered.json (by: human, accepted-as-is or deferred)"

# ---------------------------------------------------------------------------
# 8. Never onto a protected branch, never onto a detached HEAD, and at the levels
#    that publish, nothing that would leave the landing half done for a reason
#    known now.
# ---------------------------------------------------------------------------

#    The protected-branch half guards the loop's own commit. With LANDING=off
#    there is none — the user commits, on whatever branch they work on — so it
#    is reported instead of refused. A detached HEAD refuses at every level: the
#    files and the message would be for a commit no branch reaches; otherwise a
#    project whose requirement "Who writes to git" leaves commits to the user and
#    that works on main could never get the files and the message out of the
#    loop at all.
#
#    At push, pr and merge a protected branch is left for task/<id>, as is the
#    branch of another task, whose id the commit would not match. That branch is
#    only decided here: it is created just before the commit, after the gates,
#    so a refused landing leaves the branch as it was. What the push would meet
#    is checked here too: a task branch that exists elsewhere, a remote branch that
#    moved, commits under this one that no landing made.

BRANCH="$(current_branch)"
BRANCH_NOTE=""
LANDING_BRANCH="$BRANCH"
REMOTE=""
BASE_BRANCH=""
[ -n "$BRANCH" ] || \
  refuse 8 "HEAD is detached — a commit here would be unreachable from any branch"

if landing_publishes "$LANDING"; then
  task_id_names_branch "$TASK_ID" || \
    refuse 8 "task id $TASK_ID cannot name a branch — "\
"it must match ^[A-Za-z0-9._-]+\$ and be a valid ref"
  REMOTE="$(resolve_remote "$CONFIG")" || refuse 8 "$REMOTE"
  BASE_BRANCH="$(resolve_base_branch "$CONFIG" "$REMOTE")" || refuse 8 "$BASE_BRANCH"
  PROBLEM="$(publishing_problem "$CONFIG" "$LANDING" "$REMOTE" "$BASE_BRANCH")" || \
    refuse 8 "$PROBLEM"

  TASK_BRANCH="task/$TASK_ID"
  if [ "$BRANCH" != "$TASK_BRANCH" ]; then
    git show-ref --verify --quiet "refs/heads/$TASK_BRANCH" && \
      refuse 8 "$TASK_BRANCH exists and is not the current branch, $BRANCH"
    ON_REMOTE="$(git ls-remote --heads "$REMOTE" "refs/heads/$TASK_BRANCH" 2>/dev/null)" || \
      refuse 8 "the remote $REMOTE cannot be reached"
    [ -z "$ON_REMOTE" ] || \
      refuse 8 "$TASK_BRANCH exists on $REMOTE and is not the current branch, $BRANCH"
  fi

  OTHER_TASK_BRANCH=0
  case "$BRANCH" in task/*) [ "$BRANCH" = "$TASK_BRANCH" ] || OTHER_TASK_BRANCH=1 ;; esac
  if [ "$OTHER_TASK_BRANCH" -eq 1 ] || \
    branch_in_list "$BRANCH" "$PROTECTED_BRANCHES $BASE_BRANCH"; then
    # A branch named task leaves no room for a folder of that name in the refs.
    NAMED_TASK="$(git show-ref --heads task 2>/dev/null; \
git ls-remote --heads "$REMOTE" refs/heads/task 2>/dev/null)"
    printf '%s\n' "$NAMED_TASK" | grep -qE '[[:space:]]refs/heads/task$' && \
      refuse 8 "a branch named task exists, so $TASK_BRANCH cannot be created"
    LANDING_BRANCH="$TASK_BRANCH"
  fi

  REMOTE_TIP=\
"$(git ls-remote --heads "$REMOTE" "refs/heads/$LANDING_BRANCH" 2>/dev/null | cut -f1)"
  if [ -n "$REMOTE_TIP" ] && \
    ! git merge-base --is-ancestor "$REMOTE_TIP" HEAD 2>/dev/null; then
    refuse 8 "$LANDING_BRANCH on $REMOTE has moved past this one — "\
"it is never forced, so a person brings the two together first"
  fi

  UNLANDED="$(commits_no_landing_made "$LANDING" "$REMOTE" "$BASE_BRANCH")"
  [ -z "$UNLANDED" ] || \
    refuse 8 "LANDING=$LANDING would publish commits no landing made — "\
"a person pushes or moves them first: $(printf '%s' "$UNLANDED" | tr '\n' ';')"
elif branch_in_list "$BRANCH" "$PROTECTED_BRANCHES"; then
  [ "$LANDING" != "on" ] || \
    refuse 8 "current branch is $BRANCH — landing never touches a protected branch"
  BRANCH_NOTE="current branch is $BRANCH, a protected branch: "\
"the loop would not commit here; the user decides where the commit goes"
fi

# ---------------------------------------------------------------------------
# 3. Gates re-run green NOW. Cheap insurance, and it catches an environment
#    that drifted between review and landing. Checked after 4 to 8, which read
#    files and, at the levels that publish, ask the remote and gh: a landing
#    refused for one of those, again and again, then never rebuilds and retests.
# ---------------------------------------------------------------------------

[ -x "$REVIEW_DIR/gates.sh" ] || \
  refuse 3 "$REVIEW_DIR/gates.sh is missing or not executable — the gates cannot be confirmed"

# A landing whose gates end red or unfinished, or which fails after them, may be
# retried once on the same run — the simulator is booted again, say — so the
# answers to its escalations still apply. A second time sends the work back
# through review.sh: review.sh counts its runs per task and stops at ASK_AFTER_RUNS,
# and nothing else counts landings, so retrying landing alone could rebuild and
# retest without end. The attempt is written before the gates start, so a gate
# run that hangs or is killed counts too, and taken back only once the commit is
# made or printed.
LANDING_REDS="$(cat "$RUN_DIR/landing-reds" 2>/dev/null)"
case "$LANDING_REDS" in ''|*[!0-9]*) LANDING_REDS=0 ;; esac
[ "$LANDING_REDS" -lt 2 ] || \
  refuse 3 "the landing of this run failed at or after its gates twice — "\
"ask the user, then run review.sh again; another landing of this run would repeat uncounted"
printf '%s\n' "$((LANDING_REDS + 1))" >"$RUN_DIR/landing-reds"

"$REVIEW_DIR/gates.sh" "$RUN_DIR/gates.land.json" >/dev/null 2>&1
GATES_EXIT=$?

# "Could not run the gates" and "the gates are red" are different refusals, and
# only the second one means go fix the code.
if [ "$GATES_EXIT" -ge 126 ] || \
  ! jq -e 'type == "object"' "$RUN_DIR/gates.land.json" >/dev/null 2>&1; then
  refuse 3 "$REVIEW_DIR/gates.sh did not run (exit $GATES_EXIT) — "\
"the gates were never confirmed green"
fi

if [ "$GATES_EXIT" -ne 0 ]; then
  FAILED_GATES="$(jq -r 'to_entries[] | select(.value.status == "fail") | .key' \
    "$RUN_DIR/gates.land.json" | tr '\n' ' ')"
  refuse 3 "gates are red at landing time: ${FAILED_GATES:-unknown}"
fi

# ---------------------------------------------------------------------------
# 9. Landing is explicitly delegated.
# ---------------------------------------------------------------------------

if [ "$LANDING" = "off" ]; then
  DRY_RUN=1
fi

# ---------------------------------------------------------------------------
# Commit
# ---------------------------------------------------------------------------

GATE_SUMMARY="$(jq -r '[to_entries[] | "\(.key)=\(.value.status)"] | join(",")' \
  "$RUN_DIR/gates.land.json")"
REJECTED_COUNT=\
"$(jq '[.verdicts[] | select(.verdict == "reject")] | length' "$RUN_DIR/verdicts.json")"
FINDING_COUNT="$(jq '.verdicts | length' "$RUN_DIR/verdicts.json")"

if [ -z "$MESSAGE" ]; then
  MESSAGE="$TASK_ID: $(jq -r '.title // .id' "$TASK_FILE")"
fi

# Trailers are self-contained: the run directory is local and gitignored, so
# the commit carries the audit facts themselves rather than a path to them.
COMMIT_BODY="$(printf 'Task-Id: %s\nGates: %s\n'\
'Findings: %s reviewed, %s rejected, 0 outstanding at %s+\n'\
'Exit-Criteria: %s verified\nReview-Run: %s (local)\n' \
  "$TASK_ID" "$GATE_SUMMARY" "$FINDING_COUNT" "$REJECTED_COUNT" "$THRESHOLD" \
  "$CRITERIA_COUNT" "$(basename "$RUN_DIR")")"

if [ "$DRY_RUN" -eq 1 ]; then
  if [ "$LANDING" = "off" ]; then
    echo "LANDING=off in $CONFIG — not committing. For the user to commit:"
    [ -z "$BRANCH_NOTE" ] || echo "Note: $BRANCH_NOTE."
  else
    echo "dry run — not committing. The commit would be:"
    echo "Branch: $LANDING_BRANCH"
    if landing_publishes "$LANDING"; then
      echo "Then, at LANDING=$LANDING: publish.sh, to $REMOTE; the base branch is $BASE_BRANCH."
    fi
  fi
  echo
  echo "Files:"
  printf '  %s\n' "${TO_COMMIT[@]}"
  echo
  echo "Message:"
  printf '%s\n\n%s\n' "$MESSAGE" "$COMMIT_BODY" | sed 's/^/  /'
  echo
  echo "Commands (for the user only when they ask for them; never run them):"
  if [ "$LANDING_BRANCH" != "$BRANCH" ]; then
    printf '  git switch -c %q\n' "$LANDING_BRANCH"
  fi
  printf '  git add --'
  printf ' %q' "${TO_COMMIT[@]}"
  printf '\n'
  printf '  git commit --only -m %q -m %q --' "$MESSAGE" "$COMMIT_BODY"
  printf ' %q' "${TO_COMMIT[@]}"
  printf '\n'
  printf '%s\n' "$LANDING_REDS" >"$RUN_DIR/landing-reds"
  exit 0
fi

# The gates ran since condition 2 was checked, and that takes minutes. Re-check
# rather than trusting the rule that gates must not modify the tree.
[ "$(tree_fingerprint)" = "$REVIEWED_FINGERPRINT" ] || \
  refuse 2 "the tree changed while the gates ran — review again before landing"
marks_checked_by_run

# The one branch this script may create. `git switch -c` starts from HEAD and
# leaves the tree and the index alone, so the uncommitted task moves with it; if
# the commit below then fails, a retry finds itself on this branch and stays.
if [ "$LANDING_BRANCH" != "$BRANCH" ]; then
  git switch -c "$LANDING_BRANCH" || {
    echo "could not create $LANDING_BRANCH — nothing was committed" >&2
    exit 1
  }
fi

# `git add` first, because --only alone cannot commit a path git has never seen;
# then --only with the same pathspec, because a bare `git commit` writes the
# WHOLE INDEX. Anything the user had staged beforehand would ride along inside
# the task's commit — including `.review/land.conf` and `.review/REVIEW_POLICY.md`,
# which are filtered out of CHANGED_FILES above and so are never scope-checked.
# The files that define the pipeline's limits are exactly the ones that must not
# be able to change unnoticed in a commit the pipeline made by itself.
git add -- "${TO_COMMIT[@]}" || { echo "staging failed" >&2; exit 1; }
git commit --only -m "$MESSAGE" -m "$COMMIT_BODY" -- "${TO_COMMIT[@]}" || {
  # The add already happened, so the task's files are staged and the commit is
  # not there — a pre-commit hook rejecting the change is the usual cause. This
  # script has no unstage path on purpose (it may commit and nothing else), so
  # say plainly what state the tree is in rather than leaving it to be found.
  echo "commit failed — the task's files are left STAGED, nothing was committed" >&2
  echo "  a pre-commit hook is the usual cause; its output is above" >&2
  echo "  to undo the staging yourself:" >&2
  printf '    git restore --staged --'  >&2
  printf ' %q' "${TO_COMMIT[@]}" >&2
  printf '\n' >&2
  exit 1
}

printf '%s\n' "$LANDING_REDS" >"$RUN_DIR/landing-reds"
echo "landed $TASK_ID on $LANDING_BRANCH: ${#TO_COMMIT[@]} file(s)"

landing_publishes "$LANDING" || exit 0

"$LIB_DIR/publish.sh" --task-file "$TASK_FILE"
PUBLISH_EXIT=$?
if [ "$PUBLISH_EXIT" -ne 0 ]; then
  echo "the commit of $TASK_ID landed on $LANDING_BRANCH, "\
"but publishing did not finish (publish.sh exit $PUBLISH_EXIT)" >&2
  # Off that branch, publish.sh got as far as the base branch: the merge is in, and
  # its own last line says what is left.
  if [ "$(current_branch)" = "$LANDING_BRANCH" ]; then
    echo "  if no code has to change, meet the cause above, "\
"then run publish.sh alone, never land.sh again:" >&2
    printf '    %q --task-file %q\n' "$LIB_DIR/publish.sh" "$TASK_FILE" >&2
    echo "  if code has to change, that is a new pass of the loop on this branch: "\
"the work, review.sh, then land.sh, which adds a commit" >&2
  fi
  exit 4
fi
