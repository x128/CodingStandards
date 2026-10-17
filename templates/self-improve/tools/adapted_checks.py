import difflib, os, re, sys

USAGE = 'usage: adapted_checks.py <acceptance tests as written> <the same tests after adapting them>  (lines that assert, expect a value or send an event must stay the same; every other changed line is printed)'

CHECK = re.compile(r'\b(assert\w*|expect\w*|fail|check\w*|onEvent|send|\.on[A-Z]\w*)\s*[({<]|\bshouldBe\b|@Test')


def lines(root):
    out = {}
    for name in sorted(os.listdir(root)):
        if name.endswith('.kt'):
            out[name] = open(os.path.join(root, name), encoding='utf-8').read().split('\n')
    return out


if len(sys.argv) != 3: sys.exit(USAGE)
original, adapted = lines(sys.argv[1]), lines(sys.argv[2])
changed_checks = 0
for name in sorted(set(original) | set(adapted)):
    a, b = original.get(name, []), adapted.get(name, [])
    if name not in adapted:
        print(f'REMOVED FILE {name}')
        changed_checks += sum(1 for l in a if CHECK.search(l))
        continue
    if name not in original:
        print(f'NEW FILE {name}')
    checks_a = [l.strip() for l in a if CHECK.search(l)]
    checks_b = [l.strip() for l in b if CHECK.search(l)]
    if checks_a != checks_b:
        for d in difflib.unified_diff(checks_a, checks_b, lineterm='', n=0):
            if d.startswith(('+', '-')) and not d.startswith(('+++', '---')):
                print(f'CHECK CHANGED {name}: {d}')
                changed_checks += 1
    for d in difflib.unified_diff(a, b, lineterm='', n=0):
        if d.startswith(('+', '-')) and not d.startswith(('+++', '---')) and not CHECK.search(d):
            print(f'  other line {name}: {d[:160]}')
print(f'CHECK LINES CHANGED: {changed_checks}')
