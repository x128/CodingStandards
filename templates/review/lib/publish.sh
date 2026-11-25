#!/usr/bin/env bash
#
# publish.sh — takes what land.sh committed as far as LANDING says: the remote
# branch, a pull request, the merge.
#
# Runs FROM THE SUBMODULE and is deliberately NOT overridable by projects, for the
# reason land.sh is not: it must not be widenable locally.
#
# It has no code path for commit, amend, --force, rebase, reset, stash or clean.
# It works only from a branch that is not protected, on a HEAD land.sh made for
# this task. What a push adds to the remote must come from landings, and what a
# merge takes into the base branch must be this task's alone, so the loop reaches
# the base branch only through a pull request. The one branch it moves to is the
# base branch, after a merge, by fast-forward; the one it deletes is task/<id>, once
# that is merged.
#
# land.sh calls it after a commit at LANDING=push, pr and merge: it pushes, and at pr
# and merge opens the pull request and posts the loop's statuses on its head
# (pr-post.sh); it never merges then. Run it alone to finish what stopped, a push that
# failed or a pull request that could not be opened, without another commit. Run
# again, it does nothing twice: an open pull request is left as it is, a merged one
# is not pushed back, and a closed one is not replaced.
#
# At pr and merge, --check checks the merge contract and merges nothing; --merge, at
# merge alone, checks it and merges the pull request with a squash. See TASK_LOOP.md
# § Publishing and § The contract at the pull request levels.
#
# Whenever it finds the pull request of the task merged — by its own --merge, or by a
# person at pr — it writes down the checks /qa put off until after the merge
# (.review/runs/after-merge-<task>/owed.json) and lists those that have no result yet.
# No later task merges while one is missing (M10).
#
# Usage, from the project root:
#   publish.sh --task-file <task.json> [--check | --merge]
#
# Exit codes:
#   0  done, as far as LANDING says; with --check, the pull request is ready to merge
#   3  refused, with the reason on stderr
#   5  waiting — the pull request stays as it is, and the reason and its URL are on
#      stderr
#   1  usage or environment error, or a push that failed
#
# Requires: jq >= 1.6, git >= 2.23; gh at LANDING=pr and merge

set -uo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 1
# shellcheck source=common.sh
. "$LIB_DIR/common.sh"

TASK_FILE=""
MODE=publish

while [ $# -gt 0 ]; do
  case "$1" in
    --task-file) require_value "--task-file" $#; TASK_FILE="$2"; shift 2 ;;
    --check)     MODE=check; shift ;;
    --merge)     MODE=merge; shift ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done

[ -n "$TASK_FILE" ] || { echo "--task-file is required" >&2; exit 1; }
[ -f "$TASK_FILE" ] || { echo "no such task file: $TASK_FILE" >&2; exit 1; }

# Resolved before the cd below, as land.sh resolves its own: the review run records
# the task file by its absolute path, and the merge compares the two.
TASK_FILE="$(abspath "$TASK_FILE")" || exit 1
PROJECT_ROOT="$(git rev-parse --show-toplevel)" || exit 1
TASK_ID="$(jq -r '.id' "$TASK_FILE")"
[ -n "$TASK_ID" ] && [ "$TASK_ID" != "null" ] || { echo "task file has no .id" >&2; exit 1; }
cd "$PROJECT_ROOT" || exit 1

CONFIG=".review/land.conf"

