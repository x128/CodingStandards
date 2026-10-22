"""Lists the places in a message that may break the rules of SKILL.md next to this file.

python3 -I check.py MESSAGE [--reader READER] [--words WORDS] [--json]

READER holds the reader's own messages: a name they used is not listed under rule 2.
WORDS holds one regular expression per line for words this reader does not want to see.
"""
import argparse
import json
import re
import sys

CODE = re.compile(r"```.*?```|`[^`\n]+`", re.S)
SENTENCE_END = re.compile(r"(?<=[.!?…])\s+")
LONG_MESSAGE_SENTENCES = 12

FILE_NAME = re.compile(r"\b[\w.-]+\.(?:kt|kts|swift|md|sh|py|json|ya?ml|xml|conf|sq|sqm|gradle|toml)\b")
CAMEL_CASE = re.compile(r"\b[A-Z]?[a-z]+(?:[A-Z][a-z0-9]+)+\b")
SNAKE_CASE = re.compile(r"\b[a-z]+(?:_[a-z0-9]+)+\b")
LATIN_WORD = re.compile(r"\b[A-Za-z][A-Za-z-]{2,}\b")

COUNTED_THINGS = (
    r"(?:абзац|пункт|строк|правил|замечани|находк|вопрос|файл|мест|исправлени|верси|раздел|ошибк|шаг|"
    r"paragraph|item|line|rule|finding|question|file|place|fix|version|section|error|step)\w*"
)
NUMERAL = r"(?:\d+|два|две|три|четыре|пять|шесть|семь|восемь|девять|десять|two|three|four|five|six|seven|eight|nine|ten)"
POINTERS = [
    re.compile(rf"(?i)\b(?:эт(?:и|их|от|а|о|у)|т(?:е|ех|от|а|у)|указанн\w*|упомянут\w*|стар\w+|нов\w+|прежн\w*|те же)\s+{NUMERAL}?\s*{COUNTED_THINGS}"),
    re.compile(rf"(?i)\b{NUMERAL}\s+{COUNTED_THINGS}"),
    re.compile(r"(?i)\b(?:см\. выше|как (?:я )?(?:писал|говорил) (?:выше|раньше)|выше|ранее|as above|see above|as mentioned|the (?:old|new|previous) \w+)\b"),
]
NUMBER = re.compile(r"(?<![\w.,/-])\d+(?:[.,]\d+)?(?![\w.,/-])")
NUMBER_FOLLOWED_BY_WORD = re.compile(r"\s*(?:%|[-–]\s*\d+\s*)?\s*[A-Za-zА-Яа-яЁё]")
DATE_OR_ID = re.compile(r"(?i)^\s*(?:янв|фев|мар|апр|ма[йя]|июн|июл|авг|сен|окт|ноя|дек)")
NOUN_BEFORE = re.compile(r"[A-Za-zА-Яа-яЁё]{2,}\.?\s*$")

OWN_ACTION = re.compile(
    r"(?i)\b(?:я\s+)?(?:сделал|добавил|запустил|изменил|убрал|удалил|исправил|перенёс|отдал|поставил|заменил|"
    r"переписал|остановил|отключил|включил|откатил|вернул|провёл|I (?:added|ran|changed|removed|deleted|fixed|moved|replaced|rewrote|stopped|reverted))\b"
)
REASON = re.compile(r"(?i)\b(?:потому что|так как|чтобы|поэтому|из-за|иначе|ведь|оттого|because|so that|since|therefore)\b|:")
LABEL_OPTION = re.compile(
    r"(?i)^\s*(?:это\s+)?(?:правил\w*|разов\w*|исключени\w*|вариант\s*\w*|[A-ZА-Я]|\d+|a rule|a one-off|option\s*\w*)\s*[?.!]?\s*$"
)


def strip_code(text):
    return CODE.sub(" ", text)


def sentences(text):
    return [s.strip() for s in SENTENCE_END.split(strip_code(text)) if s.strip()]


