import sys
import xml.etree.ElementTree as ET

USAGE = 'usage: crap.py <jacoco.xml> <highest allowed score> [file of Class.function names recorded as exceptions]'


def crap_score_of_savoia_and_evans(complexity, covered_share):
    return complexity ** 2 * (1 - covered_share) ** 3 + complexity


def missed_and_covered(method, counter_type):
    for counter in method.findall('counter'):
        if counter.get('type') == counter_type:
            return int(counter.get('missed')), int(counter.get('covered'))
    return None


def recorded_exceptions(path):
    try:
        return {line.strip() for line in open(path) if line.strip()}
    except (FileNotFoundError, TypeError):
        return set()


def measured_functions(report):
    for package in ET.parse(report).getroot().iter('package'):
        for cls in package.findall('class'):
            for method in cls.findall('method'):
                if missed_and_covered(method, 'LINE') is None:
                    continue
                complexity_as_decisions_plus_one = sum(missed_and_covered(method, 'COMPLEXITY'))
                missed_instructions, covered_instructions = missed_and_covered(method, 'INSTRUCTION')
                all_instructions = missed_instructions + covered_instructions
                covered_share = covered_instructions / all_instructions if all_instructions else 1.0
                yield (crap_score_of_savoia_and_evans(complexity_as_decisions_plus_one, covered_share),
                       complexity_as_decisions_plus_one, covered_share,
                       cls.get('name').split('/')[-1] + '.' + method.get('name'),
                       (cls.get('sourcefilename') or '?') + ':' + (method.get('line') or '?'))


def main():
    if len(sys.argv) not in (3, 4):
        sys.exit(USAGE)
    report, highest_allowed = sys.argv[1], float(sys.argv[2])
    exceptions = recorded_exceptions(sys.argv[3] if len(sys.argv) == 4 else None)
    rows = list(measured_functions(report))
    above = [r for r in rows if r[0] > highest_allowed and r[3] not in exceptions]
    waived = [r for r in rows if r[0] > highest_allowed and r[3] in exceptions]
    highest = max((r[0] for r in rows), default=0)
    print(f'CRAP: {len(rows)} functions measured; highest {highest:.1f}; above {highest_allowed:g}: {len(above)}'
          + (f'; recorded exceptions: {len(waived)}' if waived else ''))
    for score, complexity, covered_share, name, where in sorted(above, reverse=True):
        print(f'  CRAP {score:6.1f}  complexity {complexity:3d}  coverage {covered_share:4.0%}  {name}  ({where})')
    sys.exit(1 if above else 0)


main()
