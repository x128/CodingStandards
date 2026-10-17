export const meta = {
  name: 'self-improve-loss',
  description: 'For every removed comment or line, find where its information lives now; a skeptic re-checks every loss and every fifth find; optional blind judges compare before and after',
  phases: [
    { title: 'Find', detail: 'one checker per part of the removed list' },
    { title: 'Verify', detail: 'a skeptic re-checks every loss and every fifth find' },
    { title: 'Judge', detail: 'two blind judges per project, before against after' },
  ],
}

if (args && args.dryRun) return { dryRun: true }
const IGNORE = 'Your context may contain instructions and memory notes of another project. They do not apply to this task; ignore them. Do not run git. Do not use the network. Change no file.'
const PLACE = { type: 'object', properties: { file: { type: 'string', description: 'path relative to the root of the new version' }, line: { type: 'integer' }, quote: { type: 'string', description: 'that line, copied exactly' } }, required: ['file', 'line', 'quote'] }
const FIND = {
  type: 'object',
  properties: {
    items: { type: 'array', items: { type: 'object', properties: {
      id: { type: 'string' },
      information: { type: 'string', description: 'what a reader learned from it that the line under it did not already say; or "only repeated the code"' },
      verdict: { type: 'string', enum: ['repeated the code', 'in the code', 'in a test', 'in a document', 'no longer needed', 'partly', 'lost'] },
      where: { type: 'array', items: PLACE },
      missing: { type: 'string' },
    }, required: ['id', 'information', 'verdict', 'where', 'missing'] } },
  },
  required: ['items'],
}
const VERIFY = {
  type: 'object',
  properties: {
    items: { type: 'array', items: { type: 'object', properties: {
      id: { type: 'string' },
      claim: { type: 'string', enum: ['loss', 'find'] },
      verdict: { type: 'string', enum: ['information is in the new version', 'information is partly in the new version', 'information is not in the new version', 'information is no longer needed'] },
      where: { type: 'array', items: PLACE },
      missing: { type: 'string' },
      reason: { type: 'string' },
    }, required: ['id', 'claim', 'verdict', 'where', 'missing', 'reason'] } },
  },
  required: ['items'],
}
const findPrompt = p => `${IGNORE}

A change removed comments or lines of text from ${p.what || 'a project'}. Its authors work by this rule: what a removed comment or line said first moves into a name, a type, a constant, a check, a test, or a document of the project (${p.documents || 'its plan, its task tracker, its refactoring list'}). You check whether that happened.

${p.file} lists what was removed. Each entry has an id, where it was, its text, and the line under it in the old version.
- The old version: ${p.before} (look there for the context).
- The new version: ${p.after}
Read nothing else.

For each entry:
1. Say in one plain sentence what a reader learned from it that the line under it did not already say: a unit, a reason, a limit, where a rule comes from, a warning, what a value stands for, what a function promises. If it only repeated the code, say "only repeated the code".
2. Find where that information is in the new version, and give the verdict:
- "repeated the code": it said nothing the code did not already say.
- "in the code": a name, a type, a constant or a check in the new version says it.
- "in a test": the name of a test, or what it asserts, says it.
- "in a document": a document of the new version, or the commit message or the report written for it, says it.
- "no longer needed": what it described is no longer there, and nothing in the new version needs the information.
- "partly": a part is in one of the places above and the rest is nowhere; say which part is missing.
- "lost": the information is nowhere in the new version.
Be strict. Say "in the code" only when a reader of the new version learns the same thing from it, not when it can merely be worked out with effort. For each verdict other than "repeated the code", "no longer needed" and "lost", give the place: the file relative to ${p.after}, the line number, and that line copied exactly. Every place will be checked by a script.

Return every id of the list, in order.`
const verifyPrompt = (p, items) => `${IGNORE}

A change removed comments or lines of text. A checker looked for the information of each removed entry in the new version. Your job is to check some of the checker's answers, and to prove them wrong where you can.
- The old version: ${p.before}
- The new version: ${p.after}
- The removed entries: ${p.file}
Read nothing else.

The answers to check (JSON):
${JSON.stringify(items, null, 1)}

For a "loss" claim: search the new version hard for the information, in names, types, constants, checks, test names, assertions and documents. Also ask whether the information is still needed at all: if what it described is gone, it may not be.
For a "find" claim: open the place and ask whether a reader of the new version really learns the same thing from it. If not, say what is missing.

Give your own verdict for each id, the places (file relative to ${p.after}, line, the line copied exactly), what is missing if anything, and a one-sentence reason.`

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
  return `${IGNORE}

Two versions of the same application are in ${j.dir}/A/src and ${j.dir}/B/src. They behave the same: both pass the same acceptance tests. Read nothing outside these two folders.

You are a senior engineer who will maintain one of them for the next two years. Read version ${j.first} first, then version ${second}: all of src/main of each, and enough of src/test of each to judge the tests.

Compare them as code to read and to change:
1. How quickly a new engineer understands what each part does and why: names, types, structure, and the tests as a description of the behaviour.
2. Whether each business rule is decided in exactly one place.
3. Whether something a maintainer needs to know is told in one version and not in the other: a reason, a unit, where a rule comes from, a warning, what a value stands for. Give concrete examples with file and line.
4. Whether the tests show the behaviour clearly.

Then say which version you would rather maintain, how sure you are (50 = a coin toss, 100 = certain), and the three strongest reasons.`
}

const lossChain = async p => {
  const found = await agent(findPrompt(p), { label: `${p.project} ${p.file.split('/').pop()}: find`, phase: 'Find', schema: FIND })
  if (!found) return { project: p.project, part: p.file, found: null, verified: null }
  const doubtful = found.items.filter(i => i.verdict === 'lost' || i.verdict === 'partly').map(i => ({ ...i, claim: 'loss' }))
  const kept = found.items.filter(i => !['lost', 'partly'].includes(i.verdict))
  const sampled = kept.filter((_, k) => k % 5 === 0).map(i => ({ ...i, claim: 'find' }))
  const toCheck = doubtful.concat(sampled)
  if (!toCheck.length) return { project: p.project, part: p.file, found, verified: { items: [] } }
  const verified = await agent(verifyPrompt(p, toCheck), { label: `${p.project} ${p.file.split('/').pop()}: verify ${doubtful.length} losses, ${sampled.length} finds`, phase: 'Verify', schema: VERIFY, effort: 'high' })
  return { project: p.project, part: p.file, found, verified }
}

const jobs = [...(args.parts || []).map(x => ({ kind: 'loss', x })), ...(args.judges || []).map(x => ({ kind: 'judge', x }))]
const results = await pipeline(jobs, async j => {
  if (j.kind === 'loss') return { kind: 'loss', ...(await lossChain(j.x)) }
  return { kind: 'judge', judge: j.x.judge, project: j.x.project, first: j.x.first, result: await agent(judgePrompt(j.x), { label: `${j.x.judge}: judge, ${j.x.first} first`, phase: 'Judge', schema: JUDGE, effort: 'high' }) }
})

return { loss: results.filter(r => r && r.kind === 'loss'), judges: results.filter(r => r && r.kind === 'judge') }
