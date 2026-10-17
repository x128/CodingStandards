import json, sys

USAGE = 'usage: loss_parts.py <json of removed_comments.py> <out folder> <project name> [blocks per part, 55 by default]'


def main():
    if len(sys.argv) not in (4, 5): sys.exit(USAGE)
    source, out, project = sys.argv[1], sys.argv[2], sys.argv[3]
    per_part = int(sys.argv[4]) if len(sys.argv) == 5 else 55
    blocks = json.load(open(source))['blocks']
    parts = [blocks[i:i + per_part] for i in range(0, len(blocks), per_part)]
    for k, part in enumerate(parts, 1):
        with open(f'{out}/{project}-part{k}.md', 'w') as f:
            f.write(f'# Comments removed from {project}, part {k} of {len(parts)}\n\n')
            for b in part:
                f.write(f"## {b['id']}\nWas in: src/{b['file']} line {b['line']}\n\n```\n" + '\n'.join(b['text']) + '\n```\n')
                f.write('The code line under it (or the line it trailed): ' + b['documents'] + '\n\n')
    print(project, len(blocks), 'blocks in', len(parts), 'parts')


main()
