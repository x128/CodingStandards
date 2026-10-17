import json, os, re, sys

USAGE = 'usage: removed_comments.py <src before> <src after> <out json> [how many blocks at most; every k-th removed block is taken above it]'
BARE_TEST_MARKER = re.compile(r'^\s*// (arrange|act|assert|given|when|then)\s*$', re.IGNORECASE)
TRAILING_COMMENT = re.compile(r'\S.*?\s//\s?(.*)$')


def next_code_line(lines, start):
    return next((l.strip() for l in lines[start:] if l.strip()), '')


def comment_blocks_with_the_line_they_stand_on(root):
    blocks = []
    for folder, _, files in os.walk(root):
        for name in sorted(files):
            if not name.endswith('.kt'): continue
            path = os.path.join(folder, name)
            relative = os.path.relpath(path, root)
            lines = open(path, encoding='utf-8').read().split('\n')
            i = 0
            while i < len(lines):
                line = lines[i]
                stripped = line.strip()
                if BARE_TEST_MARKER.match(line):
                    i += 1
                    continue
                if stripped.startswith('/*'):
                    start = i
                    while '*/' not in lines[i] and i + 1 < len(lines): i += 1
                    blocks.append({'file': relative, 'line': start + 1, 'text': [l.strip() for l in lines[start:i + 1]], 'documents': next_code_line(lines, i + 1)})
                    i += 1
                    continue
                if stripped.startswith('//'):
                    start = i
                    while i < len(lines) and lines[i].strip().startswith('//') and not BARE_TEST_MARKER.match(lines[i]): i += 1
                    blocks.append({'file': relative, 'line': start + 1, 'text': [l.strip() for l in lines[start:i]], 'documents': next_code_line(lines, i)})
                    continue
                trailing = TRAILING_COMMENT.match(line)
                if trailing and not line.split('//')[0].endswith('"') and not re.search(r'https?://', line):
                    blocks.append({'file': relative, 'line': i + 1, 'text': ['// ' + trailing.group(1).strip()], 'documents': stripped})
                i += 1
    return blocks


def words_of(block):
    return ' '.join(re.sub(r'^(/\*\*?|\*/|\*|//)\s?', '', t).strip() for t in block['text']).strip()


def main():
    if len(sys.argv) not in (4, 5): sys.exit(USAGE)
    before, after, out = sys.argv[1], sys.argv[2], sys.argv[3]
    at_most = int(sys.argv[4]) if len(sys.argv) == 5 else 100000
    blocks_before = comment_blocks_with_the_line_they_stand_on(before)
    blocks_after = comment_blocks_with_the_line_they_stand_on(after)
    still_there = {words_of(b) for b in blocks_after}
    removed = [b for b in blocks_before if words_of(b) and words_of(b) not in still_there]
    every = max(1, -(-len(removed) // at_most))
    chosen = removed[::every][:at_most]
    for n, block in enumerate(chosen, 1): block['id'] = f'C{n:03d}'
    json.dump({'blocks_before': len(blocks_before), 'blocks_after': len(blocks_after), 'removed': len(removed),
               'taken': len(chosen), 'every': every, 'blocks': chosen}, open(out, 'w'), ensure_ascii=False, indent=1)
    print(f'{before}: blocks before {len(blocks_before)}, after {len(blocks_after)}, removed {len(removed)}, taken {len(chosen)} (every {every})')


main()
