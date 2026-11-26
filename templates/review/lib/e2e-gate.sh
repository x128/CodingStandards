#!/usr/bin/env bash
#
# e2e-gate.sh — the end-to-end tests: the app driven the way its user drives it,
# on every platform the tree ships.
#
# Runs FROM THE SUBMODULE and, like land.sh, is NOT overridable: the project
# says how its end-to-end tests run (.review/e2e.sh), never whether they count.
#
# Usage, from the project root:
#   e2e-gate.sh run <run-dir> [task-id]   runs .review/e2e.sh once per platform
#                                         and writes <run-dir>/e2e.json
#   e2e-gate.sh check                     reads the newest e2e.json, runs nothing:
#                                         of a run or of a repeat of its tests alone
#                                         (<run>/e2e-again/<n>, review.sh)
#
# What counts is the JUnit XML .review/e2e.sh leaves, never its exit code: a test
# command with nothing to run exits 0. A platform has a harness when a test ran
# on it and a case of qa/test-cases.md names a test that ran (any test, while
# the file has no case yet). The one exit code that is read is 75: the harness
# says that its device or a tool was not there. The platform then runs once
# more, after E2E_REPEAT_PAUSE seconds (15; the environment only), and a second
# 75 is the environment's: its reports are not read, since nothing is known of
# the code.
#
# Android and iOS are held while their harness runs: one run of the tests on a
# platform at a time, in every copy of every project of the user on this machine
# (E2E_LOCK, E2E_WAIT and E2E_TIMEOUT of land.conf; common.sh, "The hold on a
# platform"). A run waits while another holds the platform, and a run that was
# killed frees it by itself.
#
# Exit codes, run:
#   0  pass — no test failed, and every test a case names passed on every
#      platform that runs it
#   2  red — a test failed, e2e.sh failed, or a named test did not pass or run
#   75 the environment — the harness said so with exit 75, twice, another run
#      held the platform past E2E_WAIT, no hold on it could be made, or it did not
#      end in E2E_TIMEOUT and left no failed test; nothing is known of the code
#   1  no working harness, no test that ran, or a pipeline error
# Exit codes, check:
#   0  the newest e2e.json had a harness on every platform the tree ships now,
#      and its tests ran
#   2  it did not, or the check itself could not run, with the reason on
#      stderr — a PreToolUse hook blocks on 2 and lets any other code through
#
# Requires: jq >= 1.6, git, awk

set -uo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 1
# shellcheck source=common.sh
. "$LIB_DIR/common.sh"

MODE="${1:-}"
RUN_DIR="${2:-}"
TASK_ID="${3:-}"

# check refuses with 2, the one code on which a PreToolUse hook blocks. The last
# line says where the hook lives: no settings file of the project holds it.
hold_back() {
  printf '%s\n' "$@" >&2
  echo "   This is the hook of the /qa skill (CodingStandards/.agents/skills/qa/SKILL.md):" >&2
  echo "   /qa checks the app by hand only after review.sh has run its end-to-end tests." >&2
  exit 2
}

case "$MODE" in
  run)   [ -n "$RUN_DIR" ] || { echo "usage: e2e-gate.sh run <run-dir> [task-id]" >&2; exit 1; }
         mkdir -p "$RUN_DIR" || exit 1
         # Resolved before the cd below, as land.sh resolves its own arguments.
         RUN_DIR="$(abspath "$RUN_DIR")" || exit 1 ;;
  check) ;;
  *)     echo "usage: e2e-gate.sh run <run-dir> [task-id] | e2e-gate.sh check" >&2; exit 1 ;;
esac

PROJECT_ROOT="$(git rev-parse --show-toplevel)" || {
  [ "$MODE" != check ] || hold_back "NO E2E HARNESS — $(pwd) is not inside a git repository, "\
"so no end-to-end run can be found."
  exit 1
}
cd "$PROJECT_ROOT" || exit 1

REVIEW_DIR=".review"
HARNESS="$REVIEW_DIR/e2e.sh"