# The merge contract reuses the conditions of land.sh through common.sh, which names
# each by its number there and calls refuse with it; here it is the item of the
# contract that holds that condition.
# refuse <reason>, refuse <condition> <reason>, and either with <whose> <what> after it:
# then the last line says whose turn it is (turn, common.sh). fail and waiting take
# <reason> [<whose> <what>] the same way.
refuse() {
  local whose="" what=""
  case $# in
    3) whose="$2"; what="$3"; set -- "$1" ;;
    4) whose="$3"; what="$4"; set -- "$1" "$2" ;;
  esac
  if [ $# -ge 2 ]; then
    case "$1" in 1|2) set -- "M1: $2" ;; 3) set -- "M2: $2" ;; 4) set -- "M3: $2" ;;
                 5) set -- "M4: $2" ;; 7) set -- "M5: $2" ;; *) set -- "$1: $2" ;; esac
  fi
  echo "PUBLISHING REFUSED — $1" >&2
  [ -z "$whose" ] || turn "$whose" "$what"
  exit 3
}
fail() {
  echo "PUBLISHING FAILED — $1" >&2
  [ $# -lt 3 ] || turn "$2" "$3"
  exit 1
}
waiting() {
  echo "PUBLISHING WAITS — $1" >&2
  [ $# -lt 3 ] || turn "$2" "$3"
  exit 5
}

# ---------------------------------------------------------------------------
# 1. Only what a landing made, at a level that publishes.
# ---------------------------------------------------------------------------

# The config is read as data, never sourced, as in land.sh.
LANDING="$(landing_level "$CONFIG")" || refuse "$LANDING"
landing_publishes "$LANDING" || \
  refuse "LANDING=$LANDING in $CONFIG does not publish — only push, pr and merge do"
if [ "$MODE" != publish ]; then
  landing_opens_pull_request "$LANDING" || \
    refuse "--$MODE is for LANDING=pr and merge, not $LANDING: there is no pull request"
  [ "$MODE$LANDING" != mergepr ] || \
    refuse "LANDING=pr in $CONFIG: publish.sh merges nothing there, and --check says whether "\
"the pull request is ready" user:only-theirs "the merge, with squash"
fi

task_id_names_branch "$TASK_ID" || \
  refuse "task id $TASK_ID cannot name a branch — "\
"it must match ^[A-Za-z0-9._-]+\$ and be a valid ref"

BRANCH="$(current_branch)"
[ -n "$BRANCH" ] || refuse "HEAD is detached — there is no branch to push"

REMOTE="$(resolve_remote "$CONFIG")" || refuse "$REMOTE"
BASE="$(resolve_base_branch "$CONFIG" "$REMOTE")" || refuse "$BASE"
PROBLEM="$(publishing_problem "$CONFIG" "$LANDING" "$REMOTE" "$BASE")" || refuse "$PROBLEM"

if branch_in_list "$BRANCH" "$(protected_branches "$CONFIG") $BASE"; then
  refuse "current branch is $BRANCH, a protected branch — it is reached only through a pull request"
fi

# HEAD itself, unless a person merged the base into the branch on top of it: the
# first-parent line then still ends in the commit of the landing.
TASK_COMMIT="$(git rev-list -1 --no-merges --first-parent HEAD)"
[ "$(task_id_of "$TASK_COMMIT")" = "$TASK_ID" ] || \
  refuse "HEAD does not carry the trailer Task-Id: $TASK_ID — "\
"only a commit land.sh made for this task is published"

HEAD_COMMIT="$(git rev-parse HEAD)"

# What the merge would take is measured against the base branch as it is now.
if [ "$LANDING" = "merge" ] || [ "$MODE" != publish ]; then
  git fetch -q "$REMOTE" "+refs/heads/$BASE:refs/remotes/$REMOTE/$BASE" || \
    fail "could not read $BASE from $REMOTE; git says why above"
fi

UNLANDED="$(commits_no_landing_made "$LANDING" "$REMOTE" "$BASE")"
[ -z "$UNLANDED" ] || \
  refuse "LANDING=$LANDING would publish commits no landing made: "\
"$(printf '%s' "$UNLANDED" | tr '\n' ';')" \
    user:only-theirs "push or move them: the loop publishes only what its landings made"

# ---------------------------------------------------------------------------
# What is already there. Asked before the push: pushing a merged branch would bring
# it back, and a pull request closed without a merge is somebody's no, which a
# rerun must not undo by opening another. A failed question must not read as "none
# yet": that would open a second one.
# ---------------------------------------------------------------------------

# Every gh call names the repository of REMOTE, and after this one the pull request
# by its URL: a branch named 1234 would otherwise select pull request #1234.
REPOSITORY=""
PR_URL=""
PR_NUMBER=""
PR_STATE=""
PR_HEAD=""

# The pull request is merged: what /qa put off until then is owed from now on, and is
# written down before anything else can fail (common.sh, owe_after_merge). <items> is what
# was read before a merge made here.
owe_checks() {
  owe_after_merge "$TASK_ID" "$PR_URL" "$PR_NUMBER" "$BASE" "$@" || \
    fail "$PR_URL is merged into $BASE, but the checks /qa put off until after the merge "\
"could not be written down under .review/runs/after-merge-$TASK_ID; what is above says why" \
      loop "run publish.sh again on this branch: it writes the list and merges nothing twice"
}

# What the merge of this pull request owes and has no result for yet, after every end that
# finds it merged. The exit code stays what it was: the merge is done.
say_owed() {
  local list folder="" owed
  for list in .review/runs/after-merge-*/owed.json; do
    [ -f "$list" ] || continue
    ! json_holds --arg url "$PR_URL" '.pr_url == $url' "$list" || folder="${list%/owed.json}"
  done
  [ -n "$folder" ] || return 0
  owed="$(after_merge_unsettled | jq -sc --arg folder "$folder" \
    'map(select(.folder == $folder and .kind != "list"))')" || return 0
  [ "$(printf '%s' "$owed" | jq 'length')" -gt 0 ] || return 0
  printf '%s' "$owed" | jq -r --arg task "$TASK_ID" '
    "OWED AFTER THE MERGE — /qa put off \(length) check(s) of \($task) until now:",
    (.[] | "  - \(.id): \(.check)")'
  turn loop "make them now (/qa --after-merge $TASK_ID): the results go into "\
"$folder/results.json, with a report.md beside it; no later task merges before each has its "\
"result"
}

finish_on_base() {
  local merged_note="$PR_URL is merged into $BASE on $REMOTE"
  if [ "$(current_branch)" != "$BASE" ]; then
    if git worktree list --porcelain | grep -xF "branch refs/heads/$BASE" >/dev/null; then
      echo "merged $TASK_ID: $PR_URL into $BASE, which is checked out in another worktree, "\
"so this one stays on $BRANCH"
      qa_asks "$TASK_ID"
      say_owed
      exit 0
    fi
    git switch "$BASE" || \
      fail "$merged_note, but this checkout could not move to $BASE; git says why above. "\
"publish.sh again only tries that again, and pushes nothing"
  fi
  git pull --ff-only "$REMOTE" "refs/heads/$BASE" || \
    fail "$merged_note, and nothing is left to publish, but $BASE here could not fast-forward; "\
"git says why above" \
      user:only-theirs "bring $BASE here in line with $REMOTE: publish.sh refuses on $BASE"
  # Not -D, which is a force: after a squash the branch is in no commit of the base, but
  # its upstream still names the head that was merged.
  if [ "$BRANCH" = "task/$TASK_ID" ] && git show-ref --verify --quiet "refs/heads/$BRANCH"; then
    git branch -q -d "$BRANCH" || echo "$BRANCH stays here: git would not delete it"
  fi
  echo "merged $TASK_ID: $PR_URL into $BASE"
  qa_asks "$TASK_ID"
  say_owed
}

if landing_opens_pull_request "$LANDING"; then
  REPOSITORY="$(remote_repository "$REMOTE")"
  LATEST="$(pull_request_of "$REPOSITORY" "$BRANCH" "$BASE" all)" || \
    fail "gh could not say whether $BRANCH has a pull request into $BASE"
  PR_URL="$(printf '%s' "$LATEST" | jq -r '.url // ""')"
  PR_NUMBER="$(printf '%s' "$LATEST" | jq -r '.number // ""')"
  PR_STATE="$(printf '%s' "$LATEST" | jq -r '.state // ""')"
  PR_HEAD="$(printf '%s' "$LATEST" | jq -r '.headRefOid // ""')"

  case "$PR_STATE" in
    CLOSED)
      waiting "$PR_URL was closed without a merge. Nothing was pushed and no new pull "\
"request was opened" user:only-theirs "reopen it, or say that the task ends here" ;;
    MERGED)
      if [ "$PR_HEAD" = "$HEAD_COMMIT" ]; then
        owe_checks
        if [ "$LANDING" = "merge" ] && [ "$MODE" != check ]; then
          finish_on_base
        else
          echo "already merged: $PR_URL"
          say_owed
        fi
        exit 0
      fi
      # New work on a branch whose earlier pull request was merged: a new one.
      PR_URL=""
      PR_NUMBER="" ;;
  esac
