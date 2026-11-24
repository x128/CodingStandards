#!/usr/bin/env bash
#
# land.sh — the only thing in the pipeline that commits.
#
# Runs FROM THE SUBMODULE and is deliberately NOT overridable by projects: it is
# the one file with commit authority, so it must not be widenable locally.
#
# It has no code path for push, amend, --force, rebase, checkout, reset, stash or
# clean. It stages the task's declared files, the loop's own, the end-to-end harness
# the task changed and, with WITH_RECORDS=yes, the loop's records, and commits: on
# the current branch, or at LANDING=push, pr and merge on task/<id>, the one branch
# it may create and the only one it may move to. That is all it can do.
# Whatever happens to the commit next is in publish.sh, which it calls and which
# cannot commit.
#
# It refuses (exit 3) unless all eight landing conditions hold. A ninth switch,
# LANDING, then decides how far the task goes: off only prints the commit, which
# is not a refusal and exits 0; on commits; push, pr and merge commit and call
# publish.sh. See TASK_LOOP.md § Landing.
#
# At pr and merge the work is committed before its review, which runs on the pull
# request: the commit checks conditions 8, 6 and the gates of 3, and takes no --run;
# the rest of the eight are checked by publish.sh --check and --merge. See
# TASK_LOOP.md § The contract at the pull request levels.
#
# Usage, from the project root:
#   land.sh --task-file <task.json> --run <run-dir> [--message "..."] [--dry-run]
#   land.sh --task-file <task.json> [--message "..."] [--dry-run]
#           [--past-limit [--because <why>] [--user-decided]]   at LANDING=pr and merge
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
PAST_LIMIT=false
BECAUSE=""
BECAUSE_GIVEN=false
USER_DECIDED=false

while [ $# -gt 0 ]; do
  case "$1" in
    --task-file)  require_value "--task-file" $#; TASK_FILE="$2"; shift 2 ;;
    --run)        require_value "--run" $#; RUN_DIR="$2"; shift 2 ;;
    --message)    require_value "--message" $#; MESSAGE="$2"; shift 2 ;;
    --dry-run)    DRY_RUN=1; shift ;;
    --past-limit) PAST_LIMIT=true; shift ;;
    --because)    require_value "--because" $#; BECAUSE_GIVEN=true; BECAUSE="$2"; shift 2 ;;
    --user-decided) USER_DECIDED=true; shift ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done

# What passes the limit of landings goes with --past-limit alone, as for review.sh: the
# loop's own reason, or that the user decided to go on. --user-decided takes no words:
# nothing keeps what a person said. The reason is read without the blanks around it, so
# one made of blanks is none.
BECAUSE="${BECAUSE#"${BECAUSE%%[![:space:]]*}"}"
BECAUSE="${BECAUSE%"${BECAUSE##*[![:space:]]}"}"
if [ "$PAST_LIMIT" = false ]; then
  [ "$BECAUSE_GIVEN" = false ] || { echo "--because goes with --past-limit" >&2; exit 1; }
  [ "$USER_DECIDED" = false ] || { echo "--user-decided goes with --past-limit" >&2; exit 1; }
fi

[ -n "$TASK_FILE" ] || { echo "--task-file is required" >&2; exit 1; }
[ -f "$TASK_FILE" ] || { echo "no such task file: $TASK_FILE" >&2; exit 1; }

# Resolved before the cd below. Documented usage is "from the project root", but
# run from a subdirectory these relative paths would quietly point elsewhere
# afterwards and land as a condition-2 refusal instead of a usage error.
TASK_FILE="$(abspath "$TASK_FILE")" || exit 1
if [ -d "$RUN_DIR" ]; then
  RUN_DIR="$(abspath "$RUN_DIR")" || exit 1
fi

PROJECT_ROOT="$(git rev-parse --show-toplevel)" || exit 1
cd "$PROJECT_ROOT" || exit 1

REVIEW_DIR=".review"
CONFIG="$REVIEW_DIR/land.conf"

# The config is read as data, never sourced — a project must not be able to
# redefine a command or a guard in the one script with commit authority.
PROTECTED_BRANCHES="$(protected_branches "$CONFIG")"

# refuse <condition> <reason> [<whose> <what>]: with the last two, the last line says
# whose turn it is (turn, common.sh).
refuse() {
  echo "LANDING REFUSED — condition $1: $2" >&2
  [ $# -lt 4 ] || turn "$3" "$4"
  exit 3
}

LANDING="$(landing_level "$CONFIG")" || refuse 8 "$LANDING"

# At pr and merge the review runs on the pull request, after this commit.
if landing_opens_pull_request "$LANDING"; then
  [ -z "$RUN_DIR" ] || \
    echo "LANDING=$LANDING: --run is not used — the review runs on the pull request, "\
"after this commit; publish.sh --check and --merge check it" >&2
  RUN_DIR=""
else
  [ -n "$RUN_DIR" ] || { echo "--run is required" >&2; exit 1; }
  [ -d "$RUN_DIR" ] || { echo "no such run directory: $RUN_DIR" >&2; exit 1; }
  [ "$PAST_LIMIT" = false ] || {
    echo "--past-limit counts the landings of LANDING=pr and merge; at $LANDING a run counts "\
"its own (review.sh --past-limit)" >&2
    exit 1
  }
fi

# The records of the loop — the requirements and the plan, the decision logs and the
# review policy — land in the task's commit with WITH_RECORDS=yes; with no, they stay
# in the tree for the user. The loop's settings (land.conf, gates.sh) never land here:
# what the loop may do is the user's to commit. Nor does the task file, which the
# project ignores.
WITH_RECORDS="$(read_conf "$CONFIG" WITH_RECORDS no)"
case "$WITH_RECORDS" in
  yes | no) ;;
  *) refuse 8 "WITH_RECORDS in $CONFIG must be yes or no, not '$WITH_RECORDS'" ;;
