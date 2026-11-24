#!/usr/bin/env bash
#
# pr-post.sh — the loop's posts on the pull request of a task, at LANDING=pr and merge;
# its command qa says at every level what a /qa left, and whose turn it is.
#
# Runs FROM THE SUBMODULE and is deliberately NOT overridable, for the reason
# publish.sh is not. It is the only script that writes to the pull request apart from
# its creation and its merge, which are publish.sh's. It has no code path for push,
# commit or merge, and writes no file of the tree: only its records under .review/runs.
# Every gh call names the repository of REMOTE. Every post starts with a hidden marker,
# <!-- loop:<what> -->: gh is logged in as the person, so the marker is how the loop
# and publish.sh tell the loop's posts from what people wrote. It counts only at the
# start of a post: a person's text that quotes it is still the person's. A report of
# /qa over 60 000 characters goes in several comments; any other text over 65 000
# characters is cut, with a line naming the local file that holds it whole.
#
# Commands:
#   run <run-dir>        one review of the run at the commit it reviewed, then the
#                        statuses: in its body the summary — the run of ASK_AFTER_RUNS,
#                        the models, each gate with its result, seconds, summary line and
#                        the end of its output, the end-to-end tests of each platform, the
#                        findings by what became of them, those dropped with why, the
#                        tokens and the cost — and one comment on the line of each verified
#                        finding, with its triage. A finding off the pull request's diff
#                        goes into the body. pr-review.json and pr-comments.json in the run
#                        record it: run again, it finds the review it posted, and posts no
#                        second one. review.sh calls it after every run at these levels.
#   answers <run-dir>    each answer of <run>/answers.json and escalations-answered.json
#                        as a reply to its finding's comment, recorded in
#                        answers-posted.json and never posted twice; then the statuses
#                        and the description
#   reply <comment-id> <answer> <text-file>
#                        the loop's answer to what a person wrote on the pull request — a
#                        comment, a review or a comment on a line, by its id: fixed,
#                        not-a-problem, other-task, unsettled, or user, the user's own
#                        decision in their words. Only fixed and user settle it for the
#                        merge (common.sh, people_comments_open). Never posted twice.
#   comments             reads only: what people wrote that is not settled, whole, with
#                        its id, author and place — the line of a file, a review, or the
#                        pull request; reply answers it in its thread
#   work                 reads only: {work, head, merge_base} — the fingerprint of the
#                        work now, HEAD and the merge base, for /qa to record in qa.json:
#                        a /qa of the whole pull request records the merge base as since
#   qa <qa-dir>          at every level, before anything is asked of the remote: checks
#                        <qa-dir>/qa.json (common.sh, qa_record_fault) and prints what the
#                        /qa left and whose turn each thing is (qa_left) — a failing case
#                        with its words, its test and the loop's next step, what is
#                        unproven or not checked, and what the app does that nothing
#                        written describes, the one question for the user. Below the pull
#                        request levels that is all. At pr and merge: <qa-dir>/report.md
#                        as a comment, once; then the statuses and the description
#   statuses             at HEAD: loop/<gate>, loop/e2e-<platform>, loop/review and
#                        loop/qa, from the newest review run and /qa of the task if they
#                        checked the work as it is now — by the same checks as the merge
#                        (common.sh) — and pending otherwise
#   body [--to <file>]   the description: the task, its exit criteria and scope, its
#                        review runs and /qa runs, and the trailers of the squash; with
#                        --to, into the file only, for publish.sh to open the pull
#                        request with
#
# Usage, from the project root:
#   pr-post.sh <command> [arguments] [--task-file <task.json>]
# The task is the one HEAD's Task-Id trailer names. Its file is --task-file, else the one
# the run, or the newest review run of the task, was made with.
#
# Exit codes:
#   0  posted, or nothing was left to post; qa below the pull request levels, once it
#      has said what /qa left
#   3  refused, with the reason on stderr
#   1  usage or environment error, or gh failed; qa: a qa.json that is missing or does
#      not hold
#
# Requires: jq >= 1.6, git, gh

set -uo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 1
# shellcheck source=common.sh
. "$LIB_DIR/common.sh"

COMMAND=""
ARGUMENTS=()
TASK_FILE=""
TO=""

while [ $# -gt 0 ]; do
  case "$1" in
    --task-file) require_value "--task-file" $#; TASK_FILE="$2"; shift 2 ;;
    --to)        require_value "--to" $#; TO="$2"; shift 2 ;;
    -*) echo "unknown argument: $1" >&2; exit 1 ;;
    *) if [ -z "$COMMAND" ]; then COMMAND="$1"; else ARGUMENTS+=("$1"); fi; shift ;;
  esac
done

usage() {
  echo "usage: pr-post.sh run|answers <run-dir> | reply <comment-id> <answer> <text-file> | "\
"qa <qa-dir> | statuses | comments | work | body [--to <file>] — [--task-file <task.json>]" >&2
  exit 1
}

case "$COMMAND:${#ARGUMENTS[@]}" in
  run:1 | answers:1 | qa:1 | reply:3 | statuses:0 | comments:0 | work:0 | body:0) ;;
  *) usage ;;
esac
[ -z "$TO" ] || [ "$COMMAND" = body ] || usage

# Resolved before the cd below, as land.sh resolves its own arguments.
ARGUMENT=""
case "$COMMAND" in
  run | answers | qa)
    [ -d "${ARGUMENTS[0]}" ] || { echo "no such folder: ${ARGUMENTS[0]}" >&2; exit 1; }
    ARGUMENT="$(abspath "${ARGUMENTS[0]}")" || exit 1 ;;
  reply)
    case "${ARGUMENTS[1]}" in fixed | not-a-problem | other-task | unsettled | user) ;;
      *) echo "the answer is fixed, not-a-problem, other-task, unsettled or user, "\