fi

if [ "$MODE" = publish ]; then
  # -------------------------------------------------------------------------
  # 2. Push. Never forced: a remote branch that moved is someone's work. Both sides
  #    of the refspec are written out: a bare branch name goes through
  #    remote.<name>.push, where a `+` would force it and a mapping would send it to
  #    another branch.
  # -------------------------------------------------------------------------

  PUSH_OUTPUT="$(git push -u "$REMOTE" "refs/heads/$BRANCH:refs/heads/$BRANCH" 2>&1)"
  PUSH_EXIT=$?
  printf '%s\n' "$PUSH_OUTPUT"
  if [ "$PUSH_EXIT" -ne 0 ]; then
    case "$PUSH_OUTPUT" in
      *"[rejected]"*) fail "the remote branch $BRANCH moved on $REMOTE — "\
"the push was rejected, and it is never forced" ;;
      *) fail "the push to $REMOTE failed; git says why above" ;;
    esac
  fi

  if ! landing_opens_pull_request "$LANDING"; then
    echo "published $TASK_ID: $BRANCH on $REMOTE"
    exit 0
  fi

  # -------------------------------------------------------------------------
  # 3. One pull request, never a draft, with the task as its title and the loop's
  #    description (pr-post.sh body); then the loop's statuses on the head just
  #    pushed (pr-post.sh statuses): those of the newest review and /qa if they
  #    checked the work as it is, which a commit of the loop's files alone keeps,
  #    and otherwise pending. Never a merge: that is --merge, once the review, /qa
  #    and the answers allow it.
  # -------------------------------------------------------------------------

  if [ -z "$PR_URL" ]; then
    BODY_FILE="$(mktemp)" || fail "no temporary file for the description"
    "$LIB_DIR/pr-post.sh" body --to "$BODY_FILE" --task-file "$TASK_FILE" || {
      rm -f "$BODY_FILE"
      fail "the description of the pull request could not be written; pr-post.sh says why above"
    }
    PR_URL="$(gh pr create --repo "$REPOSITORY" --base "$BASE" --head "$BRANCH" \
      --title "$TASK_ID: $(jq -r '.title // .id' "$TASK_FILE")" --body-file "$BODY_FILE")"
    CREATE_EXIT=$?
    rm -f "$BODY_FILE"
    [ "$CREATE_EXIT" -eq 0 ] || fail "gh could not open a pull request of $BRANCH into $BASE"
  fi
  echo "pull request: $PR_URL"
  "$LIB_DIR/pr-post.sh" statuses --task-file "$TASK_FILE" || \
    fail "$PR_URL is open, but the loop's statuses are not posted on it; pr-post.sh says why "\
