#!/usr/bin/env bash
#
# land.sh — the only thing in the pipeline that commits.
#
# Runs FROM THE SUBMODULE and is deliberately NOT overridable by projects: it is
# the one file with write authority, so it must not be widenable locally.
#
# It has no code path for push, amend, --force, rebase, checkout, reset, stash,
# clean, or branch switching. It stages the task's declared files on the current
# branch and commits. That is all it can do.
#
# It refuses (exit 3) unless all eight landing conditions hold. A ninth switch,
# LANDING, then decides whether it commits or only prints the commit — that one
# is not a refusal and exits 0. See TASK_LOOP.md § Landing.
#
# Usage, from the project root:
#   land.sh --task-file <task.json> --run <run-dir> [--message "..."] [--dry-run]
#
# Exit codes:
#   0  committed (or printed the commit, in dry-run / LANDING=off)
#   3  refused — a landing condition failed, with the reason on stderr
#   1  usage or environment error
#
# Requires: jq >= 1.6, git

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
LANDING="$(read_conf "$CONFIG" LANDING off)"
# Projects may add protected branches; they cannot remove the built-in ones.
PROTECTED_BRANCHES="main master $(read_conf "$CONFIG" PROTECTED_BRANCHES "")"

refuse() {
  echo "LANDING REFUSED — condition $1: $2" >&2
  exit 3
}

TASK_ID="$(jq -r '.id' "$TASK_FILE")"
[ -n "$TASK_ID" ] && [ "$TASK_ID" != "null" ] || { echo "task file has no .id" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 1. The run directory is a completed review run.
#    Missing files must never read as "nothing was found" — that would let any
#    empty directory authorise a commit.
# ---------------------------------------------------------------------------

for artifact in meta.json verdicts.json approved.json escalated.json; do
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
# scope, and landing checks another's. `.review/` is outside the fingerprint, so
# nothing else would catch a swapped task file.
# Both sides are absolute: run.sh resolves the path before recording it, and
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
# 3. Gates re-run green NOW. Cheap insurance, and it catches an environment
#    that drifted between review and landing.
# ---------------------------------------------------------------------------

[ -x "$REVIEW_DIR/gates.sh" ] || \
  refuse 3 "$REVIEW_DIR/gates.sh is missing or not executable — the gates cannot be confirmed"

"$REVIEW_DIR/gates.sh" "$RUN_DIR/gates.land.json" >/dev/null 2>&1
GATES_EXIT=$?

# "Could not run the gates" and "the gates are red" are different refusals, and
# only the second one means go fix the code.
if [ "$GATES_EXIT" -ge 126 ] || ! jq -e 'type == "object"' "$RUN_DIR/gates.land.json" >/dev/null 2>&1; then
  refuse 3 "$REVIEW_DIR/gates.sh did not run (exit $GATES_EXIT) — the gates were never confirmed green"
fi

if [ "$GATES_EXIT" -ne 0 ]; then
  FAILED_GATES="$(jq -r 'to_entries[] | select(.value.status == "fail") | .key' \
    "$RUN_DIR/gates.land.json" | tr '\n' ' ')"
  refuse 3 "gates are red at landing time: ${FAILED_GATES:-unknown}"
fi

# ---------------------------------------------------------------------------
# 4 & 5. No outstanding findings, no pending escalations.
# ---------------------------------------------------------------------------

APPROVED_COUNT="$(require_array_length "$RUN_DIR/approved.json")" || \
  refuse 4 "approved.json is unreadable — refusing to assume it is empty"
[ "$APPROVED_COUNT" -eq 0 ] || \
  refuse 4 "$APPROVED_COUNT accepted finding(s) at or above $THRESHOLD are unresolved"

ESCALATED_COUNT="$(require_array_length "$RUN_DIR/escalated.json")" || \
  refuse 5 "escalated.json is unreadable — refusing to assume it is empty"

# An escalation is answered, not waited out. The human's answer is recorded in
# escalations-answered.json — one entry per escalated finding — and only then
# does landing proceed. Without this an escalated finding (every replication
# finding, for one) could never land at all: re-running the review reproduces it.
if [ "$ESCALATED_COUNT" -gt 0 ]; then
  ANSWERS="$RUN_DIR/escalations-answered.json"
  [ -f "$ANSWERS" ] || \
    refuse 5 "$ESCALATED_COUNT escalation(s) are waiting on a human — record the answers in $ANSWERS"
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
    refuse 5 "could not read the escalation answers in $ANSWERS — refusing to assume they are answered"
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
CHANGED_FILES="$( { git diff --name-only; git diff --cached --name-only;
                    git ls-files --others --exclude-standard; } \
                  | sort -u | grep -v '^\.review/' )"
[ -n "$CHANGED_FILES" ] || refuse 6 "nothing to commit outside .review/"

OUT_OF_SCOPE=""
IN_SCOPE=()
while IFS= read -r file; do
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