as_json_array() { jq -R . | jq -sc 'map(select(length > 0)) | unique'; }

# ---------------------------------------------------------------------------
# check — for the hook of /qa: no driving of the app by hand where the
# end-to-end tests never ran. Only files are read; no device is touched.
# ---------------------------------------------------------------------------

if [ "$MODE" = check ]; then
  # The newest by the time recorded inside, not by folder name: run folders are
  # named by the local clock and the process id, and neither sorts by time. A repeat of a
  # run's tests alone is in a folder of its own beside the run's files.
  NEWEST="$(for record in "$REVIEW_DIR"/runs/*/e2e.json \
      "$REVIEW_DIR"/runs/*/e2e-again/*/e2e.json; do
      [ -f "$record" ] || continue
      jq -c --arg file "$record" '{time, status, platforms, reasons, file: $file}' "$record" \
        2>/dev/null
    done | jq -sc 'sort_by(.time) | last // empty')"
  [ -n "$NEWEST" ] || hold_back \
    "NO E2E HARNESS — no end-to-end run is recorded in $REVIEW_DIR/runs/*/e2e.json." \
    "   review.sh runs the end-to-end tests after the gates; the app is checked by hand" \
    "   only where they ran. The harness is a task of its own and comes first."
  RECORD="$(printf '%s' "$NEWEST" | jq -r '.file')"
  case "$(printf '%s' "$NEWEST" | jq -r '.status')" in
    no-harness)
      hold_back "NO E2E HARNESS — the newest end-to-end run, $RECORD, found no working harness:" \
        "$(printf '%s' "$NEWEST" | jq -r '.reasons[]? | "   \(.)"')" \
        "   The harness is a task of its own and comes first." ;;
    environment | no-test)
      hold_back "E2E DID NOT RUN — the newest end-to-end run, $RECORD, could not run its tests:" \
        "$(printf '%s' "$NEWEST" | jq -r '.reasons[]? | "   \(.)"')" \
        "   Mend what stopped them, then run review.sh again: it repeats only the tests." ;;
  esac
  MISSING="$(platforms | as_json_array | jq -r --argjson newest "$NEWEST" \
    '. - ($newest.platforms // []) | join(" ")')"
  [ -z "$MISSING" ] || \
    hold_back "NO E2E HARNESS — the newest end-to-end run, $RECORD, never ran on: $MISSING"
  exit 0
fi

# ---------------------------------------------------------------------------
# run
# ---------------------------------------------------------------------------

REPEAT_PAUSE="${E2E_REPEAT_PAUSE:-15}"
case "$REPEAT_PAUSE" in
  ''|*[!0-9]*) echo "E2E_REPEAT_PAUSE must be a whole number of seconds, not '$REPEAT_PAUSE'" >&2
               exit 1 ;;
esac

# The hold on a platform (common.sh). With E2E_LOCK=platform the run holds android and ios
# while their harness runs, so that no other run of the loop, in any copy of any project
# of the user on this machine, uses their devices meanwhile; off, where each copy has
# devices of its own. E2E_WAIT is how long a busy platform is waited for, E2E_TIMEOUT how
# long one platform's tests may take before they are stopped (0, no limit). HOLD_LEASE and
# HOLD_RENEW, the lease and how often a living run renews it, are of the environment, for
# selftest.sh alone.
CONF="$REVIEW_DIR/land.conf"
E2E_LOCK="$(read_conf "$CONF" E2E_LOCK platform)"
case "$E2E_LOCK" in
  platform|off) ;;
  *) echo "E2E_LOCK in $CONF must be platform or off, not '$E2E_LOCK'" >&2; exit 1 ;;
esac
E2E_WAIT="$(read_conf "$CONF" E2E_WAIT 1800)"
E2E_TIMEOUT="$(read_conf "$CONF" E2E_TIMEOUT 0)"
for setting in "E2E_WAIT=$E2E_WAIT" "E2E_TIMEOUT=$E2E_TIMEOUT"; do
  case "${setting#*=}" in
    ''|*[!0-9]*|??????????*)
      echo "${setting%%=*} in $CONF must be a whole number of seconds, not '${setting#*=}'" >&2
      exit 1 ;;
  esac