"not ${ARGUMENTS[1]}" >&2; exit 1 ;; esac
    [ -f "${ARGUMENTS[2]}" ] || { echo "no such file: ${ARGUMENTS[2]}" >&2; exit 1; }
    ARGUMENT="$(abspath "${ARGUMENTS[2]}")" || exit 1 ;;
esac
if [ -n "$TASK_FILE" ]; then
  [ -f "$TASK_FILE" ] || { echo "no such task file: $TASK_FILE" >&2; exit 1; }
  TASK_FILE="$(abspath "$TASK_FILE")" || exit 1
fi
if [ -n "$TO" ]; then
  TO="$(abspath "$TO")" || { echo "no folder for $TO" >&2; exit 1; }
fi

PROJECT_ROOT="$(git rev-parse --show-toplevel)" || exit 1
cd "$PROJECT_ROOT" || exit 1

CONFIG=".review/land.conf"

# Each takes <reason> [<whose> <what>]: with the last two, the last line says whose turn
# it is (turn, common.sh).
refuse() {
  echo "POSTING REFUSED — $1" >&2
  [ $# -lt 3 ] || turn "$2" "$3"
  exit 3
}
fail() {
  echo "POSTING FAILED — $1" >&2
  [ $# -lt 3 ] || turn "$2" "$3"
  exit 1
}

SCRATCH="$(mktemp -d)" || exit 1
trap 'rm -rf "$SCRATCH"' EXIT

# ---------------------------------------------------------------------------
# The pull request and the task.
# ---------------------------------------------------------------------------

# The config is read as data, never sourced, as in land.sh.
LANDING="$(landing_level "$CONFIG")" || refuse "$LANDING"

# What /qa left is said at every level, and first: it needs neither the remote nor gh.
if [ "$COMMAND" = qa ]; then
  [ -f "$ARGUMENT/qa.json" ] || fail "$ARGUMENT has no qa.json — /qa writes it (section 4)"
  FAULT="$(qa_record_fault "$ARGUMENT/qa.json")"
  [ -z "$FAULT" ] || fail "$ARGUMENT/qa.json does not hold: $FAULT"
  qa_left "$(jq -r '.task' "$ARGUMENT/qa.json")" "$ARGUMENT" || \
    fail "the records of /qa could not be read"
  if ! landing_opens_pull_request "$LANDING"; then
    echo "LANDING=$LANDING opens no pull request: the report stays in $ARGUMENT/report.md"
    exit 0
  fi
fi
landing_opens_pull_request "$LANDING" || \
  refuse "LANDING=$LANDING in $CONFIG opens no pull request — only pr and merge do"
REMOTE="$(resolve_remote "$CONFIG")" || refuse "$REMOTE"
BASE="$(resolve_base_branch "$CONFIG" "$REMOTE")" || refuse "$BASE"
REPOSITORY="$(remote_repository "$REMOTE")" || refuse "the remote $REMOTE has no URL"
BRANCH="$(current_branch)"
[ -n "$BRANCH" ] || refuse "HEAD is detached — there is no pull request of it"
HEAD_COMMIT="$(git rev-parse HEAD)"

# The task is the one land.sh committed HEAD for, as publish.sh reads it.
TASK_ID="$(task_id_of "$(git rev-list -1 --no-merges --first-parent HEAD)")"
[ -n "$TASK_ID" ] || \
  refuse "HEAD carries no Task-Id trailer — land.sh has committed no task on $BRANCH"

if [ "$COMMAND" != reply ] && [ "$COMMAND" != comments ] && [ "$COMMAND" != work ]; then
  if [ -z "$TASK_FILE" ]; then
    case "$COMMAND" in
      run | answers) TASK_FILE="$(jq -r '.task_file // ""' "$ARGUMENT/meta.json" 2>/dev/null)" ;;
    esac
  fi
  if [ -z "$TASK_FILE" ]; then
    NEWEST_RUN="$(review_runs_of "$TASK_ID" | tail -1)"
    [ -z "$NEWEST_RUN" ] || TASK_FILE="$(jq -r '.task_file // ""' "$NEWEST_RUN/meta.json")"
  fi
  [ -n "$TASK_FILE" ] && [ -f "$TASK_FILE" ] || \
    refuse "no task file of $TASK_ID is known yet — name it with --task-file"
  [ "$(jq -r '.id' "$TASK_FILE")" = "$TASK_ID" ] || \
    refuse "$TASK_FILE is not the task HEAD was committed for, $TASK_ID"
fi

PR_URL=""
PR_NUMBER=""
if [ -z "$TO" ]; then
  OPEN="$(pull_request_of "$REPOSITORY" "$BRANCH" "$BASE")" || \
    fail "gh could not say whether $BRANCH has a pull request into $BASE"
  PR_URL="$(printf '%s' "$OPEN" | jq -r '.url // ""')"
  PR_NUMBER="$(printf '%s' "$OPEN" | jq -r '.number // ""')"
  [ -n "$PR_URL" ] || refuse "$BRANCH has no open pull request into $BASE — publish.sh opens it"
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# A JSON file as compact JSON, or the fallback when it is not there or not JSON: the
# summary says what a run has, and a run that ended early has less.
json_or() {
  jq -sc 'if length == 1 then .[0] else error("not one value") end' "$1" 2>/dev/null \
    || printf '%s' "$2"
}

# GitHub takes up to 65 536 characters in a body.
JQ_CUT='def cut($source):
  if length > 65000
  then .[0:64000] + "\n\n…\n\nCut here; the whole text is in \($source)."
  else . end;
'

# A finding and its triage, as a comment says it.
JQ_FINDING='def finding_text($verdict):
  "**\(.id)** \(.severity) \(.category), \(.confidence)"
    + (if (.rule_violated // "") != "" then " — rule: \(.rule_violated)" else "" end),
  "",
  (.evidence | if type == "string" then . else tojson end | split("\n") | map("> " + .)
   | join("\n")),
  "",
  (if $verdict == null then "Triage: none — the run ended before it."
   else "Triage: **\($verdict.verdict)**, \($verdict.severity), by \($verdict.decision_rule)"
        + (if ($verdict.policy_rule // "") != "" then " (\($verdict.policy_rule))" else "" end)
        + ": \($verdict.reason)" end);
'

api_post() {
  gh_repo_api "$REPOSITORY" "$1" --method POST --input "$2"
}

# A comment on the pull request itself, its marker first; prints its id.
post_comment() {
  local marker="$1" text_file="$2" source="$3"
  jq -n --arg marker "$marker" --rawfile text "$text_file" --arg source "$source" "$JQ_CUT"'
    {body: ("<!-- loop:\($marker) -->\n" + $text | cut($source))}' >"$SCRATCH/comment.json"
  api_post "issues/$PR_NUMBER/comments" "$SCRATCH/comment.json" | jq -r '.id'
}

# A reply in the thread of a comment on a line; prints its id.
post_reply() {
  local comment_id="$1" marker="$2" text_file="$3" source="$4"
  jq -n --arg marker "$marker" --rawfile text "$text_file" --arg source "$source" "$JQ_CUT"'
    {body: ("<!-- loop:\($marker) -->\n" + $text | cut($source))}' >"$SCRATCH/reply.json"
  api_post "pulls/$PR_NUMBER/comments/$comment_id/replies" "$SCRATCH/reply.json" | jq -r '.id'
}

post_status() {
  jq -n --arg context "$2" --arg state "$3" --arg description "$4" \
    '{context: $context, state: $state, description: ($description | .[0:140])}' \
    >"$SCRATCH/status.json"
  api_post "statuses/$1" "$SCRATCH/status.json" >/dev/null
}

# Why a check of common.sh refuses, or nothing when it holds. The check runs in a
# subshell whose refuse prints the reason and ends it; a check that dies any other way
# has not held either.
why_not() {
  local reason status
  reason="$( ( refuse() { printf '%s' "$2"; exit 3; }; "$@" ) 2>/dev/null )"
  status=$?
  case "$status" in
    0) ;;
    3) printf '%s' "$reason" ;;
    *) printf 'could not be checked (exit %s)' "$status" ;;
  esac
}

# What a review run came to, in a few words.
run_result() {
  local run="$1"
  if [ ! -f "$run/gates.json" ]; then
    echo "did not finish"
  elif jq -e 'any(.[]; .status == "fail" and .blocking != false)' "$run/gates.json" \
       >/dev/null 2>&1; then
    echo "gates red"
  elif [ ! -f "$run/e2e.json" ]; then
    echo "did not finish"
  elif ! jq -e '.status == "pass"' "$run/e2e.json" >/dev/null 2>&1; then
    case "$(jq -r '.status' "$run/e2e.json" 2>/dev/null)" in
      red) echo "end-to-end tests red" ;;
      *) echo "no end-to-end harness" ;;
    esac
  elif [ ! -f "$run/approved.json" ] || [ ! -f "$run/escalated.json" ]; then
    if [ -f "$run/findings.json" ] && [ "$(jq '.findings | length' "$run/findings.json")" -eq 0 ]
    then echo "unusable: no finding located"; else echo "did not finish"; fi
  else
    jq -rn --slurpfile approved "$run/approved.json" --slurpfile escalated "$run/escalated.json" '
      ($approved[0] | length) as $a | ($escalated[0] | length) as $e
      | if $a + $e == 0 then "clean"
        else [if $a > 0 then "\($a) accepted" else empty end,
              if $e > 0 then "\($e) escalated" else empty end] | join(", ") end'
  fi
}

