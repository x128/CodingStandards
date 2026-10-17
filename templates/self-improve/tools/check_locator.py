import collections, json, os, sys

USAGE = 'usage: check_locator.py <project root> <locator answer as json> [locator answer for the same project before the change]'


def where_the_quote_is(source_root, file, line, quote):
    path = os.path.join(source_root, file)
    if not os.path.exists(path): return 'no file'
    lines = open(path, encoding='utf-8').read().split('\n')
    quote = quote.strip()
    if 1 <= line <= len(lines) and quote and quote in lines[line - 1]: return 'exact'
    return 'near' if any(quote in l for l in lines[max(0, line - 6):line + 5]) else 'NOT FOUND'


def answer_of(path):
    data = json.load(open(path))
    return data.get('result', data) if isinstance(data, dict) and 'rules' not in data else data


def main():
    if len(sys.argv) not in (3, 4): sys.exit(USAGE)
    source_root = os.path.join(sys.argv[1], 'src/main/kotlin')
    after = answer_of(sys.argv[2])
    before = answer_of(sys.argv[3]) if len(sys.argv) == 4 else None
    quotes = collections.Counter(where_the_quote_is(source_root, r['file'], r['line'], r['quote']) for r in after['rules'] if r['found'] != 'no')
    print('quotes of the rules:', dict(quotes))
    copies = collections.Counter(where_the_quote_is(source_root, c['file'], c['line'], c['quote']) for r in after['rules'] for c in r['also_decided_in'])
    print('quotes of the copies:', dict(copies))
    failure_places = after['failures']['library_exception_first_caught'] + after['failures']['general_message_produced_in']
    failures = collections.Counter(where_the_quote_is(source_root, f['file'], f['line'], f['quote']) for f in failure_places)
    print('quotes of the failures:', dict(failures))
    print('found:', dict(collections.Counter(r['found'] for r in after['rules'])))
    print('kind:', dict(collections.Counter(r['kind'] for r in after['rules'])))
    rules_before = {r['id'][:3]: r for r in before['rules']} if before else {}
    for rule in after['rules']:
        earlier = rules_before.get(rule['id'][:3])
        copies_before = len(earlier['also_decided_in']) if earlier else None
        if rule['also_decided_in'] or rule['found'] != 'yes' or copies_before:
            change = f'{copies_before} -> ' if earlier else ''
            print(f"   {rule['id'][:3]} {rule['found']} {rule['kind']} copies {change}{len(rule['also_decided_in'])} | {rule['note'][:180]}")
    units = after['units']
    print('use cases:', len(units), '| body is one call:', sum(1 for u in units if u['one_call']), '| decide something:', sum(1 for u in units if u['has_rule']))
    print('library exceptions first caught in:', sorted({p['file'].split('/')[-1] for p in after['failures']['library_exception_first_caught']}))


main()