done
HOLD_LEASE="${HOLD_LEASE:-120}"
HOLD_RENEW="${HOLD_RENEW:-30}"
for setting in "HOLD_LEASE=$HOLD_LEASE" "HOLD_RENEW=$HOLD_RENEW"; do
  case "${setting#*=}" in
    ''|*[!0-9]*|0|??????????*)
      echo "${setting%%=*} must be a whole number of seconds from 1, not '${setting#*=}'" >&2
      exit 1 ;;
  esac
done
HOLD_PLACE="$(device_lock_dir "$CONF")"
HOLDER="${RUN_DIR#"$PROJECT_ROOT"/}"
GATE_STARTED="$(process_started "$$")"
HELD=""
RENEWER=""
HARNESS_PID=""

# While the gate holds a platform, a child renews the lease every HOLD_RENEW seconds, and
# only while the gate lives: a gate that is killed stops renewing, and the platform is free
# again once the lease has run out.
renew_hold() {
  local ticks=0
  while sleep 1; do
    kill -0 "$$" 2>/dev/null || exit 0
    ticks=$((ticks + 1))
    [ "$ticks" -ge "$HOLD_RENEW" ] || continue
    ticks=0
    [ "$(process_started "$$")" = "$GATE_STARTED" ] && hold_renew "$1" "$HOLD_LEASE" || exit 0
  done
}
release_platform() {
  [ -z "$RENEWER" ] || kill "$RENEWER" 2>/dev/null
  RENEWER=""
  [ -z "$HELD" ] || hold_release "$HELD"
  HELD=""
}
# A gate that is stopped stops the harness it runs — the whole process group of it — and
# gives the platform back at once.
stop_gate() {
  trap '' TERM INT
  [ -z "$HARNESS_PID" ] || kill -TERM -- "-$HARNESS_PID" 2>/dev/null
  release_platform
  exit "$1"
}
trap 'stop_gate 143' TERM
trap 'stop_gate 130' INT
trap release_platform EXIT

# One call of the harness, in a process group of its own, so that a stop of the gate, the
# taker of a hold that ran out and E2E_TIMEOUT reach every process it started. Sets
# exit_code; a harness that E2E_TIMEOUT stopped leaves the file <platform>.timed-out. The
# harness starts only once its group is recorded with the hold, and never once the gate is
# gone: a gate killed at any moment leaves no harness, or one whose group the taker stops.
# 1, the group could not be recorded, and no harness ran.
call_harness() {
  local platform="$1" directory="$2" watcher="" go="$RUN_DIR/e2e/$platform.go"
  rm -f "$RUN_DIR/e2e/$platform.timed-out" "$go"
  set -m
  (
    set +m
    until [ -e "$go" ]; do
      kill -0 "$$" 2>/dev/null || exit 1
      sleep 0.1
    done
    exec "$HARNESS" "$platform" "$directory"
  ) </dev/null >"$RUN_DIR/e2e/$platform.log" 2>&1 &
  HARNESS_PID=$!
  set +m
  if [ -n "$HELD" ] && ! hold_group "$HELD" "$HARNESS_PID"; then
    kill -TERM -- "-$HARNESS_PID" 2>/dev/null
    wait "$HARNESS_PID" 2>/dev/null
    HARNESS_PID=""
    exit_code=1
    return 1
  fi
  : >"$go"
  if [ "$E2E_TIMEOUT" -gt 0 ]; then
    (
      elapsed=0
      while [ "$elapsed" -lt "$E2E_TIMEOUT" ]; do
        sleep 1
        elapsed=$((elapsed + 1))
        kill -0 "$HARNESS_PID" 2>/dev/null || exit 0
      done
      : >"$RUN_DIR/e2e/$platform.timed-out"
      kill -TERM -- "-$HARNESS_PID" 2>/dev/null
    ) </dev/null >/dev/null 2>&1 &
    watcher=$!
  fi
  wait "$HARNESS_PID" 2>/dev/null
  exit_code=$?
  HARNESS_PID=""
  rm -f "$go"
  [ -z "$watcher" ] || { kill "$watcher" 2>/dev/null; wait "$watcher" 2>/dev/null; }
  return 0
}
START="$(date +%s)"
FINGERPRINT="$(tree_fingerprint)"
# The loop's own files are outside the fingerprint, and qa/test-cases.md is one of
# them: the run is checked against the marks as they were when it began, and the
# whole tree is compared after it, so a harness that rewrites the cases is seen.
WHOLE_TREE="$(tree_fingerprint --whole)"
MARKS="$(case_marks)"
# The words of each case as they are when the run begins, as a digest: a test seen failing
# is seen failing against these words, and land.sh compares them with the words at landing.
CASE_DIGESTS="$(case_digests)" || exit 1
PLATFORMS="$(platforms)"
# Recorded before the run: a harness that rewrites itself while it runs would
# otherwise leave another one behind as the one that ran.
HARNESS_BEFORE="$(harness_blobs)"