"above. Run pr-post.sh statuses alone"
  echo "published $TASK_ID: $BRANCH on $REMOTE"
  exit 0
fi

# ---------------------------------------------------------------------------
# 4. The merge contract (--check, --merge): what can be checked only once the
#    review, the end-to-end tests and /qa have run on the pull request. Each item
#    that does not hold refuses (3), naming it; M8 and M9 wait (5). M10, what the
#    merges of earlier tasks still owe, is checked first.
# ---------------------------------------------------------------------------

[ -n "$PR_URL" ] || \
  refuse "$BRANCH has no open pull request into $BASE — publish.sh alone opens one"

# The description says where the task stands, at every check, refused or not.
"$LIB_DIR/pr-post.sh" body --task-file "$TASK_FILE" || \
  fail "the description of $PR_URL could not be refreshed; pr-post.sh says why above"

# The tree: the task's work committed and pushed, the loop's files committed, and with
# WITH_RECORDS=yes the records too; with no, the owner's files and the logs are the user's
# to commit and may wait in the tree.
UNCOMMITTED="$(uncommitted_task_work)"
[ -z "$UNCOMMITTED" ] || \
  refuse "the task's work is not all committed: $(printf '%s\n' "$UNCOMMITTED" | tr '\n' ' ')— "\
"land.sh commits it, and the review runs on it then"
UNCOMMITTED="$(uncommitted "${LOOP_FILES[@]}")"
[ -z "$UNCOMMITTED" ] || \
  refuse "the loop's files are not committed: $(printf '%s\n' "$UNCOMMITTED" | tr '\n' ' ')— "\
"land.sh commits them"
if [ "$(read_conf "$CONFIG" WITH_RECORDS no)" = yes ]; then
  UNCOMMITTED="$(uncommitted "${RECORDS[@]}")"
  [ -z "$UNCOMMITTED" ] || \
    refuse "with WITH_RECORDS=yes the records land with the task, and these are not committed: "\
"$(printf '%s\n' "$UNCOMMITTED" | tr '\n' ' ')— land.sh commits them"
fi

FINGERPRINT="$(tree_fingerprint)"
MERGE_BASE="$(git merge-base "refs/remotes/$REMOTE/$BASE" HEAD)" || \
  fail "HEAD has no commit in common with $BASE of $REMOTE"

# M10: no task merged before this one still owes a check that /qa put off until after its
# merge (common.sh, after_merge_unsettled). What the loop can do itself is named first: a
# result that is missing or does not say what was seen, then a failure that names no task
# of the tracker; a check that could not be made is the user's to accept. Then the report
# of each merged task is on its pull request: pr-post.sh after-merge posts it, once.
OWED="$(after_merge_unsettled | jq -sc --arg url "$PR_URL" 'map(select(.pr_url != $url))')" || \
  fail "what the merges of earlier tasks owe could not be read (.review/runs/after-merge-*)"
