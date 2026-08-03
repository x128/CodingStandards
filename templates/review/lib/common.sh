#!/usr/bin/env bash
#
# common.sh — helpers shared by run.sh and land.sh.
#
# Runs from the submodule; not overridable. Sourced, never executed.

# Fingerprint of everything the reviewer saw: HEAD, tracked changes, and the
# content of untracked files. run.sh records it; land.sh recomputes it and
# refuses when it differs — a review of a tree that has since changed is not a
# review of what is about to be committed.
tree_fingerprint() {
  {
    git rev-parse HEAD
    # `.review/` is pipeline bookkeeping and is excluded on BOTH sides: the task
    # file is tracked and is filled in (verified_by) after the review by design,
    # so including it here would invalidate every run before it could land.
    git diff HEAD -- . ':(exclude).review'
    git ls-files --others --exclude-standard | grep -v '^\.review/' | while IFS= read -r file; do
      printf '%s\n' "$file"
      cat "$file" 2>/dev/null
    done
  } | sha256_stdin
}

sha256_stdin() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | cut -d' ' -f1
  else
    sha256sum | cut -d' ' -f1
  fi
}

# Reads one key from a project's land.conf as DATA. The config is never sourced:
# sourcing it would let a project redefine `git`, `jq`, or any guard in the
# scripts that read it, which contradicts the whole point of landing authority
# living in a file the project cannot edit.
read_conf() {
  local config_file="$1" key="$2" fallback="$3" value
  [ -f "$config_file" ] || { printf '%s' "$fallback"; return; }
  value="$(grep -E "^[[:space:]]*${key}=" "$config_file" 2>/dev/null \
           | tail -1 | cut -d= -f2- \
           | sed -e 's/[[:space:]]*#.*$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
           | sed -e 's/^"//' -e "s/^'//" -e 's/"$//' -e "s/'$//")"
  printf '%s' "${value:-$fallback}"
}

# Guards a flag that takes a value: `--threshold` as the last argument would
# otherwise read $2 under `set -u` and die with "unbound variable".
require_value() { [ "$2" -ge 2 ] || { echo "$1 needs a value" >&2; exit 1; }; }

# Absolute path of an existing file. Both scripts cd to the project root early,
# so every path taken from the command line must be resolved BEFORE that cd —
# otherwise a relative path given from a subdirectory silently means a different
# file afterwards, and the mismatch surfaces as a confusing landing refusal
# rather than as the usage error it is.
abspath() {
  local target="$1" directory
  directory="$(cd "$(dirname "$target")" 2>/dev/null && pwd)" || return 1
  if [ -d "$target" ]; then
    printf '%s' "$(cd "$target" && pwd)"
  else
    printf '%s/%s' "$directory" "$(basename "$target")"
  fi
}

# Prints the length of a JSON array, or fails. Never prints a non-number:
# an unparseable file must stop the pipeline, not read as "nothing found".
require_array_length() {
  local file="$1" length
  if [ ! -f "$file" ]; then
    echo "missing $file" >&2
    return 1
  fi
  length="$(jq -e 'if type == "array" then length else empty end' "$file" 2>/dev/null)" || {
    echo "$file is not a JSON array — refusing to treat it as empty" >&2
    return 1
  }
  printf '%s' "$length"
}
