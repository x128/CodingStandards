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

# ---------------------------------------------------------------------------
# A host that gives no answer. git exits 128 both when the remote refuses and when its
# host cannot be reached, and gh exits 1 for both; their words decide nothing. So after
# a call of either failed, one curl to the host tells the two apart by its exit code.
# ---------------------------------------------------------------------------

# The URL to ask for a remote, as its URL is written (`git remote get-url` gives it after
# insteadOf): for http(s)://[user@]host[:port]/... the scheme, the host and the port; for
# an ssh URL or [user@]host:path, https://<host>/; for a path, nothing.
remote_host_url() {
  local url host
  url="$(git config --get "remote.$1.url" 2>/dev/null)" || return 0
  case "$url" in
    http://* | https://*)
      host="${url#*://}"; host="${host%%/*}"; host="${host##*@}"
      printf '%s://%s/' "${url%%://*}" "$host" ;;
    ssh://* | git+ssh://* | ssh+git://*)
      host="${url#*://}"; host="${host%%/*}"; host="${host##*@}"; host="${host%%:*}"
      printf 'https://%s/' "$host" ;;
    *://* | /* | ./* | ../*) ;;
    *:*)
      host="${url%%:*}"
      case "$host" in
        */*) ;;
        *) printf 'https://%s/' "${host##*@}" ;;
      esac ;;
  esac
}

# The URL to ask for the GitHub of a repository as remote_repository names it: the API of
# github.com, or the host in front of the name.
github_api_url() {
  case "$1" in
    */*/*) printf 'https://%s/' "${1%%/*}" ;;
    *) printf 'https://api.github.com/' ;;
  esac
}

# Whether a host answers: 0 for an answer of any status, 75 when it gives none (no
# proxy, no name, no connection, a timeout, no TLS, an empty reply, a connection that
# broke), 1 when that cannot be told: an empty URL, no curl, any other failure.
host_answers() {
  local url="$1" status
  [ -n "$url" ] || return 1
  command -v curl >/dev/null 2>&1 || return 1
  curl -s -o /dev/null --connect-timeout 10 --max-time 15 "$url" >/dev/null 2>&1
  status=$?
  case "$status" in
    0) return 0 ;;
    5 | 6 | 7 | 28 | 35 | 52 | 56) return 75 ;;
    *) return 1 ;;
  esac
}

# Whether the host of a remote, or the GitHub of a repository, gives no answer at all.
# Asked only after a call of git or gh failed: a host that answers, or of which nothing
# can be told, leaves the refusal as it is.
connection_lost() {
  host_answers "$(remote_host_url "$1")"
  [ $? -eq 75 ]
}
github_lost() {
  host_answers "$(github_api_url "$1")"
  [ $? -eq 75 ]
}

remote_gives_no_answer() {
  printf 'the remote %s gives no answer' "$1"
}

# What this copy last heard from its remote, kept in .review/runs/.loop/last-heard.json:
# {"base": <branch>, "pulls": {<branch>: <url of its open pull request>}, "time": <seconds>}.
# The folder starts with a dot, so no `*` takes it for a run. heard base <branch>, heard
# pull <branch> <url>; an empty url forgets the branch's pull request. A copy that cannot
# write it has heard nothing, and nothing stops for that.
LAST_HEARD=.review/runs/.loop/last-heard.json
heard() {
  local kept updated
  mkdir -p "${LAST_HEARD%/*}" 2>/dev/null || return 0
  kept="$(jq -c 'if type == "object" then . else {} end' "$LAST_HEARD" 2>/dev/null)"
  [ -n "$kept" ] || kept='{}'
  case "$1" in
    base) updated="$(printf '%s' "$kept" | jq -c --arg base "$2" '.base = $base')" ;;
    pull)
      updated="$(printf '%s' "$kept" | jq -c --arg branch "$2" --arg url "$3" '
        .pulls = (if (.pulls | type) == "object" then .pulls else {} end)
        | if $url == "" then del(.pulls[$branch]) else .pulls[$branch] = $url end')" ;;
    *) return 0 ;;
  esac || return 0
  printf '%s' "$updated" | jq -c '.time = (now | floor)' >"$LAST_HEARD.new" 2>/dev/null &&
    mv "$LAST_HEARD.new" "$LAST_HEARD" 2>/dev/null
  rm -f "$LAST_HEARD.new"
  return 0
}

# The base branch this copy last heard of the remote: from last-heard.json, else the one
# that the HEAD a clone recorded names; nothing when it heard none.
last_heard_base() {
  local base
  base="$(jq -r '.base // empty | strings' "$LAST_HEARD" 2>/dev/null)"
  if [ -z "$base" ]; then
    base="$(git symbolic-ref -q "refs/remotes/$1/HEAD" 2>/dev/null)"
    base="${base#refs/remotes/$1/}"
  fi
  printf '%s' "$base"
}

# The branch pull requests go to, which is also protected at the levels that
# publish. Asked of the remote every time: the HEAD a clone recorded stays as it
# was when the remote's default branch changes, and the real one would then be left
# unprotected. A remote that answers and refuses is no answer, and neither is one of
# which nothing can be told, so nothing is guessed here: the guesses are for a remote
# that answers and has no HEAD. Prints the branch, or why it cannot be known and
# fails. When the host of the remote gives no answer at all, prints the base branch
# this copy last heard and returns 75; having heard none, says what to set and fails.
resolve_base_branch() {
  local config_file="$1" remote="$2" base answer
  base="$(read_conf "$config_file" BASE_BRANCH "")"
  if [ -n "$base" ]; then
    heard base "$base"
    printf '%s' "$base"
    return 0
  fi
  answer="$(git ls-remote --symref "$remote" HEAD 2>/dev/null)" || {
    if connection_lost "$remote"; then
      base="$(last_heard_base "$remote")"
      if [ -n "$base" ]; then
        printf '%s' "$base"
        return 75
      fi
      printf '%s, and this copy never heard which branch is its base — set BASE_BRANCH in %s' \
        "$(remote_gives_no_answer "$remote")" "$config_file"
      return 1
    fi
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
  heard base "$base"
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
# Prints the reason and fails, or prints nothing. Returns 75 when the host of the remote,
# or GitHub, gives no answer at all.
publishing_problem() {
  local config_file="$1" level="$2" remote="$3" base="$4" base_on_remote repository checks_wait
  base_on_remote="$(git ls-remote --heads "$remote" "refs/heads/$base" 2>/dev/null)" || {
    if connection_lost "$remote"; then
      remote_gives_no_answer "$remote"
      return 75
    fi
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
  repository="$(remote_repository "$remote")"
  gh auth status >/dev/null 2>&1 || {
    if github_lost "$repository"; then
      printf 'LANDING=%s needs gh, and GitHub gives no answer' "$level"
      return 75
    fi
    printf 'LANDING=%s needs gh, and gh is not logged in — run gh auth login' "$level"
    return 1
  }
  gh repo view "$repository" --json name >/dev/null 2>&1 || {
    if github_lost "$repository"; then
      printf 'LANDING=%s needs gh, and GitHub gives no answer' "$level"
      return 75
    fi
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

# When a landing of the task last committed with its review, as the tree records it: the
# time, in seconds since 1970, of the newest commit in the history of HEAD that carries the
# trailer Task-Id: <id> and names the review it landed with — Review-Run, which land.sh
# writes below the pull request levels, or Review-Runs, which the squash of a pull request
# carries (squash_trailers); 0 when there is none: task_landed_at <id>. A commit of land.sh
# on the branch of a pull request names no review: the task goes on after it. What ran
# before that time was another task under the same id, so what repeats is read from what
# came after it (landed_since): the runs of the task and its /qa records by review.sh, the
# /qa records by the print after /qa, the landings by land.sh.
task_landed_at() {
  local one='valueonly,separator=%x2C'
  git log --fixed-strings --grep="Task-Id: $1" \
    --format="%ct%x09%(trailers:key=Task-Id,$one)%x09%(trailers:key=Review-Run,$one)"\
"%(trailers:key=Review-Runs,$one)" HEAD 2>/dev/null \
    | awk -F'\t' -v id="$1" '
        $2 == id && $3 != "" && $1 + 0 > newest { newest = $1 + 0 }
        END { printf "%d\n", newest }'
}

# As jq: landed_since($after) holds for a record made after the landing that committed at
# $after — its `time`, in whole seconds, is later, since a commit records no part of a
# second — and for every record when no landing committed (0). A record that does not say
# its time is not known to be later.
JQ_LANDED_SINCE='def landed_since($after):
  $after == 0 or (((.time | numbers) // 0) | floor) > $after;
'

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

# Whether a file of JSON says what a filter asks: json_holds [<options of jq>] <filter>
# <file>. What the filter gives is printed and compared with `true`. The exit code of
# jq -e is not asked: jq 1.6 ends -e with 0 on a file that is there and empty, which would
# read as yes — as an acceptance, a report that is posted, the list of this pull request.
# A file that is missing, empty or no JSON says nothing.
json_holds() {
  [ "$(jq -r "$@" 2>/dev/null)" = "true" ]
}

# Whose turn it is after a stop. A script that stops for the user says so through
# `turn user:<kind>`; <kind> is one of USER_DECIDES: what only the user decides, or only the
# user can do. Every other stop is the loop's, and `turn loop` names its next step. No script
# names the user anywhere else (selftest.sh, "the scripts send the user only what is
# theirs"): a stop that can name none of the kinds goes on. The line goes to stderr, after
# the script's own.
USER_DECIDES="what-should-be beyond-agreed not-converging only-theirs a-person-said"

turn_words() {
  case "$1" in
    loop)                printf 'The loop goes on' ;;
    user:what-should-be) printf 'For the user, what should be' ;;
    user:beyond-agreed)  printf 'For the user, beyond what was agreed' ;;
    user:not-converging) printf 'For the user, the work does not converge' ;;
    user:only-theirs)    printf 'For the user, only they can' ;;
    user:a-person-said)  printf 'For the user, what a person wrote' ;;
    *) return 1 ;;
  esac
}

turn() {
  local words
  words="$(turn_words "$1")" || {
    echo "turn: '$1' is neither loop nor user:<one of: $USER_DECIDES>" >&2
    exit 1
  }
  shift
  printf '   %s: %s\n' "$words" "$*" >&2
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
#
# AWK_MARK reads the ids, for case_marks and for case_words, which takes the mark out of
# the words: take_id() takes the next id off the start of `rest`, the text after `e2e:`,
# into `id`, and says whether there was one; more_ids() takes the separator that announces
# another. `quoted` is empty before the first id of a mark.
AWK_MARK='
    function take_id(   stop) {
      sub(/^[ \t]+/, "", rest)
      if (substr(rest, 1, 1) == "`" && quoted != "no") {
        stop = index(substr(rest, 2), "`")
        if (stop == 0) return 0
        id = substr(rest, 2, stop - 1)
        rest = substr(rest, stop + 2)
        quoted = "yes"
      } else if (quoted != "yes" &&
                 match(rest, /^[A-Za-z_][A-Za-z0-9_$]*(\.[A-Za-z0-9_$]+)+(\(\))?/)) {
        id = substr(rest, 1, RLENGTH)
        rest = substr(rest, RLENGTH + 1)
        quoted = "no"
      } else return 0
      return 1
    }
    function more_ids() {
      return sub(/^[ \t]*(,[ \t]*(and[ \t]+)?|;[ \t]*|and[ \t]+)/, "", rest)
    }
'
case_marks() {
  [ -f qa/test-cases.md ] || return 0
  awk "$AWK_MARK"'
    function flush(   text, at, marked) {
      if (current == "") return
      text = block
      while ((at = index(text, "e2e:")) > 0) {
        rest = substr(text, at + 4)
        quoted = ""
        while (take_id()) {
          gsub(/[ \t]+/, " ", id); gsub(/ ?\. ?/, ".", id)
          sub(/^ /, "", id); sub(/ $/, "", id); sub(/\(\)$/, "", id)
          if (id != "") { print current "\t" id; marked = 1 }
          if (!more_ids()) break
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

# The words of the cases of qa/test-cases.md, one `TC-nnn` TAB `<words>` per line: the
# lines of the case up to the first list item after it — a note, a line of its history —
# without its list marker and without its mark, runs of blanks as one blank. The mark is
# `e2e:` with the ids after it, as case_marks reads them, and the dash before it, or, after
# a blank and a dash, `manual` with its reason: what else stands after an end-to-end mark
# is words of the case, and so is a word that ends in `-manual:`. The words stay as they
# are when a mark is added or grows, when the case is wrapped another way, when a note is
# added under it and when `manual` gets its reason; they change when what the user does
# and sees is written anew.
case_words() {
  [ -f qa/test-cases.md ] || return 0
  awk "$AWK_MARK"'
    function flush(   text, at, words, after) {
      if (current == "") return
      text = block
      gsub(/[ \t]+/, " ", text); sub(/ $/, "", text)
      sub(/^ ?([-*+]|[0-9]+[.)]) /, "", text)
      words = ""
      while ((at = index(text, "e2e:")) > 0) {
        words = words substr(text, 1, at - 1)
        sub(/ ?(—|--|-)? ?$/, "", words)
        rest = substr(text, at + 4)
        quoted = ""
        after = rest
        # A separator with no id after it is no part of the mark.
        while (take_id()) { after = rest; if (!more_ids()) break }
        text = after
      }
      text = words text
      sub(/ (—|--|-) ?manual( ?:.*)?$/, "", text)
      while (sub(/( |-|—)+$/, "", text)) ;
      print current "\t" text
      current = ""
    }
    /^#/ { flush(); next }
    /^[ \t]*([-*+]|[0-9]+[.)])[ \t]+(\*\*)?TC-[0-9]+/ {
      flush()
      match($0, /TC-[0-9]+/)
      current = substr($0, RSTART, RLENGTH)
      block = ""
      open = 1
    }
    current != "" && open && block != "" && /^[ \t]*([-*+]|[0-9]+[.)])[ \t]/ { open = 0 }
    current != "" && open { block = block " " $0 }
    END { flush() }' qa/test-cases.md
}

# A digest of the words of each case, as one JSON object {"TC-nnn": <sha256>}. A run of the
# end-to-end tests records it before it runs; land.sh compares the words of a case /qa
# failed, as they are now, with the words its test was seen failing against. The words go
# into one file for each case and are hashed in one pass: a project has hundreds of cases.
case_digests() {
  local scratch status
  scratch="$(mktemp -d)" || return 1
  case_words | awk -F'\t' -v dir="$scratch" \
    '$1 != "" { file = dir "/" $1; printf "%s", $2 >file; close(file) }'
  ( cd "$scratch" || exit 1
    set -- TC-*
    [ -f "$1" ] || exit 0
    if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$@"; else sha256sum "$@"; fi
  ) | jq -Rnc '[inputs | capture("^(?<digest>[0-9a-f]{64})[ *]+(?<case>TC-[0-9]+)$")
                | {(.case): .digest}] | add // {}'
  status=$?
  rm -rf "$scratch"
  return "$status"
}

# The words of the cases a /qa failed, as they are when it failed them: a digest of each,
# {"TC-nnn": <sha256>}, beside its record as cases.json. pr-post.sh qa writes it right after
# /qa and never again; land.sh compares the words at landing with it, so a case reworded
# after /qa failed it — before its test was ever seen failing, too — proves nothing. A /qa
# that failed no case of the file keeps nothing.
qa_keeps_words() {
  local qa_dir="$1" digests kept
  [ ! -e "$qa_dir/cases.json" ] || return 0
  digests="$(case_digests)" || return 1
  kept="$(jq -c --argjson digests "$digests" \
    '[.failures[].case | select($digests[.] != null) | {(.): $digests[.]}] | add // {}' \
    "$qa_dir/qa.json")" || return 1
  [ "$kept" = "{}" ] || printf '%s\n' "$kept" >"$qa_dir/cases.json"
}

# The cases that say why no end-to-end test can see them, one `TC-nnn` TAB `<why>` per
# line: a case whose text, up to the first list item after it, ends with a blank, a dash,
# `manual:` and words after it. A bare `manual` gives no line, and neither does a word
# that ends in `-manual:`.
case_manual() {
  [ -f qa/test-cases.md ] || return 0
  awk '
    function flush(   text) {
      if (current == "") return
      text = block
      gsub(/[ \t]+/, " ", text); sub(/ $/, "", text)
      sub(/ ?(—|--|-)? ?e2e:.*$/, "", text)
      if (match(text, / (—|--|-) ?manual ?:.*$/)) {
        text = substr(text, RSTART)
        sub(/^ (—|--|-) ?manual ?: ?/, "", text)
        while (sub(/( |-|—)+$/, "", text)) ;
        if (text != "") print current "\t" text
      }
      current = ""
    }
    /^#/ { flush(); next }
    /^[ \t]*([-*+]|[0-9]+[.)])[ \t]+(\*\*)?TC-[0-9]+/ {
      flush()
      match($0, /TC-[0-9]+/)
      current = substr($0, RSTART, RLENGTH)
      block = ""
      open = 1
    }
    current != "" && open && block != "" && /^[ \t]*([-*+]|[0-9]+[.)])[ \t]/ { open = 0 }
    current != "" && open { block = block " " $0 }
    END { flush() }' qa/test-cases.md
}

# The line of qa/test-cases.md on which a case starts, or nothing when it has no such case.
case_line() {
  [ -f qa/test-cases.md ] || return 0
  awk -v wanted="$1" '
    /^[ \t]*([-*+]|[0-9]+[.)])[ \t]+(\*\*)?TC-[0-9]+/ {
      match($0, /TC-[0-9]+/)
      if (substr($0, RSTART, RLENGTH) == wanted) { print NR; exit }
    }' qa/test-cases.md
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

# The tries of a run's end-to-end tests, oldest first, one e2e.json a line: the run's own,
# then each repeat. A run on work whose review is made and whose tests have not passed
# repeats only the tests (review.sh), each time into a folder of its own beside the run's
# files, <run>/e2e-again/<n>, numbered from 1, and never rewrites the run's own e2e.json:
# the landing's condition on a /qa failure reads each try as a record of its own
# (qa_failures_proven).
# run_e2e_record <run> is the newest try, what the tests came to; with none it names the
# run's own e2e.json, which is then not there.
run_e2e_tries() {
  local number
  [ ! -f "$1/e2e.json" ] || printf '%s\n' "$1/e2e.json"
  [ -d "$1/e2e-again" ] || return 0
  for number in $(ls "$1/e2e-again" | grep -E '^[0-9]+$' | sort -n); do
    [ ! -f "$1/e2e-again/$number/e2e.json" ] || printf '%s\n' "$1/e2e-again/$number/e2e.json"
  done
}
run_e2e_record() {
  local newest
  newest="$(run_e2e_tries "$1" | tail -1)"
  printf '%s' "${newest:-$1/e2e.json}"
}

# What a review run came to, in a few words: the review's words, and after them, when the
# run made a review and its end-to-end tests are not green, what they came to. A run that
# made no review says what ended it: a run of the master's scripts ended at red end-to-end
# tests or at a missing harness before its review.
run_result() {
  local run="$1" status
  status="$(jq -r '.status // ""' "$(run_e2e_record "$run")" 2>/dev/null)"
  if [ ! -f "$run/gates.json" ]; then
    echo "did not finish"
  elif jq -e 'any(.[]; .status == "fail" and .blocking != false)' "$run/gates.json" \
       >/dev/null 2>&1; then
    echo "gates red"
  elif [ ! -f "$run/approved.json" ] || [ ! -f "$run/escalated.json" ]; then
    if [ -f "$run/findings.json" ] && [ "$(jq '.findings | length' "$run/findings.json")" -eq 0 ]
    then echo "unusable: no finding located"
    else
      case "$status" in
        red) echo "end-to-end tests red" ;;
        no-harness) echo "no end-to-end harness" ;;
        *) echo "did not finish" ;;
      esac
    fi
  else
    jq -rn --slurpfile approved "$run/approved.json" --slurpfile escalated "$run/escalated.json" '
      ($approved[0] | length) as $a | ($escalated[0] | length) as $e
      | if $a + $e == 0 then "clean"
        else [if $a > 0 then "\($a) accepted" else empty end,
              if $e > 0 then "\($e) escalated" else empty end] | join(", ") end' \
      | tr -d '\n'
    case "$status" in
      pass) ;;
      red) printf '; end-to-end tests red' ;;
      no-test) printf '; no end-to-end test ran' ;;
      environment) printf '; the end-to-end tests could not run' ;;
      no-harness) printf '; no end-to-end harness' ;;
      *) printf '; the end-to-end tests have not run' ;;
    esac
    echo
  fi
}

# The gates of a report that failed and block, as jq: red_gates, on the report, gives them
# as entries {key, value}; gates_same, on those entries, is what two reports share when the
# same gates failed with the same output but for its digits — a time, a count. A review
# run (JQ_RUN) and a landing (red_gates_same) are compared by it.
JQ_GATES='def no_digits: tostring | [explode[] | select(. < 48 or . > 57)] | implode;
def red_gates:
  [objects | to_entries[]
   | select((.value | type) == "object" and .value.status == "fail" and .value.blocking != false)];
def gates_same: ["gates", [.[] | [.key, (.value.output // "" | no_digits)]]];
'

# The digest of what failed in a gate report, or nothing when no blocking gate failed or the
# report cannot be read: red_gates_same <gates.json>. It is the `same` of a review run with
# those gates red (task_runs_json).
red_gates_same() {
  local text
  text="$(jq -r "$JQ_GATES"'red_gates | select(length > 0) | gates_same | tojson' "$1" \
    2>/dev/null)" || return 0
  [ -z "$text" ] || printf '%s\n' "$text" | sha256_stdin
}

# What was red in a gate report, in words: `<gate>, <gate> red`, `the gates did not run` when
# there is no report to read, or `no gate red`: red_gates_words <gates.json>.
red_gates_words() {
  local names
  names="$(jq -rs "$JQ_GATES"'if length == 1 and (.[0] | type) == "object"
                              then .[0] | red_gates | map(.key) | join(", ")
                              else error("no report") end' "$1" 2>/dev/null)" || {
    printf 'the gates did not run'
    return 0
  }
  if [ -n "$names" ]; then printf '%s red' "$names"; else printf 'no gate red'; fi
}

# One run of a task as task_runs_json gives it, read from its meta.json and the files beside
# it; $run, $approved, $escalated, $gates, $e2e, $findings and $quote_lines are the folder
# and the text of each file, empty when it is not there. `same` is here the text that says
# what failed; its digest takes its place.
JQ_RUN='
def parsed: if . == "" then null else (try fromjson catch null) end;
($approved | parsed) as $approved | ($escalated | parsed) as $escalated
| ($gates | parsed) as $gates
| ($e2e | parsed | if type == "object" then . else {} end) as $e2e
| ($findings | parsed) as $findings
| ($quote_lines | parsed | if type == "object" then . else {} end) as $quote_lines
| (($approved | type) == "array") as $reviewed
| ($gates | red_gates) as $red_gates
| (.end
   // (if $reviewed then
         (if (($escalated | arrays | length) // 0) > 0 then "escalations"
          elif ($approved | length) > 0 then "findings"
          elif $e2e.status == "red" then "e2e-red"
          elif $e2e.status == "environment" or $e2e.status == "no-test"
               or $e2e.status == "no-harness" then $e2e.status
          else "clean" end)
       elif ($red_gates | length) > 0 then "gates-red"
       elif $e2e.status == "red" then "e2e-red"
       elif $e2e.status == "no-harness" then "no-harness"
       elif (($findings | objects | .findings | arrays | length) // -1) == 0 then "unusable"
       else "error" end)) as $ending
| (if ($red_gates | length) > 0 then "gates"
   elif $e2e.status == "red" then "e2e"
   elif $e2e.status == "no-harness" or $e2e.status == "no-test" then "harness"
   elif $ending == "unusable" then "unusable"
   else null end) as $failed
| {run: $run, time: (.time // 0), epoch: (.epoch // 0), past_limit: (.past_limit == true),
   user_decided: (.user_decided == true), stop: (.stop // null),
   because: (.because // null), work: .tree_fingerprint,
   reviewed: $reviewed,
   accepted: [$approved | arrays | .[] | objects
              | .finding_id as $id
              | {id: $id}
                + (.finding | objects
                   | {file, line, category,
                      quote: ([(.code_quote // "" | tostring | split("\n")[]
                                | gsub("^\\s+|\\s+$"; "") | select(. != ""))] | first // ""),
                      quote_lines: ($quote_lines[$id | tostring] // null)})],
   end: $ending, failed: $failed,
   same: (if $failed == "gates" then ($red_gates | gates_same)
          elif $failed == "e2e" or $failed == "harness"
            then [$failed, ([$e2e.reasons[]? | no_digits] | sort)]
          elif $failed == "unusable" then [$failed]
          else null end
          | if . == null then null else tojson end)}'

# The runs of a task as one JSON array, oldest first by the time each records: for each
# folder under .review/runs whose meta.json names the task — a folder of a landing (land-*)
# or of /qa (qa-*) is no review run —
#   {run, time, epoch, past_limit, user_decided, stop, because, work, reviewed, accepted,
#    end, failed, same}
# `stop` names the stop a run with --past-limit passed, `user_decided` says that the user
# decided to go on there, and `because` is the loop's reason. `work` is the fingerprint of
# the tree the run looked at.
# `reviewed`: the run made a review — its approved.json is there and is a list, which
# review.sh writes only when the triage ended. `accepted`: what the review accepted, each
# {id, file, line, category, quote, quote_lines}, the quote being the first line of the
# finding's quote that is not blank, trimmed, and quote_lines on how many lines the file
# held it when the review was made (quote-lines.json; null for a run that does not say).
# `end`: how
# the run ended, as review.sh records it (record_end); for a run that does not say — one
# made before review.sh recorded it, or one that was killed — it is read from what the run
# left: escalations or findings when it is reviewed and its review says so, else by the
# status of its e2e.json — e2e-red, environment, no-test or no-harness, clean on a pass;
# gates-red when a blocking gate failed, e2e-red or no-harness by the status of its
# e2e.json when there is no review, unusable when its findings.json holds no finding, and
# error otherwise. `failed`: which check of the run was not green, whether or not it made a
# review — gates, e2e, harness (no harness, or no test that ran), unusable — or null: an
# end-to-end run that the environment kept from running failed nothing of the work.
# `same`: a digest of `failed` and of what failed, null when `failed` is: the name and the
# output of each failing blocking gate, or the reasons of e2e.json, sorted, each with its
# digits taken out, so that two runs that end the same way but for a time or a count have
# one digest. A run that ended in an error has none: two errors at one stage may be two
# errors. The e2e.json read is the newest try of the run's tests (run_e2e_record): a repeat
# on reviewed work is no run of its own. A meta.json that cannot be read fails the whole
# call and says which: it must never read as "no run". task_run_json <run-dir> gives one
# run. task_runs_json <id> [<landed-at>] gives the runs made after a landing of the id
# committed (task_landed_at), every run of the id without it.
task_run_json() {
  local run="$1" entry same e2e
  local approved="$1/approved.json" escalated="$1/escalated.json" gates="$1/gates.json"
  local findings="$1/findings.json" quote_lines="$1/quote-lines.json"
  e2e="$(run_e2e_record "$1")"
  [ -f "$approved" ] || approved=/dev/null
  [ -f "$escalated" ] || escalated=/dev/null
  [ -f "$gates" ] || gates=/dev/null
  [ -f "$e2e" ] || e2e=/dev/null
  [ -f "$findings" ] || findings=/dev/null
  [ -f "$quote_lines" ] || quote_lines=/dev/null
  entry="$(jq -c --arg run "$run" --rawfile approved "$approved" \
    --rawfile escalated "$escalated" --rawfile gates "$gates" --rawfile e2e "$e2e" \
    --rawfile findings "$findings" --rawfile quote_lines "$quote_lines" \
    "$JQ_GATES$JQ_RUN" "$run/meta.json")" \
    && [ -n "$entry" ] || return 1
  # `same` is the last key of the entry, so a run that failed nothing ends with its null.
  case "$entry" in
    *'"same":null}') ;;
    *) same="$(printf '%s' "$entry" | jq -r '.same' | sha256_stdin)" || return 1
       entry="$(printf '%s' "$entry" | jq -c --arg same "$same" '.same = $same')" || return 1 ;;
  esac
  printf '%s\n' "$entry"
}

unreadable_meta() {
  echo "$1 is not readable — the runs of a task are read from these files: repair it or "\
"remove that run folder" >&2
}

# The run folders are read 500 at a time, one jq for each 500: a project keeps hundreds of
# them, and every run of review.sh reads them all.
task_runs_json() {
  local meta from=0 entries
  local -a metas=()
  for meta in .review/runs/*/meta.json; do
    [ -f "$meta" ] || continue
    case "$meta" in .review/runs/land-*|.review/runs/qa-*) continue ;; esac
    [ -s "$meta" ] || { unreadable_meta "$meta"; return 1; }
    metas+=("$meta")
  done
  entries="$(while [ "$from" -lt "${#metas[@]}" ]; do
      jq -r --arg id "$1" --argjson after "${2:-0}" "$JQ_LANDED_SINCE"'
        if type == "object" then select(.task == $id and landed_since($after)) | input_filename
        else error("no object") end' "${metas[@]:from:500}" 2>/dev/null || {
        for meta in "${metas[@]:from:500}"; do
          jq -e 'type == "object"' "$meta" >/dev/null 2>&1 || { unreadable_meta "$meta"; break; }
        done
        exit 1
      }
      from=$((from + 500))
    done | while IFS= read -r meta; do
      task_run_json "${meta%/meta.json}" || exit 1
    done)" || return 1
  printf '%s' "$entries" | jq -sc 'sort_by(.time)'
}

