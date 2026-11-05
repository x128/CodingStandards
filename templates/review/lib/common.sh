#!/usr/bin/env bash
#
# common.sh — helpers shared by review.sh, land.sh and publish.sh.
#
# Runs from the submodule; not overridable. Sourced, never executed.

# The files the loop itself keeps as it goes: the tracker at the root (PLANNING_GUIDE.md)
# and the test cases of /qa. They are in no task's scope and are written after the
# review, so neither the reviewer, nor the scope check, nor the fingerprint looks at
# them. They land with the task: otherwise a line in the tracker would refuse the next
# task, and they would reach main only by hand.
LOOP_FILES=(TASK_TRACKER.md qa/test-cases.md)

# The requirements and the plan change only with the product owner's answer. They are
# not task work, and no landing commits them: like the policy under .review/, the user
# reads and commits them.
OWNER_FILES=(REQUIREMENTS.md PLAN.md)

NOT_TASK_WORK=(':(exclude).review')
for loop_file in "${LOOP_FILES[@]}" "${OWNER_FILES[@]}"; do
  NOT_TASK_WORK+=(":(exclude)$loop_file")
done
unset loop_file

is_loop_file() {
  local file
  for file in "${LOOP_FILES[@]}"; do
    [ "$1" != "$file" ] || return 0
  done
  return 1
}

is_owner_file() {
  local file
  for file in "${OWNER_FILES[@]}"; do
    [ "$1" != "$file" ] || return 0
  done
  return 1
}

