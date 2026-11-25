#!/usr/bin/env bash
#
# review.sh — one review pass: gates → reviewer → maintainer triage.
#
# The loop around this (rounds, landing, advancing) is driven by /maintain.
# Landing lives in land.sh.
#
# Runs FROM THE SUBMODULE. Never copy or edit this file: it is shared across
# projects and updates with `git submodule update --remote`.
#
# What it reads from your project (.review/ — yours to edit):
#   gates.sh, e2e.sh, REVIEW_POLICY.md, land.conf, and any prompts/ or schemas/
#   you choose to override.
# What it reads from the submodule (shared defaults):
#   prompts/, schemas/ — used whenever .review/ has no override.
#
# Usage, from your project root:
#   review.sh [--base <ref>] [--threshold <sev>] [--task-file <task.json>]
#             [--past-limit [--because <why>] [--user-decided]] [--dry-run]
#
# Without --base, reviews the uncommitted work — exactly what land.sh commits.
# With --base <ref>, reviews the whole branch since that ref (a final pass).
# At LANDING=pr and merge, reviews the task's pull request instead: its change since
# the merge base with the base branch, committed and pushed by land.sh; the run is
# then posted there (pr-post.sh run). --dry-run reviews the uncommitted work, as at
# push, and posts nothing.
#
# Exit codes:
#   0  clean — gates green, nothing accepted above the threshold
#   2  gates or end-to-end tests red — send the executor back with the output,
#      no LLM review
#   3  accepted findings remain — hand them to the executor
#   4  escalations — answered before landing (maintain, step 7)
#   5  review unusable — every finding failed quote verification; re-run
#   6  nothing ran: the task is at its limit of reviews, or the script read a
#      circle in its runs or in its /qa records — its last line says whose turn
#      it is (--past-limit runs once more)
#   1  pipeline error, including any malformed agent output (fails closed), or
#      no working end-to-end harness; at LANDING=pr and merge also work that is not
#      committed, a pull request that is not at HEAD, or a run that could not be
#      posted on it
#
# Requires: jq >= 1.6, git, and whichever agent CLIs REVIEWER_CMD / MAINTAINER_CMD use.
# VERIFY CLI FLAGS against your installed versions before first use.

set -uo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 1
# shellcheck source=common.sh
. "$LIB_DIR/common.sh"

BASE=""
THRESHOLD_CLI=""
TASK_FILE=""
PAST_LIMIT=false
BECAUSE=""
BECAUSE_GIVEN=false
USER_DECIDED=false
DRY_RUN=false

while [ $# -gt 0 ]; do
  case "$1" in
    --base)       require_value "--base" $#; BASE="$2"; shift 2 ;;
    --threshold)  require_value "--threshold" $#; THRESHOLD_CLI="$2"; shift 2 ;;
    --task-file)  require_value "--task-file" $#; TASK_FILE="$2"; shift 2 ;;
    --past-limit) PAST_LIMIT=true; shift ;;
    --because)    require_value "--because" $#; BECAUSE_GIVEN=true; BECAUSE="$2"; shift 2 ;;
    --user-decided) USER_DECIDED=true; shift ;;
    --dry-run)    DRY_RUN=true; shift ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done

