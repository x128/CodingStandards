import glob, json, os, re, sys
from collections import defaultdict

USAGE = ('usage: scan_transcripts.py <transcript folder of one workflow run> <work folder> <tools folder> <folder of hidden material> [folders no agent may read ...]\n'
         'Lists, for each agent, the paths outside its own project that its tool calls name.')
ABSOLUTE_PATH = re.compile(r'(/(?:private/tmp|Users|tmp|var|home)/[^\s"\'`;|&<>()\\]+)')


def project_root_named_first(content, work):
    match = re.search(r'(%s/[A-Za-z0-9_./-]*?/p\d+(?:-[a-z0-9]+)?)[ /]' % re.escape(work), content)
    return match.group(1) if match else None


def kind_of(path, work, tools, hidden, forbidden):
    if path.startswith(tools): return 'tools'
    if any(path.startswith(f) for f in forbidden): return 'FORBIDDEN'
    if path.startswith(hidden): return 'HIDDEN'
    if re.match(re.escape(work) + r'/.*?/p\d+', path): return 'OTHER PROJECT'
    if path.startswith(work): return 'work folder, elsewhere'
    return 'outside'


def main():
    if len(sys.argv) < 5: sys.exit(USAGE)
    transcripts, work, tools, hidden = sys.argv[1:5]
    forbidden = sys.argv[5:]
    report = defaultdict(lambda: defaultdict(set))
    for path in sorted(glob.glob(transcripts + '/agent-*.jsonl')):
        meta = path.replace('.jsonl', '.meta.json')
        label = json.load(open(meta)).get('description', '?') if os.path.exists(meta) else os.path.basename(path)
        root = None
        for line in open(path):
            try: entry = json.loads(line)
            except ValueError: continue
            content = (entry.get('message') or {}).get('content')
            if root is None and isinstance(content, str): root = project_root_named_first(content, work)
            if not isinstance(content, list): continue
            for block in content:
                if block.get('type') != 'tool_use': continue
                for p in ABSOLUTE_PATH.findall(json.dumps(block.get('input'), ensure_ascii=False)):
                    p = p.rstrip('.,:')
                    if root and (p == root or p.startswith(root + '/')): continue
                    report[f"{label} | root={os.path.basename(root) if root else '?'}"][kind_of(p, work, tools, hidden, forbidden)].add((block.get('name'), p[:160]))
    serious_agents = 0
    for label in sorted(report):
        kinds = report[label]
        serious = {k: v for k, v in kinds.items() if k in ('FORBIDDEN', 'HIDDEN', 'OTHER PROJECT')}
        print(('!! ' if serious else '   ') + label + ' -> ' + ', '.join(f'{k}: {len(v)}' for k, v in sorted(kinds.items())))
        serious_agents += bool(serious)
        for k, v in serious.items():
            for name, p in sorted(v)[:8]: print('        ', k, name, p)
    print('agents with paths outside their project:', len(report), '| agents that read hidden material, another project or a forbidden folder:', serious_agents)


main()