def finding(rule, quote, what):
    return {"rule": rule, "quote": quote.strip()[:120], "what": what}


def one_subject(text):
    found = []
    prose = strip_code(text)
    if prose.count("?") > 1:
        found.append(finding(1, "?" * prose.count("?"), "more than one question: ask the first, name the others in one line"))
    count = len(sentences(text))
    if count > LONG_MESSAGE_SENTENCES:
        found.append(finding(1, f"{count} sentences", "long: more than one subject, or facts the reader does not need"))
    return found


def unseen_names(text, reader):
    names = set(re.findall(r"`([^`\n]+)`", text))
    prose = strip_code(text)
    for pattern in (FILE_NAME, CAMEL_CASE, SNAKE_CASE):
        names.update(pattern.findall(prose))
    if len(re.findall(r"[А-Яа-яЁё]", prose)) > len(re.findall(r"[A-Za-z]", prose)):
        names.update(LATIN_WORD.findall(prose))
    seen = reader.lower()
    return [
        finding(2, name, "a name the reader has not used: explain it in the same sentence, or leave it out")
        for name in sorted(names)
        if name.lower() not in seen
    ]


def pointers(text):
    prose = strip_code(text)
    return [
        finding(3, match.group(0), "points at something: say which one and what it says, or quote it")
        for pattern in POINTERS
        for match in pattern.finditer(prose)
    ]


def bare_numbers(text):
    found = []
    for sentence in sentences(text):
        for match in NUMBER.finditer(sentence):
            after = sentence[match.end():]
            before = sentence[:match.start()]
            if NUMBER_FOLLOWED_BY_WORD.match(after) or DATE_OR_ID.match(after) or NOUN_BEFORE.search(before):
                continue
            found.append(finding(4, sentence[max(0, match.start() - 30):match.end() + 10], "a number without what it counts"))
    return found


def steps_without_reason(text):
    parts = sentences(text)
    found = []
    for index, sentence in enumerate(parts):
        if not OWN_ACTION.search(sentence):
            continue
        following = parts[index + 1] if index + 1 < len(parts) else ""
        if not REASON.search(sentence) and not REASON.search(following):
            found.append(finding(5, sentence, "a step without the event that made you take it"))
    return found


def label_options(text):
    prose = strip_code(text)
    questions = [s for s in sentences(prose) if s.endswith("?")]
    found = []
    for question in questions:
        options = re.split(r"\s+(?:или|or)\s+", question.split(":")[-1])
        if len(options) > 1 and any(LABEL_OPTION.match(option) for option in options):
            found.append(finding(6, question, "an option is a label: say the action the reader would take"))
    return found


def unwanted_words(text, patterns):
    prose = strip_code(text)
    return [
        finding(0, match.group(0), "a word this reader does not want: say it in their words")
        for pattern in patterns
        for match in pattern.finditer(prose)
    ]


def check(text, reader="", word_patterns=()):
    return (
        one_subject(text) + unseen_names(text, reader) + pointers(text) + bare_numbers(text)
        + steps_without_reason(text) + label_options(text) + unwanted_words(text, word_patterns)
    )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("message")
    parser.add_argument("--reader", default=None)
    parser.add_argument("--words", default=None)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    text = open(args.message, encoding="utf-8").read()
    reader = open(args.reader, encoding="utf-8").read() if args.reader else ""
    patterns = []
    if args.words:
        lines = open(args.words, encoding="utf-8").read().splitlines()
        patterns = [re.compile(line, re.I) for line in lines if line.strip() and not line.startswith("#")]
    found = check(text, reader, patterns)
    if args.json:
        json.dump(found, sys.stdout, ensure_ascii=False, indent=1)
        return
    for item in found:
        print(f"rule {item['rule']}: «{item['quote']}» — {item['what']}")
    print(f"{len(found)} place(s) to look at")


if __name__ == "__main__":
    main()