# owed_first <kind> <jq>: of the first merged task that has items of the kind, as <jq> says.
owed_first() {
  printf '%s' "$OWED" | jq -r --arg kind "$1" \
    'map(select(.kind == $kind)) | group_by(.folder) | first // empty | '"$2"
}
OWED_FIRST="$(owed_first list '.[0].folder')"
[ -z "$OWED_FIRST" ] || \
  refuse M10 "$OWED_FIRST/owed.json, the list of the checks a merged task owes, is not "\
"readable" \
    loop "repair it — {task, pr_url, pr_number, base, time, items: [{id, reason, check, from}]}, "\
"as publish.sh wrote it after the merge"
OWED_FIRST="$(owed_first result '[.[0].task, .[0].folder, (map(.id) | join("; "))] | @tsv')"
if [ -n "$OWED_FIRST" ]; then
  IFS=$'\t' read -r OWING OWED_FOLDER OWED_IDS <<<"$OWED_FIRST"
  refuse M10 "$OWING was merged with checks put off until after its merge, and these have no "\
"result that says what was seen: $OWED_IDS" \
    loop "make them (/qa --after-merge $OWING): $OWED_FOLDER/results.json"
fi
OWED_FIRST="$(owed_first task '[.[0].task, (map(.id) | join("; "))] | @tsv')"
if [ -n "$OWED_FIRST" ]; then
  IFS=$'\t' read -r OWING OWED_IDS <<<"$OWED_FIRST"
  refuse M10 "$OWING was merged, and these checks failed after it and name no task of the "\
"tracker: $OWED_IDS" \
    loop "a check that fails after the merge is a defect: write it into the tracker as a task, "\
"and name the task in its result"
fi
OWED_FIRST="$(owed_first accepted '[.[0].task, .[0].folder, .[0].id, .[0].reason] | @tsv')"
if [ -n "$OWED_FIRST" ]; then
  IFS=$'\t' read -r OWING OWED_FOLDER OWED_IDS OWED_REASON <<<"$OWED_FIRST"
  refuse M10 "$OWING is merged, and $OWED_IDS could not be checked after it ($OWED_REASON)" \
    user:beyond-agreed "leave it unchecked, or say how to check it; their acceptance goes into "\
"$OWED_FOLDER/open-answered.json, {\"by\": \"human\", \"answer\": \"accepted-as-is\"}"
fi
for OWED_LIST in .review/runs/after-merge-*/owed.json; do
  [ -f "$OWED_LIST" ] || continue
  OWED_FOLDER="${OWED_LIST%/owed.json}"
  OWING="$(jq -r '.task' "$OWED_LIST")"
  OWED_URL="$(jq -r '.pr_url // ""' "$OWED_LIST")"
  [ "$OWED_URL" != "$PR_URL" ] || continue
  ! json_holds --arg url "$OWED_URL" '.pr_url == $url' "$OWED_FOLDER/pr-comment.json" || continue
  [ -s "$OWED_FOLDER/report.md" ] || \
    refuse M10 "the report of the checks after the merge of $OWING is not written" \
      loop "write $OWED_FOLDER/report.md"
  "$LIB_DIR/pr-post.sh" after-merge "$OWED_FOLDER" || \
    fail "the report of the checks after the merge of $OWING is not on $OWED_URL; "\
"pr-post.sh says why above"
done

# M1 to M5: the newest review run of the task made on this pull request, by the time it
# records, posted there, of the change since the merge base as it is now, with the
# conditions of land.sh (common.sh); /qa checked this work, one /qa the whole pull request,
# and nothing it left open stands unanswered. A run of --dry-run, or one never posted, is
# no review on the pull request.
RUN="$(review_runs_on "$TASK_ID" "$PR_URL" | tail -1)"
[ -n "$RUN" ] || \
  refuse M1 "no review run of $TASK_ID on $PR_URL — review.sh runs on the pull request"
run_is_complete "$RUN"
run_reviewed_this_tree "$RUN" "$TASK_FILE" "$FINGERPRINT"
[ "$(jq -r '.merge_base // ""' "$RUN/meta.json")" = "$MERGE_BASE" ] || \
  refuse M1 "$(basename "$RUN") reviewed the change from another merge base than $MERGE_BASE "\
"— review again"
jq -e --arg url "$PR_URL" '.pr_url == $url' "$RUN/pr-review.json" >/dev/null 2>&1 || \
  refuse M1 "$(basename "$RUN") is not posted on $PR_URL — pr-post.sh run $RUN posts it"
run_e2e_passed "$RUN" "$FINGERPRINT"
run_has_no_findings "$RUN"
run_escalations_answered "$RUN"
criteria_verified "$TASK_FILE"
qa_failures_proven "$RUN" "$TASK_ID"
qa_checked_this_work "$TASK_ID" "$FINGERPRINT" "$MERGE_BASE"
qa_left_nothing_open "$TASK_ID" "$MERGE_BASE"
qa_reports_posted "$TASK_ID" "$MERGE_BASE" "$PR_URL"