esac

TASK_ID="$(jq -r '.id' "$TASK_FILE")"
[ -n "$TASK_ID" ] && [ "$TASK_ID" != "null" ] || { echo "task file has no .id" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 1 to 5. The run is a completed review run (1) of THIS tree (2); its end-to-end
#    tests passed on every platform the tree ships, through the harness as it is now,
#    with every mark of qa/test-cases.md (3, end-to-end half); no accepted finding is
#    at or above its threshold (4) and no escalation waits for an answer (5). The
#    checks are in common.sh, which publish.sh shares for the merge. At pr and merge
#    there is no run yet: the review runs on the pull request this commit updates.
# ---------------------------------------------------------------------------

CURRENT_FINGERPRINT="$(tree_fingerprint)"
if [ -n "$RUN_DIR" ]; then
  run_is_complete "$RUN_DIR"
  run_reviewed_this_tree "$RUN_DIR" "$TASK_FILE" "$CURRENT_FINGERPRINT"
  run_e2e_passed "$RUN_DIR" "$CURRENT_FINGERPRINT"
  run_has_no_findings "$RUN_DIR"
  run_escalations_answered "$RUN_DIR"
  # The threshold comes from the run that produced these verdicts, so landing can
  # never apply a different bar than the review did.
  THRESHOLD="$(jq -r '.threshold // "major"' "$RUN_DIR/meta.json")"
fi

# ---------------------------------------------------------------------------
# 6. The diff stayed inside the task's declared scope (outside_scope, common.sh).
# ---------------------------------------------------------------------------

[ "$(jq '[.scope[]?] | length' "$TASK_FILE")" -gt 0 ] || refuse 6 "task $TASK_ID declares no scope"

# The pipeline's own bookkeeping (decision logs, policy edits, run artifacts) is
# never part of a task's diff: it is not scope-checked, and not staged or committed
# here — see the `--only` on the commit below, which is what makes that last part
# true — apart from the decision logs and the policy with WITH_RECORDS=yes, below.
# Threshold changes, and policy changes with WITH_RECORDS=no, are the user's to commit.
# The end-to-end harness is another exception: it is reviewed work and lands with
# the task, below, even a task of the harness alone. The loop's own files land too,
# but need a task to land with: alone, they are not a task — at pr and merge, the
# task is the open pull request they land on (condition 8).
# Names as they are (core.quotePath=false): a quoted non-ASCII name matches no
# scope and is no file to stage.
EVERY_CHANGE="$( { git -c core.quotePath=false diff --name-only;
                   git -c core.quotePath=false diff --cached --name-only;
                   git -c core.quotePath=false ls-files --others --exclude-standard; } \
                 | sort -u )"
CHANGED_FILES="$(printf '%s\n' "$EVERY_CHANGE" | only_task_work)"
HARNESS_CHANGED="$(printf '%s\n' "$EVERY_CHANGE" | while IFS= read -r file; do
    ! is_harness "$file" || printf '%s\n' "$file"
  done)"