# The paths on stdin that are the task's own work.
only_task_work() {
  local path
  while IFS= read -r path; do
    case "$path" in .review/*) continue ;; esac
    is_loop_file "$path" || is_owner_file "$path" || printf '%s\n' "$path"
  done
}

# Fingerprint of everything the reviewer saw: HEAD and the tree outside `.review/`
# and the loop's own files. review.sh records it; land.sh recomputes it and
# refuses when it differs — a review of a tree that has since changed is not a
# review of what is about to be committed. HEAD counts as the commit it names,
# never as a branch name, so the task branch land.sh creates from HEAD leaves the
# fingerprint as it was.
#
# The tree goes through a throwaway copy of the index, so every change reads the
# same, tracked or new, staged or not: a landing whose commit failed leaves its new
# files staged, and that must not read as a tree that changed.
tree_fingerprint() {
  local scratch
  scratch="$(mktemp -d)" || return 1
  # -p: git trusts an entry whose file is older than the index, so a copy that looks
  # newer than the real one would hide an edit made in the second of the last `git add`.
  cp -p "$(git rev-parse --git-path index)" "$scratch/index" 2>/dev/null
  {
    git rev-parse HEAD
    # `.review/` is pipeline bookkeeping and is excluded on BOTH sides: the task
    # file is tracked and is filled in (verified_by) after the review by design,
    # so including it here would invalidate every run before it could land.
    GIT_INDEX_FILE="$scratch/index" git add -A -- . "${NOT_TASK_WORK[@]}" 2>/dev/null
    GIT_INDEX_FILE="$scratch/index" git diff --cached --binary HEAD -- . "${NOT_TASK_WORK[@]}"
  } | sha256_stdin
  rm -rf "$scratch"
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

# The level of LANDING in a project's land.conf; with no such line, off. Prints it,
# or why there is none and fails: both scripts refuse then. A typo must never read
# as off, and still less as on, and read_conf skips a line it cannot match — so a
# line that means LANDING is looked for here in every spelling.
landing_level() {
  local config_file="$1" line value
  line="$(grep -iE '^[[:space:]]*(export[[:space:]]+)?LANDING[[:space:]]*=' \
"$config_file" 2>/dev/null | tail -1)"
  if [ -z "$line" ]; then
    printf 'off'
    return 0
  fi
  if ! printf '%s' "$line" | grep -qE '^[[:space:]]*LANDING='; then
    printf 'the line "%s" in %s is not LANDING=<level>, with one of off, on, push, pr, merge' \
      "$line" "$config_file"
    return 1
  fi
  value="$(read_conf "$config_file" LANDING "")"
  case "$value" in
    off|on|push|pr|merge) printf '%s' "$value" ;;
    *) printf 'LANDING=%s in %s is not one of off, on, push, pr, merge' "$value" "$config_file"
       return 1 ;;
  esac
}

landing_publishes() {
  case "$1" in push|pr|merge) return 0 ;; *) return 1 ;; esac
}

landing_opens_pull_request() {
  case "$1" in pr|merge) return 0 ;; *) return 1 ;; esac
}

# A task id that can name task/<id>. Both scripts use it before they trust the id:
# it also goes into a trailer and a comparison, where a line break would be two ids.
task_id_names_branch() {
  [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]] && git check-ref-format "refs/heads/task/$1"
}

# The branch HEAD is on, by its plain name, and nothing on a detached HEAD. Not
# `git rev-parse --abbrev-ref HEAD`: with a tag of the same name that prints
# heads/main, which is in no list of protected branches.
current_branch() {
  git branch --show-current
}

# Projects may add protected branches; they cannot remove the built-in ones.
protected_branches() {
  printf 'main master %s' "$(read_conf "$1" PROTECTED_BRANCHES "")"
}

lowercase() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

# Case is ignored: where the filesystem ignores it, `git checkout Main` puts HEAD on
# a branch named Main whose commits land on main.
branch_in_list() {
  local branch listed
  branch="$(lowercase "$1")"
  for listed in $(lowercase "$2"); do
    [ "$branch" != "$listed" ] || return 0
  done
  return 1
}

# The remote to publish to. Never assumes `origin`: a project's remote can have
# any name. Prints it, or prints why there is none and fails.
resolve_remote() {
  local config_file="$1" configured remotes
  configured="$(read_conf "$config_file" REMOTE "")"
  remotes="$(git remote)"
  if [ -n "$configured" ]; then
    if printf '%s\n' "$remotes" | grep -xF -- "$configured" >/dev/null; then
      printf '%s' "$configured"
      return 0
    fi
    printf 'REMOTE=%s in %s is not a remote of this repository' "$configured" "$config_file"
    return 1
  fi
  if printf '%s\n' "$remotes" | grep -xF origin >/dev/null; then
    printf 'origin'
    return 0
  fi
  case "$(printf '%s' "$remotes" | grep -c '')" in
    0) printf 'this repository has no remote' ;;
    1) printf '%s' "$remotes"; return 0 ;;
    *) printf 'there are several remotes and none is named origin — set REMOTE in %s' \
         "$config_file" ;;
  esac
  return 1
}

# The branch pull requests go to, which is also protected at the levels that
# publish. Asked of the remote every time: the HEAD a clone recorded stays as it
# was when the remote's default branch changes, and the real one would then be left
# unprotected. A remote that cannot be asked is no answer, so nothing is guessed
# here: the guesses are for a remote that answers and has no HEAD. Prints the
# branch, or why it cannot be known and fails.
resolve_base_branch() {
  local config_file="$1" remote="$2" base answer
  base="$(read_conf "$config_file" BASE_BRANCH "")"
  if [ -n "$base" ]; then
    printf '%s' "$base"
    return 0
  fi
  answer="$(git ls-remote --symref "$remote" HEAD 2>/dev/null)" || {
    printf 'the remote %s cannot be reached' "$remote"
    return 1
  }
  base="$(printf '%s\n' "$answer" | \
sed -n 's|^ref:[[:space:]]*refs/heads/\([^[:space:]]*\)[[:space:]]*HEAD$|\1|p')"
  if [ -z "$base" ]; then
    if git show-ref --verify --quiet refs/heads/main \
       || git show-ref --verify --quiet "refs/remotes/$remote/main"; then
      base=main
    else
      base=master
    fi
  fi
  printf '%s' "$base"
}

# OWNER/REPO of a remote, with the host in front when it is not github.com, for gh's
# --repo. gh otherwise picks a repository of its own among the remotes, in an order
# that has nothing to do with REMOTE, and would act on another one than the push
# went to. Works on the last two segments of the URL's path, whatever its form.
remote_repository() {
  local url host="" repository
  url="$(git remote get-url "$1")" || return 1
  url="${url%/}"
  url="${url%.git}"
  case "$url" in
    *://*) url="${url#*://}"; url="${url#*@}"; host="${url%%/*}"; url="${url#*/}" ;;
    /*|./*|../*) ;;
    *:*) url="${url#*@}"; host="${url%%:*}"; url="${url#*:}" ;;
  esac
  repository="${url##*/}"
  url="${url%/*}"
  repository="${url##*/}/$repository"
  host="${host%%:*}"
  case "$host" in
    ""|github.com|ssh.github.com) printf '%s' "$repository" ;;
    *) printf '%s/%s' "$host" "$repository" ;;
  esac
}