# The failures /qa has recorded for this task so far. A test that fails in this
# run is seen red AFTER /qa reported its case; land.sh asks for exactly that, and
# these lists keep the record when a qa.json is rewritten or its folder removed.
QA_KNOWN="$(for record in "$REVIEW_DIR"/runs/*/qa.json; do
    [ -f "$record" ] || continue
    jq -c --arg id "$TASK_ID" 'select(.task == $id) | [.failures[]?.case?]' "$record" 2>/dev/null
  done | jq -sc 'add // [] | map(select(type == "string" and test("^TC-[0-9]+$"))) | unique')" \
  || exit 1

# One row per test case of the JUnit reports: `<classname>.<name>` TAB passed,
# failed or skipped; and `#timestamp` TAB the time each testsuite gives. The
# reports are read tag by tag (each record starts after a `<`), so a testcase
# may span lines or share one, be self-closing or not, and take its attributes
# in any order and with spaces around `=`. Comments and CDATA — a test's own
# output — are passed over, entities in a name are decoded, and a trailing `()`
# of the name (XCTest, JUnit 5) is dropped. Each record is looked at once, so a
# report with megabytes of output reads in about the time it takes to scan.
junit_rows() {
  awk '
    BEGIN { RS = "<" }
    function attribute(head, key,   value, quoted) {
      quoted = "(\"[^\"]*\"|'\''[^'\'']*'\'')"
      if (!match(head, "[ \t\r\n]" key "[ \t\r\n]*=[ \t\r\n]*" quoted)) return ""
      value = substr(head, RSTART, RLENGTH)
      sub(/^[^=]*=[ \t\r\n]*./, "", value)
      value = substr(value, 1, length(value) - 1)
      gsub(/&lt;/, "<", value); gsub(/&gt;/, ">", value); gsub(/&quot;/, "\"", value)
      gsub(/&apos;/, "'\''", value); gsub(/&amp;/, "\\&", value)
      return value
    }
    # The tag up to its closing ">", which may also stand inside a quoted value.
    function tag(record,   i, n, c, quote) {
      n = length(record)
      for (i = 1; i <= n; i++) {
        c = substr(record, i, 1)
        if (quote != "") { if (c == quote) quote = "" }
        else if (c == "\"" || c == "'\''") quote = c
        else if (c == ">") return substr(record, 1, i - 1)
      }
      return record
    }
    function close_case() { if (open) print id "\t" status; open = 0 }
    FNR == 1 { close_case(); skip = "" }
    skip == "comment" { if (index($0, "-->")) skip = ""; next }
    skip == "cdata"   { if (index($0, "]]>")) skip = ""; next }
    /^!--/            { if (!index($0, "-->")) skip = "comment"; next }
    /^!\[CDATA\[/     { if (!index($0, "]]>")) skip = "cdata"; next }
    /^testsuite[ \t\r\n\/>]/ {
      stamp = attribute(tag($0), "timestamp")
      if (stamp != "") print "#timestamp\t" stamp
      next
    }
    /^testcase[ \t\r\n\/>]/ {
      close_case()
      head = tag($0)
      name = attribute(head, "name")
      sub(/\(\)$/, "", name)
      classname = attribute(head, "classname")
      id = (classname == "" ? name : classname "." name)
      status = "passed"
      open = 1
      if (head ~ /\/[ \t\r\n]*$/) close_case()
      next
    }
    open && /^\/testcase[ \t\r\n>]/        { close_case(); next }
    open && /^(failure|error)[ \t\r\n\/>]/ { status = "failed"; next }
    open && /^skipped[ \t\r\n\/>]/         { if (status != "failed") status = "skipped"; next }
    END { close_case() }' "$@"
}

# Each platform's tests, into <run-dir>/e2e/<platform>/, emptied first and read
# as soon as its run ends: a report another platform's run wrote there is not
# this platform's. The log and the rows go next to that folder. A platform whose
# harness said twice that its device or a tool was not there, that another run
# held past E2E_WAIT (BUSY) or whose hold cannot be made (UNMADE) is in
# ENVIRONMENT, with the reason, and no report is read.
PRESET_REASONS="[]"
RESULTS="{}"
ENVIRONMENT="{}"
BUSY="[]"
UNMADE="[]"
TIMED_OUT="{}"
add_platform() { jq -c --arg platform "$platform" '. + [$platform]' <<<"$1"; }
if [ ! -x "$HARNESS" ]; then
  PRESET_REASONS="$(jq -nc --arg reason "$HARNESS is missing or not executable" '[$reason]')"
else
  for platform in $PLATFORMS; do
    directory="$RUN_DIR/e2e/$platform"
    rm -rf "$directory" && mkdir -p "$directory" || exit 1
    rm -f "$RUN_DIR/e2e/$platform.log"
    absent=""
    if [ "$E2E_LOCK" = platform ] && [ "$platform" != app ]; then
      hold_take "$platform" "$HOLDER" run "$HOLD_LEASE" "$E2E_WAIT"
      case $? in
        0)  HELD="$platform"
            renew_hold "$platform" </dev/null >/dev/null 2>&1 &
            RENEWER=$! ;;
        75) absent="$HOLD_SAID"; BUSY="$(add_platform "$BUSY")" || exit 1 ;;
        *)  absent="$HOLD_SAID"; UNMADE="$(add_platform "$UNMADE")" || exit 1 ;;
      esac
    fi
    exit_code=75
    if [ -z "$absent" ]; then
      for try in first second; do
        rm -rf "$directory" && mkdir -p "$directory" || exit 1
        echo "── e2e $platform" >&2
        call_harness "$platform" "$directory" || {
          absent="$platform: the hold cannot be made at $HOLD_PLACE/$platform.lock"
          UNMADE="$(add_platform "$UNMADE")" || exit 1
          break
        }
        [ "$exit_code" -eq 75 ] && [ "$try" = first ] || break
        echo "   .review/e2e.sh says the device or a tool was not there (exit 75): "\