OUT_OF_SCOPE="$(printf '%s\n' "$CHANGED_FILES" | outside_scope "$TASK_FILE" \
  | while IFS= read -r file; do printf ' %s' "$file"; done)"
[ -z "$OUT_OF_SCOPE" ] || \
  refuse 6 "files outside task scope:$OUT_OF_SCOPE — split them into their own task"

# What the commit holds: the task's files, the loop's own, and the end-to-end harness
# the task changed. The decision logs record what the user said, and the requirements
# and the plan are the product owner's: they land here only with WITH_RECORDS=yes, and
# otherwise stay in the tree for the user. A task of the harness alone has no file in
# scope.
TO_COMMIT=()
while IFS= read -r file; do
  [ -z "$file" ] || TO_COMMIT+=("$file")
done <<<"$CHANGED_FILES"
while IFS= read -r file; do
  if is_loop_file "$file"; then
    TO_COMMIT+=("$file")
  elif [ "$WITH_RECORDS" = yes ] && is_record "$file"; then
    TO_COMMIT+=("$file")
  fi
done <<<"$EVERY_CHANGE"
while IFS= read -r file; do
  [ -z "$file" ] || TO_COMMIT+=("$file")
done <<<"$HARNESS_CHANGED"

# A commit of the loop's files and records alone — the tracker's done, the cases of /qa,
# the plan's [x], the logs — changes no task work, so at pr and merge it lands on the
# task's open pull request without staling its review. Elsewhere it is no task.
RECORDS_ONLY=0
if [ -z "$CHANGED_FILES" ] && [ -z "$HARNESS_CHANGED" ]; then
  landing_opens_pull_request "$LANDING" || \
    refuse 6 "nothing to commit outside .review/, the end-to-end harness apart, "\
"and the loop's own files"
  [ "${#TO_COMMIT[@]}" -gt 0 ] || \
    refuse 6 "nothing to commit: no work of the task, no file of the loop's own and no record "\
"it lands (WITH_RECORDS=$WITH_RECORDS) changed"
  RECORDS_ONLY=1
fi

# ---------------------------------------------------------------------------
# 7. Every exit criterion carries an explicit verification claim, and /qa checked
#    the task (criteria_verified and qa_failures_proven, common.sh). At pr and merge
#    /qa runs on the pull request after this commit, and publish.sh checks both.
# ---------------------------------------------------------------------------

CRITERIA_COUNT="$(jq '.exit_criteria | length' "$TASK_FILE")"
if [ -n "$RUN_DIR" ]; then
  criteria_verified "$TASK_FILE"
  qa_failures_proven "$RUN_DIR" "$TASK_ID"
fi

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
CHANGE_BASE=HEAD
TASK_COMMITS=""
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
fi

#    At pr and merge a task never stacks: the pull request is merged with a squash,
#    which never puts the commits of another task on the base branch, so a pull
#    request on top of them could never merge. They are measured against the base
#    branch as the remote has it now, which is also where the change the gates
#    measure starts (REVIEW_BASE).
if landing_opens_pull_request "$LANDING"; then
  git fetch -q "$REMOTE" "+refs/heads/$BASE_BRANCH:refs/remotes/$REMOTE/$BASE_BRANCH" || \
    refuse 8 "could not read $BASE_BRANCH from $REMOTE; git says why above"
  BASE_REF="refs/remotes/$REMOTE/$BASE_BRANCH"
  OTHER_TASKS="$(other_tasks_on "$BASE_REF" "$TASK_ID")"
  [ -z "$OTHER_TASKS" ] || \
    refuse 8 "HEAD carries ${OTHER_TASKS}which is not on $BASE_BRANCH of $REMOTE: a squash never "\
