#!/usr/bin/env bash
#
# device.sh — the hold on a platform for a check that drives a device by hand: /qa, the
# executor. It is the hold the end-to-end tests take (e2e-gate.sh; common.sh, "The hold on
# a platform"), so a check never boots, drives, erases or switches off a device while a run
# of the tests, or a check of another copy of the project, is on its platform, and no run
# uses the platform under the check.
#
# A check holds a platform for this copy of the project, for some minutes. The hold runs
# out by itself, so a session that ends without a release frees the platform; the check
# takes the platform again to keep it. A run of the end-to-end tests in the same copy takes
# the hold over at once: it is the same loop, a step further.
#
# Runs FROM THE SUBMODULE, like e2e-gate.sh: the hold is the same for every copy of every
# project on the machine.
#
# Usage, from the project root:
#   device.sh take <platform>... [--minutes <n>]
#       waits, up to E2E_WAIT seconds, while another holds a platform, then holds each for
#       this copy for <n> minutes (30). Taken again, the hold is made longer. Several
#       platforms are taken in one order, android before ios; a take that cannot hold
#       them all gives back again those it took.
#   device.sh off <platform> android <serial> | ios <udid>
#       switches that device off now (adb -s <serial> emu kill, xcrun simctl shutdown
#       <udid>), only while a check of this copy holds the platform.
#   device.sh release <platform>...
#       gives the platform back.
#   device.sh status
#       one line for each platform that is held: who, of which copy, since when, until when.
# With E2E_LOCK=off in .review/land.conf each copy has devices of its own: nothing is
# held, and off asks no hold.
#
# Exit codes:
#   0  done
#   75 take: a platform is still held by another after E2E_WAIT
#   1  the hold cannot be made; off or release: no check of this copy holds the platform,
#      and nothing is switched off or given back; a device that was not switched off;
#      usage or environment error
#
# Requires: jq >= 1.6, git; adb or xcrun for off

set -uo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 1
# shellcheck source=common.sh
. "$LIB_DIR/common.sh"

usage() {
  echo "usage: device.sh take <platform>... [--minutes <n>] | off <platform> android <serial>"\
" | off <platform> ios <udid> | release <platform>... | status" >&2
  exit 1
}

COMMAND="${1:-}"
[ $# -eq 0 ] || shift
case "$COMMAND" in
  take|off|release|status) ;;
  *) usage ;;
esac

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "device.sh: $(pwd) is not inside a git repository, so no copy of a project holds here" >&2
  exit 1
}
cd "$PROJECT_ROOT" || exit 1
CONF=".review/land.conf"
E2E_LOCK="$(hold_lock_setting "$CONF")" || exit 1
HOLD_PLACE="$(device_lock_dir "$CONF")"
WHO="a check by hand"

# The platforms named, android before ios, each once; sets PLATFORMS.
platforms_named() {
  local platform named=" "
  for platform in "$@"; do
    case "$platform" in
      android|ios) named="$named$platform " ;;
      *) echo "device.sh holds android and ios, not '$platform'" >&2; exit 1 ;;
    esac
  done
  PLATFORMS=""
  for platform in android ios; do
    case "$named" in *" $platform "*) PLATFORMS="$PLATFORMS $platform" ;; esac
  done
  PLATFORMS="${PLATFORMS# }"
  [ -n "$PLATFORMS" ] || usage
}

lock_of() { printf '%s/%s.lock' "$HOLD_PLACE" "$1"; }

# Until when the hold on <platform> holds, as a time.
held_until() {
  jq -r 'if (.until | type) == "number" then .until | floor | todate else "?" end' \
    "$(lock_of "$1")/holder" 2>/dev/null
}

# Whether a check of this copy holds <platform>, and its lease has not run out.
held_here() {
  local holder
  holder="$(hold_holder "$(lock_of "$1")")"
  hold_is_this_copys_check "$holder" && \
    json_holds --argjson now "$(date +%s)" '(.until // 0) >= $now' <<<"$holder"
}

# Gives <platform> back when a check of this copy holds it; 1 when another holds it.
give_back() {
  local lock holder
  lock="$(lock_of "$1")"
  [ -d "$lock" ] || { echo "── $1: was not held"; return 0; }
  holder="$(hold_holder "$lock")"
  if hold_is_this_copys_check "$holder"; then
    rm -rf "$lock" && echo "── $1: given back"
    return
  fi
  echo "$1 is held by $(hold_named "$holder"), not by a check of this copy: nothing is given"\
" back" >&2
  return 1
}

