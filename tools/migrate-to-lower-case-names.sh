#!/usr/bin/env bash
#
# migrate-to-lower-case-names.sh — brings a project that was set up before the standards took
# lower-case file names up to date. It renames .review/REVIEW_POLICY.md to review-policy.md and
# points the project's references to the standards at their new names:
# - in the copies of the templates (.review/, .claude/agents/), every old name: there each one is
#   the name of a standard;
# - in CLAUDE.md and AGENTS.md, only a name written through the submodule
#   (CodingStandards/TESTING.md), because a project may have its own ARCHITECTURE.md.
# It changes files and nothing in git: read the diff, then commit it.
#
# Usage, from the project root: CodingStandards/tools/migrate-to-lower-case-names.sh

set -euo pipefail

old_policy=.review/REVIEW_POLICY.md
new_policy=.review/review-policy.md
if [ -f "$old_policy" ] && [ -f "$new_policy" ]; then
  echo "both $old_policy and $new_policy exist: move the rules of the old one into the new one," >&2
  echo "delete the old one, then run this again" >&2
  exit 1
fi
if [ -f "$old_policy" ]; then
  mv "$old_policy" "$new_policy"
  echo "renamed $old_policy to $new_policy"
fi

names="REVIEW_POLICY:review-policy TASK_LOOP:task-loop PLANNING_GUIDE:planning-guide
EXECUTION_GUIDE:execution-guide MAINTAINER_TRAINING:maintainer-training CLEAN_CODE:clean-code
KOTLIN_MULTIPLATFORM:kotlin-multiplatform ARCHITECTURE:architecture KOTLIN:kotlin SWIFT:swift
TESTING:testing"

in_copies=""
in_own_files="s{\\.review/REVIEW_POLICY\\.md}{.review/review-policy.md}g;"
for pair in $names; do
  old="${pair%%:*}"
  new="${pair##*:}"
  in_copies="${in_copies}s{(?<![A-Za-z0-9_-])${old}\\.md(?![A-Za-z0-9_])}{${new}.md}g;"
  in_own_files="${in_own_files}s{(?<=CodingStandards/)${old}\\.md(?![A-Za-z0-9_])}{${new}.md}g;"
done

rewrite() {
  local program="$1" file="$2" before
  before="$(cksum <"$file")"
  perl -pi -e "$program" "$file"
  [ "$(cksum <"$file")" = "$before" ] || echo "updated $file"
}

for file in .review/*.sh .review/*.conf .review/*.md .review/prompts/*.md \
            .claude/agents/*.md .claude/agents.conf; do
  if [ -f "$file" ]; then rewrite "$in_copies" "$file"; fi
done
for file in CLAUDE.md AGENTS.md; do
  if [ -f "$file" ]; then rewrite "$in_own_files" "$file"; fi
done
echo "done: read git diff, then commit"
