#!/usr/bin/env bash
#
# run.sh — one review pass: gates → reviewer → maintainer triage.
#
# The loop around this (rounds, landing, advancing) is driven by /maintain.
# Landing lives in land.sh.
#
# Runs FROM THE SUBMODULE. Never copy or edit this file: it is shared across
# projects and updates with `git submodule update --remote`.
#
# What it reads from your project (.review/ — yours to edit):
#   gates.sh, REVIEW_POLICY.md, land.conf, and any prompts/ or schemas/ you
#   choose to override.
# What it reads from the submodule (shared defaults):
#   prompts/, schemas/ — used whenever .review/ has no override.
#
# Usage, from your project root:
#   run.sh [--base <ref>] [--threshold <sev>] [--task-file <task.json>]
#
# Without --base, reviews the uncommitted work — exactly what land.sh commits.
# With --base <ref>, reviews the whole branch since that ref (a final pass).
#
# Exit codes:
#   0  clean — gates green, nothing accepted above the threshold
#   2  gates red — send the executor back with the gate output, no LLM review
#   3  accepted findings remain — hand them to the executor
#   4  escalations — a human decides
#   5  review unusable — every finding failed quote verification; re-run
#   1  pipeline error, including any malformed agent output (fails closed)
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

while [ $# -gt 0 ]; do
  case "$1" in
    --base)      require_value "--base" $#; BASE="$2"; shift 2 ;;
    --threshold) require_value "--threshold" $#; THRESHOLD_CLI="$2"; shift 2 ;;
    --task-file) require_value "--task-file" $#; TASK_FILE="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done

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
if [ -f "$PROJECT_ROOT/TASK_LOOP.md" ] && [ -f "$PROJECT_ROOT/templates/review/lib/run.sh" ]; then
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

# The task file has to live under `.review/`. That directory is the one place
# excluded from the tree fingerprint, and step 8 of the loop writes `verified_by`
# into the task file AFTER this review has run. Anywhere else, that write changes
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

# Different model per role — this is what keeps the maintainer from rubber-stamping
# the reviewer. Override to point a role at another vendor's CLI.
REVIEWER_CMD="${REVIEWER_CMD:-claude -p --model sonnet --allowedTools Read,Grep,Glob,Bash --output-format json}"
MAINTAINER_CMD="${MAINTAINER_CMD:-claude -p --model opus --allowedTools Read --output-format json}"

# The one thing the schemas cannot express: severities are ordered. Adding a
# severity to a schema without a rank here would make it compare against null,
# and in jq every number is >= null — the whole point of the threshold would
# quietly vanish. So the two are cross-checked rather than merely both existing.
RANKS='{"blocker":3,"major":2,"minor":1,"nit":0}'

SCHEMA_SEVERITIES="$(schema_enum "$(lib_file schemas/review-findings.schema.json)" findings severity)" || exit 1
if ! printf '%s' "$RANKS" | jq -e --argjson declared "$SCHEMA_SEVERITIES" \
     '(keys | sort) == ($declared | sort)' >/dev/null; then
  echo "the severity ranks in run.sh and the severities in the findings schema disagree." >&2
  echo "  ranks:  $(printf '%s' "$RANKS" | jq -rc 'keys | sort | join(", ")')" >&2
  echo "  schema: $(printf '%s' "$SCHEMA_SEVERITIES" | jq -rc 'sort | join(", ")')" >&2
  echo "  an unranked severity compares against null and defeats the threshold." >&2
  exit 1
fi

# An unknown threshold indexes to null, with the same consequence: a typo would
# send every nit to the executor and silently empty the optional list.
if ! printf '%s' "$RANKS" | jq -e --arg t "$THRESHOLD" 'has($t)' >/dev/null; then
  echo "unknown threshold '$THRESHOLD' — use $(printf '%s' "$RANKS" | jq -r 'keys_unsorted | join(", ")')" >&2
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
  # (--append-system-prompt "a b") must survive intact.
  if ! eval "$command" <"$prompt_file" | extract_json >"$output_file"; then
    echo "   $label failed to run" >&2
    return 1
  fi
  if ! jq -e . "$output_file" >/dev/null 2>&1; then
    echo "   $label returned invalid JSON — see $output_file" >&2
    return 1
  fi
}

# Nearest line in the file whose text contains the quote, or nothing at all.
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
                      | sort_by(.distance) | .[0].line)
          end
      end
  ' "$findings_file" 2>/dev/null
}