"$platform runs once more in $REPEAT_PAUSE s" >&2
        sleep "$REPEAT_PAUSE"
      done
      release_platform
      [ "$exit_code" -ne 75 ] || \
        absent="$platform: .review/e2e.sh says the device or a tool was not there (exit 75), twice"
      if [ -f "$RUN_DIR/e2e/$platform.timed-out" ]; then
        TIMED_OUT="$(jq -c --arg platform "$platform" --arg reason "$platform: .review/e2e.sh "\
"did not end in $E2E_TIMEOUT s (E2E_TIMEOUT) and was stopped" '. + {($platform): $reason}' \
          <<<"$TIMED_OUT")" || exit 1
      fi
    fi
    reports=()
    if [ -n "$absent" ]; then
      ENVIRONMENT="$(jq -c --arg platform "$platform" --arg reason "$absent" \
        '. + {($platform): $reason}' <<<"$ENVIRONMENT")" || exit 1
    else
      while IFS= read -r -d '' report; do
        reports+=("$report")
      done < <(find "$directory" -type f -iname '*.xml' -print0)
    fi
    if [ "${#reports[@]}" -gt 0 ]; then junit_rows "${reports[@]}"; fi \
      >"$RUN_DIR/e2e/$platform.rows.tsv"
    digests="$(for report in ${reports[@]+"${reports[@]}"}; do sha256_stdin <"$report"; done \
      | as_json_array)"
    RESULTS="$(jq -Rn --argjson results "$RESULTS" --arg platform "$platform" \
        --argjson exit "$exit_code" --argjson reports "$digests" '
      [inputs | split("\t") | {id: .[0], status: .[1]}] as $rows
      | $results + {($platform): ({exit: $exit, reports: $reports,
          timestamps: [$rows[] | select(.id == "#timestamp") | .status]}
          + ([ "passed", "failed", "skipped" ]
             | map({key: .,
                    value: (. as $status | [$rows[] | select(.status == $status) | .id] | unique)})
             | from_entries))}' <"$RUN_DIR/e2e/$platform.rows.tsv")" || exit 1
  done