# ---------------------------------------------------------------------------
# 7. Every exit criterion carries an explicit verification claim.
#    Machine-checkable criteria belong in gates; the rest must at least be
#    stated, so the claim lands in the commit and can be audited later.
# ---------------------------------------------------------------------------

CRITERIA_COUNT="$(jq '.exit_criteria | length' "$TASK_FILE")"
[ "$CRITERIA_COUNT" -gt 0 ] || refuse 7 "task $TASK_ID declares no exit criteria"

UNVERIFIED="$(jq -r '[.exit_criteria[] | select((.verified_by // "") == "")] | length' "$TASK_FILE")"
[ "$UNVERIFIED" -eq 0 ] || \
  refuse 7 "$UNVERIFIED exit criterion/criteria have no verified_by claim"

# ---------------------------------------------------------------------------
# 8. Never onto a protected branch, and never onto a detached HEAD.
# ---------------------------------------------------------------------------

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
[ "$BRANCH" != "HEAD" ] || \
  refuse 8 "HEAD is detached — a commit here would be unreachable from any branch"
for protected in $PROTECTED_BRANCHES; do
  [ "$BRANCH" = "$protected" ] && \
    refuse 8 "current branch is $BRANCH — landing never touches a protected branch"
done

# ---------------------------------------------------------------------------
# 9. Landing is explicitly delegated.
# ---------------------------------------------------------------------------

if [ "$LANDING" != "on" ]; then
  DRY_RUN=1
fi

# ---------------------------------------------------------------------------
# Commit
# ---------------------------------------------------------------------------

GATE_SUMMARY="$(jq -r '[to_entries[] | "\(.key)=\(.value.status)"] | join(",")' \
  "$RUN_DIR/gates.land.json")"
REJECTED_COUNT="$(jq '[.verdicts[] | select(.verdict == "reject")] | length' "$RUN_DIR/verdicts.json")"
FINDING_COUNT="$(jq '.verdicts | length' "$RUN_DIR/verdicts.json")"

if [ -z "$MESSAGE" ]; then
  MESSAGE="$TASK_ID: $(jq -r '.title // .id' "$TASK_FILE")"
fi

# Trailers are self-contained: the run directory is local and gitignored, so
# the commit carries the audit facts themselves rather than a path to them.
COMMIT_BODY="$(printf 'Task-Id: %s\nGates: %s\nFindings: %s reviewed, %s rejected, 0 outstanding at %s+\nExit-Criteria: %s verified\nReview-Run: %s (local)\n' \
  "$TASK_ID" "$GATE_SUMMARY" "$FINDING_COUNT" "$REJECTED_COUNT" "$THRESHOLD" \
  "$CRITERIA_COUNT" "$(basename "$RUN_DIR")")"

if [ "$DRY_RUN" -eq 1 ]; then
  if [ "$LANDING" != "on" ]; then
    echo "LANDING=off in $CONFIG — not committing. Run this yourself:"
  else
    echo "dry run — not committing. The commit would be:"
  fi
  echo
  printf '  git add --'
  printf ' %q' "${IN_SCOPE[@]}"
  printf '\n'
  printf '  git commit --only -m %q -m %q --' "$MESSAGE" "$COMMIT_BODY"
  printf ' %q' "${IN_SCOPE[@]}"
  printf '\n'
  exit 0
fi

# The gates ran since condition 2 was checked, and that takes minutes. Re-check
# rather than trusting the rule that gates must not modify the tree.
[ "$(tree_fingerprint)" = "$REVIEWED_FINGERPRINT" ] || \
  refuse 2 "the tree changed while the gates ran — review again before landing"

# `git add` first, because --only alone cannot commit a path git has never seen;
# then --only with the same pathspec, because a bare `git commit` writes the
# WHOLE INDEX. Anything the user had staged beforehand would ride along inside
# the task's commit — including `.review/land.conf` and `.review/REVIEW_POLICY.md`,
# which are filtered out of CHANGED_FILES above and so are never scope-checked.
# The files that define the pipeline's limits are exactly the ones that must not
# be able to change unnoticed in a commit the pipeline made by itself.
git add -- "${IN_SCOPE[@]}" || { echo "staging failed" >&2; exit 1; }
git commit --only -m "$MESSAGE" -m "$COMMIT_BODY" -- "${IN_SCOPE[@]}" || {
  # The add already happened, so the task's files are staged and the commit is
  # not there — a pre-commit hook rejecting the change is the usual cause. This
  # script has no unstage path on purpose (it may commit and nothing else), so
  # say plainly what state the tree is in rather than leaving it to be found.
  echo "commit failed — the task's files are left STAGED, nothing was committed" >&2
  echo "  a pre-commit hook is the usual cause; its output is above" >&2
  echo "  to undo the staging yourself:" >&2
  printf '    git restore --staged --'  >&2
  printf ' %q' "${IN_SCOPE[@]}" >&2
  printf '\n' >&2
  exit 1
}

echo "landed $TASK_ID on $BRANCH: ${#IN_SCOPE[@]} file(s)"
