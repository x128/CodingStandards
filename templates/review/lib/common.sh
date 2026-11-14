#!/usr/bin/env bash
#
# common.sh — helpers shared by review.sh, land.sh, publish.sh, pr-post.sh and e2e-gate.sh.
#
# Runs from the submodule; not overridable. Sourced, never executed.

# The files the loop itself keeps as it goes: the tracker at the root (PLANNING_GUIDE.md)
# and the test cases of /qa. They are in no task's scope and are written after the
# review, so neither the reviewer, nor the scope check, nor the fingerprint looks at
# them. They land with the task: otherwise a line in the tracker would refuse the next
# task, and they would reach main only by hand.
LOOP_FILES=(TASK_TRACKER.md qa/test-cases.md)

# The requirements and the plan change only with the product owner's answer, apart from
# the `[x]` of a finished task in the plan. They are not task work: a landing commits
# them only with WITH_RECORDS=yes (land.sh), and otherwise, like the policy under
# .review/, the user reads and commits them.
OWNER_FILES=(REQUIREMENTS.md PLAN.md)

NOT_TASK_WORK=(':(exclude).review')

# The end-to-end harness: `.review/e2e.sh` and any `.review/e2e-*` it calls. It lives
# under `.review/` but is reviewed and lands like task work: a change to it is in the
# reviewed diff and the fingerprint, and lands in the task's commit — so a harness
# changed to pass without a test running does not go unseen.
HARNESS=(.review/e2e.sh ':(glob).review/e2e-*')
for loop_file in "${LOOP_FILES[@]}" "${OWNER_FILES[@]}"; do
  NOT_TASK_WORK+=(":(exclude)$loop_file")
done
unset loop_file

# The loop's records: the owner's files, the review policy and the decision logs. They land
# with a task only with WITH_RECORDS=yes (land.sh).
RECORDS=("${OWNER_FILES[@]}" .review/REVIEW_POLICY.md ':(glob).review/decisions/*.jsonl')

is_record() {
  case "$1" in .review/decisions/*.jsonl | .review/REVIEW_POLICY.md) return 0 ;; esac
  is_owner_file "$1"
}

is_harness() {
  case "$1" in .review/e2e.sh | .review/e2e-*) return 0 ;; *) return 1 ;; esac
}

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

# Fingerprint of everything the reviewer saw: the content of the task's work — the tree
# outside `.review/`, the loop's own files and the owner's, and the end-to-end harness.
# review.sh records it; land.sh and publish.sh recompute it and refuse when it differs — a
# review of a tree that has since changed is not a review of what is about to be committed
# or merged. It is the content alone, never a commit or a branch: committing reviewed work,
# or the tracker, the plan or the records, leaves it as it was, and so does the task branch
# land.sh creates from HEAD; changing a line of the work changes it.
#
# The tree goes through a throwaway copy of the index, so every change reads the
# same, tracked or new, staged or not: a landing whose commit failed leaves its new
# files staged, and that must not read as a tree that changed.
#
# With --whole, the loop's and the owner's files count too: the whole tree outside
# `.review/`. e2e-gate.sh checks with it that the end-to-end tests left the tree as
# they found it, qa/test-cases.md included, whose marks name the tests a run must pass.
tree_fingerprint() {
  local scratch harness outside=("${NOT_TASK_WORK[@]}")
  [ "${1:-}" != --whole ] || outside=(':(exclude).review')
  scratch="$(mktemp -d)" || return 1
  # -p: git trusts an entry whose file is older than the index, so a copy that looks
  # newer than the real one would hide an edit made in the second of the last `git add`.
  cp -p "$(git rev-parse --git-path index)" "$scratch/index" 2>/dev/null
  {
    # `.review/` is pipeline bookkeeping and is excluded, the harness apart (below): the
    # task file is tracked and is filled in (verified_by) after the review by design, so
    # including it here would invalidate every run before it could land.
    GIT_INDEX_FILE="$scratch/index" git add -A -- . "${outside[@]}" 2>/dev/null
    GIT_INDEX_FILE="$scratch/index" git ls-files -s -- . "${outside[@]}"
    if [ "${1:-}" != --whole ]; then
      # One pathspec at a time: given several, git stages nothing when one matches no file.
      for harness in "${HARNESS[@]}"; do
        GIT_INDEX_FILE="$scratch/index" git add -A -- "$harness" 2>/dev/null
      done
      GIT_INDEX_FILE="$scratch/index" git ls-files -s -- "${HARNESS[@]}"
    fi
  } | sha256_stdin
  rm -rf "$scratch"
}

# The paths under the pathspecs that differ from HEAD, tracked or new, one per line, named
# as they are (core.quotePath=false). Only read: the index is never written.
uncommitted() {
  { git -c core.quotePath=false diff --name-only HEAD -- "$@"
    git -c core.quotePath=false ls-files --others --exclude-standard -- "$@"; } | sort -u
}

# The task's work that is not committed: at the pull request levels review.sh reviews, and
# publish.sh merges, only what is committed and pushed.
uncommitted_task_work() {
  { uncommitted . "${NOT_TASK_WORK[@]}"; uncommitted "${HARNESS[@]}"; } | sort -u
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

# gh api on a path of the repository remote_repository names: the owner and the repository go
# into the path, and a host that is not github.com to --hostname, since gh api has no --repo.
gh_repo_api() {
  local repository="$1" path="$2" host=""
  shift 2
  case "$repository" in */*/*) host="${repository%%/*}"; repository="${repository#*/}" ;; esac
  gh api "repos/$repository/$path" ${host:+--hostname "$host"} "$@"
}

