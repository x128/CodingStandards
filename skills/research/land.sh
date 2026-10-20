#!/usr/bin/env bash
# land.sh — commits one research topic folder, when the project said so.
#
# Usage: bash land.sh <topic folder> "<subject>"   (run from inside the project)
# The project's answer lives in <topic folder>/../land.conf: LANDING=on | off.
# Missing or anything but "on" means off: the script lists the changed files and stops.
# With on, it commits only that folder, on the branch that is checked out.
# It never pushes, creates or switches a branch, amends, resets or adds a worktree.

usage() { echo "usage: bash land.sh <topic folder> \"<subject>\"" >&2; exit 1; }

[ $# -eq 2 ] && [ -n "$2" ] || usage
subject=$2
dir=$(cd -P -- "$1" 2>/dev/null && pwd -P) || { echo "land.sh: no such folder: $1" >&2; usage; }

top=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -z "$top" ]; then
  echo "Not inside a git repository: nothing is committed. The files are in $dir"
  exit 0
fi
top=$(cd -P "$top" && pwd -P)

# The skill's own repository, found from where this file really is (symlinks resolved).
skill_dir=$(cd -P "$(dirname "$0")" && pwd -P)
skill_top=$(git -C "$skill_dir" rev-parse --show-toplevel 2>/dev/null)
[ -n "$skill_top" ] && skill_top=$(cd -P "$skill_top" && pwd -P)
if [ "$top" = "$skill_top" ]; then
  echo "land.sh: refused — this is the skill's own repository; research belongs to the project that uses the skill." >&2
  exit 3
fi

case "$dir" in
  "$top"/*) ;;
  *) echo "land.sh: $dir is not inside the project $top" >&2; usage ;;
esac

# Read as data, never sourced: the last LANDING= line wins.
landing=$(sed -n 's/^[[:space:]]*LANDING[[:space:]]*=[[:space:]]*"\{0,1\}\([A-Za-z]*\).*/\1/p' \
  "$dir/../land.conf" 2>/dev/null | tail -n 1)

if git -C "$top" check-ignore -q -- "$dir"; then
  echo "Not committed: the project's .gitignore covers $dir. The files are in $dir"
  exit 0
fi

# --no-optional-locks: even this read must not refresh the project's index.
changed=$(git --no-optional-locks -C "$top" status --porcelain --untracked-files=all -- "$dir")
if [ "$landing" != "on" ]; then
  if [ -z "$changed" ]; then echo "Nothing changed under $dir."; exit 0; fi
  echo "$changed"
  echo "Not committed: LANDING=off for this project. The files are in $dir"
  exit 0
fi

[ -n "$changed" ] || { echo "Nothing changed under $dir; nothing to commit."; exit 0; }
branch=$(git -C "$top" branch --show-current)
[ -n "$branch" ] || {
  echo "land.sh: refused — HEAD is detached; check out a branch first." >&2
  exit 3
}

# The project's answer goes with the research, so other clones are not asked again.
paths=("$dir")
[ -f "$dir/../land.conf" ] && paths+=("$(cd -P "$dir/.." && pwd -P)/land.conf")
if ! git -C "$top" add -- "${paths[@]}" || ! git -C "$top" commit --only -m "$subject" -- "${paths[@]}"; then
  echo "land.sh: the commit failed (git says why above; often a hook). The files of $dir stay staged." >&2
  exit 1
fi
echo "Committed $(git -C "$top" rev-parse --short HEAD) on $branch: $subject"
