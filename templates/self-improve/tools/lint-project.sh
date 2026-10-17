#!/bin/sh
[ $# -eq 1 ] || { echo "usage: lint-project.sh <project root>  (fails on a comment in src that comment-allowed.txt does not allow, and on a function whose CRAP score is above 8 unless crap-exceptions.txt names it as Class.function)"; exit 2; }
TOOLS="$(cd "$(dirname "$0")" && pwd)"
[ -n "$SELF_IMPROVE_JARS" ] || [ ! -f "$TOOLS/../env.sh" ] || . "$TOOLS/../env.sh"
JAVA="${SELF_IMPROVE_JAVA:-java}"
ROOT="$1"
OUT="$ROOT/build/lint"
LIB_CP=$(ls "$SELF_IMPROVE_JARS"/libs/*.jar | tr '\n' ':')
STATUS=0
echo "== comments"
FOUND=$(grep -rnE --include='*.kt' '(^|[[:space:]])(//|/[*])' "$ROOT/src" | grep -viE '// (arrange|act|assert|given|when|then)$' | sed "s#$ROOT/##")
if [ -f "$ROOT/comment-allowed.txt" ] && [ -n "$FOUND" ]; then FOUND=$(echo "$FOUND" | grep -v -f "$ROOT/comment-allowed.txt"); fi
if [ -n "$FOUND" ]; then echo "$FOUND" | head -40; echo "COMMENTS: $(echo "$FOUND" | wc -l | tr -d ' ') comment lines (CLEAN_CODE.md, Comments)"; STATUS=1; else echo "COMMENTS: none"; fi
echo "== CRAP"
rm -rf "${OUT:?}"; mkdir -p "$OUT/main" "$OUT/test"
sh "$TOOLS/kotlinc.sh" "$OUT/main" "" $(find "$ROOT/src/main/kotlin" -name '*.kt') > "$OUT/compile.log" 2>&1 || { tail -20 "$OUT/compile.log"; echo "LINT FAILED: src/main/kotlin does not compile"; exit 1; }
sh "$TOOLS/kotlinc.sh" "$OUT/test" "$OUT/main" $(find "$ROOT/src/test/kotlin" -name '*.kt') >> "$OUT/compile.log" 2>&1 || { tail -20 "$OUT/compile.log"; echo "LINT FAILED: src/test/kotlin does not compile"; exit 1; }
CLASSES=$(cd "$OUT/test" && find . -name '*Test.class' | grep -v '\$' | sed 's#^\./##; s#\.class$##; s#/#.#g' | sort)
"$JAVA" -javaagent:"$SELF_IMPROVE_JARS/jacoco/agent.jar=destfile=$OUT/jacoco.exec" -cp "$LIB_CP$OUT/main:$OUT/test" tools.runner.TestRunnerKt $CLASSES > "$OUT/tests.log" 2>&1 || { tail -20 "$OUT/tests.log"; echo "LINT FAILED: tests fail"; exit 1; }
"$JAVA" -jar "$SELF_IMPROVE_JARS/jacoco/cli.jar" report "$OUT/jacoco.exec" --classfiles "$OUT/main" --sourcefiles "$ROOT/src/main/kotlin" --xml "$OUT/jacoco.xml" > "$OUT/report.log" 2>&1 || { tail -5 "$OUT/report.log"; echo "LINT FAILED: no coverage report"; exit 1; }
python3 -I "$TOOLS/crap.py" "$OUT/jacoco.xml" 8 "$ROOT/crap-exceptions.txt" || STATUS=1
if [ $STATUS -eq 0 ]; then echo "LINT OK"; else echo "LINT FAILED"; fi
exit $STATUS