# M6: what the pull request changes stayed inside the task's scope, the loop's own files,
# the harness and the records apart.
OUT_OF_SCOPE="$(git -c core.quotePath=false diff --name-only --no-renames "$MERGE_BASE" HEAD \
  | while IFS= read -r file; do
      is_loop_file "$file" || is_harness "$file" || is_record "$file" || printf '%s\n' "$file"
    done | outside_scope "$TASK_FILE" | tr '\n' ' ')"
[ -z "$OUT_OF_SCOPE" ] || \
  refuse M6 "the pull request changes files outside the scope of $TASK_ID: $OUT_OF_SCOPE"

# M7: every run made on this pull request is posted there, and every finding it handed
# over — accepted at or above the threshold, or escalated — has its answer posted there.
# The optional ones never reach anyone.
UNANSWERED="$(review_runs_on "$TASK_ID" "$PR_URL" | while IFS= read -r run; do
    if ! jq -e --arg url "$PR_URL" '.pr_url == $url' "$run/pr-review.json" >/dev/null 2>&1; then
      echo "$(basename "$run"): not posted — pr-post.sh run $run"
      continue
    fi
    # A run that ended before its triage handed nothing over; a file that is there is read.
    { cat "$run/approved.json" 2>/dev/null || echo '[]'
      cat "$run/escalated.json" 2>/dev/null || echo '[]'
      cat "$run/answers-posted.json" 2>/dev/null || echo '[]'; } \
      | jq -sr --arg run "$(basename "$run")" '
        ([.[0][].finding_id] + [.[1][].finding_id] | unique) - [.[2][].finding_id]
        | .[] | "\($run) \(.)"' 2>/dev/null \
      || echo "$(basename "$run"): its findings or answers are unreadable"
  done | tr '\n' ';')"
[ -z "$UNANSWERED" ] || \
  refuse M7 "runs or findings of $PR_URL that are not posted there: $UNANSWERED "\
"— a finding's answer goes into <run>/answers.json, then pr-post.sh answers <run>"

# M8: whatever a person wrote on the pull request — a comment, a review, a comment on a
# line — is settled: the loop fixed it, or the user decided it (common.sh,
# people_comments_open). The loop's own posts start with its marker. Whose turn it is is
# read from all that are open: while one of them is the loop's — one not answered, which
# it weighs and answers, or one it answered unsettled, which it finds out — the stop is the
# loop's and names the first such comment, wherever it stands among them. Only when every
# open comment is one the loop answered not-a-problem or other-task does the stop stand
# between the author of the first and the loop: then it is the user's.
OPEN_COMMENTS="$(people_comments_open "$REPOSITORY" "$PR_NUMBER")" || \
  fail "gh could not read the comments of $PR_URL"
NAMED_COMMENT="$(printf '%s' "$OPEN_COMMENTS" | jq -c '
  (map(select(.answered == null or .answered == "unsettled")) | first // null) as $loops
  | (first // empty)
  | if $loops == null then . + {which: "the first"}
    elif $loops.id == .id then $loops + {which: "the first"}
    else $loops + {which: "the first that is the loop'"'"'s"} end')"
if [ -n "$NAMED_COMMENT" ]; then
  UNSETTLED="$(printf '%s' "$OPEN_COMMENTS" | jq length) comment(s) of people on $PR_URL are "\
"not settled, $(printf '%s' "$NAMED_COMMENT" | jq -r '
    "\(.which) \(.id) by \(.author) on \(.where)"
    + (if .answered == null then ", not answered" else ", answered \(.answered)" end)')"
  NAMED_ID="$(printf '%s' "$NAMED_COMMENT" | jq -r '.id')"
  NAMED_ANSWER="$(printf '%s' "$NAMED_COMMENT" | jq -r '.answered // ""')"
  NAMED_AUTHOR="$(printf '%s' "$NAMED_COMMENT" | jq -r '.author // ""')"
  case "$NAMED_ANSWER" in
    "") waiting "$UNSETTLED" loop "weigh it like a finding and answer it: pr-post.sh comments "\
"shows it whole, pr-post.sh reply $NAMED_ID <answer> <text-file> answers" ;;
    unsettled) waiting "$UNSETTLED" loop "find out what is still assumed, then answer it again" ;;
    *) waiting "$UNSETTLED" user:a-person-said "decide between what ${NAMED_AUTHOR:-its author} "\
