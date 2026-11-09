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
# land.sh calls it after a commit at LANDING=push, pr and merge. Run it alone to
# finish what stopped, a push that failed or a pull request that was waiting,
# without another commit. Run again, it does nothing twice: an open pull request is
# left as it is, a merged one is not pushed back, and a closed one is not replaced.
# See task-loop.md § Publishing.
#
# Usage, from the project root:
#   publish.sh --task-file <task.json>
#
# Exit codes:
#   0  done, as far as LANDING says
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

while [ $# -gt 0 ]; do
  case "$1" in
    --task-file) require_value "--task-file" $#; TASK_FILE="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done

[ -n "$TASK_FILE" ] || { echo "--task-file is required" >&2; exit 1; }
[ -f "$TASK_FILE" ] || { echo "no such task file: $TASK_FILE" >&2; exit 1; }

PROJECT_ROOT="$(git rev-parse --show-toplevel)" || exit 1
TASK_ID="$(jq -r '.id' "$TASK_FILE")"
[ -n "$TASK_ID" ] && [ "$TASK_ID" != "null" ] || { echo "task file has no .id" >&2; exit 1; }
cd "$PROJECT_ROOT" || exit 1

CONFIG=".review/land.conf"

refuse()  { echo "PUBLISHING REFUSED — $1" >&2; exit 3; }
fail()    { echo "PUBLISHING FAILED — $1" >&2; exit 1; }
waiting() { echo "PUBLISHING WAITS — $1" >&2; exit 5; }

# ---------------------------------------------------------------------------
# 1. Only what a landing made, at a level that publishes.
# ---------------------------------------------------------------------------

# The config is read as data, never sourced, as in land.sh.
LANDING="$(landing_level "$CONFIG")" || refuse "$LANDING"
landing_publishes "$LANDING" || \
  refuse "LANDING=$LANDING in $CONFIG does not publish — only push, pr and merge do"

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
if [ "$LANDING" = "merge" ]; then
  git fetch -q "$REMOTE" "+refs/heads/$BASE:refs/remotes/$REMOTE/$BASE" || \
    fail "could not read $BASE from $REMOTE; git says why above"
fi

UNLANDED="$(commits_no_landing_made "$LANDING" "$REMOTE" "$BASE")"
[ -z "$UNLANDED" ] || \
  refuse "LANDING=$LANDING would publish commits no landing made — "\
"a person pushes or moves them first: $(printf '%s' "$UNLANDED" | tr '\n' ';')"

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
PR_STATE=""
PR_HEAD=""

finish_on_base() {
  local merged_note="$PR_URL is merged into $BASE on $REMOTE"
  if [ "$(current_branch)" != "$BASE" ]; then
    if git worktree list --porcelain | grep -xF "branch refs/heads/$BASE" >/dev/null; then
      echo "merged $TASK_ID: $PR_URL into $BASE, which is checked out in another worktree, "\
"so this one stays on $BRANCH"
      exit 0
    fi
    git switch "$BASE" || \
      fail "$merged_note, but this checkout could not move to $BASE; git says why above. "\
"publish.sh again only tries that again, and pushes nothing"
  fi
  git pull --ff-only "$REMOTE" "refs/heads/$BASE" || \
    fail "$merged_note, and nothing is left to publish, but $BASE here could not fast-forward; "\
"git says why above. That is for a person to settle: publish.sh refuses on $BASE"
  if [ "$BRANCH" = "task/$TASK_ID" ] && git show-ref --verify --quiet "refs/heads/$BRANCH"; then
    git branch -q -d "$BRANCH" || echo "$BRANCH stays here: git would not delete it"
  fi
  echo "merged $TASK_ID: $PR_URL into $BASE"
}

if landing_opens_pull_request "$LANDING"; then
  REPOSITORY="$(remote_repository "$REMOTE")"
  PULL_REQUESTS="$(gh pr list --repo "$REPOSITORY" --head "$BRANCH" --base "$BASE" --state all \
    --json url,state,headRefOid,isCrossRepository)" || \
    fail "gh could not say whether $BRANCH has a pull request into $BASE"
  LATEST=\
"$(printf '%s' "$PULL_REQUESTS" | jq -c '[.[] | select(.isCrossRepository | not)][0] // {}')" || \
    fail "gh's answer about the pull requests of $BRANCH is not readable: $PULL_REQUESTS"
  PR_URL="$(printf '%s' "$LATEST" | jq -r '.url // ""')"
  PR_STATE="$(printf '%s' "$LATEST" | jq -r '.state // ""')"
  PR_HEAD="$(printf '%s' "$LATEST" | jq -r '.headRefOid // ""')"

  case "$PR_STATE" in
    CLOSED)
      waiting "$PR_URL was closed without a merge, which is somebody's no: "\
"only a person reopens it. Nothing was pushed and no new pull request was opened" ;;
    MERGED)
      if [ "$PR_HEAD" = "$HEAD_COMMIT" ]; then
        if [ "$LANDING" = "merge" ]; then
          finish_on_base
        else
          echo "already merged: $PR_URL"
        fi
        exit 0
      fi
      # New work on a branch whose earlier pull request was merged: a new one.
      PR_URL="" ;;
  esac
