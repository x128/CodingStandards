export const meta = {
  name: 'self-improve-measure',
  description: 'Measure projects: testers run the hidden acceptance scenarios, readers locate every business rule, maintainers make the hidden changes of business rules, blind judges compare two versions',
  phases: [
    { title: 'Scenarios', detail: 'testers write and run the acceptance scenarios through the screens' },
    { title: 'Rules', detail: 'readers locate each business rule and its copies' },
    { title: 'Changes', detail: 'fresh maintainers make one change of a business rule each' },
    { title: 'Judges', detail: 'blind judges compare two versions, each read first once' },
  ],
}

if (args && args.dryRun) return { dryRun: true }
const HIDDEN = args.hidden
const TOOLS = args.tools
const L = args.locator || {}
const NOTE = 'Your context may contain instructions and memory notes of another project. They do not apply to this task; ignore them. Do not run git. Do not use the network.'

const SCEN = {
  type: 'object',
  properties: {
    scenarios: { type: 'array', items: { type: 'object', properties: {
      id: { type: 'string' },
      status: { type: 'string', enum: ['pass', 'fail', 'part', 'cannot check'] },
      detail: { type: 'string', description: 'empty for pass; otherwise what was expected and what the application did instead, or why it cannot be checked' },
    }, required: ['id', 'status', 'detail'] } },
    how_driven: { type: 'string' },
    tests_written: { type: 'integer' },
    notes: { type: 'string' },
  },
  required: ['scenarios', 'how_driven', 'tests_written', 'notes'],
}
const scenarioPrompt = s => `${NOTE}

You are an acceptance tester. A team built an application in ${s.root} from the requirements in ${s.root}/REQUIREMENTS.md. You check whether it does what the owner expects.

The expected behaviour is written as scenarios in ${HIDDEN}/ACCEPTANCE.md . Read that file (it is the only thing you read outside ${s.root}). Your part is the scenarios ${s.ids}.

For each scenario write tests in the new folder ${s.root}/acceptance/ (file names end in Test.kt, class names end in Test). Drive the application the way the hosting system would, through the one place the application offers for that (see ${s.root}/docs/LIBRARIES.md): send the events a user would cause and read what the screen state holds. If something cannot be reached through a screen, go one level below and say so in the detail.

Rules of the check:
- Change nothing under ${s.root}/src . You test the application as it is.
- Do not help the application. If it shows another text, another number or another order than the scenario says, the scenario fails, however reasonable the other answer is. If one part of a scenario holds and another does not, the status is "part" and the detail says which part fails.
- "cannot check" is only for a scenario that the application gives no way to exercise at all; say what is missing.
- Every test must end; clear the ViewModels you create.
- Run your tests with:  sh ${TOOLS}/run-extra.sh ${s.root} ${s.root}/acceptance
  A scenario passes only if its tests were run and passed. A test that asserts what the application happens to do, and not what the scenario says, is not a pass.

Return one entry for every scenario of your part.`