"wrote and the loop's answer $NAMED_ANSWER; their decision is posted with pr-post.sh reply "\
"$NAMED_ID user <text-file>" ;;
  esac
fi

# ---------------------------------------------------------------------------
# M9: on GitHub. The commit to merge is the one checked here: a commit someone else
# pushed meanwhile never went through the loop.
# ---------------------------------------------------------------------------

# A branch stacked on an unmerged task would take that task into the base branch
# past its own pull request, whatever review stands on it there.
OTHER_TASKS="$(other_tasks_on "refs/remotes/$REMOTE/$BASE" "$TASK_ID")"
[ -z "$OTHER_TASKS" ] || \
  waiting "$PR_URL also carries ${OTHER_TASKS}which is not on $BASE yet: "\
"that task's pull request goes first, then run publish.sh --$MODE again"

PR_VIEW="$(gh pr view "$PR_URL" --repo "$REPOSITORY" --json headRefOid,reviewDecision)" || \
  fail "gh could not read the review decision of $PR_URL"
PR_HEAD="$(printf '%s' "$PR_VIEW" | jq -r '.headRefOid')" || \
  fail "gh's answer about $PR_URL is not readable: $PR_VIEW"
if [ "$PR_HEAD" != "$HEAD_COMMIT" ]; then
  HEAD_DIFFERS="the head of $PR_URL is $PR_HEAD, not HEAD, $HEAD_COMMIT"
  git merge-base --is-ancestor "$PR_HEAD" HEAD 2>/dev/null && \
    waiting "$HEAD_DIFFERS" \
      loop "run publish.sh alone, which pushes it, then publish.sh --$MODE again"
  waiting "$HEAD_DIFFERS" \
    user:only-theirs "bring the two together: that commit was pushed to $BRANCH from elsewhere"
fi
REVIEW_DECISION="$(printf '%s' "$PR_VIEW" | jq -r '.reviewDecision')"
# GitHub gives a review decision only where a rule of the branch requires reviews, so the
# reviews themselves are read too: each person's latest review that decides something.
REVIEWS="$(gh_repo_api_list "$REPOSITORY" "pulls/$PR_NUMBER/reviews")" || \
  fail "gh could not read the reviews of $PR_URL"
CHANGES_REQUESTED="$(printf '%s' "$REVIEWS" | jq -r '
  [.[] | select(.state == "APPROVED" or .state == "CHANGES_REQUESTED" or .state == "DISMISSED")]
  | group_by(.user.login // "") | map(last) | any(.state == "CHANGES_REQUESTED")')" || \
  fail "the reviews of $PR_URL are not readable"
[ "$REVIEW_DECISION" != "CHANGES_REQUESTED" ] && [ "$CHANGES_REQUESTED" != true ] || \
  waiting "changes are requested on $PR_URL, and they stand until the one who asked approves "\
"or dismisses their review" \
    user:a-person-said "ask them to approve or dismiss it, once every remark is answered"

# By bucket, not by gh's exit code: a cancelled check exits 0, and it did not pass. The
# loop's own statuses (loop/*) are read apart: waiting does not change them.
read_checks() {
  CHECKS_OUTPUT="$(gh pr checks "$PR_URL" --repo "$REPOSITORY" --json name,bucket,description \
    2>&1)"
  LOOP_CHECKS='[]'
  case "$CHECKS_OUTPUT" in
    *"no checks reported"*) CHECKS_STATE=none; return ;;
  esac
  LOOP_CHECKS="$(printf '%s' "$CHECKS_OUTPUT" \
    | jq -c '[.[] | select(.name | startswith("loop/"))]' 2>/dev/null)" || LOOP_CHECKS='[]'
  CHECKS_STATE="$(printf '%s' "$CHECKS_OUTPUT" | jq -r '
    if type != "array" then "failing"
    else map(select(.name | startswith("loop/") | not))
    | if length == 0 then "none"
      elif any(.bucket == "fail" or .bucket == "cancel") then "failing"
      elif any(.bucket == "pending") then "pending"
      elif all(.bucket == "pass" or .bucket == "skipping") then "passed"
      else "failing" end end' 2>/dev/null)" || CHECKS_STATE=failing
}

