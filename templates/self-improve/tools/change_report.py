import filecmp, os, re, subprocess, sys

USAGE = 'usage: change_report.py <project before the change> <project after the change> [folder of acceptance tests ...]'
TOOLS = os.path.dirname(os.path.abspath(__file__))


def layer_of(relative_path):
    folders = relative_path.split('/')
    if 'presentation' in folders: return 'presentation'
    if 'data' in folders: return 'data'
    if 'di' in folders: return 'wiring'
    if 'domain' in folders or 'model' in folders: return 'domain'
    return 'other'


def changed_files(before, after, part):
    root_before, root_after = os.path.join(before, part), os.path.join(after, part)
    changed = []
    for folder, _, files in os.walk(root_after):
        for name in files:
            if not name.endswith('.kt'): continue
            path = os.path.join(folder, name)
            relative = os.path.relpath(path, root_after)
            old = os.path.join(root_before, relative)
            if not os.path.exists(old): changed.append(('added', relative))
            elif not filecmp.cmp(old, path, shallow=False): changed.append(('changed', relative))
    for folder, _, files in os.walk(root_before):
        for name in files:
            relative = os.path.relpath(os.path.join(folder, name), root_before)
            if name.endswith('.kt') and not os.path.exists(os.path.join(root_after, relative)): changed.append(('removed', relative))
    return sorted(changed, key=lambda c: c[1])


def last_line_of(command):
    if command[0] == 'sh' and not os.path.exists(command[1]):
        return [f'no {os.path.basename(command[1])}'], ''
    out = subprocess.run(command, capture_output=True, text=True).stdout
    lines = [l for l in out.split('\n') if re.match(r'(OK|Tests run|FAILED|BUILD|LINT|COMMENTS|CRAP)', l)]
    return lines, out


def failing_tests(output):
    return sorted(set(re.findall(r'^\d+\) (.+?)\(', output, re.M)))


def main():
    if len(sys.argv) < 3: sys.exit(USAGE)
    before, after = sys.argv[1], sys.argv[2]
    main_changes = changed_files(before, after, 'src/main/kotlin')
    test_changes = changed_files(before, after, 'src/test/kotlin')
    layers = sorted({layer_of(path) for _, path in main_changes})
    print(f'{after}')
    print(f'   main files: {len(main_changes)} in layers {layers}')
    for kind, path in main_changes: print(f'      {kind:8} {path}')
    print(f'   test files: {len(test_changes)}')
    build, _ = last_line_of(['sh', os.path.join(after, 'build.sh')])
    print('   build:', build[-1] if build else 'no result')
    lint, _ = last_line_of(['sh', os.path.join(after, 'lint.sh')])
    print('   lint:', ' | '.join(lint[-3:]) if lint else 'no result')
    for acceptance in sys.argv[3:]:
        result, output = last_line_of(['sh', os.path.join(TOOLS, 'run-extra.sh'), after, acceptance])
        print(f'   acceptance {os.path.basename(acceptance)}:', result[-1] if result else 'no result')
        for name in failing_tests(output): print('      failing:', name[:150])


main()