const PLACE = { type: 'object', properties: { file: { type: 'string' }, line: { type: 'integer' }, quote: { type: 'string' }, kind: { type: 'string' } }, required: ['file', 'line', 'quote', 'kind'] }
const LOC = {
  type: 'object',
  properties: {
    rules: { type: 'array', items: { type: 'object', properties: {
      id: { type: 'string' },
      found: { type: 'string', enum: ['yes', 'partly', 'no'] },
      file: { type: 'string' }, line: { type: 'integer' }, quote: { type: 'string' },
      kind: { type: 'string', enum: ['entity or value type', 'use case', 'other domain code', 'view model', 'other presentation code', 'data code', 'wiring', 'none'] },
      also_decided_in: { type: 'array', items: PLACE },
      note: { type: 'string' },
    }, required: ['id', 'found', 'file', 'line', 'quote', 'kind', 'also_decided_in', 'note'] } },
    units: { type: 'array', items: { type: 'object', properties: {
      name: { type: 'string' }, file: { type: 'string' }, has_rule: { type: 'boolean' }, one_call: { type: 'boolean' }, started_by: { type: 'string' },
    }, required: ['name', 'file', 'has_rule', 'one_call', 'started_by'] } },
    failures: { type: 'object', properties: {
      library_exception_first_caught: { type: 'array', items: { type: 'object', properties: { file: { type: 'string' }, line: { type: 'integer' }, quote: { type: 'string' }, turned_into: { type: 'string' } }, required: ['file', 'line', 'quote', 'turned_into'] } },
      general_message_produced_in: { type: 'array', items: { type: 'object', properties: { file: { type: 'string' }, line: { type: 'integer' }, quote: { type: 'string' } }, required: ['file', 'line', 'quote'] } },
      how_a_refusal_travels: { type: 'string' },
    }, required: ['library_exception_first_caught', 'general_message_produced_in', 'how_a_refusal_travels'] },
  },
  required: ['rules', 'units', 'failures'],
}
const locatorPrompt = x => `${NOTE}

You examine a codebase and change nothing in it. It is an application in ${x.root} ; its requirements are in ${x.root}/REQUIREMENTS.md and the libraries it uses are described in ${x.root}/docs/LIBRARIES.md . Read ${HIDDEN}/RULES.md : it lists the rules of the product. Outside ${x.root} that file is the only thing you read. Do not read the folder CodingStandards, the plan, the tracker or any REFACTORING file: judge only from the code.

Read all of ${x.root}/src/main . Then, for every rule, find the code that MAKES THE DECISION of the rule: the comparison, the computation, the branch. Not the code that only calls it, passes it on or shows its result. Give the file (relative to src/main/kotlin), the line number, and that line copied exactly. Say what kind of code holds it:
- "entity or value type": a type of the subject itself or a function that belongs to such a type;
- "use case": a unit that the project treats as a use case;
- "other domain code": other code of the domain layer (a function, a calculator, a policy, a service);
- "view model" or "other presentation code" (formatters, mappers to screen state, event handlers);
- "data code": repository implementations, storage, clients of libraries;
- "wiring": the code that builds the objects.
Then list every other place where the same decision is made a second time: a second comparison with the same limit, a second copy of the same computation, a second check of the same state. A call of the same function is not a second place.${L.sameCodeRules ? ` For ${L.sameCodeRules} the question is exactly this: is the screen's knowledge the same code as the rule, or a copy.` : ''}
If a rule is not implemented, say "no". If only a part is, say "partly" and what is missing.

Then list every unit that the project treats as a use case, and for each: does it check or decide something itself, or does its body only pass one call on.

Then the failures: where an exception of ${L.libraries || 'a library'} is first caught and what it is turned into; where the general failure message${L.generalMessage ? ` "${L.generalMessage}"` : ''} is produced; and what carries a refusal with its own message from the rule to the screen.

Be exact: every file, line and quote will be checked against the code by a script.`

const CHANGE = {
  type: 'object',
  properties: {
    files: { type: 'array', items: { type: 'object', properties: { path: { type: 'string' }, what: { type: 'string' } }, required: ['path', 'what'] } },
    build_passes: { type: 'boolean' },
    lint_passes: { type: 'boolean' },
    notes: { type: 'string', description: 'anything that made the change harder than it should be; empty if nothing' },
  },
  required: ['files', 'build_passes', 'lint_passes', 'notes'],
}
const changePrompt = c => `You are a maintainer of this project.
Your context may contain instructions and memory notes of another project. They do not apply here; ignore them. This project's root is ${c.root} . Every relative path in its documents is relative to that root. Work only inside the root (the build and lint scripts call tools that lie outside; that is fine). Do not use the network. Do not run git.

Read ${c.root}/CLAUDE.md first and follow it and the standards it lists: your change will be reviewed against them. The application is finished and ./build.sh passes.