# What passes a stop goes with --past-limit alone: the loop's own reason, or that the user
# decided to go on. --user-decided takes no words: nothing keeps what a person said. The
# reason is read without the blanks around it, so one made of blanks is none.
BECAUSE="${BECAUSE#"${BECAUSE%%[![:space:]]*}"}"
BECAUSE="${BECAUSE%"${BECAUSE##*[![:space:]]}"}"
if [ "$PAST_LIMIT" = false ]; then
  [ "$BECAUSE_GIVEN" = false ] || { echo "--because goes with --past-limit" >&2; exit 1; }
  [ "$USER_DECIDED" = false ] || { echo "--user-decided goes with --past-limit" >&2; exit 1; }
fi

# A task file that does not exist must be a usage error, never a silent
# downgrade. Without this the maintainer is told "no task file supplied" and
# triages with no scope at all, while meta.json still records the path — so the
# run looks scoped to landing and never was.
if [ -n "$TASK_FILE" ]; then
  [ -f "$TASK_FILE" ] || { echo "no such task file: $TASK_FILE" >&2; exit 1; }
  # Resolved before the cd below, so the path means the same thing here, in
  # meta.json, and later in land.sh.
  TASK_FILE="$(abspath "$TASK_FILE")" || exit 1
fi

PROJECT_ROOT="$(git rev-parse --show-toplevel)" || exit 1

# Running from inside the CodingStandards checkout resolves PROJECT_ROOT to the
# standards repo itself, which has no .review/ and no diff worth reviewing.
if [ -f "$PROJECT_ROOT/TASK_LOOP.md" ] && \
  [ -f "$PROJECT_ROOT/templates/review/lib/review.sh" ]; then
  echo "run this from your project root, not from inside the CodingStandards checkout" >&2
  exit 1
fi

cd "$PROJECT_ROOT" || exit 1

REVIEW_DIR=".review"

# Project-owned. No sensible default exists — these encode the stack and the taste.
for required in gates.sh REVIEW_POLICY.md; do
  if [ ! -f "$REVIEW_DIR/$required" ]; then
    echo "missing $REVIEW_DIR/$required — run /maintain --init, or copy" >&2
    echo "  $(cd "$LIB_DIR/../project" 2>/dev/null && pwd)/. into $REVIEW_DIR/" >&2
    exit 1
  fi
done

# Checked separately from existence: a gates.sh that cannot be executed exits
# 126, which is indistinguishable from a failing gate downstream, and the loop
# would send the executor off to fix code on the strength of an empty gate
# report. Copying the templates through an archive or a templating step is
# enough to lose the bit.
[ -x "$REVIEW_DIR/gates.sh" ] || {
  echo "$REVIEW_DIR/gates.sh is not executable — chmod +x $REVIEW_DIR/gates.sh" >&2
  exit 1
}

# The task file has to live under `.review/`. That directory, the end-to-end harness
# apart, is the one place excluded from the tree fingerprint, and the loop writes
# `verified_by` into the task file AFTER this review has run. Anywhere else, that write changes
# the fingerprint and landing refuses with "the tree changed after this review" —
# on every task, with nothing in the message pointing at the real cause.
if [ -n "$TASK_FILE" ]; then
  case "$TASK_FILE" in
    "$PROJECT_ROOT/$REVIEW_DIR"/*) ;;
    *) echo "the task file must live under $REVIEW_DIR/ — it is the only path" >&2
       echo "  outside the tree fingerprint, and filling in verified_by after this" >&2
       echo "  review would otherwise make landing refuse every time" >&2
       exit 1 ;;
  esac
fi

# Every repetition of the loop is another run of this script: a new round, a
# re-run after red gates or an unusable review, a review again after /qa or a
# landing refusal. Nothing else counts them, and none of those paths has a limit
# of its own, so a session nobody watches could repeat one of them for as long as
# the account pays. So the script reads the runs of the task and its /qa records
# before it makes a new run (task_runs_json, qa_records_of and JQ_READING,
# common.sh) and stops, with exit 6 and nothing run, in five cases:
#   a finding in a circle  a finding of the newest review was accepted at the same
#                          place in three reviews in a row, each of other work than
#                          the one before; once the user decided to go on, the stop
#                          is lifted until the next review
#   a case in a circle     a case the newest /qa failed has failed on three works of
#                          the task, counted as pr-post.sh qa counts them; once the
#                          user decided to go on, the stop is lifted until the next
#                          /qa
#   the same end           three runs in a row ended the same way: the same gates
#                          red with the same output, the same end-to-end tests red,
#                          the same missing harness, an unusable review; after a run
#                          that passed it where the work had changed each time,
#                          three more
#   the limit of reviews   ASK_AFTER_RUNS reviews since the count started: the runs
#                          that made a review, not those that ended before one
#   the limit of runs      ASK_AFTER_RUNS runs in a row with no review, whatever
#                          ended them
# Each stop prints what was read and ends with one line that says whose turn it is
# (turn). A circle of the work — the finding or the case — is the user's: --past-limit
# --user-decided runs once more when they decided to go on, and takes no reason
# beside it. Gates or end-to-end tests that stayed red the same way while the work
# changed each time are the loop's the first time: the script cannot tell fixes that
# do not close a failure from a device that went away each time, a stale build or a
# service that was down, and the loop has the logs. It passes that stop with the
# cause it found, --past-limit --because <why>, and --user-decided is refused
# there. Three more runs in a row with that end after such a pass, each after a
# change, show that the reason did not hold: then it is the user's. Every other
# stop is the loop's, since a count alone is never a question. Where the script
# reads that the work converges — no finding came back and the reviews do not accept
# as many as before or more — --past-limit alone runs once more; where it cannot
# read that, --past-limit takes the loop's own reason, --because <why>. What passed
# a stop is kept in the run and shown on the pull request. A run with --past-limit
# starts the count of reviews again from zero, and the flag is accepted only at a
# stop, so one left in the command fails on the next run instead of switching the
# count off.
ASK_AFTER_RUNS="$(read_conf "$REVIEW_DIR/land.conf" ASK_AFTER_RUNS 5)"
case "$ASK_AFTER_RUNS" in
  ''|*[!0-9]*|0*|??????????*)
    echo "ASK_AFTER_RUNS in $REVIEW_DIR/land.conf must be a whole number from 1 to 999999999, "\
"not '$ASK_AFTER_RUNS'" >&2
    exit 1 ;;
esac

TASK_ID=""
if [ -n "$TASK_FILE" ]; then
  TASK_ID="$(jq -er '.id // empty' "$TASK_FILE" 2>/dev/null)" && [ -n "$TASK_ID" ] || {
    echo "$TASK_FILE is not JSON or has no .id — runs are counted per task" >&2
    exit 1
  }
fi

# What a run's check that was not green came to, in words: what_failed <run> <failed>,
# <failed> as task_runs_json names it.
what_failed() {
  case "$2" in
    gates)
      printf 'gates red: %s, the same output each time but for its numbers' \
        "$(jq -r '[to_entries[] | select(.value.status == "fail" and .value.blocking != false)
                   | .key] | join(", ")' "$1/gates.json" 2>/dev/null)" ;;
    e2e)
      printf 'end-to-end tests red: %s' \
        "$(jq -r '[.reasons[]?] | join("; ")' "$1/e2e.json" 2>/dev/null)" ;;
    harness)
      printf 'no working end-to-end harness: %s' \
        "$(jq -r '[.reasons[]?] | join("; ")' "$1/e2e.json" 2>/dev/null)" ;;
    unusable) printf 'the review was unusable' ;;
  esac
}

# The stop in force, as $READING has it: what was read, on stdout, then whose turn it is.
say_stop() {
  local newest failed row came_back accepted what case_id times qa_runs line
  local cases="" fixes=0 more=""
  IFS=$'\t' read -r newest failed row came_back accepted < <(printf '%s' "$READING" | jq -r '
    [.newest.run // "-", .newest.failed // "-",
     (if .stop == "finding" then ([.came_back[].row] | max) else .same_end_changed end),
     (.came_back | length), (.accepted | add // 0)] | @tsv')
  case "$STOP" in
    reviews)
      printf '%s' "$READING" | jq -r --arg id "$TASK_ID" --arg limit "$ASK_AFTER_RUNS" '
        "LIMIT OF REVIEWS — \($id) has had \(.reviews) reviews since the count started, "
          + "\(.runs_in_all) runs in all (ASK_AFTER_RUNS=\($limit)); nothing ran.",
        "   accepted by each review, oldest first: \(.accepted | map(tostring) | join(", "))",
        (.came_back[]
         | "   came back after its fix: \(.file):\(.line) (\(.category)), in \(.row) reviews "
           + "in a row (\(.runs | map(split("/") | last) | join(", ")))"),
        (if .not_fewer then "   they do not get fewer" else empty end)'
      if [ "$STOP_WHOSE" = converging ] && [ "$accepted" -eq 0 ]; then
        turn loop "no review accepted a finding, so the reviews are not what repeats: if a "\
"landing or /qa sends the task back each time, find that cause first — then run again with "\
"--past-limit, which runs once more and starts the count again"
      elif [ "$STOP_WHOSE" = converging ]; then
        turn loop "no finding came back after its fix: the reviews found different things, "\
"and each was fixed — run again with --past-limit, which runs once more and starts the count "\
"again"
      elif [ "$came_back" -gt 0 ]; then
        turn loop "a finding came back after its fix: find why the fix did not hold "\
"(maintain, step 6), then run again with --past-limit --because \"<why it came back, and what "\
"is different now>\""
      else
        turn loop "the findings differ and do not get fewer: judge whether the work moves "\
"toward the goal (maintain, step 6) — each was a defect of its own and is fixed: run again "\
"with --past-limit --because \"<what moves>\"; each fix brings the next, or you cannot tell: "\
"the work does not converge, and that is a question, asked with the lines above"
      fi ;;
    finding)
      # Every row ends at the newest review, which need not be the newest run. A run's
      # diff.patch is the whole change that review saw, not one fix.
      printf '%s' "$READING" | jq -r --arg id "$TASK_ID" '
        "NOT CONVERGING — the fixes of \($id) do not close a finding of the review; nothing ran.",
        (.came_back[] | select(.row >= 3)
         | "   \(.file):\(.line) (\(.category)) `\(.quote)` was accepted in \(.row) reviews in "
           + "a row, each after a change of the work: "
           + (.runs | map(split("/") | last) | join(", "))),
        "   what it says: \([.came_back[] | select(.row >= 3) | .runs | last] | first)"
          + "/approved.json; the whole change as each review saw it: the diff.patch of each of "
          + "those runs — what a fix changed is what differs between two"'
      turn user:not-converging "the same finding came back after each of $((row - 1)) fixes "\
"— whether to go on trying, to stop the task here, or to rule that it is no problem (/policy); "\
"--past-limit --user-decided then runs once more"
      ;;
    case)
      echo "NOT CONVERGING — the fixes of $TASK_ID do not close a case of /qa; nothing ran."
      while IFS=$'\t' read -r case_id times qa_runs; do
        [ -n "$case_id" ] || continue
        echo "   $case_id failed in $times /qa of this task, each on other work: $qa_runs"
        line="$(case_line "$case_id")"
        if [ -n "$line" ]; then
          echo "   what it expects: qa/test-cases.md:$line; what /qa saw each time: the "\
"report.md of each"
        else
          echo "   qa/test-cases.md has no $case_id; what /qa saw each time: the report.md "\
"of each"
        fi
        if [ -z "$cases" ]; then
          fixes=$((times - 1))
        else
          [ "$((times - 1))" -eq "$fixes" ] || more=" or more"
          [ "$((times - 1))" -ge "$fixes" ] || fixes=$((times - 1))
        fi
        cases="${cases:+$cases, }$case_id"
      done < <(printf '%s' "$READING" | jq -r '.qa_back[] | select(.times >= 3)
        | [.case, .times, (.runs | map(split("/") | last) | join(", "))] | @tsv')
      turn user:not-converging "$cases failed again after each of $fixes fixes$more — "\
"whether to go on trying, to stop the task here, or to change what the case expects; "\
"--past-limit --user-decided then runs once more"
      ;;
    same-end-after-changes)
      what="$(what_failed "$newest" "$failed")"
      if [ "$STOP_WHOSE" = user ]; then
        echo "NOT CONVERGING — $TASK_ID ended the same way in $row more runs in a row, each "\
"after a change of the work, since "\
"$(printf '%s' "$READING" | jq -r '.passed.run | split("/") | last') passed this stop; nothing ran."
        echo "   $what ($(basename "$newest"))"
        printf '%s' "$READING" | jq -r '"   the loop'"'"'s reason then, which did not hold: "
          + (.passed.because // "none is recorded" | gsub("\\s+"; " "))'
        turn user:not-converging "the same check stayed red through the cause the loop found "\
"and $row more fixes — whether to go on trying, to stop the task here, or to change what is "\
"asked of it; --past-limit --user-decided then runs once more"
      else
        echo "STOPPED — $TASK_ID ended the same way in $row runs in a row, each after a "\
"change of the work; nothing ran."
        echo "   $what ($(basename "$newest"))"
        turn loop "the changes between those runs did not move it, and review.sh cannot tell "\
"fixes that do not close a failure from a machine that failed each time — a device that went "\
"away, a stale build, a service that was down: find the cause in the output of those runs and "\
"mend it, then run again with --past-limit --because \"<what the cause was, and what was done "\
"about it>\"; three more runs in a row that end this way after it, each after a change, show "\
"that the reason did not hold"
      fi ;;
    same-end)
      what="$(what_failed "$newest" "$failed")"
      echo "STOPPED — $TASK_ID ended the same way in "\
"$(printf '%s' "$READING" | jq -r '.same_end_row') runs in a row; nothing ran."
      echo "   $what ($(basename "$newest"))"
      turn loop "a retry does not mend it — find the cause in that output: in the code, "\
"fix it; in the machine, restore the tool or the device; then run again with --past-limit "\
"--because \"<what was mended>\""
      ;;
    runs)
      printf '%s' "$READING" | jq -r --arg id "$TASK_ID" --arg limit "$ASK_AFTER_RUNS" '
        {"gates-red": "gates red", "e2e-red": "end-to-end tests red",
         "no-harness": "no working end-to-end harness", "unusable": "an unusable review",
         "error": "an error"} as $words
        | "LIMIT OF RUNS — the last \(.no_review_row) runs of \($id) made no review "
          + "(ASK_AFTER_RUNS=\($limit)); nothing ran.",
        "   how they ended, oldest first: \(.ends | map($words[.] // .) | join("; "))"'
      turn loop "find what they share before another run, then run again with --past-limit "\
"--because \"<what was mended>\""
      ;;
  esac
}

# EPOCH is the count number: the highest one among the task's runs, one more for a
# --past-limit run. The reviews counted are the plain ones of the highest epoch, so the
# count depends neither on the order of the run directories — their names come from the
# local clock and the process id, and neither sorts by time reliably — nor on old run
# directories having been deleted.
EPOCH=null
REVIEWS_SO_FAR=0
STOP=-
STOP_WHOSE=-
PAST_LIMIT_KIND=""
if [ -n "$TASK_ID" ]; then
  # Runs of a task that landed are not the runs of a new task under its id: where the tree
  # records that a landing of the id committed with its review, the runs and the /qa
  # records made after it are read (task_landed_at, common.sh).
  LANDED_AT="$(task_landed_at "$TASK_ID")"
  RUNS="$(task_runs_json "$TASK_ID" "$LANDED_AT")" || {
    echo "the runs of $TASK_ID could not be read; nothing ran" >&2
    exit 1
  }
  # A /qa record that cannot be read, or one of the task that does not hold, is never read
  # as no failure: qa_records_of says which and what, and nothing runs.
  QA="$(qa_records_of "$TASK_ID" | qa_cases_of "$LANDED_AT")" && [ -n "$QA" ] || {
    echo "the /qa records of $TASK_ID could not be read: a qa.json is unreadable or not "\
"{task, failures: [{case: TC-nnn}]}, or its items do not hold; the line before this one says "\
"what; nothing ran" >&2
    exit 1
  }
  READING="$(task_reading "$RUNS" "$QA" "$ASK_AFTER_RUNS")" && [ -n "$READING" ] || {
    echo "the runs of $TASK_ID could not be read; nothing ran" >&2
    exit 1
  }
  IFS=$'\t' read -r STOP STOP_WHOSE REVIEWS_SO_FAR EPOCH < <(printf '%s' "$READING" \
    | jq -r '[.stop // "-", .whose // "-", .reviews, .epoch] | @tsv')
  if [ "$PAST_LIMIT" = true ]; then
    case "$STOP_WHOSE" in
      -)
        echo "--past-limit is only for a task at its limit: $TASK_ID has had "\
"$REVIEWS_SO_FAR of $ASK_AFTER_RUNS reviews, and review.sh reads no circle — run without it" >&2
        exit 1 ;;
      user)
        [ "$USER_DECIDED" = true ] || {
          echo "this stop takes --user-decided: the work does not converge, and that is no "\
"decision of the loop — run without --past-limit to read it; --past-limit --user-decided "\
"runs once more" >&2
          exit 1
        }
        [ -z "$BECAUSE" ] || {
          echo "this stop takes --user-decided alone: --because is the loop's reason at a "\
"stop of its own, and nothing keeps words where the user decided — run again without it" >&2
          exit 1
        } ;;
      loop)
        if [ "$STOP" = same-end-after-changes ]; then
          [ "$USER_DECIDED" = false ] || {
            echo "this stop is the loop's: --user-decided is for a stop that is the user's, "\
"and nothing is theirs to decide here — find the cause and run again with --past-limit "\
"--because \"<what the cause was, and what was done about it>\"" >&2
            exit 1
          }
          [ -n "$BECAUSE" ] || {
            echo "--past-limit at this stop needs --because \"<what the cause was, and what "\
"was done about it>\" — run without --past-limit to read the stop" >&2
            exit 1
          }
        fi
        [ -n "$BECAUSE" ] || [ "$USER_DECIDED" = true ] || {
          echo "--past-limit at this stop needs --because \"<what moves toward the goal>\" "\
"— run without --past-limit to read the stop" >&2
          exit 1
        } ;;
    esac
    EPOCH=$((EPOCH + 1))
    PAST_LIMIT_KIND="$STOP_WHOSE"
  elif [ "$STOP" != - ]; then
    say_stop
    exit 6
  fi
elif [ "$PAST_LIMIT" = true ]; then
  echo "--past-limit needs --task-file: runs are counted per task" >&2
  exit 1
fi

# The disk. Builds, simulators and recordings take gigabytes, and a disk that fills
# up stops the user's own work too, which they learn only when they come back. Below
# MIN_FREE_GB free, nothing runs; the run is not counted. Whose turn it is is read from
# what the loop left under runs: where that is as much as is missing, the loop deletes
# it; where it is less, only the user can free the disk. The measure is of all that is
# under runs, and the loop may delete only a part of it (maintain, step 12): the script
# cannot tell that part, so the loop's line ends with whose the stop is once nothing of it
# is left — the user's, in the words of that kind (turn_words).
MIN_FREE_GB="$(read_conf "$REVIEW_DIR/land.conf" MIN_FREE_GB 15)"
case "$MIN_FREE_GB" in
  ''|*[!0-9]*|??????*)
    echo "MIN_FREE_GB in $REVIEW_DIR/land.conf must be a whole number of gigabytes, "\
"not '$MIN_FREE_GB'" >&2
    exit 1 ;;
esac
FREE_GB=$(( $(df -Pk . | awk 'NR == 2 { print $4 }') / 1048576 ))
if [ "$FREE_GB" -lt "$MIN_FREE_GB" ]; then
  echo "DISK LOW — $FREE_GB GB free, $MIN_FREE_GB needed (MIN_FREE_GB); nothing ran." >&2
  MISSING_GB=$((MIN_FREE_GB - FREE_GB))
  LEFT_KB="$(du -sk "$REVIEW_DIR/runs" 2>/dev/null | awk 'NR == 1 { print $1 }')"
  case "$LEFT_KB" in ''|*[!0-9]*) LEFT_KB=0 ;; esac
  if [ "$LEFT_KB" -ge $((MISSING_GB * 1048576)) ]; then
    turn loop "delete what the loop left behind (maintain, step 12) — recordings, frames, "\
"copies of the code and builds under $REVIEW_DIR/runs of tasks that landed — and run again. "\
"With nothing of that left to delete: $(turn_words user:only-theirs): free $MISSING_GB GB on "\
"this disk"
  else
    turn user:only-theirs "free $MISSING_GB GB on this disk: what the loop left under "\
"$REVIEW_DIR/runs takes only $((LEFT_KB / 1024)) MB"
  fi
  exit 1
fi

# Each role runs in its own fresh session, which keeps the maintainer from
# rubber-stamping the reviewer. The model and effort of each role come from
# .claude/agents.conf, one line per role ("REVIEWER=opus high"), opus when it names
# none. Each runs in a process of its own, with no session to inherit a model from,
# so "inherit" is refused. They are printed before anything runs, so the user sees
# what a run costs before it does. REVIEWER_CMD or MAINTAINER_CMD replaces a role's
# whole command.
AGENTS_CONF="$(dirname "$REVIEW_DIR")/.claude/agents.conf"
role_setting() {
  local role="$1" value model effort
  value="$(read_conf "$AGENTS_CONF" "$role" opus | tr '\t' ' ' | tr -s ' ')"
  model="${value%% *}"
  effort=""
  [ "$model" = "$value" ] || effort="${value#* }"
  case "$model" in
    ''|*[!A-Za-z0-9._-]*) \
      echo "$role in $AGENTS_CONF names no model: '$value'" >&2; return 1 ;;
  esac
  [ "$model" != inherit ] || { echo "$role in $AGENTS_CONF is inherit, but review.sh "\
"starts it in a process of its own, with no session to inherit from: name a model" >&2; return 1; }
  case "$effort" in
    ''|low|medium|high|xhigh|max) ;;
    *) echo "$role in $AGENTS_CONF has effort '$effort' "\
"— use low, medium, high, xhigh or max" >&2; return 1 ;;
  esac
  printf '%s' "$model${effort:+ $effort}"
}

role_flags() {
  local model="${1%% *}" effort=""
  [ "$model" = "$1" ] || effort="${1#* }"
  printf -- '--model %s ' "$model"
  [ -z "$effort" ] || printf -- '--effort %s ' "$effort"
}

REVIEWER_SETTING="$(role_setting REVIEWER)" || exit 1
MAINTAINER_SETTING="$(role_setting MAINTAINER)" || exit 1
REVIEWER_SHOWN="${REVIEWER_CMD:+REVIEWER_CMD}"
MAINTAINER_SHOWN="${MAINTAINER_CMD:+MAINTAINER_CMD}"
# The reviewer holds Bash to verify claims, but not gh: the pull request holds the
# verdicts and the answers, which are not the reviewer's to see (TASK_LOOP.md, "Role
# separation").
REVIEWER_CMD="${REVIEWER_CMD:-claude -p $(role_flags \
"$REVIEWER_SETTING")--allowedTools Read,Grep,Glob,Bash --disallowedTools \"Bash(gh:*)\" \
--output-format json}"
MAINTAINER_CMD="${MAINTAINER_CMD:-claude -p $(role_flags \
"$MAINTAINER_SETTING")--allowedTools Read --output-format json}"
MODELS="reviewer ${REVIEWER_SHOWN:-$REVIEWER_SETTING}, "\
"maintainer ${MAINTAINER_SHOWN:-$MAINTAINER_SETTING}"
echo "── models: $MODELS ($AGENTS_CONF)"

# What the merges of earlier tasks still owe — checks that /qa put off until after them —
# is said in every run and stops none (common.sh).
say_after_merge_unsettled "$REVIEW_DIR/land.conf"

# At LANDING=pr and merge the work is committed and its pull request open before it is
# reviewed, and the run reviews the pull request: the task's work committed, the pull
# request open at HEAD. Each refusal says whose turn it is. Its URL goes into no prompt
# and into meta.json alone: the pull request holds what neither the reviewer nor the
# executor may see. --dry-run reviews the uncommitted work, as at push.
pr_refuse() {
  echo "REVIEW REFUSED — $1" >&2
  [ $# -lt 3 ] || turn "$2" "$3"
  exit 1
}
LANDING="$(landing_level "$REVIEW_DIR/land.conf")" || pr_refuse "$LANDING"
PR_URL=""
MERGE_BASE=""
if landing_opens_pull_request "$LANDING" && [ "$DRY_RUN" = false ]; then
  [ -n "$TASK_ID" ] || \
    pr_refuse "at LANDING=$LANDING the run is posted on the task's pull request: --task-file"
  [ -z "$BASE" ] || \
    pr_refuse "at LANDING=$LANDING the review is of the pull request, from its merge base: "\
"--base is for the levels below"
  REMOTE="$(resolve_remote "$REVIEW_DIR/land.conf")" || pr_refuse "$REMOTE"
  BASE_BRANCH="$(resolve_base_branch "$REVIEW_DIR/land.conf" "$REMOTE")" || \
    pr_refuse "$BASE_BRANCH"
  PROBLEM="$(publishing_problem "$REVIEW_DIR/land.conf" "$LANDING" "$REMOTE" "$BASE_BRANCH")" \
    || pr_refuse "$PROBLEM"
  BRANCH="$(current_branch)"
  [ -n "$BRANCH" ] || pr_refuse "HEAD is detached — there is no pull request to review"
  UNCOMMITTED="$(uncommitted_task_work)"
  [ -z "$UNCOMMITTED" ] || \
    pr_refuse "the task's work is not committed: $(printf '%s\n' "$UNCOMMITTED" | tr '\n' ' ')"\
"— commit it with land.sh first, which also publishes it"
  [ "$(task_id_of "$(git rev-list -1 --no-merges --first-parent HEAD)")" = "$TASK_ID" ] || \
    pr_refuse "HEAD is no commit of $TASK_ID — commit it with land.sh first"
  git fetch -q "$REMOTE" "+refs/heads/$BASE_BRANCH:refs/remotes/$REMOTE/$BASE_BRANCH" || \
    pr_refuse "could not read $BASE_BRANCH from $REMOTE; git says why above"
  PULL_REQUEST="$(pull_request_of "$(remote_repository "$REMOTE")" "$BRANCH" "$BASE_BRANCH" all)" \
    || pr_refuse "gh could not say whether $BRANCH has a pull request into $BASE_BRANCH"
  PR_URL="$(printf '%s' "$PULL_REQUEST" | jq -r '.url // ""')"
  PR_HEAD="$(printf '%s' "$PULL_REQUEST" | jq -r '.headRefOid // ""')"
  case "$(printf '%s' "$PULL_REQUEST" | jq -r '.state // ""')" in
    OPEN) ;;
    CLOSED) pr_refuse "$PR_URL was closed without a merge" \
              user:only-theirs "reopen it, or say that the task ends here" ;;
    *) pr_refuse "$BRANCH has no open pull request into $BASE_BRANCH" \
         loop "run publish.sh alone: it opens the pull request, or says what stops it; then "\
"review again" ;;
  esac
  if [ "$PR_HEAD" != "$(git rev-parse HEAD)" ]; then
    git merge-base --is-ancestor "$PR_HEAD" HEAD 2>/dev/null && \
      pr_refuse "the head of $PR_URL is behind HEAD — run publish.sh alone, then review again"
    pr_refuse "the head of $PR_URL is $PR_HEAD, which HEAD does not contain" \
      user:only-theirs "bring the two together: that commit was pushed to $BRANCH from elsewhere"
  fi
  MERGE_BASE="$(git merge-base "refs/remotes/$REMOTE/$BASE_BRANCH" HEAD)" || \
    pr_refuse "HEAD has no commit in common with $BASE_BRANCH of $REMOTE"
fi

# Created only once the configuration is known good: otherwise every run against
# an unconfigured project leaves an empty directory behind.
# Second precision alone collides when two passes run back to back.
RUN_DIR="$REVIEW_DIR/runs/$(date +%Y%m%dT%H%M%S)-$$"
mkdir -p "$RUN_DIR"

# One source of truth for the threshold: land.conf, overridable per run by the
# flag. The value actually used is recorded in the run so land.sh cannot
# disagree with the review that produced it.
THRESHOLD="$(read_conf "$REVIEW_DIR/land.conf" THRESHOLD major)"
[ -n "$THRESHOLD_CLI" ] && THRESHOLD="$THRESHOLD_CLI"

# Shared default from the submodule, unless the project overrides it in .review/.
lib_file() {
  local relative_path="$1"
  if [ -f "$REVIEW_DIR/$relative_path" ]; then
    printf '%s' "$REVIEW_DIR/$relative_path"
  else
    printf '%s' "$LIB_DIR/$relative_path"
  fi
}

# Reads one field's allowed values straight out of the schema that is sent to the
# model. The schema and this script used to hold two hand-written copies of the
# same enum, so adding a `decision_rule` meant editing both, and the drift would
# surface only as every verdict suddenly being malformed. Deriving them also
# means a project that overrides a schema under `.review/` is validated against
# its own file rather than against the submodule's.
schema_enum() {
  local schema_file="$1" array_property="$2" field="$3" values
  values="$(jq -ce --arg a "$array_property" --arg f "$field" \
    '.properties[$a].items.properties[$f].enum
     | if type == "array" and length > 0 then . else empty end' "$schema_file" 2>/dev/null)" || {
    echo "$schema_file has no usable enum for $field — refusing to validate against nothing" >&2
    return 1
  }
  printf '%s' "$values"
}


# The one thing the schemas cannot express: severities are ordered. Adding a
# severity to a schema without a rank here would make it compare against null,
# and in jq every number is >= null — the whole point of the threshold would
# quietly vanish. So the two are cross-checked rather than merely both existing.
RANKS='{"blocker":3,"major":2,"minor":1,"nit":0}'

SCHEMA_SEVERITIES=\
"$(schema_enum "$(lib_file schemas/review-findings.schema.json)" findings severity)" || exit 1
if ! printf '%s' "$RANKS" | jq -e --argjson declared "$SCHEMA_SEVERITIES" \
     '(keys | sort) == ($declared | sort)' >/dev/null; then
  echo "the severity ranks in review.sh and the severities in the findings schema disagree." >&2
  echo "  ranks:  $(printf '%s' "$RANKS" | jq -rc 'keys | sort | join(", ")')" >&2
  echo "  schema: $(printf '%s' "$SCHEMA_SEVERITIES" | jq -rc 'sort | join(", ")')" >&2
  echo "  an unranked severity compares against null and defeats the threshold." >&2
  exit 1
fi

# An unknown threshold indexes to null, with the same consequence: a typo would
# send every nit to the executor and silently empty the optional list.
if ! printf '%s' "$RANKS" | jq -e --arg t "$THRESHOLD" 'has($t)' >/dev/null; then
  echo "unknown threshold '$THRESHOLD' — use "\
"$(printf '%s' "$RANKS" | jq -r 'keys_unsorted | join(", ")')" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Unwraps an agent CLI's response envelope and strips markdown fences.
# Pulls the JSON payload out of an agent's reply. Models wrap it in prose on
# both sides, and both sides have to be survivable: a range match to EOF chokes
# on a closing fence or "let me know if you want more detail", while taking the
# first brace-balanced object chokes on prose that merely mentions `{tenant}`.
# Either way a paid reviewer+maintainer pass dies on a parse error.
#
# So: emit every brace-balanced candidate, take the first one jq accepts.
# Quoted braces and escaped quotes are tracked, so a `}` inside a reason string
# does not close an object early. Prose containing a *valid* JSON object ahead of
# the real payload would still win — the structural checks below reject it, with
# a message naming the schema.
extract_json() {
  local raw inner candidate
  raw="$(cat)"
  if inner="$(printf '%s' "$raw" | jq -er '.result? // empty' 2>/dev/null)" && [ -n "$inner" ]; then
    raw="$inner"
  fi
  while IFS= read -r -d $'\036' candidate; do
    if printf '%s' "$candidate" | jq -e . >/dev/null 2>&1; then
      printf '%s' "$candidate"
      return 0
    fi
  done < <(printf '%s' "$raw" | awk '
    BEGIN { depth = 0; started = 0; in_string = 0; escaped = 0; SEP = sprintf("%c", 30) }
    {
      out = ""
      for (i = 1; i <= length($0); i++) {
        c = substr($0, i, 1)
        if (!started) { if (c == "{") started = 1; else continue }
        out = out c
        if (escaped) { escaped = 0; continue }
        if (in_string) {
          if (c == "\\") escaped = 1
          else if (c == "\"") in_string = 0
          continue
        }
        if (c == "\"") { in_string = 1; continue }
        if (c == "{") depth++
        else if (c == "}") {
          depth--
          if (depth == 0) { print out; print SEP; started = 0; out = "" }
        }
      }
      if (started) print out
    }
    END { if (started) print SEP }')
  # Nothing parsed. Hand back the whole reply so the caller's "invalid JSON"
  # message points at a file containing what the agent actually said.
  printf '%s' "$raw"
}

run_agent() {
  local command="$1" prompt_file="$2" output_file="$3" label="$4"
  echo "── $label" >&2
  # eval, not word splitting: a command with a quoted argument
  # (--append-system-prompt "a b") must survive intact. The CLI's answer is kept
  # whole, <run>/<label>.cli.json: its tokens and cost go into the summary.
  if ! eval "$command" <"$prompt_file" >"$RUN_DIR/$label.cli.json"; then
    echo "   $label failed to run" >&2
    return 1
  fi
  extract_json <"$RUN_DIR/$label.cli.json" >"$output_file"
  if ! jq -e . "$output_file" >/dev/null 2>&1; then
    echo "   $label returned invalid JSON — see $output_file" >&2
    return 1
  fi
}

# Nearest line in the file whose text contains the quote, and on how many lines the
# file holds it, as `<line> <lines>`; or nothing at all.
# The reviewer reads line numbers off a unified diff, so being a few lines out
# is ordinary; the quote is the reliable part. Relocating beats dropping —
# a dropped finding is a silent loss of recall.
#
# Matching uses the quote's first non-blank line: models quote whole signatures
# and multi-line conditions, and a line-by-line search can never match a needle
# containing a newline. That silently deleted every such finding.
locate_quote() {
  local findings_file="$1" finding_id="$2" source_file="$3"
  jq -r --arg id "$finding_id" --rawfile src "$source_file" '
    ($src | split("\n")) as $lines
    | (.findings[] | select(.id == $id)) as $finding
    | ($finding.code_quote
       | split("\n") | map(select(test("\\S"))) | (.[0] // "")
       | gsub("^\\s+|\\s+$"; "")) as $needle
    | if ($needle | length) == 0 then empty
      else
        [ range(0; $lines | length) | select($lines[.] | contains($needle)) | . + 1 ] as $hits
        | if ($hits | length) == 0 then empty
          else ($hits | map({line: ., distance: ((. - $finding.line) | fabs)})
                      | sort_by(.distance) | "\(.[0].line) \($hits | length)")
          end
      end
  ' "$findings_file" 2>/dev/null
}

# Drops findings whose quote appears nowhere in the file, and corrects the line
# number of the rest. Cheap, deterministic, and it removes a large share of
# hallucinated findings before the maintainer sees them. With a third file it
# writes there on how many lines of its file each located quote stands, as
# {<finding id>: <lines>}: a quote the file holds at several places names no one
# place, and the reading of a task's runs does not take it for one (same_place,
# common.sh).
verify_quotes() {
  local input_file="$1" output_file="$2" lines_file="${3:-}"
  local finding_id source_file cited_line actual_line held
  local corrections=""

  # id, file and line come out in one read rather than one jq call each, and the
  # corrections accumulate as plain lines rather than by re-serialising a growing
  # JSON array per finding.
  while IFS=$'\t' read -r finding_id source_file cited_line; do
    if [ ! -f "$source_file" ]; then
      echo "   dropped $finding_id — no such file: $source_file" >&2
      continue
    fi
    read -r actual_line held <<<"$(locate_quote "$input_file" "$finding_id" "$source_file")"
    if [ -z "$actual_line" ]; then
      echo "   dropped $finding_id — quote not found anywhere in $source_file" >&2
      continue
    fi
    if [ "$actual_line" != "$cited_line" ]; then
      echo "   relocated $finding_id — $source_file:$cited_line → :$actual_line" >&2
    fi
    corrections="$corrections$finding_id $actual_line $held"$'\n'
  done < <(jq -r '.findings[] | [.id, .file, .line] | @tsv' "$input_file")

  if [ -n "$lines_file" ]; then
    printf '%s' "$corrections" | jq -Rs '
      [split("\n")[] | select(length > 0) | split(" ") | {key: .[0], value: (.[2] | tonumber)}]
      | from_entries' >"$lines_file" || return 1
  fi

  # A finding with no correction line was dropped, and drops must be silent
  # losses of noise only — an id that survives always carries a located line.
  printf '%s' "$corrections" | jq -R --slurpfile findings "$input_file" -s '
    ( split("\n") | map(select(length > 0) | split(" ")'\
' | {id: .[0], line: (.[1] | tonumber)}) ) as $corrections
    | {findings: [ $findings[0].findings[]
        | . as $finding
        | ($corrections[] | select(.id == $finding.id)) as $correction
        | $finding + {line: $correction.line} ]}' >"$output_file"
}

# Fails closed on anything the maintainer got wrong: a missing enum, a verdict
# for a finding that does not exist, a finding with no verdict. Any of these
# used to read as "nothing accepted" and land the task.
validate_verdicts() {
  local verdicts_file="$1" findings_file="$2" schema_file
  local verdict_values severity_values rule_values min_reason
  schema_file="$(lib_file schemas/maintainer-verdicts.schema.json)"

  verdict_values="$(schema_enum "$schema_file" verdicts verdict)"   || return 1
  severity_values="$(schema_enum "$schema_file" verdicts severity)" || return 1
  rule_values="$(schema_enum "$schema_file" verdicts decision_rule)" || return 1
  min_reason="$(jq -r '.properties.verdicts.items.properties.reason.minLength // 1' "$schema_file")"

  jq -e --argjson verdicts "$verdict_values" --argjson severities "$severity_values" \
        --argjson rules "$rule_values" --argjson min_reason "$min_reason" '
    def in_enum($values): . as $value | $values | any(. == $value);
    (.verdicts | type) == "array"
      and (.verdicts | length) > 0
      and all(.verdicts[];
              ((.finding_id? // "") != "")
              and ((.verdict? // "") | in_enum($verdicts))
              and ((.severity? // "") | in_enum($severities))
              and ((.decision_rule? // "") | in_enum($rules))
              and ((.reason? // "") | length) >= $min_reason)
  ' "$verdicts_file" >/dev/null 2>&1 || {
    echo "   maintainer output is malformed. Every verdict needs finding_id, plus:" >&2
    echo "     verdict       $(printf '%s' "$verdict_values" | jq -r 'join("|")')" >&2
    echo "     severity      $(printf '%s' "$severity_values" | jq -r 'join("|")')" >&2
    echo "     decision_rule $(printf '%s' "$rule_values" | jq -r 'join("|")')" >&2
    echo "     reason        at least $min_reason characters" >&2
    echo "   decision_rule is what /policy reads when a verdict was wrong; a verdict without" >&2
    echo "   one is not a decision, it is an opinion." >&2
    return 1
  }

  jq -e --slurpfile findings "$findings_file" '
    ([.verdicts[].finding_id] | sort) == ([$findings[0].findings[].id] | sort)
  ' "$verdicts_file" >/dev/null 2>&1 || {
    echo "   verdicts do not match findings one-to-one — see $verdicts_file" >&2
    jq -r --slurpfile findings "$findings_file" '
      ([.verdicts[].finding_id] - [$findings[0].findings[].id]) as $unknown
      | ([$findings[0].findings[].id] - [.verdicts[].finding_id]) as $unjudged
      | "   verdicts for unknown findings: \($unknown | join(", ") // "none")\n'\
'   findings with no verdict: \($unjudged | join(", ") // "none")"
    ' "$verdicts_file" >&2
    return 1
  }
}

# ---------------------------------------------------------------------------
# 1. The diff under review
# ---------------------------------------------------------------------------

# By default the diff under review is exactly what landing would commit: the
# uncommitted work. Reviewing from a merge base instead would re-review tasks
# that already landed on this branch, and their findings could never be resolved
# — land.sh does not see those files as changed, so it would refuse forever.
# --base <ref> widens the review to a whole branch for a final pass; landing
# still only ever commits the uncommitted work. At the pull request levels the work
# is committed first, and the branch holds this task alone — land.sh refuses another
# task's commits on it — so the review is of the pull request, from its merge base.
if [ -n "$BASE" ]; then
  DIFF_FROM="$(git merge-base "$BASE" HEAD)" || exit 1
elif [ -n "$MERGE_BASE" ]; then
  DIFF_FROM="$MERGE_BASE"
else
  DIFF_FROM="HEAD"
fi
# `.review/` is pipeline bookkeeping, not task code: land.sh never stages it as task
# work, so the reviewer must not spend findings on it either. The same goes for the
# tracker, which lands with the task but is not its code, and for the requirements,
# the plan, the decision logs and the policy, which land beside it only with
# WITH_RECORDS=yes and are then named to the reviewer below. The end-to-end harness
# is the exception: it lands with the task that changes it, so it is reviewed.
git diff "$DIFF_FROM" -- . "${NOT_TASK_WORK[@]}" >"$RUN_DIR/diff.patch"
git diff "$DIFF_FROM" -- "${HARNESS[@]}" >>"$RUN_DIR/diff.patch"

# Untracked files are invisible to `git diff` but land.sh will commit them, so
# a whole new source file would otherwise be committed with no review at all.
while IFS= read -r untracked; do
  [ -n "$untracked" ] || continue
  git diff --no-index -- /dev/null "$untracked" >>"$RUN_DIR/diff.patch" 2>/dev/null
done < <(git ls-files --others --exclude-standard | only_task_work;
         git ls-files --others --exclude-standard -- "${HARNESS[@]}")

if [ ! -s "$RUN_DIR/diff.patch" ]; then
  echo "no changes against ${BASE:-${MERGE_BASE:-HEAD}} — nothing to review"
  exit 0
fi

# `time` orders the runs of a task (M1 of the merge takes the newest), and `head`, `pr_url`
# and `merge_base` say what was reviewed at the pull request levels. `end`, `exit` and
# `stage` say how the run ended, and `count` which review of the ASK_AFTER_RUNS it made:
# they are written when it ends (record_end), and a run that made no review, or one past
# the limit, has no count. What a run with --past-limit passed: `stop` names the stop,
# `past_limit_kind` whose it was — user, loop, or converging where the script read that
# the work converges — `because` is the loop's reason, and `user_decided` is true when the
# user decided to go on. All four are null on a plain run.
REVIEWED_FINGERPRINT="$(tree_fingerprint)"
jq -n --arg base "${BASE:-HEAD}" --arg threshold "$THRESHOLD" \
      --arg fingerprint "$REVIEWED_FINGERPRINT" --arg task "$TASK_FILE" \
      --arg task_id "$TASK_ID" --argjson past_limit "$PAST_LIMIT" \
      --argjson epoch "$EPOCH" --arg kind "$PAST_LIMIT_KIND" --arg stop "$STOP" \
      --arg because "$BECAUSE" --argjson user_decided "$USER_DECIDED" \
      --arg reviewer "$REVIEWER_CMD" --arg maintainer "$MAINTAINER_CMD" --arg models "$MODELS" \
      --arg head "$(git rev-parse HEAD)" --arg pr_url "$PR_URL" --arg merge_base "$MERGE_BASE" \
      '{base: $base, threshold: $threshold, tree_fingerprint: $fingerprint,
        task_file: (if $task == "" then null else $task end),
        task: (if $task_id == "" then null else $task_id end),
        past_limit: $past_limit, epoch: $epoch, count: null, time: now, head: $head,
        pr_url: (if $pr_url == "" then null else $pr_url end),
        merge_base: (if $merge_base == "" then null else $merge_base end),
        models: $models, reviewer: $reviewer, maintainer: $maintainer,
        end: null, exit: null, stage: null,
        past_limit_kind: (if $kind == "" then null else $kind end),
        stop: (if $past_limit then $stop else null end),
        because: (if $because == "" then null else $because end),
        user_decided: (if $user_decided then true else null end)}' \
  >"$RUN_DIR/meta.json"

# How the run ended, written into its meta.json whatever ends it: the next run of the task
# reads there what repeats (task_runs_json). STAGE is how far the run came — gates, e2e,
# reviewer, verify, maintainer, triage — and END what it came to, set where the script
# knows it: gates-red, e2e-red, no-harness, unusable, clean, findings or escalations. A run
# that ends anywhere else — an agent's answer that does not hold, a gate runner that did
# not run, a signal — ended in an error.
STAGE=""
END=""
record_end() {
  local count=null
  case "$END" in
    clean | findings | escalations)
      [ -z "$TASK_ID" ] || [ "$PAST_LIMIT" = true ] || count=$((REVIEWS_SO_FAR + 1)) ;;
  esac
  jq --arg ending "${END:-error}" --argjson exit "$1" --arg stage "$STAGE" \
    --argjson count "$count" \
    '.end = $ending | .exit = $exit | .stage = (if $stage == "" then null else $stage end)
     | .count = $count' \
    "$RUN_DIR/meta.json" >"$RUN_DIR/meta.json.new" 2>/dev/null \
    && mv "$RUN_DIR/meta.json.new" "$RUN_DIR/meta.json" \
    || { rm -f "$RUN_DIR/meta.json.new"
         echo "   how the run ended could not be written into $RUN_DIR/meta.json" >&2; }
}

# What repeats, said at the end of a run, with this run among those read: a finding its
# review accepted again after a change of the work, and an end that is the same as that of
# the run before. A third time in a row the next run stops.
say_what_repeats() {
  local this runs reading row before failed passed
  [ -n "$TASK_ID" ] || return 0
  this="$(task_run_json "$RUN_DIR" 2>/dev/null)" || return 0
  runs="$(printf '[%s, [%s]]' "$RUNS" "$this" | jq -c 'add' 2>/dev/null)" || return 0
  reading="$(task_reading "$runs" "$QA" "$ASK_AFTER_RUNS" 2>/dev/null)" || return 0
  case "$END" in
    findings | escalations)
      printf '%s' "$reading" | jq -r '
        (.came_back[] | "   again after a change: \(.id) \(.file):\(.line) — also accepted in "
           + (.runs[:-1] | map(split("/") | last) | join(", "))),
        (if any(.came_back[]; .row >= 3)
         then "   that is \([.came_back[].row] | max) reviews in a row: the next run of "
              + "review.sh stops and says whose turn it is (maintain, step 5)"
         elif (.came_back | length) > 0
         then "   a third time in a row review.sh stops (maintain, step 5)"
         else empty end)' ;;
  esac
  IFS=$'\t' read -r row before failed passed < <(printf '%s' "$reading" | jq -r '
    [.same_end_row, (.same_end_runs[-2] // "-" | split("/") | last), .newest.failed // "-",
     (.passed.run // "-")] | @tsv')
  # This run passed the stop of the same end after changes, and ended that way again.
  if [ "${row:-0}" -eq 0 ] && [ "$passed" = "$RUN_DIR" ]; then
    echo "── the same end as before this stop was passed: "\
"$(what_failed "$RUN_DIR" "$failed"); three more times in a row and review.sh stops again"
    return 0
  fi
  [ "${row:-0}" -ge 2 ] || return 0
  if [ "$row" -eq 2 ]; then
    echo "── the same end as the run before ($before): $(what_failed "$RUN_DIR" "$failed"); "\
"a third time in a row review.sh stops"
  else
    echo "── the same end as the $((row - 1)) runs before: "\
"$(what_failed "$RUN_DIR" "$failed"); the next run of review.sh stops and says whose turn it is"
  fi
}

# At the pull request levels every run is posted there, whatever its end: red checks and
# findings are what the people on the pull request need to see. A post that fails is
# said, and a clean run then exits 1.
end_run() {
  local code=$?
  trap - EXIT
  record_end "$code"
  say_what_repeats
  if [ -n "$PR_URL" ] && ! "$LIB_DIR/pr-post.sh" run "$RUN_DIR"; then
    echo "   the run is not posted on $PR_URL — run $LIB_DIR/pr-post.sh run $RUN_DIR alone" >&2
    if [ "$code" -eq 0 ]; then
      code=1
      record_end "$code"
    fi
  fi
  exit "$code"
}
trap end_run EXIT

# ---------------------------------------------------------------------------
# 2. Layer 0 — gates. Ground truth, and a hard stop.
# ---------------------------------------------------------------------------

# REVIEW_BASE: where the change under review starts, for a gate that looks at the
# change alone — on a pull request whose work is all committed, HEAD would show none.
STAGE=gates
REVIEW_BASE="$DIFF_FROM" "$REVIEW_DIR/gates.sh" "$RUN_DIR/gates.json" >/dev/null
GATES_EXIT=$?

# A gate runner that could not run is not a red gate. 126/127, or no usable
# gates.json, means there is no gate output to send anywhere — and "GATES RED"
# with an empty failure list would put the executor to work on nothing.
if [ "$GATES_EXIT" -ge 126 ] || \
  ! jq -e 'type == "object"' "$RUN_DIR/gates.json" >/dev/null 2>&1; then
  echo "$REVIEW_DIR/gates.sh did not run (exit $GATES_EXIT) or wrote no usable" >&2
  echo "   $RUN_DIR/gates.json — fix the gate runner; this is not a red gate" >&2
  exit 1
fi

# Gates check, they do not fix: a formatter in the `format` slot that rewrites
# files invalidates the diff that was just captured and the fingerprint the run
# is bound to. Caught here, where the cause is obvious — the next fingerprint
# check is after the reviewer, and would blame the reviewer for this.
if [ "$(tree_fingerprint)" != "$REVIEWED_FINGERPRINT" ]; then
  echo "   a gate modified the working tree — gates must check, not fix" >&2
  echo "   most likely one of two things:" >&2
  echo "     - a formatter running in write mode (use ktlintCheck, not ktlint" >&2
  echo "       --format; swiftformat --lint, not swiftformat)" >&2
  echo "     - build output that .gitignore does not cover, so the build gate" >&2
  echo "       leaves new untracked files behind" >&2
  exit 1
fi

if [ "$GATES_EXIT" -ne 0 ]; then
  echo
  echo "GATES RED — no LLM review. Failing gates:"
  jq -r 'to_entries[] | select(.value.status == "fail")'\
' | "  \(.key): \(.value.command)\n\(.value.output)"' \
    "$RUN_DIR/gates.json"
  END=gates-red
  exit 2
fi

# The end-to-end tests, through the project's .review/e2e.sh, after the gates
# because they need the build. Green gates say nothing about the app as its
# user drives it, so a tree with no working harness stops here as well — in
# every project, whatever its gates.sh holds, since this file is the
# submodule's. e2e-gate.sh exits 2 when red and 1 without a harness, and has written
# e2e.json then: with none, it ended in an error.
STAGE=e2e
"$LIB_DIR/e2e-gate.sh" run "$RUN_DIR" "$TASK_ID"
E2E_EXIT=$?
if [ "$E2E_EXIT" -ne 0 ]; then
  if [ -f "$RUN_DIR/e2e.json" ]; then
    case "$E2E_EXIT" in
      2) END=e2e-red ;;
      1) END=no-harness ;;
    esac
  fi
  exit "$E2E_EXIT"
fi

# The requirements, the plan and the loop's records are not reviewed. With
# WITH_RECORDS=yes they land in the task's commit all the same, and a review that
# does not know it reads a plan moved to PLAN.md as a plan deleted, and cannot tell
# that a commit of the loop changes the review policy.
WITH_RECORDS="$(read_conf "$REVIEW_DIR/land.conf" WITH_RECORDS no)"
records_landing_unreviewed() {
  [ "$WITH_RECORDS" = yes ] || return 0
  { git diff --name-only "$DIFF_FROM" -- "${RECORDS[@]}"
    git ls-files --others --exclude-standard -- "${RECORDS[@]}"; } | sort -u
}
RECORDS_LANDING="$(records_landing_unreviewed)"
say_records_landing() {
  [ -n "$RECORDS_LANDING" ] || return 0
  echo
  echo "## Not in the diff, landing with this task"
  echo "The requirements, the plan and the loop's records are not reviewed, but these land in"
  echo "the same commit; a file the diff seems to lose may be among them:"
  printf '%s\n' "$RECORDS_LANDING"
}

# ---------------------------------------------------------------------------
# 3. Reviewer
# ---------------------------------------------------------------------------

{
  cat "$(lib_file prompts/reviewer.md)"
  echo
  echo "## Output schema (JSON only, no prose, no markdown fences)"
  cat "$(lib_file schemas/review-findings.schema.json)"
  echo
  echo "## Gate results"
  jq 'map_values(.status)' "$RUN_DIR/gates.json"
  echo
  echo "## Diff under review"
  echo '```diff'
  cat "$RUN_DIR/diff.patch"
  echo '```'
  say_records_landing
} >"$RUN_DIR/reviewer-prompt.md"

STAGE=reviewer
run_agent "$REVIEWER_CMD" "$RUN_DIR/reviewer-prompt.md" "$RUN_DIR/findings.raw.json" \
  "reviewer" || exit 1

# The reviewer holds Bash so it can verify claims, and it is reading a diff it
# did not write. If it changed the tree, say so here rather than letting landing
# refuse later with a confusing message.
if [ "$(tree_fingerprint)" != "$REVIEWED_FINGERPRINT" ]; then
  echo "   the reviewer modified the working tree — it must not write anything" >&2
  echo "   review is void; check $RUN_DIR and the reviewer's tool permissions" >&2
  exit 1
fi

FINDINGS_SCHEMA="$(lib_file schemas/review-findings.schema.json)"
CATEGORY_VALUES="$(schema_enum "$FINDINGS_SCHEMA" findings category)"     || exit 1
SEVERITY_VALUES="$(schema_enum "$FINDINGS_SCHEMA" findings severity)"     || exit 1
CONFIDENCE_VALUES="$(schema_enum "$FINDINGS_SCHEMA" findings confidence)" || exit 1

jq -e --argjson categories "$CATEGORY_VALUES" --argjson severities "$SEVERITY_VALUES" \
      --argjson confidences "$CONFIDENCE_VALUES" '
  def in_enum($values): . as $value | $values | any(. == $value);
  (.findings | type) == "array"
    and (([.findings[].id] | length) == ([.findings[].id] | unique | length))
    and all(.findings[];
            ((.id? // "") | test("^F-[0-9]{3}$"))
            and ((.file? // "") != "")
            and ((.line? | type) == "number" and .line == (.line | floor) and .line >= 1)
            and ((.code_quote? // "") != "")
            and ((.category? // "") | in_enum($categories))
            and ((.severity? // "") | in_enum($severities))
            and ((.confidence? // "") | in_enum($confidences))
            and ((.evidence? | type) == "string" and .evidence != ""))
' "$RUN_DIR/findings.raw.json" >/dev/null 2>&1 || {
  echo "   reviewer output does not match the findings schema — see $RUN_DIR/findings.raw.json" >&2
  echo "   required per finding: id (F-nnn), file, line, code_quote, category," >&2
  echo "   severity, confidence, evidence — all from the schema's enums;" >&2
  echo "   ids must be unique within the run" >&2
  jq -r '[.findings[].id] | group_by(.) | map(select(length > 1) | .[0]) as $dupes
         | if ($dupes | length) > 0'\
' then "   duplicate ids: \($dupes | join(", "))" else empty end' \
    "$RUN_DIR/findings.raw.json" >&2 2>/dev/null
  exit 1
}

STAGE=verify
RAW_COUNT="$(jq '.findings | length' "$RUN_DIR/findings.raw.json")"
verify_quotes "$RUN_DIR/findings.raw.json" "$RUN_DIR/findings.json" \
  "$RUN_DIR/quote-lines.json" || {
  echo "   quote verification failed — see $RUN_DIR" >&2
  exit 1
}

FINDING_COUNT="$(jq -e 'if (.findings | type) == "array" then (.findings | length) else empty end' \
  "$RUN_DIR/findings.json" 2>/dev/null)" || {
  echo "   findings.json is not a findings array — refusing to read it as empty" >&2
  exit 1
}

# Partial loss is worth saying out loud. Only a 100% loss stops the run, so
# without this a review that located one finding out of ten reads as a review
# that found one thing — and the nine that were silently dropped are exactly
# where recall goes to die.
DROPPED_COUNT=$((RAW_COUNT - FINDING_COUNT))
if [ "$DROPPED_COUNT" -gt 0 ]; then
  echo "   $DROPPED_COUNT of $RAW_COUNT finding(s) dropped — quote not found in the file" >&2
  if [ $((DROPPED_COUNT * 2)) -gt "$RAW_COUNT" ]; then
    echo "   that is most of them: the reviewer is quoting from memory rather than" >&2
    echo "   from the diff. Treat what survived as low-confidence and re-run." >&2
  fi
fi

# Every finding unverifiable means the reviewer produced nothing usable, not
# that the diff is clean. Reporting CLEAN here would let the task land on a
# review that located nothing.
if [ "$RAW_COUNT" -gt 0 ] && [ "$FINDING_COUNT" -eq 0 ]; then
  echo
  echo "REVIEW UNUSABLE — all $RAW_COUNT finding(s) failed quote verification."
  echo "Not a clean run: nothing was actually reviewed. Run the review again."
  END=unusable
  exit 5
fi

if [ "$FINDING_COUNT" -eq 0 ]; then
  echo '[]' >"$RUN_DIR/approved.json"
  echo '[]' >"$RUN_DIR/escalated.json"
  echo '[]' >"$RUN_DIR/optional.json"
  echo '{"verdicts":[]}' >"$RUN_DIR/verdicts.json"
  echo
  echo "── review complete: $RUN_DIR"
  echo "CLEAN — gates green, no verified findings."
  END=clean
  exit 0
fi

# ---------------------------------------------------------------------------
# 4. Maintainer — triage
# ---------------------------------------------------------------------------

{
  cat "$(lib_file prompts/maintainer.md)"
  echo
  echo "## Output schema (JSON only, one verdict per finding)"
  cat "$(lib_file schemas/maintainer-verdicts.schema.json)"
  echo
  echo "## REVIEW_POLICY.md"
  cat "$REVIEW_DIR/REVIEW_POLICY.md"
  echo
  if [ -n "$TASK_FILE" ] && [ -f "$TASK_FILE" ]; then
    echo "## The task: scope and exit criteria"
    echo "Decision rule 5 (out of task scope) and any scope-based policy rule are"
    echo "judged against this. Files outside .scope are not this task's problem, except the"
    echo "end-to-end harness (.review/e2e.sh, .review/e2e-*): it lands with the task that"
    echo "changes it."
    cat "$TASK_FILE"
    echo
    echo "## Files changed in this diff"
    git diff --name-only "$DIFF_FROM" -- . "${NOT_TASK_WORK[@]}"
    git ls-files --others --exclude-standard | only_task_work
    git diff --name-only "$DIFF_FROM" -- "${HARNESS[@]}"
    git ls-files --others --exclude-standard -- "${HARNESS[@]}"
    say_records_landing
    echo
  else
    echo "## No task file supplied"
    echo "Do not apply scope-based rules — you cannot see the task's scope."
    echo
  fi
  echo "## Gate results (ground truth)"
  cat "$RUN_DIR/gates.json"
  echo
  echo "## Findings to triage"
  cat "$RUN_DIR/findings.json"
} >"$RUN_DIR/maintainer-prompt.md"

STAGE=maintainer
run_agent "$MAINTAINER_CMD" "$RUN_DIR/maintainer-prompt.md" "$RUN_DIR/verdicts.json" \
  "maintainer" || exit 1
validate_verdicts "$RUN_DIR/verdicts.json" "$RUN_DIR/findings.json" || exit 1

# ---------------------------------------------------------------------------
# 5. Filter — only accepted findings at or above the threshold reach the executor
# ---------------------------------------------------------------------------

STAGE=triage
jq --argjson rank "$RANKS" --arg threshold "$THRESHOLD" \
  --slurpfile findings "$RUN_DIR/findings.json" '
  [ .verdicts[]
    | . as $verdict
    | select($verdict.verdict == "accept" and $rank[$verdict.severity] >= $rank[$threshold])
    | $verdict + {finding: ($findings[0].findings[] | select(.id == $verdict.finding_id))}
  ]' "$RUN_DIR/verdicts.json" >"$RUN_DIR/approved.json" || exit 1

jq '[.verdicts[] | select(.verdict == "escalate")]' "$RUN_DIR/verdicts.json" \
  >"$RUN_DIR/escalated.json" || exit 1
jq --argjson rank "$RANKS" --arg threshold "$THRESHOLD" \
  '[.verdicts[] | select(.verdict == "accept" and $rank[.severity] < $rank[$threshold])]' \
  "$RUN_DIR/verdicts.json" >"$RUN_DIR/optional.json" || exit 1

APPROVED_COUNT="$(require_array_length "$RUN_DIR/approved.json")" || exit 1
ESCALATED_COUNT="$(require_array_length "$RUN_DIR/escalated.json")" || exit 1
OPTIONAL_COUNT="$(require_array_length "$RUN_DIR/optional.json")" || exit 1
REJECTED_COUNT=\
"$(jq '[.verdicts[] | select(.verdict == "reject")] | length' "$RUN_DIR/verdicts.json")"

echo
echo "── review complete: $RUN_DIR"
echo "   verified findings : $FINDING_COUNT   (of $RAW_COUNT reported, $DROPPED_COUNT dropped)"
echo "   accepted (>= $THRESHOLD): $APPROVED_COUNT   → approved.json, for the executor"
echo "   accepted (below)  : $OPTIONAL_COUNT   → optional.json, not acted on"
echo "   escalated         : $ESCALATED_COUNT   → escalated.json, to answer"
echo "   rejected          : $REJECTED_COUNT"

if [ "$ESCALATED_COUNT" -gt 0 ]; then
  END=escalations
  exit 4
fi
if [ "$APPROVED_COUNT" -gt 0 ]; then
  END=findings
  exit 3
fi
END=clean
exit 0
