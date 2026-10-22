#!/usr/bin/env bash
#
# export-version.sh — takes one version of the project out into a folder of its
# own, ready to build, without touching the working tree or the index: a replay
# of /qa, the version a change is compared with, or a copy whose code a check may
# break on purpose. Only git commands that read are used.
#
# Usage, from the project root:
#   export-version.sh <ref> <folder>      # a commit, branch or tag
#   export-version.sh WORKTREE <folder>   # the working tree as it is now, uncommitted work included
#
# Executable files keep their bit, symbolic links stay links, a submodule is
# linked to the project's own checkout of it, and local.properties (local, never
# committed, and needed by the Android build) is copied along when it exists.

set -euo pipefail

[ $# -eq 2 ] || { echo "usage: export-version.sh <ref>|WORKTREE <folder>" >&2; exit 1; }
REF="$1"
TARGET="$2"
ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

[ ! -e "$TARGET" ] || [ -z "$(ls -A "$TARGET" 2>/dev/null)" ] || {
  echo "$TARGET is not empty — export into an empty folder" >&2
  exit 1
}
mkdir -p "$TARGET"
TARGET="$(cd "$TARGET" && pwd)"

if [ "$REF" = "WORKTREE" ]; then
  git ls-files --cached --others --exclude-standard -z | while IFS= read -r -d '' path; do
    if [ -d "$path" ] && [ ! -L "$path" ]; then
      ln -s "$ROOT/$path" "$TARGET/$path"
    elif [ -e "$path" ] || [ -L "$path" ]; then
      mkdir -p "$TARGET/$(dirname "$path")"
      cp -P -p "$path" "$TARGET/$path"
    fi
  done
else
  git rev-parse --verify --quiet "$REF^{commit}" >/dev/null || { echo "no such commit: $REF" >&2; exit 1; }
  git ls-tree -r -z "$REF" | while IFS= read -r -d '' entry; do
    meta="${entry%%$'\t'*}"
    path="${entry#*$'\t'}"
    mode="${meta%% *}"
    object="${meta##* }"
    mkdir -p "$TARGET/$(dirname "$path")"
    case "$mode" in
      100644) git cat-file blob "$object" >"$TARGET/$path" ;;
      100755) git cat-file blob "$object" >"$TARGET/$path"; chmod +x "$TARGET/$path" ;;
      120000) ln -s "$(git cat-file blob "$object")" "$TARGET/$path" ;;
      160000) ln -s "$ROOT/$path" "$TARGET/$path" ;;
      *) echo "skipped $path: unknown mode $mode" >&2 ;;
    esac
  done
fi

[ ! -f "$ROOT/local.properties" ] || cp "$ROOT/local.properties" "$TARGET/local.properties"
echo "$REF → $TARGET"
