#!/bin/sh
[ $# -eq 1 ] || { echo "usage: build-project.sh <project root>  (compiles src/main/kotlin and src/test/kotlin, then runs every test class whose name ends in Test)"; exit 2; }
TOOLS="$(cd "$(dirname "$0")" && pwd)"
[ -n "$SELF_IMPROVE_JARS" ] || [ ! -f "$TOOLS/../env.sh" ] || . "$TOOLS/../env.sh"
JAVA="${SELF_IMPROVE_JAVA:-java}"
ROOT="$1"
OUT="$ROOT/build"
LIB_CP=$(ls "$SELF_IMPROVE_JARS"/libs/*.jar | tr '\n' ':')
rm -rf "${OUT:?}"; mkdir -p "$OUT/main" "$OUT/test"
MAIN=$(find "$ROOT/src/main/kotlin" -name '*.kt' 2>/dev/null)
if [ -z "$MAIN" ]; then echo "BUILD FAILED: no Kotlin files in src/main/kotlin"; exit 1; fi
echo "== compiling src/main/kotlin ($(echo "$MAIN" | wc -l | tr -d ' ') files)"
sh "$TOOLS/kotlinc.sh" "$OUT/main" "" $MAIN || { echo "BUILD FAILED: src/main/kotlin does not compile"; exit 1; }
TESTS=$(find "$ROOT/src/test/kotlin" -name '*.kt' 2>/dev/null)
if [ -z "$TESTS" ]; then echo "BUILD OK: main compiles; there are no tests in src/test/kotlin"; exit 0; fi
echo "== compiling src/test/kotlin ($(echo "$TESTS" | wc -l | tr -d ' ') files)"
sh "$TOOLS/kotlinc.sh" "$OUT/test" "$OUT/main" $TESTS || { echo "BUILD FAILED: src/test/kotlin does not compile"; exit 1; }
CLASSES=$(cd "$OUT/test" && find . -name '*Test.class' | grep -v '\$' | sed 's#^\./##; s#\.class$##; s#/#.#g' | sort)
if [ -z "$CLASSES" ]; then echo "BUILD FAILED: no test class whose name ends in Test"; exit 1; fi
echo "== running tests"
"$JAVA" -cp "$LIB_CP$OUT/main:$OUT/test" tools.runner.TestRunnerKt $CLASSES
STATUS=$?
if [ $STATUS -eq 0 ]; then echo "BUILD OK: all tests pass"; else echo "BUILD FAILED: tests fail"; fi
exit $STATUS
