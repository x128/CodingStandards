export const meta = {
  name: 'self-improve-build',
  description: 'Independent teams build the same application, each with its own copy of the standards: one planner per project, then fresh engineers who each do one epic until the task tracker is empty and build and lint pass',
  phases: [
    { title: 'Plan', detail: 'one planner per project writes the implementation plan and the task tracker' },
    { title: 'Build', detail: 'fresh engineers, one epic per sitting' },
  ],
}

if (args && args.dryRun) return { dryRun: true }
const PROJECTS = args.projects
const MAX_SITTINGS = args.maxSittings || 14

const note = root => `Your context may contain instructions and memory notes of another project. They do not apply here; ignore them. This project's root is ${root} . Every relative path in its documents is relative to that root: "CodingStandards/..." means ${root}/CodingStandards/... . Work only inside the root: do not read or write any file outside it (the build and lint scripts call tools that lie outside; that is fine), do not look into neighbouring folders, do not use the network, do not run git.`

const PLAN = {
  type: 'object',
  properties: {
    epics: { type: 'array', items: { type: 'object', properties: { name: { type: 'string' }, tasks: { type: 'integer' } }, required: ['name', 'tasks'] } },
    tasks_total: { type: 'integer' },
    decisions: { type: 'array', items: { type: 'string' }, description: 'the decisions you recorded in the Decisions Log, one line each' },
    notes: { type: 'string' },
  },
  required: ['epics', 'tasks_total', 'decisions', 'notes'],
}
const SITTING = {
  type: 'object',
  properties: {
    epic: { type: 'string' },
    tasks_done: { type: 'array', items: { type: 'string' } },
    unfinished_tasks_left: { type: 'integer', description: 'how many tasks in the whole TASK_TRACKER.md are still not done after this sitting' },
    build_passes: { type: 'boolean', description: 'true only if ./build.sh printed BUILD OK at the end' },
    lint_passes: { type: 'boolean', description: 'true only if ./lint.sh printed LINT OK at the end' },
    notes: { type: 'string' },
  },
  required: ['epic', 'tasks_done', 'unfinished_tasks_left', 'build_passes', 'lint_passes', 'notes'],
}

const planPrompt = root => `You are the first engineer on a new project.
${note(root)}

Read ${root}/CLAUDE.md first; it says which documents bind you. Read REQUIREMENTS.md, docs/LIBRARIES.md and the standards that CLAUDE.md lists.

Your task is the planning step only, as CodingStandards/PLANNING_GUIDE.md describes it: write IMPLEMENTATION_PLAN.md and TASK_TRACKER.md in the project root, for the whole product. Write no code.

After you, other engineers will implement the tasks, one epic per sitting. None of them has seen your work, and nobody can be asked: each one has only the project folder. The plan and the tracker must be enough for them. They must agree with the standards, because the code will be reviewed against the standards.

Group the tasks into 6 to 9 epics of comparable size that can be done in the order in which they are listed. After each epic ./build.sh and ./lint.sh must pass.

When both files are written, return a short account of them.`

const sittingPrompt = (root, n) => `You are one of several engineers who work on this project one after another.
${note(root)}

Nobody can be asked. What the engineers before you did is in the project folder and nowhere else.
Read ${root}/CLAUDE.md first and follow it. Before you write code, read the standards it lists (the code will be reviewed against them), then IMPLEMENTATION_PLAN.md and TASK_TRACKER.md, then the code that is already there.

This is sitting ${n} on this project.
1. Run ./build.sh. If it fails because of the code (and not because there is no code yet), repair that first.
2. Take the first epic in TASK_TRACKER.md that has unfinished tasks. Do its unfinished tasks in order, one at a time: write the code and its tests, meet the exit criteria of the task, make ./build.sh and ./lint.sh pass, mark the task done in TASK_TRACKER.md.
3. Stop when that epic is finished. Do not start the next epic. If you cannot finish the epic, stop after the last task that you finished completely.

You may change code written before you where your task needs it. Keep the tracker truthful: a task is marked done only when it is done. If the plan turns out to be wrong, correct the plan and note the change in its Decisions Log.

When you stop, return the account that is asked of you.`

const results = await pipeline(PROJECTS, async (p) => {
  const plan = p.skipPlan ? null : await agent(planPrompt(p.root), { label: `${p.name}: plan`, phase: 'Plan', schema: PLAN, effort: 'high' })
  const sittings = []
  let left = plan && plan.tasks_total > 0 ? plan.tasks_total : 1
  let clean = false
  let failures = 0
  let n = p.firstSitting ? p.firstSitting - 1 : 0
  while ((left > 0 || !clean) && n < MAX_SITTINGS && failures < 2) {
    n += 1
    const r = await agent(sittingPrompt(p.root, n), { label: `${p.name}: sitting ${n}`, phase: 'Build', schema: SITTING })
    if (!r) { failures += 1; sittings.push({ sitting: n, died: true }); continue }
    failures = 0
    sittings.push({ sitting: n, ...r })
    left = r.unfinished_tasks_left
    clean = r.build_passes && r.lint_passes
    log(`${p.name}: sitting ${n} finished "${r.epic}", ${left} tasks left, build ${r.build_passes ? 'passes' : 'FAILS'}, lint ${r.lint_passes ? 'passes' : 'FAILS'}`)
  }
  if (left > 0 || !clean) log(`${p.name}: stopped after sitting ${n} with ${left} tasks left`)
  return { project: p.name, plan, sittings, finished: left === 0 && clean }
})

return { projects: results }
