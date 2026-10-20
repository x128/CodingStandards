#!/usr/bin/env python3
"""capture.py: one URL to one text file that research can quote from.

Usage:
    python3 capture.py <url> <out.md> [--kind auto|html|pdf|youtube|text] [--lang ru,en]

Writes <out.md>: a header (url, title, retrieved) between --- lines, then the text.
  html     readable text; headings as #, list items as -, table cells joined by |
  pdf      text under [page N] markers (needs pypdf)
  youtube  the caption track as [mm:ss] lines; --lang picks the track, else the spoken one
  text     the body as it came: JSON APIs, RSS and Atom feeds, plain text

Prints one JSON line: {"status", "http", "out", "chars", "title"}, plus "reason" when not ok.
Exit codes: 0 ok; 2 blocked (401, 403, 429 or a challenge page; never worked around);
3 nothing readable; 4 a dependency missing (pypdf); 1 any other failure, including an
audio or video URL, which is refused unread because downloading it is the user's call.
"""

import argparse
import html
import io
import json
import os
import re
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ElementTree
from datetime import datetime, timezone
from html.parser import HTMLParser

KINDS = ("auto", "html", "pdf", "youtube", "text")
USER_AGENT = "research-skill/1"
TIMEOUT_SECONDS = 30
MAX_BODY_BYTES = 100 * 1024 * 1024
# Agents capture from one host one after another; arXiv asks for 3 s between requests.
PAUSE_SECONDS = {"arxiv.org": 3.0, "reddit.com": 5.0}
DEFAULT_PAUSE_SECONDS = 1.0
PACE_FOLDER = os.path.join(tempfile.gettempdir(), "capture-py-pace")

OK, FAILED, BLOCKED, NOTHING_READABLE, MISSING_DEPENDENCY = 0, 1, 2, 3, 4
STATUS = ("ok", "failed", "blocked", "empty", "failed")  # by exit code
BLOCKED_CODES = {401, 403, 429}
MEDIA_TYPES = ("audio/", "video/", "application/ogg")
HTML_TYPES = ("text/html", "application/xhtml+xml")
# Challenge pages are small: looking only at small pages keeps an article about bots readable.
CHALLENGE_PAGE_MAX_BYTES = 64 * 1024
CHALLENGE_MARKERS = (
    "<title>just a moment...</title>", "window._cf_chl_opt", "attention required! | cloudflare",
    "/.within.website/x/cmd/anubis/", "making sure you're not a bot", "challengerequirederror",
    "captcha-delivery.com", 'id="px-captcha"', "detected unusual traffic from your computer",
    "<title>client challenge</title>",
)
JAVASCRIPT_NOTICE = re.compile(r"\b(enable|turn on|requires?|need)\b.{0,40}\bjavascript\b"
                               r"|\bjavascript\b.{0,40}\b(required|disabled|needed)\b", re.I)

YOUTUBE_HOST = re.compile(r"(www\.|m\.)?(youtube\.com|youtube-nocookie\.com|youtu\.be)")
YOUTUBE_ID = re.compile(r"(?:[?&]v=|youtu\.be/|/shorts/|/live/|/embed/)([\w-]{11})(?![\w-])")
YOUTUBE_PLAYER = "https://www.youtube.com/youtubei/v1/player"
# The web client's caption URLs come back empty without a proof-of-origin token; the
# ANDROID client's do not. The interface is undocumented and may close.
YOUTUBE_CLIENT = {"clientName": "ANDROID", "clientVersion": "20.10.38"}
AUTO_CAPTIONS = "asr"

DROPPED_TAGS = set("script style noscript template svg nav footer iframe object canvas select "
                   "button dialog title".split())
VOID_TAGS = set("area base br col embed hr img input link meta param source track wbr".split())
BLOCK_TAGS = set("address article aside blockquote br caption dd details div dl dt figcaption "
                 "figure header hr li main ol p pre section summary table tr ul h1 h2 h3 h4 h5 h6"
                 .split())
# A word of a parameter name (split at punctuation and camelCase) that contains a part or ends
# with an ending is secret: api_key, apiKey, X-Amz-Signature, oauth; keyword and author are not.
SECRET_PARTS = ("token", "secret", "signature", "credential", "password", "mailto", "email",
                "authoriz", "authentic")
SECRET_ENDINGS = ("key", "sig", "auth")
NAME_WORDS = re.compile(r"[A-Z]?[a-z0-9]+|[A-Z]+(?![a-z])")


class Failure(Exception):
    def __init__(self, reason, http=None, exit_code=FAILED):
        super().__init__(reason)
        self.reason, self.http, self.exit_code = reason, http, exit_code


def host_of(url):
    return (urllib.parse.urlsplit(url).hostname or "").lower()


def one_line(value):
    return re.sub(r"\s+", " ", str(value or "")).strip()


