#!/usr/bin/env python3
"""edit-check.py — checks a research REPORT.md against the writing rules of method.md "The Report".

Usage: python3 edit-check.py <REPORT.md>

Prints one line per breach with the line number, and a summary; exit 1 when there is a breach,
0 when the report passes. The checks are mechanical and err on the side of flagging: an editor
reads each line and decides. Checked: the Коротко section is 5-8 sentences in 2-4 paragraphs;
a paragraph has at most 6 sentences and 120 words, a sentence at most 35 words; a heading has at most 10 words; a quote in Latin script is
followed by a translation; no file path, URL or journal vocabulary in the prose; a number with
three or more digits is not repeated more than three times. Code blocks, tables, lists and the
Источники section are not prose and are skipped.
"""
import re
import sys

MAX_SENTENCES = 6
MAX_SENTENCE_WORDS = 35
MAX_PARAGRAPH_WORDS = 120
MAX_HEADING_WORDS = 10
SHORT_SENTENCES = (5, 8)
SHORT_PARAGRAPHS = (2, 4)
MAX_NUMBER_REPEATS = 3

SENTENCE_END = re.compile(r'[.!?…](?:[»")\]]*)\s+(?=[A-ZА-ЯЁ«"(\[*])')
LATIN_QUOTE = re.compile(r'[«"“]([^«»"“”]*?)[»"”]')
LATIN_WORDS = re.compile(r'[A-Za-z]{2,}')
CYRILLIC = re.compile(r'[А-Яа-яЁё]')
TRANSLATION_AFTER = re.compile(r'^[\s\[\]\d,.;]*[(—–:]')
URL = re.compile(r'https?://\S+|\b[a-z0-9.-]+\.(?:com|org|net|io|ai|dev|md|ru)/\S*')
PATH = re.compile(r'(?<![\w`/])(?:[\w.-]+/){1,}[\w.-]+\.(?:md|py|sh|yaml|yml|jsonl|json|plist|txt)\b')
BARE_FILE = re.compile(r'(?<![\w`/.])[A-Z_]{3,}\.md\b')
JOURNAL = re.compile(r'\bQ\d{1,2}\b|\b(?:run|прогон[а-я]*)\s+\d{3}\b|не исследовал|гипотез[аы] #|\bR\d\b')
BIG_NUMBER = re.compile(r'(?<![\d.,])(?<!\d )\d{3,}(?![\d.,])(?! \d)')


def sentences(text):
    return [part for part in SENTENCE_END.split(text.strip()) if part.strip()] if text.strip() else []


def prose_blocks(lines):
    """Yields (line number, kind, text) for headings and prose paragraphs; skips code, tables, lists."""
    in_code = False
    paragraph, start = [], 0
    section = ''
    for number, line in enumerate(lines, 1):
        stripped = line.strip()
        if stripped.startswith('```'):
            in_code = not in_code
            continue
        if in_code:
            continue
        if stripped.startswith('#'):
            if paragraph:
                yield start, 'paragraph', ' '.join(paragraph), section
                paragraph = []
            section = stripped.lstrip('#').strip()
            yield number, 'heading', section, section
            continue
        if not stripped or stripped.startswith('|') or re.match(r'^(?:[-*+]|\d+[.)])\s', stripped):
            if paragraph:
                yield start, 'paragraph', ' '.join(paragraph), section
                paragraph = []
            continue
        if not paragraph:
            start = number
        paragraph.append(stripped)
    if paragraph:
        yield start, 'paragraph', ' '.join(paragraph), section


def check(path):
    lines = open(path, encoding='utf-8').read().split('\n')
    breaches = []
    short_sentences, short_paragraphs = 0, 0
    numbers = {}
    for number, kind, text, section in prose_blocks(lines):
        if section.startswith('Источники'):
            continue
        if kind == 'heading':
            words = len(text.split())
            if words > MAX_HEADING_WORDS:
                breaches.append((number, f'heading has {words} words (at most {MAX_HEADING_WORDS})'))
            continue
        parts = sentences(text)
        count = len(parts)
        words = len(text.split())
        if section == 'Коротко':
            short_sentences += count
            short_paragraphs += 1
        elif count > MAX_SENTENCES:
            breaches.append((number, f'paragraph has {count} sentences (at most {MAX_SENTENCES})'))
        if words > MAX_PARAGRAPH_WORDS:
            breaches.append((number, f'paragraph has {words} words (at most {MAX_PARAGRAPH_WORDS})'))
        for part in parts:
            length = len(part.split())
            if length > MAX_SENTENCE_WORDS:
                breaches.append((number, f'sentence has {length} words (at most {MAX_SENTENCE_WORDS}): «{part[:60]}…»'))
        for match in LATIN_QUOTE.finditer(text):
            quote = match.group(1)
            if len(LATIN_WORDS.findall(quote)) >= 4 and not CYRILLIC.search(quote):
                after = text[match.end():match.end() + 90]
                if not (TRANSLATION_AFTER.match(after) and CYRILLIC.search(after)):
                    breaches.append((number, f'quote without a translation after it: «{quote[:50]}»'))
        bare = re.sub(r'`[^`]*`', '', text)
        for match in URL.finditer(bare):
            breaches.append((number, f'URL in the prose: {match.group(0)[:60]} (cite a number, list it in Источники)'))
        for match in PATH.finditer(bare):
            breaches.append((number, f'path in the prose: {match.group(0)} (name the artifact in code font, or cite)'))
        for match in JOURNAL.finditer(bare):
            breaches.append((number, f'journal vocabulary in the prose: «{match.group(0)}»'))
        for match in BIG_NUMBER.finditer(bare):
            numbers.setdefault(match.group(0), []).append(number)
    if short_paragraphs:
        if not SHORT_SENTENCES[0] <= short_sentences <= SHORT_SENTENCES[1]:
            breaches.append((0, f'Коротко has {short_sentences} sentences (5-8)'))
        if not SHORT_PARAGRAPHS[0] <= short_paragraphs <= SHORT_PARAGRAPHS[1]:
            breaches.append((0, f'Коротко has {short_paragraphs} paragraph(s) (2-4)'))
    else:
        breaches.append((0, 'no Коротко section'))
    for value, where in numbers.items():
        if len(where) > MAX_NUMBER_REPEATS:
            breaches.append((where[MAX_NUMBER_REPEATS], f'the number {value} appears {len(where)} times (say it once, then refer to it)'))
    for number, message in sorted(breaches):
        print(f'{path}:{number}: {message}')
    print(f'{len(breaches)} breach(es)' if breaches else 'passes the writing rules')
    return 1 if breaches else 0


if __name__ == '__main__':
    if len(sys.argv) != 2:
        print(__doc__.strip().split('\n')[2], file=sys.stderr)
        sys.exit(2)
    sys.exit(check(sys.argv[1]))