fi

if [ "$(harness_blobs)" != "$HARNESS_BEFORE" ]; then
  echo "   the harness changed while it ran — .review/e2e.sh and the .review/e2e-* it calls" >&2
  echo "   must stay as they are: what ran is what land.sh compares with the harness at landing" >&2
  exit 1
fi

# The end-to-end tests check, they do not change: a build that writes outside
# .gitignore changes the tree the run is bound to, and every later check of
# the fingerprint would then blame something else. The loop's and the owner's
# files count here too: the tests change none of them either.
if [ "$(tree_fingerprint --whole)" != "$WHOLE_TREE" ]; then
  echo "   the e2e run modified the working tree — .review/e2e.sh must leave it as it found it;" >&2
  echo "   most likely build output that .gitignore does not cover" >&2
  exit 1
fi

# Every test a case names, with whether a skip tag of that case sits on it: such
# a test may be skipped — its task cannot land while the tag stays (land.sh) —
# but it must still be there to be skipped.
SKIP_TAGS="$(skip_tags)"
[ $? -le 1 ] || { echo "   could not search the tree for skipped end-to-end tests" >&2; exit 1; }
MARKED="$(printf '%s\n' "$MARKS" | marks_json)" || exit 1
CASE_COUNT="$(printf '%s\n' "$MARKS" | cut -f1 | grep -c .)"
NAMED="$(printf '%s\n' "$MARKS" | cut -f2 | as_json_array)"
REQUIRED="$(printf '%s\n' "$MARKS" | awk -F'\t' '$2 != ""' \
  | while IFS=$'\t' read -r case_id test_id; do
    tagged=false
    skip_tag_on "$SKIP_TAGS" "$case_id" "$test_id" && tagged=true
    jq -nc --arg case "$case_id" --arg test "$test_id" --argjson tagged "$tagged" \
      '{case: $case, test: $test, tagged: $tagged}'
  done | jq -sc .)" || exit 1