# ---------------------------------------------------------------------------
# statuses
# ---------------------------------------------------------------------------

# At HEAD, for people to see; publish.sh merges by the same checks, made again. The
# newest review run made on this pull request and the newest /qa count only if they
# checked the work as it is now, so a commit of the loop's files alone keeps them, and
# new work shows pending. A run of --dry-run, or of another level, is no review here.
post_statuses() {
  local fingerprint merge_base run reason state text platform result
  git fetch -q "$REMOTE" "+refs/heads/$BASE:refs/remotes/$REMOTE/$BASE" || \
    fail "could not read $BASE from $REMOTE; git says why above"
  merge_base="$(git merge-base "refs/remotes/$REMOTE/$BASE" HEAD)" || \
    fail "HEAD has no commit in common with $BASE of $REMOTE"
  fingerprint="$(tree_fingerprint)"
  run="$(review_runs_on "$TASK_ID" "$PR_URL" | tail -1)"
  if [ -n "$run" ] && \
     { [ "$(jq -r '.tree_fingerprint // ""' "$run/meta.json")" != "$fingerprint" ] || \
       [ "$(jq -r '.merge_base // ""' "$run/meta.json")" != "$merge_base" ]; }; then
    run=""
  fi

  # A failed gate that does not block is no failure of the change.
  if [ -n "$run" ] && [ -f "$run/gates.json" ]; then
    jq -r 'to_entries[] | [.key, .value.status, (.value.blocking != false | tostring),
                           (.value.summary // "")] | @tsv' "$run/gates.json" \
      | while IFS=$'\t' read -r gate result blocking text; do
          case "$result:$blocking" in
            pass:*)     post_status "$HEAD_COMMIT" "loop/$gate" success "pass${text:+ — $text}" ;;
            fail:false) post_status "$HEAD_COMMIT" "loop/$gate" success \
                          "fail (not blocking)${text:+ — $text}" ;;
            *)          post_status "$HEAD_COMMIT" "loop/$gate" failure \
                          "$result${text:+ — $text}" ;;
          esac || exit 1
        done || return 1
  fi

  if [ -n "$run" ] && [ -f "$run/e2e.json" ]; then
    for platform in $(platforms); do
      result="$(jq -r --arg platform "$platform" '
        .results[$platform] as $tests
        | if $tests == null then "failure\tdid not run"
          else (if .status == "pass" then "success" else "failure" end) + "\t"
               + "\($tests.passed | length) of "
               + "\($tests.passed + $tests.failed + $tests.skipped | length) passed"
               + (if .status == "pass" then ""
                  else " — " + ([.reasons[]? | select(startswith($platform + ": ")
                                                      or (test("^[a-z]+: ") | not))][0]
                                 // .status) end) end' "$run/e2e.json")" || return 1
      post_status "$HEAD_COMMIT" "loop/e2e-$platform" "${result%%$'\t'*}" "${result#*$'\t'}" \
        || return 1
    done
  fi

  # loop/review: M1 to M4 of the merge.
  if [ -z "$run" ]; then
    state=pending; text="not checked by the loop yet"
  elif [ "$(run_result "$run")" = "gates red" ] || \
       [ "$(run_result "$run")" = "end-to-end tests red" ] || \
       [ "$(run_result "$run")" = "no end-to-end harness" ]; then
    state=failure; text="checks were red: $(run_result "$run")"
  else
    reason="$(why_not run_is_complete "$run")"
    [ -n "$reason" ] || \
      reason="$(why_not run_reviewed_this_tree "$run" "$TASK_FILE" "$fingerprint")"
    [ -n "$reason" ] || reason="$(why_not run_e2e_passed "$run" "$fingerprint")"
    [ -n "$reason" ] || reason="$(why_not run_has_no_findings "$run")"
    if [ -n "$reason" ]; then
      state=failure; text="$reason"
    else
      reason="$(why_not run_escalations_answered "$run")"
      if ! jq -e --arg url "$PR_URL" '.pr_url == $url' "$run/pr-review.json" >/dev/null 2>&1
      then
        reason="the review of $(basename "$run") is not posted on the pull request yet"
      fi
      if [ -n "$reason" ]; then
        state=pending; text="$reason"
      else
        state=success
        text="reviewed: nothing outstanding at $(jq -r '.threshold // "major"' "$run/meta.json")+"
      fi
    fi
  fi
  post_status "$HEAD_COMMIT" loop/review "$state" "$text" || return 1

  # loop/qa: the /qa part of M5. Pending until /qa checked this work and, once, the whole
  # pull request, and while what it left unproven or unchecked waits for the user; failing
  # while a failure it found is neither seen red then green nor answered, or a test is
  # still skipped for the task.
  reason="$(why_not qa_checked_this_work "$TASK_ID" "$fingerprint" "$merge_base")"
  [ -n "$reason" ] || reason="$(why_not qa_left_nothing_open "$TASK_ID" "$merge_base")"
  [ -n "$reason" ] || reason="$(why_not qa_reports_posted "$TASK_ID" "$merge_base" "$PR_URL")"
  if [ -n "$reason" ]; then
    state=pending; text="$reason"
  else
    reason="$(why_not qa_failures_proven "${run:-.review/runs/no-review-of-this-work}" \
      "$TASK_ID")"
    if [ -n "$reason" ]; then
      state=failure; text="$reason"
    else
      state=success
      text="$(qa_records_of "$TASK_ID" | jq -r 'last
        | "\(.extent): \(.counts.pass) passed, \(.failures | length) failure(s) proven or "
          + "answered, \(.counts.unproven) unproven, \(.counts.not_checked) not checked"')"
    fi
  fi
  post_status "$HEAD_COMMIT" loop/qa "$state" "$text" || return 1
  echo "statuses posted at $HEAD_COMMIT: $PR_URL"
}

# ---------------------------------------------------------------------------
# body
# ---------------------------------------------------------------------------

write_body() {
  local runs qa_records qa_asks
  runs="$( { if [ -n "$PR_URL" ]; then review_runs_on "$TASK_ID" "$PR_URL"
             else review_runs_of "$TASK_ID"; fi; } | while IFS= read -r run; do
      jq -c --arg run "$(basename "$run")" --arg result "$(run_result "$run")" \
        --argjson findings "$(json_or "$run/findings.json" '{"findings": []}')" \
        --argjson verdicts "$(json_or "$run/verdicts.json" '{"verdicts": []}')" '
        {run: $run, head: (.head // ""), result: $result,
         verified: ($findings.findings | length),
         accepted: ([$verdicts.verdicts[] | select(.verdict == "accept")] | length),
         escalated: ([$verdicts.verdicts[] | select(.verdict == "escalate")] | length),
         rejected: ([$verdicts.verdicts[] | select(.verdict == "reject")] | length)}' \
        "$run/meta.json"
    done | jq -sc .)" || return 1
  qa_records="$(qa_records_of "$TASK_ID")" || \
    fail "a qa.json of $TASK_ID is unreadable or not {task, failures: [{case: TC-nnn}]}, or its "\
"items do not hold; the line before this one says what"
  qa_asks="$(qa_questions "$TASK_ID")" || return 1
  squash_trailers "$TASK_FILE" "$PR_URL" >"$SCRATCH/trailers" || return 1
  jq -nr --slurpfile task "$TASK_FILE" --argjson runs "$runs" --argjson qa "$qa_records" \
         --argjson asks "$qa_asks" --arg asked "$(turn_words user:what-should-be)" \
         --rawfile trailers "$SCRATCH/trailers" '
    def short: if . == "" then "—" else "`\(.[0:7])`" end;
    $task[0] as $task
    | "<!-- loop:body -->",
      "## \($task.id): \($task.title // "")",
      "",
      "### Exit criteria",
      (if ($task.exit_criteria // []) == [] then "None."
       else ($task.exit_criteria[] | if (.verified_by // "") != ""
             then "- [x] \(.text) — \(.verified_by)" else "- [ ] \(.text)" end) end),
      "",
      "### Scope",
      ([$task.scope[]? | "`\(.)`"] | join(", ")),
      "",
      "### Review runs",
      (if $runs == [] then "None yet."
       else "| Run | Head | Result | Verified | Accepted | Escalated | Rejected |",
            "|---|---|---|---|---|---|---|",
            ($runs[] | "| \(.run) | \(.head | short) | \(.result) | \(.verified) "
                       + "| \(.accepted) | \(.escalated) | \(.rejected) |") end),
      "",
      "### /qa runs",
      (if $qa == [] then "None yet."
       else "| Run | Head | Extent | Failures |",
            "|---|---|---|---|",
            ($qa[] | "| \(.run | split("/") | last) | \((.head // "") | short) "
                     + "| \(.extent // "—") | \(.failures | length) |") end),
      (if $asks == [] then empty
       else "", ($asks[] | "- \($asked): \(.what) (\(.where))" | gsub("\\s+"; " ")) end),
      "",
      ($trailers | rtrimstr("\n"))'
}

post_body() {
  write_body >"$SCRATCH/body.md" || fail "the description of $TASK_ID could not be written"
  jq -Rsr --arg source "pr-post.sh body --to <file>" "$JQ_CUT"'cut($source)' \
    <"$SCRATCH/body.md" >"$SCRATCH/body.cut.md"
  if [ -n "$TO" ]; then
    cp "$SCRATCH/body.cut.md" "$TO" || fail "could not write $TO"
    return 0
  fi
  gh pr edit "$PR_URL" --repo "$REPOSITORY" --body-file "$SCRATCH/body.cut.md" >/dev/null || \
    fail "gh could not write the description of $PR_URL"
  echo "description written: $PR_URL"
}

# ---------------------------------------------------------------------------
# run
# ---------------------------------------------------------------------------

# Whether a line of a file is on the pull request's diff, where GitHub takes a comment:
# inside a hunk of the new side, three lines of context included.
# The whole diff, with renames found as GitHub finds them: a renamed file has its real
# hunks, not every line as added.
on_diff() {
  local file="$1" line="$2" merge_base="$3" head="$4"
  git -c core.quotePath=false diff -U3 -M --no-color "$merge_base" "$head" 2>/dev/null \
    | awk -v file="$file" -v line="$line" '
    /^diff --git / { current = 0; next }
    /^\+\+\+ / { name = substr($0, 5); sub(/\t$/, "", name); current = (name == "b/" file); next }
    current && /^@@ / { split($3, plus, ","); start = substr(plus[1], 2) + 0
                        count = (plus[2] == "" ? 1 : plus[2] + 0)
                        if (line >= start && line < start + count) found = 1 }
    END { exit !found }'
}

# The summary of a run, the body of its review; with the findings named in $2 (a JSON
# array of ids), each in full: those off the diff, or all of them after a 422.
review_summary() {
  local run="$1" in_body="$2" usage
  usage="$(for role in reviewer maintainer; do
      jq -c --arg role "$role" 'select(type == "object" and (has("usage") or has("total_cost_usd")))
        | {role: $role, cost: .total_cost_usd,
        tokens: ((.usage // {}) | [.input_tokens, .output_tokens, .cache_creation_input_tokens,
                                   .cache_read_input_tokens] | map(. // 0) | add)}' \
        "$run/$role.cli.json" 2>/dev/null
    done | jq -sc .)"
  jq -nr --arg run "$(basename "$run")" --arg ask "$(read_conf "$CONFIG" ASK_AFTER_RUNS 5)" \
    --arg result "$(run_result "$run")" --argjson in_body "$in_body" --argjson usage "$usage" \
    --argjson meta "$(json_or "$run/meta.json" '{}')" \
    --argjson gates "$(json_or "$run/gates.json" 'null')" \
    --argjson e2e "$(json_or "$run/e2e.json" 'null')" \
    --argjson raw "$(json_or "$run/findings.raw.json" '{"findings": []}')" \
    --argjson findings "$(json_or "$run/findings.json" '{"findings": []}')" \
    --argjson verdicts "$(json_or "$run/verdicts.json" '{"verdicts": []}')" \
    --argjson approved "$(json_or "$run/approved.json" '[]')" \
    --argjson optional "$(json_or "$run/optional.json" '[]')" \
    --argjson escalated "$(json_or "$run/escalated.json" '[]')" \
    "$JQ_FINDING"'
    def findings_of: if type == "object" and (.findings | type) == "array"
                     then [.findings[] | objects] else [] end;
    ($raw | findings_of) as $raw_findings | ($findings | findings_of) as $kept_findings
    | ($raw | .findings = $raw_findings) as $raw | ($findings | .findings = $kept_findings) as $findings
    | "<!-- loop:review \($run) -->",
    "**The loop'"'"'s review**, run `\($run)` of \($meta.task // "no task") at "
      + "`\(($meta.head // "")[0:7])`: \($result). "
      + (if $meta.past_limit == true then "A run past the limit (--past-limit)."
         elif $meta.count != null then "Run \($meta.count) of \($ask) (ASK_AFTER_RUNS)."
         else "" end),
    "",
    "Models: \($meta.models // "not recorded").",
    "",
    (if $gates == null then "The gates did not run."
     else "| Gate | Result | Seconds | Summary |", "|---|---|---|---|",
          ($gates | to_entries[] | "| \(.key) | \(.value.status)"
             + (if .value.status == "fail" and .value.blocking == false then " (not blocking)"
                else "" end)
             + " | \(.value.seconds // "—") | \(.value.summary // "") |"),
          "", "<details><summary>What each gate printed, its end</summary>", "",
          ($gates | to_entries[] | "**\(.key)**: `\(.value.command // "")`", "", "````",
             ((.value.output // "") | rtrimstr("\n")), "````", ""),
          "</details>" end),
    "",
    (if $e2e == null then "The end-to-end tests did not run."
     else "| End-to-end | Passed | Of |", "|---|---|---|",
          ($e2e.results | to_entries[] | "| \(.key) | \(.value.passed | length) "
             + "| \(.value.passed + .value.failed + .value.skipped | length) |"),
          (if $e2e.status != "pass" then "", ($e2e.reasons[]? | "- \(.)") else empty end) end),
    "",
    "Findings: \($raw.findings | length) reported, "
      + "\(($raw.findings | length) - ($findings.findings | length)) dropped, "
      + "\($findings.findings | length) verified; \($approved | length) accepted at "
      + "\($meta.threshold // "major")+, \($optional | length) below, "
      + "\([$verdicts.verdicts[] | select(.verdict == "reject")] | length) rejected, "
      + "\($escalated | length) escalated.",
    ([$findings.findings[].id] as $kept
     | [$raw.findings[] | select(.id as $id | $kept | index($id) == null)] as $dropped
     | if $dropped == [] then empty
       else "", "<details><summary>Dropped: the file, or the quote in it, was not found"
                + "</summary>", "",
            ($dropped[] | "- `\(.file):\(.line)` **\(.id)** \(.severity // "") "
               + "\(.category // "") — \((.evidence // "") | if type == "string" then .
                                                                else tojson end | split("\n")[0])"),
            "", "</details>" end),
    "",
    (if $usage == [] then "Tokens and cost: not recorded."
     else "Tokens: \([$usage[].tokens] | add)"
          + " (\([$usage[] | "\(.role) \(.tokens)"] | join(", "))); cost: "
          + (if any($usage[]; .cost == null) then "not recorded"
             else "$\([$usage[].cost] | add * 100 | round / 100)" end) + "." end),
    (if $in_body == [] then empty
     else "", "### Findings off the diff",
          ($findings.findings[] | select(.id as $id | $in_body | index($id) != null)
           | . as $finding
           | "", "`\(.file):\(.line)`",
             ($finding | finding_text([$verdicts.verdicts[]
                                       | select(.finding_id == $finding.id)][0]))) end)'
}

# The ids of the comments the review of a run made, by the marker of each finding, into
# pr-comments.json; read only when some are missing there.
read_comment_ids() {
  local run="$1" review_id="$2" name wanted have
  name="$(basename "$run")"
  wanted="$(jq -c '[.findings[].id] - (input.in_body // [])' "$run/findings.json" \
    "$run/pr-review.json" 2>/dev/null || echo '[]')"
  have="$(json_or "$run/pr-comments.json" '{}')"
  if printf '%s' "$have" | jq -e --argjson wanted "$wanted" '($wanted - keys) == []' >/dev/null
  then
    return 0
  fi
  gh_repo_api_list "$REPOSITORY" "pulls/$PR_NUMBER/reviews/$review_id/comments" \
    | jq --arg name "$name" '
      [.[] | (.body // "") as $body
       | ($body | capture("<!-- loop:finding (?<run>[^ ]+) (?<id>F-[0-9]+) -->")?) as $marker
       | select($marker != null and $marker.run == $name) | {key: $marker.id, value: .id}]
      | from_entries' >"$SCRATCH/comments.json" || \
    fail "gh could not read the comments of the review of $name on $PR_URL"
  mv "$SCRATCH/comments.json" "$run/pr-comments.json"
}

post_run() {
  local run="$1" name head merge_base pr_url findings verdicts inline in_body review_id
  name="$(basename "$run")"
  [ -f "$run/meta.json" ] || refuse "$run has no meta.json — this is not a review run"
  pr_url="$(jq -r '.pr_url // ""' "$run/meta.json")"
  [ -n "$pr_url" ] || \
    refuse "$name was not made on a pull request — review.sh --dry-run, or another level"
  [ "$pr_url" = "$PR_URL" ] || refuse "$name was made on $pr_url, not on the open $PR_URL"
  [ "$(jq -r '.task // ""' "$run/meta.json")" = "$TASK_ID" ] || \
    refuse "$name is not a run of $TASK_ID"

  if [ -f "$run/pr-review.json" ]; then
    review_id="$(jq -r '.id' "$run/pr-review.json")"
    echo "the review of $name is on $PR_URL already: no second one"
  else
    # A review GitHub took, whose record was not written — gh failed after the post, or
    # this script stopped — is found by its marker, not posted twice.
    review_id="$(gh_repo_api_list "$REPOSITORY" "pulls/$PR_NUMBER/reviews" \
      | jq -r --arg marker "<!-- loop:review $name -->" \
        'first(.[] | select((.body // "") | startswith($marker)) | .id) // empty')" || \
      fail "gh could not read the reviews of $PR_URL"
    head="$(jq -r '.head' "$run/meta.json")"
    if [ -n "$review_id" ]; then
      echo "the review of $name is on $PR_URL already, unrecorded: recorded now"
      in_body="null"
    else
      merge_base="$(jq -r '.merge_base' "$run/meta.json")"
      findings="$(json_or "$run/findings.json" '{"findings": []}')"
      verdicts="$(json_or "$run/verdicts.json" '{"verdicts": []}')"
      inline="[]"
      in_body="[]"
      while IFS=$'\t' read -r id file line; do
        [ -n "$id" ] || continue
        if on_diff "$file" "$line" "$merge_base" "$head"; then
          inline="$(printf '%s' "$inline" | jq -c --arg id "$id" '. + [$id]')"
        else
          in_body="$(printf '%s' "$in_body" | jq -c --arg id "$id" '. + [$id]')"
        fi
      done < <(printf '%s' "$findings" | jq -r '.findings[] | [.id, .file, .line] | @tsv')

      # Posted again with every finding in the body when GitHub takes none of the comments
      # (422): a line it does not count as on the diff.
      for attempt in comments body; do
        if [ "$attempt" = body ]; then
          in_body="$(printf '%s' "$findings" | jq -c '[.findings[].id]')"
          inline="[]"
        fi
        review_summary "$run" "$in_body" >"$run/pr-review.md" || \
          fail "the summary of $name could not be written"
        jq -n --arg head "$head" --rawfile summary "$run/pr-review.md" --arg run "$name" \
          --argjson findings "$findings" --argjson verdicts "$verdicts" \
          --argjson inline "$inline" --arg source "$run/pr-review.md" "$JQ_CUT$JQ_FINDING"'
          {commit_id: $head, event: "COMMENT", body: ($summary | cut($source)),
           comments: [$findings.findings[] | select(.id as $id | $inline | index($id) != null)
                      | . as $finding
                      | {path: .file, line: .line, side: "RIGHT",
                         body: (["<!-- loop:finding \($run) \(.id) -->",
                                 finding_text([$verdicts.verdicts[]
                                               | select(.finding_id == $finding.id)][0])]
                                | join("\n"))}]}' >"$SCRATCH/review.json" || \
          fail "the review of $name could not be put together"
        if api_post "pulls/$PR_NUMBER/reviews" "$SCRATCH/review.json" >"$SCRATCH/posted.json" \
             2>"$SCRATCH/posted.err"; then
          break
        fi
        cat "$SCRATCH/posted.err" >&2
        if [ "$attempt" = body ] || ! grep -q 'HTTP 422' "$SCRATCH/posted.err"; then
          fail "gh could not post the review of $name on $PR_URL — pr-post.sh run $run again "\
"finds it if GitHub took it"
        fi
        echo "GitHub took no comment on a line (422): posting the review with every finding "\
"in its body" >&2
      done
      review_id="$(jq -r '.id' "$SCRATCH/posted.json")"
      echo "review of $name posted: $PR_URL"
    fi
    # Written at once: whatever fails after this, a rerun posts no second review.
    jq -n --argjson id "$review_id" --arg url "$PR_URL" --arg head "$head" \
      --argjson in_body "$in_body" \
      '{id: $id, pr_url: $url, commit_id: $head} + (if $in_body == null then {}
                                                    else {in_body: $in_body} end)' \
      >"$run/pr-review.json"
  fi
  read_comment_ids "$run" "$review_id"
  post_statuses || fail "the statuses could not be posted on $PR_URL"
}

# ---------------------------------------------------------------------------
# answers
# ---------------------------------------------------------------------------

post_answers() {
  local run="$1" name answers posted head key id kind text comment_id loose=""
  name="$(basename "$run")"
  jq -e --arg url "$PR_URL" '.pr_url == $url' "$run/pr-review.json" >/dev/null 2>&1 || \
    refuse "the review of $name is not on $PR_URL — pr-post.sh run $run posts it first, if "\
"it was made on this pull request"
  head="$HEAD_COMMIT"
  # The four answers of EXECUTION_GUIDE.md, "A review's findings", and the answers to
  # escalations; a file that is there must be read whole.
  answers="$( { if [ -f "$run/answers.json" ]; then
                  jq -c '.[] | {finding_id, kind: "answer", answer, text: (.text // ""),
                                commit: (.commit // "")}' "$run/answers.json" || echo FAILED
                fi
                if [ -f "$run/escalations-answered.json" ]; then
                  jq -c '.[] | select((.resolution // "") != "")
                         | {finding_id, kind: "escalation", answer: .resolution,
                            text: (.note // ""), by: (.by // "")}' \
                    "$run/escalations-answered.json" || echo FAILED
                fi; } )"
  case "$answers" in *FAILED*) fail "the answers of $name are not readable" ;; esac
  printf '%s\n' "$answers" | jq -se 'all(.[]; (.finding_id | type) == "string"
    and (.kind == "escalation" or (.answer as $answer
      | ["fixed", "not-a-problem", "other-task", "unsettled"] | index($answer)) != null))' \
    >/dev/null || \
    fail "$run/answers.json holds an answer that is not fixed, not-a-problem, other-task or "\
"unsettled, or one with no finding_id"
  [ -f "$run/answers-posted.json" ] || printf '[]' >"$run/answers-posted.json"

  while IFS= read -r answer; do
    [ -n "$answer" ] || continue
    id="$(printf '%s' "$answer" | jq -r '.finding_id')"
    kind="$(printf '%s' "$answer" | jq -r '.kind')"
    jq -e --arg id "$id" --arg kind "$kind" \
      'any(.[]; .finding_id == $id and .kind == $kind)' "$run/answers-posted.json" >/dev/null \
      && continue
    # A fix without its commit was made in HEAD.
    answer="$(printf '%s' "$answer" | jq -c --arg head "$head" '
      if .answer == "fixed" and (.commit // "") == "" and .kind == "answer"
      then .commit = $head else . end')"
    printf '%s' "$answer" | jq -r '
      "**\(.answer)**"
      + (if (.commit // "") != "" then " in `\(.commit[0:7])`" else "" end)
      + (if (.by // "") != "" then ", by \(.by)" else "" end)
      + (if .text != "" then " — \(.text)" else "" end)' >"$SCRATCH/answer.md"
    comment_id="$(jq -r --arg id "$id" '.[$id] // empty' "$run/pr-comments.json" 2>/dev/null)"
    if [ -n "$comment_id" ]; then
      comment_id="$(post_reply "$comment_id" "answer $name $id" "$SCRATCH/answer.md" \
        "$run/answers.json")" || fail "gh could not post the answer to $id on $PR_URL"
    else
      # Those with no comment of their own — off the diff, or a /qa failure answered —
      # go together into one comment, posted after the loop.
      loose="$loose$(printf '%s' "$answer" | jq -c --arg text "$(cat "$SCRATCH/answer.md")" \
        '. + {shown: $text}')"$'\n'
      continue
    fi
    jq --argjson answer "$answer" --arg comment "$comment_id" \
      '. + [$answer + {comment_id: $comment}]' "$run/answers-posted.json" \
      >"$SCRATCH/posted.json" && mv "$SCRATCH/posted.json" "$run/answers-posted.json"
  done <<<"$answers"

  if [ -n "$loose" ]; then
    printf '%s' "$loose" | jq -sr '.[] | "**\(.finding_id)**: \(.shown)\n"' \
      >"$SCRATCH/answers.md"
    comment_id="$(post_comment "answers $name" "$SCRATCH/answers.md" "$run/answers.json")" || \
      fail "gh could not post the answers of $name on $PR_URL"
    printf '%s' "$loose" | jq -s --slurpfile posted "$run/answers-posted.json" \
      --arg comment "$comment_id" '$posted[0] + map(del(.shown) + {comment_id: $comment})' \
      >"$SCRATCH/posted.json" && mv "$SCRATCH/posted.json" "$run/answers-posted.json"
  fi
  echo "answers of $name posted: $PR_URL"
}

# ---------------------------------------------------------------------------
# reply, qa
# ---------------------------------------------------------------------------

# In the thread of a comment on a line, or else on the pull request. GitHub takes a reply
# only to the first comment of a thread, so a person's comment inside a thread is answered
# in it, at its root. The marker names the comment answered, by the id given, which
# publish.sh matches with the id or the node id of what the person wrote, and the answer.
post_person_reply() {
  local comment_id="$1" answer="$2" text_file="$3" lines thread marker
  marker="reply $comment_id $answer"
  lines="$(gh_repo_api_list "$REPOSITORY" "pulls/$PR_NUMBER/comments")" || \
    fail "gh could not read the comments of $PR_URL"
  if printf '%s' "$lines" | jq -e --arg marker "<!-- loop:$marker -->" \
       'any(.[]; (.body // "") | startswith($marker))' >/dev/null; then
    echo "the reply to $comment_id ($answer) is on $PR_URL already: no second one"
    return 0
  fi
  thread="$(printf '%s' "$lines" | jq -r --arg id "$comment_id" \
    'first(.[] | select((.id | tostring) == $id or .node_id == $id)
           | (.in_reply_to_id // .id)) // empty')"
  if [ -n "$thread" ]; then
    post_reply "$thread" "$marker" "$text_file" "$text_file" >/dev/null || \
      fail "gh could not post the reply to $comment_id on $PR_URL"
  else
    gh_repo_api_list "$REPOSITORY" "issues/$PR_NUMBER/comments" \
      | jq -e --arg marker "<!-- loop:$marker -->" \
          'any(.[]; (.body // "") | startswith($marker))' >/dev/null && {
      echo "the reply to $comment_id ($answer) is on $PR_URL already: no second one"
      return 0
    }
    post_comment "$marker" "$text_file" "$text_file" >/dev/null || \
      fail "gh could not post the reply to $comment_id on $PR_URL"
  fi
  echo "reply to $comment_id ($answer) posted: $PR_URL"
}

# What people wrote that is not settled, whole, for the loop to read before it answers.
show_comments() {
  local open
  open="$(people_comments_open "$REPOSITORY" "$PR_NUMBER")" || \
    fail "gh could not read the comments of $PR_URL"
  printf '%s' "$open" | jq -r --arg url "$PR_URL" '
    if length == 0 then "nothing people wrote on \($url) waits for the loop"
    else .[] | "── \(.id) by \(.author) on \(.where), \(.at)"
                + (if .answered == null then "" else " — answered \(.answered); the user decides"
                   end),
               .text, "" end'
}

post_qa() {
  local qa_dir="$1" comment_id
  [ -f "$qa_dir/report.md" ] || refuse "$qa_dir has no report.md — /qa writes it (step 4)"
  if jq -e --arg url "$PR_URL" '.pr_url == $url' "$qa_dir/pr-comment.json" >/dev/null 2>&1; then
    echo "the report of $(basename "$qa_dir") is on $PR_URL already: no second one"
    return 0
  fi
  # Whole, in as many comments as it takes, parts after the first marked as such: the
  # report stays on the pull request when the folder of the run is gone.
  local parts count part ids="[]"
  parts="$(jq -Rsc '[range(0; length; 60000) as $at | .[$at:$at + 60000]]' "$qa_dir/report.md")"
  count="$(printf '%s' "$parts" | jq 'length')"
  for part in $(seq 0 $((count - 1))); do
    printf '%s' "$parts" | jq -r --argjson part "$part" --argjson count "$count" '
      (if $count > 1 then "*Part \($part + 1) of \($count).*\n\n" else "" end) + .[$part]' \
      >"$SCRATCH/part.md"
    comment_id="$(post_comment "qa $(basename "$qa_dir")$([ "$part" -eq 0 ] || echo " part $((part + 1))")" \
      "$SCRATCH/part.md" "$qa_dir/report.md")" || \
      fail "gh could not post the report of /qa on $PR_URL"
    ids="$(printf '%s' "$ids" | jq -c --arg id "$comment_id" '. + [$id]')"
  done
  jq -n --argjson ids "$ids" --arg url "$PR_URL" '{id: $ids[0], ids: $ids, pr_url: $url}' \
    >"$qa_dir/pr-comment.json"
  echo "report of $(basename "$qa_dir") posted: $PR_URL"
}

case "$COMMAND" in
  run)      post_run "$ARGUMENT" ;;
  comments) show_comments ;;
  work)     git fetch -q "$REMOTE" "+refs/heads/$BASE:refs/remotes/$REMOTE/$BASE" || \
              fail "could not read $BASE from $REMOTE; git says why above"
            jq -n --arg work "$(tree_fingerprint)" --arg head "$HEAD_COMMIT" \
              --arg merge_base "$(git merge-base "refs/remotes/$REMOTE/$BASE" HEAD)" \
              '{work: $work, head: $head, merge_base: $merge_base}' ;;
  answers)  post_answers "$ARGUMENT"
            post_statuses || fail "the statuses could not be posted on $PR_URL"
            post_body ;;
  reply)    post_person_reply "${ARGUMENTS[0]}" "${ARGUMENTS[1]}" "$ARGUMENT" ;;
  qa)       post_qa "$ARGUMENT"
            post_statuses || fail "the statuses could not be posted on $PR_URL"
            post_body ;;
  statuses) post_statuses || fail "the statuses could not be posted on $PR_URL" ;;
  body)     post_body ;;
esac