The owner has changed one rule of the product:

${c.request}

Make this change: the code and its tests. ./build.sh and ./lint.sh must pass at the end. Change what this change needs and nothing else. Do not edit REQUIREMENTS.md or TASK_TRACKER.md; in IMPLEMENTATION_PLAN.md change only its Decisions Log, and only where the standards ask for a decision to be recorded.

Return the list of files you changed or added, with one sentence for each.`

const JUDGE = {
  type: 'object',
  properties: {
    prefer: { type: 'string', enum: ['A', 'B', 'equal'] },
    confidence: { type: 'integer', description: '50 to 100' },
    reasons: { type: 'array', items: { type: 'string' } },
    knowledge_only_in_A: { type: 'array', items: { type: 'object', properties: { what: { type: 'string' }, file: { type: 'string' }, line: { type: 'integer' } }, required: ['what', 'file', 'line'] } },
    knowledge_only_in_B: { type: 'array', items: { type: 'object', properties: { what: { type: 'string' }, file: { type: 'string' }, line: { type: 'integer' } }, required: ['what', 'file', 'line'] } },
    readability: { type: 'string', enum: ['A', 'B', 'equal'] },
    one_place: { type: 'string', enum: ['A', 'B', 'equal'] },
    tests: { type: 'string', enum: ['A', 'B', 'equal'] },
  },
  required: ['prefer', 'confidence', 'reasons', 'knowledge_only_in_A', 'knowledge_only_in_B', 'readability', 'one_place', 'tests'],
}
const judgePrompt = j => {
  const second = j.first === 'A' ? 'B' : 'A'
  return `${NOTE} Change no file.

Two versions of the same application are in ${j.dir}/A/src and ${j.dir}/B/src.${j.sameBehaviour ? ' They behave the same: both pass the same acceptance tests.' : ' They were built from the same requirements.'} Read nothing outside these two folders.

You are a senior engineer who will maintain one of them for the next two years. Read version ${j.first} first, then version ${second}: all of src/main of each, and enough of src/test of each to judge the tests.

Compare them as code to read and to change:
1. How quickly a new engineer understands what each part does and why: names, types, structure, and the tests as a description of the behaviour.
2. Whether each business rule is decided in exactly one place.
3. Whether something a maintainer needs to know is told in one version and not in the other: a reason, a unit, where a rule comes from, a warning, what a value stands for. Give concrete examples with file and line.
4. Whether the tests show the behaviour clearly.

Then say which version you would rather maintain, how sure you are (50 = a coin toss, 100 = certain), and the three strongest reasons.`
}

const jobs = [
  ...(args.scenarios || []).map(s => ({ kind: 'scenarios', x: s })),
  ...(args.locators || []).map(x => ({ kind: 'rules', x })),
  ...(args.changes || []).map(x => ({ kind: 'change', x })),
  ...(args.judges || []).map(x => ({ kind: 'judge', x })),
]
const results = await pipeline(jobs, async j => {
  if (j.kind === 'scenarios') return { kind: j.kind, name: j.x.name, result: await agent(scenarioPrompt(j.x), { label: `${j.x.name}: scenarios ${j.x.ids}`, phase: 'Scenarios', schema: SCEN }) }
  if (j.kind === 'rules') return { kind: j.kind, name: j.x.name, result: await agent(locatorPrompt(j.x), { label: `${j.x.name}: rules`, phase: 'Rules', schema: LOC, effort: 'high' }) }
  if (j.kind === 'change') return { kind: j.kind, name: j.x.name, result: await agent(changePrompt(j.x), { label: `${j.x.name}: change`, phase: 'Changes', schema: CHANGE }) }
  return { kind: j.kind, name: j.x.name, first: j.x.first, result: await agent(judgePrompt(j.x), { label: `${j.x.name}: judge, ${j.x.first} first`, phase: 'Judges', schema: JUDGE, effort: 'high' }) }
})

return { results }
