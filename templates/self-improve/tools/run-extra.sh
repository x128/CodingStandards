#!/bin/sh
[ $# -eq 2 ] || { echo "usage: run-extra.sh <project root> <folder of extra Kotlin test files>  (builds the project, compiles the extra files against it, runs their classes whose name ends in Test)"; exit 2; }
TOOLS="$(cd "$(dirname "$0")" && pwd)"
[ -n "$SELF_IMPROVE_JARS" ] || [ ! -f "$TOOLS/../env.sh" ] || . "$TOOLS/../env.sh"
JAVA="${SELF_IMPROVE_JAVA:-java}"
ROOT="$1"; EXTRA="$2"
LIB_CP=$(ls "$SELF_IMPROVE_JARS"/libs/*.jar | tr '\n' ':')
OUT="$ROOT/build"
rm -rf "${OUT:?}/main" "${OUT:?}/extra"; mkdir -p "$OUT/main" "$OUT/extra"
sh "$TOOLS/kotlinc.sh" "$OUT/main" "" $(find "$ROOT/src/main/kotlin" -name '*.kt') || { echo "FAILED: src/main/kotlin does not compile"; exit 1; }
sh "$TOOLS/kotlinc.sh" "$OUT/extra" "$OUT/main" $(find "$EXTRA" -name '*.kt') || { echo "FAILED: the extra files do not compile"; exit 1; }
CLASSES=$(cd "$OUT/extra" && find . -name '*Test.class' | grep -v '\$' | sed 's#^\./##; s#\.class$##; s#/#.#g' | sort)
"$JAVA" -cp "$LIB_CP$OUT/main:$OUT/extra" tools.runner.TestRunnerKt $CLASSES
