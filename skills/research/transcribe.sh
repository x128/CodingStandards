#!/bin/bash
# transcribe.sh: a local audio or video file to a text file that research can quote from.
#
# Usage: bash transcribe.sh <local file> <out.md> [--lang auto|ru|en] [--url <source>]
#
# Writes the header of capture.py (url, title, retrieved), then one "[mm:ss] text" line
# per whisper segment. The url is --url (the address the file came from), else
# file:<name>, so no local path lands in a capture. Local files only: getting a file
# from the internet is a download, which fetch-media.sh does after the user's yes.
# Model: $WHISPER_MODEL, else the first ggml-*.bin in ~/models/whisper. A
# ggml-silero-*.bin next to the model turns on voice detection, which stops whisper
# from inventing words in silence.
# Exit codes: 0 ok; 1 failure; 3 no speech found; 4 ffmpeg, whisper-cli or a model missing.

set -uo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODEL_FOLDER="$HOME/models/whisper"

fail() {
  echo "transcribe.sh: $2" >&2
  exit "$1"
}

INPUT="" OUT="" LANGUAGE="auto" SOURCE_URL=""
while [ $# -gt 0 ]; do
  case "$1" in
    --lang) LANGUAGE="${2:-}"; shift 2 || fail 1 "--lang needs a value" ;;
    --url) SOURCE_URL="${2:-}"; shift 2 || fail 1 "--url needs a value" ;;
    -*) fail 1 "unknown option: $1" ;;
    *) if [ -z "$INPUT" ]; then INPUT="$1"; elif [ -z "$OUT" ]; then OUT="$1"
       else fail 1 "unexpected argument: $1"; fi
       shift ;;
  esac
done
[ -n "$INPUT" ] && [ -n "$OUT" ] \
  || fail 1 "usage: transcribe.sh <local file> <out.md> [--lang auto|ru|en] [--url <source>]"
case "$INPUT" in
  *://*) fail 1 "local files only: downloading $INPUT needs the user's yes, then fetch-media.sh" ;;
esac
[ -f "$INPUT" ] || fail 1 "no such file: $INPUT"
command -v ffmpeg >/dev/null || fail 4 "ffmpeg is not installed (brew install ffmpeg)"
command -v whisper-cli >/dev/null \
  || fail 4 "whisper-cli is not installed (brew install whisper-cpp)"

MODEL="${WHISPER_MODEL:-}"
if [ -z "$MODEL" ]; then
  for candidate in "$MODEL_FOLDER"/ggml-*.bin; do
    case "$candidate" in *ggml-silero*) continue ;; esac
    [ -f "$candidate" ] && { MODEL="$candidate"; break; }
  done
fi
[ -f "$MODEL" ] \
  || fail 4 "no whisper model: set WHISPER_MODEL or put a ggml-*.bin into $MODEL_FOLDER"
VAD_ARGUMENTS=()
for candidate in "$(dirname "$MODEL")"/ggml-silero*.bin; do
  [ -f "$candidate" ] && { VAD_ARGUMENTS=(--vad --vad-model "$candidate"); break; }
done

WORK="$(mktemp -d)" || fail 1 "cannot create a temporary folder"
trap 'rm -rf "$WORK"' EXIT

ffmpeg -nostdin -v error -y -i "$INPUT" -vn -ar 16000 -ac 1 -c:a pcm_s16le "$WORK/audio.wav" \
  2>"$WORK/ffmpeg.log" \
  || fail 1 "ffmpeg cannot read the audio: $(tail -1 "$WORK/ffmpeg.log")"
whisper-cli -m "$MODEL" -l "$LANGUAGE" ${VAD_ARGUMENTS[@]+"${VAD_ARGUMENTS[@]}"} -np -osrt \
  -of "$WORK/transcript" -f "$WORK/audio.wav" >"$WORK/whisper.log" 2>&1 \
  || fail 1 "whisper-cli failed: $(tail -1 "$WORK/whisper.log")"

# An SRT block is a number, "hh:mm:ss,mmm --> ...", then text lines; minutes are not wrapped at 60.
awk '
  / --> / {
    split($1, t, /[:,]/); stamp = sprintf("[%02d:%02d]", t[1] * 60 + t[2], t[3]); text = ""; next
  }
  /^[0-9]+$/ && stamp == "" { next }
  NF { text = text (text == "" ? "" : " ") $0; next }
  stamp != "" && text != "" { print stamp " " text }
  { stamp = ""; text = "" }
  END { if (stamp != "" && text != "") print stamp " " text }
' "$WORK/transcript.srt" | sed -e 's/  */ /g' -e 's/ $//' >"$WORK/body.txt"
[ -s "$WORK/body.txt" ] || fail 3 "whisper found no speech in $INPUT"

if [ -n "$SOURCE_URL" ]; then
  URL="$(python3 -I -c 'import sys; sys.path.insert(0, sys.argv[1]); import capture
print(capture.redacted_url(sys.argv[2]))' "$SKILL_DIR" "$SOURCE_URL")" \
    || fail 1 "cannot read --url $SOURCE_URL"
else
  URL="file:$(basename "$INPUT")"
fi
mkdir -p "$(dirname "$OUT")" || fail 1 "cannot create the folder of $OUT"
{
  printf -- '---\nurl: %s\ntitle: %s\nretrieved: %s\n---\n' \
    "$URL" "$(basename "$INPUT")" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  cat "$WORK/body.txt"
} >"$OUT" || fail 1 "cannot write $OUT"
echo "ok: $OUT, $(wc -l <"$WORK/body.txt" | tr -d ' ') lines, model $(basename "$MODEL")"
