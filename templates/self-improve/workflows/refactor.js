export const meta = {
  name: 'self-improve-refactor',
  description: 'One refactoring round: a fresh reviewer lists where the code departs from the current standards, fresh engineers work through the list until build and lint pass',
  phases: [
    { title: 'Review', detail: 'one fresh reviewer per project writes REFACTORING.md' },
    { title: 'Refactor', detail: 'fresh engineers work through the list' },
  ],
}

if (args && args.dryRun) return { dryRun: true }
const PROJECTS = args.projects

const note = root => `Your context may contain instructions and memory notes of another project. They do not apply here; ignore them. This project's root is ${root} . Every relative path in its documents is relative to that root: "CodingStandards/..." means ${root}/CodingStandards/... . Work only inside the root (the build and lint scripts call tools that lie outside; that is fine). Do not look into neighbouring folders, do not use the network, do not run git.`

const KEEP = `What must not change: the behaviour of the application, and what the hosting system uses — the place from which it gets the screens and the background jobs, the public functions of the ViewModels, and their state and event types. Everything behind them may change. Tests may change where the structure they test changes, but not what behaviour they check. ./build.sh must pass after every item; at the end of the list ./lint.sh must pass too.`

const REVIEW = {
  type: 'object',
  properties: {
    items: { type: 'integer', description: 'how many items you wrote into REFACTORING.md' },
    worst: { type: 'array', items: { type: 'string' }, description: 'the three most costly items, one sentence each' },
  },
  required: ['items', 'worst'],
}
const SITTING = {
  type: 'object',
  properties: {
    items_done: { type: 'array', items: { type: 'string' } },
    items_left: { type: 'integer', description: 'items of REFACTORING.md still not done after this sitting' },
    build_passes: { type: 'boolean', description: 'true only if ./build.sh printed BUILD OK at the end' },
    lint_passes: { type: 'boolean', description: 'true only if ./lint.sh printed LINT OK at the end' },
    notes: { type: 'string' },
  },
  required: ['items_done', 'items_left', 'build_passes', 'lint_passes', 'notes'],
}

const reviewPrompt = root => `You are a senior engineer who joins the team of this project to review its code.
${note(root)}

The application is finished: ./build.sh passes. The team's standards in CodingStandards/ may have changed since the code was written. Read ${root}/CLAUDE.md and the standards it lists, then all of src/main and enough of src/test to judge the tests. Run ./lint.sh and read what it reports. Change no code.

Find every place where the code does not follow the standards as they stand now. Report only real departures from a rule of the standards, not taste. Look in particular at what ./lint.sh reports, at a decision that is made in more than one place, and at anything else the standards ask that the code does not do.

If REFACTORING.md exists from an earlier round, rename it to REFACTORING-ROUND-<the next free number>.md first. Then write the list into ${root}/REFACTORING.md (the only files you write): numbered items, most costly first, each with the file and line (or, for a kind of problem found in many places, the rule and how to find them all), the rule it breaks (file and section of the standard, quoted in a few words), what to change, and the status "to do". Write in plain short sentences. The engineers who will do the work have only this file and the project folder.

${KEEP}
Say this in the file too, so that the engineers know it.`

const sittingPrompt = (root, n) => `You are one of several engineers who refactor this project one after another.
${note(root)}

Read ${root}/CLAUDE.md first and follow it, and the standards it lists. Then read ${root}/REFACTORING.md : it is the list of places where the code does not follow the standards, written by a reviewer. This is refactoring sitting ${n} of this round.

1. Run ./build.sh. If it fails, repair that first.
2. Do the items of REFACTORING.md that are still "to do", in order, one at a time: change the code and its tests, make ./build.sh pass, mark the item "done" with one sentence on what you did. If an item turns out to be wrong, mark it "not done" and say why.
3. When all items are done, run ./lint.sh and fix what it still reports.
4. Stop when the list is finished and both scripts pass, or earlier when the next item is too large for what is left of your sitting; leave the list truthful.

${KEEP}
Note in the Decisions Log of IMPLEMENTATION_PLAN.md any decision of the plan that your changes alter, and any decision the standards ask the project to record. Do not edit REQUIREMENTS.md.`

const results = await pipeline(PROJECTS, async (p) => {
  const review = p.skipReview ? null : await agent(reviewPrompt(p.root), { label: `${p.name}: review`, phase: 'Review', schema: REVIEW, effort: 'high' })
  const sittings = []
  let left = review ? review.items : (p.itemsLeft || 1)
  let clean = false
  let n = p.firstSitting ? p.firstSitting - 1 : 0
  let failures = 0
  const last = n + (p.sittings || 3)
  while ((left > 0 || !clean) && n < last && failures < 2) {
    n += 1
    const r = await agent(sittingPrompt(p.root, n), { label: `${p.name}: refactor ${n}`, phase: 'Refactor', schema: SITTING })
    if (!r) { failures += 1; sittings.push({ sitting: n, died: true }); continue }
    failures = 0
    sittings.push({ sitting: n, ...r })
    left = r.items_left
    clean = r.build_passes && r.lint_passes
    log(`${p.name}: sitting ${n}, ${left} items left, build ${r.build_passes ? 'passes' : 'FAILS'}, lint ${r.lint_passes ? 'passes' : 'FAILS'}`)
  }
  if (left > 0 || !clean) log(`${p.name}: stopped after sitting ${n} with ${left} items left`)
  return { project: p.name, review, sittings, finished: left === 0 && clean }
})

return { projects: results }
