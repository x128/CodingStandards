#!/bin/bash
# fetch-media.sh: downloads the audio of one video or podcast episode, for transcribe.sh.
#
# Usage: bash fetch-media.sh <url> <folder> [--max-size 500M]
#
# It downloads, so it runs only after the user said yes to this file, its source and its
# size. yt-dlp takes the best audio-only stream of one item (never a playlist, never
# video), up to --max-size (default 500M), into <folder> as <id>.<ext>, and the script
# prints the file's path. Keep the folder out of the project: media is never committed.
# Exit codes: 0 ok; 1 failure (too large, no audio, no such item); 2 blocked (401, 403,
# 429, a sign-in or bot check); 4 yt-dlp missing.

set -uo pipefail

fail() {
  echo "fetch-media.sh: $2" >&2
  exit "$1"
}

URL="${1:-}" FOLDER="${2:-}" MAX_SIZE="500M"
[ "${3:-}" = "--max-size" ] && MAX_SIZE="${4:-}"
[ -n "$URL" ] && [ -n "$FOLDER" ] && [ -n "$MAX_SIZE" ] \
  || fail 1 "usage: fetch-media.sh <url> <folder> [--max-size 500M]"
case "$URL" in
  http://*|https://*) ;;
  *) fail 1 "the URL must start with http:// or https://" ;;
esac
command -v yt-dlp >/dev/null \
  || fail 4 "yt-dlp is not installed (brew install yt-dlp); or the user downloads the file"

mkdir -p "$FOLDER" || fail 1 "cannot create $FOLDER"
LOG="$(mktemp)" || fail 1 "cannot create a log file"
trap 'rm -f "$LOG"' EXIT

FILE="$(yt-dlp --no-playlist --no-simulate --restrict-filenames -f bestaudio \
  --max-filesize "$MAX_SIZE" --print after_move:filepath \
  -o "$FOLDER/%(id)s.%(ext)s" -- "$URL" 2>"$LOG" | tail -1)"
if [ -z "$FILE" ] || [ ! -f "$FILE" ]; then
  REASON="$(grep -E 'ERROR|larger than max-filesize' "$LOG" | tail -1)"
  if grep -qiE 'HTTP Error (401|403|429)|not a bot|sign in to confirm|login required' "$LOG"; then
    fail 2 "refused: $REASON"
  fi
  fail 1 "no audio file: ${REASON:-$(tail -1 "$LOG")}"
fi
echo "$FILE"