if [ "$COMMAND" = status ]; then
  [ $# -eq 0 ] || usage
  if [ "$E2E_LOCK" = off ]; then
    echo "── E2E_LOCK=off in $CONF: each copy has devices of its own, and nothing is held"
    exit 0
  fi
  any=""
  for lock in "$HOLD_PLACE"/*.lock; do
    [ -d "$lock" ] || continue
    platform="$(basename "$lock" .lock)"
    holder="$(hold_holder "$lock")"
    line="$platform: held by $(hold_named "$holder")"
    [ -z "$holder" ] || line="$line, until $(held_until "$platform")"
    if [ -n "$holder" ] && \
       json_holds --argjson now "$(date +%s)" '(.until // 0) < $now' <<<"$holder"; then
      line="$line — its lease has run out"
    fi
    echo "$line"
    any=yes
  done
  [ -n "$any" ] || echo "no platform is held (at $HOLD_PLACE)"
  exit 0
fi

if [ "$COMMAND" = off ]; then
  [ $# -eq 3 ] || usage
  platform="$1" device="$2" id="$3"
  platforms_named "$platform"
  [ "$device" = "$platform" ] || {
    echo "device.sh off $platform switches off a device of $platform: $platform <id>, not"\
" '$device'" >&2
    exit 1
  }
  if [ "$E2E_LOCK" = platform ] && ! held_here "$platform"; then
    holder="$(hold_holder "$(lock_of "$platform")")"
    if [ -d "$(lock_of "$platform")" ] && ! hold_is_this_copys_check "$holder"; then
      echo "$platform is held by $(hold_named "$holder"): nothing is switched off" >&2
    elif [ -n "$holder" ]; then
      echo "$platform: the hold of this copy ran out at $(held_until "$platform"): nothing is"\
" switched off" >&2
    else
      echo "$platform is not held by this copy: nothing is switched off" >&2
    fi
    turn loop "take the platform first: device.sh take $platform waits while a run or a check"\
" of another copy is on it"
    exit 1
  fi
  case "$device" in
    android) tool=adb ;;
    ios)     tool=xcrun ;;
  esac
  command -v "$tool" >/dev/null 2>&1 || {
    echo "$tool is not on PATH: $id is not switched off" >&2
    exit 1
  }
  case "$device" in
    android) adb -s "$id" emu kill ;;
    ios)     xcrun simctl shutdown "$id" ;;
  esac
  code=$?
  [ "$code" -eq 0 ] || { echo "$platform: $id was not switched off: $tool exited $code" >&2; exit 1; }
  echo "── $platform: switched off $id"
  exit 0
fi

MINUTES=30
named=""
while [ $# -gt 0 ]; do
  case "$1" in
    --minutes) [ "$COMMAND" = take ] || usage
               require_value --minutes $#
               MINUTES="$2"; shift 2 ;;
    -*)        usage ;;
    *)         named="$named $1"; shift ;;
  esac
done
# shellcheck disable=SC2086 # the platforms are words of the command line, and each is checked
platforms_named $named
case "$MINUTES" in
  ''|*[!0-9]*|0|??????*)
    echo "--minutes must be a whole number of minutes from 1, not '$MINUTES'" >&2
    exit 1 ;;
esac

if [ "$E2E_LOCK" = off ]; then
  echo "── E2E_LOCK=off in $CONF: each copy has devices of its own, and nothing is held"
  exit 0
fi

if [ "$COMMAND" = release ]; then
  refused=""
  for platform in $PLATFORMS; do
    give_back "$platform" || refused=yes
  done
  [ -z "$refused" ] || {
    turn loop "go on: this copy holds it no more — its hold ran out, or a run of this copy"\
" took it over"
    exit 1
  }
  exit 0
fi

E2E_WAIT="$(hold_seconds "$CONF" E2E_WAIT 1800)" || exit 1
taken=""
for platform in $PLATFORMS; do
  held_before=no
  hold_is_this_copys_check "$(hold_holder "$(lock_of "$platform")")" && held_before=yes
  hold_take "$platform" "$WHO" agent $((MINUTES * 60)) "$E2E_WAIT"
  code=$?
  if [ "$code" -ne 0 ]; then
    echo "$HOLD_SAID" >&2
    for given in $taken; do
      give_back "$given" >/dev/null && echo "── $given: given back again, since $platform is not held" >&2
    done
    if [ "$code" -eq 75 ]; then
      turn loop "take it again later: device.sh status says who holds it"
    else
      turn user:only-theirs "let the runs meet somewhere they can write: DEVICE_LOCK_DIR in "\
"$CONF, the same folder in every copy of the project, or E2E_LOCK=off where each copy has "\
"devices of its own — an edit of that file is theirs"
    fi
    exit "$code"
  fi
  [ "$held_before" = yes ] || taken="$taken $platform"
  echo "── $platform: held for this copy of the project until $(held_until "$platform")"\
" (device.sh release $platform gives it back)"
done
exit 0