"puts those commits there, so a pull request on top of them could never merge — the task "\
"starts from $BASE_BRANCH, updated"
  CHANGE_BASE="$(git merge-base "$BASE_REF" HEAD)" || \
    refuse 8 "HEAD has no commit in common with $BASE_BRANCH of $REMOTE"
  TASK_COMMITS="$(git rev-list --no-merges "$BASE_REF..HEAD" | while IFS= read -r commit; do
    [ "$(task_id_of "$commit")" != "$TASK_ID" ] || printf '%s\n' "$commit"
  done)"

  # The loop's files alone land on the branch of the task, under its own commit, while
  # the task's pull request is open: that is the task they belong to.
  if [ "$RECORDS_ONLY" -eq 1 ]; then
    OPEN="$(pull_request_of "$(remote_repository "$REMOTE")" "$BRANCH" "$BASE_BRANCH")" || \
      refuse 8 "gh could not say whether $BRANCH has a pull request into $BASE_BRANCH"
    OPEN="$(printf '%s' "$OPEN" | jq -r '.url // ""')"
    [ "$LANDING_BRANCH" = "$BRANCH" ] && [ -n "$TASK_COMMITS" ] && [ -n "$OPEN" ] || \
      refuse 6 "the loop's own files alone are not a task: they land on the branch of $TASK_ID "\
"while its pull request is open"
  fi
fi
if ! landing_publishes "$LANDING" && branch_in_list "$BRANCH" "$PROTECTED_BRANCHES"; then
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
# through review.sh: review.sh counts the reviews of a task and stops at ASK_AFTER_RUNS,
# and nothing else counts landings, so retrying landing alone could rebuild and
# retest without end. The attempt is written before the gates start, so a gate
# run that hangs or is killed counts too, and taken back only once the commit is
# made or printed.
#
# At pr and merge there is no run: the landings of the task are counted instead, each
# in a folder of its own, land-<time>-<pid>, which is no review run. Each records the
# work it was to commit and, after red gates, what failed (`same`, as a review run
# has it: red_gates_same, common.sh). Past ASK_AFTER_RUNS that did not commit, since
# the count started, land.sh refuses and says what was red in each. When the newest
# three landings of the count, with none that committed between them, failed the
# same way — the same gates red with the same output but for its numbers — each of
# other work than the one before, that is the loop's the first time, as review.sh
# reads its runs: the script cannot tell fixes that do not close a failure from a
# machine that failed each time, and the loop can. It lands with the cause it found,
# --past-limit --because <why>, and --user-decided is refused there. When the limit
# comes again with the gates red that way, and every landing since the one that
# passed it ended so, the reason did not hold, and that is the user's: --past-limit
# --user-decided lands once more when they decided to go on, and takes no reason
# beside it. A landing that ended another way between — one that committed, other
# gates red — starts the row again. Anything else is the loop's — the same work
# again, other gates each time, gates that did not run, a landing that committed
# between: --past-limit takes its reason, --because <why>. A landing with
# --past-limit starts the count again, and the flag is accepted only at the limit.
# What passed it is kept in the landing's record.
if landing_opens_pull_request "$LANDING"; then
  ASK_AFTER_RUNS="$(read_conf "$CONFIG" ASK_AFTER_RUNS 5)"
  case "$ASK_AFTER_RUNS" in
    ''|*[!0-9]*|0*|??????????*)
      refuse 8 "ASK_AFTER_RUNS in $CONFIG must be a whole number from 1 to 999999999, "\