# Checks appear on a commit some seconds after its push, and until then gh says "no
# checks reported" in a repository that has them, so asked at once every landing
# would merge before its checks started. Then they run. Both are waited for up to
# CHECKS_WAIT seconds; after that "none" is believed and "pending" is exit 5.
CHECKS_WAIT="$(read_conf "$CONFIG" CHECKS_WAIT 30)"
CHECKS_DEADLINE=$((SECONDS + 10#$CHECKS_WAIT))
CHECKS_PAUSE=1
read_checks
while { [ "$CHECKS_STATE" = "none" ] || [ "$CHECKS_STATE" = "pending" ]; } \
      && [ "$SECONDS" -lt "$CHECKS_DEADLINE" ]; do
  sleep "$CHECKS_PAUSE"
  [ "$CHECKS_PAUSE" -ge 15 ] || CHECKS_PAUSE=$((CHECKS_PAUSE * 2))
  read_checks
done

case "$CHECKS_STATE" in
  pending) waiting "checks are pending on $PR_URL — run publish.sh --$MODE again later" ;;
  failing) printf '%s\n' "$CHECKS_OUTPUT"; waiting "checks are failing on $PR_URL" ;;
esac

# The statuses of the loop at HEAD, which pr-post.sh posts for people to see: each
# blocking gate of the run, the end-to-end tests of each platform, the review and /qa.
# The merge does not take its own word for them: what the people saw is what merges.
LOOP_WANTED="$( { jq -r 'to_entries[] | select(.value.blocking != false) | "loop/\(.key)"' \
                    "$RUN/gates.json"
                  platforms | sed 's|^|loop/e2e-|'
                  printf 'loop/review\nloop/qa\n'; } | jq -R . | jq -sc .)"
NOT_GREEN="$(jq -nr --argjson wanted "$LOOP_WANTED" --argjson seen "$LOOP_CHECKS" '
  [$wanted[] as $name | ([$seen[] | select(.name == $name)] | last) as $status
   | if $status == null then "\($name) is not posted"
     elif $status.bucket != "pass" then "\($name): \($status.description // $status.bucket)"
     else empty end] | first // empty')"
[ -z "$NOT_GREEN" ] || \
  waiting "a status of the loop at $HEAD_COMMIT is not green on $PR_URL — $NOT_GREEN; "\
"pr-post.sh statuses posts them again"

# What /qa put off until after the merge, read before it: the merge may leave this checkout
# on the base branch.
AFTER_MERGE="$(qa_after_merge_items "$TASK_ID")" || \
  fail "the /qa records of $TASK_ID could not be read; the line before this one says which"

if [ "$MODE" = check ]; then
  echo "ready to merge: $PR_URL — with squash; its description ends with the trailers"
  printf '%s' "$AFTER_MERGE" | jq -r 'select(length > 0)
    | "   after the merge /qa owes \(length) check(s): \(map(.id) | join("; "))"'
  qa_asks "$TASK_ID"
  exit 0
fi

# ---------------------------------------------------------------------------
# 5. Merge: a squash of the head checked here, so the base branch gets one commit per
#    task, whose message carries the audit trailers. Only the branch of the task goes
#    with it: any other branch is someone's.
# ---------------------------------------------------------------------------

MERGE_ARGUMENTS=(--repo "$REPOSITORY" --squash --match-head-commit "$HEAD_COMMIT"
                 --subject "$TASK_ID: $(jq -r '.title // .id' "$TASK_FILE")"
                 --body "$(squash_trailers "$TASK_FILE" "$PR_URL")")
[ "$BRANCH" != "task/$TASK_ID" ] || MERGE_ARGUMENTS+=(--delete-branch)

if ! MERGE_OUTPUT="$(gh pr merge "$PR_URL" "${MERGE_ARGUMENTS[@]}" 2>&1)"; then
  # gh tidies up after the merge, and can fail there with the pull request already
  # merged. The question is what happened to it, and, where it is not merged, whether it
  # conflicts with the base branch: that merge is no step of the loop.
  PR_AFTER="$(gh pr view "$PR_URL" --repo "$REPOSITORY" --json state,mergeable 2>/dev/null)"
  PR_STATE="$(printf '%s' "$PR_AFTER" | jq -r '.state' 2>/dev/null)"
  if [ "$PR_STATE" != "MERGED" ]; then
    [ "$(printf '%s' "$PR_AFTER" | jq -r '.mergeable' 2>/dev/null)" != "CONFLICTING" ] || \
      waiting "gh did not merge $PR_URL: $MERGE_OUTPUT" \
        user:only-theirs "merge $BASE into $BRANCH: the pull request conflicts with it; the "\
"loop then publishes, reviews and checks it again"
    waiting "gh did not merge $PR_URL: $MERGE_OUTPUT" \
      loop "gh's reason is above; run publish.sh --merge again once it no longer holds"
  fi
  echo "gh merged $PR_URL and did not finish tidying up, "\
"so $BRANCH may be left on $REMOTE: $MERGE_OUTPUT"
fi

owe_checks "$AFTER_MERGE"
finish_on_base
