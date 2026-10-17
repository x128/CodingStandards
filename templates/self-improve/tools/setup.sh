#!/bin/sh
[ $# -eq 1 ] || { echo "usage: setup.sh <work folder>  (checks the jars listed in jars.txt under <work folder>/jars, builds the platform library and the test runner, writes <work folder>/env.sh)"; exit 2; }
TOOLS="$(cd "$(dirname "$0")" && pwd)"
PLATFORM="$(cd "$TOOLS/../platform" && pwd)"
WORK="$(mkdir -p "$1" && cd "$1" && pwd)"
JARS="$WORK/jars"
JAVA="${SELF_IMPROVE_JAVA:-java}"
mkdir -p "$JARS/compiler" "$JARS/libs" "$JARS/jacoco"
MISSING=0
while read -r folder name size url; do
  file="$JARS/$folder/$name"
  if [ ! -f "$file" ]; then echo "MISSING $folder/$name ($size bytes) from $url"; MISSING=1
  elif [ "$(wc -c < "$file" | tr -d ' ')" != "$size" ]; then echo "WRONG SIZE $folder/$name: expected $size bytes, has $(wc -c < "$file" | tr -d ' ')"; MISSING=1; fi
done < "$TOOLS/jars.txt"
if [ $MISSING -ne 0 ]; then echo "SETUP STOPPED: ask the human before downloading; download each file into a new empty folder, compare its SHA-1 with the .sha1 file next to it on Maven Central, then move it to the folder named above"; exit 1; fi
"$JAVA" -version 2>&1 | head -1
export SELF_IMPROVE_JARS="$JARS" SELF_IMPROVE_JAVA="$JAVA"
rm -f "${JARS:?}/libs/platform-lib.jar" "${JARS:?}/libs/test-runner.jar"
sh "$TOOLS/kotlinc.sh" "$JARS/libs/platform-lib.jar" "" $(find "$PLATFORM/lib" -name '*.kt') || { echo "SETUP FAILED: the platform library does not compile"; exit 1; }
sh "$TOOLS/kotlinc.sh" "$JARS/libs/test-runner.jar" "" "$PLATFORM/runner/TestRunner.kt" || { echo "SETUP FAILED: the test runner does not compile"; exit 1; }
rm -rf "${WORK:?}/tools"; mkdir -p "$WORK/tools"; cp "$TOOLS"/*.sh "$TOOLS"/*.py "$TOOLS"/jars.txt "$WORK/tools/"
printf 'export SELF_IMPROVE_WORK="%s"\nexport SELF_IMPROVE_JARS="%s"\nexport SELF_IMPROVE_JAVA="%s"\nexport SELF_IMPROVE_TOOLS="%s"\n' "$WORK" "$JARS" "$JAVA" "$WORK/tools" > "$WORK/env.sh"
echo "SETUP OK: $WORK/env.sh"