"not '$ASK_AFTER_RUNS'" ;;
  esac
  # The landings of a task that merged are not those of a new task under its id: where the
  # tree records that the id landed with its review, the landings made after it are read.
  LANDINGS="$(for record in "$REVIEW_DIR"/runs/land-*/landing.json; do
      [ -f "$record" ] || continue
      jq -c --arg id "$TASK_ID" --arg run "${record%/landing.json}" \
        'select(.task == $id) | . + {run: $run}' "$record" 2>/dev/null
    done | jq -sc --argjson after "$(task_landed_at "$TASK_ID")" "$JQ_LANDED_SINCE"'
      map(select(landed_since($after))) | sort_by(.time // 0)')"
  EPOCH="$(printf '%s' "$LANDINGS" | jq 'map(.epoch // 0) | max // 0')"
  # The landings of the count, oldest first, and those of them that did not commit.
  COUNTED_RUNS="$(printf '%s' "$LANDINGS" | jq -c --argjson epoch "$EPOCH" '
    map(select((.epoch // 0) == $epoch and .past_limit != true))')"
  NOT_LANDED_RUNS="$(printf '%s' "$COUNTED_RUNS" | jq -c '
    map(select(.result != "committed" and .result != "printed"))')"
  NOT_LANDED="$(printf '%s' "$NOT_LANDED_RUNS" | jq 'length')"
  PAST_LIMIT_KIND=""
  STOP=""
  if [ "$NOT_LANDED" -ge "$ASK_AFTER_RUNS" ]; then
    # Which stop it is, and whose. The newest three landings are read whatever came of
    # them: one that committed between two red ones shows that the gates do go green.
    # Three that failed the same way, each of other work than the one before, are the
    # loop's the first time. They are the user's when the landings ended that way ever
    # since one that passed this stop with the loop's reason: PASSED is that landing,
    # the newest of the row that is not its oldest, as review.sh reads its runs
    # (JQ_READING, common.sh). After such a landing the oldest of the three is compared
    # with the landing before it as well, which is PASSED when no other came between: a
    # landing again on the work of that one is a retry, so the three are not each after
    # a change, and the stop is the limit alone.
    STOP=landings
    STOP_WHOSE=loop
    PASSED=""
    if printf '%s' "$COUNTED_RUNS" | jq -e '
         .[-3:] | length == 3 and (.[2].same // null) != null
         and .[0].same == .[2].same and .[1].same == .[2].same
         and (.[0].work // null) != null and (.[1].work // null) != null
         and (.[2].work // null) != null
         and .[0].work != .[1].work and .[1].work != .[2].work' >/dev/null; then
      STOP=same-end-after-changes
      PASSED="$(printf '%s' "$LANDINGS" | jq -c \
        --arg oldest "$(printf '%s' "$COUNTED_RUNS" | jq -r '.[-3].run')" '
        reverse | . as $newest_first
        | ([.[] | (.same // null) == $newest_first[0].same] | (index(false) // length)) as $row
        | ([$newest_first[0:$row][]
            | .past_limit == true and .stop == "same-end-after-changes"
              and .user_decided != true] | index(true)) as $at
        | ([.[] | .run == $oldest] | index(true)) as $oldest_at
        | if $at != null and $at < $row - 1
          then $newest_first[$at] | {run, because}
            + {retry: ($newest_first[$oldest_at].work == $newest_first[$oldest_at + 1].work)}
          else empty end')"
      # `retry` is the last key of what jq prints here.
      case "$PASSED" in
        '') ;;
        *'"retry":true}') STOP=landings PASSED="" ;;
        *) STOP_WHOSE=user ;;
      esac
    fi
    COUNT_SAYS="$NOT_LANDED landings of $TASK_ID failed at or after their gates since the "\
"count started (ASK_AFTER_RUNS=$ASK_AFTER_RUNS)"
    if [ "$PAST_LIMIT" = false ] && [ "$STOP" = same-end-after-changes ]; then
      WAS_RED="$(red_gates_words \
        "$(printf '%s' "$NOT_LANDED_RUNS" | jq -r 'last.run')/gates.json")"
      if [ "$STOP_WHOSE" = loop ]; then
        refuse 3 "$COUNT_SAYS, the last 3 the same way after changes of the work: $WAS_RED" \
          loop "the changes between those landings did not move it, and land.sh cannot tell "\
"fixes that do not close a failure from a machine that failed each time — a device that went "\
"away, a stale build, a service that was down: find the cause in the output of the gates and "\
"mend it, then land with --past-limit --because \"<what the cause was, and what was done "\
"about it>\"; the same gates red that way at the next limit show that the reason did not hold"
      fi
      refuse 3 "$COUNT_SAYS, the last 3 the same way after changes of the work: $WAS_RED — "\
"$(printf '%s' "$PASSED" | jq -r '"as before \(.run | split("/") | last) passed this limit "
          + "with the loop'"'"'s reason, which did not hold: "
          + (.because // "none is recorded" | gsub("\\s+"; " "))')" \
        user:not-converging "the same gates stayed red through the cause the loop found and "\
"the fixes after it — whether to go on trying, to stop the task here, or to change what is "\
"asked of it; land.sh --past-limit --user-decided then lands once more"
    elif [ "$PAST_LIMIT" = false ]; then
      WAS_RED="$(printf '%s' "$NOT_LANDED_RUNS" | jq -r '.[].run' \
        | while IFS= read -r landed; do
            printf '%s; ' "$(red_gates_words "$landed/gates.json")"
          done)"
      refuse 3 "$COUNT_SAYS: ${WAS_RED%; }" \
        loop "run $REVIEW_DIR/gates.sh alone until it is green, then land with --past-limit "\
"--because \"<what was mended>\""
    elif [ "$STOP_WHOSE" = user ]; then
      [ "$USER_DECIDED" = true ] || {
        echo "this stop takes --user-decided: the work does not converge, and that is no "\
"decision of the loop — run without --past-limit to read it; --past-limit --user-decided "\
"lands once more" >&2
        exit 1
      }
      [ -z "$BECAUSE" ] || {
        echo "this stop takes --user-decided alone: --because is the loop's reason at a stop "\
"of its own, and nothing keeps words where the user decided — land again without it" >&2
        exit 1
      }
    elif [ "$STOP" = same-end-after-changes ]; then
      [ "$USER_DECIDED" = false ] || {
        echo "this stop is the loop's: --user-decided is for a stop that is the user's, and "\
"nothing is theirs to decide here — find the cause and land with --past-limit --because "\
"\"<what the cause was, and what was done about it>\"" >&2
        exit 1
      }
      [ -n "$BECAUSE" ] || {
        echo "--past-limit at this stop needs --because \"<what the cause was, and what was "\
"done about it>\" — run without --past-limit to read the stop" >&2
        exit 1
      }
    else
      [ -n "$BECAUSE" ] || [ "$USER_DECIDED" = true ] || {
        echo "--past-limit at this stop needs --because \"<what was mended>\" — run without "\
"--past-limit to read the stop" >&2
        exit 1
      }
    fi
    EPOCH=$((EPOCH + 1))
    PAST_LIMIT_KIND="$STOP_WHOSE"
  elif [ "$PAST_LIMIT" = true ]; then
    echo "--past-limit is only for a task at its limit: $TASK_ID has had $NOT_LANDED of "\
"$ASK_AFTER_RUNS landings that did not commit — run without it" >&2
    exit 1
  fi
  LAND_DIR="$REVIEW_DIR/runs/land-$(date +%Y%m%dT%H%M%S)-$$"
  mkdir -p "$LAND_DIR" || exit 1
  # landing_ends <result> [<same>]: the record of this landing. `work` is the fingerprint
  # of what it was to commit; `same`, after red gates, what failed (red_gates_same), null
  # otherwise. What a landing with --past-limit passed: `stop` names it — landings, the
  # limit alone, or same-end-after-changes — `past_limit_kind` says whose the stop was,
  # user or loop, `because` is the loop's reason, and `user_decided` is true when the
  # user decided to go on. All four are null on a plain landing.
  landing_ends() {
    jq -n --arg task "$TASK_ID" --argjson epoch "$EPOCH" --argjson past_limit "$PAST_LIMIT" \
      --arg result "$1" --arg work "$CURRENT_FINGERPRINT" --arg same "${2:-}" \
      --arg kind "$PAST_LIMIT_KIND" --arg stop "$STOP" --arg because "$BECAUSE" \
      --argjson user_decided "$USER_DECIDED" \
      '{task: $task, time: now, epoch: $epoch, past_limit: $past_limit, result: $result,
        work: $work, same: (if $same == "" then null else $same end),
        stop: (if $past_limit and $stop != "" then $stop else null end),
        past_limit_kind: (if $kind == "" then null else $kind end),
        because: (if $because == "" then null else $because end),
        user_decided: (if $user_decided then true else null end)}' >"$LAND_DIR/landing.json"
  }
  GATES_FILE="$LAND_DIR/gates.json"
else
  LANDING_REDS="$(cat "$RUN_DIR/landing-reds" 2>/dev/null)"
  case "$LANDING_REDS" in ''|*[!0-9]*) LANDING_REDS=0 ;; esac
  [ "$LANDING_REDS" -lt 2 ] || \
    refuse 3 "the landing of this run failed at or after its gates twice" \
      loop "run review.sh again: another landing of this run would repeat uncounted"
  landing_ends() {
    case "$1" in
      unfinished) printf '%s\n' "$((LANDING_REDS + 1))" >"$RUN_DIR/landing-reds" ;;
      committed | printed) printf '%s\n' "$LANDING_REDS" >"$RUN_DIR/landing-reds" ;;
    esac
  }
  GATES_FILE="$RUN_DIR/gates.land.json"
fi
landing_ends unfinished

# REVIEW_BASE: where the change the gates look at starts (gates.sh).
REVIEW_BASE="$CHANGE_BASE" "$REVIEW_DIR/gates.sh" "$GATES_FILE" >/dev/null 2>&1
GATES_EXIT=$?

# "Could not run the gates" and "the gates are red" are different refusals, and
# only the second one means go fix the code.
if [ "$GATES_EXIT" -ge 126 ] || \
  ! jq -e 'type == "object"' "$GATES_FILE" >/dev/null 2>&1; then
  landing_ends red
  refuse 3 "$REVIEW_DIR/gates.sh did not run (exit $GATES_EXIT) — "\
"the gates were never confirmed green"
fi

if [ "$GATES_EXIT" -ne 0 ]; then
  landing_ends red "$(red_gates_same "$GATES_FILE")"
  FAILED_GATES="$(jq -r 'to_entries[] | select(.value.status == "fail") | .key' \
    "$GATES_FILE" | tr '\n' ' ')"
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

GATES_TRAILER="$(jq -r '[to_entries[] | "\(.key)=\(.value.status)"] | join(",")' \
  "$GATES_FILE")"

# Trailers are self-contained: the run directory is local and gitignored, so
# the commit carries the audit facts themselves rather than a path to them. At pr
# and merge the commit is reviewed after it is made: the audit facts go into the
# squash commit (publish.sh --merge), and the message says which commit of the
# task this is — its first, the changes after a review, or the loop's files alone.
if landing_opens_pull_request "$LANDING"; then
  if [ -z "$MESSAGE" ]; then
    if [ "$RECORDS_ONLY" -eq 1 ]; then
      MESSAGE="$TASK_ID: records"
    elif [ -n "$TASK_COMMITS" ]; then
      REVIEWS_ON_BRANCH="$(review_runs_of "$TASK_ID" | while IFS= read -r run; do
          head="$(jq -r 'select(.pr_url != null) | .head // empty' "$run/meta.json")"
          [ -z "$head" ] || ! git merge-base --is-ancestor "$head" HEAD 2>/dev/null || echo "$run"
        done | grep -c .)"
      if [ "$REVIEWS_ON_BRANCH" -gt 0 ]; then
        MESSAGE="$TASK_ID: changes after review $REVIEWS_ON_BRANCH"
      else
        MESSAGE="$TASK_ID: changes before review"
      fi
    fi
  fi
  COMMIT_BODY="$(printf 'Task-Id: %s\nGates: %s\n' "$TASK_ID" "$GATES_TRAILER")"
else
  REJECTED_COUNT=\
"$(jq '[.verdicts[] | select(.verdict == "reject")] | length' "$RUN_DIR/verdicts.json")"
  FINDING_COUNT="$(jq '.verdicts | length' "$RUN_DIR/verdicts.json")"
  COMMIT_BODY="$(printf 'Task-Id: %s\nGates: %s\n'\
'Findings: %s reviewed, %s rejected, 0 outstanding at %s+\n'\
'Exit-Criteria: %s verified\nReview-Run: %s (local)\n' \
    "$TASK_ID" "$GATES_TRAILER" "$FINDING_COUNT" "$REJECTED_COUNT" "$THRESHOLD" \
    "$CRITERIA_COUNT" "$(basename "$RUN_DIR")")"
fi
if [ -z "$MESSAGE" ]; then
  MESSAGE="$TASK_ID: $(jq -r '.title // .id' "$TASK_FILE")"
fi

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
  landing_ends printed
  qa_asks "$TASK_ID"
  exit 0
fi

# The gates ran since condition 2 was checked, and that takes minutes. Re-check
# rather than trusting the rule that gates must not modify the tree.
[ "$(tree_fingerprint)" = "$CURRENT_FINGERPRINT" ] || \
  refuse 2 "the tree changed while the gates ran — review again before landing"
[ -z "$RUN_DIR" ] || marks_checked_by_run "$RUN_DIR"

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
# the task's commit — including `.review/land.conf` and, with WITH_RECORDS=no,
# `.review/REVIEW_POLICY.md`, which are filtered out of CHANGED_FILES above and so
# are never scope-checked. The files that define the pipeline's limits are exactly
# the ones that must not be able to change unnoticed in a commit the pipeline made
# by itself: the policy lands only by WITH_RECORDS=yes, among the files the commit names.
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

landing_ends committed
echo "landed $TASK_ID on $LANDING_BRANCH: ${#TO_COMMIT[@]} file(s)"
qa_asks "$TASK_ID"

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
    if landing_opens_pull_request "$LANDING"; then
      echo "  if code has to change, that is a new pass of the loop on this branch: "\
"the work, then land.sh, which adds a commit, then review.sh" >&2
    else
      echo "  if code has to change, that is a new pass of the loop on this branch: "\
"the work, review.sh, then land.sh, which adds a commit" >&2
    fi
  fi
  exit 4
fi
