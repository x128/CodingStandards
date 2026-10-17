import collections, json, sys

USAGE = 'usage: trace_summary.py <result json of a trace or loss run> [arm]  (counts where the meaning of each traced comment is: main code, tests or documents)'


def place_kind(path):
    if path.startswith('src/main'): return 'main'
    if path.startswith('src/test'): return 'test'
    return 'document'


def final(item, check):
    verdict, where = item['verdict'], item['where']
    if check is None: return verdict, where
    if check['verdict'] == 'information is in the new version':
        return ('found by verifier' if verdict in ('lost', 'partly') else verdict), (check['where'] if verdict in ('lost', 'partly') else where)
    if check['verdict'] == 'information is partly in the new version': return 'partly', check['where'] or where
    if check['verdict'] == 'information is no longer needed': return 'no longer needed', where
    return 'lost', where


def best_place(verdict, where):
    if verdict in ('repeated the code', 'no longer needed', 'code gone'): return 'repeated or gone'
    if verdict == 'lost': return 'lost'
    kinds = {place_kind(w['file']) for w in where}
    place = next((k for k in ('main', 'test', 'document') if k in kinds), 'nowhere')
    return ('partly, ' if verdict == 'partly' else '') + place


def main():
    if len(sys.argv) not in (2, 3): sys.exit(USAGE)
    out = json.load(open(sys.argv[1]))
    result = out.get('result', out)
    result = json.loads(result) if isinstance(result, str) else result
    chains = [r for r in result.get('results', result.get('loss', [])) if r and r.get('kind', 'loss') == 'loss' and (len(sys.argv) == 2 or r.get('arm') == sys.argv[2])]
    counts = collections.Counter()
    per_id = {}
    for chain in chains:
        if not chain.get('found'): counts['part not checked'] += 1; continue
        checks = {i['id']: i for i in (chain.get('verified') or {}).get('items', [])}
        for item in chain['found']['items']:
            place = best_place(*final(item, checks.get(item['id'])))
            counts[place] += 1
            per_id[f"{chain['project']}:{item['id']}"] = place
    print(json.dumps({'counts': dict(counts), 'total': sum(v for k, v in counts.items() if k != 'part not checked')}))
    json.dump(per_id, open(sys.argv[1] + '.places.json', 'w'))


main()