def pause_before_request(host):
    """The time of the last request to a host is the modification time of its file."""
    domain = next((d for d in PAUSE_SECONDS if host == d or host.endswith("." + d)), host)
    interval = PAUSE_SECONDS.get(domain, DEFAULT_PAUSE_SECONDS)
    marker = os.path.join(PACE_FOLDER, domain)
    try:
        if os.path.exists(marker):
            since_last = time.time() - os.path.getmtime(marker)
            time.sleep(min(interval, max(0.0, interval - since_last)))
        os.makedirs(PACE_FOLDER, exist_ok=True)
        with open(marker, "a"):
            os.utime(marker)
    except OSError:
        pass


def fetch(url, data=None, headers=None, kind="auto"):
    """Returns (http code, final url, content type, body); refusals and challenges raise."""
    pause_before_request(host_of(url))
    request = urllib.request.Request(url, data=data, headers={
        "User-Agent": USER_AGENT, **(headers or {})})
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as reply:
            code, final_url, reply_headers = reply.status, reply.geturl(), reply.headers
            content_type = reply_headers.get_content_type()
            if content_type.startswith(MEDIA_TYPES):
                raise Failure(f"{content_type} is a download, not a page: ask the user first", code)
            body = reply.read(MAX_BODY_BYTES + 1)
    except urllib.error.HTTPError as error:
        code, final_url, reply_headers = error.code, error.geturl() or url, error.headers
        content_type = reply_headers.get_content_type() if reply_headers else ""
        body = error.read(CHALLENGE_PAGE_MAX_BYTES)
    except (urllib.error.URLError, OSError) as error:
        raise Failure(f"cannot reach {host_of(url)}: {error}") from error
    if len(body) > MAX_BODY_BYTES:
        raise Failure(f"the body is over {MAX_BODY_BYTES >> 20} MB: ask the user first", code)
    host = host_of(final_url)
    if is_challenge(code, content_type, body, kind):
        raise Failure(f"challenge page from {host}", code, BLOCKED)
    if code >= 400:
        exit_code = BLOCKED if code in BLOCKED_CODES else FAILED
        raise Failure(f"HTTP {code} from {host}", code, exit_code)
    return code, final_url, content_type, body


def is_challenge(code, content_type, body, kind):
    if content_type.endswith(("json", "xml")):
        return False
    small_page = len(body) <= CHALLENGE_PAGE_MAX_BYTES and content_type in HTML_TYPES
    if code < 400 and not (small_page and kind != "text"):
        return False
    page = body[:CHALLENGE_PAGE_MAX_BYTES].decode("utf-8", "replace").lower().replace("&#39;", "'")
    return any(marker in page for marker in CHALLENGE_MARKERS)


