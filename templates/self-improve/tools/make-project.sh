#!/bin/sh
[ $# -eq 4 ] || { echo "usage: make-project.sh <work folder> <spec folder with REQUIREMENTS.md, docs/ and CLAUDE.md> <standards folder> <new project folder>  (the copy of the standards leaves out everything that belongs to the evaluation)"; exit 2; }
WORK="$1"; SPEC="$2"; STANDARDS="$3"; PROJECT="$4"
[ ! -e "$PROJECT" ] || { echo "$PROJECT exists already; choose a new folder"; exit 1; }
mkdir -p "$PROJECT/src/main/kotlin" "$PROJECT/src/test/kotlin"
cp "$SPEC/REQUIREMENTS.md" "$SPEC/CLAUDE.md" "$PROJECT/"
cp -R "$SPEC/docs" "$PROJECT/docs"
sh "$(cd "$(dirname "$0")" && pwd)/refresh-standards.sh" "$WORK" "$STANDARDS" "$PROJECT" > /dev/null || exit 1
echo "PROJECT READY: $PROJECT"