# What stops this level from publishing, known before anything is done: land.sh
# refuses on it before the commit, so that a landing never ends half done for a
# reason it could have named, and publish.sh refuses on it when run alone.
# Prints the reason and fails, or prints nothing.
publishing_problem() {
  local config_file="$1" level="$2" remote="$3" base="$4" base_on_remote repository checks_wait
  base_on_remote="$(git ls-remote --heads "$remote" "refs/heads/$base" 2>/dev/null)" || {
    printf 'the remote %s cannot be reached' "$remote"
    return 1
  }
  landing_opens_pull_request "$level" || return 0
  [ -n "$base_on_remote" ] || {
    printf 'the base branch %s is not on the remote %s — set BASE_BRANCH in %s, or push it' \
      "$base" "$remote" "$config_file"
    return 1
  }
  command -v gh >/dev/null 2>&1 || {
    printf 'LANDING=%s needs gh, and gh is not installed' "$level"
    return 1
  }
  gh auth status >/dev/null 2>&1 || {
    printf 'LANDING=%s needs gh, and gh is not logged in — run gh auth login' "$level"
    return 1
  }
  repository="$(remote_repository "$remote")"
  gh repo view "$repository" --json name >/dev/null 2>&1 || {
    printf 'gh cannot see %s, the repository of the remote %s' "$repository" "$remote"
    return 1
  }
  checks_wait="$(read_conf "$config_file" CHECKS_WAIT 30)"
  case "$checks_wait" in
    *[!0-9]*)
      printf 'CHECKS_WAIT=%s in %s is not a whole number of seconds' "$checks_wait" "$config_file"
      return 1 ;;
  esac
}

# The Task-Id of a commit: what land.sh wrote into it, or nothing.
task_id_of() {
  git log -1 --format='%(trailers:key=Task-Id,valueonly)' "$1"
}

# Commits of this branch that no landing made, one per line. At push and pr these
# are the ones the push would add to the remote: a person merges afterwards and sees
# what the branch holds. What the remote has is what it says now, as far as those
# commits are known here, and what this repository last heard from it. At merge
# nobody looks, so it is everything not yet on the base branch. A merge commit
# counts as neither: agents cannot make one, it is how a person brings the base into
# a branch that conflicts with it, and the commits it brings in from anywhere else
# are listed themselves.
commits_no_landing_made() {
  local level="$1" remote="$2" base="$3" published commit
  if [ "$level" = "merge" ] && git show-ref --verify --quiet "refs/remotes/$remote/$base"; then
    published="^refs/remotes/$remote/$base"
  else
    published="$(git ls-remote --heads "$remote" 2>/dev/null | cut -f1 \
                 | git cat-file --batch-check='%(objectname) %(objecttype)' \
                 | awk '$2 == "commit" { print "^" $1 }'
                 git for-each-ref --format='^%(objectname)' "refs/remotes/$remote/")"
  fi
  printf 'HEAD\n%s\n' "$published" | git rev-list --no-merges --stdin \
    | while IFS= read -r commit; do
    [ -n "$(task_id_of "$commit")" ] || git log -1 --format='%h %s' "$commit"
  done
}

# Guards a flag that takes a value: `--threshold` as the last argument would
# otherwise read $2 under `set -u` and die with "unbound variable".
require_value() { [ "$2" -ge 2 ] || { echo "$1 needs a value" >&2; exit 1; }; }

# Absolute path of an existing file. Both scripts cd to the project root early,
# so every path taken from the command line must be resolved BEFORE that cd —
# otherwise a relative path given from a subdirectory silently means a different
# file afterwards, and the mismatch surfaces as a confusing landing refusal
# rather than as the usage error it is. Symbolic links are resolved (`pwd -P`),
# as `git rev-parse --show-toplevel` resolves them: a project reached through a
# link — any temporary folder on macOS — would otherwise fail every comparison
# of a path with the project root.
abspath() {
  local target="$1" directory
  directory="$(cd "$(dirname "$target")" 2>/dev/null && pwd -P)" || return 1
  if [ -d "$target" ]; then
    printf '%s' "$(cd "$target" && pwd -P)"
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
