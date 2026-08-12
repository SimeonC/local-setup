export const meta = {
  name: 'delegate',
  description: 'Policy-enforcing delegation: scoped teammates, one task each, capped concurrency, no worktrees for coding',
  whenToUse:
    'Any multi-step or broad task that needs more than one agent. Replaces ad-hoc Agent fan-out — the policy that used to live in CLAUDE.md prose is enforced here in code.',
  phases: [
    { title: 'Explore', detail: 'read-only sweeps, one scoped question each' },
    { title: 'Implement', detail: 'scoped edits, one deliverable each' },
    { title: 'Review', detail: 'cross-check the combined result' },
  ],
}

// ---------------------------------------------------------------------------
// Policy. Encoded here so it cannot drift the way prose instructions do.
//
//  - agentType is a ROLE. Never a model id. `model` is never passed to agent(),
//    so each agent's ~/.claude/agents/*.md frontmatter is the only model source.
//  - One scoped task per agent. Agents are never reused for a second task.
//  - Concurrency capped at 3.
//  - isolation:'worktree' is NEVER set for implementation work. Exploration may
//    opt in per-item via `isolate: true`; those worktrees are auto-removed when
//    unchanged, and the SessionEnd cleanup-agent-worktrees.sh hook sweeps the
//    rest.
// ---------------------------------------------------------------------------

const MAX_CONCURRENT = 3

const ROLES = {
  explore: 'custom-explorer',
  implement: 'custom-worker',
  hard: 'custom-specialist',
  plan: 'custom-planner',
  review: 'custom-reviewer',
  commit: 'custom-committer',
}

const RETURN_CONTRACT = `
Return ONLY: file paths, \`file:line\` references, and 1-2 sentence conclusions
per finding. Never dump file contents, diffs, or raw search output.
Stay inside the stated scope — note anything outside it and keep going.`

const NO_WORKTREE = `
Do NOT create a git worktree, branch, or clone for this work. Edit the working
tree you were given. If you believe isolation is required, stop and say so
instead of creating one.`

const FINDINGS = {
  type: 'object',
  required: ['summary', 'refs'],
  properties: {
    summary: { type: 'string', description: '1-2 sentences' },
    refs: {
      type: 'array',
      items: {
        type: 'object',
        required: ['ref', 'note'],
        properties: {
          ref: { type: 'string', description: 'path or path:line' },
          note: { type: 'string' },
        },
      },
    },
    outOfScope: {
      type: 'array',
      items: { type: 'string' },
      description: 'Things noticed but deliberately not done',
    },
  },
}

/** Run thunks at most MAX_CONCURRENT at a time. parallel() alone has no cap we control. */
async function batched(thunks) {
  const out = []
  for (let i = 0; i < thunks.length; i += MAX_CONCURRENT) {
    out.push(...(await parallel(thunks.slice(i, i + MAX_CONCURRENT))))
  }
  return out.filter(Boolean)
}

function normalise(items, fallbackRole) {
  if (!items) return []
  const list = Array.isArray(items) ? items : [items]
  return list.map((it, i) =>
    typeof it === 'string'
      ? { name: `${fallbackRole}-${i + 1}`, role: fallbackRole, prompt: it }
      : { name: it.name || `${fallbackRole}-${i + 1}`, role: it.role || fallbackRole, ...it },
  )
}

function agentTypeFor(role) {
  const t = ROLES[role]
  if (!t) throw new Error(`unknown role "${role}" — use one of: ${Object.keys(ROLES).join(', ')}`)
  return t
}

// ---------------------------------------------------------------------------

const input = args || {}
const task = input.task || 'unspecified task'
const explore = normalise(input.explore, 'explore')
const implement = normalise(input.implement, 'implement')
const review = input.review === false ? null : input.review || null

log(`delegate: ${task}`)

// ===== Explore =====
let findings = []
if (explore.length) {
  phase('Explore')
  log(`${explore.length} exploration stream(s), max ${MAX_CONCURRENT} at a time`)
  findings = await batched(
    explore.map((s) => () =>
      agent(`${s.prompt}\n${RETURN_CONTRACT}`, {
        label: s.name,
        phase: 'Explore',
        agentType: agentTypeFor(s.role),
        schema: FINDINGS,
        // Exploration may isolate; implementation may not. Opt-in only.
        ...(s.isolate ? { isolation: 'worktree' } : {}),
      }),
    ),
  )
}

// ===== Implement =====
// Context from exploration is passed forward as distilled refs, never raw output.
const context = findings.length
  ? `\n\n## Prior findings\n${findings
      .map((f) => `- ${f.summary}\n${(f.refs || []).map((r) => `  - ${r.ref} — ${r.note}`).join('\n')}`)
      .join('\n')}`
  : ''

let built = []
if (implement.length) {
  phase('Implement')
  log(`${implement.length} implementation stream(s)`)
  built = await batched(
    implement.map((s) => () =>
      agent(
        `${s.prompt}${context}\n${NO_WORKTREE}\n${RETURN_CONTRACT}\n` +
          `Verify narrowly: run only the tests/typecheck covering files you touched. ` +
          `Do NOT run the full suite or repo-wide lint.`,
        {
          label: s.name,
          phase: 'Implement',
          agentType: agentTypeFor(s.role),
          schema: FINDINGS,
          // No isolation. Implementation shares the working tree by policy.
        },
      ),
    ),
  )
}

// ===== Review =====
let verdict = null
if (review && built.length) {
  phase('Review')
  const changed = built.flatMap((b) => (b.refs || []).map((r) => r.ref))
  verdict = await agent(
    `Review the completed work against its intent.\n\n## Intent\n${task}\n\n` +
      `## What was changed\n${changed.map((c) => `- ${c}`).join('\n')}\n\n` +
      `${typeof review === 'string' ? review : 'Cross-check the diff against the intent. Flag anything missed, incomplete, or out of scope.'}` +
      `\n${NO_WORKTREE}\n${RETURN_CONTRACT}`,
    { label: 'review', phase: 'Review', agentType: ROLES.review, schema: FINDINGS },
  )
}

const outOfScope = [...findings, ...built, verdict]
  .filter(Boolean)
  .flatMap((r) => r.outOfScope || [])

if (outOfScope.length) log(`${outOfScope.length} item(s) noted out of scope — not actioned`)

return { task, findings, built, verdict, outOfScope }
