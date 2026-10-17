#!/bin/sh
[ $# -ge 3 ] || { echo "usage: kotlinc.sh <output dir> <extra classpath or \"\"> <source files...>"; exit 2; }
TOOLS="$(cd "$(dirname "$0")" && pwd)"
[ -n "$SELF_IMPROVE_JARS" ] || [ ! -f "$TOOLS/../env.sh" ] || . "$TOOLS/../env.sh"
[ -n "$SELF_IMPROVE_JARS" ] || { echo "SELF_IMPROVE_JARS is not set: run setup.sh and use the build.sh that make-project.sh writes"; exit 2; }
JAVA="${SELF_IMPROVE_JAVA:-java}"
OUT="$1"; EXTRA="$2"; shift 2
COMPILER_CP=$(ls "$SELF_IMPROVE_JARS"/compiler/*.jar | tr '\n' ':')
LIB_CP=$(ls "$SELF_IMPROVE_JARS"/libs/*.jar | tr '\n' ':')
exec "$JAVA" -Xmx2g -cp "$COMPILER_CP" org.jetbrains.kotlin.cli.jvm.K2JVMCompiler -no-stdlib -no-reflect -jvm-target 17 -opt-in=kotlin.RequiresOptIn -opt-in=kotlinx.coroutines.ExperimentalCoroutinesApi -cp "$LIB_CP$EXTRA" -d "$OUT" "$@"