# A named test is matched on each platform by itself: a platform that runs it
# must pass it, and a platform that runs other tests of the class it ran in
# elsewhere — the same class, package and all, as a shared test is — must run
# it too. A parameterized row (shows42(int)[1]) counts for its method. A report
# whose testsuite says it ran more than a day before this run — a day, since
# time zones differ — is an old one copied over.
jq -n --arg task "$TASK_ID" --arg fingerprint "$FINGERPRINT" --arg harness "$HARNESS_BEFORE" \
      --argjson start "$START" --argjson qa "$QA_KNOWN" --argjson cases "$CASE_COUNT" \
      --argjson platforms "$(printf '%s\n' "$PLATFORMS" | as_json_array)" \
      --argjson results "$RESULTS" --argjson named "$NAMED" --argjson required "$REQUIRED" \
      --argjson marks "$MARKED" --argjson words "$CASE_DIGESTS" \
      --argjson preset "$PRESET_REASONS" --argjson unrun "$ENVIRONMENT" --argjson busy "$BUSY" \
      --argjson stopped "$TIMED_OUT" "$JQ_HIT"'
  def class: base | if test("\\.") then sub("\\.[^.]*$"; "") else null end;
  def rows: .passed + .failed + .skipped;
  def ran: .passed + .failed;
  def stamp: .[0:19] | try (strptime("%Y-%m-%dT%H:%M:%S") | mktime) catch null;
  def once: reduce .[] as $item ([]; if any(.[]; . == $item) then . else . + [$item] end);
  def prefixed($platform): startswith($platform + ": ");
  # A platform of the environment says nothing of the code: only the others are read. One
  # that E2E_TIMEOUT stopped is read from what it left: red where a test failed, otherwise
  # its tests could not be finished, as on a platform of the environment.
  (($unrun | keys_unsorted)
   + [$stopped | keys_unsorted[] | select(($results[.].failed | length) == 0)]) as $absent
  | [$results | to_entries[] | select(.key as $platform | $absent | index($platform) | not)]
    as $all
  | ([$unrun[]] + [$stopped | to_entries[] | select(.key as $platform | $absent
                                                     | index($platform)) | .value])
    as $environment
  | ([$preset[] | {kind: "no-harness", reason: .}]
     + [$all[] | .key as $platform | select($stopped | has($platform) | not) | .value
        | if (ran | length) == 0
            then {kind: "no-test", reason: "\($platform): the e2e run ran no test (exit \(.exit))"}
          elif .exit >= 126
            then {kind: "no-harness",
                  reason: "\($platform): .review/e2e.sh could not run or was killed (exit \(.exit))"}
          elif any(.timestamps[]; stamp as $time | $time != null and $time < $start - 86400)
            then {kind: "no-harness",
                  reason: ("\($platform): a report is older than this run (testsuite timestamp "
                           + "\(.timestamps | min)) — the harness copied results it did not make")}
          elif $cases > 0
               and ([ran[] as $row | $named[] | select(. as $id | $row | hit($id))] | length) == 0
            then {kind: "no-harness",
                  reason: "\($platform): no case of qa/test-cases.md names an e2e test that ran"}
          else empty end]
     + [range(0; $all | length) as $i | range(0; $i) as $j
        | select(any($all[$i].value.reports[]; . as $digest
                     | any($all[$j].value.reports[]; . == $digest)))
        | {kind: "no-harness",
           reason: ("\($all[$i].key): a report is the same file as one of \($all[$j].key)"
                    + " — each platform writes its own")}]
    ) as $faults
  | [$faults[].reason] as $no_harness
  | ([$all[] | .key as $platform | .value
      | (if $stopped | has($platform) then $stopped[$platform]
         elif .exit != 0 then "\($platform): .review/e2e.sh exited \(.exit)" else empty end),
        (.failed[] | "\($platform): failed: \(.)")]
     + [$required[] | . as $mark
        | ([$all[].value | rows[] | select(hit($mark.test)) | class | select(. != null)]
           | unique) as $classes
        | [$all[] | {platform: .key,
             passed: [.value.passed[] | select(hit($mark.test))],
             skipped: [.value.skipped[] | select(hit($mark.test))],
             listed: [.value | rows[] | select(hit($mark.test))],
             classmate: any(.value | rows[]; class as $other
                            | any($classes[]; . == $other))}] as $on
        | if ([$on[].passed[]] | length) == 0
             and (($mark.tagged | not) or ([$on[].skipped[]] | length) == 0)
            then (if ($absent | length) == 0 then "named but did not pass: \($mark.test)"
                  else empty end)
          else
            ($on[] | select((.skipped | length) > 0 and ($mark.tagged | not))
             | "\(.platform): named but did not pass: \($mark.test)"),
            ($on[] | select((.listed | length) == 0 and .classmate)
             | "\(.platform): named but did not run: \($mark.test)")
          end]
     | once) as $red
  # The worst of the platforms: no harness, no test that ran, red, the environment, pass.
  | (if any($faults[]; .kind == "no-harness") then "no-harness"
     elif ($faults | length) > 0 then "no-test"
     elif ($red | length) > 0 then "red"
     elif ($environment | length) > 0 then "environment"
     else "pass" end) as $status
  | {time: now, task: (if $task == "" then null else $task end),
     fingerprint: $fingerprint, harness: $harness, platforms: $platforms, qa_failures: $qa,
     marks: $marks, cases: $words,
     status: $status,
     reasons: (if $status == "no-harness" or $status == "no-test" then $no_harness
               elif $status == "red" then $red
               elif $status == "environment" then $environment else [] end),
     environment: $environment, busy: $busy,
     results: ($results | with_entries(.key as $platform
       | .value.outcome = (if $absent | index($platform) then "environment"
                           elif any($faults[]; .kind == "no-harness"
                                    and (.reason | prefixed($platform))) then "no-harness"
                           elif any($faults[]; .reason | prefixed($platform)) then "no-test"
                           elif any($red[]; prefixed($platform)) then "red"
                           else "pass" end)))}' >"$RUN_DIR/e2e.json" || exit 1