# Drops findings whose quote appears nowhere in the file, and corrects the line
# number of the rest. Cheap, deterministic, and it removes a large share of
# hallucinated findings before the maintainer sees them.
verify_quotes() {
  local input_file="$1" output_file="$2"
  local finding_id source_file cited_line actual_line
  local corrections=""

  # id, file and line come out in one read rather than one jq call each, and the
  # corrections accumulate as plain lines rather than by re-serialising a growing
  # JSON array per finding.
  while IFS=$'\t' read -r finding_id source_file cited_line; do
    if [ ! -f "$source_file" ]; then
      echo "   dropped $finding_id — no such file: $source_file" >&2
      continue
    fi
    actual_line="$(locate_quote "$input_file" "$finding_id" "$source_file")"
    if [ -z "$actual_line" ]; then
      echo "   dropped $finding_id — quote not found anywhere in $source_file" >&2
      continue
    fi
    if [ "$actual_line" != "$cited_line" ]; then
      echo "   relocated $finding_id — $source_file:$cited_line → :$actual_line" >&2
    fi
    corrections="$corrections$finding_id $actual_line"$'\n'
  done < <(jq -r '.findings[] | [.id, .file, .line] | @tsv' "$input_file")

  # A finding with no correction line was dropped, and drops must be silent
  # losses of noise only — an id that survives always carries a located line.
  printf '%s' "$corrections" | jq -R --slurpfile findings "$input_file" -s '
    ( split("\n") | map(select(length > 0) | split(" ") | {id: .[0], line: (.[1] | tonumber)}) ) as $corrections
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
    (.verdicts | type) == "array"
      and (.verdicts | length) > 0
      and all(.verdicts[];
              ((.finding_id? // "") != "")
              and ($verdicts | index(.verdict? // "")) != null
              and ($severities | index(.severity? // "")) != null
              and ($rules | index(.decision_rule? // "")) != null
              and ((.reason? // "") | length) >= $min_reason)
  ' "$verdicts_file" >/dev/null 2>&1 || {
    echo "   maintainer output is malformed. Every verdict needs finding_id, plus:" >&2
    echo "     verdict       $(printf '%s' "$verdict_values" | jq -r 'join("|")')" >&2
    echo "     severity      $(printf '%s' "$severity_values" | jq -r 'join("|")')" >&2
    echo "     decision_rule $(printf '%s' "$rule_values" | jq -r 'join("|")')" >&2
    echo "     reason        at least $min_reason characters" >&2
    echo "   decision_rule is the field Track A is analysed on; a verdict without" >&2
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
      | "   verdicts for unknown findings: \($unknown | join(", ") // "none")\n   findings with no verdict: \($unjudged | join(", ") // "none")"
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
# still only ever commits the uncommitted work.
if [ -n "$BASE" ]; then
  DIFF_FROM="$(git merge-base "$BASE" HEAD)" || exit 1
else
  DIFF_FROM="HEAD"
fi
# `.review/` is pipeline bookkeeping, not task code: land.sh never stages it,
# so the reviewer must not spend findings on it either.
git diff "$DIFF_FROM" -- . ':(exclude).review' >"$RUN_DIR/diff.patch"

# Untracked files are invisible to `git diff` but land.sh will commit them, so
# a whole new source file would otherwise be committed with no review at all.
while IFS= read -r untracked; do
  [ -n "$untracked" ] || continue
  git diff --no-index -- /dev/null "$untracked" >>"$RUN_DIR/diff.patch" 2>/dev/null
done < <(git ls-files --others --exclude-standard | grep -v '^\.review/')

if [ ! -s "$RUN_DIR/diff.patch" ]; then
  echo "no changes against ${BASE:-HEAD} — nothing to review"
  exit 0
fi

REVIEWED_FINGERPRINT="$(tree_fingerprint)"
jq -n --arg base "${BASE:-HEAD}" --arg threshold "$THRESHOLD" \
      --arg fingerprint "$REVIEWED_FINGERPRINT" --arg task "$TASK_FILE" \
      '{base: $base, threshold: $threshold, tree_fingerprint: $fingerprint,
        task_file: (if $task == "" then null else $task end)}' >"$RUN_DIR/meta.json"

# ---------------------------------------------------------------------------
# 2. Layer 0 — gates. Ground truth, and a hard stop.
# ---------------------------------------------------------------------------

"$REVIEW_DIR/gates.sh" "$RUN_DIR/gates.json" >/dev/null
GATES_EXIT=$?

# A gate runner that could not run is not a red gate. 126/127, or no usable
# gates.json, means there is no gate output to send anywhere — and "GATES RED"
# with an empty failure list would put the executor to work on nothing.
if [ "$GATES_EXIT" -ge 126 ] || ! jq -e 'type == "object"' "$RUN_DIR/gates.json" >/dev/null 2>&1; then
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
  jq -r 'to_entries[] | select(.value.status == "fail") | "  \(.key): \(.value.command)\n\(.value.output)"' \
    "$RUN_DIR/gates.json"
  exit 2
fi

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
} >"$RUN_DIR/reviewer-prompt.md"

run_agent "$REVIEWER_CMD" "$RUN_DIR/reviewer-prompt.md" "$RUN_DIR/findings.raw.json" "reviewer" || exit 1

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
  (.findings | type) == "array"
    and (([.findings[].id] | length) == ([.findings[].id] | unique | length))
    and all(.findings[];
            ((.id? // "") | test("^F-[0-9]{3}$"))
            and ((.file? // "") != "")
            and ((.line? | type) == "number" and .line == (.line | floor) and .line >= 1)
            and ((.code_quote? // "") != "")
            and ($categories | index(.category? // "")) != null
            and ($severities | index(.severity? // "")) != null
            and ($confidences | index(.confidence? // "")) != null
            and ((.evidence? // "") != ""))
' "$RUN_DIR/findings.raw.json" >/dev/null 2>&1 || {
  echo "   reviewer output does not match the findings schema — see $RUN_DIR/findings.raw.json" >&2
  echo "   required per finding: id (F-nnn), file, line, code_quote, category," >&2
  echo "   severity, confidence, evidence — all from the schema's enums;" >&2
  echo "   ids must be unique within the run" >&2
  jq -r '[.findings[].id] | group_by(.) | map(select(length > 1) | .[0]) as $dupes
         | if ($dupes | length) > 0 then "   duplicate ids: \($dupes | join(", "))" else empty end' \
    "$RUN_DIR/findings.raw.json" >&2 2>/dev/null
  exit 1
}

RAW_COUNT="$(jq '.findings | length' "$RUN_DIR/findings.raw.json")"
verify_quotes "$RUN_DIR/findings.raw.json" "$RUN_DIR/findings.json" || {
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
    echo "Decision rule 4 (out of task scope) and any scope-based policy rule are"
    echo "judged against this. Files outside .scope are not this task's problem."
    cat "$TASK_FILE"
    echo
    echo "## Files changed in this diff"
    git diff --name-only "$DIFF_FROM" -- . ':(exclude).review'
    git ls-files --others --exclude-standard | grep -v '^\.review/'
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

run_agent "$MAINTAINER_CMD" "$RUN_DIR/maintainer-prompt.md" "$RUN_DIR/verdicts.json" "maintainer" || exit 1
validate_verdicts "$RUN_DIR/verdicts.json" "$RUN_DIR/findings.json" || exit 1

# ---------------------------------------------------------------------------
# 5. Filter — only accepted findings at or above the threshold reach the executor
# ---------------------------------------------------------------------------

jq --argjson rank "$RANKS" --arg threshold "$THRESHOLD" --slurpfile findings "$RUN_DIR/findings.json" '
  [ .verdicts[]
    | . as $verdict
    | select($verdict.verdict == "accept" and $rank[$verdict.severity] >= $rank[$threshold])
    | $verdict + {finding: ($findings[0].findings[] | select(.id == $verdict.finding_id))}
  ]' "$RUN_DIR/verdicts.json" >"$RUN_DIR/approved.json" || exit 1

jq '[.verdicts[] | select(.verdict == "escalate")]' "$RUN_DIR/verdicts.json" >"$RUN_DIR/escalated.json" || exit 1
jq --argjson rank "$RANKS" --arg threshold "$THRESHOLD" \
  '[.verdicts[] | select(.verdict == "accept" and $rank[.severity] < $rank[$threshold])]' \
  "$RUN_DIR/verdicts.json" >"$RUN_DIR/optional.json" || exit 1

APPROVED_COUNT="$(require_array_length "$RUN_DIR/approved.json")" || exit 1
ESCALATED_COUNT="$(require_array_length "$RUN_DIR/escalated.json")" || exit 1
OPTIONAL_COUNT="$(require_array_length "$RUN_DIR/optional.json")" || exit 1
REJECTED_COUNT="$(jq '[.verdicts[] | select(.verdict == "reject")] | length' "$RUN_DIR/verdicts.json")"

echo
echo "── review complete: $RUN_DIR"
echo "   verified findings : $FINDING_COUNT   (of $RAW_COUNT reported, $DROPPED_COUNT dropped)"
echo "   accepted (>= $THRESHOLD): $APPROVED_COUNT   → approved.json, for the executor"
echo "   accepted (below)  : $OPTIONAL_COUNT   → optional.json, for the user"
echo "   escalated         : $ESCALATED_COUNT   → escalated.json, for the user"
echo "   rejected          : $REJECTED_COUNT"

[ "$ESCALATED_COUNT" -gt 0 ] && exit 4
[ "$APPROVED_COUNT" -gt 0 ] && exit 3
exit 0
