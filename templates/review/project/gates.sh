#!/usr/bin/env bash
#
# .review/gates.sh — Layer 0: deterministic gates.
#
# THIS FILE BELONGS TO YOUR PROJECT, NOT TO THE SUBMODULE.
# Copied once from CodingStandards/templates/review/project/ into your repo's
# .review/, then edited freely — submodule updates never touch it.
#
# It is also the only language-specific file in the pipeline: fill in the five
# slots at the bottom for your stack and nothing else changes between projects.
#
# Usage:   .review/gates.sh [output-path]
# Writes:  JSON gate results (default .review/runs/latest/gates.json)
# Exit:    0 — all blocking gates passed
#          1 — a blocking gate failed
#
# Requires: jq >= 1.6

set -uo pipefail

OUT="${1:-.review/runs/latest/gates.json}"
mkdir -p "$(dirname "$OUT")"

RESULTS_FILE="$(mktemp)"
trap 'rm -f "$RESULTS_FILE"' EXIT
BLOCKING_FAILURE=0
MAX_OUTPUT_CHARS=4000

# run_gate <slot> <blocking:yes|no> <command...>
run_gate() {
  local slot="$1" blocking="$2"
  shift 2
  local command="$*"
  local log_file status

  log_file="$(mktemp)"
  printf '── gate %-7s %s\n' "$slot" "$command" >&2

  if eval "$command" >"$log_file" 2>&1; then
    status="pass"
  else
    status="fail"
    if [ "$blocking" = "yes" ]; then
      BLOCKING_FAILURE=1
    fi
  fi

  printf '   %s\n' "$status" >&2

  jq -n \
    --arg slot "$slot" \
    --arg status "$status" \
    --arg command "$command" \
    --argjson blocking "$([ "$blocking" = "yes" ] && echo true || echo false)" \
    --rawfile output "$log_file" \
    --argjson maxChars "$MAX_OUTPUT_CHARS" \
    '{
       key: $slot,
       value: {
         status: $status,
         blocking: $blocking,
         command: $command,
         output: (if ($output | length) > $maxChars
                  then ($output | .[(length - $maxChars):])
                  else $output end)
       }
     }' >>"$RESULTS_FILE"

  rm -f "$log_file"
}

# ---------------------------------------------------------------------------
# The five slots. Replace the commands; keep the slot names.
# See TASK_LOOP.md § "Wiring a new language" for per-stack commands.
# ---------------------------------------------------------------------------

# 1. build — does it compile / typecheck?
run_gate build yes "echo 'TODO: build command' && false"

# 2. test — do the tests pass?
run_gate test yes "echo 'TODO: test command' && false"

# 3. format — is it formatted canonically? (a PostToolUse hook should have
#    already auto-fixed this; failing here means the hook is not wired up)
run_gate format yes "echo 'TODO: format check command' && false"

# 4. lint — any known-bad patterns?
run_gate lint yes "echo 'TODO: lint command' && false"

# 5. arch — do the architecture rules hold? Write these as ordinary unit tests
#    if the stack has no dedicated tool. See ARCHITECTURE.md.
run_gate arch yes "echo 'TODO: architecture rule tests' && false"

# Examples (delete the stubs above and uncomment what fits):
#
# Kotlin / KMP
#   run_gate build yes  "./gradlew compileKotlinMetadata compileKotlinJvm"
#   run_gate test  yes  "./gradlew allTests"
#   run_gate format yes "./gradlew ktlintCheck"
#   run_gate lint  yes  "./gradlew detekt"
#   run_gate arch  yes  "./gradlew :architecture:test"
#
# Swift
#   run_gate build yes  "swift build"
#   run_gate test  yes  "swift test"
#   run_gate format yes "swift-format lint --recursive Sources"
#   run_gate lint  yes  "swiftlint --strict"
#   run_gate arch  yes  "swift test --filter ArchitectureTests"
#
# TypeScript
#   run_gate build yes  "npx tsc --noEmit"
#   run_gate test  yes  "npx vitest run"
#   run_gate format yes "npx prettier --check ."
#   run_gate lint  yes  "npx eslint ."
#   run_gate arch  yes  "npx depcruise --validate src"
#
# Rust
#   run_gate build yes  "cargo check --all-targets"
#   run_gate test  yes  "cargo test"
#   run_gate format yes "cargo fmt --check"
#   run_gate lint  yes  "cargo clippy --all-targets -- -D warnings"
#   run_gate arch  yes  "cargo test --test architecture"
#
# Go
#   run_gate build yes  "go build ./..."
#   run_gate test  yes  "go test ./..."
#   run_gate format yes "test -z \"\$(gofmt -l .)\""
#   run_gate lint  yes  "golangci-lint run"
#   run_gate arch  yes  "go-arch-lint check"
#
# Python
#   run_gate build yes  "mypy src"
#   run_gate test  yes  "pytest -q"
#   run_gate format yes "ruff format --check ."
#   run_gate lint  yes  "ruff check ."
#   run_gate arch  yes  "lint-imports"

# ---------------------------------------------------------------------------

jq -s 'from_entries' "$RESULTS_FILE" >"$OUT"
cat "$OUT"

exit "$BLOCKING_FAILURE"