fi

# ---------------------------------------------------------------------------
# 2. Push. Never forced: a remote branch that moved is someone's work. Both sides
#    of the refspec are written out: a bare branch name goes through
#    remote.<name>.push, where a `+` would force it and a mapping would send it to
#    another branch.
# ---------------------------------------------------------------------------

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

# ---------------------------------------------------------------------------
# 3. One pull request.
# ---------------------------------------------------------------------------

if [ -z "$PR_URL" ]; then
  PR_URL="$(gh pr create --repo "$REPOSITORY" --base "$BASE" --head "$BRANCH" \
    --title "$(git log -1 --format=%s "$TASK_COMMIT")" \
    --body "$(git log -1 --format='%(trailers:only,unfold)' "$TASK_COMMIT")")" || \
    fail "gh could not open a pull request of $BRANCH into $BASE"
fi
echo "pull request: $PR_URL"

if [ "$LANDING" != "merge" ]; then
  echo "published $TASK_ID: $BRANCH on $REMOTE"
  exit 0
fi

# ---------------------------------------------------------------------------
# 4. Merge, unless something stands in the way. The commit to merge is the one just
#    pushed: a commit someone else pushed meanwhile never went through the loop.
# ---------------------------------------------------------------------------

# A branch stacked on an unmerged task would take that task into the base branch
# past its own pull request, whatever review stands on it there.
OTHER_TASKS=\
"$(git rev-list --no-merges "refs/remotes/$REMOTE/$BASE..HEAD" | while IFS= read -r commit; do
  commit_task="$(task_id_of "$commit")"
  [ "$commit_task" = "$TASK_ID" ] || printf '%s\n' "$commit_task"
done | sort -u | tr '\n' ' ')"
[ -z "$OTHER_TASKS" ] || \
  waiting "$PR_URL also carries ${OTHER_TASKS}which is not on $BASE yet: "\
"that task's pull request goes first, then run publish.sh again"

PR_VIEW="$(gh pr view "$PR_URL" --repo "$REPOSITORY" --json headRefOid,reviewDecision)" || \
  fail "gh could not read the review decision of $PR_URL"
PR_HEAD="$(printf '%s' "$PR_VIEW" | jq -r '.headRefOid')" || \
  fail "gh's answer about $PR_URL is not readable: $PR_VIEW"
[ "$PR_HEAD" = "$HEAD_COMMIT" ] || \
  waiting "the head of $PR_URL is $PR_HEAD, not the commit landed here, $HEAD_COMMIT — "\
"run publish.sh again; if it stays so, someone else pushed to $BRANCH"
REVIEW_DECISION="$(printf '%s' "$PR_VIEW" | jq -r '.reviewDecision')"
[ "$REVIEW_DECISION" != "CHANGES_REQUESTED" ] || \
  waiting "changes are requested on $PR_URL"

# By bucket, not by gh's exit code: a cancelled check exits 0, and it did not pass.
read_checks() {
  CHECKS_OUTPUT="$(gh pr checks "$PR_URL" --repo "$REPOSITORY" --json name,bucket 2>&1)"
  case "$CHECKS_OUTPUT" in
    *"no checks reported"*) CHECKS_STATE=none; return ;;
  esac
  CHECKS_STATE="$(printf '%s' "$CHECKS_OUTPUT" | jq -r '
    if type != "array" then "failing"
    elif length == 0 then "none"
    elif any(.bucket == "fail" or .bucket == "cancel") then "failing"
    elif any(.bucket == "pending") then "pending"
    elif all(.bucket == "pass" or .bucket == "skipping") then "passed"
    else "failing" end' 2>/dev/null)" || CHECKS_STATE=failing
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
  pending) waiting "checks are pending on $PR_URL — run publish.sh again later" ;;
  failing) printf '%s\n' "$CHECKS_OUTPUT"; waiting "checks are failing on $PR_URL" ;;
esac

# Never a squash: a merge commit keeps the Task-Id trailers of the commits. Only the
# branch of the task goes with it: any other branch is someone's.
MERGE_ARGUMENTS=(--repo "$REPOSITORY" --merge --match-head-commit "$HEAD_COMMIT")
[ "$BRANCH" != "task/$TASK_ID" ] || MERGE_ARGUMENTS+=(--delete-branch)

if ! MERGE_OUTPUT="$(gh pr merge "$PR_URL" "${MERGE_ARGUMENTS[@]}" 2>&1)"; then
  # gh tidies up after the merge, and can fail there with the pull request already
  # merged. The question is what happened to it.
  PR_STATE=\
"$(gh pr view "$PR_URL" --repo "$REPOSITORY" --json state 2>/dev/null | jq -r '.state' 2>/dev/null)"
  [ "$PR_STATE" = "MERGED" ] || waiting "gh did not merge $PR_URL: $MERGE_OUTPUT"
  echo "gh merged $PR_URL and did not finish tidying up, "\
"so $BRANCH may be left on $REMOTE: $MERGE_OUTPUT"
fi

finish_on_base
