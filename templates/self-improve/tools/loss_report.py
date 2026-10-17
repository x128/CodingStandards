import collections, json, os, re, sys

USAGE = ('usage: loss_report.py <result json of the loss workflow> <judge mapping file> <folder that holds the projects after the change, one folder per project name>\n'
         'judge mapping lines look like: larch (p2): A=before B=after')
LOSS_VERDICTS = {'lost', 'partly'}


def result_of(path):
    out = json.load(open(path))
    result = out.get('result', out)
    return json.loads(result) if isinstance(result, str) else result


def judge_mapping(path):
    mapping = {}
    for line in open(path):
        m = re.match(r'(\w+) \((\w+)\): A=(\w+) B=(\w+)', line.strip())
        if m: mapping[m.group(1)] = {'A': m.group(3), 'B': m.group(4)}
    return mapping


def where_the_quote_is(root, place):
    path = os.path.join(root, place['file'])
    if not os.path.exists(path): return 'no file'
    lines = open(path, encoding='utf-8').read().split('\n')
    quote, n = place['quote'].strip(), place['line']
    if 1 <= n <= len(lines) and quote and quote in lines[n - 1]: return 'exact'
    return 'near' if any(quote in l for l in lines[max(0, n - 6):n + 5]) else 'NOT FOUND'


def final_verdict(item, verified):
    if verified is None: return item['verdict']
    if verified['verdict'] == 'information is in the new version':
        return 'found by verifier' if item['verdict'] in LOSS_VERDICTS else item['verdict']
    if verified['verdict'] == 'information is no longer needed': return 'no longer needed'
    if verified['verdict'] == 'information is partly in the new version': return 'partly'
    return 'lost'


def loss_per_project(chains, projects_after):
    per_project = collections.defaultdict(lambda: {'checker': collections.Counter(), 'final': collections.Counter(), 'places': collections.Counter(), 'lost': [], 'refuted finds': [], 'parts not checked': 0})
    for chain in chains:
        if not chain: continue
        summary = per_project[chain['project']]
        if not chain.get('found'):
            summary['parts not checked'] += 1
            continue
        root = os.path.join(projects_after, chain['project'])
        verified = {i['id']: i for i in (chain.get('verified') or {}).get('items', [])}
        for item in chain['found']['items']:
            summary['checker'][item['verdict']] += 1
            for place in item['where']: summary['places'][where_the_quote_is(root, place)] += 1
            check = verified.get(item['id'])
            verdict = final_verdict(item, check)
            if check is not None and item['verdict'] not in LOSS_VERDICTS and verdict in LOSS_VERDICTS:
                summary['refuted finds'].append((item['id'], item['verdict'], check['missing'] or check['reason']))
            summary['final'][verdict] += 1
            if verdict in LOSS_VERDICTS:
                summary['lost'].append((item['id'], verdict, item['information'], (check or item)['missing']))
    return per_project


def print_judges(judges, mapping):
    for j in judges:
        if not j or not j.get('result'):
            print('a judge gave no result'); continue
        sides = mapping.get(j['judge'], {})
        r = j['result']
        named = lambda x: sides.get(x, x)
        before_letter = 'A' if sides.get('A') == 'before' else 'B'
        after_letter = 'B' if before_letter == 'A' else 'A'
        print(f"{j['project']} ({j['judge']}, {j['first']} first): prefers {named(r['prefer'])} ({r['confidence']}); "
              f"readability {named(r['readability'])}, one place {named(r['one_place'])}, tests {named(r['tests'])}; "
              f"only in before: {len(r['knowledge_only_in_' + before_letter])}, only in after: {len(r['knowledge_only_in_' + after_letter])}")
        for reason in r['reasons']: print('     -', reason[:220])


def main():
    if len(sys.argv) != 4: sys.exit(USAGE)
    result = result_of(sys.argv[1])
    for project, s in sorted(loss_per_project(result.get('loss', []), sys.argv[3]).items()):
        print('=' * 80)
        print(project, '| checker:', dict(s['checker']))
        print('   after verification:', dict(s['final']), '| parts not checked:', s['parts not checked'])
        print('   cited places:', dict(s['places']))
        print('   finds the verifier refuted:', len(s['refuted finds']))
        for r in s['refuted finds']: print('     ', r[0], r[1], '->', r[2][:200])
        print('   lost or partly lost:', len(s['lost']))
        for r in s['lost']: print('     ', r[0], r[1], '|', r[2][:160], '| missing:', r[3][:160])
    print('=' * 80)
    print_judges(result.get('judges', []), judge_mapping(sys.argv[2]))


main()