STATUS="$(jq -r '.status' "$RUN_DIR/e2e.json")"

show_failures() {
  local platform
  jq -r '.reasons[] | "  \(.)"' "$RUN_DIR/e2e.json"
  for platform in $(jq -r '.results | to_entries[]
      | select(.value.exit != 0 or (.value.failed | length) > 0 or (.value.passed | length) == 0)
      | .key' "$RUN_DIR/e2e.json"); do
    [ -f "$RUN_DIR/e2e/$platform.log" ] || continue
    echo "  ── the end of $RUN_DIR/e2e/$platform.log"
    tail -n 20 "$RUN_DIR/e2e/$platform.log" | sed 's/^/     /'
  done
}

case "$STATUS" in
  pass)
    echo "── e2e: pass on $(printf '%s' "$PLATFORMS" | tr '\n' ' ') "\
"— $(jq '[.results[].passed[]] | length' "$RUN_DIR/e2e.json") test(s) passed" ;;
  red)
    echo
    echo "E2E RED. Failing:"
    show_failures
    exit 2 ;;
  no-test)
    echo
    echo "NO END-TO-END TEST RAN — the harness is there and ran none:"
    show_failures
    turn loop "read the end of each log: a cause in the code is fixed; a device or a tool "\
"that was not there is restored, and review.sh run again repeats only the tests. A harness that "\
"knows its device is gone says so with exit 75 (templates/review/project/e2e.sh)"
    exit 1 ;;
  environment)
    echo
    echo "E2E COULD NOT RUN — the environment, not the code:"
    show_failures
    if [ "$UNMADE" != "[]" ]; then
      turn user:only-theirs "let the runs meet somewhere they can write: DEVICE_LOCK_DIR in "\
".review/land.conf, the same folder in every copy of the project, or E2E_LOCK=off where each "\
"copy has devices of its own — an edit of that file is theirs"
    elif json_holds --argjson busy "$BUSY" '[.results | to_entries[]
           | select(.value.outcome == "environment") | .key] - $busy == []' "$RUN_DIR/e2e.json"
    then
      turn loop "run review.sh again later: it repeats only these tests"
    else
      turn loop "restore it, then run review.sh again: it repeats only these tests, in this "\
"run, and counts no review"
    fi
    exit 75 ;;
  *)
    echo
    if [ ! -x "$HARNESS" ]; then
      echo "NO E2E HARNESS — copy CodingStandards/templates/review/project/e2e.sh to $HARNESS,"
      echo "  make it executable and fill it for: $(printf '%s' "$PLATFORMS" | tr '\n' ' '); "\
"the harness is a task"
      echo "  of its own and comes first."
    else
      echo "NO E2E HARNESS — the harness does not test this tree; it is a task of its own and "\
"comes first:"
      show_failures
    fi
    exit 1 ;;
esac