# A list gh api reads page by page, as one JSON array: each page is an array of its own.
gh_repo_api_list() {
  gh_repo_api "$1" "$2" --paginate | jq -sc 'add // []'
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

# The platforms the tree ships, one per line: `android` for an Android app with a
# launcher activity (a phone's or a TV's), `ios` for an iOS application target
# (built for iphoneos alone or among other platforms), `app` for anything else.
# Read from the files under review, never from a setting: a platform a project
# could drop by editing `.review/` would be a platform nothing tests. Vendored
# code is passed over: the sample app of a library is not an app the project
# ships.
platforms() {
  local file android=0 ios=0
  while IFS= read -r -d '' file; do
    case "/$file" in
      /.review/*|*/third_party/*|*/third-party/*|*/vendor/*|*/Pods/*|*/Carthage/*) ;;
      */node_modules/*) ;;
      */AndroidManifest.xml)
        grep -qE 'android\.intent\.category\.(LEANBACK_)?LAUNCHER' "$file" 2>/dev/null \
          && android=1 ;;
      *.pbxproj)
        grep -qE 'SDKROOT = iphoneos|SUPPORTED_PLATFORMS = "[^"]*iphoneos' "$file" 2>/dev/null \
          && grep -q 'com.apple.product-type.application' "$file" 2>/dev/null && ios=1 ;;
    esac
  done < <(git ls-files -z -co --exclude-standard)
  [ "$android" -eq 0 ] || echo android
  [ "$ios" -eq 0 ] || echo ios
  [ "$android$ios" != 00 ] || echo app
}

# The cases of qa/test-cases.md and the end-to-end tests their marks name, one
# `TC-nnn` TAB `<test>` per line, and `TC-nnn` TAB nothing for a case with no
# mark. A case is a list item that starts with its id (`- **TC-001`, `1. **TC-001`,
# `* TC-001`) and runs to the next case or heading, its lines joined as Markdown
# joins them. The mark is `e2e:` and the ids after it, all in backticks or all
# bare (a bare id has a dot: `Class.method`), separated by commas, semicolons or
# "and". A trailing `()` is dropped, and so is the space a line wrapped inside
# an id leaves next to a dot.
case_marks() {
  [ -f qa/test-cases.md ] || return 0
  awk '
    function flush(   text, rest, at, stop, id, quoted, marked) {
      if (current == "") return
      text = block
      while ((at = index(text, "e2e:")) > 0) {
        rest = substr(text, at + 4)
        quoted = ""
        for (;;) {
          sub(/^[ \t]+/, "", rest)
          if (substr(rest, 1, 1) == "`" && quoted != "no") {
            stop = index(substr(rest, 2), "`")
            if (stop == 0) break
            id = substr(rest, 2, stop - 1)
            rest = substr(rest, stop + 2)
            quoted = "yes"
          } else if (quoted != "yes" &&
                     match(rest, /^[A-Za-z_][A-Za-z0-9_$]*(\.[A-Za-z0-9_$]+)+(\(\))?/)) {
            id = substr(rest, 1, RLENGTH)
            rest = substr(rest, RLENGTH + 1)
            quoted = "no"
          } else break
          gsub(/[ \t]+/, " ", id); gsub(/ ?\. ?/, ".", id)
          sub(/^ /, "", id); sub(/ $/, "", id); sub(/\(\)$/, "", id)
          if (id != "") { print current "\t" id; marked = 1 }
          if (!sub(/^[ \t]*(,[ \t]*(and[ \t]+)?|;[ \t]*|and[ \t]+)/, "", rest)) break
        }
        text = rest
      }
      if (!marked) print current "\t"
      current = ""
    }
    /^#/ { flush(); next }
    /^[ \t]*([-*+]|[0-9]+[.)])[ \t]+(\*\*)?TC-[0-9]+/ {
      flush()
      match($0, /TC-[0-9]+/)
      current = substr($0, RSTART, RLENGTH)
      block = ""
    }
    current != "" { block = block " " $0 }
    END { flush() }' qa/test-cases.md
}

