import glob, json, os, re, sys
from collections import Counter, defaultdict

USAGE = 'usage: count_code.py <project root> [--json]'
LIBRARY_EXCEPTIONS = r'(StoreException|RatesException|NotificationException)'


def layer_of(path, text):
    folders = path.split('/')
    if 'presentation' in folders: return 'presentation'
    if 'data' in folders: return 'data'
    if 'di' in folders: return 'wiring'
    if 'domain' in folders or 'model' in folders: return 'domain'
    if re.search(r'^import lib\.(store|rates|notify)\.', text, re.M): return 'data'
    if re.search(r'^import lib\.ui\.', text, re.M) or 'ViewModel' in os.path.basename(path): return 'presentation'
    return 'unsorted'


def code_comment_and_kdoc_lines_without_blank_ones(text):
    code = comment = kdoc = 0
    inside_block = False
    block_is_kdoc = False
    for raw in text.split('\n'):
        line = raw.strip()
        if not line: continue
        if inside_block:
            if block_is_kdoc: kdoc += 1
            else: comment += 1
            if '*/' in line: inside_block = False
            continue
        if line.startswith('/**'):
            kdoc += 1
            if '*/' not in line: inside_block, block_is_kdoc = True, True
            continue
        if line.startswith('/*'):
            comment += 1
            if '*/' not in line: inside_block, block_is_kdoc = True, False
            continue
        if line.startswith('//'):
            comment += 1
            continue
        code += 1
        if re.search(r'[^:"\'/]//\s', line) and not re.search(r'"[^"]*//[^"]*"', line): comment += 1
    return code, comment, kdoc


def count(root):
    main = sorted(glob.glob(root + '/src/main/kotlin/**/*.kt', recursive=True))
    test = sorted(glob.glob(root + '/src/test/kotlin/**/*.kt', recursive=True))
    per_layer = defaultdict(Counter)
    facts = Counter()
    lists = defaultdict(list)
    for path in main:
        text = open(path).read()
        relative = path.replace(root + '/src/main/kotlin/', '')
        layer = layer_of(path.replace(root, ''), text)
        code, comment, kdoc = code_comment_and_kdoc_lines_without_blank_ones(text)
        per_layer[layer].update({'files': 1, 'code': code, 'comment': comment, 'kdoc': kdoc})
        imports = re.findall(r'^import\s+([\w.]+)', text, re.M)
        if layer == 'domain':
            for name in imports:
                if name.startswith(('lib.', 'java.io', 'java.nio', 'java.sql', 'java.net')): lists['domain names an outside API'].append(f'{relative}: {name}')
                if re.search(r'\.(data|presentation|di)\.', name) and name.startswith('app.'): lists['domain imports data, presentation or wiring'].append(f'{relative}: {name}')
            if re.search(r'\b(LocalDate|Instant|LocalDateTime)\.now\(|System\.currentTimeMillis\(', text): lists['domain reads the clock itself'].append(relative)
        if layer == 'presentation':
            for name in imports:
                if name.startswith(('lib.store', 'lib.rates', 'lib.notify')) or (name.startswith('app.') and '.data.' in name): lists['presentation imports data code or a library of the data layer'].append(f'{relative}: {name}')
        facts['kotlin.Result as a type'] += len(re.findall(r'\bResult<', text))
        facts['runCatching'] += len(re.findall(r'\brunCatching\b', text))
        facts['catch (Exception or Throwable)'] += len(re.findall(r'catch\s*\(\s*\w+\s*:\s*(?:Exception|Throwable)\s*\)', text))
        facts['catch of CancellationException'] += len(re.findall(r'catch\s*\(\s*\w+\s*:\s*CancellationException', text))
        facts['!!'] += len(re.findall(r'\w!!', text))
        facts['else -> branches'] += len(re.findall(r'^\s*else\s*->', text, re.M))
        facts['sealed types'] += len(re.findall(r'\bsealed\s+(?:interface|class)\b', text))
        for match in re.finditer(r'^\s*(?:(?:internal|private|public|abstract|open|data|final)\s+)*class\s+(\w+)', text, re.M):
            name = match.group(1)
            if name.endswith('Impl'): lists['classes named ...Impl'].append(name)
            if name.endswith('UseCase'): lists['use case classes'].append((name, code))
            if name.endswith('ViewModel'): lists['view models'].append((name, code, len(re.findall(r'\bif\s*\(|\bwhen\b', text))))
        if re.search(r'catch\s*\(\s*\w+\s*:\s*' + LIBRARY_EXCEPTIONS, text): lists['files that catch a library exception'].append(f'{relative} [{layer}]')
    test_functions = sum(len(re.findall(r'@Test\b', open(path).read())) for path in test)
    test_code = sum(code_comment_and_kdoc_lines_without_blank_ones(open(path).read())[0] for path in test)
    total = Counter()
    for layer_counts in per_layer.values(): total.update(layer_counts)
    use_cases = lists.pop('use case classes', [])
    view_models = lists.pop('view models', [])
    return {
        'root': os.path.basename(root),
        'layers': {k: dict(v) for k, v in sorted(per_layer.items())},
        'main': dict(total),
        'tests': {'files': len(test), 'code': test_code, 'test functions': test_functions},
        'facts': dict(facts),
        'use cases': {'count': len(use_cases),
                      'with 12 code lines or fewer in the file': sorted(n for n, c in use_cases if c <= 12),
                      'median file size': sorted(c for _, c in use_cases)[len(use_cases) // 2] if use_cases else 0},
        'view models': sorted(view_models, key=lambda v: -v[1]),
        'lists': {k: sorted(set(map(str, v))) for k, v in lists.items()},
    }


def main():
    if len(sys.argv) < 2: sys.exit(USAGE)
    result = count(sys.argv[1].rstrip('/'))
    if '--json' in sys.argv:
        print(json.dumps(result, ensure_ascii=False))
        return
    print('==', result['root'], '| main', result['main'], '| tests', result['tests'])
    for name, counts in result['layers'].items(): print(f'   {name:13}', counts)
    print('   facts', result['facts'])
    print('   use cases', result['use cases']['count'], '| median file size', result['use cases']['median file size'], '| small ones', len(result['use cases']['with 12 code lines or fewer in the file']))
    print('   view models', result['view models'][:8])
    for name, items in result['lists'].items(): print(f'   {name}: {len(items)}', items[:6])


main()