class ReadableText(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.lines, self.inline, self.prefix, self.dropped = [], [], "", []
        self.in_math, self.first_heading = False, ""

    def handle_starttag(self, tag, attrs):
        attributes = dict(attrs)
        if self.in_math:
            return
        if self.dropped or tag in DROPPED_TAGS or attributes.get("role") == "navigation":
            if tag not in VOID_TAGS:
                self.dropped.append(tag)
        elif tag == "math" and attributes.get("alttext"):
            # arXiv HTML keeps the LaTeX of each formula in alttext.
            self.in_math = True
            self.inline.append(f" {attributes['alttext']} ")
        else:
            row_so_far = "".join(self.inline).strip()
            if tag in ("td", "th") and row_so_far and not row_so_far.endswith("|"):
                self.inline.append(" | ")
            if tag in BLOCK_TAGS:
                self.end_block()
            if re.fullmatch(r"h[1-6]", tag):
                self.prefix = "#" * int(tag[1]) + " "
            elif tag == "li":
                self.prefix = "- "

    def handle_endtag(self, tag):
        if self.dropped:
            if tag in self.dropped:
                while self.dropped.pop() != tag:
                    pass
        elif self.in_math:
            self.in_math = tag != "math"
        elif tag in BLOCK_TAGS:
            self.end_block()

    def handle_data(self, data):
        if not self.dropped and not self.in_math:
            self.inline.append(data)

    def end_block(self):
        text, self.inline = one_line("".join(self.inline)), []
        if text:
            if self.prefix.startswith("#") and not self.first_heading:
                self.first_heading = text
            self.lines.append(self.prefix + text)
        self.prefix = ""


def text_of_html(body, url):
    declared = re.search(rb"""<meta[^>]+charset=["']?([A-Za-z0-9_-]+)""", body[:4096], re.I)
    try:
        page = body.decode(declared.group(1).decode() if declared else "utf-8", "replace")
    except LookupError:
        page = body.decode("utf-8", "replace")
    parser = ReadableText()
    parser.feed(page)
    parser.close()
    parser.end_block()
    text = "\n".join(parser.lines)
    if not text.strip() or (len(text) <= 600 and JAVASCRIPT_NOTICE.search(text)):
        raise Failure(f"no readable text in the HTML of {host_of(url)} (built by JavaScript?): "
                      "try the site's API or feed (SOURCES.md)", 200, NOTHING_READABLE)
    title = re.search(r"<title[^>]*>(.*?)</title>", page, re.I | re.S)
    return (one_line(html.unescape(title.group(1))) if title else "") or parser.first_heading, text


def text_of_pdf(body):
    try:
        import pypdf
    except ImportError as error:
        raise Failure("pypdf is missing: python3 -m pip install --user pypdf",
                      exit_code=MISSING_DEPENDENCY) from error
    try:
        reader = pypdf.PdfReader(io.BytesIO(body))
        pages = [re.sub(r"[ \t]+", " ", page.extract_text() or "").strip() for page in reader.pages]
        title = one_line(reader.metadata.title if reader.metadata else "")
        title = title or (largest_text(reader.pages[0]) if reader.pages else "")
    except Exception as error:
        raise Failure(f"pypdf cannot read this PDF: {error}") from error
    if not any(pages):
        raise Failure(f"the PDF has {len(pages)} pages and no text layer (a scan?)",
                      exit_code=NOTHING_READABLE)
    return title, "\n".join(f"[page {number}]\n{page}" for number, page in enumerate(pages, 1))


def largest_text(page):
    """Many arXiv PDFs have no title in their metadata; the title is the largest type."""
    runs = []

    def remember(text, matrix, text_matrix, font, size):
        if text.strip():
            runs.append((round(size * abs(matrix[3] * text_matrix[3]), 1), text.strip()))

    page.extract_text(visitor_text=remember)
    largest = max((size for size, _ in runs), default=0)
    return one_line(" ".join(text for size, text in runs if size == largest))


def youtube_id(url):
    found = YOUTUBE_ID.search(url) if YOUTUBE_HOST.fullmatch(host_of(url)) else None
    return found.group(1) if found else ""


def text_of_youtube(url, languages):
    video_id = youtube_id(url)
    if not video_id:
        raise Failure("not a YouTube video URL (watch, youtu.be, shorts, live or embed)")
    request = json.dumps({"context": {"client": YOUTUBE_CLIENT}, "videoId": video_id}).encode()
    _, _, _, body = fetch(YOUTUBE_PLAYER, request, {"Content-Type": "application/json"})
    player = json.loads(body)
    playability = player.get("playabilityStatus", {})
    if playability.get("status") != "OK":
        reason = f"YouTube: {one_line(playability.get('reason')) or playability.get('status')}"
        raise Failure(reason, 200, FAILED if playability.get("status") == "ERROR" else BLOCKED)
    captions = player.get("captions", {}).get("playerCaptionsTracklistRenderer", {})
    if not captions.get("captionTracks"):
        raise Failure(f"the video has no captions ({media_size(player)}): its audio is a download "
                      "for the user to approve, then transcribe.sh", 200, NOTHING_READABLE)
    track = choose_track(captions["captionTracks"], languages)
    code, _, _, timedtext = fetch(track["baseUrl"], kind="text")
    lines = caption_lines(parse_captions(timedtext))
    if not lines:
        raise Failure(f"the {track.get('languageCode')} caption track is empty",
                      code, NOTHING_READABLE)
    return code, player.get("videoDetails", {}).get("title", ""), "\n".join(lines)


def media_size(player):
    """Length and the size of the best audio stream: what the user weighs before a download."""
    seconds = int(player.get("videoDetails", {}).get("lengthSeconds") or 0)
    audio = [f for f in player.get("streamingData", {}).get("adaptiveFormats", [])
             if f.get("mimeType", "").startswith("audio/") and f.get("contentLength")]
    size = max((int(f["contentLength"]) for f in audio), default=0)
    length = f"length {seconds // 60}:{seconds % 60:02d}" if seconds else "length unknown"
    return f"{length}, audio about {size / 1_000_000:.0f} MB" if size else length


def choose_track(tracks, languages):
    """The wanted language first, else the spoken one; an uploaded track before an automatic."""
    spoken = next((t["languageCode"] for t in tracks if t.get("kind") == AUTO_CAPTIONS), "")
    for language in [code for code in languages + [spoken] if code]:
        base = language.lower().split("-")[0]
        matching = [t for t in tracks if t.get("languageCode", "").lower().split("-")[0] == base]
        if matching:
            return min(matching, key=lambda t: t.get("kind") == AUTO_CAPTIONS)
    return tracks[0]


def parse_captions(xml_bytes):
    """timedtext format 3: <p t="start in ms">text</p>."""
    if not xml_bytes.strip():
        return []
    cues = [(int(p.get("t", "0")), one_line("".join(p.itertext())))
            for p in ElementTree.fromstring(xml_bytes).iter("p")]
    return [(start, text) for start, text in cues if text]


def caption_lines(cues):
    """Cues last 2-5 s; a line of 30-60 s that ends at a sentence is easier to quote."""
    lines = []
    for start, text in cues:
        seconds = (start - lines[-1][0]) / 1000 if lines else 0
        at_sentence_end = bool(lines) and lines[-1][1][-1].endswith((".", "!", "?", "…"))
        if lines and seconds < 60 and not (seconds >= 30 and at_sentence_end):
            lines[-1][1].append(text)
        else:
            lines.append((start, [text]))
    return [f"[{start // 60000:02d}:{start // 1000 % 60:02d}] {' '.join(words)}"
            for start, words in lines]


def capture(url, kind, languages):
    """Returns (http code, title, text)."""
    if kind == "youtube" or (kind == "auto" and youtube_id(url)):
        return text_of_youtube(url, languages)
    code, final_url, content_type, body = fetch(url, kind=kind)
    if not body.strip():
        raise Failure("the answer has an empty body", code, NOTHING_READABLE)
    if kind == "auto":
        kind = auto_kind(content_type, body)
    if kind == "pdf":
        return (code, *text_of_pdf(body))
    if kind == "html":
        return (code, *text_of_html(body, final_url))
    path = urllib.parse.urlsplit(final_url).path.rstrip("/")
    title = urllib.parse.unquote(path.rsplit("/", 1)[-1]) or host_of(final_url)
    return code, title, body.decode("utf-8", "replace").replace("\r\n", "\n")


def auto_kind(content_type, body):
    if content_type == "application/pdf" or body.startswith(b"%PDF-"):
        return "pdf"
    starts_as_html = body[:512].lstrip().lower().startswith((b"<!doctype", b"<html"))
    if content_type in HTML_TYPES or starts_as_html:
        return "html"
    if content_type.startswith("text/") or content_type.endswith(("json", "xml")):
        return "text"
    raise Failure(f"cannot read {content_type or 'an unknown type'}: a download, ask the user")


def redacted_url(url):
    """Captures may be committed, so key-like query values and user:password@ never reach them."""
    parts = urllib.parse.urlsplit(url)
    netloc = parts.netloc
    if "@" in netloc:
        netloc = "REDACTED@" + netloc.rpartition("@")[2]
    pairs = []
    for pair in parts.query.split("&"):
        name, has_value, _ = pair.partition("=")
        words = [word.lower() for word in NAME_WORDS.findall(urllib.parse.unquote_plus(name))]
        secret = any(part in word for word in words for part in SECRET_PARTS)
        secret = secret or any(word.endswith(SECRET_ENDINGS) for word in words)
        pairs.append(f"{name}=REDACTED" if has_value and secret else pair)
    return urllib.parse.urlunsplit(parts._replace(netloc=netloc, query="&".join(pairs)))


def write_capture(out_path, url, title, text):
    retrieved = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    header = f"url: {redacted_url(url)}\ntitle: {one_line(title)}\nretrieved: {retrieved}"
    os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as handle:
        handle.write(f"---\n{header}\n---\n" + text.strip("\n") + "\n")


def report(status, out=None, chars=0, title=None, http=None, reason=None):
    line = {"status": status, "http": http, "out": out, "chars": chars, "title": title}
    print(json.dumps({**line, **({"reason": reason} if reason else {})}, ensure_ascii=False))


def main(argv):
    parser = argparse.ArgumentParser(prog="capture.py", description="URL -> text capture")
    parser.add_argument("url")
    parser.add_argument("out")
    parser.add_argument("--kind", default="auto", choices=KINDS)
    parser.add_argument("--lang", default="", help="caption languages in order, e.g. ru,en")
    try:
        arguments = parser.parse_args(argv)
    except SystemExit as exit_request:
        # argparse exits 2 on a usage error, and 2 here means blocked.
        return OK if exit_request.code == 0 else FAILED
    if urllib.parse.urlsplit(arguments.url).scheme not in ("http", "https"):
        print("capture.py: the URL must start with http:// or https://", file=sys.stderr)
        return FAILED
    languages = [code.strip() for code in arguments.lang.split(",") if code.strip()]
    try:
        code, title, text = capture(arguments.url, arguments.kind, languages)
        if not text.strip():
            raise Failure("the source has no text", code, NOTHING_READABLE)
        write_capture(arguments.out, arguments.url, title, text)
    except Failure as failure:
        report(STATUS[failure.exit_code], http=failure.http, reason=failure.reason)
        return failure.exit_code
    except (ValueError, ElementTree.ParseError, OSError) as error:
        report("failed", reason=f"{type(error).__name__}: {error}")
        return FAILED
    report("ok", arguments.out, len(text), title, code)
    return OK


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