# How a row of a JUnit report answers to a test a case names, as jq: the same
# id, or its end after a dot (the package left out) — also with the parameters
# of a parameterized row (shows42(int)[1], shows42[0]) left out.
JQ_HIT='def base: sub("(\\([^()]*\\))?(\\[[^\\[\\]]*\\])*$"; "");
def hit($id): . == $id or endswith("." + $id) or (base | . == $id or endswith("." + $id));
'

# The end-to-end tests named in qa/test-cases.md, one per line; with a case id,
# only that case's.
case_tests() {
  case_marks \
    | awk -F'\t' -v wanted="${1:-}" '$2 != "" && (wanted == "" || $1 == wanted) { print $2 }'
}

# The lines of case_marks on stdin as a JSON array of {case, test}, each mark once and
# in order. A run of the end-to-end tests records the marks it was checked against
# this way; land.sh reads the file now the same way and compares.
marks_json() {
  awk -F'\t' '$2 != ""' | jq -R 'split("\t") | {case: .[0], test: .[1]}' | jq -sc 'unique'
}

# Where these standards are. A plain copy of them inside a project, rather than
# a submodule, is searched like any other folder, and its examples are no skips.
STANDARDS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"

# The end-to-end tests skipped for a task, one `T-nnn: TC-nnn` TAB file per line:
# the reason of the skip names the task the defect belongs to and the case it
# breaks, quoted or not, with more words after it or none, and a task of several
# ids as T-016+T-004 — @Ignore("T-017: TC-009"), XCTSkip("T-017: TC-009"),
# skip(reason='T-017: TC-009 Android shows filesDir'). Markdown, `.review/` and
# the standards are left out: a plan, a report or an example that names a skip
# is not one. Exits 1 when there is none, and above 1 when the search failed.
skip_tags() {
  local root outside=()
  root="$(pwd -P)"
  case "$STANDARDS_DIR" in "$root"/*) outside=(":(exclude)${STANDARDS_DIR#"$root"/}") ;; esac
  git grep -z -I -o --untracked -E 'T-[0-9]+(\+T-[0-9]+)*:[[:space:]]*TC-[0-9]+' \
      -- . ':(exclude)*.md' ':(exclude).review' ${outside[@]+"${outside[@]}"} \
    | tr '\0' '\t' \
    | awk -F'\t' '{ tag = $2; sub(/:[ \t]*/, ": ", tag); print tag "\t" $1 }' | sort -u
}

# Whether a test is skipped for a case with a tag that sits on it: a tag of the
# case in a file that also names the test. A tag anywhere else — a note, a
# comment on another test — skips nothing.
skip_tag_on() {
  local tags="$1" case_id="$2" test_id="$3" file
  while IFS= read -r file; do
    [ -n "$file" ] && grep -qF -- "${test_id##*.}" "$file" 2>/dev/null && return 0
  done < <(printf '%s\n' "$tags" \
             | awk -F'\t' -v wanted="$case_id" '$1 ~ (": " wanted "$") { print $2 }')
  return 1
}

# The files of the end-to-end harness — `.review/e2e.sh` and any
# `.review/e2e-*` it calls — one `<blob> <path>` per line, each as git stores
# it: a symbolic link as its target's name. e2e-gate.sh records them before the
# run; land.sh compares them with the harness at landing.
harness_blobs() {
  local file
  for file in .review/e2e.sh .review/e2e-*; do
    if [ -L "$file" ]; then
      printf '%s %s\n' "$(printf '%s' "$(readlink "$file")" | git hash-object --stdin)" "$file"
    elif [ -f "$file" ]; then
      printf '%s %s\n' "$(git hash-object -- "$file")" "$file"
    fi
  done | sort
}

# The paths on stdin that no glob of the task's scope matches. In bash pattern matching `*`
# also matches `/`, so `src/*` covers nested paths — write scopes accordingly.
outside_scope() {
  local task_file="$1" patterns=() pattern file matched
  # Built with a read loop rather than mapfile: macOS still ships bash 3.2.
  while IFS= read -r pattern; do
    [ -z "$pattern" ] || patterns+=("$pattern")
  done < <(jq -r '.scope[]?' "$task_file")
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    matched=0
    for pattern in ${patterns[@]+"${patterns[@]}"}; do
      # shellcheck disable=SC2053
      if [[ "$file" == $pattern ]]; then matched=1; break; fi
    done
    [ "$matched" -eq 1 ] || printf '%s\n' "$file"
  done
}

