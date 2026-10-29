#!/bin/sh
[ $# -eq 3 ] || { echo "usage: refresh-standards.sh <work folder> <standards folder> <project folder>  (puts a fresh copy of the standards into the project, without what belongs to the evaluation, and writes its build.sh and lint.sh)"; exit 2; }
WORK="$(cd "$1" && pwd)"; STANDARDS="$2"; PROJECT="$3"
[ -f "$WORK/env.sh" ] || { echo "no $WORK/env.sh: run setup.sh first"; exit 1; }
[ -d "$PROJECT" ] || { echo "no project folder $PROJECT"; exit 1; }
. "$WORK/env.sh"
COPY="$PROJECT/CodingStandards"
rm -rf "${COPY:?}"; mkdir -p "$COPY"
rsync -a --exclude .git --exclude templates/self-improve --exclude skills/self-improve "$STANDARDS/" "$COPY/"
for index in $(cd "$COPY" && grep -rl -e 'self-improve' --include='*.md' .); do
  grep -v -e 'self-improve' "$COPY/$index" > "$COPY/$index.kept" && mv "$COPY/$index.kept" "$COPY/$index"
done
sed '/^## Self-improve$/,$d' "$COPY/templates/README.md" > "$COPY/templates/README.md.kept" && mv "$COPY/templates/README.md.kept" "$COPY/templates/README.md"
LEFT=$(grep -rln -e 'self-improve' "$COPY")
[ -z "$LEFT" ] || { echo "REFRESH FAILED: the copy of the standards still names the evaluation in: $LEFT"; exit 1; }
for script in build lint; do
  printf '#!/bin/sh\nexport SELF_IMPROVE_JARS="%s" SELF_IMPROVE_JAVA="%s"\nexec sh "%s/%s-project.sh" "$(cd "$(dirname "$0")" && pwd)"\n' "$SELF_IMPROVE_JARS" "$SELF_IMPROVE_JAVA" "$SELF_IMPROVE_TOOLS" "$script" > "$PROJECT/$script.sh"
done
chmod +x "$PROJECT/build.sh" "$PROJECT/lint.sh"
echo "STANDARDS REFRESHED: $PROJECT"