# The works on which /qa failed a case, oldest first, each once, as {work, run}: jq's
# works_failed(<records>; <case>), the records oldest first, each {run, work, failures:
# [case]} (qa_cases_of). A /qa of work that did not change is the same /qa again, and no
# fix lies between the two. A record that does not say its `work` is not known to be of
# other work: beside records that say theirs it counts nothing, and with none of those the
# newest such record counts once. The print after /qa (qa_times) and the stop of review.sh
# (JQ_READING) count with it, so the two never differ.
JQ_WORKS_FAILED='def works_failed($records; $case):
  [$records[] | select(any(.failures[]; . == $case))] as $failed
  | reduce ($failed[] | select((.work // "") != "")) as $record ([];
      if any(.[]; .work == $record.work) then .
      else . + [{work: $record.work, run: $record.run}] end)
  | if length == 0 then [$failed | last | select(. != null) | {work: null, run}] else . end;
'

# What repeats in the runs of a task, the stop in force and whose it is. Input: {runs, qa,
# limit}. runs: task_runs_json. qa: the /qa records of the task, oldest first, each {run,
# time, work, failures: [case]} (qa_cases_of). limit: ASK_AFTER_RUNS.
#
# The stops, the first that holds: `finding` — a finding of the newest review was accepted
# at the same place in three reviews in a row, each of other work than the one before,
# until a run newer than that review passed this stop on the user's decision: the decision
# holds until the next review, so a run past the stop that ended before its review does
# not use it up;
# `case` — a case the newest /qa failed has failed on three works (works_failed), until a
# run newer than that /qa passed this stop on the user's decision: the decision holds
# until the next /qa, and one taken at another stop is none on the case;
# `same-end-after-changes` — three runs in a row ended the same way (`same`) with the same
# gates or end-to-end tests red, each of other work than the one before; `same-end` — three
# runs in a row ended the same way otherwise: on the same work, or with no check of the
# code red; `reviews` — `limit` reviews since the count started;
# `runs` — `limit` runs in a row with no review. `whose`: `user` for a circle of the work —
# the finding, the case, or the same end after changes once the loop's reason did not hold;
# `loop` where the script cannot read that the work converges; `converging` at the limit of
# reviews when no finding came back and the reviews accept fewer.
#
# The same end after changes is the loop's the first time: the script cannot tell fixes
# that do not close a failure from a machine that failed each time, and the loop can. The
# run that passes that stop with the loop's reason starts the row again: `same_end_row`
# then counts the runs after it, and three more that end the same way, each of other work
# than the one before, show that the reason did not hold — that is the user's, and
# `passed` names the run and the reason. The one before the oldest run of that row is the
# run that passed: a run on the work of that run is a retry, and none of the three. With
# no such run the oldest of the row is compared with nothing. Such a run starts the row
# again only while the run before it is of the row: after a different end the same end is
# the first time once more. A run that passed the stop on the user's decision, or
# `same-end`, starts nothing again: those stops stay in force while the runs end the same
# way.
#
# The same place of two findings: the same file and category, and the same quote or lines
# no more than five apart. A quote names a place only where the file held it on one line
# when each review was made: `return null` on three lines of a file is three places. A
# review of the same work as the review after it is passed over: nothing was fixed between.
# The count reads the reviews of the newest epoch; the rows read every run of the task, so
# a run past the limit does not wipe a circle.
JQ_READING='
def on_one_line: (.quote_lines // 1) <= 1;
def same_place($a; $b):
  $a.file == $b.file and $a.category == $b.category
  and (($a.quote != "" and $a.quote == $b.quote and ($a | on_one_line) and ($b | on_one_line))
       or (($a.line | type) == "number" and ($b.line | type) == "number"
           and (($a.line - $b.line) | fabs) <= 5));
.runs as $runs | .qa as $qa | .limit as $limit
| ($runs | map(.epoch // 0) | max // 0) as $epoch
| [$runs[] | select(.reviewed)] as $reviews
| [range(0; $reviews | length) as $i
   | select($i == ($reviews | length) - 1 or $reviews[$i].work != $reviews[$i + 1].work)
   | $reviews[$i]] as $steps
| ($steps | reverse) as $back
| [ ($back[0].accepted // [])[] | . as $finding
    | reduce $back[1:][] as $review ({row: 1, at: $finding, runs: [$back[0].run], open: true};
        if .open | not then .
        else (.at as $at | [$review.accepted[] | select(same_place(.; $at))] | first) as $hit
          | if $hit == null then .open = false
            else .row += 1 | .at = $hit | .runs += [$review.run] end
        end)
    | select(.row >= 2)
    | $finding + {row: .row, runs: (.runs | reverse)} ] as $came_back
| ([$runs | reverse | .[] | .reviewed] | (index(true) // length)) as $no_review_row
| ($runs | reverse) as $newest_first
| (if ($newest_first | length) == 0 or $newest_first[0].same == null then 0
   else ([$newest_first[] | .same == $newest_first[0].same] | (index(false) // length)) end)
    as $whole_row
| ([$newest_first[0:$whole_row][]
    | .past_limit == true and .stop == "same-end-after-changes" and .user_decided != true]
   | index(true) | if . != null and . < $whole_row - 1 then . else null end) as $passed_at
| ($passed_at // $whole_row) as $same_end_row
| (if $passed_at == null then 0 else 1 end) as $with_pass
| ($newest_first[0:$same_end_row + $with_pass]
   | [range(0; length - 1) as $i | .[$i].work != .[$i + 1].work]
   | (index(false) // length) + 1 - $with_pass) as $changed_row
| (($newest_first[0].failed // "") as $failed
   | $changed_row >= 3 and ($failed == "gates" or $failed == "e2e")) as $same_end_after_changes
| (($reviews[-1].time // 0) as $newest
   | any($runs[]; .user_decided == true and .stop == "finding" and (.time // 0) > $newest))
    as $finding_answered
| (($qa[-1].time // 0) as $newest
   | any($runs[]; .user_decided == true and .stop == "case" and (.time // 0) > $newest))
    as $qa_answered
| ([$qa[-1].failures[]?] | unique | map(. as $case
     | works_failed($qa; $case) | {case: $case, times: length, runs: map(.run)})
   | map(select(.times >= 2))) as $qa_back
| ([$reviews[] | select((.epoch // 0) == $epoch and .past_limit != true)] | length) as $counted
| [$reviews[] | .accepted | length] as $series
| (($series | length) >= 2 and $series[-1] > 0 and $series[-1] >= $series[-2]) as $not_fewer
| (if ($finding_answered | not) and any($came_back[]; .row >= 3)
     then {stop: "finding", whose: "user"}
   elif ($qa_answered | not) and any($qa_back[]; .times >= 3) then {stop: "case", whose: "user"}
   elif $same_end_row >= 3 and $same_end_after_changes
     then {stop: "same-end-after-changes",
           whose: (if $passed_at != null then "user" else "loop" end)}
   elif $same_end_row >= 3 then {stop: "same-end", whose: "loop"}
   elif $counted >= $limit
     then {stop: "reviews",
           whose: (if ($came_back | length) > 0 or $not_fewer then "loop" else "converging" end)}
   elif $no_review_row >= $limit then {stop: "runs", whose: "loop"}
   else {stop: null, whose: null} end) as $stop
| {epoch: $epoch, reviews: $counted, runs_in_all: ($runs | length), accepted: $series,
   not_fewer: $not_fewer, came_back: $came_back, no_review_row: $no_review_row,
   ends: [$newest_first[0:$no_review_row] | reverse | .[].end],
   same_end_row: $same_end_row, same_end_changed: $changed_row,
   same_end_runs: [$newest_first[0:$same_end_row] | reverse | .[].run],
   passed: (if $passed_at == null then null
            else $newest_first[$passed_at] | {run, because} end),
   newest: ($newest_first[0] // {} | {run, failed}), qa_back: $qa_back}
  + $stop'

# The reading of a task's runs: task_reading <runs> <qa-records> <limit>, each as JSON. They
# go to jq on its input, never as an argument: a task with many runs is longer than one
# argument may be.
task_reading() {
  printf '{"runs": %s, "qa": %s, "limit": %s}' "$1" "$2" "$3" \
    | jq -c "$JQ_WORKS_FAILED$JQ_READING"
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
# own nor a bot's, with its id, author, where it is and its whole text. A post is the loop's
# own only when it starts with the loop's marker, and a reply of the loop is read only from
# such a post: the marker inside what a person wrote hides nothing and settles nothing. A
# person outranks the loop: what they wrote is settled by a reply of the loop that names it
# with the answer `fixed`, or with `user` — the user's own decision, from the chat or from what
# they wrote. A reply of the loop that disagrees, or defers, leaves it to the user; one that
# says `unsettled` leaves it to the loop, to find out and answer again (publish.sh, M8).
# Each of the three requests fails the call by its own exit code (gh_repo_api_list, under the
# caller's pipefail); the text read is never searched for a failure: a comment may quote the
# log of a build.
people_comments_open() {
  local repository="$1" number="$2" issue_comments reviews line_comments
  issue_comments="$(gh_repo_api_list "$repository" "issues/$number/comments")" || return 1
  reviews="$(gh_repo_api_list "$repository" "pulls/$number/reviews")" || return 1
  line_comments="$(gh_repo_api_list "$repository" "pulls/$number/comments")" || return 1
  printf '%s\n' "$issue_comments" "$reviews" "$line_comments" | jq -sc '
    def own: (.body // "") | startswith("<!-- loop:");
    add as $all
    | [$all[] | select(own) | .body
       | capture("^<!-- loop:reply (?<id>[^ ]+) (?<answer>[a-z-]+) -->")?] as $replies
    | [$all[] | select((.body // "") != "" and (own | not)
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

# The first fault of a /qa record, or nothing when it holds. Beside what a record always
# had — its task and failures: [{case: TC-nnn}] — it may list its items, one {id, verdict,
# reason, check} for each: the verdict as counts names it, a reason for every verdict but
# pass, for after_merge the check that will be made then, and for fail an id that is of a
# case of failures (of_case): no failure is recorded under no case. And, apart
# from the items, behaviour_without_requirement: [{what, where}], what the app does that
# no requirement, exit criterion or case describes — a question, so it may name no case:
# what fails in a case is a failure. A record with neither field reads as it always did.
#
# An item is of a case when its id is the case id, or starts with the case id and a
# character that is no letter, digit or dash: `TC-002 on iOS`, `TC-002: the start`,
# `TC-002 (tablet)`. `TC-0021` and `TC-002-b` are of other cases. The record's fault and
# condition 7 read it the same way: `<id> | of_case(<case id>)`.
JQ_OF_CASE='def of_case($case):
  . == $case or (startswith($case) and (.[($case | length):] | test("^[^A-Za-z0-9-]")));
'
qa_record_fault() {
  local fault unreadable="it is not one JSON object with a task and failures: [{case: TC-nnn}]"
  fault="$(jq -rs --arg unreadable "$unreadable" "$JQ_OF_CASE"'
    def text: type == "string" and . != "";
    def fault:
      . as $record
      | ["pass", "fail", "unproven", "not_checked", "after_merge"] as $verdicts
      | first(
          (select(type != "object" or (.task | text | not) or (.failures | type) != "array"
                  or (all(.failures[]; (.case? // "") | text and test("^TC-[0-9]+$")) | not))
           | $unreadable),
          (select(has("items"))
           | select((.items | type) != "array"
                    or (all(.items[]; type == "object" and (.id | text) and (.verdict | text)
                                      and (.verdict as $verdict | $verdicts | index($verdict)))
                        | not))
           | "items is not a list of {id, verdict}, each verdict one of "
             + ($verdicts | join(", "))),
          (.items[]? | select(.verdict != "pass" and (.reason | text | not))
           | "item \(.id) says \(.verdict) and gives no reason"),
          (.items[]? | select(.verdict == "after_merge" and (.check | text | not))
           | "item \(.id) is put off until after the merge and does not say how it is "
             + "checked then (check)"),
          (.items[]? | select(.verdict == "after_merge" and (.id | test("TC-[0-9]+")))
           | "item \(.id) is put off until after the merge and names a case: a case is what "
             + "is seen in the app, and is checked on the pull request"),
          (select(has("items")) | $verdicts[] as $verdict
           | ([$record.items[] | select(.verdict == $verdict)] | length) as $listed
           | (($record.counts | objects | .[$verdict]) // 0) as $counted
           | select($listed != $counted)
           | "\($listed) item(s) say \($verdict) and counts.\($verdict) is "
             + ($counted | if type == "number" then tostring
                           else "\(tojson), which is no number" end)),
          (.items[]? | select(.verdict == "fail") | .id as $id
           | select(any($record.failures[].case; . as $case | $id | of_case($case)) | not)
           | "item \($id) says fail and failures does not list its case: /qa writes the case "
             + "of every failure and lists it in failures"),
          (select(has("behaviour_without_requirement"))
           | select((.behaviour_without_requirement | type) != "array"
                    or (all(.behaviour_without_requirement[];
                            type == "object" and (.what | text) and (.where | text)) | not))
           | "behaviour_without_requirement is not a list of {what, where}"),
          (.behaviour_without_requirement[]? | (.what, .where) | select(test("TC-[0-9]+"))
           | "a behaviour nothing written describes names a case (\(.)): a case is written, "
             + "so what fails in it is a failure: list the case in failures, or leave its id "
             + "out of what and where"),
          null);
    if length == 1 then .[0] | fault // empty else $unreadable end' "$1" 2>/dev/null)" \
    || fault="$unreadable"
  [ -z "$fault" ] || printf '%s\n' "$fault"
}

# The qa.json records of a task as one JSON array, oldest first by the time each records,
# each with its folder as `run`. A record that cannot be read, or one of the task that has a
# fault (qa_record_fault), fails the whole call, with the record and its fault on stderr: it
# must never read as "no failures". A record that is no JSON object names no task, so it
# fails the call for every task: the line names the file, which may be another task's.
qa_records_of() {
  local record records fault
  records="$(for record in .review/runs/*/qa.json; do
      [ -f "$record" ] || continue
      jq -c --arg run "${record%/qa.json}" '. + {run: $run}' "$record" || {
        echo "   $record is not readable — the /qa records of a task are read from these "\
"files: repair it or remove that folder" >&2
        exit 1
      }
    done | jq -sc --arg id "$1" 'map(select(.task == $id)) | sort_by(.time // 0)')" || return 1
  while IFS= read -r record; do
    [ -n "$record" ] || continue
    fault="$(qa_record_fault "$record/qa.json")"
    [ -z "$fault" ] || { echo "   $record/qa.json: $fault" >&2; return 1; }
  done < <(printf '%s' "$records" | jq -r '.[].run')
  printf '%s\n' "$records"
}

# The /qa records of a task as the reading of its runs takes them (JQ_READING): the output
# of qa_records_of on stdin, each record cut to {run, time, work, failures: [case]}. With
# the time a landing of the task committed (task_landed_at), the records made after it.
qa_cases_of() {
  jq -c --argjson after "${1:-0}" "$JQ_LANDED_SINCE"'
    map(select(landed_since($after))
        | {run, time: (.time // 0), work: (.work // null), failures: [.failures[].case]})'
}

# On how many works /qa of a task failed each case that a record lists in failures — the
# newest record of the task, or the one given — and in which records: a JSON array of
# {case, times, runs}, runs being the folders, oldest first, one for each work
# (works_failed). The records counted are those made after a landing of the task
# committed, as review.sh reads them.
qa_times() {
  local records cases landed_at
  landed_at="$(task_landed_at "$1")" || return 1
  records="$(qa_records_of "$1")" || return 1
  if [ $# -ge 2 ]; then
    cases="$(jq -c '[.failures[].case]' "$2")" || return 1
  else
    cases="$(printf '%s' "$records" | jq -c '[(last // {}).failures[]?.case]')" || return 1
  fi
  records="$(printf '%s' "$records" | qa_cases_of "$landed_at")" || return 1
  printf '%s' "$records" | jq -c --argjson cases "$cases" "$JQ_WORKS_FAILED"'
    . as $records
    | reduce $cases[] as $case ([]; if index($case) != null then . else . + [$case] end)
    | map(. as $case | works_failed($records; $case)
          | {case: $case, times: length, runs: map(.run | split("/") | last)})'
}

# What a /qa record did not check, wherever a count decides or is shown — the merge (M5,
# qa_left_nothing_open) and the status of /qa. An item /qa put off until after the merge
# (after_merge, with its reason and its check) is none of them: the merge does not wait on
# it, and the script that merges owes its check (owe_after_merge). A count of items put
# off that no item of the record backs names no check to owe (put_off_unlisted), so it
# stays among those not checked; one that is no number counts as one: it never reads as
# none.
JQ_NOT_CHECKED='def put_off_unlisted:
  (((.counts | objects | .after_merge) // 0) | if type == "number" then . else 1 end) as $counted
  | ([.items | arrays | .[] | objects | select(.verdict == "after_merge")] | length) as $listed
  | if $counted > $listed then $counted - $listed else 0 end;
def not_checked: (.counts.not_checked // 0) + put_off_unlisted;
'

# What /qa put off until after the merge of a task: the items with the verdict after_merge
# of its records, as a JSON array of {id, reason, check, from}, `from` being the folder of
# the record. Of an id that several records list, the newest decides: its reason and its
# check hold, and an item that it lists with another verdict was checked and is put off no
# more. The records are those made after a landing of the task committed (landed_since).
qa_after_merge_items() {
  local records landed_at
  landed_at="$(task_landed_at "$1")" || return 1
  records="$(qa_records_of "$1")" || return 1
  printf '%s' "$records" | jq -c --argjson after "$landed_at" "$JQ_LANDED_SINCE"'
    reduce (.[] | select(landed_since($after)) | .run as $from | .items[]?
            | {id, verdict, reason, check, from: $from}) as $item
      ([]; map(select(.id != $item.id)) + [$item])
    | map(select(.verdict == "after_merge") | del(.verdict))'
}

# One line of what /qa left: the items of a record with one verdict, as `   <n> <words>:
# <id> (<reason>); …`, the ids and reasons when the record lists its items. Nothing, and
# exit 1, when there is no such item.
qa_left_items() {
  local line
  line="$(jq -r --arg verdict "$2" --arg words "$3" '
    ((.counts | objects | .[$verdict]) // 0) as $count
    | select($count > 0)
    | ([.items[]? | select(.verdict == $verdict) | "\(.id) (\(.reason))"] | join("; ")) as $list
    | "   \($count) \($words)" + (if $list == "" then "" else ": \($list)" end)' "$1")" \
    || return 1
  [ -n "$line" ] || return 1
  printf '%s\n' "$line"
}

# What a /qa left and whose turn each thing is: `pr-post.sh qa <qa-dir>` prints it after
# every /qa, at every level. Each thing is on stdout and ends with its line of `turn`, on
# stderr. A failing case says what is to be seen, so it is the loop's to fix, however
# often /qa was red; the same case failing on three works — after each of two fixes — does
# not converge, and that is the user's: review.sh stops the task there, and runs once more
# when they decided to go on. An unproven item and one not checked are the loop's. An item
# put off until after the merge holds nothing: it says its check, which the loop makes
# right after the merge at the pull request levels — <level> is the LANDING of the
# project — and below them, where nothing merges, it stands in the report. A count of such
# items with no item behind it counts as not checked (JQ_NOT_CHECKED). What the app does
# that nothing written describes is the one question that holds nothing.
qa_left() {
  local task_id="$1" qa_dir="$2" level="$3" record="$2/qa.json" times entry case_id count runs
  local line
  local words tests why next said=false
  times="$(qa_times "$task_id" "$record")" || return 1
  echo "── what /qa left in $(basename "$qa_dir"), and whose it is:"
  while IFS=$'\t' read -r case_id count runs; do
    [ -n "$case_id" ] || continue
    said=true
    line="$(case_line "$case_id")"
    tests=""
    if [ -z "$line" ]; then
      echo "   $case_id failed, and qa/test-cases.md has no $case_id"
      next="have /qa write the case of $case_id, then fix it"
    else
      words="$(case_words | awk -F'\t' -v wanted="$case_id" '$1 == wanted { print $2; exit }')"
      tests="$(case_tests "$case_id" | awk 'NR > 1 { printf ", " } { printf "%s", $0 }')"
      echo "   $case_id failed. What should be is written (qa/test-cases.md:$line):"
      echo "      \"$words\""
      if [ -n "$tests" ]; then
        echo "      its end-to-end test: $tests"
        next="fix $case_id — it is no question: see its test fail in a run of review.sh made "\
"now, then fix, then see it pass (condition 7)"
      elif why="$(case_manual | awk -F'\t' -v wanted="$case_id" '$1 == wanted { print $2; exit }')"
           [ -n "$why" ]; then
        echo "      /qa marks it manual: $why"
        next="fix $case_id — it is no question: no end-to-end test can see it, so the next /qa "\
"that passes it on the changed work proves it (condition 7)"
        [ -n "$(jq -r '.work // ""' "$record")" ] || \
          next="$next; this record does not say which work /qa checked (work): have /qa add "\
"it — pr-post.sh work prints it — or no later /qa proves the fix"
      else
        echo "      no end-to-end test is marked for it"
        next="fix $case_id — it is no question: write its end-to-end test and mark the case "\
"(e2e: \`<test>\`), see it fail in a run of review.sh made now, then fix, then see it pass; "\
"where no end-to-end test can see it, /qa says so in the case (— manual: <why>), and the next "\
"/qa after the fix proves it"
      fi
    fi
    [ "$count" -lt 2 ] || \
      echo "      it failed in $count /qa of this task, each on other work: $runs"
    if [ "$count" -ge 3 ]; then
      turn user:not-converging "$case_id failed again after each of $((count - 1)) fixes — "\
"whether to go on trying, to stop the task here, or to change what the case expects; say "\
"what /qa saw each time and what each fix changed; when they decide to go on, review.sh runs "\
"once more with --past-limit --user-decided"
    elif [ "$count" -eq 2 ]; then
      turn loop "$next; it failed after a fix before: find why that fix did not hold first"
    else
      turn loop "$next"
    fi
  done < <(printf '%s' "$times" | jq -r '.[] | [.case, .times, (.runs | join(", "))] | @tsv')

  # Failures counted under no case: /qa writes the case of every failure. A record that
  # lists its items cannot hold one (qa_record_fault); one with counts alone says so when
  # it lists no case at all.
  line="$(jq -r '
    select((has("items") | not) and .failures == [])
    | ((.counts | objects | .fail) // 0) as $count
    | select($count > 0)
    | "   \($count) failed with no case among the failures"' "$record")" || return 1
  if [ -n "$line" ]; then
    said=true
    printf '%s\n' "$line"
    turn loop "have /qa write the case of each, then fix it"
  fi
  if qa_left_items "$record" unproven "unproven"; then
    said=true
    turn loop "an unproven item goes back to the work, which makes it provable"
  fi
  if qa_left_items "$record" not_checked "not checked"; then
    said=true
    turn loop "restore what failed — a tool, a device — and run /qa again"
  fi
  line="$(jq -r '
    [.items[]? | select(.verdict == "after_merge")]
    | select(length > 0)
    | "   \(length) to check after the merge — they do not hold it:",
      (.[] | "      \(.id) — \(.reason | sub("[.]$"; "")). Then: \(.check)")' "$record")" \
    || return 1
  if [ -n "$line" ]; then
    said=true
    printf '%s\n' "$line"
    if landing_opens_pull_request "$level"; then
      turn loop "they are checked right after the merge (/qa --after-merge $task_id)"
    else
      turn loop "nothing merges at LANDING=$level: what is put off stands in the report of "\
"the task (maintain, step 13)"
    fi
  fi
  line="$(jq -r "$JQ_NOT_CHECKED"'
    put_off_unlisted | select(. > 0)
    | "   \(.) put off until after the merge by a count alone: no item says its check, so "
      + "they count as not checked"' "$record")" || return 1
  if [ -n "$line" ]; then
    said=true
    printf '%s\n' "$line"
    turn loop "have /qa list each as an item, with its reason and the check that will be "\
"made then (items), or check it now"
  fi
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    said=true
    qa_question "$entry"
  done < <(jq -c '.behaviour_without_requirement[]?' "$record")
  [ "$said" = true ] || echo "   nothing: every item passed"
}

# What the /qa of a task saw that no requirement, exit criterion or case describes, each
# once, the oldest first: a JSON array of {what, where}.
qa_questions() {
  local records
  records="$(qa_records_of "$1" 2>/dev/null)" || return 1
  printf '%s' "$records" | jq -c '
    reduce .[].behaviour_without_requirement[]? as $seen ([];
      if any(.[]; .what == $seen.what) then . else . + [$seen] end)'
}

# One of them, as a line of `turn`: the one question a /qa leaves the user. `pr-post.sh qa`,
# right after /qa, is where it is said and where it is asked. With `named`, for the ends
# that come later and come again: the line names the question and says that it is not
# asked again there.
qa_question() {
  local seen
  seen="$(printf '%s' "$1" | jq -r '"\(.what) (\(.where))" | gsub("\\s+"; " ")')"
  seen="$seen — /qa saw it, and"
  if [ "${2:-}" = named ]; then
    turn user:what-should-be "$seen pr-post.sh qa, right after that /qa, is where it is "\
"asked, once: it is not asked again here"
  else
    turn user:what-should-be "$seen no requirement, exit criterion or case says what should "\
"happen: ask it once, in their words; the task does not wait for the answer unless one of its "\
"own criteria does"
  fi
}

# Those questions of a task, named at the end of a landing, of --check and of a merge. It
# prints nothing when there is none, and never stops what calls it: the conditions read the
# records. No record says that a question was asked or answered, so every such end names
# it, and none asks it.
qa_asks() {
  local questions entry
  questions="$(qa_questions "$1")" || return 0
  while IFS= read -r entry; do
    [ -z "$entry" ] || qa_question "$entry" named
  done < <(printf '%s' "$questions" | jq -c '.[]')
}

# ---------------------------------------------------------------------------
# The conditions of a review run. land.sh checks them before a commit (TASK_LOOP.md, "The
# contract"); publish.sh before a merge at the pull request levels, as items of the merge
# contract; pr-post.sh shows them in the statuses it posts. Each reports through the caller's
# `refuse <condition> <reason> [<whose> <what>]`, which does not return, and names the
# condition by its number in land.sh; with the last two the caller ends with the line of
# `turn`.
# ---------------------------------------------------------------------------

# 1. The run directory is a completed review run. Missing files must never read as "nothing
#    was found" — that would let any empty directory authorise a commit.
#    The end-to-end tests may have run in a repeat of them alone (run_e2e_record). The
#    review's own files are run_review_is_complete: the review's status on the pull request
#    asks for those alone, since the review is made whatever the tests come to.
run_review_is_complete() {
  local run="$1" artifact
  for artifact in meta.json verdicts.json approved.json escalated.json; do
    [ -f "$run/$artifact" ] || \
      refuse 1 "$run has no $artifact — this is not a completed review run"
  done
}
run_is_complete() {
  run_review_is_complete "$1"
  [ -f "$(run_e2e_record "$1")" ] || \
    refuse 1 "$1 has no e2e.json — this is not a completed review run"
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
#    the harness is in the reviewed diff and lands with the task. What is read is the newest
#    try of the run's tests, a repeat of them on the same work included (run_e2e_record).
run_e2e_passed() {
  local run="$1" fingerprint="$2" platforms_now record
  record="$(run_e2e_record "$run")"
  platforms_now="$(platforms | jq -R . | jq -sc .)"
  jq -e --arg fingerprint "$fingerprint" --argjson need "$platforms_now" \
    '.status == "pass" and .fingerprint == $fingerprint and (($need - .platforms) | length) == 0' \
    "$record" >/dev/null 2>&1 || \
    refuse 3 "the end-to-end tests of this run did not pass on every platform the tree ships: "\
"$(printf '%s' "$platforms_now" | jq -r 'join(" ")')"
  run_e2e_checked_now "$run"
}

# The half of condition 3 that a platform's own tests answer to as well, whatever the other
# platforms came to: the harness is `.review/e2e.sh` and any `.review/e2e-*` it calls, each
# now as it ran (recorded before the run), `.review/e2e.sh` there; and every mark of
# qa/test-cases.md was one the run was checked against.
run_e2e_checked_now() {
  local run="$1" harness_now
  harness_now="$(harness_blobs)"
  case "$harness_now" in *" .review/e2e.sh"*) ;; *) harness_now="" ;; esac
  [ -n "$harness_now" ] && \
    [ "$(jq -r '.harness // ""' "$(run_e2e_record "$run")")" = "$harness_now" ] || \
    refuse 3 ".review/e2e.sh, or a .review/e2e-* beside it, is not as it ran — review again"
  marks_checked_by_run "$run"
}

# Every test a case of qa/test-cases.md names now, under that case, was one the run was
# checked against. The cases are one of the loop's own files, outside condition 2: a mark
# written since the run names a test no run has seen pass. land.sh checks it again after the
# gates, which run between here and the commit.
marks_checked_by_run() {
  local run="$1" now unchecked record
  record="$(run_e2e_record "$run")"
  now="$(case_marks | marks_json)" || refuse 3 "could not read the marks of qa/test-cases.md"
  unchecked="$(jq -r --argjson now "$now" \
    '$now - (.marks // []) | map("\(.case) \(.test)") | join(", ")' "$record")" || \
    refuse 3 "$record is unreadable"
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
#    never written at its start (PLANNING_GUIDE.md, "Task Rules"). A claim that starts with
#    `after the merge:` is not made yet: what follows the colon is the id of an item /qa
#    put off until then (qa_after_merge_items), whose result after the merge is the evidence.
criteria_verified() {
  local unverified later put_off unnamed
  unverified="$(jq -r '[.exit_criteria[] | select((.verified_by // "") == "")] | length' "$1")"
  [ "$unverified" -eq 0 ] || \
    refuse 7 "$unverified exit criterion/criteria have no verified_by claim"
  later="$(jq -c '[.exit_criteria[] | select(.verified_by | strings
                                             | startswith("after the merge:"))]' "$1")"
  [ "$later" != "[]" ] || return 0
  put_off="$(qa_after_merge_items "$(jq -r '.id' "$1")")" || \
    refuse 7 "a qa.json is unreadable or not {task, failures: [{case: TC-nnn}]}, or its items "\
"do not hold — refusing to read what /qa put off until after the merge; the line before this "\
"one says what"
  unnamed="$(jq -rn --argjson later "$later" --argjson put_off "$put_off" '
    [$later[]
     | (.verified_by | sub("^after the merge:\\s*"; "") | sub("\\s+$"; "")) as $id
     | select(any($put_off[]; .id == $id) | not) | .text // "with no text"]
    | first // empty')"
  [ -z "$unnamed" ] || \
    refuse 7 "the criterion '$unnamed' is put off until after the merge and names no item /qa "\
"put off until then (after the merge: <the item's id>)" loop \
"have /qa record the item with its check, or claim what was checked"
}

# 7, /qa. /qa checked the task, and each failure it recorded — in a qa.json, or in the
#    qa_failures an e2e.json of this task took from one, which outlasts a qa.json rewritten or
#    removed — is proven. For each failing case the first of these that holds decides:
#    - the user answered it: proven. The loop never asks for that answer.
#    - it has no marked test now and a run of the task recorded one for it: the mark was
#      taken off a failing case, and nothing proves it.
#    - it has a marked test: that test failed in a try of another run of this task made
#      after /qa recorded the failure — the run's own or a repeat's (run_e2e_tries) —, and
#      passes in the newest try of this run, or is skipped in it under a tag of the case for
#      the task it belongs to — and the words of the case are those the newest /qa that
#      failed it failed it with (cases.json beside its record, kept by pr-post.sh qa), or,
#      where none was kept, those the oldest such red try recorded (cases in its e2e.json;
#      a run made before they were recorded is not compared): a case reworded since /qa
#      failed it proves nothing. A test red and then green in tries of this run proves no
#      fix. A pass of /qa never stands in for a case that has a test.
#    - it has no test and says why none can see it (case_manual): the newest /qa record of
#      the task with items of the case passed them all — and among them each item of the
#      case that failed in the failing record (`TC-nnn on <platform>`): a pass on another
#      platform proves nothing, and an item that passed then is not asked again —, is
#      newer than the newest record that lists the case in failures, and is of other work
#      than that one, both works known: pr-post.sh work prints the work at every level.
#      The refusal names each item that is not passed, or failed and is not there.
#    - anything else is not proven.
#    No test stays skipped for the task. Every record is read: an unreadable one refuses,
#    never reads as "no failures".
qa_failures_proven() {
  local run="$1" task_id="$2" records record tags task still runs failures now answered
  local case_id tests manual digests kept verdict reason
  local unproven="" unpassed="" lost="" reworded=""
  records="$(qa_records_of "$task_id")" || \
    refuse 7 "a qa.json is unreadable or not {task, failures: [{case: TC-nnn}]}, or its items "\
"do not hold — refusing to read it as no failures; the line before this one says what"
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

  # Every try of every run, each a record of its own: the run's e2e.json and each repeat's.
  # A try of the run that is landed is never the red side (`landed`).
  runs="$(for folder in .review/runs/*/; do
      folder="${folder%/}"
      run_e2e_tries "$folder" | while IFS= read -r record; do
        jq -c --arg run "${record#.review/runs/}" --arg folder "$(basename "$folder")" \
          --arg landed "$(basename "$run")" \
          '. + {run: ($run | sub("/e2e.json$"; "")), landed: ($folder == $landed)}' \
          "$record" || exit 1
      done || exit 1
    done | jq -sc --arg id "$task_id" '[.[] | select(.task == $id)
      | {run, landed, time: (.time // 0), qa: (.qa_failures // []),
         failed: [.results[]?.failed[]?], marks: (.marks // []), cases: (.cases // {})}]')" || \
    refuse 7 "an e2e.json is unreadable — refusing to read it as no failures"
  failures="$(jq -nc --argjson records "$records" --argjson runs "$runs" \
    '[$records[].failures[].case] + [$runs[].qa[]] | unique')" || \
    refuse 7 "could not gather the /qa failures of $task_id"
  # A run that never got as far as its end-to-end tests saw nothing pass. What passed is
  # the newest try of the run's tests, a repeat of them included (run_e2e_record).
  now='{"passed": [], "skipped": []}'
  if [ -f "$(run_e2e_record "$run")" ]; then
    now="$(jq -c '{passed: [.results[]?.passed[]?], skipped: [.results[]?.skipped[]?]}' \
      "$(run_e2e_record "$run")")" || refuse 7 "$(run_e2e_record "$run") is unreadable"
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
  manual="$(case_manual | cut -f1 | jq -R . | jq -sc .)" || \
    refuse 7 "could not read the cases of qa/test-cases.md"
  digests="$(case_digests)" || refuse 7 "could not read the cases of qa/test-cases.md"
  # The words each failing case had when /qa failed it, the newest such /qa last.
  kept="$(printf '%s' "$records" | jq -r '.[].run' | while IFS= read -r record; do
      [ -f "$record/cases.json" ] || continue
      jq -c --slurpfile kept "$record/cases.json" --arg run "$(basename "$record")" \
        '[.failures[].case as $case | $kept[0][$case] | strings
          | {($case): {digest: ., run: $run}}] | add // {}' "$record/qa.json" || exit 1
    done | jq -sc 'add // {}')" || \
    refuse 7 "a cases.json beside a qa.json of $task_id is unreadable — pr-post.sh qa writes it"

  for case_id in $(printf '%s' "$failures" | jq -r '.[]'); do
    tests="$(case_tests "$case_id" | while IFS= read -r test_id; do
        tagged=false
        skip_tag_on "$tags" "$case_id" "$test_id" && tagged=true
        jq -nc --arg test "$test_id" --argjson tagged "$tagged" '{test: $test, tagged: $tagged}'
      done | jq -sc .)"
    # proven, lost, unpassed or `unpassed <the items>`, `words <run>`, or anything else:
    # not proven. A query that dies proves nothing.
    verdict="$(jq -rn --argjson tests "$tests" --argjson runs "$runs" --argjson now "$now" \
          --argjson answered "$answered" --argjson records "$records" \
          --argjson manual "$manual" --argjson digests "$digests" --argjson kept "$kept" \
          --arg case "$case_id" \
          "$JQ_HIT$JQ_OF_CASE"'
      def among($rows): . as $id | any($rows[]; hit($id));
      if ($answered | index($case)) != null then "proven"
      elif ($tests | length) == 0 and any($runs[]; any(.marks[]; .case == $case)) then "lost"
      elif ($tests | length) > 0 then
        [$tests[] | select(. as $mark | ($mark.test | among($now.passed))
                           or ($mark.tagged and ($mark.test | among($now.skipped))))] as $green
        | ([$runs[] | select((.landed | not) and (.qa | index($case)) != null)
            | select(. as $run | any($green[]; .test | among($run.failed)))]
           | sort_by(.time)) as $reds
        | ($kept[$case]
           // ([$reds[] | select(.cases[$case] != null)] | first
               | if . == null then null else {digest: .cases[$case], run} end)) as $said
        | if ($reds | length) == 0 then "unproven"
          elif $said != null and $digests[$case] != null and $said.digest != $digests[$case]
            then "words \($said.run)"
          else "proven" end
      elif ($manual | index($case)) != null then
        ([$records[] | select(any(.failures[]; .case == $case))] | last) as $failed
        | ([$records[] | select(any(.items[]?; .id | of_case($case)))] | last) as $checked
        | if $failed != null and $checked != null
             and ($checked.time // 0) > ($failed.time // 0)
             and ($failed.work // "") != "" and ($checked.work // "") != ""
             and $checked.work != $failed.work
          then
            ($checked.run | split("/") | last) as $later
            | [($checked.items[] | select(.id | of_case($case)) | select(.verdict != "pass")
                | "item \(.id) says \(.verdict) in \($later)"),
               ($failed.items[]? | select(.verdict == "fail") | .id
                | select(of_case($case) and . != $case)
                | select(. as $id | any($checked.items[]; .id == $id) | not)
                | "item \(.) failed in \($failed.run | split("/") | last) and is not among "
                  + "the items of \($later)")] as $missing
            | if $missing == [] then "proven" else "unpassed \($missing | join(", "))" end
          else "unpassed" end
      else "unproven" end' 2>/dev/null)"
    case "$verdict" in
      proven) ;;
      lost) lost="$lost $case_id" ;;
      unpassed) unpassed="$unpassed${unpassed:+,} $case_id" ;;
      "unpassed "*) unpassed="$unpassed${unpassed:+,} $case_id (${verdict#unpassed })" ;;
      "words "*) reworded="$reworded${reworded:+,} $case_id (as recorded in ${verdict#words })" ;;
      *) unproven="$unproven $case_id" ;;
    esac
  done
  reason=""
  [ -z "$unproven" ] || reason="without an end-to-end test seen red, then green:$unproven"
  [ -z "$unpassed" ] || reason="${reason:+$reason; }of a case /qa marks manual, not passed by "\
"a later /qa on other work:$unpassed"
  [ -z "$lost" ] || \
    reason="${reason:+$reason; }lost its end-to-end test after /qa failed it:$lost"
  [ -z "$reworded" ] || \
    reason="${reason:+$reason; }whose words changed since /qa failed it:$reworded"
  [ -z "$reason" ] || \
    refuse 7 "a /qa failure $reason" loop \
"fix it — the case says what is to be seen, so this is no question: mark the case with its "\
"test (e2e: \`<test>\`), see it fail in a run of $task_id made after /qa recorded it, then pass; "\
"a case no end-to-end test can see, which /qa marks — manual: <why>, is proven by the next /qa "\
"that passes it after the fix, each /qa recording the work it checked (pr-post.sh work prints "\
"it); a mark stays on a failing case, and so do its words"
}

# 7, /qa at the pull request levels. The newest qa.json of the task, by the time inside it,
#    checked the work as it is now, and one of them checked the whole pull request: its
#    change since the merge base. A /qa after a fix checks only what the fix can reach.
qa_checked_this_work() {
  local task_id="$1" fingerprint="$2" merge_base="$3" records
  records="$(qa_records_of "$task_id")" || \
    refuse 7 "a qa.json is unreadable or not {task, failures: [{case: TC-nnn}]}, or its items "\
"do not hold — refusing to read it as no failures; the line before this one says what"
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
# left, in <its folder>/open-answered.json: {"by": "human", "answer": "accepted-as-is"}. It
# keeps no words; a record made before, which holds some, is read as it is
# (qa_open_accepted). A /qa after a fix checks only what the fix can reach, so what an
# earlier one left open goes away only with a later /qa of the whole pull request or with
# the user's acceptance. An item put off until after the merge is in neither count:
# the merge does not wait on it, and owes its check (owe_after_merge). A count of items put
# off that no item backs is among those not checked (JQ_NOT_CHECKED), and the refusal says
# how many of them are such.
#
# The refusal names the open items when the record lists them, and says whose turn it is.
# It is the loop's first, and its line says what applies to what the record left: an
# unproven item goes back to the work; what a tool or a device kept from being checked is
# restored, and an item that can be checked only after the merge is one /qa records as put
# off until then; a count of items put off that no item backs gets its items. Then /qa
# checks the whole pull request again. It is the user's once the loop has tried again,
# which is read of each item by its id: every item that the newest /qa of the whole pull
# request left open was left open by a record of the task before it too, and the user
# accepted nothing beside that record. An item that is open for the first time keeps the
# stop the loop's. A record of counts alone names no item, so it is read by its counts:
# such a record tried again when any record before it left something open, and an older
# one of that form left open whatever a newer one lists.
qa_open_accepted() {
  json_holds '.by == "human" and .answer == "accepted-as-is"' "$1/open-answered.json"
}
qa_left_nothing_open() {
  local task_id="$1" merge_base="$2" records landed_at accepted open run counts tried detail
  local unproven unchecked unlisted next
  records="$(qa_records_of "$task_id")" || \
    refuse 7 "a qa.json is unreadable or not {task, failures: [{case: TC-nnn}]}, or its items "\
"do not hold; the line before this one says what"
  landed_at="$(task_landed_at "$task_id")"
  accepted="$(printf '%s' "$records" | jq -r '.[].run' | while IFS= read -r run; do
      ! qa_open_accepted "$run" || printf '%s\n' "$run"
    done | jq -R . | jq -sc .)"
  open="$(printf '%s' "$records" | jq -r --arg since "$merge_base" \
    --argjson after "${landed_at:-0}" --argjson accepted "${accepted:-[]}" \
    "$JQ_NOT_CHECKED$JQ_LANDED_SINCE"'
    def left: (.counts.unproven // 0) + not_checked;
    def open_items: [.items[]? | select(.verdict == "unproven" or .verdict == "not_checked")];
    def by_counts: (.items | type) != "array" or (open_items | length) == 0;
    def left_before($id):
      by_counts or ((.run as $run | all($accepted[]; . != $run))
                    and any(open_items[]; .id == $id));
    ([to_entries[] | select(.value.since == $since and (.value.counts | type) == "object")
      | .key] | last // 0) as $from
    | [.[:$from][] | select(landed_since($after) and left > 0)] as $older
    | .[$from:] | to_entries[] | .key as $at | .value | select(left > 0)
    | (if $at > 0 or ($older | length) == 0 then "first"
       elif by_counts then "again"
       elif all(open_items[]; .id as $id | any($older[]; left_before($id))) then "again"
       else "first" end) as $tried
    | "\(.run)\t\(.counts.unproven // 0) unproven and \(not_checked) not checked\t\($tried)\t"
      + "\(.counts.unproven // 0) \(.counts.not_checked // 0) \(put_off_unlisted)\t"
      + ((if put_off_unlisted > 0
          then " (\(put_off_unlisted) of them put off until after the merge by a count alone: "
               + "no item says its check)"
          else "" end)
         + (open_items | map("\(.id) (\(.reason))")
            | if length > 0 then ": " + join("; ") else "" end)
         | gsub("[\\t\\n\\r]+"; " "))')"
  while IFS=$'\t' read -r run counts tried next detail; do
    [ -n "$run" ] || continue
    ! qa_open_accepted "$run" || continue
    [ "$tried" != again ] || \
      refuse 7 "/qa of the whole pull request ran again and still left $counts in "\
"$(basename "$run")$detail" user:beyond-agreed \
"merge without that checked, or not; their acceptance goes into $run/open-answered.json, "\
"{\"by\": \"human\", \"answer\": \"accepted-as-is\"}"
    read -r unproven unchecked unlisted <<<"$next"
    next=""
    [ "$unproven" = 0 ] || next="an unproven item goes back to the work; "
    [ "$unlisted" = 0 ] || \
      next="${next}have /qa list each item it put off by a count alone, with its reason and "\
"the check that will be made then (items), or check it now; "
    if [ "$unchecked" = 0 ]; then
      next="${next}then run /qa of the whole pull request again"
    else
      next="${next}restore what failed — boot or erase the simulator — and run /qa of the "\
"whole pull request again; an item that can be checked only once the pull request is merged "\
"is recorded by /qa as after_merge, with the check it will make, and does not hold the merge"
    fi
    refuse 7 "/qa left $counts in $(basename "$run")$detail" loop "$next"
  done <<<"$open"
}

# 7, /qa at the pull request levels, continued. The reports of the newest /qa and of the newest
# one of the whole pull request are on it: what /qa found stays where people look.
qa_reports_posted() {
  local task_id="$1" merge_base="$2" pr_url="$3" records run
  records="$(qa_records_of "$task_id")" || \
    refuse 7 "a qa.json is unreadable or not {task, failures: [{case: TC-nnn}]}, or its items "\
"do not hold; the line before this one says what"
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
  local task_file="$1" pr_url="${2:-}" task_id runs newest run qa later
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
  printf 'Exit-Criteria: %s\n' "$(jq -r '
    [.exit_criteria[]? | .verified_by // "" | select(. != "")]
    | ([.[] | strings | select(startswith("after the merge:"))] | length) as $later
    | "\(length - $later) verified"
      + (if $later > 0 then ", \($later) to check after the merge" else "" end)' "$task_file")"
  if [ -n "$newest" ]; then
    printf 'Review-Runs: %s, last %s\n' "$(printf '%s\n' "$runs" | grep -c .)" \
      "$(basename "$newest")"
  else
    printf 'Review-Runs: 0\n'
  fi
  later="$(qa_after_merge_items "$task_id" 2>/dev/null | jq 'length' 2>/dev/null)"
  qa="$(qa_records_of "$task_id" 2>/dev/null | jq -r --argjson later "${later:-0}" '
    last // empty
    | "QA: \(.run | split("/") | last) (\(.extent // "extent not recorded")"
      + (if $later > 0 then "; \($later) to check after the merge" else "" end) + ")"' \
    2>/dev/null)"
  [ -z "$qa" ] || printf '%s\n' "$qa"
}

# What a merged task owes: the checks /qa put off until after its merge, written down by
# the script that merged, once for a pull request, as
# .review/runs/after-merge-<task>/owed.json — {task, pr_url, pr_number, base, time, items:
# [{id, reason, check, from}]}. owe_after_merge <task-id> <pr-url> <pr-number> <base>
# [<items>] writes it when there are such items, and prints nothing. <items> is what
# qa_after_merge_items gave before the merge: a merge may leave this checkout on the base
# branch, where the records of the task read as those of a task that landed. A folder that
# holds the list of another pull request of the task keeps it, and this one's goes beside
# it, with the number of its pull request in its name.
owe_after_merge() {
  local task_id="$1" pr_url="$2" pr_number="$3" base="$4" items="${5:-}" folder list count
  for list in .review/runs/after-merge-*/owed.json; do
    [ -f "$list" ] || continue
    ! json_holds --arg url "$pr_url" '.pr_url == $url' "$list" || return 0
  done
  [ -n "$items" ] || items="$(qa_after_merge_items "$task_id")" || return 1
  count="$(printf '%s' "$items" | jq 'length')" || return 1
  [ "$count" -gt 0 ] || return 0
  folder=".review/runs/after-merge-$task_id"
  [ ! -e "$folder/owed.json" ] || folder="$folder-pr$pr_number"
  mkdir -p "$folder" || return 1
  jq -n --arg task "$task_id" --arg url "$pr_url" --arg number "$pr_number" --arg base "$base" \
    --argjson items "$items" '
    {task: $task, pr_url: $url, pr_number: ($number | tonumber? // $number), base: $base,
     time: (now | floor), items: $items}' >"$folder/owed.json.new" \
    && mv "$folder/owed.json.new" "$folder/owed.json"
}

# What is still owed after the merges of earlier tasks: one line of JSON for each item of
# an owed.json that is not settled, {task, id, why, kind, folder, check, reason, pr_url}.
# An item is settled when results.json beside the list, a JSON array, holds an entry of its
# id — the last one — that says
#  - pass, with what was seen (evidence);
#  - fail, with its reason and the task that takes the defect: a heading `### <task>: ` of
#    TASK_TRACKER.md, and not the merged task;
#  - or not_checked, with its reason, and open-answered.json beside it records the
#    acceptance: {"by": "human", "answer": "accepted-as-is"}.
# `kind` says what is missing: result — the check, or what it saw; task — the task of a
# failure; accepted — the acceptance of a check that could not be made; list — an owed.json
# that cannot be read, which names no task. A file that cannot be read settles nothing.
after_merge_unsettled() {
  local list folder tasks="" results accepted
  for list in .review/runs/after-merge-*/owed.json; do
    [ -f "$list" ] || continue
    folder="${list%/owed.json}"
    [ -n "$tasks" ] || \
      tasks="$(awk '/^### / { line = substr($0, 5); at = index(line, ": ")
                              if (at > 1) print substr(line, 1, at - 1) }' TASK_TRACKER.md \
                 2>/dev/null | jq -R . | jq -sc .)"
    results="$(jq -sc 'if length == 1 and (.[0] | type) == "array" then .[0] else empty end' \
      "$folder/results.json" 2>/dev/null)"
    accepted=false
    ! json_holds '.by == "human" and .answer == "accepted-as-is"' \
        "$folder/open-answered.json" || accepted=true
    jq -c --arg folder "$folder" --argjson results "${results:-[]}" \
      --argjson tasks "${tasks:-[]}" --argjson accepted "$accepted" '
      def text: type == "string" and . != "";
      . as $owed
      | .items[] | .id as $id
      | ([$results[] | objects | select(.id == $id)] | last) as $result
      | (if $result == null then ["result", "no result"]
         elif $result.verdict == "pass" then
           (if $result.evidence | text then null
            else ["result", "passed without what was seen (evidence)"] end)
         elif $result.verdict == "fail" then
           (if $result.reason | text | not
              then ["result", "failed without what was seen (reason)"]
            elif ($result.task | text) and $result.task != $owed.task
                 and any($tasks[]; . == $result.task) then null
            else ["task", "failed and names no task of the tracker"] end)
         elif $result.verdict == "not_checked" then
           (if $result.reason | text | not
              then ["result", "not checked without the reason (reason)"]
            elif $accepted then null
            else ["accepted", "could not be checked and is not accepted"] end)
         else ["result", "no result"] end) as $open
      | select($open != null)
      | {task: $owed.task, id: $id, why: $open[1], kind: $open[0], folder: $folder,
         check: (.check // ""), reason: ($result.reason? // ""),
         pr_url: ($owed.pr_url // "")}' "$list" 2>/dev/null \
      || jq -nc --arg folder "$folder" '
           {task: "", id: "owed.json", why: "the list is not readable", kind: "list",
            folder: $folder, check: "", reason: "", pr_url: ""}'
  done
}

# The lists that no run of publish.sh wrote. At pr the user merges, and publish.sh learns
# of it only when it is run on the task's branch afterwards; on the base branch it refuses.
# So a merge is also read from what this copy holds: the /qa records of a task whose
# reports are on one pull request (pr-comment.json beside each) put items off, the newest
# of them was made before a landing of the task committed with its review — the squash of
# that pull request, in the history of HEAD (task_landed_at) — and no list names the pull
# request. Its list is written then, as owe_after_merge writes it, with the base branch
# land.conf names, or none: no remote is asked here. While a list is there that cannot be
# read, or names no pull request, none is written: it may be the one that is missing, and
# it is said and holds a later merge until it is repaired. owe_merged_unlisted <land.conf>
# prints nothing; what it could not read or write it leaves to the next run.
owe_merged_unlisted() {
  local config="$1" record records listed="" list merged task url landed_at
  records="$(for record in .review/runs/*/qa.json; do
      [ -f "$record" ] || continue
      jq -c --arg run "${record%/qa.json}" \
        --arg url "$(jq -r '.pr_url // ""' "${record%/qa.json}/pr-comment.json" 2>/dev/null)" '
        select(type == "object" and (.task | type) == "string" and $url != "")
        | {task, time: ((.time | numbers) // 0), run: $run, url: $url,
           items: [.items | arrays | .[] | objects]}' "$record" 2>/dev/null
    done | jq -sc 'sort_by(.time)')" || return 0
  for list in .review/runs/after-merge-*/owed.json; do
    [ -f "$list" ] || continue
    url="$(jq -r '.pr_url | strings' "$list" 2>/dev/null)"
    [ -n "$url" ] || return 0
    listed="$listed$url"$'\n'
  done
  listed="$(printf '%s' "$listed" | jq -R . | jq -sc .)" || return 0
  while IFS= read -r merged; do
    [ -n "$merged" ] || continue
    task="$(printf '%s' "$merged" | jq -r '.task')"
    url="$(printf '%s' "$merged" | jq -r '.url')"
    landed_at="$(task_landed_at "$task")"
    [ "${landed_at:-0}" -gt 0 ] || continue
    json_holds --argjson after "$landed_at" "$JQ_LANDED_SINCE"'landed_since($after) | not' \
      <<<"$merged" || continue
    owe_after_merge "$task" "$url" "${url##*/}" "$(read_conf "$config" BASE_BRANCH "")" \
      "$(printf '%s' "$merged" | jq -c '.items')" 2>/dev/null
  done < <(printf '%s' "$records" | jq -c --argjson listed "${listed:-[]}" '
    group_by([.task, .url])[]
    | select(.[0].url as $url | all($listed[]; . != $url))
    | {task: .[0].task, url: .[0].url, time: last.time,
       items: (reduce (.[] | .run as $from | .items[]
                       | {id, verdict, reason, check, from: $from}) as $item
                 ([]; map(select(.id != $item.id)) + [$item])
               | map(select(.verdict == "after_merge") | del(.verdict)))}
    | select(.items | length > 0)' 2>/dev/null)
}

# The same, as review.sh and land.sh say it in every run: one line on stderr for each item,
# or for a list that cannot be read, and nothing when nothing is owed. It stops no run: only
# a later merge waits (publish.sh, M10). A merge that no run of publish.sh saw gets its
# list first (owe_merged_unlisted): say_after_merge_unsettled <land.conf>.
say_after_merge_unsettled() {
  local unsettled
  owe_merged_unlisted "$1"
  unsettled="$(after_merge_unsettled)"
  [ -n "$unsettled" ] || return 0
  printf '%s\n' "$unsettled" | jq -r '
    if .kind == "list"
    then "OWED — \(.folder)/owed.json, the list of the checks a merged task owes, is not readable"
    else "OWED — \(.task): \(.id), put off until after its merge: \(.why) (\(.folder))" end' >&2
}

# ---------------------------------------------------------------------------
# The hold on a platform
# ---------------------------------------------------------------------------

# One run of the end-to-end tests uses a platform — android, ios — at a time, in every copy
# of every project of the user on this machine (e2e-gate.sh). A hold is a folder
# <place>/<platform>.lock, and the one whose mkdir makes it holds the platform. Its file
# `holder` is one JSON object: `pid` and `pid_started`, the process that holds and when it
# started; `root`, the project; `who`, what holds — a run folder, or a check by hand
# (device.sh); `kind`, run or agent; `since` and `until`, in seconds since 1970. Its file
# `group`, {group, group_started}, is the process group of the harness and when its leader
# started: a file of its own, since the holder's renewal writes `holder` meanwhile. The hold is a lease: it holds until `until`, and only
# a holder that lives renews it, so a run that was killed frees the platform by itself, and
# whoever takes it over stops the process group it left running. A run that still lives
# keeps its hold when it renewed late, as after a machine that slept. A check's hold (kind
# agent) runs out by its lease alone: the check takes the platform again to keep it, and a
# run of the same copy of the project takes it over at once. HOLD_PLACE is the place
# (device_lock_dir); HOLD_SAID says why a hold was not taken.

# The place where the runs meet: DEVICE_LOCK_DIR of the environment (selftest.sh alone sets
# it), else of land.conf, else one folder of the user under /tmp, the same for every copy of
# every project: /tmp is shared by every process on macOS and Linux, TMPDIR is not.
device_lock_dir() {
  local place="${DEVICE_LOCK_DIR:-}"
  [ -n "$place" ] || place="$(read_conf "$1" DEVICE_LOCK_DIR "")"
  printf '%s' "${place:-/tmp/review-devices-$(id -u)}"
}

# The settings of the hold in <config>, each with its default, or 1 with what is wrong on
# stderr: hold_lock_setting prints E2E_LOCK, platform or off; hold_seconds <config> <key>
# <default>, a setting of whole seconds.
hold_lock_setting() {
  local value
  value="$(read_conf "$1" E2E_LOCK platform)"
  case "$value" in
    platform|off) printf '%s' "$value" ;;
    *) echo "E2E_LOCK in $1 must be platform or off, not '$value'" >&2; return 1 ;;
  esac
}
hold_seconds() {
  local value
  value="$(read_conf "$1" "$2" "$3")"
  case "$value" in
    ''|*[!0-9]*|??????????*)
      echo "$2 in $1 must be a whole number of seconds, not '$value'" >&2
      return 1 ;;
  esac
  printf '%s' "$value"
}

# When process <pid> started, as ps says it, or nothing when there is no such process.
process_started() {
  LC_ALL=C ps -o lstart= -p "$1" 2>/dev/null | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

# The record of the hold <lock>, as one line of JSON, or nothing when it has none that reads.
hold_holder() {
  jq -c 'select(type == "object")' "$1/holder" 2>/dev/null
}

# Whether this process holds <lock>: its record names this process and when it started.
hold_is_mine() {
  local holder
  holder="$(hold_holder "$1")"
  [ -n "$holder" ] && json_holds --arg pid "$$" --arg started "$(process_started "$$")" \
    '(.pid | tostring) == $pid and (.pid_started // "") == $started' <<<"$holder"
}

# Whether the record <holder> is the hold of a check by hand of this copy of the project.
hold_is_this_copys_check() {
  [ -n "$1" ] && json_holds --arg root "$(pwd)" '.kind == "agent" and .root == $root' <<<"$1"
}

# Who holds, in words: `<who> of <root> since <time>`.
hold_named() {
  if [ -z "$1" ]; then
    printf 'a holder that has not written who it is yet'
  else
    printf '%s' "$1" | jq -r '"\(.who // "?") of \(.root // "?") since "
      + (if (.since | type) == "number" then (.since | floor | todate) else "?" end)'
  fi
}

# Whether the hold <lock> with the record <holder> ran out: its lease ended and the run that
# holds it is gone, or it has no record and was made over a minute ago.
hold_ran_out() {
  local lock="$1" holder="$2" until pid started
  if [ -z "$holder" ]; then
    [ -n "$(find "$lock" -maxdepth 0 -mmin +1 2>/dev/null)" ]
    return
  fi
  until="$(printf '%s' "$holder" | jq -r 'if (.until | type) == "number" then .until | floor
    else 0 end')"
  [ "${until:-0}" -lt "$(date +%s)" ] || return 1
  pid="$(printf '%s' "$holder" | jq -r 'if .kind == "run" then .pid // "" else "" end')"
  case "$pid" in ''|*[!0-9]*) return 0 ;; esac
  started="$(process_started "$pid")"
  [ -n "$started" ] && [ "$started" = "$(printf '%s' "$holder" | jq -r '.pid_started // ""')" ] \
    && return 1
  return 0
}

# Takes over the hold <lock> of <platform> that ran out, or that a check of this copy held
# (<why>: is this copy's own): moves it aside, so that one taker alone does it, and stops
# the process group it recorded — unless another process has the group's number now — then
# says so on stderr. One taker at a time, while it makes the folder <lock>.taking, and only
# while the hold is still the one <holder> read; a <lock>.taking over a minute old is of a
# taker that was killed, and is removed. 1, it did not take the hold over.
hold_take_over() {
  local platform="$1" lock="$2" holder="$3" why="${4:-ran out}" aside="$2.taken.$$"
  local group stopped="" leader whose
  if ! mkdir "$lock.taking" 2>/dev/null; then
    [ -z "$(find "$lock.taking" -maxdepth 0 -mmin +1 2>/dev/null)" ] || rmdir "$lock.taking"
    return 1
  fi
  if [ "$(hold_holder "$lock")" != "$holder" ] || \
     { [ -z "$holder" ] && ! hold_ran_out "$lock" ""; } || ! mv "$lock" "$aside" 2>/dev/null
  then
    rmdir "$lock.taking"
    return 1
  fi
  rmdir "$lock.taking"
  if [ -n "$holder" ]; then
    whose="the hold of $(printf '%s' "$holder" | jq -r '"\(.who // "?") of \(.root // "?")"')"
    group="$(jq -r '.group // "" | tostring' "$aside/group" 2>/dev/null)"
    case "$group" in ''|*[!0-9]*) group="" ;; esac
    if [ -n "$group" ] && kill -0 -- "-$group" 2>/dev/null; then
      leader="$(process_started "$group")"
      if [ -z "$leader" ] || \
         [ "$leader" = "$(jq -r '.group_started // ""' "$aside/group" 2>/dev/null)" ]; then
        kill -TERM -- "-$group" 2>/dev/null && stopped="its tests, process group $group"
      fi
    fi
    echo "── $platform: $whose $why — taking over${stopped:+; stopped what it left running: $stopped}" >&2
  else
    echo "── $platform: the hold at $lock names no holder and is over a minute old — taking over" >&2
  fi
  rm -rf "$aside"
}

# hold_take <platform> <who> <kind> <lease> <wait>: holds the platform for <lease> seconds,
# waiting while another holds it, up to <wait> seconds, and saying every minute whom it waits
# for. 0, held; 75, still held by another after the wait; 1, the hold cannot be made at all.
# On 75 and 1, HOLD_SAID says why, as a reason of e2e.json: `<platform>: …`. A check's hold
# of this copy is taken over by a run (<kind> run), and made longer by a check (agent).
hold_take() {
  local platform="$1" who="$2" kind="$3" lease="$4" wait="$5"
  local lock="$HOLD_PLACE/$1.lock" waited=0 holder held_by now
  HOLD_SAID=""
  mkdir -p "$HOLD_PLACE" 2>/dev/null
  while :; do
    if mkdir "$lock" 2>/dev/null; then
      now="$(date +%s)"
      jq -n --argjson pid "$$" --arg started "$(process_started "$$")" --arg root "$(pwd)" \
        --arg who "$who" --arg kind "$kind" --argjson since "$now" \
        --argjson until "$((now + lease))" \
        '{pid: $pid, pid_started: $started, root: $root, who: $who, kind: $kind,
          since: $since, until: $until}' \
        >"$lock/holder" 2>/dev/null && return 0
      rm -rf "$lock"
    fi
    if [ ! -d "$lock" ] && { [ ! -d "$HOLD_PLACE" ] || [ ! -w "$HOLD_PLACE" ]; }; then
      HOLD_SAID="$platform: the hold cannot be made at $lock"
      return 1
    fi
    if [ -d "$lock" ]; then
      holder="$(hold_holder "$lock")"
      if hold_is_this_copys_check "$holder"; then
        if [ "$kind" = agent ]; then
          hold_extend "$lock" "$lease" && return 0
          HOLD_SAID="$platform: the hold cannot be made at $lock"
          return 1
        fi
        hold_take_over "$platform" "$lock" "$holder" "is this copy's own" && continue
        holder="$(hold_holder "$lock")"
      fi
      if hold_ran_out "$lock" "$holder"; then
        hold_take_over "$platform" "$lock" "$holder" && continue
        holder="$(hold_holder "$lock")"
      fi
      held_by="$(hold_named "$holder")"
      if [ "$waited" -ge "$wait" ]; then
        HOLD_SAID="$platform: busy — held by $held_by; waited $waited s (E2E_WAIT)"
        return 75
      fi
      [ $((waited % 60)) -ne 0 ] || echo "── $platform: waiting — held by $held_by" >&2
    fi
    sleep 1
    waited=$((waited + 1))
  done
}

# hold_renew <platform> <lease>: holds it <lease> seconds more from now, only by its holder.
hold_renew() {
  local lock="$HOLD_PLACE/$1.lock"
  hold_is_mine "$lock" || return 1
  jq --argjson lease "$2" '.until = (now | floor) + $lease' "$lock/holder" \
    >"$lock/holder.$$" 2>/dev/null && mv "$lock/holder.$$" "$lock/holder" \
    || { rm -f "$lock/holder.$$"; return 1; }
}
# hold_extend <lock> <lease>: a check's hold, taken again, holds <lease> seconds from now,
# or as long as it held already when that is longer.
hold_extend() {
  jq --argjson lease "$2" '.until = ([(.until // 0), ((now | floor) + $lease)] | max)' \
    "$1/holder" >"$1/holder.$$" 2>/dev/null && mv "$1/holder.$$" "$1/holder" \
    || { rm -f "$1/holder.$$"; return 1; }
}
# hold_group <platform> <pgid>: the process group of the harness, which a taker stops.
hold_group() {
  local lock="$HOLD_PLACE/$1.lock"
  hold_is_mine "$lock" || return 1
  jq -n --argjson group "$2" --arg started "$(process_started "$2")" \
    '{group: $group, group_started: $started}' >"$lock/group.$$" 2>/dev/null \
    && mv "$lock/group.$$" "$lock/group" || { rm -f "$lock/group.$$"; return 1; }
}
# hold_release <platform>: gives the platform back, only by its holder.
hold_release() {
  hold_is_mine "$HOLD_PLACE/$1.lock" || return 1
  rm -rf "$HOLD_PLACE/$1.lock"
}