# The review runs of a task, oldest first by the time each records, one folder per line. A
# folder of a landing (land-*) or of /qa (qa-*) is no review run, whatever it holds.
review_runs_of() {
  local meta
  for meta in .review/runs/*/meta.json; do
    [ -f "$meta" ] || continue
    case "$meta" in .review/runs/land-*|.review/runs/qa-*) continue ;; esac
    jq -c --arg id "$1" --arg run "${meta%/meta.json}" \
      'select(.task == $id) | {time: (.time // 0), run: $run}' "$meta" 2>/dev/null
  done | jq -sr 'sort_by(.time) | .[].run'
}

# The review runs of a task made on a pull request, oldest first: those whose meta.json names
# it. A run of --dry-run, or of another level, names none, and never stands for a review on
# the pull request.
review_runs_on() {
  local run
  review_runs_of "$1" | while IFS= read -r run; do
    if jq -e --arg url "$2" '.pr_url == $url' "$run/meta.json" >/dev/null 2>&1; then
      printf '%s\n' "$run"
    fi
  done
}

# The tasks other than <task-id> whose commits are between <base-ref> and HEAD, one line,
# each followed by a space. A commit with no Task-Id trailer is none: commits_no_landing_made
# judges those.
other_tasks_on() {
  local commit commit_task
  git rev-list --no-merges "$1..HEAD" | while IFS= read -r commit; do
    commit_task="$(task_id_of "$commit")"
    [ -z "$commit_task" ] || [ "$commit_task" = "$2" ] || printf '%s\n' "$commit_task"
  done | sort -u | tr '\n' ' '
}

# The open pull request of <branch> into <base> in <repository>, from this repository and not
# a fork, as {url, number, state, headRefOid}; {} when there is none. With "all" as the fourth
# argument, the newest of any state.
pull_request_of() {
  local found
  found="$(gh pr list --repo "$1" --head "$2" --base "$3" --state "${4:-open}" \
    --json url,number,state,headRefOid,isCrossRepository)" || return 1
  printf '%s' "$found" | jq -c '[.[] | select(.isCrossRepository | not)][0] // {}
    | del(.isCrossRepository)'
}

# What people wrote on pull request <number> of <repository> that the loop has not settled, as
# a JSON array, oldest first: each comment, review and comment on a line that is not the loop's
# own (its marker) nor a bot's, with its id, author, where it is and its whole text. A person
# outranks the loop: what they wrote is settled by a reply of the loop that names it with the
# answer `fixed`, or with `user` — the user's own decision, from the chat or from what they
# wrote. A reply of the loop that disagrees, or defers, leaves it to the person.
people_comments_open() {
  local repository="$1" number="$2" all
  all="$( { gh_repo_api_list "$repository" "issues/$number/comments" || echo FAILED
            gh_repo_api_list "$repository" "pulls/$number/reviews" || echo FAILED
            gh_repo_api_list "$repository" "pulls/$number/comments" || echo FAILED; } )"
  case "$all" in *FAILED*) return 1 ;; esac
  printf '%s\n' "$all" | jq -sc '
    add as $all
    | [$all[] | (.body // "") | capture("<!-- loop:reply (?<id>[^ ]+) (?<answer>[a-z-]+) -->")?]
      as $replies
    | [$all[] | select((.body // "") != "" and ((.body | contains("<!-- loop")) | not)
                       and (.state // "") != "PENDING" and (.user.type // "") != "Bot")
       | (.id | tostring) as $id | (.node_id // "") as $node
       | [$replies[] | select(.id == $id or ($node != "" and .id == $node)) | .answer] as $answers
       | select(any($answers[]; . == "fixed" or . == "user") | not)
       | {id: $id, author: (.user.login // ""), at: (.created_at // .submitted_at // ""),
          where: (if .path != null then "\(.path):\(.line // .original_line // "?")"
                  elif .pull_request_review_id == null and has("state") then "review \(.state)"
                  else "the pull request" end),
          answered: ($answers | last // null), text: .body}]
    | sort_by(.at)'
}

# The qa.json records of a task as one JSON array, oldest first by the time each records,
# each with its folder as `run`. A record that cannot be read, or that is not {task, failures:
# [{case: TC-nnn}]}, fails the whole call: it must never read as "no failures".
qa_records_of() {
  local record
  for record in .review/runs/*/qa.json; do
    [ -f "$record" ] || continue
    jq -c --arg run "${record%/qa.json}" '. + {run: $run}' "$record" || exit 1
  done | jq -sc --arg id "$1" '
    map(select(.task == $id)) | sort_by(.time // 0)
    | if all(.[]; (.failures | type) == "array"
                  and all(.failures[]; (.case? // "") | test("^TC-[0-9]+$")))
      then . else error("malformed") end'
}

# ---------------------------------------------------------------------------
# The conditions of a review run. land.sh checks them before a commit (TASK_LOOP.md, "The
# contract"); publish.sh before a merge at the pull request levels, as items of the merge
# contract; pr-post.sh shows them in the statuses it posts. Each reports through the caller's
# `refuse <condition> <reason>`, which does not return, and names the condition by its number
# in land.sh.
# ---------------------------------------------------------------------------

# 1. The run directory is a completed review run. Missing files must never read as "nothing
#    was found" — that would let any empty directory authorise a commit.
run_is_complete() {
  local run="$1" artifact
  for artifact in meta.json verdicts.json approved.json escalated.json e2e.json; do
    [ -f "$run/$artifact" ] || \
      refuse 1 "$run has no $artifact — this is not a completed review run"
  done
}

# 2. The run reviewed THIS tree, for THIS task. Any edit since the review — including the fix
#    that was supposed to be the last one — invalidates it. The run must belong to this task:
#    the maintainer triaged against one task's scope, and landing checks another's.
#    `.review/` (the harness apart) is outside the fingerprint, so nothing else would catch a
#    swapped task file. Both paths are absolute: review.sh resolves the path before recording
#    it, and the callers resolve their own argument the same way.
run_reviewed_this_tree() {
  local run="$1" task_file="$2" fingerprint="$3" recorded
  recorded="$(jq -r '.task_file // ""' "$run/meta.json")"
  [ -n "$recorded" ] || \
    refuse 2 "this run was made without a task file — its triage never saw a scope"
  [ "$recorded" = "$task_file" ] || refuse 2 "this run reviewed $recorded, not $task_file"
  recorded="$(jq -r '.tree_fingerprint // ""' "$run/meta.json")"
  [ -n "$recorded" ] || refuse 2 "$run/meta.json has no tree fingerprint"
  [ "$recorded" = "$fingerprint" ] || \
    refuse 2 "the tree changed after this review ran — review again before landing"
}

# 3, end-to-end half. The run's end-to-end tests passed on this tree, on every platform the
#    tree ships, through the harness as it is now. Only files are read: the devices ran in
#    review.sh, and condition 2 binds that run to this tree, the harness included: a change to
#    the harness is in the reviewed diff and lands with the task.
run_e2e_passed() {
  local run="$1" fingerprint="$2" platforms_now harness_now
  platforms_now="$(platforms | jq -R . | jq -sc .)"
  jq -e --arg fingerprint "$fingerprint" --argjson need "$platforms_now" \
    '.status == "pass" and .fingerprint == $fingerprint and (($need - .platforms) | length) == 0' \
    "$run/e2e.json" >/dev/null 2>&1 || \
    refuse 3 "the end-to-end tests of this run did not pass on every platform the tree ships: "\
"$(printf '%s' "$platforms_now" | jq -r 'join(" ")')"

  # The harness is `.review/e2e.sh` and any `.review/e2e-*` it calls: each must be now as it
  # ran (recorded before the run), and `.review/e2e.sh` must be there.
  harness_now="$(harness_blobs)"
  case "$harness_now" in *" .review/e2e.sh"*) ;; *) harness_now="" ;; esac
  [ -n "$harness_now" ] && [ "$(jq -r '.harness // ""' "$run/e2e.json")" = "$harness_now" ] || \
    refuse 3 ".review/e2e.sh, or a .review/e2e-* beside it, is not as it ran — review again"
  marks_checked_by_run "$run"
}

# Every test a case of qa/test-cases.md names now, under that case, was one the run was
# checked against. The cases are one of the loop's own files, outside condition 2: a mark
# written since the run names a test no run has seen pass. land.sh checks it again after the
# gates, which run between here and the commit.
marks_checked_by_run() {
  local run="$1" now unchecked
  now="$(case_marks | marks_json)" || refuse 3 "could not read the marks of qa/test-cases.md"
  unchecked="$(jq -r --argjson now "$now" \
    '$now - (.marks // []) | map("\(.case) \(.test)") | join(", ")' "$run/e2e.json")" || \
    refuse 3 "$run/e2e.json is unreadable"
  [ -z "$unchecked" ] || \
    refuse 3 "qa/test-cases.md names end-to-end tests this run was not checked against: "\
"$unchecked — review again before landing"
}

# 4. No accepted finding at or above the threshold of the run that produced the verdicts, so
#    no later check applies a different bar than the review did.
run_has_no_findings() {
  local run="$1" threshold count
  threshold="$(jq -r '.threshold // "major"' "$run/meta.json")"
  count="$(require_array_length "$run/approved.json")" || \
    refuse 4 "approved.json is unreadable — refusing to assume it is empty"
  [ "$count" -eq 0 ] || refuse 4 "$count accepted finding(s) at or above $threshold are unresolved"
}

# 5. No pending escalation. An escalation is answered, not waited out. The answer is recorded
#    in escalations-answered.json — one entry per escalated finding — and only then does
#    landing proceed. Without this an escalated finding (every replication finding, for one)
#    could never land at all: re-running the review reproduces it.
run_escalations_answered() {
  local run="$1" count answers="$1/escalations-answered.json" unanswered
  count="$(require_array_length "$run/escalated.json")" || \
    refuse 5 "escalated.json is unreadable — refusing to assume it is empty"
  [ "$count" -gt 0 ] || return 0
  [ -f "$answers" ] || \
    refuse 5 "$count escalation(s) are waiting for an answer — record the answers in $answers"
  # The same discipline conditions 4 and 5 apply above, and for the same reason: a jq that
  # dies on a malformed answers file prints nothing, and nothing is indistinguishable from "no
  # unanswered escalations". That is the exact fail-open this whole section exists to
  # prevent, so the file is proved to be a JSON array first, and the query's own exit status
  # is checked after.
  require_array_length "$answers" >/dev/null || \
    refuse 5 "$answers is unreadable — refusing to assume the escalations were answered"
  unanswered="$(jq -r --slurpfile answers "$answers" '
    [ .[] | select(.finding_id as $id
        | ([$answers[0][] | select((.resolution // "") != "") | .finding_id] | index($id)) == null)
      | .finding_id ] | join(", ")' "$run/escalated.json")" || \
    refuse 5 "could not read the escalation answers in $answers — "\
"refusing to assume they are answered"
  [ -z "$unanswered" ] || refuse 5 "escalation(s) with no recorded answer: $unanswered"
}

# 7. Every exit criterion carries an explicit verification claim. Machine-checkable criteria
#    belong in gates; the rest must at least be stated, so the claim lands in the commit and
#    can be audited later. A task may have none: criteria are gathered before a task starts,
#    never written at its start (PLANNING_GUIDE.md, "Task Rules").
criteria_verified() {
  local unverified
  unverified="$(jq -r '[.exit_criteria[] | select((.verified_by // "") == "")] | length' "$1")"
  [ "$unverified" -eq 0 ] || \
    refuse 7 "$unverified exit criterion/criteria have no verified_by claim"
}

# 7, /qa. /qa checked the task, and each failure it recorded — in a qa.json, or in the
#    qa_failures an e2e.json of this task took from one, which outlasts a qa.json rewritten or
#    removed — has a test its case is marked with that failed in a run of this task made after
#    /qa recorded it: passing in this run, or skipped in it under a tag of the case for the
#    task it belongs to. Or the user answered it. No test stays skipped for the task. Every
#    record is read: an unreadable one refuses, never reads as "no failures".
qa_failures_proven() {
  local run="$1" task_id="$2" records record tags task still runs failures now answered unproven
  local case_id tests
  records="$(qa_records_of "$task_id")" || \
    refuse 7 "a qa.json is unreadable or not {task, failures: [{case: TC-nnn}]} — "\
"refusing to read it as no failures"
  [ "$(printf '%s' "$records" | jq 'length')" -gt 0 ] || \
    refuse 7 "no /qa record (qa.json) for $task_id — /qa has not checked this task"

  tags="$(skip_tags)"
  [ $? -le 1 ] || refuse 7 "could not search the tree for skipped end-to-end tests"
  for task in $(printf '%s' "$task_id" | tr '+' ' '); do
    still="$(printf '%s\n' "$tags" | awk -F'\t' -v task="$task" '
      { split($1, tag, ": "); n = split(tag[1], ids, "+")
        for (i = 1; i <= n; i++)
          if (ids[i] == task) { cases = cases " " tag[2]; files = files " " $2 } }
      END { if (cases != "")
              print substr(cases, 2) " is still skipped for " task " — make it pass:" files }')"
    [ -z "$still" ] || refuse 7 "the end-to-end test of $still"
  done

  runs="$(for record in .review/runs/*/e2e.json; do
      [ -f "$record" ] || continue
      jq -c . "$record" || exit 1
    done | jq -sc --arg id "$task_id" '[.[] | select(.task == $id)
      | {qa: (.qa_failures // []), failed: [.results[]?.failed[]?]}]')" || \
    refuse 7 "an e2e.json is unreadable — refusing to read it as no failures"
  failures="$(jq -nc --argjson records "$records" --argjson runs "$runs" \
    '[$records[].failures[].case] + [$runs[].qa[]] | unique')" || \
    refuse 7 "could not gather the /qa failures of $task_id"
  # A run that never got as far as its end-to-end tests saw nothing pass.
  now='{"passed": [], "skipped": []}'
  if [ -f "$run/e2e.json" ]; then
    now="$(jq -c '{passed: [.results[]?.passed[]?], skipped: [.results[]?.skipped[]?]}' \
      "$run/e2e.json")" || refuse 7 "$run/e2e.json is unreadable"
  fi
  # Only the user's answer counts, and only one that lets the task land: `fixed` means review
  # again (maintain, step 7).
  answered="[]"
  if [ -f "$run/escalations-answered.json" ]; then
    require_array_length "$run/escalations-answered.json" >/dev/null && \
    answered="$(jq -c '[.[] | select(.by == "human"
        and (.resolution == "accepted-as-is" or .resolution == "deferred"))
      | .finding_id]' "$run/escalations-answered.json")" || \
      refuse 7 "$run/escalations-answered.json is unreadable — refusing to assume an answer"
  fi

  unproven=""
  for case_id in $(printf '%s' "$failures" | jq -r '.[]'); do
    tests="$(case_tests "$case_id" | while IFS= read -r test_id; do
        tagged=false
        skip_tag_on "$tags" "$case_id" "$test_id" && tagged=true
        jq -nc --arg test "$test_id" --argjson tagged "$tagged" '{test: $test, tagged: $tagged}'
      done | jq -sc .)"
    jq -en --argjson tests "$tests" --argjson runs "$runs" --argjson now "$now" \
          --argjson answered "$answered" --arg case "$case_id" "$JQ_HIT"'
      def among($rows): . as $id | any($rows[]; hit($id));
      ($answered | index($case)) != null
        or any($tests[]; . as $mark
               | any($runs[]; . as $run
                     | ($run.qa | index($case)) != null and ($mark.test | among($run.failed)))
                 and (($mark.test | among($now.passed))
                      or ($mark.tagged and ($mark.test | among($now.skipped)))))' \
      >/dev/null || unproven="$unproven $case_id"
  done
  [ -z "$unproven" ] || \
    refuse 7 "a /qa failure without an end-to-end test seen red, then green:$unproven — "\
"mark the case with its test (e2e: \`<test>\`), see it fail in a run of $task_id made after /qa "\
"recorded it, then pass; where no end-to-end test can see it, the user answers it in "\
"$run/escalations-answered.json (by: human, accepted-as-is or deferred)"
}

# 7, /qa at the pull request levels. The newest qa.json of the task, by the time inside it,
#    checked the work as it is now, and one of them checked the whole pull request: its
#    change since the merge base. A /qa after a fix checks only what the fix can reach.
qa_checked_this_work() {
  local task_id="$1" fingerprint="$2" merge_base="$3" records
  records="$(qa_records_of "$task_id")" || \
    refuse 7 "a qa.json is unreadable or not {task, failures: [{case: TC-nnn}]} — "\
"refusing to read it as no failures"
  printf '%s' "$records" | jq -e --arg work "$fingerprint" 'last.work == $work' >/dev/null || \
    refuse 7 "/qa has not checked this work of $task_id: its newest qa.json is of other work, "\
"or there is none"
  printf '%s' "$records" | jq -e --arg since "$merge_base" 'any(.[]; .since == $since)' \
    >/dev/null || \
    refuse 7 "no /qa of $task_id checked the whole pull request: no qa.json has since = "\
"$merge_base, the merge base"
  # How far /qa went, and why, and what came of each item, are part of the record: a /qa
  # that never chose between the cases the change can reach and a full regression has not
  # done its first step.
  printf '%s' "$records" | jq -e --arg since "$merge_base" '
    def told: (.extent == "reachable" or .extent == "full") and ((.reason // "") != "")
      and all(["pass", "fail", "unproven", "not_checked"][] as $key
              | .counts[$key]; type == "number");
    (last | told) and any(.[] | select(.since == $since); told)' >/dev/null || \
    refuse 7 "$(printf '%s' "$records" | jq -r --arg since "$merge_base" '
      [last, (map(select(.since == $since)) | last)] | map(.run | split("/") | last)
      | unique | join(" or ")') does not say how far /qa went and what came of it: "\
"extent (reachable or full), reason, and counts of pass, fail, unproven and not_checked"
}

# 7, /qa at the pull request levels, continued. No /qa since the newest complete one of the
# whole pull request left anything unproven or not checked, or the user accepted what it
# left, in <its folder>/open-answered.json: {"by": "human", "answer": "accepted-as-is",
# "words": "<what they said>"}. A /qa after a fix checks only what the fix can reach, so
# what an earlier one left open goes away only with a later /qa of the whole pull request or
# with the user's acceptance. A merge nobody looks at never stands on a check nobody made.
qa_left_nothing_open() {
  local task_id="$1" merge_base="$2" records open
  records="$(qa_records_of "$task_id")" || \
    refuse 7 "a qa.json is unreadable or not {task, failures: [{case: TC-nnn}]}"
  open="$(printf '%s' "$records" | jq -r --arg since "$merge_base" '
    ([to_entries[] | select(.value.since == $since and (.value.counts | type) == "object")
      | .key] | last // 0) as $from
    | .[$from:][] | select(((.counts.unproven // 0) + (.counts.not_checked // 0)) > 0)
    | "\(.run)\t\(.counts.unproven // 0) unproven and \(.counts.not_checked // 0) not checked"')"
  while IFS=$'\t' read -r run counts; do
    [ -n "$run" ] || continue
    jq -e '.by == "human" and .answer == "accepted-as-is" and ((.words // "") != "")' \
      "$run/open-answered.json" >/dev/null 2>&1 || \
      refuse 7 "/qa left $counts in $(basename "$run") — restore what failed and run /qa of "\
"the whole pull request again, or the user accepts it: $run/open-answered.json, "\
"{\"by\": \"human\", \"answer\": \"accepted-as-is\", \"words\": \"<what they said>\"}"
  done <<<"$open"
}

# 7, /qa at the pull request levels, continued. The reports of the newest /qa and of the newest
# one of the whole pull request are on it: what /qa found stays where people look.
qa_reports_posted() {
  local task_id="$1" merge_base="$2" pr_url="$3" records run
  records="$(qa_records_of "$task_id")" || \
    refuse 7 "a qa.json is unreadable or not {task, failures: [{case: TC-nnn}]}"
  for run in $(printf '%s' "$records" | jq -r --arg since "$merge_base" \
                 '[last, (map(select(.since == $since)) | last)] | map(.run) | unique | .[]'); do
    jq -e --arg url "$pr_url" '.pr_url == $url' "$run/pr-comment.json" >/dev/null 2>&1 || \
      refuse 7 "the report of $(basename "$run") is not on $pr_url — pr-post.sh qa $run posts it"
  done
}

# The trailers of a task's squash commit at the pull request levels, which the description of
# its pull request ends with too. Self-contained: the run folders are local and gitignored,
# so the commit carries the audit facts themselves rather than a path to them.
squash_trailers() {
  local task_file="$1" pr_url="${2:-}" task_id runs newest run qa
  task_id="$(jq -r '.id' "$task_file")"
  if [ -n "$pr_url" ]; then
    runs="$(review_runs_on "$task_id" "$pr_url")"
  else
    runs="$(review_runs_of "$task_id")"
  fi
  newest="$(printf '%s\n' "$runs" | tail -1)"
  printf 'Task-Id: %s\n' "$task_id"
  if [ -n "$newest" ]; then
    [ ! -f "$newest/gates.json" ] || printf 'Gates: %s\n' \
      "$(jq -r '[to_entries[] | "\(.key)=\(.value.status)"] | join(",")' "$newest/gates.json")"
    printf 'Findings: %s reviewed, %s rejected, %s outstanding at %s+\n' \
      "$(printf '%s\n' "$runs" | while IFS= read -r run; do
           cat "$run/verdicts.json" 2>/dev/null; done | jq -s '[.[].verdicts[]?] | length')" \
      "$(printf '%s\n' "$runs" | while IFS= read -r run; do
           cat "$run/verdicts.json" 2>/dev/null; done \
         | jq -s '[.[].verdicts[]? | select(.verdict == "reject")] | length')" \
      "$(jq 'length' "$newest/approved.json" 2>/dev/null || echo "?")" \
      "$(jq -r '.threshold // "major"' "$newest/meta.json")"
  fi
  printf 'Exit-Criteria: %s verified\n' \
    "$(jq '[.exit_criteria[]? | select((.verified_by // "") != "")] | length' "$task_file")"
  if [ -n "$newest" ]; then
    printf 'Review-Runs: %s, last %s\n' "$(printf '%s\n' "$runs" | grep -c .)" \
      "$(basename "$newest")"
  else
    printf 'Review-Runs: 0\n'
  fi
  qa="$(qa_records_of "$task_id" 2>/dev/null | jq -r 'last // empty
    | "QA: \(.run | split("/") | last) (\(.extent // "extent not recorded"))"' 2>/dev/null)"
  [ -z "$qa" ] || printf '%s\n' "$qa"
}
